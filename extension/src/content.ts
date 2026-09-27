import {coverUrl,openCollection,readCatalog,turnPage} from './catalog';
import {readRelated} from './related';
import {bounded,RemoteError} from './types';
import {autoNextControl,danmakuControl,danmakuOn,partInfo,videoLocation} from './player-dom';
import {installFullscreenEscape,isPlayerFullscreen,setPlayerFullscreen} from './fullscreen';
import {readQuality,switchQuality} from './quality';

let managed=false,playbackId:string|undefined,endedSent=false,lastError='';
let previousAutoNext:boolean|undefined;
let binding:Record<string,unknown>|undefined;
let qualitySwitching=false;
let disposed=false,reportTimer:ReturnType<typeof setInterval>|undefined;
let removeFullscreenListeners=()=>{};
const pageListeners=new AbortController();
function dispose(){
  if(disposed)return;
  disposed=true;
  clearInterval(reportTimer);pageListeners.abort();removeFullscreenListeners();
  try{chrome.runtime.onMessage.removeListener(onMessage)}catch{/* The old runtime may already be inaccessible. */}
  manage(false);
}
function runtimeActive():boolean{
  if(disposed)return false;
  try{if(chrome.runtime.id)return true}catch{/* Reading the runtime can itself throw after reload. */}
  dispose();return false;
}
function runtimeError(error:unknown){
  if(/extension context invalidated/i.test(String(error)))dispose();
  else runtimeActive(); // A temporarily unavailable receiver does not invalidate this script.
}
function requireRuntime(){if(!runtimeActive())throw new RemoteError('extension_reloaded','扩展已重新加载，请刷新这个 B 站页面')}
function video():HTMLVideoElement|null{return document.querySelector<HTMLVideoElement>('.bpx-player-video-wrap video,video')}
function emit(event:string,data?:unknown){
  if(!runtimeActive())return;
  // sendMessage may throw before it returns a Promise when an extension is reloaded.
  try{void chrome.runtime.sendMessage(data===undefined?{event}:{event,data}).catch(runtimeError)}catch(error){runtimeError(error)}
}
function snapshot(){const v=video();return {bvid:location.pathname.match(/BV[\w]+/)?.[0]??'',title:document.querySelector('h1')?.textContent?.trim()??document.title.replace(/_哔哩哔哩.*$/,''),url:location.href,cover:coverUrl(document.querySelector('meta[property="og:image"]')?.getAttribute('content')),currentTime:Number.isFinite(v?.currentTime)?v!.currentTime:0,duration:Number.isFinite(v?.duration)?v!.duration:0,paused:v?.paused??true,ended:v?.ended??false,...partInfo(),volume:v?.volume??1,muted:v?.muted??false,rate:v?.playbackRate??1,danmaku:danmakuOn(),fullscreen:isPlayerFullscreen(),quality:readQuality(),playbackId}}
function manage(value:boolean,original?:unknown){
  if(value&&!runtimeActive())return;
  const control=autoNextControl();
  if(value&&typeof original==='boolean'&&previousAutoNext===undefined)previousAutoNext=original;
  if(value&&control instanceof HTMLInputElement){
    if(previousAutoNext===undefined){previousAutoNext=control.checked;emit('player.autoNextCaptured',{value:previousAutoNext})}
    if(disposed)return;
    if(control.checked)control.click();
  }
  if(!value&&managed&&control instanceof HTMLInputElement&&previousAutoNext!==undefined&&control.checked!==previousAutoNext)control.click();
  managed=value;if(!value){playbackId=undefined;previousAutoNext=undefined;binding=undefined}
}
function matchesBinding(params:Record<string,unknown>){const current=videoLocation();return params.bvid===current.bvid&&(params.part??1)===current.part}
function releaseManualNavigation(){if(binding&&!matchesBinding(binding))manage(false)}
// Capture before site listeners so exactly one queue controller handles media end.
document.addEventListener('ended',event=>{
  if(!runtimeActive())return;
  releaseManualNavigation();
  if(!managed||event.target!==video())return;
  event.stopImmediatePropagation();if(endedSent)return;endedSent=true;
  const state=snapshot();emit(state.part<state.partCount?'player.partEnded':'player.ended',state);
},{capture:true,signal:pageListeners.signal});
function visiblePlayerError():RemoteError|undefined {
  const error=document.querySelector('.error-panel,.bpx-player-error-message,.error-container')?.textContent?.trim()??'';
  if(!error)return undefined;
  return new RemoteError(/不存在|已删除|失效|不见了|被删除/.test(error)?'video_unavailable':/登录|验证/.test(error)?'verification_required':'player_error',error.slice(0,200));
}
function requireBinding(params:Record<string,unknown>){
  requireRuntime();
  if(!binding||binding.playbackId!==params.playbackId||!matchesBinding(params)){
    releaseManualNavigation();throw new RemoteError('target_changed','电脑上已切换视频或停止遥控队列');
  }
}
async function waitVideo(params:Record<string,unknown>):Promise<HTMLVideoElement>{
  for(let i=0;i<100;i++){
    requireBinding(params);
    const error=visiblePlayerError();if(error)throw error;
    const v=video();if(v&&v.readyState>=1)return v;
    await new Promise(resolve=>setTimeout(resolve,200));
  }
  throw new RemoteError('player_not_ready','播放器尚未就绪，请检查电脑网页');
}
function attach(params:Record<string,unknown>){
  requireRuntime();
  if(!matchesBinding(params))throw new RemoteError('target_changed','电脑上已切换视频');
  manage(Boolean(params.managed),params.originalAutoNext);requireRuntime();binding=params;playbackId=String(params.playbackId??'');endedSent=false;lastError='';return snapshot();
}
async function bind(params:Record<string,unknown>){
  attach(params);const v=await waitVideo(params);requireBinding(params);manage(managed,params.originalAutoNext);requireBinding(params);
  if(typeof params.time==='number')v.currentTime=Math.min(Math.max(0,params.time),v.duration||params.time);
  try{await v.play()}catch{throw new RemoteError('autoplay_blocked','浏览器阻止了自动播放，请在电脑视频区域点击一次播放，再从手机继续')}
  emit('player.changed',snapshot());return snapshot();
}
async function command(params:Record<string,unknown>){
  requireRuntime();
  const action=String(params.action);if(action==='fullscreen'){await setPlayerFullscreen(Boolean(params.value),runtimeActive);emit('player.changed',snapshot());return snapshot()}
  const v=video();if(!v)throw new RemoteError('no_player','请先选择一个视频');
  switch(action){
    case 'quality':{
      if(qualitySwitching)throw new RemoteError('quality_busy','清晰度正在切换，请稍候');
      if(typeof params.bvid!=='string'||!/^BV[0-9A-Za-z]+$/.test(params.bvid)||typeof params.part!=='number'||!Number.isInteger(params.part)||params.part<1)throw new RemoteError('invalid_request','缺少有效的视频信息，请重新选择清晰度');
      qualitySwitching=true;
      try{await switchQuality(params.value,()=>runtimeActive()&&params.bvid===location.pathname.match(/BV[\w]+/)?.[0]&&params.part===partInfo().part)}finally{qualitySwitching=false}
      break;
    }
    case 'play':try{await v.play()}catch{throw new RemoteError('autoplay_blocked','请先在电脑视频区域点击一次播放')}break;
    case 'pause':v.pause();break;
    case 'seek':v.currentTime=Math.min(bounded(params.value,0,864000),Number.isFinite(v.duration)?v.duration:864000);endedSent=false;break;
    case 'seekBy':v.currentTime=Math.max(0,Math.min(v.currentTime+bounded(params.value,-3600,3600),Number.isFinite(v.duration)?v.duration:864000));endedSent=false;break;
    case 'volume':v.volume=bounded(params.value,0,1);break;
    case 'mute':v.muted=Boolean(params.value);break;
    case 'rate':v.playbackRate=bounded(params.value,.5,2);break;
    case 'danmaku':{const control=danmakuControl();if(!control)throw new RemoteError('unsupported','找不到弹幕开关，请更新扩展');if(danmakuOn()!==Boolean(params.value))control.click();break}
    default:throw new RemoteError('unknown_method','不支持的播放操作');
  }
  emit('player.changed',snapshot());return snapshot();
}
function onMessage(message:any,_sender:chrome.runtime.MessageSender,respond:(response:unknown)=>void){
  if(!runtimeActive())return false;
  const reply=(response:unknown)=>{
    if(!runtimeActive())return;
    try{respond(response)}catch(error){runtimeError(error)}
  };
  if(message.method==='player.related'){
    void readRelated(String(message.params?.bvid??'')).then(result=>reply({ok:true,result}),error=>reply({ok:false,error:{code:error.code??'extension_error',message:error.message}}));return true;
  }
  void (async()=>{switch(message.method){case 'catalog.read':return readCatalog(message.params.kind);case 'catalog.page':await turnPage(message.params.page,message.params.kind);return readCatalog(message.params.kind);case 'catalog.openCollection':return openCollection(message.params.title,message.params.index);case 'player.bind':return bind(message.params);case 'player.attach':return attach(message.params);case 'player.manage':manage(Boolean(message.params.enabled));return snapshot();case 'player.command':return command(message.params);case 'player.state':return snapshot();default:throw new RemoteError('unknown_method','未知扩展操作')}})().then(result=>reply({ok:true,result}),error=>reply({ok:false,error:{code:error.code??'extension_error',message:error.message}}));
  return true;
}
function report(){
  if(!runtimeActive())return;
  releaseManualNavigation();
  if(location.hostname!=='www.bilibili.com'||!location.pathname.startsWith('/video/'))return;
  const v=video();if(v){if(managed)manage(true);emit('player.changed',snapshot());if(!v.ended)endedSent=false}
  const error=document.querySelector('.error-panel,.bpx-player-error-message,.error-container')?.textContent?.trim()??'';
  if(error&&error!==lastError){lastError=error;const unavailable=/不存在|已删除|失效|不见了|被删除/.test(error);emit('player.error',{...snapshot(),errorCode:unavailable?'video_unavailable':/登录|验证/.test(error)?'verification_required':'player_error',errorMessage:error.slice(0,200)})}
}
if(runtimeActive()){
  try{chrome.runtime.onMessage.addListener(onMessage)}catch{dispose()}
}
if(!disposed){
  reportTimer=setInterval(report,1000);
  removeFullscreenListeners=installFullscreenEscape(report,runtimeActive);
  window.addEventListener('pagehide',()=>manage(false),{signal:pageListeners.signal});
  for(const event of ['play','pause','seeked','volumechange','ratechange','loadedmetadata'])document.addEventListener(event,()=>{if(video())report()},{capture:true,signal:pageListeners.signal});
  emit('content.ready');
}

import {readCatalog,turnPage} from './catalog';
import {bounded,RemoteError} from './types';

let managed=false,playbackId:string|undefined,webFullscreen=false,endedSent=false,lastError='';
let previousAutoplay:boolean|undefined;
function video():HTMLVideoElement|null{return document.querySelector<HTMLVideoElement>('.bpx-player-video-wrap video,video')}
function emit(event:string,data:unknown){chrome.runtime.sendMessage({event,data}).catch(()=>{})}
function initialPartCount():number {
  for(const script of document.scripts){
    const match=script.textContent?.match(/window\.__INITIAL_STATE__\s*=\s*(\{.*?\});/s);
    if(match)try{const value=JSON.parse(match[1]);const data=value.videoData;if(data?.bvid===location.pathname.match(/BV[\w]+/)?.[0])return Math.max(1,data.pages?.length??data.videos??1)}catch{}
  }
  const bvid=location.pathname.match(/BV[\w]+/)?.[0];
  return Math.max(1,...[...document.querySelectorAll<HTMLAnchorElement>('a[href*="p="]')].filter(a=>a.href.includes(bvid??'__missing__')).map(a=>Number(new URL(a.href).searchParams.get('p'))||1));
}
function danmakuControl():HTMLElement|null{return document.querySelector('.bpx-player-dm-switch input,.bpx-player-dm-switch,.bilibili-player-video-danmaku-switch input')}
function danmakuOn():boolean{const control=danmakuControl();return control instanceof HTMLInputElement?control.checked:control?.getAttribute('aria-checked')!=='false'&&!control?.classList.contains('bpx-state-disabled')}
function snapshot(){const v=video();return {bvid:location.pathname.match(/BV[\w]+/)?.[0]??'',title:document.querySelector('h1')?.textContent?.trim()??document.title.replace(/_哔哩哔哩.*$/,''),url:location.href,currentTime:Number.isFinite(v?.currentTime)?v!.currentTime:0,duration:Number.isFinite(v?.duration)?v!.duration:0,paused:v?.paused??true,ended:v?.ended??false,part:Number(new URL(location.href).searchParams.get('p'))||1,partCount:initialPartCount(),volume:v?.volume??1,muted:v?.muted??false,rate:v?.playbackRate??1,danmaku:danmakuOn(),fullscreen:webFullscreen,playbackId}}
function autoplayControl():HTMLElement|null{return document.querySelector('.next-play input,.auto-play input,.video-pod__auto-play input,.bpx-player-ctrl-setting-autoplay input,.bpx-player-ctrl-setting-autoplay .bui-switch-input')}
function manage(value:boolean){
  const control=autoplayControl();
  if(value&&!managed&&control instanceof HTMLInputElement){previousAutoplay=control.checked;if(control.checked)control.click()}
  if(!value&&managed&&control instanceof HTMLInputElement&&previousAutoplay!==undefined&&control.checked!==previousAutoplay)control.click();
  managed=value;if(!value){playbackId=undefined;previousAutoplay=undefined}
}
// Capture before site listeners so exactly one queue controller handles media end.
document.addEventListener('ended',event=>{
  if(!managed||event.target!==video())return;
  event.stopImmediatePropagation();if(endedSent)return;endedSent=true;
  const state=snapshot();emit(state.part<state.partCount?'player.partEnded':'player.ended',state);
},true);
async function waitVideo():Promise<HTMLVideoElement>{for(let i=0;i<100;i++){const v=video();if(v&&v.readyState>=1)return v;await new Promise(resolve=>setTimeout(resolve,200))}throw new RemoteError('player_not_ready','播放器尚未就绪，请检查电脑网页')}
function attach(params:Record<string,unknown>){playbackId=String(params.playbackId??'');manage(Boolean(params.managed));endedSent=false;lastError='';return snapshot()}
async function bind(params:Record<string,unknown>){attach(params);const v=await waitVideo();if(typeof params.time==='number')v.currentTime=Math.min(Math.max(0,params.time),v.duration||params.time);try{await v.play()}catch{throw new RemoteError('autoplay_blocked','浏览器阻止了自动播放，请在电脑视频区域点击一次播放，再从手机继续')}emit('player.changed',snapshot());return snapshot()}
function fillPlayer(value:boolean){
  const control=document.querySelector<HTMLElement>('.bpx-player-ctrl-web,.bilibili-player-video-web-fullscreen');
  if(webFullscreen!==value&&control)control.click();
  if(!control){let style=document.getElementById('biliremote-fullscreen');if(value&&!style){style=document.createElement('style');style.id='biliremote-fullscreen';style.textContent='.bpx-player-container{position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;z-index:2147483600!important;background:#000!important}';document.head.append(style)}else if(!value)style?.remove()}
  webFullscreen=value;
}
async function command(params:Record<string,unknown>){
  const action=String(params.action);if(action==='fullscreen'){fillPlayer(Boolean(params.value));return snapshot()}
  const v=video();if(!v)throw new RemoteError('no_player','请先选择一个视频');
  switch(action){
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
chrome.runtime.onMessage.addListener((message,_sender,respond)=>{
  (async()=>{switch(message.method){case 'catalog.read':return readCatalog(message.params.kind);case 'catalog.page':await turnPage(message.params.page,message.params.kind);return readCatalog(message.params.kind);case 'player.bind':return bind(message.params);case 'player.attach':return attach(message.params);case 'player.manage':manage(Boolean(message.params.enabled));return snapshot();case 'player.command':return command(message.params);case 'player.state':return snapshot();default:throw new RemoteError('unknown_method','未知扩展操作')}})().then(result=>respond({ok:true,result}),error=>respond({ok:false,error:{code:error.code??'extension_error',message:error.message}}));
  return true;
});
function report(){
  if(location.hostname!=='www.bilibili.com'||!location.pathname.startsWith('/video/'))return;
  const v=video();if(v){emit('player.changed',snapshot());if(!v.ended)endedSent=false}
  const error=document.querySelector('.error-panel,.bpx-player-error-message,.error-container')?.textContent?.trim()??'';
  if(error&&error!==lastError){lastError=error;const unavailable=/不存在|已删除|失效|不见了|被删除/.test(error);emit('player.error',{...snapshot(),errorCode:unavailable?'video_unavailable':/登录|验证/.test(error)?'verification_required':'player_error',errorMessage:error.slice(0,200)})}
}
setInterval(report,1000);
for(const event of ['play','pause','seeked','volumechange','ratechange','loadedmetadata'])document.addEventListener(event,()=>{if(video())report()},true);
chrome.runtime.sendMessage({event:'content.ready'}).catch(()=>{});

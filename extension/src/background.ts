import {bounded,numericId,PageResult,RemoteError,Request,urlAllowed} from './types';
import {community,relatedCovers} from './community';

const HOST='com.biliremote.bridge';
let port:chrome.runtime.Port|undefined,targetId:number|undefined,catalogId:number|undefined,managed=false;
let currentBinding:Record<string,unknown>|undefined;
let originalAutoplay:boolean|undefined;
let catalogSerial:Promise<unknown>=Promise.resolve();
const collectionRoutes=new Map<string,string>();
const windowStates=new Map<number,NonNullable<chrome.windows.UpdateInfo['state']>>();
const initialized=chrome.storage.session.get(['targetId','catalogId','managed','binding','originalAutoplay']).then(saved=>{targetId=typeof saved.targetId==='number'?saved.targetId:undefined;catalogId=typeof saved.catalogId==='number'?saved.catalogId:undefined;managed=saved.managed===true;currentBinding=saved.binding&&typeof saved.binding==='object'?saved.binding as Record<string,unknown>:undefined;originalAutoplay=typeof saved.originalAutoplay==='boolean'?saved.originalAutoplay:undefined});
async function remember(){await chrome.storage.session.set({targetId:targetId??null,catalogId:catalogId??null,managed,binding:currentBinding??null,originalAutoplay:originalAutoplay??null})}
function bindingParams(){return {...currentBinding,originalAutoplay}}
function send(event:string,data:unknown){try{port?.postMessage({v:1,event,data})}catch{}}
async function releaseDisconnectedSession(){
  await initialized;
  managed=false;currentBinding=undefined;
  if(targetId&&await tabExists(targetId))await content(targetId,'player.manage',{enabled:false});
  originalAutoplay=undefined;await remember();
}
function connect(){
  if(port)return;
  try{port=chrome.runtime.connectNative(HOST);port.onMessage.addListener((req:Request)=>{handle(req).then(result=>port?.postMessage({v:1,id:req.id,ok:true,result}),error=>{try{port?.postMessage({v:1,id:req.id,ok:false,error:{code:error.code??'extension_error',message:error.message??'扩展操作失败'}})}catch{}})});port.onDisconnect.addListener(()=>{port=undefined;chrome.action.setBadgeText({text:'!'});chrome.action.setBadgeBackgroundColor({color:'#D55D68'});void chrome.runtime.lastError;void releaseDisconnectedSession().catch(()=>{});});port.postMessage({v:1,event:'bridge.ready',data:{version:chrome.runtime.getManifest().version}});chrome.action.setBadgeText({text:''})}catch{port=undefined}
}
async function tabExists(id:number|undefined){if(id===undefined||id===null)return false;try{const t=await chrome.tabs.get(id);return !!t.url&&urlAllowed(t.url)}catch{return false}}
async function content(id:number,method:string,params:unknown={}):Promise<any>{
  let reply:any;
  for(let i=0;i<60;i++){try{reply=await chrome.tabs.sendMessage(id,{method,params});if(reply)break}catch{}await new Promise(resolve=>setTimeout(resolve,200))}
  if(!reply)throw new RemoteError('extension_not_ready','网页扩展尚未就绪，请刷新目标哔哩哔哩页面');
  if(!reply.ok)throw new RemoteError(reply.error.code,reply.error.message);return reply.result;
}
async function navigation(id:number,url:string){
  await chrome.tabs.update(id,{url});
  for(let i=0;i<100;i++){await new Promise(resolve=>setTimeout(resolve,150));const tab=await chrome.tabs.get(id);if(tab.status==='complete'&&tab.url){const actual=new URL(tab.url),expected=new URL(url);if(actual.host===expected.host&&actual.pathname.replace(/\/$/,'')===expected.pathname.replace(/\/$/,''))return}}
  throw new RemoteError('navigation_timeout','网页加载超时，请检查电脑网络');
}
async function target(){await initialized;if(!await tabExists(targetId)){const tab=await chrome.tabs.create({url:'https://www.bilibili.com/',active:true});targetId=tab.id;await remember()}return targetId!}
async function catalog(url:string,kind:string,page:number,order:string='newest'):Promise<PageResult<unknown>>{
  if(!urlAllowed(url))throw new RemoteError('invalid_url','只能读取哔哩哔哩网页');
  if(!await tabExists(catalogId)){const tab=await chrome.tabs.create({url:'https://www.bilibili.com/',active:false});catalogId=tab.id;await chrome.tabs.update(catalogId!,{muted:true,autoDiscardable:false});await remember()}
  await navigation(catalogId!,url);
  let result:PageResult<unknown>=await content(catalogId!,'catalog.read',{kind});
  const physical=order==='oldest'?result.totalPages-page+1:page;
  if(physical<1||physical>result.totalPages)return {items:[],page,totalPages:result.totalPages,total:result.total};
  if(physical>1)result=await content(catalogId!,'catalog.page',{page:physical,kind});
  return {...result,items:order==='oldest'?[...result.items].reverse():result.items,page,nextPage:page<result.totalPages?page+1:undefined};
}
function serializedCatalog(job:()=>Promise<unknown>){const result=catalogSerial.then(job,job);catalogSerial=result.catch(()=>{});return result}
async function collectionUrl(value:string):Promise<string>{
  if(!urlAllowed(value))throw new RemoteError('invalid_url','合集地址无效');
  const cached=collectionRoutes.get(value);if(cached)return cached;
  const url=new URL(value),title=url.searchParams.get('biliremoteCollection');if(!title)return value;
  const mid=url.pathname.match(/^\/(\d+)\/lists$/)?.[1];if(!mid)throw new RemoteError('invalid_url','合集来源无效');
  const page=bounded(Number(url.searchParams.get('biliremotePage')),1,10000),index=bounded(Number(url.searchParams.get('biliremoteIndex')),0,1000);
  await catalog(`https://space.bilibili.com/${mid}/lists`,'collections',page);
  await content(catalogId!,'catalog.openCollection',{title,index});
  for(let attempt=0;attempt<80;attempt++){
    const tab=await chrome.tabs.get(catalogId!);
    if(tab.url&&urlAllowed(tab.url)&&/\/lists\/\d+/.test(new URL(tab.url).pathname)){collectionRoutes.set(value,tab.url);return tab.url}
    await new Promise(resolve=>setTimeout(resolve,200));
  }
  throw new RemoteError('collection_changed','合集没有成功打开，请刷新 UP 主主页后重试');
}
async function openVideo(params:Record<string,unknown>){
  const video=params.video as {url?:string;bvid?:string}|undefined;
  if(!video?.url||!urlAllowed(video.url)||!/^BV[0-9A-Za-z]+$/.test(video.bvid??''))throw new RemoteError('invalid_video','视频地址无效');
  const url=new URL(`https://www.bilibili.com/video/${video.bvid}/`);url.searchParams.set('p',String(Math.floor(bounded(params.part??1,1,10000))));
  const id=await target();currentBinding={playbackId:params.playbackId,bvid:video.bvid,managed,time:params.time??0};await remember();
  await navigation(id,url.href);
  return content(id,'player.bind',bindingParams());
}
async function handle(req:Request):Promise<unknown>{
  await initialized;if(req.v!==1||!req.id)throw new RemoteError('version_mismatch','协议版本不匹配');const p=req.params??{};
  switch(req.method){
    case 'tabs.list':return (await chrome.tabs.query({url:['https://www.bilibili.com/*']})).filter(t=>t.id!==catalogId).map(t=>({id:t.id,title:t.title??'哔哩哔哩',url:t.url,selected:t.id===targetId}));
    case 'tabs.select':{const id=bounded(p.tabId,0,Number.MAX_SAFE_INTEGER);if(!await tabExists(id)||id===catalogId)throw new RemoteError('invalid_tab','这个标签页已经关闭或不属于哔哩哔哩');if(targetId&&await tabExists(targetId))await content(targetId,'player.manage',{enabled:false});targetId=id;currentBinding=undefined;managed=false;await remember();return content(id,'player.state')}
    case 'search':{const query=String(p.query??'').trim();if(!query||query.length>200)throw new RemoteError('invalid_request','搜索词必须为 1～200 字');const kind=p.kind==='creators'?'creators':'videos';const url=`https://search.bilibili.com/${kind==='creators'?'upuser':'video'}?keyword=${encodeURIComponent(query)}`;return serializedCatalog(()=>catalog(url,kind,Math.floor(bounded(p.page??1,1,10000))))}
    case 'creator.videos':{
      const keyword=String(p.keyword??'').trim();if(keyword.length>100)throw new RemoteError('invalid_request','搜索词不能超过 100 字');
      const query=new URLSearchParams({order:p.order==='popular'?'click':'pubdate',keyword});
      return serializedCatalog(()=>catalog(`https://space.bilibili.com/${numericId(p.creatorId)}/upload/video?${query}`,'videos',Math.floor(bounded(p.page??1,1,10000)),p.order==='oldest'?'oldest':'newest'));
    }
    case 'creator.profile':case 'favorites.folders':case 'favorites.videos':case 'comments.list':case 'comments.add':return community(req.method,p);
    case 'creator.collections':return serializedCatalog(()=>catalog(`https://space.bilibili.com/${numericId(p.creatorId)}/lists`,'collections',Math.floor(bounded(p.page??1,1,10000))));
    case 'collection.videos':return serializedCatalog(async()=>catalog(await collectionUrl(String(p.url??'')),'videos',Math.floor(bounded(p.page??1,1,10000))));
    case 'player.open':return openVideo(p);
    case 'player.related':{
      const id=targetId;
      if(id===undefined||!await tabExists(id))throw new RemoteError('no_player','请先选择一个播放视频的标签页');
      const result=await content(id,'player.related',{bvid:p.bvid});
      if(result.items.some((item:{cover?:string})=>!item.cover)){
        try{const covers=new Map((await relatedCovers(String(p.bvid))).map(item=>[item.bvid,item.cover]));result.items=result.items.map((item:{bvid:string;cover?:string})=>({...item,cover:item.cover??covers.get(item.bvid)}));}catch{/* Keep usable DOM results if the site API is unavailable. */}
      }
      if(id!==targetId)throw new RemoteError('target_changed','控制标签页已切换，请刷新相关视频');
      if((await content(id,'player.state')).bvid!==p.bvid)throw new RemoteError('target_changed','电脑已切换视频，请刷新相关视频');
      return result;
    }
    case 'player.manage':{managed=Boolean(p.enabled);if(currentBinding)currentBinding.managed=managed;const result=targetId&&await tabExists(targetId)?await content(targetId,'player.manage',{enabled:managed}):{};if(!managed)originalAutoplay=undefined;await remember();return result;}
    case 'player.state':return targetId&&await tabExists(targetId)?content(targetId,'player.state'):{};
    case 'player.command':{
      if(p.action==='quality'){
        const id=targetId;
        if(id===undefined||!await tabExists(id))throw new RemoteError('no_player','请先选择一个播放视频的标签页');
        const result=await content(id,'player.command',p);
        if(id!==targetId)throw new RemoteError('target_changed','控制标签页已切换，请重新选择清晰度');
        return result;
      }
      const id=await target();if(p.action==='fullscreen'){
        const tab=await chrome.tabs.get(id),win=await chrome.windows.get(tab.windowId);const enabled=Boolean(p.value);
        if(enabled&&!windowStates.has(win.id!))windowStates.set(win.id!,win.state??'normal');
        const result=await content(id,'player.command',p);await chrome.windows.update(win.id!,{state:enabled?'fullscreen':windowStates.get(win.id!)??'normal'});if(!enabled)windowStates.delete(win.id!);return result;
      }return content(id,'player.command',p);
    }
    default:throw new RemoteError('unknown_method',`不支持的方法：${req.method}`);
  }
}
chrome.runtime.onMessage.addListener((message,sender,respond)=>{
  if(message.popup){if(message.popup==='connect')connect();respond({connected:!!port,targetId});return}
  if(sender.tab?.id!==targetId)return;
  if(message.event==='player.autoplayCaptured'){if(managed&&originalAutoplay===undefined&&typeof message.data?.value==='boolean'){originalAutoplay=message.data.value;void remember()}return;}
  if(message.event==='content.ready'){if(currentBinding)void content(targetId!,'player.attach',bindingParams()).catch(()=>{});return;}
  if(message.event==='player.partEnded'&&managed&&currentBinding&&message.data?.playbackId===currentBinding.playbackId){
    const state=message.data;openVideo({video:{url:state.url,bvid:state.bvid},part:state.part+1,time:0,playbackId:state.playbackId}).catch(error=>send('player.error',{...state,errorCode:error.code??'player_error',errorMessage:error.message}));return;
  }
  if(['player.changed','player.ended','player.error'].includes(message.event))send(message.event,message.data);
});
chrome.tabs.onRemoved.addListener(id=>{if(id===targetId){targetId=undefined;currentBinding=undefined;managed=false;send('target.closed',{});void remember()}if(id===catalogId){catalogId=undefined;void remember()}});
chrome.tabs.onUpdated.addListener((id,change)=>{
  if(id!==targetId||!currentBinding)return;
  if(change.url&&change.url.match(/\/video\/(BV[0-9A-Za-z]+)/)?.[1]!==currentBinding.bvid){currentBinding=undefined;managed=false;void remember();send('target.navigated',{});return;}
  if(change.status==='complete')void content(id,'player.attach',bindingParams()).catch(()=>{});
});
chrome.runtime.onInstalled.addListener(()=>{connect();void chrome.alarms.create('reconnect',{periodInMinutes:.5})});
chrome.runtime.onStartup.addListener(connect);chrome.alarms.onAlarm.addListener(connect);connect();

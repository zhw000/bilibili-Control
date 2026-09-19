import {coverUrl} from './catalog';
import {bounded,numericId,PageResult,RemoteError,VideoItem} from './types';

// Fixed, first-party endpoints only. Cookies/CSRF stay inside Chrome and are
// never included in replies to the paired computer or phone.
const origin='https://api.bilibili.com';
type ObjectData=Record<string,any>;
export async function biliRequest(path:string,params:Record<string,string>={},body?:URLSearchParams):Promise<any>{
  const url=new URL(path,origin);url.search=new URLSearchParams(params).toString();
  let response:Response;
  try{response=await fetch(url.href,{credentials:'include',method:body?'POST':'GET',body,signal:AbortSignal.timeout(15000)});}
  catch{throw new RemoteError(body?'comment_uncertain':'network_error',body?'发送结果尚未确认，请刷新评论核对后再决定是否重发。':'哔哩哔哩连接失败，请稍后重试');}
  if(!response.ok)throw new RemoteError(body?'comment_uncertain':'api_unavailable',body?'发送结果尚未确认，请刷新评论核对后再决定是否重发。':`哔哩哔哩暂时不可用（${response.status}）`);
  let result:ObjectData;
  try{result=await response.json();}catch{throw new RemoteError(body?'comment_uncertain':'api_changed',body?'发送结果尚未确认，请刷新评论核对后再决定是否重发。':'哔哩哔哩返回格式已变化，请更新扩展');}
  if(result.code!==0){
    const code=result.code===-101?'login_required':[-111,-403].includes(result.code)?'login_expired':[-352,-412].includes(result.code)?'verification_required':result.code===12002?'comments_closed':'bilibili_error';
    const message=code==='login_required'?'请先在电脑 Chrome 登录哔哩哔哩':code==='login_expired'?'登录状态已失效，请在电脑重新登录后重试':code==='verification_required'?'请在电脑浏览器完成安全验证后重试':code==='comments_closed'?'这个视频已关闭评论':String(result.message||'哔哩哔哩操作失败').slice(0,200);
    throw new RemoteError(code,message);
  }
  return result.data;
}
function id(value:unknown):string{const result=numericId(value);if(result==='0'||result.length>24)throw new RemoteError('invalid_request','编号无效');return result;}
function bvid(value:unknown):string{const result=String(value??'');if(!/^BV[0-9A-Za-z]{1,60}$/.test(result))throw new RemoteError('invalid_video','视频编号无效');return result;}
function pageOf(p:Record<string,unknown>):number{return Math.floor(bounded(p.page??1,1,10000));}
function pageResult<T>(items:T[],page:number,total:number,size=20):PageResult<T>{const totalPages=Math.max(1,Math.ceil(total/size));return {items,page,total,totalPages,nextPage:page<totalPages?page+1:undefined};}
export function apiVideo(item:ObjectData):VideoItem|undefined{
  if(!/^BV[0-9A-Za-z]{1,60}$/.test(item.bvid??''))return undefined;
  return {bvid:item.bvid,title:String(item.title??'视频'),url:`https://www.bilibili.com/video/${item.bvid}/`,cover:coverUrl(item.pic??item.cover),duration:Number(item.duration)||undefined,creatorId:String(item.owner?.mid??item.upper?.mid??'')||undefined,creatorName:item.owner?.name??item.upper?.name,unavailableReason:item.attr!==undefined&&(Number(item.attr)&9)!==0?'视频已失效或不可播放':undefined};
}
export async function relatedCovers(videoId:string):Promise<VideoItem[]>{
  const data=await biliRequest('/x/web-interface/archive/related',{bvid:bvid(videoId)});
  return (Array.isArray(data)?data:[]).map(apiVideo).filter((item):item is VideoItem=>!!item);
}
async function account():Promise<ObjectData>{const data=await biliRequest('/x/web-interface/nav');if(!data?.isLogin)throw new RemoteError('login_required','请先在电脑 Chrome 登录哔哩哔哩');return data;}
async function aidFor(value:unknown):Promise<string>{const data=await biliRequest('/x/web-interface/view',{bvid:bvid(value)});return id(data?.aid);}
export function commentItem(item:ObjectData):ObjectData{
  return {id:String(item.rpid_str??item.rpid),creatorId:String(item.member?.mid??''),creatorName:String(item.member?.uname??'用户'),avatar:coverUrl(item.member?.avatar),message:String(item.content?.message??''),createdAt:Number(item.ctime)||0,likes:Number(item.like)||0,replyCount:Number(item.rcount)||0,replies:(item.replies??[]).map((reply:ObjectData)=>({...commentItem({...reply,replies:[]})}))};
}
export async function community(method:string,p:Record<string,unknown>):Promise<unknown>{
  switch(method){
    case 'creator.profile':{
      const creatorId=id(p.creatorId),data=await biliRequest('/x/web-interface/card',{mid:creatorId});
      if(!data?.card)throw new RemoteError('creator_unavailable','UP 主主页暂时不可用');
      const c=data.card;
      return {id:creatorId,name:String(c.name),url:`https://space.bilibili.com/${creatorId}`,avatar:coverUrl(c.face),description:String(c.sign??''),followers:Number(c.fans)||0,following:Number(c.attention)||0,videoCount:Number(data.archive_count)||0,likes:Number(data.like_num)||0,level:Number(c.level_info?.current_level)||0,verified:String(c.Official?.desc??c.official_verify?.desc??'')};
    }
    case 'favorites.folders':{
      const user=await account(),data=await biliRequest('/x/v3/fav/folder/created/list-all',{up_mid:id(user.mid)});
      return {accountName:String(user.uname),items:(data?.list??[]).map((folder:ObjectData)=>({id:String(folder.id),title:String(folder.title),count:Number(folder.media_count)||0}))};
    }
    case 'favorites.videos':{
      await account();const page=pageOf(p),folderId=id(p.folderId),keyword=String(p.keyword??'').trim();
      if(keyword.length>100)throw new RemoteError('invalid_request','搜索词不能超过 100 字');
      const data=await biliRequest('/x/v3/fav/resource/list',{media_id:folderId,pn:String(page),ps:'20',keyword,order:'mtime',type:'0',tid:'0',platform:'web'});
      const items=(data?.medias??[]).filter((item:ObjectData)=>item.type===2).map(apiVideo).filter((item:VideoItem|undefined)=>!!item);
      // has_more is authoritative: mixed audio/video favorites may contain fewer than 20 videos.
      return {...pageResult(items,page,Number(data?.info?.media_count)||0),nextPage:data?.has_more?page+1:undefined};
    }
    case 'comments.list':{
      const videoId=bvid(p.bvid),oid=await aidFor(videoId),page=pageOf(p),root=p.root===undefined?undefined:id(p.root);
      const data=await biliRequest(root?'/x/v2/reply/reply':'/x/v2/reply',{type:'1',oid,pn:String(page),ps:'20',...(root?{root}:{sort:p.order==='newest'?'0':'2'})});
      const pinned=!root&&page===1?(data?.top_replies??[data?.upper?.top].filter(Boolean)):[];
      const seen=new Set<string>();const items=[...pinned,...(data?.replies??[])].map(commentItem).filter(item=>!seen.has(item.id)&&!!seen.add(item.id));
      return {bvid:videoId,...pageResult(items,page,Number(data?.page?.count)||0,Number(data?.page?.size)||20)};
    }
    case 'comments.add':{
      const videoId=bvid(p.bvid),message=String(p.message??'').trim();
      if(!message||Array.from(message).length>1000)throw new RemoteError('invalid_request','评论请输入 1～1000 字');
      const root=p.root===undefined?undefined:id(p.root),parent=p.parent===undefined?root:id(p.parent);
      if(parent&&!root)throw new RemoteError('invalid_request','回复缺少主评论编号');
      await account();const oid=await aidFor(videoId);
      const csrf=await chrome.cookies.get({url:'https://www.bilibili.com/',name:'bili_jct'});
      if(!csrf?.value)throw new RemoteError('login_expired','请在电脑重新登录哔哩哔哩后发表评论');
      const body=new URLSearchParams({type:'1',oid,message,plat:'1',csrf:csrf.value,...(root?{root,parent:parent!}:{})});
      // Never retry a write: a dropped response does not mean the comment failed.
      const data=await biliRequest('/x/v2/reply/add',{},body);
      return {bvid:videoId,comment:data?.reply?commentItem(data.reply):undefined,message:'评论已提交，展示时间以哔哩哔哩审核结果为准'};
    }
    default:throw new RemoteError('unknown_method','不支持的目录操作');
  }
}

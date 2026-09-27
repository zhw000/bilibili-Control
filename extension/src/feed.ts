import {apiVideo,biliRequest} from './community';
import {bounded,VideoItem} from './types';
import {signWbi,wbiKey} from './wbi';

export interface FeedVideo extends VideoItem { views?:number; danmaku?:number; publishedAt?:number; reason?:string }
type ObjectData=Record<string,any>;
// Each batch is requested like one “换一换” on the desktop homepage.
function feedParams(batch:number):Record<string,string>{
  return {web_location:'1430650',feed_version:'V8',homepage_ver:'1',fresh_type:'3',y_num:'4',last_y_num:'4',device:'win',screen:'1920-1080',ps:'20',
    fresh_idx:String(batch),fresh_idx_1h:String(batch),brush:String(batch-1),fetch_row:'1',
    'x-bili-device-req-json':JSON.stringify({platform:'web',device:'pc',spmid:'333.1007',mobi_app:'web_cn'}),
    'x-bili-locale-json':JSON.stringify({c_locale:{language:'zh',script:'Hans'},always_translate:false})};
}
const count=(value:unknown)=>{const n=Number(value);return Number.isFinite(n)&&n>=0?Math.floor(n):undefined};
export function feedVideo(item:ObjectData):FeedVideo|undefined{
  // Only ordinary videos can be played remotely; ads, live rooms and bangumi cards are skipped.
  if(item?.goto!=='av'||item.business_info)return undefined;
  const video=apiVideo(item);if(!video)return undefined;
  const reason=String(item.rcmd_reason?.content??'').trim()||(Number(item.is_followed)===1?'已关注':'');
  return {...video,views:count(item.stat?.view),danmaku:count(item.stat?.danmaku),publishedAt:count(item.pubdate)||undefined,reason:reason||undefined};
}
export async function homeFeed(p:Record<string,unknown>){
  const page=Math.floor(bounded(p.page??1,1,10000));
  // Signed-out browsers still receive signing keys and a non-personalized feed.
  const account=await biliRequest('/x/web-interface/nav',{},undefined,[-101]);
  const data=await biliRequest('/x/web-interface/wbi/index/top/feed/rcmd',signWbi(feedParams(page),wbiKey(account?.wbi_img?.img_url,account?.wbi_img?.sub_url)));
  const seen=new Set<string>();
  const items=(Array.isArray(data?.item)?data.item:[]).map(feedVideo).filter((item:FeedVideo|undefined):item is FeedVideo=>!!item&&!seen.has(item.bvid)&&!!seen.add(item.bvid));
  return {loggedIn:account?.isLogin===true,accountName:account?.isLogin&&account.uname?String(account.uname):undefined,items,page,nextPage:page<10000?page+1:undefined};
}

export interface VideoItem { bvid:string; title:string; url:string; cover?:string; duration?:number; creatorId?:string; creatorName?:string; unavailableReason?:string }
export interface CreatorItem { id:string; name:string; url:string; avatar?:string; description?:string }
export interface CollectionItem { id:string; title:string; url:string; cover?:string; count?:number; description?:string }
export interface PageResult<T> { items:T[]; page:number; totalPages:number; total?:number; nextPage?:number }
export interface Request { v:1; id:string; method:string; params:Record<string,unknown> }
export class RemoteError extends Error { constructor(public code:string,message:string){super(message)} }
export function urlAllowed(value:string):boolean { try { const u=new URL(value);return u.protocol==='https:'&&['www.bilibili.com','space.bilibili.com','search.bilibili.com'].includes(u.hostname) }catch{return false} }
export function bounded(value:unknown,min:number,max:number):number { if(typeof value!=='number'||!Number.isFinite(value)||value<min||value>max)throw new RemoteError('out_of_range',`数值必须在 ${min}～${max} 之间`);return value }
export function numericId(value:unknown):string { const id=String(value??'');if(!/^\d+$/.test(id))throw new RemoteError('invalid_request','UP 主编号无效');return id }
export function contentId(value:string):string|undefined {
  try { const url=new URL(value);if(url.origin!=='https://www.bilibili.com')return undefined;
    return url.pathname.match(/^\/video\/(BV[0-9A-Za-z]+)\/?$/)?.[1]??url.pathname.match(/^\/bangumi\/play\/((?:ep|ss)\d+)\/?$/)?.[1];
  }catch{return undefined}
}
export function playbackUrl(video:{url?:string;bvid?:string},part=1):string {
  const id=video.url&&contentId(video.url);
  if(!id||id!==video.bvid||id.startsWith('ss'))throw new RemoteError('invalid_video','视频或剧集地址无效');
  return id.startsWith('ep')?`https://www.bilibili.com/bangumi/play/${id}`:`https://www.bilibili.com/video/${id}/?p=${Math.floor(bounded(part,1,10000))}`;
}
export function searchRoute(query:string,kind:unknown):{url:string;kind:string} {
  const routes:Record<string,string>={videos:'video',creators:'upuser',media:'pgc'};
  const category=String(kind??'videos');
  if(!Object.hasOwn(routes,category))throw new RemoteError('invalid_request','不支持的搜索类型');
  return {url:`https://search.bilibili.com/${routes[category]}?keyword=${encodeURIComponent(query)}`,kind:category};
}

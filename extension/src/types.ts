export interface VideoItem { bvid:string; title:string; url:string; cover?:string; duration?:number; creatorId?:string; creatorName?:string; unavailableReason?:string }
export interface CreatorItem { id:string; name:string; url:string; avatar?:string; description?:string }
export interface CollectionItem { id:string; title:string; url:string; cover?:string; count?:number }
export interface PageResult<T> { items:T[]; page:number; totalPages:number; total?:number; nextPage?:number }
export interface Request { v:1; id:string; method:string; params:Record<string,unknown> }
export class RemoteError extends Error { constructor(public code:string,message:string){super(message)} }
export function urlAllowed(value:string):boolean { try { const u=new URL(value);return u.protocol==='https:'&&['www.bilibili.com','space.bilibili.com','search.bilibili.com'].includes(u.hostname) }catch{return false} }
export function bounded(value:unknown,min:number,max:number):number { if(typeof value!=='number'||!Number.isFinite(value)||value<min||value>max)throw new RemoteError('out_of_range',`数值必须在 ${min}～${max} 之间`);return value }
export function numericId(value:unknown):string { const id=String(value??'');if(!/^\d+$/.test(id))throw new RemoteError('invalid_request','UP 主编号无效');return id }

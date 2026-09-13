import { CollectionItem, CreatorItem, PageResult, RemoteError, VideoItem } from './types';

export function durationSeconds(text:string):number|undefined {
  const match=text.match(/(?:^|\s)(\d{1,3}:\d{2}(?::\d{2})?)(?:\s|$)/);
  return match?match[1].split(':').reduce((sum,n)=>sum*60+Number(n),0):undefined;
}
const txt=(node:Element|null)=>node?.textContent?.replace(/\s+/g,' ').trim()??'';
const outsideHeader=(a:Element)=>!a.closest('header,nav,footer,.bili-header,.bili-header__bar,.international-header,.header-channel,.nav-bar,.bili-footer,.international-footer,.footer,.footer-wrp');
function card(a:Element):Element {
  return a.closest('.bili-video-card,.video-page-card-small')??a.closest('.bili-cover-card,.video-card,.small-item,.upload-video-card,.bili-user-profile-view,.bili-user-card,.b-user-info-card,.user-item,.user-card,.video-list-item,.list-item')??a.parentElement?.parentElement??a;
}
function imageOf(node:Element):string|undefined {
  const image=node.querySelector('img');const source=image?.getAttribute('src')||image?.getAttribute('data-src');
  if(!source||source.startsWith('data:'))return undefined;
  return coverUrl(source);
}
export function coverUrl(source:string|null|undefined):string|undefined {
  if(!source)return undefined;
  try{const url=new URL(source,location.href);if(url.protocol!=='https:')return undefined;
    // Use the original cover rather than a browser-specific AVIF resize variant.
    if(url.hostname.endsWith('.hdslb.com'))url.pathname=url.pathname.split('@')[0];
    return url.href;
  }catch{return undefined}
}
export function videoItems(root:ParentNode=document):VideoItem[] {
  const found=new Map<string,VideoItem>();
  for(const anchor of root.querySelectorAll<HTMLAnchorElement>('a[href*="/video/BV"]')){
    if(!outsideHeader(anchor))continue;
    const bvid=anchor.href.match(/\/video\/(BV[0-9A-Za-z]+)/)?.[1];if(!bvid)continue;
    const row=card(anchor);const titleAnchor=row.querySelector<HTMLElement>('a[title],h3 a,.bili-video-card__title a,.bili-video-card__info--tit a,.bili-cover-card__info-title,a.title,.info .title');
    const title=titleAnchor?.getAttribute('title')||txt(titleAnchor)||anchor.getAttribute('title')||txt(anchor);
    if(!title||/^[\d\s万亿.:]+$/.test(title))continue;
    const owner=row.querySelector<HTMLAnchorElement>('a[href*="space.bilibili.com/"]');
    const durationLabel=[...row.querySelectorAll('.bili-video-card__stats__duration,.bili-cover-card__stat span,.duration')].map(txt).find(s=>/^\d{1,3}:\d{2}(?::\d{2})?$/.test(s));
    const result:VideoItem={bvid,title,url:`https://www.bilibili.com/video/${bvid}/`,cover:imageOf(row),duration:durationSeconds(durationLabel??txt(row)),creatorId:owner?.href.match(/space\.bilibili\.com\/(\d+)/)?.[1],creatorName:txt(owner).replace(/\s*[·•]\s*.*$/,'')};
    const old=found.get(bvid);if(!old||result.title.length>old.title.length)found.set(bvid,{...old,...result});
  }
  return [...found.values()];
}
export function creatorItems(root:ParentNode=document):CreatorItem[]{
  const found=new Map<string,CreatorItem>();
  for(const anchor of root.querySelectorAll<HTMLAnchorElement>('a[href*="space.bilibili.com/"]')){
    if(!outsideHeader(anchor))continue;
    const id=anchor.href.match(/space\.bilibili\.com\/(\d+)(?:[/?#]|$)/)?.[1];if(!id)continue;
    const row=card(anchor);const name=anchor.getAttribute('title')||txt(row.querySelector('.bili-user-profile-view__info__uname,.username,.name,.bili-user-card__info__name,h2 a'))||txt(anchor);
    if(!name||name.length>80||/发消息|粉丝数|关注数|收藏/.test(name))continue;
    if(!found.has(id))found.set(id,{id,name,url:`https://space.bilibili.com/${id}`,avatar:imageOf(row),description:txt(row).slice(0,240)});
  }
  return [...found.values()];
}
export function collectionItems(root:ParentNode=document):CollectionItem[]{
  const found=new Map<string,CollectionItem>();
  for(const anchor of root.querySelectorAll<HTMLAnchorElement>('a[href]')){
    if(!outsideHeader(anchor))continue;
    const href=anchor.href;const id=href.match(/\/lists\/(\d+)/)?.[1]??(/\/(?:collectiondetail|seriesdetail)/.test(href)?new URL(href).searchParams.get('sid'):null);
    if(!id)continue;const row=card(anchor);const title=anchor.getAttribute('title')||txt(row.querySelector('[title],h3,.title'))||txt(anchor);
    if(title&&!found.has(href))found.set(href,{id,title,url:href,cover:imageOf(row),count:Number(txt(row).match(/(\d+)\s*个视频/)?.[1])||undefined});
  }
  // New space pages expose buttons instead of links. Retain a navigation locator;
  // resolve its canonical URL only when that collection is opened.
  const mid=location.pathname.match(/^\/(\d+)\/lists/)?.[1];
  if(mid){
    const page=Number(txt(document.querySelector('.vui_pagenation--btn-num.vui_button--active,.be-pager-item-active')))||1;
    [...root.querySelectorAll('.video-list__header')].forEach((header,index)=>{
      const title=txt(header.querySelector('.video-list__title'));if(!/^(合集|系列)[·・]/.test(title))return;
      const link=new URL(`https://space.bilibili.com/${mid}/lists`);link.searchParams.set('biliremoteCollection',title);link.searchParams.set('biliremotePage',String(page));link.searchParams.set('biliremoteIndex',String(index));
      found.set(link.href,{id:`${mid}:${page}:${index}:${title}`,title:title.replace(/^(合集|系列)[·・]/,''),url:link.href,cover:imageOf(header.parentElement??header),count:Number(txt(header.querySelector('.video-list__desc')).match(/\d+/)?.[0])||undefined});
    });
  }
  return [...found.values()];
}
export function openCollection(title:string,index:number):{started:boolean}{
  const headers=[...document.querySelectorAll('.video-list__header')];
  const candidate=headers[index];
  const header=candidate&&txt(candidate.querySelector('.video-list__title'))===title?candidate:headers.find(e=>txt(e.querySelector('.video-list__title'))===title);
  const button=header&&[...header.querySelectorAll<HTMLButtonElement>('button')].find(b=>txt(b).includes('查看更多'));
  if(!button)throw new RemoteError('collection_changed','合集列表已变化，请返回 UP 主主页刷新后重试');
  button.click();return {started:true};
}
export function pagination(root:ParentNode=document):{totalPages:number;total?:number}{
  const body=txt(root instanceof Document?root.body:root as Element);
  const pages=Number(body.match(/共\s*(\d+)\s*页/)?.[1]);
  const total=Number(body.match(/共\s*\d+\s*页\s*\/\s*(\d+)\s*个/)?.[1]);
  const pager=[...root.querySelectorAll('button,.vui_pagenation--btn-num,.pagination-btn,.be-pager-item')].map(e=>txt(e)).filter(x=>/^\d+$/.test(x)).map(Number);
  return {totalPages:pages||Math.max(1,...pager),total:total||undefined};
}
export function pageError():RemoteError|undefined {
  if(document.querySelector('.geetest_panel:not([style*="display: none"]),.geetest_box,iframe[src*="captcha"]'))return new RemoteError('verification_required','请在电脑浏览器完成安全验证后重试');
  const errors=[...document.querySelectorAll('.error-panel,.error-container,.bili-error,.not-found,.search-error')].map(txt).join(' ');
  if(/登录/.test(errors))return new RemoteError('login_required','请先在电脑浏览器登录哔哩哔哩');
  if(errors&&/失败|出错|异常|繁忙|稍后/.test(errors))return new RemoteError('catalog_unavailable',errors.slice(0,180));
  return undefined;
}
function emptyVisible():boolean {return /没有相关|没有找到|还没有|还没建过|什么也没有|暂无视频|暂无内容|空空如也/.test([...document.querySelectorAll('[class*="empty"],[class*="no-data"],[class*="nodata"]')].map(txt).join(' '))}
export async function readCatalog(kind:string):Promise<PageResult<VideoItem|CreatorItem|CollectionItem>>{
  for(let attempt=0;attempt<80;attempt++){
    const error=pageError();if(error)throw error;
    const items=kind==='creators'?creatorItems():kind==='collections'?collectionItems():videoItems();
    if(items.length||emptyVisible()){const {totalPages,total}=pagination();return {items,page:1,totalPages,total,nextPage:totalPages>1?2:undefined}}
    await new Promise(resolve=>setTimeout(resolve,250));
  }
  throw new RemoteError('page_changed','未能读取目录；请检查电脑网页是否加载完成，或更新扩展以适配新版页面');
}
export async function turnPage(page:number,kind:string):Promise<void>{
  if(page===1)return;
  const before=JSON.stringify(kind==='collections'?collectionItems():kind==='creators'?creatorItems():videoItems());
  const button=[...document.querySelectorAll<HTMLElement>('button,.vui_pagenation--btn-num,.be-pager-item')].find(e=>txt(e)===String(page));
  if(button)button.click();
  else {
    const input=document.querySelector<HTMLInputElement>('.vui_pagenation input,.vui_pagination input,.be-pager input,input[type="number"]');
    if(!input)throw new RemoteError('page_changed','找不到目录翻页控件，请更新扩展');
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value')?.set?.call(input,String(page));
    input.dispatchEvent(new Event('input',{bubbles:true}));input.dispatchEvent(new Event('change',{bubbles:true}));input.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,bubbles:true}));
  }
  for(let attempt=0;attempt<80;attempt++){
    await new Promise(resolve=>setTimeout(resolve,250));const error=pageError();if(error)throw error;
    const after=JSON.stringify(kind==='collections'?collectionItems():kind==='creators'?creatorItems():videoItems());
    if(after!==before&&after!=='[]')return;
  }
  throw new RemoteError('catalog_timeout','目录翻页未完成，请重试');
}

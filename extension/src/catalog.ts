import { CollectionItem, contentId, CreatorItem, PageResult, RemoteError, VideoItem } from './types';

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
  for(const image of node.querySelectorAll('img,source')){
    // Lazy images often have a nonempty data: placeholder in src, while picture
    // keeps the real cover in source/srcset before the browser decodes it.
    for(const attribute of ['data-src','data-original','data-lazy-src','src','data-srcset','srcset']){
      const value=image.getAttribute(attribute);if(!value||value.startsWith('data:'))continue;
      const cover=coverUrl(attribute.includes('srcset')?value.split(',')[0].trim().split(/\s+/)[0]:value);
      if(cover)return cover;
    }
  }
  return undefined;
}
export function coverUrl(source:string|null|undefined):string|undefined {
  if(!source)return undefined;
  try{const url=new URL(source,'https://www.bilibili.com/');
    if(url.protocol==='http:'&&url.hostname.endsWith('.hdslb.com'))url.protocol='https:';
    if(url.protocol!=='https:')return undefined;
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
    const old=found.get(bvid);
    if(!old)found.set(bvid,result);
    else found.set(bvid,{...old,...(result.title.length>old.title.length?result:{}),cover:old.cover??result.cover,duration:old.duration??result.duration,creatorId:old.creatorId||result.creatorId,creatorName:old.creatorName||result.creatorName});
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
export function mediaItems(root:ParentNode=document):CollectionItem[]{
  const found=new Map<string,CollectionItem>();
  for(const row of root.querySelectorAll('.media-card,.bangumi-item')){
    const anchor=row.querySelector<HTMLAnchorElement>('.media-card-content-head-title a,a.title')??row.querySelector<HTMLAnchorElement>('a[href*="/bangumi/play/ss"]');
    const id=anchor&&contentId(anchor.href);
    if(!id?.startsWith('ss'))continue;
    const title=anchor!.getAttribute('title')||txt(anchor);
    if(!title)continue;
    const detail=txt(row.querySelector('.media-card-content-head-label,.info'));
    const category=txt(row.querySelector('.media-card-content-head-title-tag,.type'));
    const badge=txt(row.querySelector('.media-card-image-tag'));
    found.set(id,{id,title,url:`https://www.bilibili.com/bangumi/play/${id}`,cover:imageOf(row),count:Number(detail.match(/(?:全|更新至(?:第)?)\s*(\d+)\s*[集话]/)?.[1])||undefined,description:[category,detail,badge].filter(Boolean).join(' · ')});
  }
  return [...found.values()];
}
export function episodeSection(root:ParentNode=document):Element|null {
  // Only the main feature: trailers, extras and recommendations are separate panels.
  const panels=[...root.querySelectorAll('section[class*="SectionPanel_panel"],.ep-list-wrapper,#eplist_module')];
  return panels.find(panel=>txt(panel.querySelector('h3,.ep-list-title,.list-title')).startsWith('正片'))??panels[0]??null;
}
export function episodeItems(root:ParentNode=document):VideoItem[]{
  const section=episodeSection(root);if(!section)return [];
  const found=new Map<string,VideoItem>();
  const cover=coverUrl(document.querySelector('meta[property="og:image"]')?.getAttribute('content'));
  for(const anchor of section.querySelectorAll<HTMLAnchorElement>('a[href*="/bangumi/play/ep"]')){
    const id=contentId(anchor.href);if(!id?.startsWith('ep'))continue;
    const label=anchor.getAttribute('title')||txt(anchor.querySelector('[class*="numberTitle"],.ep-title,.long-title'))||txt(anchor);
    if(!label)continue;
    const title=/^\d+$/.test(label)?`第 ${label} 集`:label;
    found.set(id,{bvid:id,title,url:`https://www.bilibili.com/bangumi/play/${id}`,cover,creatorName:txt(anchor.querySelector('[class*="Badge"],.badge'))||undefined});
  }
  return [...found.values()];
}
export async function readEpisodes():Promise<PageResult<VideoItem>>{
  for(let attempt=0;attempt<80;attempt++){
    const error=pageError();if(error)throw error;
    if(episodeItems().length)break;
    await new Promise(resolve=>setTimeout(resolve,250));
  }
  const section=episodeSection();if(!section)throw new RemoteError('page_changed','未能读取正片选集，请检查电脑上的影视页面');
  const scroll=section.querySelector<HTMLElement>('[class*="EpisodeVirtualList_scroll"]');
  const found=new Map<string,VideoItem>();
  const collect=()=>{for(const item of episodeItems())if(!found.has(item.bvid))found.set(item.bvid,item)};
  // Virtualized lists only render a window of episodes. Harvest each scroll window.
  if(scroll){
    const original=scroll.scrollTop;
    try{
      for(let position=0,step=0;step<500;step++){
        scroll.scrollTop=position;scroll.dispatchEvent(new Event('scroll'));
        await new Promise(resolve=>setTimeout(resolve,100));collect();
        if(position>=scroll.scrollHeight-scroll.clientHeight)break;
        position=Math.min(scroll.scrollHeight-scroll.clientHeight,position+Math.max(50,scroll.clientHeight*.75));
      }
    }finally{scroll.scrollTop=original;scroll.dispatchEvent(new Event('scroll'))}
  }else collect();
  const expected=Number(txt(section).match(/\(\s*\d+\s*\/\s*(\d+)\s*\)/)?.[1]);
  if(!found.size||(expected&&found.size!==expected))throw new RemoteError('page_changed','选集尚未完整加载，请刷新电脑影视页面后重试');
  const items=[...found.values()];
  // Numbered episodes may be displayed in descending order on the website.
  if(items.every(item=>/^第 \d+ 集$/.test(item.title)))items.sort((a,b)=>Number(a.title.match(/\d+/)![0])-Number(b.title.match(/\d+/)![0]));
  return {items,page:1,totalPages:1,total:items.length};
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
  const pager=[...root.querySelectorAll('button,.vui_pagenation--btn-num,.pagination-btn,.be-pager-item')].filter(e=>!e.closest('.media-card,.bangumi-item')).map(e=>txt(e)).filter(x=>/^\d+$/.test(x)).map(Number);
  return {totalPages:pages||Math.max(1,...pager),total:total||undefined};
}
export function pageError():RemoteError|undefined {
  if(document.querySelector('.geetest_panel:not([style*="display: none"]),.geetest_box,iframe[src*="captcha"]'))return new RemoteError('verification_required','请在电脑浏览器完成安全验证后重试');
  const errors=[...document.querySelectorAll('.error-panel,.error-container,.bili-error,.not-found,.search-error')].map(txt).join(' ');
  if(/登录/.test(errors))return new RemoteError('login_required','请先在电脑浏览器登录哔哩哔哩');
  if(errors&&/失败|出错|异常|繁忙|稍后/.test(errors))return new RemoteError('catalog_unavailable',errors.slice(0,180));
  return undefined;
}
function emptyVisible():boolean {return /没有相关|没有找到|还没有|还没建过|什么也没有|暂无视频|暂无内容|空空如也|寂寞如雪/.test([...document.querySelectorAll('[class*="empty"],[class*="no-data"],[class*="nodata"]')].map(txt).join(' '))}
function catalogItems(kind:string){return kind==='media'?mediaItems():kind==='creators'?creatorItems():kind==='collections'?collectionItems():videoItems()}
export async function readCatalog(kind:string):Promise<PageResult<VideoItem|CreatorItem|CollectionItem>>{
  if(kind==='episodes')return readEpisodes();
  let firstItemsAt:number|undefined;
  for(let attempt=0;attempt<80;attempt++){
    const error=pageError();if(error)throw error;
    const items=catalogItems(kind);
    if(items.length&&firstItemsAt===undefined)firstItemsAt=attempt;
    const coversReady=items.every(item=>'avatar' in item?!!item.avatar:'cover' in item&&!!item.cover);
    if((items.length&&(coversReady||attempt-(firstItemsAt??attempt)>=6||attempt===79))||emptyVisible()){const {totalPages,total}=pagination();return {items,page:1,totalPages,total,nextPage:totalPages>1?2:undefined}}
    await new Promise(resolve=>setTimeout(resolve,250));
  }
  throw new RemoteError('page_changed','未能读取目录；请检查电脑网页是否加载完成，或更新扩展以适配新版页面');
}
export async function turnPage(page:number,kind:string):Promise<void>{
  if(page===1)return;
  const before=JSON.stringify(catalogItems(kind));
  const button=[...document.querySelectorAll<HTMLElement>('button,.vui_pagenation--btn-num,.be-pager-item')].find(e=>!e.closest('.media-card,.bangumi-item')&&txt(e)===String(page));
  if(button)button.click();
  else {
    const input=document.querySelector<HTMLInputElement>('.vui_pagenation input,.vui_pagination input,.be-pager input,input[type="number"]');
    if(!input)throw new RemoteError('page_changed','找不到目录翻页控件，请更新扩展');
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value')?.set?.call(input,String(page));
    input.dispatchEvent(new Event('input',{bubbles:true}));input.dispatchEvent(new Event('change',{bubbles:true}));input.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,bubbles:true}));
  }
  for(let attempt=0;attempt<80;attempt++){
    await new Promise(resolve=>setTimeout(resolve,250));const error=pageError();if(error)throw error;
    const after=JSON.stringify(catalogItems(kind));
    if(after!==before&&after!=='[]')return;
  }
  throw new RemoteError('catalog_timeout','目录翻页未完成，请重试');
}

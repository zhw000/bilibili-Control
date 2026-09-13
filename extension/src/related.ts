import {pageError,videoItems} from './catalog';
import {RemoteError,VideoItem} from './types';

export function relatedItems(bvid:string,root:ParentNode=document):VideoItem[]{
  const found=new Map<string,VideoItem>();
  // Only recommendations: exclude multi-part/collection pods and other page links.
  for(const section of root.querySelectorAll('.recommend-list-v1,.recommend-list'))
    for(const item of videoItems(section))if(item.bvid!==bvid&&!found.has(item.bvid))found.set(item.bvid,item);
  return [...found.values()];
}

export async function readRelated(bvid:string):Promise<{bvid:string;items:VideoItem[]}>{
  if(!/^BV[0-9A-Za-z]{1,60}$/.test(bvid))throw new RemoteError('invalid_video','相关视频编号无效');
  for(let attempt=0;attempt<40;attempt++){
    if(location.pathname.match(/\/video\/(BV[0-9A-Za-z]+)/)?.[1]!==bvid)
      throw new RemoteError('target_changed','电脑已切换视频，正在更新相关视频');
    const error=pageError();if(error)throw error;
    const items=relatedItems(bvid);
    if(items.length)return {bvid,items};
    const empty=document.querySelector('.recommend-list-v1 .empty,.recommend-list .empty');
    if(empty?.textContent?.match(/暂无|没有/))return {bvid,items:[]};
    await new Promise(resolve=>setTimeout(resolve,200));
  }
  throw new RemoteError('related_unavailable','暂时未能读取相关视频，请稍后刷新列表；电脑上的视频可继续播放');
}

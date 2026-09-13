// @vitest-environment jsdom
import {beforeEach,expect,it,vi} from 'vitest';
import {relatedItems,readRelated} from '../src/related';
const card=(id:string,title:string)=>`<div class="video-page-card-small"><div class="card-box"><div class="pic-box"><div class="pic"><div class="framepreview-box"><a href="https://www.bilibili.com/video/${id}/"><img src="https://i1.hdslb.com/bfs/archive/test.jpg@336w_190h_1c.avif"></a></div><span class="duration">02:42</span></div></div><div class="info"><a href="https://www.bilibili.com/video/${id}/"><p class="title" title="${title}">${title}</p></a><div class="upname"><a href="https://space.bilibili.com/123/"><span class="name">旅行 UP</span></a></div></div></div></div>`;
beforeEach(()=>{document.body.innerHTML='';vi.useRealTimers();vi.unstubAllGlobals()});
it('reads live recommendation cards in site order, excludes current and collection videos, and deduplicates',()=>{
  document.body.innerHTML=`<div class="video-pod">${card('BVCollection','合集条目')}</div><div class="recommend-list-v1"><div class="next-play">${card('BVNext','下一个')}</div>${card('BVNext','下一个')}${card('BVCurrent','当前视频')}${card('BVLast','另一条')}</div>`;
  const items=relatedItems('BVCurrent');
  expect(items.map(x=>x.bvid)).toEqual(['BVNext','BVLast']);
  expect(items[0]).toMatchObject({title:'下一个',duration:162,creatorId:'123',creatorName:'旅行 UP',cover:'https://i1.hdslb.com/bfs/archive/test.jpg',url:'https://www.bilibili.com/video/BVNext/'});
});
it('does not fall back to unrelated page links when recommendation markup is missing',()=>{
  document.body.innerHTML=card('BVOutside','其他区域');expect(relatedItems('BVCurrent')).toEqual([]);
});
it('rejects a stale video request without navigating or clicking the player',async()=>{
  vi.stubGlobal('location',new URL('https://www.bilibili.com/video/BVChanged/'));
  await expect(readRelated('BVCurrent')).rejects.toMatchObject({code:'target_changed'});
});
it('reports an explicit empty recommendation list',async()=>{
  vi.stubGlobal('location',new URL('https://www.bilibili.com/video/BVCurrent/'));
  document.body.innerHTML='<div class="recommend-list-v1"><div class="empty">暂无相关推荐</div></div>';
  await expect(readRelated('BVCurrent')).resolves.toEqual({bvid:'BVCurrent',items:[]});
});
it('surfaces site verification rather than presenting an empty list',async()=>{
  vi.stubGlobal('location',new URL('https://www.bilibili.com/video/BVCurrent/'));
  document.body.innerHTML='<div class="geetest_box">安全验证</div>';
  await expect(readRelated('BVCurrent')).rejects.toMatchObject({code:'verification_required'});
});

// @vitest-environment jsdom
import {beforeEach,expect,it,vi} from 'vitest';
import {episodeItems,mediaItems,pagination,readCatalog,readEpisodes,turnPage} from '../src/catalog';
import {partInfo,playerError,playerIdentity} from '../src/player-dom';
import {contentId,playbackUrl,searchRoute} from '../src/types';

beforeEach(()=>{document.body.innerHTML='';document.head.innerHTML='';vi.useRealTimers()});
const episode=(id:number,label:string,active=false)=>`<a class="EpisodeVirtualList_numberItem__test ${active?'EpisodeVirtualList_activeNumber__test':''}" href="https://www.bilibili.com/bangumi/play/ep${id}" title="${label}"><span>${label}</span><span class="EpisodeVirtualList_numberBadge__test">会员</span></a>`;

it('reads film, TV and documentary season cards without treating episode previews as titles',()=>{
  document.body.innerHTML=['电影','电视剧','纪录片'].map((category,i)=>`<div class="media-card"><a href="https://www.bilibili.com/bangumi/play/ss${i+1}"><img src="https://i0.hdslb.com/cover.jpg@362w.avif"></a><span class="media-card-image-tag">大会员</span><div class="media-card-content-head-title"><span class="media-card-content-head-title-tag">${category}</span><a href="https://www.bilibili.com/bangumi/play/ss${i+1}" title="作品${i}"><em>作品</em>${i}</a></div><div class="media-card-content-head-label">2025 · 全7集</div>${episode(99,'1')}</div>`).join('');
  expect(mediaItems()).toHaveLength(3);
  expect(mediaItems()[2]).toMatchObject({id:'ss3',title:'作品2',count:7,cover:'https://i0.hdslb.com/cover.jpg',description:'纪录片 · 2025 · 全7集 · 大会员'});
});
it('routes licensed search to the real PGC search page and rejects unknown kinds',()=>{
  expect(searchRoute('电影 & 纪录片','media')).toEqual({kind:'media',url:'https://search.bilibili.com/pgc?keyword='+encodeURIComponent('电影 & 纪录片')});
  expect(searchRoute('test',undefined).kind).toBe('videos');
  expect(()=>searchRoute('test','other')).toThrow();
});
it('returns an explicit empty search instead of timing out',async()=>{
  document.body.innerHTML='<div class="search-empty">今天真是寂寞如雪啊~</div>';
  expect((await readCatalog('media')).items).toEqual([]);
});
it('ignores episode preview buttons when counting and selecting search pages',async()=>{
  document.body.innerHTML='<div class="media-card"><button>2</button><button>99</button></div><div class="vui_pagenation"><button>1</button><button>2</button></div>';
  expect(pagination().totalPages).toBe(2);
  let clicked=false;
  document.querySelector('.vui_pagenation button:last-child')!.addEventListener('click',()=>{clicked=true;document.body.insertAdjacentHTML('beforeend','<div class="media-card"><div class="media-card-content-head-title"><a href="https://www.bilibili.com/bangumi/play/ss2">第二页</a></div></div>')});
  await turnPage(2,'media');expect(clicked).toBe(true);
});
it('reads only main episodes, deduplicates links, and restores ascending episode order',async()=>{
  document.body.innerHTML=`<section class="SectionPanel_panel__test"><h3>正片</h3>(1/2)${episode(2,'2')}${episode(1,'1')}${episode(1,'1')}</section><section class="SectionPanel_panel__test"><h3>预告</h3>${episode(3,'预告片')}</section>`;
  expect(episodeItems().map(x=>x.bvid)).toEqual(['ep2','ep1']);
  expect((await readEpisodes()).items.map(x=>x.bvid)).toEqual(['ep1','ep2']);
});
it('collects every virtual scroll window and restores the original position',async()=>{
  document.body.innerHTML=`<section class="SectionPanel_panel__test"><h3>正片</h3>(1/4)<div class="EpisodeVirtualList_scroll__test">${episode(1,'1')}${episode(2,'2')}</div></section>`;
  const scroll=document.querySelector<HTMLElement>('[class*="EpisodeVirtualList_scroll"]')!;
  Object.defineProperties(scroll,{clientHeight:{value:100},scrollHeight:{value:200}});
  scroll.addEventListener('scroll',()=>{scroll.innerHTML=scroll.scrollTop<50?episode(1,'1')+episode(2,'2'):episode(3,'3')+episode(4,'4')});
  expect((await readEpisodes()).items.map(x=>x.bvid)).toEqual(['ep1','ep2','ep3','ep4']);
  expect(scroll.scrollTop).toBe(0);
});
it('fails an incomplete season instead of silently truncating a queue',async()=>{
  document.body.innerHTML=`<section class="SectionPanel_panel__test"><h3>正片</h3>(1/12)${episode(1,'1')}</section>`;
  await expect(readEpisodes()).rejects.toMatchObject({code:'page_changed'});
});
it('opens episodes by EP identity and preserves ordinary multi-part video URLs',()=>{
  expect(playbackUrl({bvid:'ep123',url:'https://www.bilibili.com/bangumi/play/ep123?from=search'},3)).toBe('https://www.bilibili.com/bangumi/play/ep123');
  expect(playbackUrl({bvid:'BVtest',url:'https://www.bilibili.com/video/BVtest/'},3)).toBe('https://www.bilibili.com/video/BVtest/?p=3');
  for(const url of ['https://evil.test/bangumi/play/ep123','https://www.bilibili.com/bangumi/play/ep456','https://www.bilibili.com/bangumi/play/ss123','https://www.bilibili.com/bangumi/play/ep123/evil'])expect(()=>playbackUrl({bvid:'ep123',url})).toThrow();
  expect(contentId('https://www.bilibili.com.evil.test/bangumi/play/ep123')).toBeUndefined();
});
it('uses active EP identity on season pages and never treats episodes as video parts',()=>{
  document.body.innerHTML=episode(123,'1',true)+'<div class="video-pod__header">视频选集 (1/7)</div>';
  expect(playerIdentity(document,'https://www.bilibili.com/bangumi/play/ss123')).toBe('ep123');
  expect(playerIdentity(document,'https://www.bilibili.com/bangumi/play/ep456')).toBe('ep456');
  expect(partInfo(document,'https://www.bilibili.com/bangumi/play/ep456')).toEqual({part:1,partCount:1});
});
it('stops on membership and region restrictions without treating them as deleted videos',()=>{
  document.body.innerHTML='<div class="bpx-player-ending-panel">试看结束，开通大会员</div>';
  expect(playerError()?.code).toBe('access_required');
  document.body.innerHTML='<div class="bpx-player-error-message">受版权限制，所在地区无法播放</div>';
  expect(playerError()?.code).toBe('region_restricted');
  document.body.innerHTML='<div class="PromptBar_subtitleText__test">试看中 · 成为大会员 免费看本片</div>';
  expect(playerError()).toBeUndefined();expect(playerError(document,true)?.code).toBe('access_required');
  document.body.innerHTML='<div class="bpx-player-ending-panel" style="display: none">试看结束</div>';
  expect(playerError()).toBeUndefined();
});

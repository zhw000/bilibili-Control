// @vitest-environment jsdom
import {beforeEach,describe,expect,it} from 'vitest';
import {durationSeconds,videoItems,pagination,creatorItems,collectionItems} from '../src/catalog';
import {bounded,urlAllowed} from '../src/types';
beforeEach(()=>{document.body.innerHTML=''});
describe('catalog adaptation',()=>{
 it('deduplicates cover/title links and preserves duration and creator',()=>{document.body.innerHTML='<div class="bili-video-card"><a href="https://www.bilibili.com/video/BV1abc/"><img src="https://i0.hdslb.com/test.jpg"> 12:30 </a><h3><a href="https://www.bilibili.com/video/BV1abc/">测试视频</a></h3><a href="https://space.bilibili.com/123">测试 UP</a></div>';const result=videoItems();expect(result).toHaveLength(1);expect(result[0]).toMatchObject({bvid:'BV1abc',title:'测试视频',duration:750,creatorId:'123'})});
 it('reads large pagination totals rather than just visible page buttons',()=>{document.body.innerHTML='<button>1</button><button>7</button><button>22</button><span>共 22 页 / 904 个，跳至</span>';expect(pagination()).toEqual({totalPages:22,total:904})});
 it('excludes header account links from creator results',()=>{document.body.innerHTML='<header><a href="https://space.bilibili.com/9">我的账号</a></header><div class="user-card"><a href="https://space.bilibili.com/1">目标 UP</a></div>';expect(creatorItems().map(x=>x.id)).toEqual(['1'])});
 it('recognizes modern collection links',()=>{document.body.innerHTML='<div class="list-item"><a href="https://space.bilibili.com/1/lists/55?type=season">教程合集</a></div>';expect(collectionItems()[0]).toMatchObject({id:'55',title:'教程合集'})});
 it('handles long timestamps',()=>expect(durationSeconds('片长 1:02:03 完整版')).toBe(3723));
 it('reads modern space-page cards with adjacent statistics',()=>{document.body.innerHTML='<div class="bili-video-card"><a class="bili-cover-card" href="https://www.bilibili.com/video/BV2abc/"><img src="//i0.hdslb.com/cover.jpg"><div class="bili-cover-card__stat"><span>2742</span><span>2</span><span>01:49</span></div></a><div class="bili-video-card__title"><a href="https://www.bilibili.com/video/BV2abc/">新版投稿标题</a></div></div>';expect(videoItems()[0]).toMatchObject({title:'新版投稿标题',duration:109})});
 it('reads the live search user-card structure',()=>{document.body.innerHTML='<div class="b-user-info-card"><a href="https://space.bilibili.com/42"><img src="https://i0.hdslb.com/avatar.jpg"></a><div class="user-content"><h2><a href="https://space.bilibili.com/42">示例 UP</a></h2><p>介绍</p></div></div>';expect(creatorItems()).toEqual([{id:'42',name:'示例 UP',url:'https://space.bilibili.com/42',avatar:'https://i0.hdslb.com/avatar.jpg',description:'示例 UP介绍'}])});
});
it('rejects arbitrary navigation and nonfinite values',()=>{expect(urlAllowed('https://www.bilibili.com.attacker.test/')).toBe(false);expect(urlAllowed('javascript:alert(1)')).toBe(false);expect(()=>bounded(NaN,0,1)).toThrow();expect(()=>bounded(2,0,1)).toThrow()});

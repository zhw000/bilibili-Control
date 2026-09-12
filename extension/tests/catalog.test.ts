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
});
it('rejects arbitrary navigation and nonfinite values',()=>{expect(urlAllowed('https://www.bilibili.com.attacker.test/')).toBe(false);expect(urlAllowed('javascript:alert(1)')).toBe(false);expect(()=>bounded(NaN,0,1)).toThrow();expect(()=>bounded(2,0,1)).toThrow()});

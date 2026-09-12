// @vitest-environment jsdom
import {beforeEach,expect,it} from 'vitest';
import {danmakuControl,danmakuOn,isWebFullscreen,partInfo} from '../src/player-dom';
beforeEach(()=>{document.body.innerHTML=''});
it('reads live multi-part headings without hidden initial state or anchor links',()=>{document.body.innerHTML='<div class="video-pod__header"><div class="title">视频选集</div><div class="amt">（2/185）</div></div>';expect(partInfo(document,'https://www.bilibili.com/video/BVtest/?p=2')).toEqual({part:2,partCount:185})});
it('does not confuse collection length with individual video parts',()=>{document.body.innerHTML='<div class="video-pod__header">合集：科学课堂 （1/40）</div>';expect(partInfo(document,'https://www.bilibili.com/video/BVtest/')).toEqual({part:1,partCount:1})});
it('uses the nested actual danmaku checkbox rather than its ancestor',()=>{document.body.innerHTML='<div class="bpx-player-dm-switch"><div><input type="checkbox" aria-checked="false"></div></div>';expect(danmakuControl()).toBeInstanceOf(HTMLInputElement);expect(danmakuOn()).toBe(false);document.querySelector('input')!.checked=true;expect(danmakuOn()).toBe(true)});
it('reflects website fullscreen state',()=>{document.body.innerHTML='<div class="bpx-player-container" data-screen="web"></div>';expect(isWebFullscreen()).toBe(true)});

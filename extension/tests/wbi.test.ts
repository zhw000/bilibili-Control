import {createHash,randomBytes} from 'node:crypto';
import {expect,it} from 'vitest';
import {md5,signWbi,wbiKey} from '../src/wbi';

const key='ea1db124af3c7062474693fa704f4ff8';
it('computes MD5 over UTF-8 text like Node crypto, including padding boundaries',()=>{
  expect(md5('')).toBe('d41d8cd98f00b204e9800998ecf8427e');
  expect(md5('abc')).toBe('900150983cd24fb0d6963f7d28e17f72');
  const samples=['哔哩哔哩 (゜-゜)つロ 干杯~','x'.repeat(55),'x'.repeat(56),'x'.repeat(63),'x'.repeat(64),'x'.repeat(1000),...Array.from({length:40},(_,i)=>randomBytes(i*5).toString('base64')+'推荐')];
  for(const text of samples)expect(md5(text)).toBe(createHash('md5').update(text,'utf8').digest('hex'));
});
it('derives the mixin key from the published WBI image names',()=>{
  expect(wbiKey('https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png','https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png')).toBe(key);
  let error:unknown;try{wbiKey(undefined,'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png')}catch(caught){error=caught}
  expect(error).toMatchObject({code:'api_changed'});
});
it('sorts keys and strips the characters the website removes before signing',()=>{
  expect(signWbi({foo:'114',bar:"5!1'4(",zab:'1919810*)'},key,1702204169000)).toEqual({foo:'114',bar:'514',zab:'1919810',wts:'1702204169',w_rid:'8f6f2b5b3d485fe1886cec6a0be8c5d4'});
});
it('reproduces the signature of a request captured from the desktop homepage',()=>{
  // “换一换” on www.bilibili.com, 2026-09-27; the website sent w_rid=abb80dfe6778e38951978e5d8b6f8a83.
  const captured={web_location:'1430650',y_num:'4',fresh_type:'3',feed_version:'V8',fresh_idx_1h:'1',fetch_row:'1',fresh_idx:'1',brush:'0',device:'win',homepage_ver:'1',ps:'10',last_y_num:'4',screen:'0-1019',tt_exp:'',domestic_zh_ps:'10',domestic_other_ps:'10',overseas_zh_ps:'10',overseas_other_ps:'15',
    last_showlist:'av_n_117280105045764,av_n_117323121823355,av_n_117160852587672,ad_n_5614,av_n_117298023110456,av_n_117324765990040,av_n_117210932580074,ad_n_5614,av_n_117257237696871,av_n_117331074225763',uniq_id:'1021113454913',
    'x-bili-device-req-json':'{"platform":"web","device":"pc","spmid":"333.1007","mobi_app":"web_cn"}','x-bili-locale-json':'{"c_locale":{"language":"zh","script":"Hans"},"always_translate":false}'};
  expect(signWbi(captured,key,1790493154000).w_rid).toBe('abb80dfe6778e38951978e5d8b6f8a83');
});

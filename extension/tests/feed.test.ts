import {createHash} from 'node:crypto';
import {afterEach,beforeEach,expect,it,vi} from 'vitest';
import {homeFeed} from '../src/feed';

const fetchMock=vi.fn();
const reply=(code:number,data:unknown)=>({ok:true,json:async()=>({code,message:'',data})});
const wbi_img={img_url:'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',sub_url:'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png'};
const video=(bvid:string,extra:Record<string,unknown>={})=>({id:117136190216177,bvid,cid:1,goto:'av',uri:`https://www.bilibili.com/video/${bvid}`,pic:'http://i2.hdslb.com/bfs/archive/cover.jpg',title:`推荐 ${bvid}`,duration:394,pubdate:1787386562,owner:{mid:5294454,name:'UP',face:'https://i0.hdslb.com/face.jpg'},stat:{view:10328558,like:930939,danmaku:16222},is_followed:0,rcmd_reason:{content:'88万点赞',reason_type:3},business_info:null,...extra});
beforeEach(()=>{vi.stubGlobal('fetch',fetchMock);fetchMock.mockReset();});
afterEach(()=>vi.unstubAllGlobals());
it('reads one signed homepage batch for the Chrome account and keeps playable videos only',async()=>{
  fetchMock.mockResolvedValueOnce(reply(0,{isLogin:true,uname:'账号',wbi_img})).mockResolvedValueOnce(reply(0,{item:[
    video('BV1a'),{id:0,bvid:'',goto:'ad',business_info:{id:5614,is_ad:true}},video('BV1b',{business_info:{is_ad:true}}),
    {id:1,bvid:'',goto:'live',room_info:{room_id:1}},video('BV1c',{rcmd_reason:{reason_type:1},is_followed:1}),video('BV1a')]}));
  const result:any=await homeFeed({page:3});
  expect(result).toMatchObject({loggedIn:true,accountName:'账号',page:3,nextPage:4});
  expect(result.items.map((item:any)=>item.bvid)).toEqual(['BV1a','BV1c']);
  expect(result.items[0]).toEqual({bvid:'BV1a',title:'推荐 BV1a',url:'https://www.bilibili.com/video/BV1a/',cover:'https://i2.hdslb.com/bfs/archive/cover.jpg',duration:394,creatorId:'5294454',creatorName:'UP',views:10328558,danmaku:16222,publishedAt:1787386562,reason:'88万点赞'});
  expect(result.items[1].reason).toBe('已关注');
  const url=new URL(fetchMock.mock.calls[1][0]);
  expect(url.pathname).toBe('/x/web-interface/wbi/index/top/feed/rcmd');
  expect(Object.fromEntries(url.searchParams)).toMatchObject({fresh_idx:'3',fresh_idx_1h:'3',brush:'2',fetch_row:'1',ps:'20',web_location:'1430650'});
  expect(fetchMock.mock.calls[1][1].credentials).toBe('include');
  // The transmitted parameters, once decoded, must be exactly the signed ones.
  const {w_rid,...sent}=Object.fromEntries(url.searchParams);
  const query=Object.keys(sent).sort().map(name=>`${encodeURIComponent(name)}=${encodeURIComponent(sent[name])}`).join('&');
  expect(createHash('md5').update(query+'ea1db124af3c7062474693fa704f4ff8').digest('hex')).toBe(w_rid);
});
it('still shows generic recommendations when Chrome is signed out',async()=>{
  fetchMock.mockResolvedValueOnce(reply(-101,{isLogin:false,wbi_img})).mockResolvedValueOnce(reply(0,{item:[video('BV1a',{rcmd_reason:null,stat:null})]}));
  const result:any=await homeFeed({});
  expect(result).toMatchObject({loggedIn:false,page:1,nextPage:2});expect(result.accountName).toBeUndefined();
  expect(result.items).toEqual([expect.objectContaining({bvid:'BV1a',views:undefined,reason:undefined})]);
});
it('validates the batch number before any request',async()=>{
  for(const page of [0,1.5e4,'2'])await expect(homeFeed({page})).rejects.toMatchObject({code:'out_of_range'});
  expect(fetchMock).not.toHaveBeenCalled();
});
it('surfaces security checks and changed signing keys instead of returning an empty feed',async()=>{
  fetchMock.mockResolvedValueOnce(reply(0,{isLogin:true,wbi_img})).mockResolvedValueOnce(reply(-352,null));
  await expect(homeFeed({page:1})).rejects.toMatchObject({code:'verification_required'});
  fetchMock.mockReset();fetchMock.mockResolvedValueOnce(reply(0,{isLogin:true,wbi_img:{img_url:'',sub_url:''}}));
  await expect(homeFeed({page:1})).rejects.toMatchObject({code:'api_changed'});expect(fetchMock).toHaveBeenCalledTimes(1);
  fetchMock.mockReset();fetchMock.mockResolvedValueOnce({ok:false,status:412,json:async()=>({})});
  await expect(homeFeed({page:1})).rejects.toMatchObject({code:'api_unavailable'});
});

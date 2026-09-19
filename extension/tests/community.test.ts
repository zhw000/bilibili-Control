import {beforeEach,afterEach,expect,it,vi} from 'vitest';
import {community} from '../src/community';

const fetchMock=vi.fn();
const cookie=vi.fn();
const success=(data:unknown)=>({ok:true,json:async()=>({code:0,data})});
const reply=(id:string)=>({rpid_str:id,content:{message:'这是一条评论'},member:{mid:'42',uname:'UP',avatar:'//i0.hdslb.com/avatar.jpg'},ctime:123,like:5,rcount:2,replies:[]});
beforeEach(()=>{vi.stubGlobal('fetch',fetchMock);vi.stubGlobal('chrome',{cookies:{get:cookie}});fetchMock.mockReset();cookie.mockReset();});
afterEach(()=>vi.unstubAllGlobals());
it('reads folders for the actual Chrome account and does not export cookies',async()=>{
 fetchMock.mockResolvedValueOnce(success({isLogin:true,mid:42,uname:'账号'})).mockResolvedValueOnce(success({list:[{id:123,title:'我的收藏',media_count:7}]}));
 expect(await community('favorites.folders',{})).toEqual({accountName:'账号',items:[{id:'123',title:'我的收藏',count:7}]});
 expect(new URL(fetchMock.mock.calls[1][0]).searchParams.get('up_mid')).toBe('42');expect(cookie).not.toHaveBeenCalled();
 expect(fetchMock.mock.calls[0][1].credentials).toBe('include');
});
it('requires a browser login rather than showing an empty favorites page',async()=>{
 fetchMock.mockResolvedValue(success({isLogin:false}));await expect(community('favorites.folders',{})).rejects.toMatchObject({code:'login_required'});expect(fetchMock).toHaveBeenCalledTimes(1);
});
it('keeps favorites pagination when a page contains only non-video items',async()=>{
 fetchMock.mockResolvedValueOnce(success({isLogin:true,mid:42})).mockResolvedValueOnce(success({info:{media_count:30},has_more:true,medias:[{type:12,id:1,title:'音频'}]}));
 expect(await community('favorites.videos',{folderId:'123',page:1})).toMatchObject({items:[],nextPage:2});
});
it('marks invalid favorites and normalizes playable video metadata',async()=>{
 fetchMock.mockResolvedValueOnce(success({isLogin:true,mid:42})).mockResolvedValueOnce(success({info:{media_count:1},has_more:false,medias:[{type:2,bvid:'BV1test',title:'失效视频',cover:'http://i1.hdslb.com/cover.jpg@320w.avif',attr:9,upper:{mid:42,name:'UP'}}]}));
 const result:any=await community('favorites.videos',{folderId:'123'});
 expect(result.items[0]).toMatchObject({cover:'https://i1.hdslb.com/cover.jpg',creatorId:'42',unavailableReason:'视频已失效或不可播放'});expect(result.nextPage).toBeUndefined();
});
it('uses stable string reply IDs, deduplicates pins, and preserves pagination',async()=>{
 const item=reply('900719925474099312');
 fetchMock.mockResolvedValueOnce(success({aid:170001})).mockResolvedValueOnce(success({top_replies:[item],replies:[item,reply('2')],page:{count:40,size:20}}));
 const result:any=await community('comments.list',{bvid:'BV1test',order:'newest'});
 expect(result.items.map((x:any)=>x.id)).toEqual(['900719925474099312','2']);expect(result.nextPage).toBe(2);
 expect(new URL(fetchMock.mock.calls[1][0]).searchParams.get('sort')).toBe('0');
});
it('loads replies using their root ID without changing the current player',async()=>{
 fetchMock.mockResolvedValueOnce(success({aid:170001})).mockResolvedValueOnce(success({replies:[],page:{count:0,size:20}}));
 await community('comments.list',{bvid:'BV1test',root:'123',page:2});
 const url=new URL(fetchMock.mock.calls[1][0]);expect(url.pathname).toBe('/x/v2/reply/reply');expect(url.searchParams.get('root')).toBe('123');expect(url.searchParams.get('pn')).toBe('2');
});
it('posts a reply once with local CSRF and returns no credential',async()=>{
 fetchMock.mockResolvedValueOnce(success({isLogin:true,mid:42})).mockResolvedValueOnce(success({aid:170001})).mockResolvedValueOnce(success({reply:reply('456')}));cookie.mockResolvedValue({value:'test-csrf'});
 const result=await community('comments.add',{bvid:'BV1test',message:' 测试回复 ',root:'123',parent:'124'});
 const options=fetchMock.mock.calls[2][1];expect(options.method).toBe('POST');expect(options.body.get('message')).toBe('测试回复');expect(options.body.get('root')).toBe('123');expect(options.body.get('parent')).toBe('124');expect(options.body.get('csrf')).toBe('test-csrf');
 expect(JSON.stringify(result)).not.toContain('test-csrf');expect(fetchMock).toHaveBeenCalledTimes(3);
});
it('does not replay an uncertain comment submission',async()=>{
 fetchMock.mockResolvedValueOnce(success({isLogin:true,mid:42})).mockResolvedValueOnce(success({aid:170001})).mockRejectedValueOnce(new Error('network disconnected'));cookie.mockResolvedValue({value:'test-csrf'});
 await expect(community('comments.add',{bvid:'BV1test',message:'评论'})).rejects.toMatchObject({code:'comment_uncertain'});expect(fetchMock).toHaveBeenCalledTimes(3);
});
it('validates comment inputs before any requests and requires CSRF',async()=>{
 await expect(community('comments.add',{bvid:'BV1test',message:' '})).rejects.toMatchObject({code:'invalid_request'});
 await expect(community('comments.add',{bvid:'BV1test',message:'x'.repeat(1001)})).rejects.toMatchObject({code:'invalid_request'});
 await expect(community('comments.list',{bvid:'https://evil.test/'})).rejects.toMatchObject({code:'invalid_video'});expect(fetchMock).not.toHaveBeenCalled();
 fetchMock.mockResolvedValueOnce(success({isLogin:true,mid:42})).mockResolvedValueOnce(success({aid:170001}));cookie.mockResolvedValue(null);
 await expect(community('comments.add',{bvid:'BV1test',message:'评论'})).rejects.toMatchObject({code:'login_expired'});expect(fetchMock).toHaveBeenCalledTimes(2);
});
it('surfaces security challenges explicitly',async()=>{
 fetchMock.mockResolvedValue({ok:true,json:async()=>({code:-352,message:'风控'})});
 await expect(community('creator.profile',{creatorId:'42'})).rejects.toMatchObject({code:'verification_required'});
});
it('reads richer creator metadata using the fixed official endpoint',async()=>{
 fetchMock.mockResolvedValue(success({card:{name:'UP',sign:'介绍',fans:10,attention:2,face:'//i0.hdslb.com/avatar.jpg',level_info:{current_level:6},Official:{desc:'认证信息'}},archive_count:7,like_num:20}));
 expect(await community('creator.profile',{creatorId:'42'})).toMatchObject({id:'42',description:'介绍',followers:10,following:2,videoCount:7,likes:20,level:6,verified:'认证信息'});
});

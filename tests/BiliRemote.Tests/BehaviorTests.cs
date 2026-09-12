using BiliRemote.Core;
using Xunit;

namespace BiliRemote.Tests;
public sealed class BehaviorTests
{
    [Theory][InlineData("01:30",90)][InlineData("1:02:03",3723)][InlineData("120:00",7200)]
    public void ParsesTime(string value, double expected) => Assert.Equal(expected, Validation.ParseTime(value));
    [Theory][InlineData("1:60")][InlineData("-1:00")][InlineData("1:99:00")][InlineData("12")]
    public void RejectsInvalidTime(string value) => Assert.ThrowsAny<Exception>(()=>Validation.ParseTime(value));
    [Fact] public async Task DeduplicatesConcurrentRelativeCommands()
    {
        var ledger = new RequestLedger(); var executions = 0;
        var request = new Request(1,"one","seek",Wire.Element(new {delta=10}));
        async Task<Reply> Run() { Interlocked.Increment(ref executions); await Task.Delay(20); return Reply.Success("one",Wire.Element(new {time=20})); }
        await Task.WhenAll(Enumerable.Range(0,20).Select(_=>ledger.Run("phone",request,Run)));
        Assert.Equal(1,executions);
        var conflict = await ledger.Run("phone",request with {Params=Wire.Element(new {delta=20})},Run);
        Assert.Equal("id_conflict",conflict.Error?.Code);
    }
    [Fact] public async Task QueueDeduplicatesPagesAndEndedEvents()
    {
        var plays = new List<string>();
        var first = new VideoItem("BV1","One","https://www.bilibili.com/video/BV1");
        var second = first with {Bvid="BV2",Title="Two"};
        var queue = new PlaybackQueue((_,page)=>Task.FromResult(page==1 ? new PageResult<VideoItem>([first],1,2,2,2) : new PageResult<VideoItem>([first,second],2,2,2)),(video,_,_,_)=>{plays.Add(video.Bvid);return Task.CompletedTask;},_=>Task.CompletedTask);
        await queue.Start(new("creator","123"));
        var ended = new PlayerState(Bvid:"BV1",Ended:true,PlaybackId:queue.Snapshot.PlaybackId);
        await Task.WhenAll(queue.Ended(ended),queue.Ended(ended));
        Assert.Equal(new[]{"BV1","BV2"},plays); Assert.Equal(2,queue.Snapshot.Items.Count);
        var final = ended with {Bvid="BV2",PlaybackId=queue.Snapshot.PlaybackId};
        await queue.Ended(final); Assert.False(queue.Snapshot.Active);
    }
    [Fact] public async Task IntermediatePartDoesNotAdvanceQueue()
    {
        var queue = new PlaybackQueue((_,_)=>throw new NotSupportedException(),(_,_,_,_)=>Task.CompletedTask,_=>Task.CompletedTask);
        await queue.Start(new("manual",Items:[new("BV1","One","https://www.bilibili.com/video/BV1")]));
        await queue.Ended(new(Part:1,PartCount:2,Ended:true,PlaybackId:queue.Snapshot.PlaybackId)); Assert.True(queue.Snapshot.Active);
    }
    [Fact] public void RestoreNeverAutoplays()
    {
        var queue = new PlaybackQueue((_,_)=>throw new NotSupportedException(),(_,_,_,_)=>throw new Exception("must not play"),_=>Task.CompletedTask);
        queue.Restore(new(new("manual"),[new("BV1","One","https://www.bilibili.com/video/BV1")],0,null,true,false,null,"old"),new(CurrentTime:42));
        Assert.False(queue.Snapshot.Active); Assert.True(queue.Snapshot.CanResume);
    }
    [Fact] public async Task SkipsVideoUnavailableDuringInitialOpen()
    {
        var played = new List<string>();
        var first = new VideoItem("BV1", "Deleted", "https://www.bilibili.com/video/BV1");
        var queue = new PlaybackQueue((_,_)=>throw new NotSupportedException(),(video,_,_,_)=>
        {
            if(video.Bvid=="BV1")throw new RemoteException("video_unavailable","视频已删除");
            played.Add(video.Bvid);return Task.CompletedTask;
        },_=>Task.CompletedTask);
        await queue.Start(new("manual",Items:[first,first with{Bvid="BV2"}]));
        Assert.Equal(new[]{"BV2"},played);Assert.Equal(1,queue.Snapshot.Index);Assert.Equal("视频已删除",queue.Snapshot.Items[0].UnavailableReason);
    }
    [Fact] public async Task UnownedEndedEventDoesNotAdvance()
    {
        var queue = new PlaybackQueue((_,_)=>throw new NotSupportedException(),(_,_,_,_)=>Task.CompletedTask,_=>Task.CompletedTask);
        await queue.Start(new("manual",Items:[new("BV1","One","https://www.bilibili.com/video/BV1")]));
        await queue.Ended(new(Ended:true));Assert.True(queue.Snapshot.Active);
    }
    [Fact] public async Task FailedPaginationReleasesPlaybackOwnershipAndCanRetry()
    {
        var managed = false; var fail = true;
        var first = new VideoItem("BV1", "First", "https://www.bilibili.com/video/BV1");
        var queue = new PlaybackQueue((_, page) => page == 1
            ? Task.FromResult(new PageResult<VideoItem>([first], 1, 2, 2, 2))
            : fail ? throw new RemoteException("verification_required", "请完成验证")
            : Task.FromResult(new PageResult<VideoItem>([first with { Bvid = "BV2" }], 2, 2, 2)),
            (_, _, _, _) => Task.CompletedTask, value => { managed = value; return Task.CompletedTask; });
        await queue.Start(new("creator", "123"));
        await Assert.ThrowsAsync<RemoteException>(() => queue.Move(1));
        Assert.False(managed); Assert.False(queue.Snapshot.Active); Assert.Null(queue.Snapshot.PlaybackId);
        Assert.Equal("请完成验证", queue.Snapshot.Message);
        fail = false; await queue.Move(1);
        Assert.True(managed); Assert.Equal("BV2", queue.Snapshot.Items[queue.Snapshot.Index].Bvid);
    }
    [Theory][InlineData("https://www.bilibili.com/video/BV1",true)][InlineData("https://www.bilibili.com.evil.test/video/BV1",false)][InlineData("file:///etc/passwd",false)]
    public void RestrictsNavigation(string url,bool allowed)=>Assert.Equal(allowed,Validation.BilibiliUrl(url));
}

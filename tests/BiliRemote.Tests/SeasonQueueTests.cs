using BiliRemote.Core;
using Xunit;

namespace BiliRemote.Tests;
public sealed class SeasonQueueTests
{
    private static readonly VideoItem[] Episodes = Enumerable.Range(1, 3).Select(i => new VideoItem("ep"+i, "第 "+i+" 集", "https://www.bilibili.com/bangumi/play/ep"+i)).ToArray();
    [Fact] public async Task SeasonStartsAtSelectedEpisodeAndAdvancesExactlyOnce()
    {
        var played = new List<string>();
        var queue = new PlaybackQueue((_,_)=>Task.FromResult(new PageResult<VideoItem>(Episodes,1,1)), (item,_,_,_)=>{played.Add(item.Bvid);return Task.CompletedTask;}, _=>Task.CompletedTask);
        await queue.Start(new("season", Url:"https://www.bilibili.com/bangumi/play/ss10", StartBvid:"ep2"));
        Assert.Equal(1,queue.Snapshot.Index);
        var ended = new PlayerState(Bvid:"ep2", Ended:true, PlaybackId:queue.Snapshot.PlaybackId);
        await queue.Ended(ended);await queue.Ended(ended);
        Assert.Equal(new[]{"ep2","ep3"},played);
        await queue.Select("ep1");Assert.Equal("season",queue.Snapshot.Source?.Kind);
        Assert.Equal(0,queue.Snapshot.Index);
    }
    [Fact] public async Task InvalidSelectedEpisodeDoesNotStartAnotherEpisode()
    {
        var played = false;
        var queue = new PlaybackQueue((_,_)=>Task.FromResult(new PageResult<VideoItem>(Episodes,1,1)), (_,_,_,_)=>{played=true;return Task.CompletedTask;}, _=>Task.CompletedTask);
        var error=await Assert.ThrowsAsync<RemoteException>(()=>queue.Start(new("season", StartBvid:"ep999")));
        Assert.Equal("queue_changed",error.Code);Assert.False(played);Assert.False(queue.Snapshot.Active);
    }
    [Fact] public async Task EpisodeProgressSurvivesRestoreWithoutAutoplay()
    {
        var queue=new PlaybackQueue((_,_)=>Task.FromResult(new PageResult<VideoItem>(Episodes,1,1)), (_,_,_,_)=>Task.CompletedTask, _=>Task.CompletedTask);
        await queue.Start(new("season", StartBvid:"ep2"));
        var state=new PlayerState(Bvid:"ep2",CurrentTime:85,PlaybackId:queue.Snapshot.PlaybackId);
        queue.Observe(state);
        var resumed=new List<(string Id,double Time)>();
        var restored=new PlaybackQueue((_,_)=>throw new NotSupportedException(), (item,_,_,time)=>{resumed.Add((item.Bvid,time));return Task.CompletedTask;}, _=>Task.CompletedTask);
        restored.Restore(queue.Snapshot,state);Assert.Empty(resumed);
        await restored.Resume();Assert.Equal(("ep2",85d),Assert.Single(resumed));
    }
}

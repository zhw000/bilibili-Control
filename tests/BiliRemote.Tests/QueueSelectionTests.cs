using BiliRemote.Core;
using Xunit;

namespace BiliRemote.Tests;
public sealed class QueueSelectionTests
{
    [Fact] public async Task SelectingLoadedItemPreservesPlaylistAndRejectsOldEndEvent()
    {
        var videos = Enumerable.Range(1, 3).Select(i => new VideoItem("BV"+i, "Video "+i, "https://www.bilibili.com/video/BV"+i)).ToArray();
        var queue = new PlaybackQueue((_,_) => Task.FromResult(new PageResult<VideoItem>(videos,1,2,6,2)), (_,_,_,_)=>Task.CompletedTask, _=>Task.CompletedTask);
        await queue.Start(new("creator", "123"));
        var previousPlayback = queue.Snapshot.PlaybackId;
        await queue.Select("BV3");
        Assert.Equal(2, queue.Snapshot.Index); Assert.Equal("creator", queue.Snapshot.Source?.Kind);
        Assert.Equal(2, queue.Snapshot.NextPage); Assert.Equal(3, queue.Snapshot.Items.Count);
        await queue.Ended(new(Ended:true, PlaybackId:previousPlayback));
        Assert.Equal(2, queue.Snapshot.Index);
        await queue.Select("BV1"); Assert.Equal(0, queue.Snapshot.Index); Assert.True(queue.Snapshot.Active);
    }
    [Fact] public async Task OpeningWebsiteListReleasesQueueAndIgnoresPreviousEnd()
    {
        var calls = new List<bool>();
        var queue = new PlaybackQueue((_,_)=>throw new NotSupportedException(), (_,_,_,_)=>Task.CompletedTask, enabled=>{calls.Add(enabled);return Task.CompletedTask;});
        await queue.Start(new("manual", Items:[new("BV1","One","https://www.bilibili.com/video/BV1")]));
        var old = queue.Snapshot.PlaybackId;
        await queue.OpenSiteList(()=>Task.FromResult(new PlayerState(Bvid:"BV2")));
        await queue.Ended(new(Ended:true, PlaybackId:old));
        Assert.Empty(queue.Snapshot.Items);
        Assert.False(queue.Snapshot.CanResume);
        Assert.False(calls.Last());
        Assert.Equal("BV2",queue.LastState.Bvid);
    }

    [Fact] public async Task SelectingUnknownItemDoesNotStopCurrentPlayback()
    {
        var queue = new PlaybackQueue((_,_)=>throw new NotSupportedException(), (_,_,_,_)=>Task.CompletedTask, _=>Task.CompletedTask);
        await queue.Start(new("manual", Items:[new("BV1","One","https://www.bilibili.com/video/BV1")]));
        var before = queue.Snapshot;
        var error = await Assert.ThrowsAsync<RemoteException>(()=>queue.Select("BVStale"));
        Assert.Equal("queue_changed", error.Code); Assert.Equal(before, queue.Snapshot);
    }
}

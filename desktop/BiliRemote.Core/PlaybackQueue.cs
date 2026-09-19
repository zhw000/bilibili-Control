namespace BiliRemote.Core;

public sealed class PlaybackQueue
{
    private readonly SemaphoreSlim gate = new(1, 1);
    private readonly Func<QueueSource, int, Task<PageResult<VideoItem>>> load;
    private readonly Func<VideoItem, string, int, double, Task> play;
    private readonly Func<bool, Task> manage;
    private readonly List<VideoItem> items = [];
    private QueueSource? source;
    private int index = -1;
    private int? nextPage;
    private bool active;
    private string? playbackId;
    private string? message;
    private PlayerState lastState = new();
    private QueueSnapshot published = new(null, [], -1, null, false, false, null, null);
    public event Action? Changed;
    public PlaybackQueue(Func<QueueSource, int, Task<PageResult<VideoItem>>> load, Func<VideoItem, string, int, double, Task> play, Func<bool, Task> manage)
    { this.load = load; this.play = play; this.manage = manage; }

    public QueueSnapshot Snapshot => Volatile.Read(ref published);
    public PlayerState LastState => lastState;
    public void Restore(QueueSnapshot saved, PlayerState state)
    {
        source = saved.Source; items.AddRange(saved.Items); index = Math.Clamp(saved.Index, -1, items.Count - 1); nextPage = saved.NextPage;
        active = false; playbackId = null; lastState = state; message = index >= 0 ? "已恢复上次队列，点击继续播放" : null;
        Notify();
    }
    private void Notify()
    {
        Volatile.Write(ref published, new(source, items.ToArray(), index, nextPage, active, !active && index >= 0 && index < items.Count, message, playbackId));
        Changed?.Invoke();
    }
    public void Observe(PlayerState state) { if (state.PlaybackId == playbackId) lastState = state; }
    public async Task Start(QueueSource newSource)
    {
        await gate.WaitAsync();
        try
        {
            active = false; await manage(false);
            source = newSource; items.Clear(); index = -1; nextPage = null; playbackId = null; message = null;
            if (newSource.Kind == "manual") Append(newSource.Items ?? []);
            else {
                var pageNumber = 1;
                do {
                    var page = await load(newSource, pageNumber); Append(page.Items);
                    nextPage = page.NextPage is int following && following > pageNumber ? following : null;
                    if (items.Count > 0 || nextPage == null) break;
                    pageNumber = nextPage.Value;
                } while (true);
            }
            if (items.Count == 0) throw new RemoteException("empty_queue", "这个列表还没有可播放的视频");
            index = 0; await StartCurrent();
        }
        catch (Exception ex) { await Suspend(ex.Message); throw; }
        finally { gate.Release(); }
    }
    private void Append(IEnumerable<VideoItem> incoming)
    {
        var known = items.Select(x => x.Bvid).ToHashSet(StringComparer.Ordinal);
        foreach (var item in incoming) if (!string.IsNullOrEmpty(item.Bvid) && known.Add(item.Bvid)) items.Add(item);
    }
    private async Task StartCurrent(int part = 1, double time = 0)
    {
        while (index >= 0 && index < items.Count)
        {
            playbackId = Guid.NewGuid().ToString("N"); active = true; message = null;
            lastState = new(Bvid: items[index].Bvid, Part: part, CurrentTime: time, PlaybackId: playbackId);
            try { await manage(true); await play(items[index], playbackId, part, time); Notify(); return; }
            catch (RemoteException ex) when (ex.Code == "video_unavailable")
            {
                items[index] = items[index] with { UnavailableReason = ex.Message };
                if (await NextIndex()) { part = 1; time = 0; continue; }
                await Complete(); return;
            }
        }
    }
    private async Task<bool> NextIndex()
    {
        while (index + 1 >= items.Count && nextPage is int page && source != null)
        {
            var batch = await load(source, page); Append(batch.Items);
            nextPage = batch.NextPage is int following && following > page ? following : null;
        }
        if (index + 1 >= items.Count) return false;
        index++; return true;
    }
    private async Task Complete() { active = false; message = "已播放完全部视频"; playbackId = null; await manage(false); Notify(); }
    private async Task Suspend(string reason)
    {
        active = false; playbackId = null; message = reason;
        try { await manage(false); } catch { /* Preserve the original playback/catalogue error. */ }
        Notify();
    }
    public async Task Resume()
    {
        await gate.WaitAsync();
        try { if (index < 0) throw new RemoteException("empty_queue", "还没有可恢复的队列"); await StartCurrent(Math.Max(1, lastState.Part), Math.Max(0, lastState.CurrentTime)); }
        catch (Exception ex) { await Suspend(ex.Message); throw; }
        finally { gate.Release(); }
    }
    public async Task Stop(string? reason = null)
    {
        await gate.WaitAsync();
        try { active = false; playbackId = null; message = reason; await manage(false); Notify(); }
        finally { gate.Release(); }
    }
    public async Task Move(int direction, string? expectedPlaybackId = null)
    {
        await gate.WaitAsync();
        try
        {
            if (expectedPlaybackId != null && (!active || expectedPlaybackId != playbackId)) return;
            if (index < 0) throw new RemoteException("empty_queue", "播放队列为空");
            if (direction < 0) { index = Math.Max(0, index - 1); await StartCurrent(); return; }
            if (!await NextIndex()) { await Complete(); return; }
            await StartCurrent();
        }
        catch (Exception ex) { await Suspend(ex.Message); throw; }
        finally { gate.Release(); }
    }
    public async Task Ended(PlayerState state)
    {
        // The extension advances individual parts; this event is the final part only.
        if (state.Part < state.PartCount || string.IsNullOrEmpty(state.PlaybackId)) return;
        await Move(1, state.PlaybackId);
    }
    public async Task MarkUnavailable(PlayerState state)
    {
        await gate.WaitAsync();
        try
        {
            if (!active || state.PlaybackId != playbackId || index < 0) return;
            items[index] = items[index] with { UnavailableReason = state.ErrorMessage ?? "视频不可用" }; Notify();
        }
        finally { gate.Release(); }
        await Move(1, state.PlaybackId);
    }
    public async Task Select(string bvid)
    {
        await gate.WaitAsync();
        try
        {
            var selected = items.FindIndex(item => item.Bvid == bvid);
            if (selected < 0) throw new RemoteException("queue_changed", "该视频已不在当前队列，请刷新后重试");
            index = selected;
            try { await StartCurrent(); }
            catch (Exception ex) { await Suspend(ex.Message); throw; }
        }
        finally { gate.Release(); }
    }
}

using System.Collections.Concurrent;

namespace BiliRemote.Core;

// Shared across socket reconnects. Repeated relative commands must never execute twice.
public sealed class RequestLedger(int capacity = 512)
{
    private sealed record Entry(string Fingerprint, Lazy<Task<Reply>> Work);
    private readonly ConcurrentDictionary<string, Entry> entries = new();
    private readonly ConcurrentQueue<string> order = new();
    public Task<Reply> Run(string deviceId, Request request, Func<Task<Reply>> action)
    {
        var key = deviceId + ":" + request.Id;
        var fingerprint = request.Method + "\n" + request.Params.GetRawText();
        var candidate = new Entry(fingerprint, new(action, LazyThreadSafetyMode.ExecutionAndPublication));
        var entry = entries.GetOrAdd(key, candidate);
        if (entry.Fingerprint != fingerprint) return Task.FromResult(Reply.Failure(request.Id, "id_conflict", "同一请求编号不能用于不同操作"));
        if (ReferenceEquals(candidate, entry))
        {
            order.Enqueue(key);
            while (entries.Count > capacity && order.TryPeek(out var oldest) && entries.TryGetValue(oldest, out var old) && old.Work.IsValueCreated && old.Work.Value.IsCompleted)
            { order.TryDequeue(out _); entries.TryRemove(oldest, out _); }
        }
        return entry.Work.Value;
    }
}

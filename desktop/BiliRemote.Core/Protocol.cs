using System.Text.Json;
using System.Text.Json.Serialization;

namespace BiliRemote.Core;

public static class Wire
{
    public const int Version = 1;
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };
    public static JsonElement Element<T>(T value) => JsonSerializer.SerializeToElement(value, Json);
    public static T Decode<T>(JsonElement value) => value.Deserialize<T>(Json) ?? throw new RemoteException("invalid_request", "请求内容为空");
    public static string Text(this JsonElement value, string key, string fallback = "") => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var p) && p.ValueKind == JsonValueKind.String ? p.GetString() ?? fallback : fallback;
    public static double Number(this JsonElement value, string key, double fallback = 0) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var p) && p.ValueKind == JsonValueKind.Number && p.TryGetDouble(out var n) && double.IsFinite(n) ? n : fallback;
    public static bool Flag(this JsonElement value, string key, bool fallback = false) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var p) && (p.ValueKind is JsonValueKind.True or JsonValueKind.False) ? p.GetBoolean() : fallback;
}

public sealed record Request(int V, string Id, string Method, JsonElement Params);
public sealed record ErrorInfo(string Code, string Message);
public sealed record Reply(int V, string Id, bool Ok, JsonElement? Result = null, ErrorInfo? Error = null)
{
    public static Reply Success(string id, JsonElement result) => new(1, id, true, result);
    public static Reply Failure(string id, string code, string message) => new(1, id, false, Error: new(code, message));
}
public sealed record Push(int V, string Event, JsonElement Data);
public sealed class RemoteException(string code, string message) : Exception(message) { public string Code { get; } = code; }

public sealed record VideoItem(string Bvid, string Title, string Url, string? Cover = null, double? Duration = null, string? CreatorId = null, string? CreatorName = null, string? UnavailableReason = null);
public sealed record CreatorItem(string Id, string Name, string Url, string? Avatar = null, string? Description = null);
public sealed record CollectionItem(string Id, string Title, string Url, string? Cover = null, int? Count = null);
public sealed record PageResult<T>(IReadOnlyList<T> Items, int Page, int TotalPages, int? Total = null, int? NextPage = null);
public sealed record QueueSource(string Kind, string? CreatorId = null, string? Url = null, string Order = "newest", IReadOnlyList<VideoItem>? Items = null, string? FolderId = null, string? Keyword = null);
public sealed record QueueSnapshot(QueueSource? Source, IReadOnlyList<VideoItem> Items, int Index, int? NextPage, bool Active, bool CanResume, string? Message, string? PlaybackId);
public sealed record VideoQualityOption(string Id, string Label, string? Badge = null, bool Disabled = false);
public sealed record PlaybackQuality(IReadOnlyList<VideoQualityOption> Options, string? CurrentId = null, string? CurrentLabel = null, int? Width = null, int? Height = null);
public sealed record PlayerState(string Bvid = "", string Title = "", string Url = "", double CurrentTime = 0, double Duration = 0, bool Paused = true, bool Ended = false, int Part = 1, int PartCount = 1, double Volume = 1, bool Muted = false, double Rate = 1, bool Danmaku = true, bool Fullscreen = false, string? PlaybackId = null, string? ErrorCode = null, string? ErrorMessage = null, string? Cover = null, PlaybackQuality? Quality = null);
public sealed record SystemVolume(double Value, bool Muted, string DeviceName, bool Available = true);

public static class Validation
{
    public static void Request(Request request)
    {
        if (request.V != 1) throw new RemoteException("version_mismatch", "请更新手机 App 和电脑助手，使版本一致");
        if (string.IsNullOrWhiteSpace(request.Id) || request.Id.Length > 128 || string.IsNullOrWhiteSpace(request.Method)) throw new RemoteException("invalid_request", "请求缺少有效编号或方法");
        if (request.Params.ValueKind != JsonValueKind.Object) throw new RemoteException("invalid_request", "请求参数必须为对象");
    }
    public static double Range(JsonElement args, string key, double min, double max)
    {
        if (args.ValueKind != JsonValueKind.Object || !args.TryGetProperty(key, out var p) || p.ValueKind != JsonValueKind.Number || !p.TryGetDouble(out var number) || !double.IsFinite(number) || number < min || number > max) throw new RemoteException("out_of_range", $"{key} 必须在 {min}～{max} 之间");
        return number;
    }
    public static bool BilibiliUrl(string url) => Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Scheme == "https" && (uri.Host == "www.bilibili.com" || uri.Host == "space.bilibili.com" || uri.Host == "search.bilibili.com");
    public static double ParseTime(string text)
    {
        var parts = text.Trim().Split(':');
        if (parts.Length is < 2 or > 3 || parts.Any(p => p.Length == 0 || !p.All(char.IsAsciiDigit))) throw new FormatException("请输入 mm:ss 或 hh:mm:ss");
        var values = parts.Select(p => int.Parse(p, System.Globalization.CultureInfo.InvariantCulture)).ToArray();
        if (values[^1] >= 60 || (values.Length == 3 && values[1] >= 60)) throw new FormatException("秒和小时格式中的分钟必须小于 60");
        return values.Aggregate(0d, (total, n) => total * 60 + n);
    }
}

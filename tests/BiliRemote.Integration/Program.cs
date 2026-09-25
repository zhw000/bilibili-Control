using System.IO.Pipes;
using System.Net;
using System.Net.Http.Json;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using BiliRemote.Core;
using BiliRemote.Desktop;
using BiliRemote.Host;

if (args.Length == 2 && args[0] == "--native") { await NativeFramingTest.Run(args[1]); return; }

var root = Path.GetFullPath(Path.Combine(Environment.CurrentDirectory, "artifacts", "integration", Guid.NewGuid().ToString("N")));
Directory.CreateDirectory(root);
var listener = new TcpListener(IPAddress.Loopback, 0); listener.Start(); var port = ((IPEndPoint)listener.LocalEndpoint).Port; listener.Stop();
Environment.SetEnvironmentVariable("BILIREMOTE_DATA_DIR", root);
Environment.SetEnvironmentVariable("BILIREMOTE_BIND", "127.0.0.1");
Environment.SetEnvironmentVariable("BILIREMOTE_PORT", port.ToString());
Environment.SetEnvironmentVariable("BILIREMOTE_PIPE", "BiliRemote.Test." + Guid.NewGuid().ToString("N"));
var checks = new List<string>();
void Check(bool value, string name) { if (!value) throw new Exception("FAILED: " + name); checks.Add(name); Console.WriteLine("PASS " + name); }
using var server = new RemoteServer();
await server.Start();
using var browser = new BrowserFixture(); await browser.Connect();
for (var attempt = 0; attempt < 100 && !server.BrowserConnected; attempt++) await Task.Delay(20);
Check(server.BrowserConnected, "current-user native pipe connected");
using var http = new HttpClient(new HttpClientHandler { ServerCertificateCustomValidationCallback = (_, cert, _, _) => cert?.GetCertHashString(HashAlgorithmName.SHA256).Equals(server.Security.Fingerprint, StringComparison.OrdinalIgnoreCase) == true });
var pairUrl = $"https://127.0.0.1:{port}/api/v1/pair";
var descriptor = server.Security.Begin("127.0.0.1", port);
var wrong = await http.PostAsJsonAsync(pairUrl, new { pairingToken = "invalid", deviceName = "Test phone" });
Check(wrong.StatusCode == HttpStatusCode.Forbidden, "invalid pairing token rejected");
var response = await http.PostAsJsonAsync(pairUrl, new { descriptor.PairingToken, deviceName = "Test phone" });
response.EnsureSuccessStatusCode();
var pairing = await response.Content.ReadFromJsonAsync<JsonElement>();
var token = pairing.Text("accessToken"); var deviceId = pairing.Text("deviceId");
Check(token.Length >= 40, "TLS pairing issued a device credential");
var replay = await http.PostAsJsonAsync(pairUrl, new { descriptor.PairingToken, deviceName = "Replay" });
Check(replay.StatusCode == HttpStatusCode.Forbidden, "pairing token is single-use");
var rejected = false;
try { using var invalid = await PhoneFixture.Connect(port, "bad", server.Security.Fingerprint); } catch (WebSocketException) { rejected = true; }
Check(rejected, "unauthenticated WebSocket rejected");
PhoneFixture phone = await PhoneFixture.Connect(port, token, server.Security.Fingerprint);
var snapshot = await phone.NextEvent(); Check(snapshot.GetProperty("data").Flag("browserConnected"), "initial snapshot reports browser state");
var opened = await phone.Request("queue.start", new { kind = "creator", creatorId = "123", order = "newest" });
Check(opened.Flag("ok") && server.Queue.Snapshot.Items.Count == 2, "queue loaded first catalog page");
var requestId = "relative-command-once";
await phone.Request("player.command", new { action = "seekBy", value = 10 }, requestId);
await phone.Request("player.command", new { action = "seekBy", value = 10 }, requestId);
Check(browser.RelativeCommands == 1, "duplicate relative command executed once end-to-end");
var conflict = await phone.Request("player.command", new { action = "seekBy", value = 20 }, requestId);
Check(conflict.GetProperty("error").Text("code") == "id_conflict", "conflicting request ID rejected");
var boundary = await phone.Request("system.volume", new { value = 1.1 });
Check(boundary.GetProperty("error").Text("code") == "out_of_range", "system-volume range enforced before hardware access");
var qualityTarget = browser.State;
var qualityReply = await phone.Request("player.command", new { action = "quality", value = "64", bvid = qualityTarget.Bvid, part = qualityTarget.Part }, "quality-once");
await phone.Request("player.command", new { action = "quality", value = "64", bvid = qualityTarget.Bvid, part = qualityTarget.Part }, "quality-once");
Check(qualityReply.Flag("ok") && qualityReply.GetProperty("result").GetProperty("quality").Text("currentId") == "64" && browser.QualityCommands == 1 && browser.LastQuality.Text("bvid") == qualityTarget.Bvid && browser.LastQuality.Number("part") == qualityTarget.Part, "quality command roundtrip preserves target and is deduplicated");
var qualitySnapshot = await phone.Request("snapshot", new { });
Check(qualitySnapshot.GetProperty("result").GetProperty("player").GetProperty("quality").GetProperty("options").GetArrayLength() == 2 && server.Queue.Snapshot.Index == 0 && browser.State.CurrentTime == qualityTarget.CurrentTime, "quality choices survive host snapshots without changing progress or queue");
var ended = browser.State with { Ended = true, Part = 1, PartCount = 1 };
await browser.Event("player.ended", ended); await browser.Event("player.ended", ended);
await WaitFor(() => server.Queue.Snapshot.Index == 1);
Check(browser.OpenedVideos.Count == 2, "duplicate end event advanced once");
await browser.Event("player.ended", browser.State with { Ended = true });
await WaitFor(() => server.Queue.Snapshot.Index == 2);
Check(server.Queue.Snapshot.Items.Count == 3, "lazy next page appended without duplicates");
phone.Dispose();
await browser.Event("player.changed", browser.State with { CurrentTime = 45 });
phone = await PhoneFixture.Connect(port, token, server.Security.Fingerprint);
var reconnected = await phone.NextEvent();
Check(reconnected.GetProperty("data").GetProperty("queue").GetProperty("index").GetInt32() == 2, "phone reconnect preserves desktop queue");
await phone.Request("player.command", new { action = "seekBy", value = 10 }, requestId);
Check(browser.RelativeCommands == 1, "deduplication survives phone reconnect");
var beforeRelated = browser.State;
var related = await phone.Request("player.related", new { bvid = beforeRelated.Bvid });
Check(related.Flag("ok") && related.GetProperty("result").GetProperty("items").GetArrayLength() == 1 && browser.State == beforeRelated, "related videos roundtrip leaves playback unchanged");
var selection = await phone.Request("queue.select", new { bvid = "BV1test" });
Check(selection.Flag("ok") && server.Queue.Snapshot.Index == 0 && server.Queue.Snapshot.Items.Count == 3 && server.Queue.Snapshot.Source?.Kind == "creator", "inline selection preserves creator playlist");
foreach (var method in new[] { "creator.profile", "favorites.folders", "comments.list" })
{
    var before = browser.State;
    var result = await phone.Request(method, new { creatorId = "123", bvid = before.Bvid });
    Check(result.Flag("ok") && result.GetProperty("result").Text("method") == method && browser.State == before, $"{method} roundtrip preserves playback");
}
await phone.Request("comments.add", new { bvid = browser.State.Bvid, message = "Fixture only" }, "comment-once");
await phone.Request("comments.add", new { bvid = browser.State.Bvid, message = "Fixture only" }, "comment-once");
Check(browser.CommentSubmissions == 1, "duplicate comment submission is forwarded exactly once");
var favorites = await phone.Request("queue.start", new { kind = "favorites", folderId = "123", keyword = "test" });
Check(favorites.Flag("ok") && server.Queue.Snapshot.Source?.FolderId == "123" && browser.LastCatalog.Text("keyword") == "test", "favorite queue preserves folder and search parameters");
await phone.Request("queue.next", new { });
await phone.Request("queue.next", new { });
Check(server.Queue.Snapshot.Index == 2 && browser.LastCatalog.Number("page") == 2, "favorite queue paginates automatically");
var seconds = args.Length == 2 && args[0] == "--soak-seconds" ? int.Parse(args[1]) : 0;
var start = DateTimeOffset.UtcNow;
for (var tick = 0; tick < seconds; tick++)
{
    await Task.Delay(1000);
    await browser.Event("player.changed", browser.State with { CurrentTime = tick % 600 });
    if (tick % 10 == 0) { var state = await phone.Request("snapshot", new { }); if (!state.Flag("ok")) throw new Exception("Snapshot failed during soak"); }
    if (tick > 0 && tick % 60 == 0)
    {
        phone.Dispose(); phone = await PhoneFixture.Connect(port, token, server.Security.Fingerprint); await phone.NextEvent();
        Console.WriteLine($"SOAK {tick}/{seconds}s: reconnected; browser pipe and queue remain active");
    }
}
if (seconds > 0) Check((DateTimeOffset.UtcNow - start).TotalSeconds >= seconds, $"{seconds}-second transport soak completed with periodic phone reconnects");
server.Revoke(deviceId);
await Task.Delay(100);
rejected = false; try { using var revoked = await PhoneFixture.Connect(port, token, server.Security.Fingerprint); } catch (WebSocketException) { rejected = true; }
Check(rejected, "revoked device cannot reconnect");
phone.Dispose();
File.WriteAllText(Path.Combine(root, "result.json"), JsonSerializer.Serialize(new { checks, completedAt = DateTimeOffset.UtcNow, soakSeconds = seconds, note = "Real Windows TLS/WebSocket/native pipe; simulated phone and browser. Not iPhone or live-page acceptance." }, Wire.Json));
Console.WriteLine($"INTEGRATION COMPLETE: {checks.Count} checks. Report: {Path.Combine(root, "result.json")}");

static async Task WaitFor(Func<bool> test) { for (var attempt = 0; attempt < 200; attempt++) { if (test()) return; await Task.Delay(25); } throw new TimeoutException("Queue did not reach expected state"); }

sealed class PhoneFixture(ClientWebSocket socket) : IDisposable
{
    public static async Task<PhoneFixture> Connect(int port, string token, string fingerprint)
    {
        var socket = new ClientWebSocket();
        socket.Options.SetRequestHeader("Authorization", "Bearer " + token);
        socket.Options.RemoteCertificateValidationCallback = (_, cert, _, _) => cert?.GetCertHashString(HashAlgorithmName.SHA256).Equals(fingerprint, StringComparison.OrdinalIgnoreCase) == true;
        try { await socket.ConnectAsync(new Uri($"wss://127.0.0.1:{port}/api/v1/ws"), CancellationToken.None); return new(socket); } catch { socket.Dispose(); throw; }
    }
    private async Task<JsonElement> Receive()
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10)); using var stream = new MemoryStream();
        var buffer = new byte[65536]; WebSocketReceiveResult result;
        do { result = await socket.ReceiveAsync(buffer, timeout.Token); if (result.MessageType == WebSocketMessageType.Close) throw new IOException("Socket closed"); await stream.WriteAsync(buffer.AsMemory(0, result.Count), timeout.Token); } while (!result.EndOfMessage);
        using var doc = JsonDocument.Parse(stream.ToArray()); return doc.RootElement.Clone();
    }
    public async Task<JsonElement> NextEvent() { while (true) { var response = await Receive(); if (response.Text("event") == "snapshot") return response; } }
    public async Task<JsonElement> Request(string method, object args, string? id = null)
    {
        id ??= Guid.NewGuid().ToString("N");
        var request = new Request(1, id, method, Wire.Element(args));
        await socket.SendAsync(JsonSerializer.SerializeToUtf8Bytes(request, Wire.Json), WebSocketMessageType.Text, true, CancellationToken.None);
        while (true) { var response = await Receive(); if (response.Text("id") == id) return response; }
    }
    public void Dispose() { socket.Abort(); socket.Dispose(); }
}
sealed class BrowserFixture : IDisposable
{
    private readonly NamedPipeClientStream pipe = new(".", DesktopPaths.PipeName, PipeDirection.InOut, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
    private readonly SemaphoreSlim sendGate = new(1, 1);
    private StreamWriter? writer;
    public PlayerState State { get; private set; } = new();
    public int RelativeCommands { get; private set; }
    public int CommentSubmissions { get; private set; }
    public int QualityCommands { get; private set; }
    public JsonElement LastQuality { get; private set; }
    public JsonElement LastCatalog { get; private set; }
    public List<string> OpenedVideos { get; } = [];
    public async Task Connect()
    {
        await pipe.ConnectAsync(10000); writer = new(pipe, new UTF8Encoding(false), 4096, true) { AutoFlush = true };
        _ = Task.Run(async () =>
        {
            using var reader = new StreamReader(pipe, new UTF8Encoding(false), false, 4096, true);
            try
            {
                while (await reader.ReadLineAsync() is { } line)
                {
                    var request = JsonSerializer.Deserialize<Request>(line, Wire.Json)!; object result;
                    switch (request.Method)
                    {
                        case "creator.videos":
                        case "favorites.videos":
                            LastCatalog = request.Params.Clone();
                            var first = new VideoItem("BV1test", "One", "https://www.bilibili.com/video/BV1test/");
                            var second = first with { Bvid = "BV2test", Title = "Two" }; var third = first with { Bvid = "BV3test", Title = "Three" };
                            result = request.Params.Number("page") == 1 ? new PageResult<VideoItem>([first, second], 1, 2, 3, 2) : new PageResult<VideoItem>([second, third], 2, 2, 3); break;
                        case "player.open":
                            var video = Wire.Decode<VideoItem>(request.Params.GetProperty("video"));
                            State = new(Bvid: video.Bvid, Title: video.Title, Url: video.Url, Duration: 600, Paused: false, PlaybackId: request.Params.Text("playbackId"));
                            OpenedVideos.Add(video.Bvid); result = State; break;
                        case "player.command":
                            if (request.Params.Text("action") == "quality") { QualityCommands++; LastQuality = request.Params.Clone(); State = State with { Quality = new([new("80", "1080P 高清"), new("64", "720P 准高清")], request.Params.Text("value"), "720P 准高清", 1280, 720) }; }
                            if (request.Params.Text("action") == "seekBy") { RelativeCommands++; State = State with { CurrentTime = State.CurrentTime + request.Params.Number("value") }; }
                            result = State; break;
                        case "player.related":
                            result = new { bvid = State.Bvid, items = new[] { new VideoItem("BVRelated", "Related", "https://www.bilibili.com/video/BVRelated/") } }; break;
                        case "creator.profile": case "favorites.folders": case "comments.list": result = new { method = request.Method }; break;
                        case "comments.add": CommentSubmissions++; result = new { message = "Fixture only" }; break;
                        default: result = State; break;
                    }
                    await Send(Reply.Success(request.Id, Wire.Element(result)));
                }
            }
            catch (Exception ex) when (ex is IOException or ObjectDisposedException) { }
        });
    }
    public Task Event(string name, PlayerState state) { State = state; return Send(new Push(1, name, Wire.Element(state))); }
    private async Task Send(object value) { await sendGate.WaitAsync(); try { await writer!.WriteLineAsync(JsonSerializer.Serialize(value, Wire.Json)); } finally { sendGate.Release(); } }
    public void Dispose() { pipe.Dispose(); }
}

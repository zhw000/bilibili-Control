using System.Collections.Concurrent;
using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using BiliRemote.Core;
using BiliRemote.Desktop;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace BiliRemote.Host;
public sealed class RemoteServer:IDisposable
{
    private sealed class Peer(string deviceId,WebSocket socket):IDisposable
    {
        public string DeviceId{get;}=deviceId;
        public WebSocket Socket{get;}=socket;
        private readonly SemaphoreSlim sendGate=new(1,1);
        public async Task Send(object message)
        {
            using var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(5));
            try {await sendGate.WaitAsync(timeout.Token);try{if(Socket.State==WebSocketState.Open)await Socket.SendAsync(JsonSerializer.SerializeToUtf8Bytes(message,Wire.Json),WebSocketMessageType.Text,true,timeout.Token);}finally{sendGate.Release();}}
            catch(Exception){Socket.Abort();}
        }
        public void Dispose()=>Socket.Dispose();
    }
    private readonly NativeBridge bridge=new();
    private readonly AudioService audio=new();
    private readonly RequestLedger ledger=new();
    private readonly ConcurrentDictionary<Guid,Peer> peers=new();
    private readonly CancellationTokenSource lifetime=new();
    private readonly object saveGate=new();
    private readonly string queuePath;
    private DateTimeOffset savedAt=DateTimeOffset.MinValue;
    private WebApplication? app;
    private PlayerState player=new();
    private string? message;
    public SecurityStore Security{get;}=new();
    public PlaybackQueue Queue{get;}
    public bool BrowserConnected=>bridge.Connected;
    public int PhoneCount=>peers.Count;
    public int Port{get;}=int.TryParse(Environment.GetEnvironmentVariable("BILIREMOTE_PORT"),out var port)?port:33391;
    public string Address{get;}=Environment.GetEnvironmentVariable("BILIREMOTE_BIND")??SecurityStore.Addresses().FirstOrDefault()?.ToString()??"127.0.0.1";
    public event Action? Changed;
    public RemoteServer()
    {
        queuePath=Path.Combine(DesktopPaths.DataDirectory,"queue.json");
        Queue=new(LoadPage,async(video,id,part,time)=>{var state=await bridge.Call("player.open",new{video,playbackId=id,part,time});player=Wire.Decode<PlayerState>(state);},async enabled=>{if(bridge.Connected)await bridge.Call("player.manage",new{enabled});});
        try{if(File.Exists(queuePath)){using var doc=JsonDocument.Parse(File.ReadAllText(queuePath));Queue.Restore(Wire.Decode<QueueSnapshot>(doc.RootElement.GetProperty("queue")),Wire.Decode<PlayerState>(doc.RootElement.GetProperty("player")));player=Queue.LastState with{Paused=true,PlaybackId=null};}}catch(Exception){message="上次队列文件无法读取，已启动新会话";}
        Queue.Changed+=()=>{Save(true);Publish();};
        bridge.ConnectionChanged+=connected=>{if(!connected){player=player with{Paused=true};_ = Queue.Stop("Chrome 已断开，连接后可继续播放");}Publish();};
        bridge.Event+=(name,data)=>_ = HandleEvent(name,data);
    }
    private object Snapshot()=>new{computerName=Environment.MachineName,browserConnected=bridge.Connected,player,queue=Queue.Snapshot,systemVolume=audio.State,message};
    public async Task Start()
    {
        var builder=WebApplication.CreateSlimBuilder();builder.Logging.ClearProviders();
        builder.WebHost.ConfigureKestrel(options=>{options.Limits.MaxRequestBodySize=1024*1024;options.Listen(IPAddress.Parse(Address),Port,listen=>listen.UseHttps(Security.Certificate));});
        app=builder.Build();app.UseWebSockets(new(){KeepAliveInterval=TimeSpan.FromSeconds(20)});
        app.MapPost("/api/v1/pair",async(HttpContext context)=>
        {
            try{var args=await JsonSerializer.DeserializeAsync<JsonElement>(context.Request.Body,Wire.Json,context.RequestAborted);var result=Security.Pair(args.Text("pairingToken"),args.Text("deviceName","iPhone"));Changed?.Invoke();return Results.Json(result,Wire.Json);}
            catch(RemoteException ex){return Results.Json(new{error=new ErrorInfo(ex.Code,ex.Message)},Wire.Json,statusCode:403);}
            catch(JsonException){return Results.BadRequest();}
        });
        app.Map("/api/v1/ws",async(HttpContext context)=>
        {
            var authorization=context.Request.Headers.Authorization.ToString();var token=authorization.StartsWith("Bearer ",StringComparison.Ordinal)?authorization[7..]:"";
            var device=Security.Authenticate(token);
            if(device==null){context.Response.StatusCode=401;return;}
            if(!context.WebSockets.IsWebSocketRequest){context.Response.StatusCode=400;return;}
            var socket=await context.WebSockets.AcceptWebSocketAsync();await Serve(device,socket,context.RequestAborted);
        });
        await app.StartAsync(lifetime.Token);bridge.Start();audio.Refresh();_ = PollAudio();
    }
    private async Task Serve(string deviceId,WebSocket socket,CancellationToken cancellation)
    {
        var id=Guid.NewGuid();using var peer=new Peer(deviceId,socket);peers[id]=peer;Changed?.Invoke();
        await peer.Send(new Push(1,"snapshot",Wire.Element(Snapshot())));
        try
        {
            var buffer=new byte[16384];
            while(socket.State==WebSocketState.Open&&!cancellation.IsCancellationRequested)
            {
                using var bytes=new MemoryStream();WebSocketReceiveResult received;
                do{received=await socket.ReceiveAsync(buffer,cancellation);if(received.MessageType==WebSocketMessageType.Close)return;if(received.MessageType!=WebSocketMessageType.Text||bytes.Length+received.Count>1024*1024)throw new InvalidDataException();await bytes.WriteAsync(buffer.AsMemory(0,received.Count),cancellation);}while(!received.EndOfMessage);
                Request request;
                try {request=JsonSerializer.Deserialize<Request>(bytes.ToArray(),Wire.Json)??throw new JsonException();Validation.Request(request);}
                catch(Exception ex) when(ex is JsonException or RemoteException){await peer.Send(Reply.Failure("invalid", "invalid_request", "请求格式无效"));continue;}
                _ = Respond(peer,deviceId,request);
            }
        }
        catch(Exception ex) when(ex is WebSocketException or OperationCanceledException or IOException or InvalidDataException){ }
        finally{peers.TryRemove(id,out _);Changed?.Invoke();}
    }
    private async Task Respond(Peer peer,string deviceId,Request request)
    {
        var reply=await ledger.Run(deviceId,request,async()=>
        {
            try{return Reply.Success(request.Id,await Dispatch(request));}
            catch(RemoteException ex){return Reply.Failure(request.Id,ex.Code,ex.Message);}
            catch(Exception ex){return Reply.Failure(request.Id,"operation_failed",ex.Message);}
        });
        await peer.Send(reply);
    }
    private async Task<JsonElement> Dispatch(Request request)
    {
        Validation.Request(request);var p=request.Params;
        switch(request.Method)
        {
            case "snapshot":return Wire.Element(Snapshot());
            case "system.volume":return Wire.Element(audio.Set(value:Validation.Range(p,"value",0,1)));
            case "system.mute":if(!p.TryGetProperty("value",out var mute)||mute.ValueKind is not (JsonValueKind.True or JsonValueKind.False))throw new RemoteException("invalid_request","静音状态必须为布尔值");return Wire.Element(audio.Set(mute:mute.GetBoolean()));
            case "queue.start":{var source=Wire.Decode<QueueSource>(p);if(source.Kind is not("manual" or "creator" or "collection"))throw new RemoteException("invalid_request","未知队列来源");if(source.Kind=="manual"&&source.Items?.Any(v=>!Validation.BilibiliUrl(v.Url))==true)throw new RemoteException("invalid_url","视频地址无效");await Queue.Start(source);return Wire.Element(Queue.Snapshot);}
            case "queue.next":await Queue.Move(1);return Wire.Element(Queue.Snapshot);
            case "queue.previous":await Queue.Move(-1);return Wire.Element(Queue.Snapshot);
            case "queue.resume":await Queue.Resume();return Wire.Element(Queue.Snapshot);
            case "queue.stop":await Queue.Stop("已停止自动连播");return Wire.Element(Queue.Snapshot);
            case "player.open":{var video=Wire.Decode<VideoItem>(p.GetProperty("video"));await Queue.Start(new("manual",Items:[video]));return Wire.Element(Queue.Snapshot);}
            case "tabs.select":await Queue.Stop("已切换控制标签页");var selected=await bridge.Call(request.Method,p);player=Wire.Decode<PlayerState>(selected);Publish();return selected;
            case "player.command":{var result=await bridge.Call(request.Method,p);player=Wire.Decode<PlayerState>(result);Queue.Observe(player);Publish();return result;}
            case "tabs.list":case "search":case "creator.videos":case "creator.collections":case "collection.videos":return await bridge.Call(request.Method,p);
            default:throw new RemoteException("unknown_method","不支持的操作");
        }
    }
    private async Task<PageResult<VideoItem>> LoadPage(QueueSource source,int page)
    {
        var result=source.Kind=="creator"?await bridge.Call("creator.videos",new{source.CreatorId,source.Order,page}):await bridge.Call("collection.videos",new{source.Url,page});
        return Wire.Decode<PageResult<VideoItem>>(result);
    }
    private async Task HandleEvent(string name,JsonElement data)
    {
        try
        {
            switch(name)
            {
                case "player.changed":player=Wire.Decode<PlayerState>(data);Queue.Observe(player);Save(false);break;
                case "player.ended":await Queue.Ended(Wire.Decode<PlayerState>(data));break;
                case "player.error":player=Wire.Decode<PlayerState>(data);if(player.ErrorCode=="video_unavailable")await Queue.MarkUnavailable(player);else await Queue.Stop(player.ErrorMessage??"请检查电脑网页");break;
                case "target.closed":await Queue.Stop("播放标签页已关闭");player=new();break;
                case "target.navigated":await Queue.Stop("电脑上已手动切换视频，自动连播已停止");break;
            }
        }
        catch(Exception ex){message=ex.Message;}
        Publish();
    }
    private async Task PollAudio()
    {
        using var timer=new PeriodicTimer(TimeSpan.FromSeconds(1));
        try{while(await timer.WaitForNextTickAsync(lifetime.Token)){var previous=audio.State;audio.Refresh();if(previous!=audio.State)Publish();}}
        catch(OperationCanceledException){ }
    }
    private void Publish(){Changed?.Invoke();var push=new Push(1,"snapshot",Wire.Element(Snapshot()));foreach(var peer in peers.Values)_ = peer.Send(push);}
    private void Save(bool force)
    {
        lock(saveGate)
        {
            if(!force&&DateTimeOffset.UtcNow-savedAt<TimeSpan.FromSeconds(5))return;
            try{File.WriteAllText(queuePath+".tmp",JsonSerializer.Serialize(new{queue=Queue.Snapshot,player=Queue.LastState},Wire.Json));File.Move(queuePath+".tmp",queuePath,true);savedAt=DateTimeOffset.UtcNow;}catch(IOException){ }
        }
    }
    public void Revoke(string deviceId){Security.Revoke(deviceId);foreach(var peer in peers.Values.Where(p=>p.DeviceId==deviceId))peer.Socket.Abort();Changed?.Invoke();}
    public void Dispose(){Save(true);lifetime.Cancel();foreach(var peer in peers.Values)peer.Socket.Abort();bridge.Dispose();audio.Dispose();if(app!=null)_ = app.DisposeAsync();}
}

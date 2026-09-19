using System.Collections.Concurrent;
using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using BiliRemote.Core;
using BiliRemote.Desktop;

namespace BiliRemote.Host;
public sealed class NativeBridge : IDisposable
{
    private readonly CancellationTokenSource lifetime=new();
    private readonly SemaphoreSlim writeGate=new(1,1);
    private readonly ConcurrentDictionary<string,TaskCompletionSource<JsonElement>> pending=new();
    private StreamWriter? writer;
    public bool Connected {get;private set;}
    public event Action<bool>? ConnectionChanged;
    public event Action<string,JsonElement>? Event;
    public void Start()=>_ = Task.Run(Listen);
    private async Task Listen()
    {
        while(!lifetime.IsCancellationRequested)
        {
            try
            {
                await using var pipe=new NamedPipeServerStream(DesktopPaths.PipeName,PipeDirection.InOut,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous|PipeOptions.CurrentUserOnly);
                await pipe.WaitForConnectionAsync(lifetime.Token);
                using var reader=new StreamReader(pipe,new UTF8Encoding(false),false,4096,true);
                using var localWriter=new StreamWriter(pipe,new UTF8Encoding(false),4096,true){AutoFlush=true};writer=localWriter;
                Connected=true;ConnectionChanged?.Invoke(true);
                while(await reader.ReadLineAsync(lifetime.Token) is { } line)
                {
                    if(line.Length>1024*1024)throw new InvalidDataException("Native message too large");
                    using var document=JsonDocument.Parse(line);var root=document.RootElement;
                    var id=root.Text("id");
                    if(id.Length>0&&pending.TryRemove(id,out var promise))
                    {
                        if(root.Flag("ok")&&root.TryGetProperty("result",out var result))promise.TrySetResult(result.Clone());
                        else {var error=root.GetProperty("error");promise.TrySetException(new RemoteException(error.Text("code","extension_error"),error.Text("message","扩展操作失败")));}
                    }
                    else if(root.TryGetProperty("event",out var name)&&root.TryGetProperty("data",out var data))Event?.Invoke(name.GetString()??"",data.Clone());
                }
            }
            catch(OperationCanceledException) when(lifetime.IsCancellationRequested) {break;}
            catch(Exception) { /* Disconnect is exposed as state, never as an unobserved task. */ }
            finally
            {
                writer=null;Connected=false;ConnectionChanged?.Invoke(false);
                foreach(var pair in pending)if(pending.TryRemove(pair.Key,out var promise))promise.TrySetException(new RemoteException("browser_disconnected","Chrome 扩展已断开，请打开 Chrome 并检查扩展"));
            }
            try{await Task.Delay(500,lifetime.Token);}catch(OperationCanceledException){break;}
        }
    }
    public async Task<JsonElement> Call(string method,object parameters)
    {
        if(!Connected||writer==null)throw new RemoteException("browser_disconnected","请先打开 Chrome 并连接哔哩遥控扩展");
        var id=Guid.NewGuid().ToString("N");var promise=new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);pending[id]=promise;
        try
        {
            await writeGate.WaitAsync(lifetime.Token);
            try {if(writer==null)throw new RemoteException("browser_disconnected","Chrome 扩展已断开");await writer.WriteLineAsync(JsonSerializer.Serialize(new Request(1,id,method,Wire.Element(parameters)),Wire.Json));}
            finally{writeGate.Release();}
            return await promise.Task.WaitAsync(TimeSpan.FromSeconds(method is "search" or "creator.videos" or "creator.collections" or "collection.videos" or "comments.add"?75:35),lifetime.Token);
        }
        catch(TimeoutException){throw new RemoteException("browser_timeout","浏览器响应超时，请查看电脑网页后重试");}
        finally {pending.TryRemove(id,out _);}
    }
    public void Dispose(){lifetime.Cancel();writer?.Dispose();lifetime.Dispose();}
}

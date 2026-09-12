using System.Buffers.Binary;
using System.IO.Pipes;
using System.Text;
using BiliRemote.Desktop;

// stdout is exclusively Chrome's length-prefixed protocol, never diagnostics.
if (args.Length == 0 || args[0] != $"chrome-extension://{DesktopPaths.ExtensionId}/") return 2;
try
{
    using var pipe = new NamedPipeClientStream(".", DesktopPaths.PipeName, PipeDirection.InOut, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
    await pipe.ConnectAsync(10000);
    using var reader = new StreamReader(pipe, new UTF8Encoding(false), false, 4096, true);
    using var writer = new StreamWriter(pipe, new UTF8Encoding(false), 4096, true) { AutoFlush = true };
    using var input = Console.OpenStandardInput(); using var output = Console.OpenStandardOutput();
    var fromChrome = Task.Run(async () =>
    {
        var prefix = new byte[4];
        while (true)
        {
            await input.ReadExactlyAsync(prefix);
            var length = BinaryPrimitives.ReadInt32LittleEndian(prefix);
            if (length is <= 0 or > 1024 * 1024) throw new InvalidDataException("Message exceeds limit");
            var bytes = new byte[length]; await input.ReadExactlyAsync(bytes);
            var json = Encoding.UTF8.GetString(bytes);
            using var document = System.Text.Json.JsonDocument.Parse(json);
            await writer.WriteLineAsync(document.RootElement.GetRawText());
        }
    });
    var toChrome = Task.Run(async () =>
    {
        while (await reader.ReadLineAsync() is { } line)
        {
            var bytes = Encoding.UTF8.GetBytes(line);
            if (bytes.Length > 1024 * 1024) throw new InvalidDataException("Message exceeds limit");
            var prefix = new byte[4]; BinaryPrimitives.WriteInt32LittleEndian(prefix, bytes.Length);
            await output.WriteAsync(prefix); await output.WriteAsync(bytes); await output.FlushAsync();
        }
    });
    await await Task.WhenAny(fromChrome, toChrome);
    return 0;
}
catch (Exception ex) { await Console.Error.WriteLineAsync("Bili Remote bridge: " + ex.Message); return 1; }

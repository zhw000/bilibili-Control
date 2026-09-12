using System.Buffers.Binary;
using System.Diagnostics;
using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using BiliRemote.Core;
using BiliRemote.Desktop;

internal static class NativeFramingTest
{
    public static async Task Run(string executable)
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        var pipeName = "BiliRemote.NativeFraming." + Guid.NewGuid().ToString("N");
        await using var pipe = new NamedPipeServerStream(pipeName, PipeDirection.InOut, 1,
            PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        ProcessStartInfo StartInfo(string origin)
        {
            var info = new ProcessStartInfo(Path.GetFullPath(executable))
            {
                RedirectStandardInput = true, RedirectStandardOutput = true,
                RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true
            };
            info.ArgumentList.Add(origin); info.Environment["BILIREMOTE_PIPE"] = pipeName;
            return info;
        }
        using var rejected = Process.Start(StartInfo("chrome-extension://untrusted/"))!;
        await rejected.WaitForExitAsync(deadline.Token);
        if (rejected.ExitCode != 2 || (await rejected.StandardOutput.ReadToEndAsync()).Length != 0)
            throw new Exception("Native host must reject unknown origins without stdout output");
        using var native = Process.Start(StartInfo($"chrome-extension://{DesktopPaths.ExtensionId}/"))!;
        try
        {
            await pipe.WaitForConnectionAsync(deadline.Token);
            using var reader = new StreamReader(pipe, new UTF8Encoding(false), false, 4096, true);
            using var writer = new StreamWriter(pipe, new UTF8Encoding(false), 4096, true) { AutoFlush = true };
            var payload = JsonSerializer.SerializeToUtf8Bytes(new { title = "中文 UTF-8 帧", text = "line one\nline two", value = .35 }, Wire.Json);
            var prefix = new byte[4]; BinaryPrimitives.WriteInt32LittleEndian(prefix, payload.Length);
            await native.StandardInput.BaseStream.WriteAsync(prefix, deadline.Token);
            await native.StandardInput.BaseStream.WriteAsync(payload, deadline.Token);
            await native.StandardInput.BaseStream.FlushAsync(deadline.Token);
            var incoming = await reader.ReadLineAsync(deadline.Token);
            if (incoming != Encoding.UTF8.GetString(payload)) throw new Exception("Chrome to pipe framing changed JSON");
            await writer.WriteLineAsync(incoming);
            await native.StandardOutput.BaseStream.ReadExactlyAsync(prefix, deadline.Token);
            var size = BinaryPrimitives.ReadInt32LittleEndian(prefix);
            if (size != payload.Length) throw new Exception("Native output prefix must count UTF-8 bytes");
            var received = new byte[size];
            await native.StandardOutput.BaseStream.ReadExactlyAsync(received, deadline.Token);
            if (!received.SequenceEqual(payload)) throw new Exception("Pipe to Chrome framing changed bytes");
            native.StandardInput.Close();
            await native.WaitForExitAsync(deadline.Token);
            Console.WriteLine("PASS native executable: origin rejection, UTF-8 stdin/stdout framing, pipe roundtrip, clean EOF termination");
        }
        finally { if (!native.HasExited) native.Kill(); }
    }
}

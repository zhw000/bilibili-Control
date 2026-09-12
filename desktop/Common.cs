using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;

namespace BiliRemote.Desktop;
public static class DesktopPaths
{
    public const string ExtensionId = "penfpdlcbljgooeeabnkphfggjhbfnnj";
    public const string NativeHost = "com.biliremote.bridge";
    public static string DataDirectory => Environment.GetEnvironmentVariable("BILIREMOTE_DATA_DIR") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BiliRemote", "data");
    public static string PipeName => Environment.GetEnvironmentVariable("BILIREMOTE_PIPE") ?? "BiliRemote." + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(WindowsIdentity.GetCurrent().User?.Value ?? Environment.UserName)))[..16];
}

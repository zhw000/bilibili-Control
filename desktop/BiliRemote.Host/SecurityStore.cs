using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using BiliRemote.Core;
using BiliRemote.Desktop;

namespace BiliRemote.Host;
public sealed record PairedDevice(string Id,string Name,string TokenHash,DateTimeOffset PairedAt);
public sealed record PairingDescriptor(int Version,string Host,int Port,string CertificateSha256,string PairingToken);
public sealed class SecurityStore : IDisposable
{
    private readonly object gate = new();
    private readonly string devicesPath;
    private readonly List<PairedDevice> devices;
    private string? pairingToken;
    private DateTimeOffset expires;
    public X509Certificate2 Certificate { get; }
    public bool IdentityRenewed { get; }
    public string Fingerprint => Certificate.GetCertHashString(HashAlgorithmName.SHA256).ToLowerInvariant();
    public IReadOnlyList<PairedDevice> Devices { get { lock(gate) return devices.ToArray(); } }
    public SecurityStore()
    {
        Directory.CreateDirectory(DesktopPaths.DataDirectory);
        var certPath=Path.Combine(DesktopPaths.DataDirectory,"identity.bin");
        // Windows Schannel needs a named key container; ephemeral PFX keys fail TLS handshakes.
        // UserKeySet's temporary import is cleaned up when the certificate is disposed.
        X509Certificate2? existing = File.Exists(certPath)
            ? X509CertificateLoader.LoadPkcs12(ProtectedData.Unprotect(File.ReadAllBytes(certPath),null,DataProtectionScope.CurrentUser),null,X509KeyStorageFlags.UserKeySet)
            : null;
        if(existing is not null && !ServerCertificate.NeedsReplacement(existing, DateTimeOffset.UtcNow)) Certificate=existing;
        else
        {
            IdentityRenewed = existing is not null;
            existing?.Dispose();
            using var generated=ServerCertificate.Create(Addresses(), DateTimeOffset.UtcNow);
            var bytes=generated.Export(X509ContentType.Pfx);
            // Preserve the DPAPI-protected old identity for recovery. Paired tokens are untouched;
            // phones must explicitly scan the new fingerprint before trusting a renewed identity.
            if(IdentityRenewed) File.Copy(certPath, certPath+".previous-"+Guid.NewGuid().ToString("N"));
            var temporary=certPath+".tmp";
            File.WriteAllBytes(temporary,ProtectedData.Protect(bytes,null,DataProtectionScope.CurrentUser));
            File.Move(temporary,certPath,true);
            Certificate=X509CertificateLoader.LoadPkcs12(bytes,null,X509KeyStorageFlags.UserKeySet);
        }
        devicesPath=Path.Combine(DesktopPaths.DataDirectory,"devices.bin");
        devices=File.Exists(devicesPath)?JsonSerializer.Deserialize<List<PairedDevice>>(ProtectedData.Unprotect(File.ReadAllBytes(devicesPath),null,DataProtectionScope.CurrentUser),Wire.Json)??[]:[];
    }
    public static IReadOnlyList<IPAddress> Addresses()
    {
        var candidates = NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback)
            .SelectMany(n =>
            {
                var properties = n.GetIPProperties();
                var gateway = properties.GatewayAddresses.Any(g => g.Address.AddressFamily == AddressFamily.InterNetwork && !g.Address.Equals(IPAddress.Any));
                var virtualInterface = n.NetworkInterfaceType is NetworkInterfaceType.Tunnel or NetworkInterfaceType.Ppp || LocalNetwork.IsVirtualInterface(n.Name, n.Description);
                return properties.UnicastAddresses.Select(a => new LocalNetworkAddress(a.Address, n.Name, gateway, n.NetworkInterfaceType == NetworkInterfaceType.Wireless80211, virtualInterface));
            });
        return LocalNetwork.ForPairing(candidates).Select(candidate => candidate.Address).ToArray();
    }
    public PairingDescriptor Begin(string host,int port){lock(gate){pairingToken=Token();expires=DateTimeOffset.UtcNow.AddMinutes(2);return new(1,host,port,Fingerprint,pairingToken);}}
    public object Pair(string supplied,string deviceName)
    {
        lock(gate)
        {
            if(pairingToken==null||DateTimeOffset.UtcNow>expires||!Equal(supplied,pairingToken))throw new RemoteException("pairing_expired","二维码已过期或已使用，请在电脑上刷新二维码");
            pairingToken=null;
            var token=Token();var id=Guid.NewGuid().ToString("N");var name=string.IsNullOrWhiteSpace(deviceName)?"iPhone":deviceName[..Math.Min(deviceName.Length,80)];
            devices.Add(new(id,name,Hash(token),DateTimeOffset.UtcNow));Save();return new{deviceId=id,accessToken=token,computerName=Environment.MachineName};
        }
    }
    public string? Authenticate(string token){if(token.Length is < 20 or > 256)return null;var hash=Hash(token);lock(gate)return devices.FirstOrDefault(d=>Equal(d.TokenHash,hash))?.Id;}
    public void Revoke(string id){lock(gate){devices.RemoveAll(d=>d.Id==id);Save();}}
    private void Save(){var path=devicesPath+".tmp";File.WriteAllBytes(path,ProtectedData.Protect(JsonSerializer.SerializeToUtf8Bytes(devices,Wire.Json),null,DataProtectionScope.CurrentUser));File.Move(path,devicesPath,true);}
    private static string Token()=>Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)).TrimEnd('=').Replace('+','-').Replace('/','_');
    private static string Hash(string text)=>Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text)));
    private static bool Equal(string a,string b)=>CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(a),Encoding.UTF8.GetBytes(b));
    public static string Link(PairingDescriptor descriptor)=>"biliremote://pair?data="+Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(descriptor,Wire.Json)).TrimEnd('=').Replace('+','-').Replace('/','_');
    public void Dispose()=>Certificate.Dispose();
}

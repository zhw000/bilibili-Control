using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace BiliRemote.Core;

public static class ServerCertificate
{
    // Includes the one-day clock-skew allowance in the total lifetime.
    public static X509Certificate2 Create(IEnumerable<IPAddress> addresses, DateTimeOffset now)
    {
        using var key = RSA.Create(2048);
        var request = new CertificateRequest("CN=Bili Remote", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
        request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature | X509KeyUsageFlags.KeyEncipherment, true));
        request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(new OidCollection { new("1.3.6.1.5.5.7.3.1") }, true));
        var san = new SubjectAlternativeNameBuilder();
        san.AddDnsName("localhost");
        foreach (var ip in addresses.Prepend(IPAddress.Loopback).Distinct()) san.AddIpAddress(ip);
        request.CertificateExtensions.Add(san.Build());
        return request.CreateSelfSigned(now.AddDays(-1), now.AddDays(364));
    }

    public static bool NeedsReplacement(X509Certificate2 certificate, DateTimeOffset now) =>
        certificate.NotAfter.ToUniversalTime() <= now.UtcDateTime ||
        certificate.NotAfter.ToUniversalTime() - certificate.NotBefore.ToUniversalTime() > TimeSpan.FromDays(397);
}

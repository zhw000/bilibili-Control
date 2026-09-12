using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using BiliRemote.Core;
using Xunit;

namespace BiliRemote.Tests;

public sealed class ServerCertificateTests
{
    [Fact] public void ProductionIdentityHasAppleCompatibleLifetimeAndServerUsage()
    {
        var now = DateTimeOffset.UtcNow;
        using var certificate = ServerCertificate.Create([IPAddress.Parse("192.168.1.2")], now);
        Assert.True(certificate.HasPrivateKey);
        Assert.Equal(TimeSpan.FromDays(365), certificate.NotAfter - certificate.NotBefore);
        Assert.False(ServerCertificate.NeedsReplacement(certificate, now));
        Assert.True(ServerCertificate.NeedsReplacement(certificate, now.AddDays(365)));
        var eku = Assert.Single(certificate.Extensions.OfType<X509EnhancedKeyUsageExtension>());
        Assert.Contains(eku.EnhancedKeyUsages.Cast<Oid>(), value => value.Value == "1.3.6.1.5.5.7.3.1");
        var san = Assert.Single(certificate.Extensions.OfType<X509SubjectAlternativeNameExtension>());
        Assert.Contains(IPAddress.Parse("192.168.1.2"), san.EnumerateIPAddresses());
        Assert.Contains(IPAddress.Loopback, san.EnumerateIPAddresses());
    }

    [Fact] public void LegacyFiveYearIdentityRequiresReplacement()
    {
        using var key = RSA.Create(2048);
        var now = DateTimeOffset.UtcNow;
        var request = new CertificateRequest("CN=legacy test", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        using var certificate = request.CreateSelfSigned(now.AddDays(-1), now.AddYears(5));
        Assert.True(ServerCertificate.NeedsReplacement(certificate, now));
    }
}

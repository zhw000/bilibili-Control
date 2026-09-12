using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using BiliRemote.Core;

var output = Path.GetFullPath(args.Single());
Directory.CreateDirectory(output);
using var certificate = ServerCertificate.Create([IPAddress.Loopback], DateTimeOffset.UtcNow);
File.WriteAllText(Path.Combine(output, "cert.pem"), certificate.ExportCertificatePem());
using var key = certificate.GetRSAPrivateKey()!;
File.WriteAllText(Path.Combine(output, "key.pem"), key.ExportPkcs8PrivateKeyPem());
File.WriteAllBytes(Path.Combine(output, "server.cer"), certificate.Export(X509ContentType.Cert));

// Match the old Windows certificate, including its critical EKU and five-year lifetime.
var legacyRequest = new CertificateRequest("CN=Bili Remote", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
foreach (var extension in certificate.Extensions) legacyRequest.CertificateExtensions.Add(extension);
using var legacy = legacyRequest.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddYears(5));
File.WriteAllBytes(Path.Combine(output, "legacy.cer"), legacy.Export(X509ContentType.Cert));
using var expired = legacyRequest.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-30), DateTimeOffset.UtcNow.AddDays(-1));
File.WriteAllBytes(Path.Combine(output, "expired.cer"), expired.Export(X509ContentType.Cert));
var wrongUsageRequest = new CertificateRequest("CN=Bili Remote", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
foreach (var extension in certificate.Extensions)
    if (extension is not X509EnhancedKeyUsageExtension) wrongUsageRequest.CertificateExtensions.Add(extension);
wrongUsageRequest.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(new OidCollection { new("1.3.6.1.5.5.7.3.2") }, true));
using var wrongUsage = wrongUsageRequest.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddDays(364));
File.WriteAllBytes(Path.Combine(output, "client-only.cer"), wrongUsage.Export(X509ContentType.Cert));

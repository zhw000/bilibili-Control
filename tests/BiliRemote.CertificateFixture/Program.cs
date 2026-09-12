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

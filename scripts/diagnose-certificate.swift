import Foundation
import Security

for path in CommandLine.arguments.dropFirst() {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let certificate = SecCertificateCreateWithData(nil, data as CFData)!
    var result: SecTrust?
    precondition(SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, nil), &result) == errSecSuccess)
    let trust = result!
    SecTrustSetAnchorCertificates(trust, [certificate] as CFArray)
    SecTrustSetAnchorCertificatesOnly(trust, true)
    SecTrustSetNetworkFetchAllowed(trust, false)
    var error: CFError?
    let valid = SecTrustEvaluateWithError(trust, &error)
    print("\(URL(fileURLWithPath: path).lastPathComponent): valid=\(valid), error=\(String(describing: error)), details=\(String(describing: SecTrustCopyResult(trust)))")
    if path.hasSuffix("/server.cer") { precondition(valid, "Production Windows certificate must pass Apple SSL policy") }
    if path.hasSuffix("/legacy.cer") { precondition(!valid, "Regression fixture must reproduce rejection of the five-year certificate") }
}

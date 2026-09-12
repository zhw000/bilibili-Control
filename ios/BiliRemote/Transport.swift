import Foundation
import Security
import CryptoKit

final class PinnedSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let host: String
    let fingerprint: String
    init(host: String, fingerprint: String) { self.host = host; self.fingerprint = fingerprint.lowercased() }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, challenge.protectionSpace.host == host, let trust = challenge.protectionSpace.serverTrust, let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let certificate = chain.first else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        let actual = SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
        guard actual == fingerprint else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        // The scanned fingerprint establishes identity even when DHCP changes the address.
        // Still validate the pinned certificate's validity and server-auth usage.
        SecTrustSetAnchorCertificates(trust, [certificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, nil))
        guard SecTrustEvaluateWithError(trust, nil) else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
enum DeviceKeychain {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.biliremote.device", kSecAttrAccount as String: "paired-computer"] }
    static func load() -> DeviceConfig? {
        var request = query; request[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(DeviceConfig.self, from: data)
    }
    static func save(_ config: DeviceConfig) throws {
        let data = try JSONEncoder().encode(config)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var request = query; request[kSecValueData as String] = data; request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { throw RemoteFailure(code: "keychain", message: "无法安全保存配对信息。") }
        } else if update != errSecSuccess { throw RemoteFailure(code: "keychain", message: "无法更新配对信息。") }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}
@MainActor final class RemoteTransport {
    enum Status: Equatable { case disconnected, connecting, connected }
    var onSnapshot: ((Snapshot) -> Void)?
    var onStatus: ((Status) -> Void)?
    var onConnectionError: ((String) -> Void)?
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var configuration: DeviceConfig?
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var timeouts: [String: Task<Void, Never>] = [:]
    private var generation = UUID()
    private var retryAttempt = 0
    private var status: Status = .disconnected { didSet { onStatus?(status) } }
    func pair(_ descriptor: PairingDescriptor, name: String) async throws -> DeviceConfig {
        let delegate = PinnedSessionDelegate(host: descriptor.host, fingerprint: descriptor.certificateSha256)
        let temporary = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { temporary.invalidateAndCancel() }
        let url = URL(string: "https://\(descriptor.host):\(descriptor.port)/api/v1/pair")!
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["pairingToken": descriptor.pairingToken, "deviceName": name])
        let (data, response) = try await temporary.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            struct Failure: Decodable { let error: RemoteFailure }
            throw (try? JSONDecoder().decode(Failure.self, from: data).error) ?? RemoteFailure(code: "pairing_failed", message: "配对失败，请刷新电脑上的二维码后重试。")
        }
        struct Result: Decodable { let deviceId: String, accessToken: String, computerName: String }
        let result = try JSONDecoder().decode(Result.self, from: data)
        return DeviceConfig(host: descriptor.host, port: descriptor.port, certificateSha256: descriptor.certificateSha256, deviceId: result.deviceId, accessToken: result.accessToken, computerName: result.computerName)
    }
    func connect(_ config: DeviceConfig) { disconnect(); configuration = config; retryAttempt = 0; open() }
    func disconnect() {
        configuration = nil; generation = UUID(); retryTask?.cancel(); receiveTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil); socket = nil; session?.invalidateAndCancel(); session = nil
        failPending(RemoteFailure.disconnected); status = .disconnected
    }
    private func open() {
        guard let config = configuration else { return }
        generation = UUID(); let thisGeneration = generation; status = .connecting
        let settings = URLSessionConfiguration.ephemeral; settings.timeoutIntervalForRequest = 20
        session = URLSession(configuration: settings, delegate: PinnedSessionDelegate(host: config.host, fingerprint: config.certificateSha256), delegateQueue: nil)
        var request = URLRequest(url: URL(string: "wss://\(config.host):\(config.port)/api/v1/ws")!)
        request.setValue("Bearer \(config.accessToken)", forHTTPHeaderField: "Authorization")
        let connection = session!.webSocketTask(with: request); socket = connection; connection.maximumMessageSize = 1024 * 1024; connection.resume()
        receiveTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await connection.receive()
                    guard let self, self.generation == thisGeneration else { return }
                    let data: Data
                    switch message { case .data(let bytes): data = bytes; case .string(let text): data = Data(text.utf8); @unknown default: continue }
                    try self.receive(data)
                }
            } catch {
                guard let self, self.generation == thisGeneration, self.configuration != nil else { return }
                self.failed(error)
            }
        }
    }
    private func receive(_ data: Data) throws {
        struct Envelope: Decodable { let v: Int; let id: String?; let ok: Bool?; let result: JSONValue?; let error: RemoteFailure?; let event: String?; let data: JSONValue? }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.v == 1 else { throw RemoteFailure(code: "version_mismatch", message: "请同时更新 App、电脑助手和扩展。") }
        if envelope.event == "snapshot", let value = envelope.data {
            let snapshot = try value.decode(Snapshot.self); retryAttempt = 0; status = .connected; onSnapshot?(snapshot)
        } else if let id = envelope.id, let continuation = pending.removeValue(forKey: id) {
            timeouts.removeValue(forKey: id)?.cancel()
            if envelope.ok == true { continuation.resume(returning: envelope.result ?? .object([:])) }
            else { continuation.resume(throwing: envelope.error ?? RemoteFailure(code: "request_failed", message: "操作未完成。")) }
        }
    }
    func request<T: Decodable>(_ method: String, params: [String: JSONValue] = [:], as type: T.Type = T.self) async throws -> T {
        guard status == .connected, let socket else { throw RemoteFailure.disconnected }
        let id = UUID().uuidString
        let payload: JSONValue = .object(["v": .number(1), "id": .string(id), "method": .string(method), "params": .object(params)])
        let bytes = try JSONEncoder().encode(payload)
        let value: JSONValue = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeouts[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(85))
                guard !Task.isCancelled, let self else { return }
                self.pending.removeValue(forKey: id)?.resume(throwing: RemoteFailure(code: "timeout", message: "电脑响应超时，请检查电脑网页。")); self.timeouts.removeValue(forKey: id)
            }
            Task { [weak self] in
                do { try await socket.send(.data(bytes)) }
                catch { guard let self else { return }; self.timeouts.removeValue(forKey: id)?.cancel(); self.pending.removeValue(forKey: id)?.resume(throwing: error) }
            }
        }
        return try value.decode(type)
    }
    private func failPending(_ error: Error) { let continuations = pending.values; pending.removeAll(); timeouts.values.forEach { $0.cancel() }; timeouts.removeAll(); continuations.forEach { $0.resume(throwing: error) } }
    private func failed(_ error: Error) {
        socket?.cancel(with: .goingAway, reason: nil); socket = nil; session?.invalidateAndCancel(); session = nil
        failPending(RemoteFailure.disconnected); status = .connecting
        onConnectionError?("连接暂时中断。请确认电脑助手正在运行、允许局域网访问，并且手机与电脑在同一网络。")
        let delay = min(15, pow(2, Double(retryAttempt))); retryAttempt += 1
        retryTask = Task { [weak self] in try? await Task.sleep(for: .seconds(delay)); guard !Task.isCancelled else { return }; self?.open() }
    }
}

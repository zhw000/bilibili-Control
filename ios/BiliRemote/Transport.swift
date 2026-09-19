import Foundation
import Security
import CryptoKit

final class PinnedSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let host: String
    let fingerprint: String
    private let lock = NSLock()
    private var validationFailure: RemoteFailure?
    var failure: RemoteFailure? { lock.withLock { validationFailure } }
    init(host: String, fingerprint: String) { self.host = host; self.fingerprint = fingerprint.lowercased() }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        do {
            guard challenge.protectionSpace.host == host, let trust = challenge.protectionSpace.serverTrust else {
                throw RemoteFailure(code: "certificate_host", message: "连接地址或电脑证书异常，请刷新电脑助手的二维码后重新扫描。")
            }
            try Self.validate(trust, fingerprint: fingerprint)
            completionHandler(.useCredential, URLCredential(trust: trust))
        } catch {
            lock.withLock { validationFailure = error as? RemoteFailure }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    static func validate(_ trust: SecTrust, fingerprint: String) throws {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let certificate = chain.first else {
            throw RemoteFailure(code: "certificate_missing", message: "电脑未提供有效证书，请更新并重启电脑助手。")
        }
        let actual = SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
        guard actual == fingerprint.lowercased() else {
            throw RemoteFailure(code: "certificate_mismatch", message: "电脑证书与配对二维码不一致，已停止连接。请确认电脑助手的地址，刷新二维码后重新扫描；如仍失败，请检查代理是否拦截了局域网连接。")
        }
        // The scanned fingerprint establishes identity even when DHCP changes the address.
        // Still validate the pinned certificate's validity and server-auth usage.
        guard SecTrustSetAnchorCertificates(trust, [certificate] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, nil)) == errSecSuccess else {
            throw RemoteFailure(code: "certificate_policy", message: "无法建立证书校验，请关闭并重新打开 App。")
        }
        var trustError: CFError?
        guard SecTrustEvaluateWithError(trust, &trustError) else {
            let detail = trustError.map { "\(CFErrorGetCode($0))：\(CFErrorCopyDescription($0) as String)" } ?? "未知原因"
            throw RemoteFailure(code: "certificate_invalid", message: "iOS 拒绝了电脑证书。请更新电脑助手，并确认手机和电脑的日期时间正确。\n证书校验：\(detail)")
        }
    }
}

enum ConnectionFailure {
    static func explain(_ error: Error, delegate: PinnedSessionDelegate, address: String) -> Error {
        if let failure = delegate.failure { return failure }
        if error is RemoteFailure { return error }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return error }
        let hint: String
        switch nsError.code {
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorTimedOut:
            hint = "无法连接电脑 \(address)。请确认电脑助手正在运行、手机与电脑连接同一路由器，并已允许 App 使用局域网。"
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            hint = "局域网连接不可用。请检查 Wi-Fi，并在 iPhone 设置 → 隐私与安全性 → 本地网络中允许哔哩遥控。"
        case NSURLErrorCancelled:
            hint = "配对连接被中断。请刷新电脑二维码后重试；若仍失败，请检查手机的局域网权限以及代理的局域网直连设置。"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid,
             NSURLErrorServerCertificateHasUnknownRoot:
            hint = "无法与电脑建立安全连接。请更新电脑助手、检查两端日期时间并重新扫码配对。"
        default: hint = "连接电脑 \(address) 失败：\(nsError.localizedDescription)"
        }
        return RemoteFailure(code: "network_\(nsError.code)", message: "\(hint)\n网络错误：\(nsError.code)")
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
    private(set) var status: Status = .disconnected { didSet { onStatus?(status) } }
    func pair(_ descriptor: PairingDescriptor, name: String) async throws -> DeviceConfig {
        let delegate = PinnedSessionDelegate(host: descriptor.host, fingerprint: descriptor.certificateSha256)
        let temporary = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { temporary.invalidateAndCancel() }
        let url = URL(string: "https://\(descriptor.host):\(descriptor.port)/api/v1/pair")!
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["pairingToken": descriptor.pairingToken, "deviceName": name])
        let data: Data
        let response: URLResponse
        do { (data, response) = try await temporary.data(for: request) }
        catch { throw ConnectionFailure.explain(error, delegate: delegate, address: "\(descriptor.host):\(descriptor.port)") }
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
        let delegate = PinnedSessionDelegate(host: config.host, fingerprint: config.certificateSha256)
        session = URLSession(configuration: settings, delegate: delegate, delegateQueue: nil)
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
                self.failed(ConnectionFailure.explain(error, delegate: delegate, address: "\(config.host):\(config.port)"))
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
    func request<T: Decodable>(_ method: String, params: [String: JSONValue] = [:], timeout: Double = 85, as type: T.Type = T.self) async throws -> T {
        guard status == .connected, let socket else { throw RemoteFailure.disconnected }
        let id = UUID().uuidString
        let payload: JSONValue = .object(["v": .number(1), "id": .string(id), "method": .string(method), "params": .object(params)])
        let bytes = try JSONEncoder().encode(payload)
        let value: JSONValue = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeouts[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled, let self else { return }
                self.pending.removeValue(forKey: id)?.resume(throwing: RemoteFailure(code: "timeout", message: "电脑响应超时，请检查电脑网页。")); self.timeouts.removeValue(forKey: id)
            }
            Task { [weak self] in
                do { try await socket.send(.string(String(decoding: bytes, as: UTF8.self))) }
                catch { guard let self else { return }; self.timeouts.removeValue(forKey: id)?.cancel(); self.pending.removeValue(forKey: id)?.resume(throwing: error) }
            }
        }
        return try value.decode(type)
    }
    private func failPending(_ error: Error) { let continuations = pending.values; pending.removeAll(); timeouts.values.forEach { $0.cancel() }; timeouts.removeAll(); continuations.forEach { $0.resume(throwing: error) } }
    private func failed(_ error: Error) {
        socket?.cancel(with: .goingAway, reason: nil); socket = nil; session?.invalidateAndCancel(); session = nil
        failPending(RemoteFailure.disconnected); status = .connecting
        onConnectionError?(error.localizedDescription)
        let delay = min(15, pow(2, Double(retryAttempt))); retryAttempt += 1
        retryTask = Task { [weak self] in try? await Task.sleep(for: .seconds(delay)); guard !Task.isCancelled else { return }; self?.open() }
    }
}

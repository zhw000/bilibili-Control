import SwiftUI
import WatchConnectivity

@MainActor final class WatchRemoteModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var state = WatchPlaybackState()
    @Published private(set) var reachable = false
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    private var pending: UUID?
    private var timeout: Task<Void, Never>?
    var lastUpdated: Date? { state.updatedAt > 0 ? Date(timeIntervalSince1970: state.updatedAt) : nil }
    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self; WCSession.default.activate()
        receive(WCSession.default.receivedApplicationContext)
    }
    private func receive(_ message: [String: Any]) {
        if let data = message["state"] as? Data, let snapshot = try? JSONDecoder().decode(WatchPlaybackState.self, from: data), snapshot.updatedAt >= state.updatedAt { state = snapshot }
    }
    func send(_ action: RemoteAction, silently: Bool = false) {
        guard !busy else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { if !silently { error = "无法连接 iPhone，请打开手机上的哔哩遥控。" }; return }
        let id = UUID(); pending = id; busy = true
        if !silently { error = nil }
        timeout?.cancel()
        timeout = Task {
            try? await Task.sleep(for: .seconds(55))
            guard !Task.isCancelled, self.pending == id else { return }
            self.pending = nil; self.busy = false
            self.error = action == .refresh ? "电脑响应超时，请检查 iPhone 的连接。" : "指令结果未确认，请刷新状态后再操作。"
        }
        session.sendMessage(["id": id.uuidString, "action": action.rawValue], replyHandler: { reply in
            Task { @MainActor in
                guard self.pending == id else { return }
                self.timeout?.cancel(); self.pending = nil; self.busy = false
                self.receive(reply); self.error = reply["error"] as? String
            }
        }, errorHandler: { _ in
            Task { @MainActor in
                guard self.pending == id else { return }
                self.timeout?.cancel(); self.pending = nil; self.busy = false
                self.error = action == .refresh ? "无法连接 iPhone，请在手机上打开哔哩遥控。" : "指令结果未确认，请刷新状态后再操作。"
            }
        })
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.reachable = session.isReachable; self.receive(session.receivedApplicationContext); self.send(.refresh, silently: true) }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.reachable = session.isReachable; if self.reachable { self.send(.refresh, silently: true) } }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { Task { @MainActor in self.receive(applicationContext) } }
}

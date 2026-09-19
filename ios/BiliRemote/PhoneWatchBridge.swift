import SwiftUI
import WatchConnectivity

@MainActor final class PhoneWatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneWatchBridge()
    @Published private(set) var status = "尚未连接 Apple Watch"
    private var state = WatchPlaybackState()
    private var lastPublished = Date.distantPast
    private var jobs: [String: (RemoteAction, Task<WatchPlaybackState, Error>)] = [:]
    private var completed: [String] = []
    var onSnapshot: ((Snapshot) -> Void)?

    private override init() { super.init(); if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() } }
    func publish(_ snapshot: Snapshot, connected: Bool, force: Bool = false) {
        let next = WatchPlaybackState(snapshot: snapshot, connected: connected)
        let changed = next.title != state.title || next.paused != state.paused || next.connected != state.connected
        state = next
        guard force || changed || Date().timeIntervalSince(lastPublished) >= 3 else { return }
        synchronize()
    }
    func clear() { state = WatchPlaybackState(); state.updatedAt = Date().timeIntervalSince1970; state.message = "请先在 iPhone 配对电脑"; synchronize() }
    private func synchronize() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(state) else { return }
        do { try session.updateApplicationContext(["state": data]); lastPublished = Date() }
        catch { status = "手表状态同步失败，请打开手表 App 重试" }
    }
    private func updateStatus() {
        let session = WCSession.default
        status = !session.isPaired ? "未配对 Apple Watch" : !session.isWatchAppInstalled ? "请在 Watch App 中安装哔哩遥控" : session.isReachable ? "Apple Watch 已连接" : "已安装，打开手表 App 即可遥控"
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.updateStatus(); self.synchronize() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.updateStatus(); self.synchronize() } }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.updateStatus(); self.synchronize() } }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let id = message["id"] as? String, UUID(uuidString: id) != nil,
              let name = message["action"] as? String, let action = RemoteAction(rawValue: name) else {
            replyHandler(["error": "手表指令无效，请更新手机和手表 App。"]); return
        }
        Task { @MainActor in
            do {
                if let existing = self.jobs[id], existing.0 != action { throw RemoteFailure(code: "id_conflict", message: "重复指令编号不一致。") }
                let job: Task<WatchPlaybackState, Error>
                if let existing = self.jobs[id] { job = existing.1 }
                else {
                    // Duplicate deliveries share the original result, including failures.
                    guard self.jobs.count - self.completed.count < 4 else { throw RemoteFailure(code: "busy", message: "正在处理遥控指令，请稍后再试。") }
                    job = Task { @MainActor in
                        let work = Task { try await RemoteCommandClient.perform(action) }
                        let background = UIApplication.shared.beginBackgroundTask(withName: "Watch playback") { work.cancel() }
                        defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
                        let snapshot = try await work.value
                        self.onSnapshot?(snapshot); self.publish(snapshot, connected: true, force: true)
                        return WatchPlaybackState(snapshot: snapshot, connected: true)
                    }
                    self.jobs[id] = (action, job)
                }
                defer {
                    if !self.completed.contains(id) { self.completed.append(id) }
                    while self.completed.count > 32 { self.jobs.removeValue(forKey: self.completed.removeFirst()) }
                }
                replyHandler(["state": try JSONEncoder().encode(try await job.value)])
            } catch { replyHandler(["error": error.localizedDescription]) }
        }
    }
}

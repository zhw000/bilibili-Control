import SwiftUI

@MainActor final class RemoteModel: ObservableObject {
    @Published var snapshot = Snapshot()
    @Published var status = RemoteTransport.Status.disconnected
    @Published var device: DeviceConfig?
    @Published var error: String?
    @Published var connectionHint: String?
    @Published var selectedTab = 0
    @Published var pairing = false
    let transport = RemoteTransport()
    init() {
        device = DeviceKeychain.load()
        if device == nil { selectedTab = 3 }
        transport.onSnapshot = { [weak self] snapshot in self?.snapshot = snapshot; self?.connectionHint = nil }
        transport.onStatus = { [weak self] status in self?.status = status }
        transport.onConnectionError = { [weak self] message in self?.connectionHint = message }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            device = nil; selectedTab = 3
            if ProcessInfo.processInfo.arguments.contains("--preview-state") {
                let first = VideoItem(bvid: "BVPreview1", title: "保持好奇，探索每一个新世界", url: "https://www.bilibili.com/", duration: 754, creatorId: "1", creatorName: "界面测试")
                let second = VideoItem(bvid: "BVPreview2", title: "下一站，发现更多有趣的事", url: "https://www.bilibili.com/", duration: 620)
                snapshot.computerName = "我的电脑"; snapshot.browserConnected = true
                snapshot.player = PlayerState(bvid: first.bvid, title: first.title, url: first.url, currentTime: 187, duration: 754, paused: false, volume: 0.7)
                snapshot.queue = QueueSnapshot(items: [first, second], index: 0, active: true)
                snapshot.systemVolume = SystemVolume(value: 0.45, muted: false, deviceName: "扬声器", available: true)
                status = .connected; selectedTab = 1
            }
        }
        #endif
    }
    var connected: Bool { status == .connected }
    var ready: Bool { connected && snapshot.browserConnected }
    var currentCover: String? { snapshot.queue.items.first(where: { $0.bvid == snapshot.player.bvid })?.cover }
    func connect() { if let device { transport.connect(device) } }
    func background() { transport.disconnect() }
    func forget() { transport.disconnect(); DeviceKeychain.clear(); device = nil; snapshot = Snapshot(); connectionHint = nil }
    func pair(_ text: String) async {
        guard !pairing else { return }; pairing = true; defer { pairing = false }
        do {
            let descriptor = try PairingDescriptor.parse(text)
            let config = try await transport.pair(descriptor, name: UIDevice.current.name)
            try DeviceKeychain.save(config); device = config; connect(); selectedTab = 0
        } catch { self.error = error.localizedDescription }
    }
    func execute(_ method: String, _ params: [String: JSONValue] = [:]) {
        Task { do { let _: EmptyResponse = try await transport.request(method, params: params) } catch { self.error = error.localizedDescription } }
    }
    func play(_ video: VideoItem) { do { execute("player.open", ["video": try JSONValue.from(video)]); selectedTab = 1 } catch { self.error = error.localizedDescription } }
    func startQueue(_ source: QueueSource) {
        do { if case .object(let params) = try JSONValue.from(source) { execute("queue.start", params); selectedTab = 1 } } catch { self.error = error.localizedDescription }
    }
    func control(_ action: String, value: JSONValue? = nil) { var params: [String: JSONValue] = ["action": .string(action)]; params["value"] = value; execute("player.command", params) }
}

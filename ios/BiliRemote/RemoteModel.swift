import SwiftUI

@MainActor final class RemoteModel: ObservableObject {
    @Published var snapshot = Snapshot()
    @Published var status = RemoteTransport.Status.disconnected
    @Published var device: DeviceConfig?
    @Published var error: String?
    @Published var connectionHint: String?
    @Published var selectedTab = 0
    @Published var pairing = false
    @Published private(set) var relatedVideos: [VideoItem] = []
    @Published private(set) var relatedLoading = false
    @Published private(set) var relatedError: String?
    private var relatedBvid = ""
    private var relatedGeneration = UUID()
    let transport = RemoteTransport()
    init() {
        device = DeviceKeychain.load()
        if device == nil { selectedTab = 3 }
        transport.onSnapshot = { [weak self] snapshot in self?.snapshot = snapshot; self?.connectionHint = nil; PhoneWatchBridge.shared.publish(snapshot, connected: true) }
        transport.onStatus = { [weak self] status in
            guard let self else { return }; self.status = status
            if status != .connected { PhoneWatchBridge.shared.publish(self.snapshot, connected: false) }
        }
        transport.onConnectionError = { [weak self] message in self?.connectionHint = message }
        PhoneWatchBridge.shared.onSnapshot = { [weak self] snapshot in self?.snapshot = snapshot }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            device = nil; selectedTab = 3
            if ProcessInfo.processInfo.arguments.contains("--preview-state") {
                let first = VideoItem(bvid: "BVPreview1", title: "保持好奇，探索每一个新世界，一起出发去看山川、森林与海洋", url: "https://www.bilibili.com/", cover: "preview-cover", duration: 754, creatorId: "1", creatorName: "界面测试")
                let second = VideoItem(bvid: "BVPreview2", title: "下一站，发现更多有趣的事", url: "https://www.bilibili.com/", duration: 620)
                snapshot.computerName = "我的电脑"; snapshot.browserConnected = true
                snapshot.player = PlayerState(bvid: first.bvid, title: first.title, url: first.url, currentTime: 187, duration: 754, paused: false, volume: 0.7)
                snapshot.queue = QueueSnapshot(source: QueueSource(kind: "creator", creatorId: "1"), items: [first, second], index: 0, active: true)
                if ProcessInfo.processInfo.arguments.contains("--preview-related") {
                    snapshot.queue = QueueSnapshot(source: QueueSource(kind: "manual"), items: [first], index: 0, active: true)
                    relatedBvid = first.bvid
                    relatedVideos = (1...12).map { number in VideoItem(bvid: "BVRelated\(number)", title: "相关视频 \(number) · 和朋友一起发现新的风景", url: "https://www.bilibili.com/", cover: "preview-cover", duration: Double(300 + number), creatorName: "旅行记录") }
                }
                snapshot.systemVolume = SystemVolume(value: 0.45, muted: false, deviceName: "扬声器", available: true)
                status = .connected; selectedTab = 1
            }
        }
        #endif
    }
    var connected: Bool { status == .connected }
    var ready: Bool { connected && snapshot.browserConnected }
    var currentCover: String? { snapshot.player.cover ?? snapshot.queue.items.first(where: { $0.bvid == snapshot.player.bvid })?.cover }
    var showsPlaylist: Bool { snapshot.queue.isPlaylist(for: snapshot.player) }
    var visibleRelatedVideos: [VideoItem] { relatedBvid == snapshot.player.bvid ? relatedVideos : [] }
    var relatedRequestKey: String { ready && !showsPlaylist ? snapshot.player.bvid : "" }
    func loadRelated() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-state") { return }
        #endif
        let bvid = relatedRequestKey
        let ticket = UUID(); relatedGeneration = ticket
        guard !bvid.isEmpty else { relatedLoading = false; return }
        if relatedBvid != bvid { relatedVideos = [] }
        relatedBvid = bvid; relatedLoading = true; relatedError = nil
        defer { if relatedGeneration == ticket { relatedLoading = false } }
        do {
            for attempt in 0..<3 {
                if attempt > 0 { try await Task.sleep(for: .seconds(2)) }
                guard relatedGeneration == ticket, relatedRequestKey == bvid, !Task.isCancelled else { return }
                let result: RelatedVideos = try await transport.request("player.related", params: ["bvid": .string(bvid)])
                guard relatedGeneration == ticket, relatedRequestKey == bvid, !Task.isCancelled else { return }
                guard result.bvid == bvid else { throw RemoteFailure(code: "target_changed", message: "电脑已切换视频，请刷新相关视频。") }
                var seen = Set<String>()
                relatedVideos = result.items.filter { $0.bvid != bvid && seen.insert($0.bvid).inserted }.map { item in
                    var enriched = item
                    if enriched.cover == nil { enriched.cover = relatedVideos.first(where: { $0.bvid == item.bvid })?.cover }
                    return enriched
                }
                if relatedVideos.allSatisfy({ $0.cover != nil }) { break }
            }
        } catch {
            guard relatedGeneration == ticket, relatedRequestKey == bvid, !Task.isCancelled else { return }
            relatedError = (error as? RemoteFailure)?.code == "unknown_method" ? "请更新电脑助手和 Chrome 扩展，以显示相关视频。" : error.localizedDescription
        }
    }
    func nextVideo() {
        if showsPlaylist { execute("queue.next") }
        else if let next = visibleRelatedVideos.first { play(next) }
    }
    func connect() { if let device, transport.status == .disconnected { transport.connect(device) } }
    func background() { transport.disconnect() }
    func forget() { transport.disconnect(); DeviceKeychain.clear(); device = nil; snapshot = Snapshot(); connectionHint = nil; PhoneWatchBridge.shared.clear() }
    func pair(_ text: String) async {
        guard !pairing else { return }; pairing = true; defer { pairing = false }
        do {
            let descriptor = try PairingDescriptor.parse(text)
            let config = try await transport.pair(descriptor, name: UIDevice.current.name)
            try DeviceKeychain.save(config); transport.disconnect(); device = config; connect(); selectedTab = 0
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

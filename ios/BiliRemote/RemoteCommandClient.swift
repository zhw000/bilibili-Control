import Foundation

/// A short-lived connection lets Siri and Watch commands work independently of
/// the UI's foreground socket. Commands are sent once and are never replayed.
@MainActor enum RemoteCommandClient {
    static func perform(_ action: RemoteAction) async throws -> Snapshot {
        guard let device = DeviceKeychain.load() else { throw RemoteFailure(code: "not_paired", message: "请先打开哔哩遥控，在设备页配对电脑。") }
        let transport = RemoteTransport()
        var connectionError: String?
        transport.onConnectionError = { connectionError = $0 }
        transport.connect(device)
        defer { transport.disconnect() }
        let deadline = Date().addingTimeInterval(8)
        while transport.status != .connected {
            try Task.checkCancellation()
            guard Date() < deadline else { throw RemoteFailure(code: "connection_timeout", message: connectionError ?? "无法连接电脑，请检查电脑助手及 iPhone 的局域网连接。") }
            try await Task.sleep(for: .milliseconds(100))
        }
        let snapshot: Snapshot = try await transport.request("snapshot", timeout: 8)
        guard action != .refresh else { return snapshot }
        guard snapshot.browserConnected else { throw RemoteFailure(code: "browser_disconnected", message: "请在电脑打开 Chrome 并连接哔哩遥控扩展。") }
        let request = try await command(action, snapshot: snapshot, transport: transport)
        try Task.checkCancellation()
        let _: EmptyResponse = try await transport.request(request.method, params: request.params, timeout: 20)
        return try await transport.request("snapshot", timeout: 5)
    }

    struct Command { let method: String; var params: [String: JSONValue] = [:] }
    static func simpleCommand(_ action: RemoteAction, snapshot: Snapshot) throws -> Command? {
        let queue = snapshot.queue, player = snapshot.player
        if action == .refresh { return Command(method: "snapshot") }
        if let list = player.siteList, action == .next || action == .previous {
            guard action == .next ? list.next : list.previous else {
                throw RemoteFailure(code: "queue_boundary", message: "已到达播放列表边界。")
            }
            return Command(method: "player.command", params: ["action": .string(action == .next ? "listNext" : "listPrevious"), "listId": .string(list.id)])
        }
        if player.siteList == nil && action == .play && queue.canResume && queue.items.indices.contains(queue.index) && (player.bvid.isEmpty || queue.items[queue.index].bvid == player.bvid) { return Command(method: "queue.resume") }
        guard !player.bvid.isEmpty else { throw RemoteFailure(code: "no_player", message: "请先在手机选择一个视频。") }
        switch action {
        case .play, .pause: return Command(method: "player.command", params: ["action": .string(action.rawValue)])
        case .forward, .backward: return Command(method: "player.command", params: ["action": .string("seekBy"), "value": .number(action == .forward ? 10 : -10)])
        case .volumeUp, .volumeDown: return Command(method: "player.command", params: ["action": .string("volume"), "value": .number(min(1, max(0, player.volume + (action == .volumeUp ? 0.1 : -0.1))))])
        case .previous:
            guard queue.isPlaylist(for: player), queue.index > 0 else { throw RemoteFailure(code: "queue_boundary", message: "已经是列表的第一个视频。") }
            return Command(method: "queue.previous")
        case .next:
            guard queue.isPlaylist(for: player) else { return nil }
            guard queue.index + 1 < queue.items.count || queue.nextPage != nil else { throw RemoteFailure(code: "queue_boundary", message: "已经是列表的最后一个视频。") }
            return Command(method: "queue.next")
        case .refresh: return Command(method: "snapshot")
        }
    }
    private static func command(_ action: RemoteAction, snapshot: Snapshot, transport: RemoteTransport) async throws -> Command {
        if let command = try simpleCommand(action, snapshot: snapshot) { return command }
        let related: RelatedVideos = try await transport.request("player.related", params: ["bvid": .string(snapshot.player.bvid)], timeout: 20)
        guard related.bvid == snapshot.player.bvid, let next = related.items.first(where: { $0.bvid != snapshot.player.bvid }) else { throw RemoteFailure(code: "no_next_video", message: "这个视频暂时没有相关推荐。") }
        return Command(method: "player.open", params: ["video": try JSONValue.from(next)])
    }
}

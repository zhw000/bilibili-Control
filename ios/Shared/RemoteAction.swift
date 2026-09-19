import Foundation

enum RemoteAction: String, Codable, CaseIterable {
    case play, pause, next, previous, forward, backward, volumeUp, volumeDown, refresh
    var title: String {
        switch self {
        case .play: return "继续播放"
        case .pause: return "暂停播放"
        case .next: return "下一个视频"
        case .previous: return "上一个视频"
        case .forward: return "前进十秒"
        case .backward: return "后退十秒"
        case .volumeUp: return "增大音量"
        case .volumeDown: return "减小音量"
        case .refresh: return "刷新播放状态"
        }
    }
}

struct WatchPlaybackState: Codable {
    var title = "尚未播放"
    var computerName = "电脑"
    var paused = true
    var connected = false
    var currentTime: Double = 0
    var duration: Double = 0
    var volume: Double = 0
    var canPrevious = false
    var canNext = false
    var updatedAt = Date.distantPast.timeIntervalSince1970
    var message: String?

    init() {}
    init(snapshot: Snapshot, connected: Bool) {
        let player = snapshot.player, queue = snapshot.queue
        title = player.title.isEmpty ? "尚未播放" : player.title
        computerName = snapshot.computerName; paused = player.paused
        self.connected = connected && snapshot.browserConnected
        currentTime = player.currentTime; duration = player.duration; volume = player.volume
        canPrevious = queue.isPlaylist(for: player) && queue.index > 0
        canNext = queue.isPlaylist(for: player) ? queue.index + 1 < queue.items.count || queue.nextPage != nil : !player.bvid.isEmpty
        updatedAt = Date().timeIntervalSince1970
        message = player.errorMessage ?? queue.message
    }
}

import Foundation

struct VideoItem: Codable, Identifiable, Hashable {
    let bvid: String
    let title: String
    let url: String
    var cover: String?
    var duration: Double?
    var creatorId: String?
    var creatorName: String?
    var unavailableReason: String?
    var id: String { bvid }
}
struct CreatorItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    var avatar: String?
    var description: String?
}
struct CollectionItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
    var cover: String?
    var count: Int?
    var description: String?
}
struct PageResult<T: Codable>: Codable { let items: [T]; let page: Int; let totalPages: Int; let total: Int?; let nextPage: Int? }
struct QueueSource: Codable { let kind: String; var creatorId: String?; var url: String?; var order = "newest"; var items: [VideoItem]?; var folderId: String?; var keyword: String?; var startBvid: String? }
struct QueueSnapshot: Codable {
    var source: QueueSource?
    var items: [VideoItem] = []
    var index = -1
    var nextPage: Int?
    var active = false
    var canResume = false
    var message: String?
    var playbackId: String?
}
struct VideoQualityOption: Codable, Identifiable {
    let id: String
    let label: String
    var badge: String?
    var disabled = false
}
struct PlaybackQuality: Codable {
    var currentId: String?
    var currentLabel: String?
    var options: [VideoQualityOption] = []
    var width: Int?
    var height: Int?
    var displayName: String { currentId == "0" ? "自动" : currentLabel ?? options.first(where: { $0.id == currentId })?.label ?? "选择清晰度" }
}
struct PlayerState: Codable {
    var bvid = "", title = "", url = ""
    var currentTime: Double = 0, duration: Double = 0
    var paused = true, ended = false
    var part = 1, partCount = 1
    var volume: Double = 1, muted = false, rate: Double = 1
    var danmaku = true, fullscreen = false
    var playbackId: String?, errorCode: String?, errorMessage: String?
    var cover: String?
    var quality: PlaybackQuality?
}
struct RelatedVideos: Decodable { let bvid: String; let items: [VideoItem] }
extension QueueSnapshot {
    func isPlaylist(for player: PlayerState) -> Bool {
        let multiple = source?.kind == "creator" || source?.kind == "collection" || source?.kind == "favorites" || source?.kind == "season" || (source?.kind == "manual" && items.count > 1)
        guard multiple, items.indices.contains(index) else { return false }
        return items[index].bvid == player.bvid || (player.bvid.isEmpty && canResume)
    }
}
struct SystemVolume: Codable { var value: Double = 0; var muted = false; var deviceName = "默认音频输出"; var available = false }
struct Snapshot: Codable {
    var computerName = "电脑"
    var browserConnected = false
    var player = PlayerState()
    var queue = QueueSnapshot()
    var systemVolume = SystemVolume()
    var message: String?
}
struct BrowserTab: Codable, Identifiable { let id: Int; let title: String; let url: String?; let selected: Bool }
struct EmptyResponse: Decodable {}
struct RemoteFailure: LocalizedError, Decodable {
    let code: String
    let message: String
    var errorDescription: String? { message }
    static let disconnected = RemoteFailure(code: "disconnected", message: "电脑尚未连接，请检查设备页。")
}
enum JSONValue: Codable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self { case .string(let v): try container.encode(v); case .number(let v): try container.encode(v); case .bool(let v): try container.encode(v); case .object(let v): try container.encode(v); case .array(let v): try container.encode(v); case .null: try container.encodeNil() }
    }
    static func from<T: Encodable>(_ value: T) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try JSONDecoder().decode(type, from: JSONEncoder().encode(self)) }
}
struct PairingDescriptor: Codable {
    let version: Int
    let host: String
    let port: Int
    let certificateSha256: String
    let pairingToken: String
    static func parse(_ text: String) throws -> PairingDescriptor {
        let bad = RemoteFailure(code: "invalid_pairing", message: "配对信息无效，请重新扫描电脑助手的二维码。")
        guard let url = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "biliremote", url.host == "pair", let encoded = url.queryItems?.first(where: { $0.name == "data" })?.value else { throw bad }
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { throw bad }
        let result = try JSONDecoder().decode(Self.self, from: data)
        let ip = result.host.split(separator: ".", omittingEmptySubsequences: false)
        guard result.version == 1, (1...65535).contains(result.port), ip.count == 4, ip.allSatisfy({ UInt8($0) != nil }), result.certificateSha256.count == 64, result.certificateSha256.allSatisfy({ $0.isHexDigit }), (32...128).contains(result.pairingToken.count) else { throw bad }
        return result
    }
}
struct DeviceConfig: Codable {
    let host: String, port: Int, certificateSha256: String
    let deviceId: String, accessToken: String, computerName: String
}
enum Timecode {
    static func parse(_ input: String) throws -> Double {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }), let last = Int(parts.last!), last < 60, parts.count != 3 || (Int(parts[1]) ?? 60) < 60 else { throw RemoteFailure(code: "invalid_time", message: "请输入 mm:ss 或 hh:mm:ss，例如 12:30。") }
        let values = parts.compactMap { Double($0) }
        guard values.count == parts.count else { throw RemoteFailure(code: "invalid_time", message: "时间数值无效。") }
        let seconds = values.reduce(0) { $0 * 60 + $1 }
        guard seconds.isFinite && seconds <= 864000 else { throw RemoteFailure(code: "invalid_time", message: "跳转时间超出范围。") }
        return seconds
    }
    static func format(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? min(seconds, 864000) : 0))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
    }
}

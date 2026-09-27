import XCTest
@testable import BiliRemote

final class ProtocolTests: XCTestCase {
    func testQualityStateAndOlderHostCompatibility() throws {
        let original = try JSONEncoder().encode(PlayerState(bvid: "BVtest"))
        XCTAssertNil(try JSONDecoder().decode(PlayerState.self, from: original).quality)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        json["quality"] = ["currentId": "80", "currentLabel": "1080P 高清", "width": 1920, "height": 1080, "options": [["id": "112", "label": "1080P 高码率", "badge": "大会员", "disabled": false], ["id": "0", "label": "自动", "disabled": false]]]
        let state = try JSONDecoder().decode(PlayerState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(state.quality?.displayName, "1080P 高清")
        XCTAssertEqual(state.quality?.width, 1920)
        XCTAssertEqual(state.quality?.options.last?.id, "0")
        XCTAssertEqual(state.quality?.options.first?.disabled, false)
        var automatic = try XCTUnwrap(state.quality); automatic.currentId = "0"
        XCTAssertEqual(automatic.displayName, "自动")
    }
    func testPlaylistAndRelatedVideoSelection() {
        let video = VideoItem(bvid: "BV1", title: "第一条", url: "https://www.bilibili.com/video/BV1/")
        let player = PlayerState(bvid: "BV1")
        var queue = QueueSnapshot(source: QueueSource(kind: "manual"), items: [video], index: 0, active: true)
        XCTAssertFalse(queue.isPlaylist(for: player), "A single manually opened video shows recommendations even while its multi-part queue is active")
        queue.source = QueueSource(kind: "creator", creatorId: "123")
        XCTAssertTrue(queue.isPlaylist(for: player))
        queue.source = QueueSource(kind: "collection", url: "https://space.bilibili.com/123/lists/1")
        XCTAssertTrue(queue.isPlaylist(for: player))
        XCTAssertFalse(queue.isPlaylist(for: PlayerState(bvid: "BVElsewhere")), "Manual browser navigation must not display a stale playlist")
        queue.active = false; queue.canResume = true
        XCTAssertTrue(queue.isPlaylist(for: player), "A suspended playlist remains available to resume")
        queue.source = QueueSource(kind: "manual")
        queue.items.append(VideoItem(bvid: "BV2", title: "第二条", url: "https://www.bilibili.com/video/BV2/"))
        XCTAssertTrue(queue.isPlaylist(for: player))
    }
    func testHomeFeedDecodingAndPlaybackItem() throws {
        // Decode through JSONValue, as RemoteTransport does, so numbers take the same path.
        let data = Data(#"{"loggedIn":true,"accountName":"账号","page":2,"nextPage":3,"items":[{"bvid":"BV1a","title":"推荐","url":"https://www.bilibili.com/video/BV1a/","cover":"https://i2.hdslb.com/bfs/archive/cover.jpg","duration":394,"creatorId":"42","creatorName":"UP","views":10328558,"danmaku":16222,"publishedAt":1787386562,"reason":"已关注"},{"bvid":"BV1b","title":"通用推荐","url":"https://www.bilibili.com/video/BV1b/"}]}"#.utf8)
        let feed = try JSONDecoder().decode(JSONValue.self, from: data).decode(HomeFeed.self)
        XCTAssertEqual(feed.items.map(\.bvid), ["BV1a", "BV1b"])
        XCTAssertEqual(feed.items[0].views, 10328558)
        XCTAssertEqual(feed.items[0].publishedAt, 1787386562)
        XCTAssertEqual(feed.items[0].reason, "已关注")
        XCTAssertNil(feed.items[1].views)
        XCTAssertEqual(feed.nextPage, 3)
        XCTAssertEqual(feed.items[0].video, VideoItem(bvid: "BV1a", title: "推荐", url: "https://www.bilibili.com/video/BV1a/", cover: "https://i2.hdslb.com/bfs/archive/cover.jpg", duration: 394, creatorId: "42", creatorName: "UP"))
        let signedOut = try JSONDecoder().decode(HomeFeed.self, from: Data(#"{"loggedIn":false,"page":1,"nextPage":2,"items":[]}"#.utf8))
        XCTAssertFalse(signedOut.loggedIn)
        XCTAssertNil(signedOut.accountName)
    }
    func testExactTimeParsing() throws {
        XCTAssertEqual(try Timecode.parse("12:30"), 750)
        XCTAssertEqual(try Timecode.parse("1:02:03"), 3723)
        XCTAssertEqual(try Timecode.parse("120:00"), 7200)
        for value in ["1:60", "1:99:00", "-1:00", "12", "1::3"] { XCTAssertThrowsError(try Timecode.parse(value)) }
        XCTAssertEqual(Timecode.format(3723), "1:02:03")
    }
    func testPairingValidation() throws {
        let valid = PairingDescriptor(version: 1, host: "192.168.1.8", port: 33391, certificateSha256: String(repeating: "a", count: 64), pairingToken: String(repeating: "b", count: 43))
        func link(_ descriptor: PairingDescriptor) throws -> String { "biliremote://pair?data=" + (try JSONEncoder().encode(descriptor)).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
        XCTAssertEqual(try PairingDescriptor.parse(link(valid)).host, valid.host)
        XCTAssertThrowsError(try PairingDescriptor.parse("https://attacker.test/pair"))
        let invalid = PairingDescriptor(version: 1, host: "192.168.1.8/evil", port: 33391, certificateSha256: valid.certificateSha256, pairingToken: valid.pairingToken)
        XCTAssertThrowsError(try PairingDescriptor.parse(link(invalid)))
    }
    func testJSONValuePreservesBooleanAndNumericTypes() throws {
        let data = Data(#"{"muted":true,"volume":0.35,"part":2}"#.utf8)
        struct Example: Decodable { let muted: Bool; let volume: Double; let part: Int }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        let decoded = try value.decode(Example.self)
        XCTAssertTrue(decoded.muted); XCTAssertEqual(decoded.volume, 0.35); XCTAssertEqual(decoded.part, 2)
    }
}

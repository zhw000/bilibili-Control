import XCTest
@testable import BiliRemote

final class CommunityTests: XCTestCase {
    func testCoverNormalizationHandlesLazyURLsAndOriginalImages() {
        XCTAssertEqual(CoverURL.normalized("//i0.hdslb.com/cover.jpg@320w.avif")?.absoluteString, "https://i0.hdslb.com/cover.jpg")
        XCTAssertEqual(CoverURL.normalized("http://i0.hdslb.com/cover.jpg")?.scheme, "https")
        XCTAssertNil(CoverURL.normalized("data:image/png;base64,AAAA"))
        XCTAssertNil(CoverURL.normalized("http://example.com/image.png"))
        XCTAssertNotNil(CoverURL.normalized("https://i0.hdslb.com"))
    }
    func testCommentStringIDsRemainExact() throws {
        let data = Data(#"{"bvid":"BV1","items":[{"id":"900719925474099312","creatorId":"42","creatorName":"UP","message":"评论","createdAt":123,"likes":2,"replyCount":0,"replies":[]}],"total":1}"#.utf8)
        let page = try JSONDecoder().decode(CommentPage.self, from: data)
        XCTAssertEqual(page.items[0].id, "900719925474099312"); XCTAssertNil(page.nextPage)
    }
    @MainActor func testSiriAndWatchUseQueueBoundariesAndClampedControls() throws {
        var snapshot = Snapshot()
        snapshot.player = PlayerState(bvid: "BV1", volume: 0.97)
        snapshot.queue = QueueSnapshot(source: QueueSource(kind: "favorites", folderId: "42"), items: [VideoItem(bvid: "BV1", title: "One", url: "https://www.bilibili.com/video/BV1/")], index: 0, active: true)
        XCTAssertThrowsError(try RemoteCommandClient.simpleCommand(.previous, snapshot: snapshot))
        XCTAssertThrowsError(try RemoteCommandClient.simpleCommand(.next, snapshot: snapshot))
        snapshot.queue.nextPage = 2
        XCTAssertEqual(try RemoteCommandClient.simpleCommand(.next, snapshot: snapshot)?.method, "queue.next")
        let volume = try XCTUnwrap(RemoteCommandClient.simpleCommand(.volumeUp, snapshot: snapshot))
        XCTAssertEqual(try volume.params["value"]?.decode(Double.self), 1)
        snapshot.queue.active = false; snapshot.queue.canResume = true
        XCTAssertEqual(try RemoteCommandClient.simpleCommand(.play, snapshot: snapshot)?.method, "queue.resume")
        snapshot.player.bvid = "BVChanged"
        XCTAssertEqual(try RemoteCommandClient.simpleCommand(.play, snapshot: snapshot)?.method, "player.command", "Manual browser navigation must not resume a stale queue")
    }
    func testWatchSnapshotIsCredentialFreeAndContainsNavigationState() throws {
        var snapshot = Snapshot(); snapshot.browserConnected = true
        snapshot.player = PlayerState(bvid: "BV1", title: "播放中", currentTime: 30, duration: 100)
        let state = WatchPlaybackState(snapshot: snapshot, connected: true)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WatchPlaybackState.self, from: data)
        XCTAssertTrue(decoded.connected); XCTAssertEqual(decoded.title, "播放中"); XCTAssertFalse(decoded.canPrevious)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["accessToken"]); XCTAssertNil(json["certificateSha256"])
    }
}

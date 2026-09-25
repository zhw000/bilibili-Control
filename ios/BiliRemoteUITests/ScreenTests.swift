import XCTest

final class ScreenTests: XCTestCase {
    @MainActor func testPairingScreenAndNavigation() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["扫描电脑二维码"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["连接并保存"].isEnabled)
        capture(app, "01-device-pairing")
        app.tabBars.buttons["发现"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        capture(app, "02-discovery")
        app.tabBars.buttons["收藏"].tap()
        XCTAssertTrue(app.navigationBars["我的收藏"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["连接电脑，开始遥控"].exists)
        capture(app, "10-favorites-disconnected")
    }
    @MainActor func testPlaybackLayoutWithTestState() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--preview-state"]; app.launch()
        XCTAssertTrue(app.staticTexts["playerTitle"].waitForExistence(timeout: 10))
        assertPlayerFits(app)
        capture(app, "03-playback")
        scrollTo(app.buttons["声音设置"], in: app)
        app.buttons["声音设置"].tap()
        scrollTo(app.staticTexts["电脑音量"], in: app)
        capture(app, "04-volume")
        scrollTo(app.buttons["queueItem-BVPreview2"], in: app)
        XCTAssertFalse(app.tabBars.buttons["队列"].exists)
        XCTAssertEqual(app.scrollViews.count, 1)
        capture(app, "05-inline-queue")
    }
    @MainActor func testQualityPickerShowsCurrentAndUnavailableChoices() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--preview-state"]; app.launch()
        XCTAssertTrue(app.staticTexts["playerTitle"].waitForExistence(timeout: 10))
        scrollTo(app.buttons["videoQuality"], in: app)
        app.buttons["videoQuality"].tap()
        XCTAssertTrue(app.navigationBars["视频清晰度"].waitForExistence(timeout: 5))
        let resolution = app.descendants(matching: .any).matching(identifier: "qualityResolution").firstMatch
        XCTAssertTrue(resolution.exists)
        XCTAssertEqual(resolution.value as? String, "1920 × 1080")
        XCTAssertFalse(app.buttons["quality-120"].isEnabled)
        XCTAssertTrue(app.buttons["quality-80"].isEnabled)
        // Expand the sheet before inspecting lower options on compact devices.
        app.swipeUp()
        XCTAssertTrue(app.buttons["quality-0"].exists)
        capture(app, "11-video-quality")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["正在播放"].exists)
    }
    @MainActor func testRelatedVideosSharePlayerScrollAndFitLandscape() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--preview-state", "--preview-related"]; app.launch()
        XCTAssertTrue(app.staticTexts["playerTitle"].waitForExistence(timeout: 10))
        assertPlayerFits(app)
        scrollTo(app.staticTexts["相关视频 1 · 和朋友一起发现新的风景"], in: app)
        capture(app, "06-inline-related")
        scrollTo(app.staticTexts["相关视频 12 · 和朋友一起发现新的风景"], in: app)
        XCTAssertEqual(app.scrollViews.count, 1)
        capture(app, "07-related-bottom")
        // Relaunch at the top before rotation. Querying hittability of a far-offscreen
        // static text after rotation can itself fail in XCTest's accessibility service.
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["playerTitle"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        assertPlayerFits(app)
        capture(app, "08-landscape")
    }
    @MainActor func testLargeTextKeepsControlsInsideScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--preview-state", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["playerTitle"].waitForExistence(timeout: 10))
        assertPlayerFits(app)
        scrollTo(app.buttons["queueItem-BVPreview2"], in: app)
        capture(app, "09-large-text")
    }
    @MainActor private func assertPlayerFits(_ app: XCUIApplication) {
        let cover = app.descendants(matching: .any).matching(identifier: "playerCover").firstMatch
        XCTAssertTrue(cover.exists)
        XCTAssertEqual(cover.frame.width / cover.frame.height, 16.0 / 9.0, accuracy: 0.02)
        let elements = [cover, app.staticTexts["playerTitle"], app.buttons["currentTime"], app.staticTexts["duration"], app.buttons["上一个视频"], app.buttons["下一个视频"], app.buttons["mainPlaybackButton"]]
        for element in elements {
            XCTAssertTrue(element.exists)
            XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX + 8, element.identifier)
            XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX - 8, element.identifier)
        }
    }
    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

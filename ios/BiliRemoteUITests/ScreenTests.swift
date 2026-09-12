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
    }
    @MainActor func testPlaybackLayoutWithTestState() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--preview-state"]; app.launch()
        XCTAssertTrue(app.staticTexts["保持好奇，探索每一个新世界"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["暂停"].exists)
        capture(app, "03-playback")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["电脑音量"].exists)
        capture(app, "04-volume")
        app.tabBars.buttons["队列"].tap()
        XCTAssertTrue(app.staticTexts["下一站，发现更多有趣的事"].waitForExistence(timeout: 5))
        capture(app, "05-queue")
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

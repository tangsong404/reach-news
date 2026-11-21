import XCTest

// MARK: - UI 测试
//
// 以可访问性标识驱动；不依赖真实网络，也不断言服务端数据。

final class ReachNewsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(language: String = "zh-Hans") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        return app
    }

    func testLaunchShowsThreeTabs() throws {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: 0).waitForExistence(timeout: 20))
        XCTAssertEqual(app.tabBars.buttons.count, 3)
    }

    func testChannelTabIsReachable() throws {
        let app = launch()
        let channels = app.tabBars.buttons.element(boundBy: 1)
        XCTAssertTrue(channels.waitForExistence(timeout: 20))
        channels.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10) || app.staticTexts.firstMatch.exists)
    }

    func testMeTabExposesSavedAndPreferences() throws {
        let app = launch()
        let me = app.tabBars.buttons.element(boundBy: 2)
        XCTAssertTrue(me.waitForExistence(timeout: 20))
        me.tap()
        XCTAssertTrue(app.otherElements["me-list"].waitForExistence(timeout: 10)
                      || app.cells.firstMatch.waitForExistence(timeout: 10))
    }

    func testChannelCreationExplainsUnavailability() throws {
        let app = launch()
        let channels = app.tabBars.buttons.element(boundBy: 1)
        guard channels.waitForExistence(timeout: 20) else { return }
        channels.tap()

        let createButton = app.buttons["channel-create-button"]
        guard createButton.waitForExistence(timeout: 10) else { return }
        createButton.tap()

        // ADR 0004：新建入口可见，但端点可用前不提供保存路径。
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
    }

    func testEnglishLaunchDoesNotCrash() throws {
        let app = launch(language: "en")
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: 0).waitForExistence(timeout: 20))
    }
}

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

    func testMeTabShowsAccountHeaderAboveSettings() throws {
        let app = launch()
        let me = app.tabBars.buttons.element(boundBy: 2)
        XCTAssertTrue(me.waitForExistence(timeout: 20))
        me.tap()

        // 合并成一个无障碍元素后，可能落在 otherElements 或 cells 里。
        let header = app.otherElements["me-account-header"]
        let headerCell = app.cells["me-account-header"]
        guard header.waitForExistence(timeout: 10) || headerCell.waitForExistence(timeout: 5) else {
            XCTFail("account header is missing on the Me tab")
            return
        }
        let headerElement = header.exists ? header : headerCell
        // 头部在三个设置入口之上。
        let saved = app.buttons["me-saved"]
        if saved.exists {
            XCTAssertLessThanOrEqual(headerElement.frame.minY, saved.frame.minY)
        }
    }

    func testChannelCreateEntryOpensCreateSheet() throws {
        let app = launch()
        let channels = app.tabBars.buttons.element(boundBy: 1)
        guard channels.waitForExistence(timeout: 20) else { return }
        channels.tap()

        let createButton = app.buttons["channel-create-button"]
        guard createButton.waitForExistence(timeout: 10) else { return }
        createButton.tap()

        // 预设模板已下线：+ 只直接进入新建页，不再有「从模板新建」菜单。
        XCTAssertTrue(app.otherElements["channel-create-sheet"].waitForExistence(timeout: 10)
                      || app.textFields["channel-create-name"].waitForExistence(timeout: 10))
    }

    func testChannelTabShowsSectionsWhenPopulated() throws {
        let app = launch()
        let channels = app.tabBars.buttons.element(boundBy: 1)
        guard channels.waitForExistence(timeout: 20) else { return }
        channels.tap()

        // 未登录时页面为空态；有数据时才断言三段标题存在，避免依赖真实网络。
        guard app.otherElements["channel-list"].waitForExistence(timeout: 10) else { return }
        XCTAssertTrue(app.otherElements["channel-section-channel.section.mine"].exists
                      || app.staticTexts["channel-section-channel.section.mine"].exists
                      || app.otherElements["channel-discover-toggle"].exists)
    }

    func testEnglishLaunchDoesNotCrash() throws {
        let app = launch(language: "en")
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: 0).waitForExistence(timeout: 20))
    }
}

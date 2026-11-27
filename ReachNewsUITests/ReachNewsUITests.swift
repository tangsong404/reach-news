import XCTest

/// Runs the real app and native UIKit/SwiftUI controls with an explicit offline launch fixture.
/// Screenshots are device screenshots, not ImageRenderer output.
final class ReachNewsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["UI_TEST_APPEARANCE"] = appearance
        app.launchEnvironment["UI_TEST_STYLE"] = "editorial"
        app.launch()
        XCTAssertTrue(element("feed-row-ui-fixture-brief", in: app).waitForExistence(timeout: 15))
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFeedLayoutAndActualArticleNavigation() throws {
        let app = launch()
        assertFeedLayout(in: app)
        screenshot("feed-editorial-light")

        let row = element("feed-row-ui-fixture-brief", in: app)
        XCTAssertTrue(row.isHittable)
        row.tap()
        XCTAssertTrue(element("brief-detail", in: app).waitForExistence(timeout: 10), "Tapping the actual feed row must navigate to detail")
        XCTAssertTrue(app.searchFields["brief-ask-field"].waitForExistence(timeout: 10), "Detail must expose the native ask field")
        XCTAssertEqual(app.tabBars.count, 0, "Only the three root pages show the tab bar")
        screenshot("detail-editorial-light")

        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(element("brief-detail", in: app).waitForExistence(timeout: 10), "Navigation must still work after going back")
    }

    func testArticleTapWhileSearchKeyboardIsVisible() throws {
        let app = launch()
        let search = app.searchFields["feed-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Feed search must be UISearchBar's native search field")
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("离线")
        let row = element("feed-row-ui-fixture-brief", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        row.tap()
        XCTAssertTrue(element("brief-detail", in: app).waitForExistence(timeout: 10), "Keyboard dismissal must not consume the article tap")
        screenshot("detail-after-search-tap")
    }

    func testNativeAskFieldFocusAndDismissal() throws {
        let app = launch()
        element("feed-row-ui-fixture-brief", in: app).tap()
        XCTAssertTrue(element("brief-detail", in: app).waitForExistence(timeout: 10))
        let ask = app.searchFields["brief-ask-field"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        ask.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        ask.typeText("后续影响是什么")
        screenshot("detail-native-ask-keyboard")

        // Tap the article title, not the input/toolbar; the background observer must dismiss only the keyboard.
        let title = app.staticTexts["离线测试日报：市场与技术动态"]
        XCTAssertTrue(title.isHittable)
        title.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("brief-detail", in: app).exists)
        screenshot("detail-native-ask-dismissed")
    }

    func testDarkFeedAndDetailScreenshots() throws {
        let app = launch(appearance: "dark")
        assertFeedLayout(in: app)
        screenshot("feed-editorial-dark")
        element("feed-row-ui-fixture-brief", in: app).tap()
        XCTAssertTrue(element("brief-detail", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.searchFields["brief-ask-field"].waitForExistence(timeout: 5))
        screenshot("detail-editorial-dark")
    }

    private func assertFeedLayout(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let brand = element("feed-brand", in: app)
        let search = app.searchFields["feed-search-field"]
        let meta = element("feed-meta", in: app)
        let date = element("feed-date-header", in: app)
        let article = element("feed-row-ui-fixture-brief", in: app)
        for item in [brand, search, meta, date, article] {
            XCTAssertTrue(item.waitForExistence(timeout: 10), file: file, line: line)
        }
        XCTAssertLessThanOrEqual(brand.frame.maxY, search.frame.minY + 2, "Brand must be above search, not below it or centered in the toolbar", file: file, line: line)
        XCTAssertLessThanOrEqual(meta.frame.maxY, date.frame.minY + 2, file: file, line: line)
        XCTAssertLessThanOrEqual(date.frame.minY - meta.frame.maxY, 28, "Metadata/date gap must not inherit List minimum row height", file: file, line: line)
        XCTAssertLessThanOrEqual(article.frame.minY - date.frame.maxY, 24, "Date/article gap must remain compact", file: file, line: line)
    }
}

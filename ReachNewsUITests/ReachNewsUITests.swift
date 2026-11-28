import XCTest

/// Runs the real app and native UIKit/SwiftUI controls with an explicit offline launch fixture.
/// Screenshots are device screenshots, not ImageRenderer output.
final class ReachNewsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(appearance: String = "light", accessibilityText: Bool = false, style: String = "editorial") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if accessibilityText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchEnvironment["UI_TEST_APPEARANCE"] = appearance
        app.launchEnvironment["UI_TEST_STYLE"] = style
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
        let returnedRow = element("feed-row-ui-fixture-brief", in: app)
        XCTAssertTrue(returnedRow.waitForExistence(timeout: 10))
        returnedRow.tap()
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

    func testGroupedSettingsNavigationAndTextSize() throws {
        let app = launch()
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(element("me-preferences", in: app).waitForExistence(timeout: 10))
        screenshot("settings-me-light")
        element("me-plan", in: app).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        screenshot("subscription-unavailable")
        app.alerts.buttons["完成"].tap()
        app.tabBars.buttons["频道"].tap()
        screenshot("density-channels")
        app.tabBars.buttons["我的"].tap()
        element("me-account-card", in: app).tap()
        XCTAssertTrue(element("account-detail", in: app).waitForExistence(timeout: 10))
        screenshot("settings-account-light")
        XCTAssertFalse(app.staticTexts["套餐"].exists)
        element("account-edit-password", in: app).tap()
        XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout: 10))
        screenshot("settings-password-light")
        app.buttons["取消"].firstMatch.tap()
        element("account-edit-nickname", in: app).tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10))
        screenshot("settings-nickname-light")
        app.buttons["取消"].firstMatch.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        element("me-preferences", in: app).tap()
        XCTAssertTrue(element("appearance-reading", in: app).waitForExistence(timeout: 10))
        screenshot("settings-appearance-light")
        let styleRow = element("preferences-style", in: app)
        XCTAssertLessThanOrEqual(styleRow.frame.height, 64, "Ordinary settings rows should use medium density, not stacked minimum heights")
        XCTAssertFalse(element("preferences-text-preview", in: app).exists)
        let slider = app.sliders["preferences-text-size-slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.8)
        screenshot("settings-text-slider-larger")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        element("me-help", in: app).tap()
        XCTAssertTrue(element("help-about", in: app).waitForExistence(timeout: 10))
        screenshot("settings-help-light")
        element("help-check-updates", in: app).tap()
        XCTAssertTrue(element("update-check-page", in: app).waitForExistence(timeout: 10))
        element("update-check-button", in: app).tap()
        XCTAssertTrue(app.staticTexts["更新检查暂不可用，等待服务端接口接入。"].waitForExistence(timeout: 5))
        screenshot("updates-unavailable")
    }

    func testCollectorSkillSelection() throws {
        let app = launch()
        app.tabBars.buttons["频道"].tap()
        element("channel-create-button", in: app).tap()
        XCTAssertTrue(element("channel-create-sheet", in: app).waitForExistence(timeout: 10))
        let sources = element("channel-create-connectors", in: app)
        if !sources.isHittable { app.swipeUp() }
        sources.tap()
        let source = element("collector-picker-ui-fixture-skill", in: app)
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        screenshot("collector-sources")
        source.tap()
        element("collector-picker-done", in: app).tap()
        XCTAssertTrue(element("channel-create-enabled", in: app).exists)
        screenshot("collector-create-binding")
    }

    func testAccountCardHitRegions() throws {
        let app = launch()
        app.tabBars.buttons["我的"].tap()
        for point in [CGVector(dx: 0.03, dy: 0.10), CGVector(dx: 0.85, dy: 0.5), CGVector(dx: 0.5, dy: 0.90)] {
            let card = element("me-account-card", in: app)
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.coordinate(withNormalizedOffset: point).tap()
            XCTAssertTrue(element("account-detail", in: app).waitForExistence(timeout: 10))
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    func testRootTitlesUseLeadingNavigationSpace() throws {
        let app = launch()
        let feed = element("feed-brand", in: app)
        let feedFrame = feed.frame
        XCTAssertLessThan(feedFrame.minY, 120, "Root title should use top toolbar, not a low content row")
        app.tabBars.buttons["频道"].tap()
        let channels = element("main-heading-channels", in: app)
        XCTAssertTrue(channels.waitForExistence(timeout: 5))
        XCTAssertLessThan(channels.frame.minY, 120)
        screenshot("root-channels-top")
        app.tabBars.buttons["我的"].tap()
        let me = element("main-heading-me", in: app)
        XCTAssertTrue(me.waitForExistence(timeout: 5))
        XCTAssertLessThan(me.frame.minY, 120)
        let channelsHeight = feedFrame.height
        XCTAssertEqual(me.frame.height, channelsHeight, accuracy: 4)
        screenshot("root-me-top")
    }

    func testQuestionUsesKeyboardSendOnly() throws {
        let app = launch()
        element("feed-row-ui-fixture-brief", in: app).tap()
        let field = app.searchFields["brief-ask-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertFalse(element("brief-ask-send", in: app).exists)
        field.tap()
        field.typeText("后续影响是什么\n")
        XCTAssertTrue(element("ask-view", in: app).waitForExistence(timeout: 10))
        screenshot("ask-keyboard-send")
    }

    func testGroupedSettingsDarkScreenshots() throws {
        let app = launch(appearance: "dark")
        app.tabBars.buttons["我的"].tap()
        screenshot("settings-me-dark")
        element("me-preferences", in: app).tap()
        XCTAssertTrue(element("appearance-reading", in: app).waitForExistence(timeout: 10))
        screenshot("settings-appearance-dark")
    }

    func testPlainTitleHierarchyAndDensityScreenshots() throws {
        let app = launch(style: "plain")
        screenshot("density-feed-plain")
        element("feed-row-ui-fixture-brief", in: app).tap()
        XCTAssertTrue(element("brief-detail", in: app).waitForExistence(timeout: 10))
        screenshot("density-detail-plain-headings")
    }

    func testSettingsAccessibilityTextLayout() throws {
        let app = launch(accessibilityText: true)
        app.tabBars.buttons["我的"].tap()
        element("me-preferences", in: app).tap()
        XCTAssertTrue(element("appearance-reading", in: app).waitForExistence(timeout: 10))
        screenshot("settings-accessibility-text")
        // Fixed icon columns must not overflow when text grows to AX5.
        let row = element("preferences-style", in: app)
        XCTAssertTrue(row.exists)
        XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(row.frame.minX, app.frame.minX - 1)
    }

    private func assertFeedLayout(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let brand = element("feed-brand", in: app)
        let search = app.searchFields["feed-search-field"]
        XCTAssertFalse(element("feed-meta", in: app).exists, "Removed count row must not reappear")
        XCTAssertFalse(element("feed-date-header", in: app).exists)
        let date = element("feed-row-time-ui-fixture-brief", in: app)
        let article = element("feed-row-ui-fixture-brief", in: app)
        for item in [brand, search, date, article] {
            XCTAssertTrue(item.waitForExistence(timeout: 10), file: file, line: line)
        }
        XCTAssertLessThanOrEqual(brand.frame.maxY, search.frame.minY + 2, "Brand must be above search, not below it or centered in the toolbar", file: file, line: line)
        XCTAssertGreaterThanOrEqual(date.frame.midX, article.frame.midX, "Time must be in the article row trailing half", file: file, line: line)
        XCTAssertGreaterThan(date.frame.midY, article.frame.midY, "Time must be in the article row lower half", file: file, line: line)
    }
}

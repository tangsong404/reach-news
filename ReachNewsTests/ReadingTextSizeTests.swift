import XCTest
import SwiftUI
import UIKit
@testable import ReachNews

@MainActor
final class ReadingTextSizeTests: XCTestCase {
    func testDefaultAndInvalidPreferenceUseStandard() {
        let preferences = InMemoryPreferences()
        XCTAssertEqual(AppearanceStore(preferences: preferences).textSize, .standard)
        preferences.readingTextSize = "invalid-size"
        XCTAssertEqual(AppearanceStore(preferences: preferences).textSize, .standard)
    }

    func testSelectingTextSizePersistsAndRestoresStore() {
        let preferences = InMemoryPreferences()
        let appearance = AppearanceStore(preferences: preferences)
        for size in ReadingTextSize.allCases {
            appearance.select(textSize: size)
            XCTAssertEqual(appearance.textSize, size)
            XCTAssertEqual(preferences.readingTextSize, size.rawValue)
            XCTAssertEqual(AppearanceStore(preferences: preferences).textSize, size)
        }
    }

    func testUserDefaultsPersistenceAcrossInstances() throws {
        let suiteName = "ReadingTextSizeTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = UserDefaultsPreferences(defaults: defaults)
        AppearanceStore(preferences: first).select(textSize: .large)
        let restored = UserDefaultsPreferences(defaults: defaults)
        XCTAssertEqual(AppearanceStore(preferences: restored).textSize, .large)
    }

    func testAppPreferenceCombinesWithSystemDynamicType() {
        for category in [DynamicTypeSize.large, .xxxLarge, .accessibility3, .accessibility5] {
            let small = ResolvedTypography(textSize: .small, dynamicTypeSize: category).scaledSize(17)
            let standard = ResolvedTypography(textSize: .standard, dynamicTypeSize: category).scaledSize(17)
            let large = ResolvedTypography(textSize: .large, dynamicTypeSize: category).scaledSize(17)
            XCTAssertLessThan(small, standard)
            XCTAssertLessThan(standard, large)
        }
        let standard = ResolvedTypography(textSize: .standard, dynamicTypeSize: .large).scaledSize(17)
        let accessible = ResolvedTypography(textSize: .small, dynamicTypeSize: .accessibility5).scaledSize(17)
        XCTAssertGreaterThan(accessible, standard, "Small app preference must not cancel the system's accessibility enlargement")
    }

    func testMinimumReadableSizeIsPreserved() {
        let typography = ResolvedTypography(textSize: .small, dynamicTypeSize: .large)
        XCTAssertGreaterThanOrEqual(typography.scaledSize(9), TypeFace.minimumSize)
    }

    func testInlineHeadingMatchesResolvedThemeSizeExactlyOnce() {
        for style in ReaderStyle.allCases {
            for size in ReadingTextSize.allCases {
                let typography = ResolvedTypography(textSize: size, dynamicTypeSize: .accessibility2)
                let multiplier = style == .editorial ? Theme.editorialHeadingScale : Theme.plainHeadingScale
                let font = typography.headingUIFont(size: 19, style: style)
                XCTAssertEqual(font.pointSize, typography.scaledSize(19 * multiplier), accuracy: 0.001)
                let (attributed, _) = InlineFollowHeading.attributedText(
                    text: "中文 English",
                    fontSize: 19,
                    style: style,
                    typography: typography
                )
                let actual = attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
                XCTAssertEqual(actual?.pointSize ?? 0, font.pointSize, accuracy: 0.001)
                XCTAssertEqual(actual?.familyName, font.familyName)
            }
        }
    }
}

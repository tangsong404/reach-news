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

    func testContinuousScaleClampsAndPersists() {
        let preferences = InMemoryPreferences()
        let store = AppearanceStore(preferences: preferences)
        for (input, expected) in [(-1.0, 0.90), (0.977, 0.977), (1.1234, 1.1234), (9.0, 1.15), (Double.nan, 1.0), (Double.infinity, 1.0)] {
            store.select(textScale: input)
            XCTAssertEqual(store.textScale, expected, accuracy: 0.00001)
            XCTAssertEqual(preferences.readingTextScale ?? 0, expected, accuracy: 0.00001)
            XCTAssertEqual(AppearanceStore(preferences: preferences).textScale, expected, accuracy: 0.00001)
        }
    }

    func testLegacySizeMigratesOnlyWhenNumericScaleAbsent() {
        for legacy in ReadingTextSize.allCases {
            let preferences = InMemoryPreferences()
            preferences.readingTextSize = legacy.rawValue
            let store = AppearanceStore(preferences: preferences)
            XCTAssertEqual(store.textScale, Double(legacy.scale), accuracy: 0.00001)
            XCTAssertNotNil(preferences.readingTextScale)
            preferences.readingTextSize = "large"
            XCTAssertEqual(AppearanceStore(preferences: preferences).textScale, store.textScale)
        }
    }

    func testContinuousScaleRespectsAllSystemCategories() {
        for category in [DynamicTypeSize.large, .xxxLarge, .accessibility3, .accessibility5] {
            let smaller = ResolvedTypography(textScale: 0.90, dynamicTypeSize: category).scaledSize(17)
            let standard = ResolvedTypography(textScale: 1, dynamicTypeSize: category).scaledSize(17)
            let larger = ResolvedTypography(textScale: 1.15, dynamicTypeSize: category).scaledSize(17)
            XCTAssertLessThan(smaller, standard)
            XCTAssertLessThan(standard, larger)
        }
        XCTAssertGreaterThan(ResolvedTypography(textScale: 0.90, dynamicTypeSize: .accessibility5).scaledSize(17), ResolvedTypography().scaledSize(17))
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
        AppearanceStore(preferences: first).select(textScale: 1.1234)
        let restored = UserDefaultsPreferences(defaults: defaults)
        XCTAssertEqual(AppearanceStore(preferences: restored).textScale, 1.1234, accuracy: 0.00001)
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

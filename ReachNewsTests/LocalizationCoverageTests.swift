import XCTest
@testable import ReachNews

/// 动态拼出来的本地化键（枚举的 labelKey）也必须存在。
///
/// 「风格」那一行一直显示 `appearance.style.editorial` 这种原始键名，
/// 就是因为代码拼的是 `appearance.style.*`，而词表里只有 `preferences.style.*`。
/// 静态扫描字面量抓不到这类键，所以这里把所有枚举列一遍。
final class LocalizationCoverageTests: XCTestCase {

    func testEveryEnumLabelKeyExistsInBothLanguages() throws {
        var keys: [String] = []
        for value in ReaderStyle.allCases { keys.append(value.labelKey) }
        for value in AppearanceMode.allCases { keys.append(value.labelKey) }
        for value in ThemeTint.allCases { keys.append(value.labelKey) }
        for value in LanguagePreference.allCases { keys.append(value.labelKey) }
        for value in FeedTimeFilter.allCases { keys.append(value.labelKey) }

        let zh = try Self.keys(language: "zh-Hans")
        let en = try Self.keys(language: "en")
        XCTAssertFalse(zh.isEmpty)
        for key in keys {
            XCTAssertTrue(zh.contains(key), "zh-Hans 缺少 \(key)")
            XCTAssertTrue(en.contains(key), "en 缺少 \(key)")
        }
    }

    /// 代码里所有字面量 L10n 键也要存在（防止再出现只改一边的情况）。
    func testLiteralL10nKeysExist() throws {
        let zh = try Self.keys(language: "zh-Hans")
        let required = [
            "ask.bar.placeholder", "ask.bar.send",
            "brief.save.confirm.title", "brief.save.remove.title",
            "me.saved.add", "preferences.appearanceMode"
        ]
        for key in required {
            XCTAssertTrue(zh.contains(key), "zh-Hans 缺少 \(key)")
        }
    }

    private static func keys(language: String) throws -> Set<String> {
        guard let path = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language) else {
            return []
        }
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        var result = Set<String>()
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""), let equals = trimmed.range(of: "\" =") else { continue }
            let key = String(trimmed.dropFirst().prefix(upTo: equals.lowerBound))
            result.insert(key)
        }
        return result
    }
}

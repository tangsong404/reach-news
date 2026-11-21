import XCTest
@testable import ReachNews

// MARK: - Fixture 可达性
//
// 契约要求样本覆盖特定边界；这里核对测试包里真的能拿到这些样本，
// 避免测试因为缺文件而"静默通过"。

final class FixtureReachabilityTests: XCTestCase {
    private let requiredFixtures = ["channels", "briefs", "materials", "runs", "cursor", "ask", "errors"]

    func testAllRequiredFixturesAreBundled() throws {
        for name in requiredFixtures {
            let data = try Fixture.data(name)
            XCTAssertFalse(data.isEmpty, "\(name).json is empty")
        }
    }

    func testFixturesAreValidJSON() throws {
        for name in requiredFixtures {
            let data = try Fixture.data(name)
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data), "\(name).json is not valid JSON")
        }
    }

    func testCoverageRequirementsFromContract() throws {
        // client-contract 要求样本覆盖：lastBriefAt null、connectorIds []、
        // missed + no-material、failed、多分组、条目引用多个素材。
        let channels = try JSONDecoder()
            .decode(PageEnvelope<ChannelDTO>.self, from: try Fixture.data("channels"))
            .items.map { $0.toDomain() }
        XCTAssertTrue(channels.contains { $0.lastBriefAt == nil })
        XCTAssertTrue(channels.contains { $0.connectorIDs.isEmpty })

        let runs = try JSONDecoder()
            .decode(PageEnvelope<RunDTO>.self, from: try Fixture.data("runs"))
            .items.map { $0.toDomain() }
        XCTAssertTrue(runs.contains { $0.state == .missed && $0.missedReason == .noMaterial })
        XCTAssertTrue(runs.contains { $0.state == .failed })

        let briefs = try JSONDecoder()
            .decode(PageEnvelope<BriefDTO>.self, from: try Fixture.data("briefs"))
            .items.map { $0.toDomain() }
        XCTAssertTrue(briefs.contains { $0.sections.count > 1 })
        XCTAssertTrue(briefs.contains { brief in
            brief.sections.contains { $0.entries.contains { $0.materialIDs.count > 1 } }
        })
    }

    func testSchemaContentExistsForEveryCoveredRequirement() throws {
        // 规格文件必须随 change 一起存在，且覆盖验收涉及的章节。
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let spec = root
            .appendingPathComponent("docs/comet/changes/redesign-ios-client/specs/ios-client/spec.md")
        let text = try String(contentsOf: spec, encoding: .utf8)

        for heading in ["领域模型", "字段归一化", "日报流", "筛选面板", "追问", "频道编辑", "鉴权与连接", "分页", "轮询", "持久化", "本地化"] {
            XCTAssertTrue(text.contains(heading), "spec.md missing section: \(heading)")
        }
    }
}

// MARK: - 本地化键集对齐
//
// 中英文键集必须完全一致，且界面不残留硬编码文案。

final class LocalizationTests: XCTestCase {
    func testChineseAndEnglishKeySetsMatch() throws {
        let zh = try keys(in: "Localizable", table: nil, language: "zh-Hans")
        let en = try keys(in: "Localizable", table: nil, language: "en")

        XCTAssertFalse(zh.isEmpty)
        XCTAssertFalse(en.isEmpty)
        XCTAssertEqual(zh.symmetricDifference(en), [], "key mismatch between zh-Hans and en")
    }

    func testRequiredKeysExistInBothLanguages() throws {
        let required = [
            "tab.briefs", "tab.channels", "tab.me",
            "feed.search.placeholder", "feed.filter.button",
            "channel.state.running", "channel.state.missed", "channel.state.failed",
            "channelEdit.busy.title", "channelEdit.busy.detail",
            "ask.pill", "ask.cited.heading", "ask.cited.deterministic",
            "channel.create.title", "channel.create.submit",
            "error.offline", "error.unauthorized", "error.busy",
            "me.saved", "me.preferences", "me.connection",
            "common.featureInProgress"
        ]
        let zh = try keys(in: "Localizable", table: nil, language: "zh-Hans")
        let en = try keys(in: "Localizable", table: nil, language: "en")
        for key in required {
            XCTAssertTrue(zh.contains(key), "zh-Hans missing \(key)")
            XCTAssertTrue(en.contains(key), "en missing \(key)")
        }
    }

    /// 文案随 App 目标打包。单元测试宿主就是 App，因此取 Bundle.main 的 .lproj。
    private func keys(in name: String, table: String?, language: String) throws -> Set<String> {
        let appBundle = Bundle.main
        guard let path = appBundle.path(forResource: name, ofType: "strings", inDirectory: nil, forLocalization: language) else {
            XCTFail("missing \(language) strings table in \(appBundle.bundlePath)")
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

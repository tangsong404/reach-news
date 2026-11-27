import XCTest
import SwiftUI
@testable import ReachNews

// MARK: - 小标题「跟踪」按钮的事件预填
//
// 小标题右侧的「跟踪」按钮直接进入频道创建页，并把名称与提示词预填好。
// 这里覆盖预填内容的生成；不再有「查看原文」，因此也没有标题↔素材匹配的测试。

final class BriefHeadingTests: XCTestCase {

    func testEventDraftNameUsesHeadingText() {
        XCTAssertEqual(TrackedEventDraft.name(heading: "  模型竞赛进入下半场  "), "模型竞赛进入下半场")
    }

    func testEventDraftNameIsOnlyTrimmedNotRewritten() {
        // 不改写文字本身：去掉冒号之类会让预填内容与标题对不上。
        XCTAssertEqual(TrackedEventDraft.name(heading: "来源："), "来源：")
        XCTAssertEqual(TrackedEventDraft.name(heading: "  "), "")
    }

    func testEventDraftPromptEmbedsHeading() {
        let prompt = TrackedEventDraft.prompt(
            heading: "模型竞赛进入下半场",
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertTrue(prompt.contains("模型竞赛进入下半场"))
        XCTAssertFalse(prompt.isEmpty)
        // 模板里不该残留未替换的占位符。
        XCTAssertFalse(prompt.contains("%@"))
    }

    func testEventDraftPromptIsLocalized() {
        let en = TrackedEventDraft.prompt(heading: "Model race", locale: Locale(identifier: "en"))
        let zh = TrackedEventDraft.prompt(heading: "Model race", locale: Locale(identifier: "zh-Hans"))

        XCTAssertTrue(en.contains("Model race"))
        XCTAssertNotEqual(en, zh)
    }
}

// MARK: - 正文链接着色
//
// 用户明确不要颜色区分：链接文字保持正文色，改用下划线 + 链条图标。
// 下划线是纯 AttributedString 属性，不需要渲染就能断言。

final class BriefLinkColoringTests: XCTestCase {

    private func attributed(_ markdown: String) -> AttributedString {
        MarkdownBlockBuilder.attributed(from: markdown)
    }

    func testLinkRunsAreUnderlined() {
        let marked = MarkdownBlockBuilder.underliningLinks(
            attributed("看这条 [原文](https://example.test/a) 的报道。")
        )

        let linked = marked.runs.filter { $0.link != nil }
        XCTAssertFalse(linked.isEmpty, "markdown 里的链接应当产生 link run")
        for run in linked {
            XCTAssertEqual(run.underlineStyle, .single)
        }
    }

    func testLinkRunsKeepBodyColor() {
        let marked = MarkdownBlockBuilder.underliningLinks(
            attributed("看这条 [原文](https://example.test/a)。")
        )

        // 链接必须显式写死正文色：不写的话 SwiftUI 会按 tint 上色，
        // 换主题色或默认 tint 时链接就会变成蓝色。
        var checked = 0
        for run in marked.runs where run.link != nil {
            XCTAssertEqual(run.foregroundColor, Palette.ink)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }

    func testNonLinkRunsGetNoUnderlineOrColor() {
        let source = attributed("普通文字，与 [链接](https://example.test/a)。")
        let marked = MarkdownBlockBuilder.underliningLinks(source)

        let plain = marked.runs.filter { $0.link == nil }
        XCTAssertFalse(plain.isEmpty)
        for run in plain {
            XCTAssertNil(run.foregroundColor)
            XCTAssertNil(run.underlineStyle)
        }
    }

    func testTextWithoutLinksIsUnchanged() {
        let source = attributed("只有正文，没有任何链接。")
        let marked = MarkdownBlockBuilder.underliningLinks(source)

        XCTAssertEqual(String(marked.characters), String(source.characters))
        for run in marked.runs {
            XCTAssertNil(run.underlineStyle)
        }
    }

    func testSplitAppliesUnderlineToEveryBlock() {
        // 标题里也放一个链接，避免只覆盖段落与列表却在名字上宣称覆盖标题。
        let markdown = """
        ## 标题里的 [链接零](https://example.test/0)

        段落里有 [链接一](https://example.test/1)。

        - 列表里有 [链接二](https://example.test/2)
        """
        let blocks = MarkdownBlockBuilder.split(attributed(markdown))

        let headings = blocks.filter { if case .heading = $0.kind { return true }; return false }
        let paragraphs = blocks.filter { $0.kind == .paragraph }
        let listItems = blocks.filter { if case .listItem = $0.kind { return true }; return false }

        for (name, group) in [("heading", headings), ("paragraph", paragraphs), ("listItem", listItems)] {
            let linkRuns = group.flatMap { $0.text.runs.filter { $0.link != nil } }
            XCTAssertFalse(linkRuns.isEmpty, "\(name) 里应当有 link run")
            for run in linkRuns {
                XCTAssertEqual(run.underlineStyle, .single)
            }
        }
    }
}

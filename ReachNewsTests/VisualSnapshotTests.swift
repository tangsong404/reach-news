import XCTest
import SwiftUI
@testable import ReachNews

// MARK: - 视觉快照
//
// 用 ImageRenderer 把关键视图离屏渲染成 PNG，挂到测试附件里。
// CI 的单元测试任务会把附件导出成 artifact，人和 Agent 都能直接看图，
// 用于验证「铃铛跟文字对齐没有」「两种风格的字体/底色差异」这类纯观感问题。

@MainActor
final class VisualSnapshotTests: XCTestCase {

    private let longHeading = "## 央行下调存款准备金率与市场影响\n\n正文里有一个 [外部链接](https://example.com) 紧跟其后，用来检查下划线与图标位置。"

    /// 正文段落与链接（纯 SwiftUI，可以离屏渲染）。
    /// 小标题带 UIViewRepresentable，ImageRenderer 渲染不了，
    /// 那条链路由 InlineFollowLayoutTests 做确定性验证。
    func testParagraphAndLinkEditorial() {
        snapshot(markdownView(style: .editorial), name: "paragraph-editorial")
    }

    func testParagraphAndLinkPlain() {
        snapshot(markdownView(style: .plain), name: "paragraph-plain")
    }

    /// 记录当前系统里可用的中文字体，避免再靠猜字体名。
    func testFontAvailabilityReport() {
        let candidates = ["SongtiSC-Regular", "Songti SC", "STSongti-SC-Regular", "HiraMinProN-W3"]
        var lines = ["candidate -> resolved"]
        for name in candidates {
            lines.append("\(name) -> \(UIFont(name: name, size: 17)?.fontName ?? "nil")")
        }
        lines.append("families containing song/serif:")
        for family in UIFont.familyNames where family.lowercased().contains("song") || family.lowercased().contains("serif") {
            lines.append("  \(family): \(UIFont.fontNames(forFamilyName: family).prefix(3))")
        }
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "font-report"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func markdownView(style: ReaderStyle) -> some View {
        MarkdownBodyView(
            markdown: longHeading,
            onOpenURL: { _ in },
            onTrackHeading: nil,
            style: style
        )
    }

    private func snapshot<V: View>(_ view: V, name: String, width: CGFloat = 390) {
        let content = view
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.l)
            .frame(width: width, alignment: .leading)
            .background(Theme.canvas(for: .editorial))

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.uiImage else {
            XCTFail("ImageRenderer 渲染失败：\(name)")
            return
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

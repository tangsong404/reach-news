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

    func testHeadingWithFollowEditorial() {
        snapshot(markdownView(style: .editorial), name: "heading-editorial")
    }

    func testHeadingWithFollowPlain() {
        snapshot(markdownView(style: .plain), name: "heading-plain")
    }

    /// 窄宽度强制标题折行，检查折行时铃铛是否贴最后一行文字。
    func testWrappedHeadingFollow() {
        let view = MarkdownBodyView(
            markdown: longHeading,
            onOpenURL: { _ in },
            onTrackHeading: { _ in },
            style: .editorial
        )
        snapshot(view, name: "heading-wrapped", width: 300)
    }

    private func markdownView(style: ReaderStyle) -> some View {
        MarkdownBodyView(
            markdown: longHeading,
            onOpenURL: { _ in },
            onTrackHeading: { _ in },
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

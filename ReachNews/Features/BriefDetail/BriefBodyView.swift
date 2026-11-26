import SwiftUI

// MARK: - 正文渲染
//
// 正文只有段落与行内链接：没有小标题、加粗或图片，因此不做 Markdown 解析。
// 按长文阅读排版：段落之间留出正常正文间距，行高放宽。
// body 缺失或全为空白段落时，显示一句说明，不回退到分组列表。

struct BriefBodyView: View {
    /// 输入正文。命名避开 `body`，否则会与 `View.body` 冲突。
    let content: BriefBody?
    var onOpenURL: (URL) -> Void
    /// 点小标题右侧「跟踪」按钮时的回调；为 nil 时不显示该按钮。
    var onTrackHeading: ((String) -> Void)?
    /// 当前观感风格：正文小标题的字形与字重跟着它走。
    var style: ReaderStyle = .editorial

    @Environment(\.appLocale) private var locale

    /// 与 Brief.hasReadableBody 保持一致：空白段落不算正文。
    private var isReadable: Bool {
        guard let content else { return false }
        return !content.isEmpty
    }

    var body: some View {
        if isReadable, let content {
            // 正文是 Markdown：交给原生 CommonMark 解析器渲染，
            // 覆盖标题、列表、粗体、行内代码、引用块、代码块与链接。
            MarkdownBodyView(
                markdown: content.markdown,
                onOpenURL: onOpenURL,
                onTrackHeading: onTrackHeading,
                style: style
            )
            .accessibilityIdentifier("brief-body")
        } else {
            Text(L10n.string("brief.body.empty", locale: locale))
                .font(TypeFace.body(14))
                .foregroundStyle(Palette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Space.m)
                .accessibilityIdentifier("brief-body-empty")
        }
    }
}

// MARK: - 正文汇编
//
// 把结构化片段拼回 Markdown 源码交给渲染器：
// - text 片段原样保留（它本身就是 Markdown）；
// - link 片段写成 [文字](url)，保证服务端校验过的链接仍然可点。

extension BriefBody {
    var markdown: String {
        paragraphs.map { paragraph in
            paragraph.segments.map { segment -> String in
                switch segment {
                case .text(let text):
                    return text
                case .link(let text, let url, _):
                    // 标签里的 ] 会提前闭合链接语法，做最小转义。
                    let label = text.replacingOccurrences(of: "]", with: "\\]")
                    return "[\(label)](\(url.absoluteString))"
                }
            }.joined()
        }
        // 每段是独立的 Markdown 块（可能自带 ## 小标题与列表），
        // 用空行分隔才能让 CommonMark 正确断块。
        .joined(separator: "\n\n")
    }
}

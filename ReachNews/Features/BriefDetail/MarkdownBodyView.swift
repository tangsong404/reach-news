import SwiftUI
import Foundation

// MARK: - 正文 Markdown 渲染（原生实现）
//
// 正文的 segments[].text 是 AI 按技能模板生成的 Markdown，语法不受逐字控制，
// 会出现标题、列表、代码块等——只认 ## 和 ** 的最小实现必然漏语法。
//
// 这里用 Foundation 自带的 CommonMark 解析器 `AttributedString(markdown:)`
// （interpretedSyntax: .full），不引入第三方依赖，也不自研正则。
//
// 它把 Markdown 解析成 AttributedString，块级结构记录在 `presentationIntent` 上：
// components 是从最外层到最内层的链（例如 [unorderedList, listItem]），
// `Text` 不会因为 intent 自动放大标题或缩进列表，所以这里按 intent 切块，
// 块级样式（标题字号、项目符号、代码底纹）由 SwiftUI 自己施加。
//
// 渲染范围严格限定 body：title / summary / sections 一律纯文本，不走这里。

struct MarkdownBodyView: View {
    let markdown: String
    var onOpenURL: (URL) -> Void
    /// 点小标题右侧「跟踪」按钮时的回调，参数是该标题的文字。
    var onTrackHeading: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            let blocks = MarkdownBlockBuilder.parse(markdown, onTrackHeading: onTrackHeading)
            ForEach(blocks) { block in
                block.view
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            onOpenURL(url)
            return .handled
        })
    }
}

// MARK: - 分块与渲染

enum MarkdownBlockBuilder {

    /// 块级种类：取 intent 链里最深的那一层。
    enum Kind: Equatable {
        case paragraph
        case heading(level: Int)
        case listItem(ordered: Bool, ordinal: Int)
        case codeBlock
        case blockQuote
        case thematicBreak
    }

    struct Block {
        let kind: Kind
        let text: AttributedString

        /// 纯文本形态，供小标题点击时把标题文字交给业务层。
        var plainText: String {
            String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// 切块 + 映射成视图后的结果。
    /// 视图负责长相，`kind` 与 `plainText` 留给调用方判断交互，
    /// 这样渲染层不需要知道「点了标题要做什么」。
    struct LaidOutBlock: Identifiable {
        let id: Int
        let kind: Kind
        let plainText: String
        let view: AnyView
    }

    static func parse(_ markdown: String, onTrackHeading: ((String) -> Void)? = nil) -> [LaidOutBlock] {
        split(attributed(from: markdown)).enumerated().map { index, block in
            LaidOutBlock(
                id: index,
                kind: block.kind,
                plainText: block.plainText,
                view: view(for: block, onTrackHeading: onTrackHeading)
            )
        }
    }

    /// Foundation 的 CommonMark 解析。失败时退回纯文本，保证正文不丢。
    static func attributed(from markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let parsed = try? AttributedString(markdown: markdown, options: options) {
            return parsed
        }
        return AttributedString(markdown)
    }

    /// 给链接 run 加下划线。
    ///
    /// 用户明确不要颜色区分：链接文字保持正文色，改用下划线 + 外链图标标识。
    /// 下划线写进 run 本身，与 view 级样式无关；图标由视图层的 `linkText` 追加。
    static func underliningLinks(_ attributed: AttributedString) -> AttributedString {
        var result = attributed
        for run in attributed.runs where run.link != nil {
            result[run.range].underlineStyle = .single
        }
        return result
    }

    /// 按块级 intent 切分：intent 变一次就换块。
    static func split(_ attributed: AttributedString) -> [Block] {
        var blocks: [Block] = []
        var current = AttributedString()
        var currentKind: Kind = .paragraph
        var currentIdentity: Int?

        func flush() {
            guard !current.characters.isEmpty, !isBlank(current) else {
                current = AttributedString()
                return
            }
            blocks.append(Block(kind: currentKind, text: underliningLinks(current)))
            current = AttributedString()
        }

        for run in attributed.runs {
            let kind = kind(of: run.presentationIntent)
            // 相邻两个段落种类相同，只看 kind 会把它们并成一块；
            // 因此同时看 intent 的 identity —— 不同段落有各自的 identity。
            let identity = run.presentationIntent?.components.last?.identity
            if kind != currentKind || identity != currentIdentity {
                flush()
                currentKind = kind
                currentIdentity = identity
            }
            // 保留行内样式即可；Text 不会因为块级 intent 自动加项目符号或放大标题，
            // 块级表现完全由下面的视图映射决定。
            current += AttributedString(attributed[run.range])
        }
        flush()
        return blocks
    }

    /// 从 intent 链判断该块的种类。
    ///
    /// 链是从最外层到最内层（例如列表项里的文字是 [unorderedList, listItem, paragraph]）。
    /// 因此不能只看最深一层：那样列表项会被当成普通段落而丢掉项目符号。
    /// 这里从内往外找第一个需要块级表现的种类，列表的有序性再由链里的容器决定。
    static func kind(of intent: PresentationIntent?) -> Kind {
        guard let components = intent?.components, !components.isEmpty else {
            return .paragraph
        }

        var isOrdered = false
        var isUnordered = false
        for component in components {
            switch component.kind {
            case .orderedList: isOrdered = true
            case .unorderedList: isUnordered = true
            default: break
            }
        }

        for component in components.reversed() {
            switch component.kind {
            case .header(let level):
                return .heading(level: level)
            case .listItem(let ordinal):
                return .listItem(ordered: isOrdered && !isUnordered, ordinal: ordinal)
            case .codeBlock:
                return .codeBlock
            case .blockQuote:
                return .blockQuote
            case .thematicBreak:
                return .thematicBreak
            default:
                continue
            }
        }
        return .paragraph
    }

    /// 清掉块首尾的换行与空白。
    ///
    /// 不做精细的富文本裁剪：attributed 的字符视图索引不能直接用于
    /// removeSubrange，而 CommonMark 已经按块切好了 run，
    /// 块首尾的空行只影响外观，统一在视图层用 padding 处理更简单可靠。
    /// 这里只把「纯空白块」判定出来，避免出现空段落占位。
    static func isBlank(_ attributed: AttributedString) -> Bool {
        attributed.characters.allSatisfy { $0.isNewline || $0 == " " || $0 == "\t" }
    }

    // MARK: 视图映射

    /// 块内文字，并在**每条链接之后**各插一个外链图标。
    ///
    /// 不用 `AttributedString(Image:)`：该初始化器要求 Image 满足 Sequence，
    /// 在目标 SDK 上不可用。改为把块按「链接结束位置」切开，用 `Text + Image`
    /// 逐段拼接——SwiftUI 的 Text 支持与 Image 相加，且能保留各段的行内样式。
    static func linkText(_ block: Block) -> Text {
        let links = block.text.runs.filter { $0.link != nil }
        // 没有链接就不必拆分。
        guard !links.isEmpty else { return Text(block.text) }

        var pieces: [Text] = []
        var cursor = block.text.startIndex
        for run in links {
            // 链接之前的普通文字（含本条链接本身）。
            if cursor < run.range.lowerBound {
                pieces.append(Text(AttributedString(block.text[cursor..<run.range.lowerBound])))
            }
            pieces.append(Text(AttributedString(block.text[run.range])))
            // 图标紧跟这条链接，且不参与跳转；略微上移，避免落在下划线高度。
            pieces.append(Text(" "))
            pieces.append(
                Text(Image(systemName: "arrow.up.forward.app"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.inkTertiary)
                    .baselineOffset(3)
            )
            cursor = run.range.upperBound
        }
        if cursor < block.text.endIndex {
            pieces.append(Text(AttributedString(block.text[cursor...])))
        }
        return pieces.reduce(Text("")) { $0 + $1 }
    }

    private static func headingWithFollow(
        _ block: Block,
        size: CGFloat,
        onTrackHeading: ((String) -> Void)?
    ) -> some View {
        guard let onTrackHeading else {
            return AnyView(
                Text(block.text)
                    .font(TypeFace.heading(size))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            )
        }

        // 把 follow 做成 inline link：它会紧跟标题最后一个文字，
        // 标题换行时自然流到最后一行，不会被 HStack 挤到整块最右侧。
        var attributed = block.text
        var follow = AttributedString("  " + String(localized: "brief.heading.follow"))
        follow.link = URL(string: "reachnews://track-heading")
        follow.foregroundColor = Palette.inkSecondary
        follow.backgroundColor = Palette.chip
        follow.font = .system(size: 11, weight: .medium)
        attributed.append(follow)

        return AnyView(
            Text(attributed)
                .font(TypeFace.heading(size))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Space.xs)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("brief-heading-follow")
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "reachnews", url.host == "track-heading" else {
                        return .systemAction
                    }
                    onTrackHeading(block.plainText)
                    return .handled
                })
        )
    }

    private static func view(for block: Block, onTrackHeading: ((String) -> Void)?) -> AnyView {
        switch block.kind {
        case .heading(let level):
            let sizes: [CGFloat] = [22, 19, 17, 16, 16, 16]
            let size = sizes[min(max(level, 1), 6) - 1]
            // follow 紧跟标题的**最后一个文字**：用 Text + Text 拼接，
            // 而不是 HStack（HStack 会把按钮顶到行的最右侧，不会随文字换行）。
            //
            // 做法：把标题文字与按钮文字拼成一个 Text，靠 baseline 流式排布，
            // 按钮的胶囊底由 overlay 画在对应位置。
            return AnyView(
                headingWithFollow(block, size: size, onTrackHeading: onTrackHeading)
            )

        case .listItem(let ordered, let ordinal):
            let marker = ordered ? "\(max(ordinal, 1))." : "•"
            return AnyView(
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(marker)
                        .font(ordered ? TypeFace.condensed(14, weight: .semibold) : TypeFace.body(16))
                        .foregroundStyle(Palette.inkTertiary)
                        .frame(minWidth: 18, alignment: .trailing)
                    linkText(block)
                        .font(TypeFace.body(16))
                        .lineSpacing(7)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            )

        case .codeBlock:
            return AnyView(
                ScrollView(.horizontal, showsIndicators: false) {
                    // 代码块不加行内样式，等宽并保留换行与缩进；不做语法高亮。
                    Text(String(block.text.characters))
                        .font(.system(size: 13.5, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .padding(Space.m)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .fill(Palette.paper)
                )
            )

        case .blockQuote:
            return AnyView(
                HStack(alignment: .top, spacing: Space.m) {
                    Rectangle()
                        .fill(Palette.lineStrong)
                        .frame(width: 3)
                    linkText(block)
                        .font(TypeFace.body(15))
                        .lineSpacing(6)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            )

        case .thematicBreak:
            return AnyView(
                Rectangle()
                    .fill(Palette.line)
                    .frame(height: 1)
                    .padding(.vertical, Space.xs)
            )

        case .paragraph:
            return AnyView(
                linkText(block)
                    .font(TypeFace.body(16))
                    .lineSpacing(7)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        }
    }
}

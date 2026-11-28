import SwiftUI
import UIKit

// MARK: - 带「跟随」铃铛的小标题
//
// 需求是铃铛紧贴小标题**最后一个字**的右边。SwiftUI 的 `Text` 不暴露每一行的
// 宽度，把按钮当兄弟视图摆放只能靠猜（CoreText 复算和 SwiftUI 的断行并不总一致，
// 实测会落到文字中间）。
//
// 这里换成 TextKit：铃铛作为**内联附件**放在同一段文本的末尾，位置天然正确；
// 点击时用 layout manager 把触点换算成字符位置，命中附件才触发。

struct InlineFollowHeading: UIViewRepresentable {
    /// 标题的纯文本（标题里不放链接与行内样式）。
    let text: String
    let fontSize: CGFloat
    let style: ReaderStyle
    let followLabel: String
    let onFollow: () -> Void
    var typography = ResolvedTypography()

    func makeCoordinator() -> Coordinator {
        Coordinator(onFollow: onFollow, followLabel: followLabel)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)
        context.coordinator.textView = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onFollow = onFollow
        context.coordinator.followLabel = followLabel

        let (attributed, followRange) = makeAttributedText()
        view.attributedText = attributed
        context.coordinator.followRange = followRange
        // VoiceOver：整段读作标题，另给一个「跟踪」自定义动作。
        view.accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: followLabel,
                target: context.coordinator,
                selector: #selector(Coordinator.performFollow)
            )
        ]
        view.accessibilityLabel = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }

    // MARK: 内容

    private func makeAttributedText() -> (NSAttributedString, NSRange) {
        Self.attributedText(text: text, fontSize: fontSize, style: style, typography: typography)
    }

    /// 纯函数版本：单测直接调用，验证铃铛附件的位置。
    static func attributedText(
        text: String,
        fontSize: CGFloat,
        style: ReaderStyle,
        typography: ResolvedTypography = ResolvedTypography()
    ) -> (NSAttributedString, NSRange) {
        let font = typography.headingUIFont(size: fontSize, style: style)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping

        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: UIColor(Palette.ink),
                .paragraphStyle: paragraph
            ]
        )

        let attachment = NSTextAttachment()
        attachment.image = Self.bellImage()
        // 让 22pt 的圆点在行内垂直居中。
        attachment.bounds = CGRect(
            x: 0,
            y: (font.capHeight - Self.bellSize) / 2 - 1,
            width: Self.bellSize,
            height: Self.bellSize
        )
        let attachmentString = NSMutableAttributedString(string: " ")
        attachmentString.append(NSAttributedString(attachment: attachment))
        let followRange = NSRange(location: result.length, length: attachmentString.length)
        result.append(attachmentString)

        // 标题可能很长，附件不能被压缩掉。
        result.addAttribute(
            .font,
            value: font,
            range: NSRange(location: 0, length: result.length)
        )
        return (result, followRange)
    }

    private static let bellSize: CGFloat = 22

    /// 22pt 圆形浅底 + 描边的铃铛图（与 SwiftUI 版本的视觉一致）。
    private static func bellImage() -> UIImage {
        let size = CGSize(width: bellSize, height: bellSize)
        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            UIColor(Palette.chip).setFill()
            context.cgContext.fillEllipse(in: rect)
            UIColor(Palette.line).setStroke()
            context.cgContext.setLineWidth(1)
            context.cgContext.strokeEllipse(in: rect)

            let configuration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            guard let symbol = UIImage(systemName: "bell", withConfiguration: configuration)?
                .withTintColor(UIColor(Palette.inkSecondary), renderingMode: .alwaysOriginal)
            else { return }
            let glyph = symbol.size
            symbol.draw(
                in: CGRect(
                    x: (bellSize - glyph.width) / 2,
                    y: (bellSize - glyph.height) / 2,
                    width: glyph.width,
                    height: glyph.height
                )
            )
        }
    }

    // MARK: 点击命中

    final class Coordinator: NSObject {
        var onFollow: () -> Void
        var followLabel: String
        var followRange: NSRange = NSRange(location: NSNotFound, length: 0)
        weak var textView: UITextView?

        init(onFollow: @escaping () -> Void, followLabel: String) {
            self.onFollow = onFollow
            self.followLabel = followLabel
        }

        @objc func performFollow() {
            onFollow()
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = textView, view.bounds.width > 0 else { return }
            let point = gesture.location(in: view)
            let index = view.layoutManager.characterIndex(
                for: point,
                in: view.textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            guard followRange.location != NSNotFound,
                  index >= followRange.location,
                  index < followRange.location + followRange.length
            else { return }
            onFollow()
        }
    }
}

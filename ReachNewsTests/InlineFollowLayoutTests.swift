import XCTest
import UIKit
@testable import ReachNews

/// 「铃铛必须紧贴最后一个字」的确定性验证。
///
/// 快照渲染不了 UIViewRepresentable，所以这里直接用 TextKit 量：
/// 把标题按真实宽度排版，确认附件的字形矩形落在**最后一行**、
/// 且在最后一个字的**右侧**。
final class InlineFollowLayoutTests: XCTestCase {

    private func layout(text: String, width: CGFloat, fontSize: CGFloat = 19) -> (attachment: CGRect, lastGlyph: CGRect, lineCount: Int) {
        let (attributed, range) = InlineFollowHeading.attributedText(
            text: text,
            fontSize: fontSize,
            style: .editorial
        )
        let view = UITextView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.attributedText = attributed
        view.frame = CGRect(x: 0, y: 0, width: width, height: 600)
        view.layoutManager.ensureLayout(for: view.textContainer)

        let attachment = view.layoutManager.boundingRect(
            forGlyphRange: range,
            in: view.textContainer
        )
        let lastGlyph = view.layoutManager.boundingRect(
            forGlyphRange: NSRange(location: range.location - 1, length: 1),
            in: view.textContainer
        )
        var lineCount = 0
        var index = 0
        let glyphCount = view.layoutManager.numberOfGlyphs
        while index < glyphCount {
            var range = NSRange()
            _ = view.layoutManager.lineFragmentRect(
                forGlyphAt: index,
                effectiveRange: &range
            )
            lineCount += 1
            index = range.location + range.length
        }
        return (attachment, lastGlyph, lineCount)
    }

    func testShortHeadingKeepsButtonOnSameLine() {
        let result = layout(text: "央行下调准备金率", width: 300)
        XCTAssertEqual(result.lineCount, 1)
        XCTAssertGreaterThanOrEqual(
            result.attachment.minX, result.lastGlyph.maxX - 1,
            "铃铛必须在最后一个字的右侧"
        )
        XCTAssertLessThan(
            result.attachment.minY, result.lastGlyph.maxY,
            "铃铛必须与最后一个字在同一行"
        )
    }

    func testWrappedHeadingKeepsButtonOnLastLine() {
        let result = layout(text: "央行下调存款准备金率与市场影响", width: 232)
        XCTAssertGreaterThan(result.lineCount, 1, "这个宽度下标题应该换行")
        XCTAssertGreaterThanOrEqual(
            result.attachment.minX, result.lastGlyph.maxX - 1,
            "折行时铃铛必须紧跟最后一个字"
        )
        XCTAssertLessThan(
            result.attachment.minY, result.lastGlyph.maxY,
            "折行时铃铛必须落在最后一行"
        )
    }
}

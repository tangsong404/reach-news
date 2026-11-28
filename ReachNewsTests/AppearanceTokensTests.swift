import Foundation
import XCTest
@testable import ReachNews

// MARK: - 亮/暗配色
//
// 只验证数字：取值来自 `NeutralTokens` / `StatusTokens`，与 `Palette`
// 里的动态色是同一份数据，所以这些断言反映的就是界面上会出现的对比度。
// 暗色第一批取值过深，文字与背景糊在一起；这里把它固化成可回归的约束。

final class AppearanceTokensTests: XCTestCase {

    // MARK: 工具

    /// WCAG 相对亮度。
    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let v = Double(value & 0xFF) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = channel(hex >> 16)
        let g = channel(hex >> 8)
        let b = channel(hex)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func assertContrast(
        _ a: UInt32,
        _ b: UInt32,
        atLeast minimum: Double,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ratio = contrast(a, b)
        XCTAssertGreaterThanOrEqual(
            ratio, minimum,
            String(format: "%@ 对比度 %.2f 低于 %.2f", label, ratio, minimum),
            file: file,
            line: line
        )
    }

    // MARK: 正文层级

    func testPrimaryTextIsReadableOnEverySurface() {
        assertContrast(NeutralTokens.ink.light, NeutralTokens.canvas.light, atLeast: 12, "亮色 正文/画布")
        assertContrast(NeutralTokens.ink.light, NeutralTokens.surface.light, atLeast: 12, "亮色 正文/卡片")
        assertContrast(NeutralTokens.ink.dark, NeutralTokens.canvas.dark, atLeast: 10, "暗色 正文/画布")
        assertContrast(NeutralTokens.ink.dark, NeutralTokens.paper.dark, atLeast: 9, "暗色 正文/纸面")
        assertContrast(NeutralTokens.ink.dark, NeutralTokens.surface.dark, atLeast: 9, "暗色 正文/卡片")
    }

    func testSecondaryAndTertiaryTextStayReadable() {
        assertContrast(NeutralTokens.inkSecondary.light, NeutralTokens.surface.light, atLeast: 6, "亮色 次要文字/卡片")
        assertContrast(NeutralTokens.inkSecondary.dark, NeutralTokens.surface.dark, atLeast: 4.5, "暗色 次要文字/卡片")
        assertContrast(NeutralTokens.inkTertiary.light, NeutralTokens.surface.light, atLeast: 3, "亮色 三级文字/卡片")
        assertContrast(NeutralTokens.inkTertiary.dark, NeutralTokens.surface.dark, atLeast: 4, "暗色 三级文字/卡片")
    }

    /// 画布 / 纸面 / 卡片是三层底色，必须彼此可辨，否则组件边界会「消失」。
    func testSurfacesStayDistinguishable() {
        assertContrast(NeutralTokens.surface.light, NeutralTokens.canvas.light, atLeast: 1.03, "亮色 卡片/画布")
        assertContrast(NeutralTokens.surface.dark, NeutralTokens.canvas.dark, atLeast: 1.15, "暗色 卡片/画布")
        assertContrast(NeutralTokens.surface.dark, NeutralTokens.paper.dark, atLeast: 1.05, "暗色 卡片/纸面")
        assertContrast(NeutralTokens.paper.dark, NeutralTokens.canvas.dark, atLeast: 1.1, "暗色 纸面/画布")
    }

    /// 底色方向不能反：亮色浅底、暗色深底。
    func testCanvasDirection() {
        XCTAssertGreaterThan(luminance(NeutralTokens.canvas.light), 0.8)
        XCTAssertLessThan(luminance(NeutralTokens.canvas.dark), 0.05)
        XCTAssertGreaterThan(
            luminance(NeutralTokens.canvas.dark),
            luminance(0x000000),
            "暗色画布应是暖灰，而不是纯黑"
        )
    }

    /// 每个 token 的亮暗取值必须真的不同，避免漏改某一项。
    func testEveryTokenHasDistinctLightAndDarkValues() {
        let pairs: [(String, (light: UInt32, dark: UInt32))] = [
            ("canvas", NeutralTokens.canvas),
            ("paper", NeutralTokens.paper),
            ("surface", NeutralTokens.surface),
            ("ink", NeutralTokens.ink),
            ("inkSecondary", NeutralTokens.inkSecondary),
            ("inkTertiary", NeutralTokens.inkTertiary),
            ("chip", NeutralTokens.chip),
            ("field", NeutralTokens.field),
            ("askBackground", NeutralTokens.askBackground),
            ("askSurface", NeutralTokens.askSurface),
            ("askBubble", NeutralTokens.askBubble),
            ("askUser", NeutralTokens.askUser),
            ("askUserText", NeutralTokens.askUserText)
        ]
        for (name, pair) in pairs {
            XCTAssertNotEqual(pair.light, pair.dark, "\(name) 的亮暗取值相同")
        }
    }

    // MARK: 状态色

    func testStatusColorsAreReadableInBothModes() {
        assertContrast(StatusTokens.runningForeground.light, StatusTokens.runningBackground.light, atLeast: 4.5, "亮色 运行中")
        assertContrast(StatusTokens.runningForeground.dark, StatusTokens.runningBackground.dark, atLeast: 4.5, "暗色 运行中")
        assertContrast(StatusTokens.missedForeground.light, StatusTokens.missedBackground.light, atLeast: 4.5, "亮色 错过")
        assertContrast(StatusTokens.missedForeground.dark, StatusTokens.missedBackground.dark, atLeast: 4.5, "暗色 错过")
        assertContrast(StatusTokens.failedForeground.light, StatusTokens.failedBackground.light, atLeast: 4.5, "亮色 失败")
        assertContrast(StatusTokens.failedForeground.dark, StatusTokens.failedBackground.dark, atLeast: 4.5, "暗色 失败")
    }

    /// 状态底色在暗色下必须是深色块，不能比画布更亮而抢走正文。
    func testStatusBackgroundsStayBehindTheText() {
        XCTAssertLessThan(luminance(StatusTokens.runningBackground.dark), luminance(NeutralTokens.ink.dark))
        XCTAssertLessThan(luminance(StatusTokens.failedBackground.dark), luminance(NeutralTokens.ink.dark))
        XCTAssertLessThan(luminance(StatusTokens.missedBackground.dark), luminance(NeutralTokens.ink.dark))
    }

    // MARK: 追问气泡

    /// 用户气泡在暗色下翻成浅底深字，否则近黑气泡会消失在深色背景里。
    func testAskBubblesInvertInDarkMode() {
        assertContrast(NeutralTokens.askUserText.light, NeutralTokens.askUser.light, atLeast: 10, "亮色 用户气泡")
        assertContrast(NeutralTokens.askUserText.dark, NeutralTokens.askUser.dark, atLeast: 10, "暗色 用户气泡")
        XCTAssertGreaterThan(
            luminance(NeutralTokens.askUser.dark),
            luminance(NeutralTokens.askUser.light),
            "暗色下用户气泡应比亮色更亮"
        )
    }
}

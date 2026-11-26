import Foundation
import SwiftUI
import UIKit

// MARK: - 色值工具

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    /// 亮 / 暗两套取值。
    ///
    /// 承载在 UIKit 动态色上：视图里仍然只写 `Palette.ink` 这样的语义 token，
    /// 由当前 trait 解析出对应色值。这样 `.preferredColorScheme` 一改，
    /// 全应用的 token 一起切换，不必给每个视图传一遍模式。
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgbHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgbHex: UInt32) {
        self.init(
            red: CGFloat((rgbHex >> 16) & 0xFF) / 255,
            green: CGFloat((rgbHex >> 8) & 0xFF) / 255,
            blue: CGFloat(rgbHex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - 语义 token
//
// 两套视觉语言并存（ADR 0001）：日报、频道、我的走「编辑风」；追问走「近单色工具风」。
// 视图内一律引用这里的 token，不写字面色值。

/// 中性 token 的亮/暗取值。
///
/// 这里是两份配色的唯一出处：`Palette` 用它构造动态色，
/// 单元测试用同一份数字算对比度，避免「文档写一套、代码是另一套」。
enum NeutralTokens {
    static let canvas = (light: UInt32(0xFBFAF7), dark: UInt32(0x121210))
    static let paper = (light: UInt32(0xF1EFE9), dark: UInt32(0x1F1F1B))
    static let surface = (light: UInt32(0xFFFFFF), dark: UInt32(0x262622))
    static let ink = (light: UInt32(0x14140F), dark: UInt32(0xF2EFE7))
    static let inkSecondary = (light: UInt32(0x53514A), dark: UInt32(0xB5B1A6))
    static let inkTertiary = (light: UInt32(0x8B877E), dark: UInt32(0x97938A))
    static let chip = (light: UInt32(0xF2F0EA), dark: UInt32(0x31312B))
    static let field = (light: UInt32(0xF2F0EA), dark: UInt32(0x31312B))
    static let askBackground = (light: UInt32(0xF6F5F2), dark: UInt32(0x14140F))
    static let askSurface = (light: UInt32(0xFFFFFF), dark: UInt32(0x1F1F1A))
    static let askBubble = (light: UInt32(0xEFEDE8), dark: UInt32(0x31312B))
    static let askUser = (light: UInt32(0x121211), dark: UInt32(0xEDE9DF))
    static let askUserText = (light: UInt32(0xF7F6F4), dark: UInt32(0x17170F))
}

/// 状态色的亮/暗取值。
enum StatusTokens {
    static let runningBackground = (light: UInt32(0xEAF0EC), dark: UInt32(0x1B2A23))
    static let runningForeground = (light: UInt32(0x3D6B5C), dark: UInt32(0x8FD3B5))
    static let missedBackground = (light: UInt32(0xEFEDE7), dark: UInt32(0x2A2823))
    static let missedForeground = (light: UInt32(0x53514A), dark: UInt32(0xB5B1A6))
    static let failedBackground = (light: UInt32(0xFAF0EC), dark: UInt32(0x2E1E19))
    static let failedForeground = (light: UInt32(0xA5452A), dark: UInt32(0xE79C80))
}


enum Palette {
    // 编辑风：日报与频道
    //
    // 每个中性色都是亮/暗成对的：暗色不是把亮色整体反相，
    // 而是保持同一套暖灰秩序（画布最暗 → 纸面 → 卡片 → 分隔线 → 正文），
    // 保证层级之间仍有对比，而不是糊成一片。
    static let canvas = Color(light: NeutralTokens.canvas.light, dark: NeutralTokens.canvas.dark)
    static let paper = Color(light: NeutralTokens.paper.light, dark: NeutralTokens.paper.dark)
    static let surface = Color(light: NeutralTokens.surface.light, dark: NeutralTokens.surface.dark)
    static let ink = Color(light: NeutralTokens.ink.light, dark: NeutralTokens.ink.dark)
    static let inkSecondary = Color(light: NeutralTokens.inkSecondary.light, dark: NeutralTokens.inkSecondary.dark)
    static let inkTertiary = Color(light: NeutralTokens.inkTertiary.light, dark: NeutralTokens.inkTertiary.dark)
    static let line = Color(light: 0x14140F, dark: 0xFFFFFF).opacity(0.12)
    static let lineStrong = Color(light: 0x14140F, dark: 0xFFFFFF).opacity(0.20)
    static let chip = Color(light: NeutralTokens.chip.light, dark: NeutralTokens.chip.dark)
    static let field = Color(light: NeutralTokens.field.light, dark: NeutralTokens.field.dark)

    // 追问风：近单色
    static let askBackground = Color(light: NeutralTokens.askBackground.light, dark: NeutralTokens.askBackground.dark)
    static let askSurface = Color(light: NeutralTokens.askSurface.light, dark: NeutralTokens.askSurface.dark)
    static let askBubble = Color(light: NeutralTokens.askBubble.light, dark: NeutralTokens.askBubble.dark)
    static let askUser = Color(light: NeutralTokens.askUser.light, dark: NeutralTokens.askUser.dark)
    static let askUserText = Color(light: NeutralTokens.askUserText.light, dark: NeutralTokens.askUserText.dark)

    // 正文链接：全局 tint 是近黑的 ink，链接若沿用 tint 就会与正文同色而看不见。
    // 取色板里的 azure，与频道标识色同一明度区间，不与状态色混淆。
    static let link = Color(light: 0x2F6F9E, dark: 0x7FB6DC)

    // 状态：运行中 / 错过 / 失败
    static let runningBackground = Color(light: StatusTokens.runningBackground.light, dark: StatusTokens.runningBackground.dark)
    static let runningForeground = Color(light: StatusTokens.runningForeground.light, dark: StatusTokens.runningForeground.dark)
    static let missedBackground = Color(light: StatusTokens.missedBackground.light, dark: StatusTokens.missedBackground.dark)
    static let missedForeground = Color(light: StatusTokens.missedForeground.light, dark: StatusTokens.missedForeground.dark)
    static let failedBackground = Color(light: StatusTokens.failedBackground.light, dark: StatusTokens.failedBackground.dark)
    static let failedForeground = Color(light: StatusTokens.failedForeground.light, dark: StatusTokens.failedForeground.dark)

    // 频道标识：steel / moss / clay / plum
    /// 频道标识色板：足够区分常见频道数，同时保持整体克制。
    /// 频道标识色板：彼此可辨，同时保持同一明度区间，避免花哨。
    static let channelTints: [Color] = [
        Color(hex: 0x2F6F9E),  // azure
        Color(hex: 0x2E7D5B),  // emerald
        Color(hex: 0xB05A2A),  // ember
        Color(hex: 0x8C3B63),  // magenta
        Color(hex: 0x6A4FA0),  // violet
        Color(hex: 0xB08615),  // amber
        Color(hex: 0x1F7A76),  // teal
        Color(hex: 0x9C2F2F),  // brick
        Color(hex: 0x4A5D23),  // olive
        Color(hex: 0x2E4E8F),  // indigo
        Color(hex: 0x7A5C3E),  // walnut
        Color(hex: 0x4A4A55)   // graphite
    ]
}

// MARK: - 频道标识色
//
// 由 channelId 稳定映射，保证同一频道在列表、详情、编辑页取到同一色。
// 订阅色复用同一块色板：服务端只存 ≤32 字符的字符串，因此用色值本身承载索引。

enum ChannelTint {
    /// 调色板的色值字符串，顺序与 `Palette.channelTints` 一一对应。
    /// 订阅时提交它，读取时比对它；服务端不维护枚举，客户端的色板就是唯一的解释。
    static let paletteHexValues: [String] = [
        "#2F6F9E", "#2E7D5B", "#B05A2A", "#8C3B63", "#6A4FA0", "#B08615",
        "#1F7A76", "#9C2F2F", "#4A5D23", "#2E4E8F", "#7A5C3E", "#4A4A55"
    ]

    /// 把色板索引转成提交给服务端的订阅色值。
    static func paletteColorValue(at index: Int) -> String {
        paletteHexValues[max(0, min(index, paletteHexValues.count - 1))]
    }

    /// 把服务端返回的订阅色解析回色板索引；空字符串、非法值与色板外的值都返回 nil。
    static func paletteIndex(for color: String?) -> Int? {
        guard let color = color?.trimmingCharacters(in: .whitespaces), !color.isEmpty else {
            return nil
        }
        return paletteHexValues.firstIndex { $0.caseInsensitiveCompare(color) == .orderedSame }
    }

    /// 本地未设置时按 id 稳定取一个颜色（保证同一频道始终同色）。
    static func fallbackIndex(for channelID: String) -> Int {
        var accumulator: UInt32 = 0
        for scalar in channelID.unicodeScalars {
            accumulator = accumulator &* 31 &+ scalar.value
        }
        return Int(accumulator % UInt32(Palette.channelTints.count))
    }

    static func fallbackColor(for channelID: String) -> Color {
        Palette.channelTints[fallbackIndex(for: channelID)]
    }

    static func color(at index: Int) -> Color {
        Palette.channelTints[max(0, min(index, Palette.channelTints.count - 1))]
    }

    static var count: Int { Palette.channelTints.count }

    /// 新建频道时挑一个当前用得最少的颜色。
    static func leastUsedIndex(among used: [Int]) -> Int {
        var counts = Array(repeating: 0, count: count)
        for index in used where (0..<count).contains(index) { counts[index] += 1 }
        if let best = counts.enumerated().min(by: { $0.element < $1.element }) {
            return best.offset
        }
        return 0
    }
}

// MARK: - 圆角与间距

enum Radius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let pill: CGFloat = 999
}

enum Space {
    static let hairline: CGFloat = 1
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 22
    static let xxl: CGFloat = 28
}

// MARK: - 弹窗尺寸
//
// 所有上拉弹窗统一占主屏约 2/3，避免有的半屏、有的全屏。

enum SheetMetrics {
    static let detents: Set<PresentationDetent> = [.fraction(0.66)]

    /// 拖动手柄下方的呼吸空间。系统手柄本身贴近圆角，
    /// 内容若从上沿开始排会显得拥挤，因此统一留出这段距离。
    static let topInset: CGFloat = 12
}

extension View {
    /// 弹窗内容统一处理：顶部让出手柄空间。
    func sheetContentInset() -> some View {
        padding(.top, SheetMetrics.topInset)
    }
}

// MARK: - 字体
//
// 中文用系统字（苹方／思源黑），数字用压缩体（对应稿子的 Arial Narrow 角色）。

enum TypeFace {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
    }

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
    }

    static func heading(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }

    static func body(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular)
    }

    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium)
    }

    /// 苹果风格的脚注尺寸，仅用于确实需要说明的次要信息。
    static let footnote: Font = .footnote

    static func condensed(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    static func monospacedDigits(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

// MARK: - 本地化辅助
//
// 按 locale 找到对应的 .lproj bundle 再取值，这样界面语言偏好能真正覆盖系统语言。
// 需要 String 而非 Text 的场合（错误文案、格式化、无障碍标签）统一走这里。

enum L10n {
    static func bundle(for locale: Locale) -> Bundle {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        var candidates = [identifier]
        if let language = identifier.split(separator: "-").first {
            candidates.append(String(language))
        }
        candidates.append("zh-Hans")
        for candidate in candidates {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return .main
    }

    static func string(_ key: String, locale: Locale) -> String {
        bundle(for: locale).localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, locale: Locale, _ arguments: CVarArg...) -> String {
        let template = string(key, locale: locale)
        return String(format: template, locale: locale, arguments: arguments)
    }
}

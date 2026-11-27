import SwiftUI
import UIKit


// MARK: - 亮暗模式

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var labelKey: String { "appearance.mode." + rawValue }
}

// MARK: - 界面风格
//
// 两套观感：编辑风（默认，纸感、较重的标题层级）与简洁风
// （更轻的底色与更小的层级差，适合长时间阅读）。
//
// 只影响观感，不改变任何信息结构与交互位置。

enum ReaderStyle: String, CaseIterable, Identifiable {
    case editorial
    case plain

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .editorial: return "appearance.style.editorial"
        case .plain: return "appearance.style.plain"
        }
    }
}

// MARK: - 主题色
//
// 一组克制的强调色。换色只改强调元素（主按钮、选中态、链接图标等），
// 不改变中性色与文字层级。

enum ThemeTint: String, CaseIterable, Identifiable {
    case ink
    case azure
    case emerald
    case ember
    case violet
    case teal

    var id: String { rawValue }

    var labelKey: String { "appearance.tint." + rawValue }

    /// 强调色本身。暗底上用同一色相提亮一档，避免深色强调色在暗底上糊掉。
    var color: Color {
        switch self {
        case .ink: return Palette.ink
        case .azure: return Color(light: 0x2F6F9E, dark: 0x7FB6DC)
        case .emerald: return Color(light: 0x2E7D5B, dark: 0x7FC9A6)
        case .ember: return Color(light: 0xB05A2A, dark: 0xD99366)
        case .violet: return Color(light: 0x6A4FA0, dark: 0xAB95DB)
        case .teal: return Color(light: 0x1F7A76, dark: 0x6FC2BD)
        }
    }

    /// 强调色的浅底，用于标签与选中背景。
    var softColor: Color { color.opacity(0.12) }
}

// MARK: - 风格提供的底色
//
// 编辑风沿用既有的纸色；简洁风把底色提亮、把纸色压淡，
// 让内容区更接近纯白，减少视觉重量。

enum Theme {
    // 底色按风格分两套：编辑风是暖纸，简洁风是纯白扁平。
    // 色值都成对给出，暗色下同样保持两套的差异（暖暗 / 中性暗）。
    // `mode` 只用于说明调用点属于哪种外观，真正取哪一套由当前 trait 决定。

    static func canvas(for style: ReaderStyle, mode: AppearanceMode = .light) -> Color {
        switch style {
        case .editorial: return Color(light: 0xF5EFE2, dark: 0x17140F)
        case .plain: return Color(light: 0xFFFFFF, dark: 0x0C0C0C)
        }
    }

    static func paper(for style: ReaderStyle, mode: AppearanceMode = .light) -> Color {
        switch style {
        case .editorial: return Color(light: 0xEBE3D2, dark: 0x1E1A14)
        case .plain: return Color(light: 0xF2F3F5, dark: 0x171717)
        }
    }

    /// 卡片底色。
    ///
    /// 简洁风的画布是纯白，卡片若也用白就完全看不见边界——所以这里给浅灰，
    /// 让「扁平但有层次」的方向成立；编辑风保持暖白纸面，靠描边立住卡片。
    static func surface(for style: ReaderStyle, mode: AppearanceMode = .light) -> Color {
        switch style {
        case .editorial: return Color(light: 0xFFFCF4, dark: 0x262219)
        case .plain: return Color(light: 0xF3F4F6, dark: 0x1E1E1E)
        }
    }

    /// 卡片描边：编辑风用细线把卡片「框」出来，简洁风不加描边保持扁平。
    static func cardStroke(for style: ReaderStyle) -> Color {
        switch style {
        case .editorial: return Palette.line
        case .plain: return Color.clear
        }
    }

    /// 标题字重的层级差：简洁风更平，编辑风对比更强。
    static func headingWeight(for style: ReaderStyle) -> Font.Weight {
        switch style {
        case .editorial: return .semibold
        case .plain: return .medium
        }
    }

    /// 标题字形：编辑风用衬线，简洁风用无衬线。
    /// 这是两套风格最好辨认的差异，切换时第一眼就该看出来。
    static func headingFont(size: CGFloat, style: ReaderStyle) -> Font {
        let scaled = TypeFace.scaledSize(size)
        // `.serif` 对中文不生效（会回退到黑体）。编辑风改用系统的宋体，
        // 中英文都能看出「衬线感」，两套风格的差异才立得住。
        if style == .editorial, UIFont(name: Theme.cjkSerifName, size: scaled) != nil {
            return .custom(Theme.cjkSerifName, size: scaled, relativeTo: .body)
        }
        return .system(
            size: scaled,
            weight: headingWeight(for: style),
            design: style == .editorial ? .serif : .default
        )
    }

    /// 系统自带的衬线中文字体名。
    static let cjkSerifName = "Songti SC"

    /// 与 `headingFont` 对应的 UIKit 字体，供 CoreText 复算换行位置。
    static func headingUIFont(size: CGFloat, style: ReaderStyle) -> UIFont {
        let scaled = TypeFace.scaledSize(size)
        if style == .editorial, let serif = UIFont(name: Theme.cjkSerifName, size: scaled) {
            return serif
        }
        let weight: UIFont.Weight = style == .editorial ? .semibold : .medium
        let base = UIFont.systemFont(ofSize: scaled, weight: weight)
        guard style == .editorial,
              let descriptor = base.fontDescriptor.withDesign(.serif)
        else { return base }
        return UIFont(descriptor: descriptor, size: scaled)
    }
}

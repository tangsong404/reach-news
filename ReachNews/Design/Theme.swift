import SwiftUI


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
    // 底色同样走亮/暗成对 token：`mode` 只用于说明调用点属于哪种外观，
    // 真正取哪一套由当前 trait 决定（`.preferredColorScheme` 已经把它设好）。
    // 这样同一处调用在亮暗之间不再需要分支，也不会漏掉某个子视图。

    static func canvas(for style: ReaderStyle, mode: AppearanceMode = .light) -> Color {
        switch style {
        case .editorial: return Palette.canvas
        case .plain: return Color(light: 0xFFFFFF, dark: 0x0F0F0D)
        }
    }

    static func paper(for style: ReaderStyle, mode: AppearanceMode = .light) -> Color {
        switch style {
        case .editorial: return Palette.paper
        case .plain: return Color(light: 0xF7F7F5, dark: 0x191917)
        }
    }

    static func surface(for style: ReaderStyle, mode: AppearanceMode = .light) -> Color {
        switch style {
        case .editorial: return Palette.surface
        case .plain: return Color(light: 0xFFFFFF, dark: 0x212120)
        }
    }

    /// 标题字重的层级差：简洁风更平，编辑风对比更强。
    static func headingWeight(for style: ReaderStyle) -> Font.Weight {
        switch style {
        case .editorial: return .semibold
        case .plain: return .medium
        }
    }
}

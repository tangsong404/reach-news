import Foundation
import Observation
import SwiftUI

// MARK: - 外观偏好
//
// 风格与主题色都存在本机偏好里，切换后立即生效并持久化。
// 不做服务端同步：这是纯本机观感设置，换账号不需要跟着走。

@MainActor
@Observable
final class AppearanceStore {
    private(set) var style: ReaderStyle
    private(set) var tint: ThemeTint
    private(set) var mode: AppearanceMode
    private(set) var textScale: Double
    /// Legacy compatibility; continuous consumers use textScale directly.
    var textSize: ReadingTextSize {
        if textScale < 0.97 { return .small }
        if textScale > 1.04 { return .large }
        return .standard
    }

    @ObservationIgnored private let preferences: PreferencesStoring

    init(preferences: PreferencesStoring) {
        self.preferences = preferences
        self.style = ReaderStyle(rawValue: preferences.readerStyle) ?? .editorial
        self.tint = ThemeTint(rawValue: preferences.themeTint) ?? .ink
        self.mode = AppearanceMode(rawValue: preferences.appearanceMode) ?? .system
        let legacy = ReadingTextSize(rawValue: preferences.readingTextSize) ?? .standard
        let resolved = ReadingTextScale.clamped(preferences.readingTextScale ?? Double(legacy.scale))
        self.textScale = resolved
        preferences.readingTextScale = resolved
    }

    func select(style: ReaderStyle) {
        self.style = style
        preferences.readerStyle = style.rawValue
    }

    func select(mode: AppearanceMode) {
        self.mode = mode
        preferences.appearanceMode = mode.rawValue
    }

    func select(tint: ThemeTint) {
        self.tint = tint
        preferences.themeTint = tint.rawValue
    }

    func select(textSize: ReadingTextSize) {
        preferences.readingTextSize = textSize.rawValue
        select(textScale: Double(textSize.scale))
    }

    func select(textScale: Double) {
        let value = ReadingTextScale.clamped(textScale)
        self.textScale = value
        preferences.readingTextScale = value
    }

    /// 当前强调色。
    var accent: Color { tint.color }
    var resolvedColorScheme: ColorScheme? {
        switch mode { case .light: return .light; case .dark: return .dark; case .system: return nil }
    }

    /// 全局施加的外观修饰：底色、强调色与标题字重都跟着走。
    func apply<V: View>(to view: V) -> some View {
        view
            .tint(accent)
            .readingTypography(textScale: textScale)
            .background(Theme.canvas(for: style))
    }
}

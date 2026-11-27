import SwiftUI

// MARK: - 频道标识点

struct ChannelDot: View {
    let channelID: String
    var diameter: CGFloat = 7
    /// 本地设置的调色板索引；为空时按 id 回退。
    var colorIndex: Int? = nil

    var body: some View {
        Circle()
            .fill(colorIndex.map(ChannelTint.color(at:)) ?? ChannelTint.fallbackColor(for: channelID))
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

// MARK: - 点分隔符

struct DotSeparator: View {
    var body: some View {
        Circle()
            .fill(Palette.inkTertiary)
            .frame(width: 3, height: 3)
            .accessibilityHidden(true)
    }
}

// MARK: - 元信息行

struct MetaLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(TypeFace.condensed(11.5, weight: .medium))
            .foregroundStyle(Palette.inkTertiary)
    }
}

// MARK: - 日期分组标题

struct DayRule: View {
    let title: String

    var body: some View {
        HStack(spacing: Space.s) {
            Text(title)
                .font(TypeFace.label(11))
                .tracking(1.1)
                .foregroundStyle(Palette.inkTertiary)
            Rectangle()
                .fill(Palette.line)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 状态 chip

struct StatusChip: View {
    enum Style {
        case running
        case missed
        case failed
        case neutral

        var background: Color {
            switch self {
            case .running: return Palette.runningBackground
            case .missed: return Palette.missedBackground
            case .failed: return Palette.failedBackground
            case .neutral: return Palette.missedBackground
            }
        }

        var foreground: Color {
            switch self {
            case .running: return Palette.runningForeground
            case .missed: return Palette.missedForeground
            case .failed: return Palette.failedForeground
            case .neutral: return Palette.missedForeground
            }
        }
    }

    let style: Style
    let text: String

    var body: some View {
        Text(text)
            .font(TypeFace.label(10))
            .foregroundStyle(style.foreground)
            .padding(.horizontal, Space.xs)
            .padding(.vertical, 2.5)
            .background(style.background, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - 分组吸顶标题

struct SectionStickyHeader: View {
    let title: String
    let count: Int
    let locale: Locale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(title)
                .font(TypeFace.heading(12.5))
                .foregroundStyle(Palette.ink)
            Text(L10n.format("briefDetail.entryCount", locale: locale, count))
                .font(TypeFace.condensed(10.5, weight: .medium))
                .foregroundStyle(Palette.inkTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.s)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 主按钮

struct PrimaryButton: View {
    let title: String
    var action: () -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TypeFace.heading(14))
                .foregroundStyle(Palette.canvas)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                // 主操作跟随主题色，而不是固定墨黑。
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(env.appearance.accent)
                )
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - 空态 / 错误态

struct MessageStateView: View {
    @Environment(AppEnvironment.self) private var env

    enum Kind {
        case empty
        case error(APIError)
        case informational
    }

    let title: String
    var message: String?
    var kind: Kind = .informational
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Space.m) {
            Image(systemName: iconName)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(iconColor)
            Text(title)
                .font(TypeFace.heading(15))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(TypeFace.body(13))
                    .foregroundStyle(Palette.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(TypeFace.heading(13.5))
                    .foregroundStyle(Palette.canvas)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.s)
                    .background(Capsule().fill(env.appearance.accent))
                    .padding(.top, Space.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.xxl)
        .padding(.vertical, 44)
    }

    private var iconName: String {
        switch kind {
        case .empty: return "tray"
        case .error(let error): return error.isOffline ? "wifi.slash" : "exclamationmark.triangle"
        case .informational: return "info.circle"
        }
    }

    private var iconColor: Color {
        switch kind {
        case .error: return Palette.failedForeground
        case .empty, .informational: return Palette.inkTertiary
        }
    }
}

// MARK: - 加载指示

struct LoadingLine: View {
    var text: String

    var body: some View {
        HStack(spacing: Space.s) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(TypeFace.body(11.5))
                .foregroundStyle(Palette.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.l)
    }
}

// MARK: - 错误提示条

struct InlineNotice: View {
    enum Kind {
        case warning
        case error
    }

    let text: String
    var detail: String?
    var kind: Kind = .warning

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: kind == .warning ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(TypeFace.body(12))
                    .foregroundStyle(foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(TypeFace.body(11))
                        .foregroundStyle(foreground.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, 11)
        .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var foreground: Color {
        switch kind {
        case .warning: return Palette.failedForeground
        case .error: return Palette.failedForeground
        }
    }

    private var background: Color {
        switch kind {
        case .warning, .error: return Palette.failedBackground
        }
    }
}

// MARK: - 圆角矩形输入框
//
// 与新建页、编辑页共用，避免各页各写一套圆角和内边距。

struct FieldBox<Content: View>: View {
    var minHeight: CGFloat = 0
    @ViewBuilder var content: Content

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        content
            .font(TypeFace.body(15))
            // 让输入控件铺满整行，而不是按内容宽度缩在一角。
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(minHeight: minHeight > 0 ? minHeight : nil, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Theme.surface(for: env.appearance.style, mode: env.appearance.mode))
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(Theme.cardStroke(for: env.appearance.style), lineWidth: 1)
            }
    }
}

// MARK: - 选择行
//
// 「点开一个选择器」的通用外观：文字摘要 + 右侧箭头。
// 新建与编辑页的连接器、时间表都用这一个，避免两页样式漂移。

struct SelectorRow: View {
    let text: String
    var isPlaceholder: Bool = false
    var action: () -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Text(text)
                    .font(TypeFace.body(15))
                    .foregroundStyle(isPlaceholder ? Palette.inkTertiary : Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Theme.surface(for: env.appearance.style, mode: env.appearance.mode))
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(Theme.cardStroke(for: env.appearance.style), lineWidth: 1)
            }
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - 频道颜色选择
//
// 新建与编辑共用，避免两页各写一套。

/// 颜色选择：表单里只显示当前色 + 名称，点开弹层再挑。
struct ChannelColorRow: View {
    @Binding var selection: Int
    @State private var showsPicker = false
    @Environment(\.appLocale) private var locale
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        // 色点与文字同行排布，不再用 overlay 叠在文字上。
        Button {
            showsPicker = true
        } label: {
            HStack(spacing: Space.s) {
                Circle()
                    .fill(ChannelTint.color(at: selection))
                    .frame(width: 16, height: 16)
                Text(ChannelColorName.name(for: selection, locale: locale))
                    .font(TypeFace.body(15))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Theme.surface(for: env.appearance.style, mode: env.appearance.mode))
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(Theme.cardStroke(for: env.appearance.style), lineWidth: 1)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("channel-color-row")
        .sheet(isPresented: $showsPicker) {
            ColorPickerSheet(selection: $selection, isPresented: $showsPicker)
                .presentationDetents(SheetMetrics.detents)
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
        }
    }
}

/// 色板弹层：网格排布，选中项带圈。
struct ColorPickerSheet: View {
    @Binding var selection: Int
    @Binding var isPresented: Bool
    @Environment(\.appLocale) private var locale
    @Environment(AppEnvironment.self) private var env

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(0..<ChannelTint.count, id: \.self) { index in
                        Button {
                            selection = index
                        } label: {
                            VStack(spacing: Space.xs) {
                                Circle()
                                    .fill(ChannelTint.color(at: index))
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(env.appearance.accent, lineWidth: selection == index ? 2 : 0)
                                            .padding(-4)
                                    }
                                Text(ChannelColorName.name(for: index, locale: locale))
                                    .font(TypeFace.footnote)
                                    .foregroundStyle(Palette.inkTertiary)
                            }
                        }
                        .buttonStyle(.pressable)
                        .accessibilityIdentifier("channel-color-\(index)")
                    }
                }
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.l)
            }
            .sheetContentInset()
            .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavTitle(text: L10n.string("channelEdit.color", locale: locale))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("common.done", locale: locale)) {
                        isPresented = false
                    }
                    .font(TypeFace.heading(15))
                }
            }
        }
    }
}

/// 颜色名称，供表单摘要与弹层共用。
enum ChannelColorName {
    static func name(for index: Int, locale: Locale) -> String {
        let keys = [
            "color.azure", "color.emerald", "color.ember", "color.magenta",
            "color.violet", "color.amber", "color.teal", "color.brick",
            "color.olive", "color.indigo", "color.walnut", "color.graphite"
        ]
        let key = keys.indices.contains(index) ? keys[index] : keys[0]
        return L10n.string(key, locale: locale)
    }
}

// MARK: - 导航标题
//
// 所有页面的顶部标题与首页品牌标题保持同一字体样式。

struct NavTitle: View {
    let text: String
    var showsDot = false

    var body: some View {
        HStack(spacing: Space.s) {
            if showsDot {
                Text("·")
                    .font(TypeFace.heading(15))
                    .foregroundStyle(Palette.inkTertiary)
            }
            Text(text)
                .font(TypeFace.heading(15))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 品牌标识

struct BrandMark: View {
    /// 指定资源时优先用它；不指定时按当前外观取亮/暗两版。
    var assetName: String? = nil
    var size: CGFloat = 26

    @Environment(\.colorScheme) private var colorScheme

    private var resolvedAssetName: String {
        if let assetName { return assetName }
        // 深底上用浅色版标识，否则一片黑看不见。
        return colorScheme == .dark ? "LogoMarkPaper" : "LogoMarkInk"
    }

    var body: some View {
        Image(resolvedAssetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - 开关
//
// 频道卡的 enabled 开关；提交中禁用，避免重复点击。

struct ChannelToggle: View {
    let isOn: Bool
    let isPending: Bool
    let action: (Bool) -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        // HIG：不在列表行里就不要用开关样式，改用「toggle 形态的按钮」——
        // 图标本身表达状态（勾选/空心），不只靠颜色；可点范围 44pt。
        Button {
            action(!isOn)
        } label: {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isOn ? env.appearance.accent : Palette.inkTertiary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(isPending)
        .opacity(isPending ? 0.5 : 1)
        .accessibilityLabel(Text(String(localized: "channel.toggle.accessibility")))
        .accessibilityValue(Text(isOn ? String(localized: "common.on") : String(localized: "common.off")))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - 按压态
//
// HIG：自定义按钮必须给按压态，否则按下去毫无反馈、像坏掉了。
// List 行有系统高亮，这里的样式主要给 ScrollView 里的自绘按钮与行用。

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// `.buttonStyle(.pressable)`
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - 收起键盘

extension View {
    /// 点空白处收起键盘。
    ///
    /// 用 `simultaneousGesture` 而不是 `onTapGesture`：不抢按钮、行的点击，
    /// 只在没被别的手势消费时兜底。
    func dismissKeyboardOnBackgroundTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        )
    }
}

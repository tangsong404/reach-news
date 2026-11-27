import SwiftUI
import UIKit

/// A small application preference, multiplied into—not substituted for—system Dynamic Type.
enum ReadingTextSize: String, CaseIterable, Identifiable {
    case small
    case standard
    case large

    var id: String { rawValue }
    var labelKey: String { "appearance.textSize." + rawValue }
    var scale: CGFloat {
        switch self {
        case .small: return 0.94
        case .standard: return 1
        case .large: return 1.08
        }
    }
}

private struct ReadingTextSizeKey: EnvironmentKey {
    static let defaultValue: ReadingTextSize = .standard
}

extension EnvironmentValues {
    var readingTextSize: ReadingTextSize {
        get { self[ReadingTextSizeKey.self] }
        set { self[ReadingTextSizeKey.self] = newValue }
    }
}

extension View {
    /// Does not replace the user's system Dynamic Type category or scale icons/navigation chrome.
    func readingTypography(textSize: ReadingTextSize) -> some View {
        environment(\.readingTextSize, textSize)
    }
}

/// View-scoped font resolver. Changes to either preference or Dynamic Type invalidate consumers.
/// Explicit fonts cannot inherit a parent `.font`; consumers must use this resolver.
@propertyWrapper
struct AppTypography: DynamicProperty {
    @Environment(\.readingTextSize) private var textSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var wrappedValue: ResolvedTypography {
        ResolvedTypography(textSize: textSize, dynamicTypeSize: dynamicTypeSize)
    }
}

struct ResolvedTypography {
    var textSize: ReadingTextSize = .standard
    var dynamicTypeSize: DynamicTypeSize = .large

    func scaledSize(_ size: CGFloat) -> CGFloat {
        let base = max(TypeFace.minimumSize, size * textSize.scale)
        return UIFontMetrics(forTextStyle: .body).scaledValue(
            for: base,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.contentSizeCategory)
        )
    }

    func display(_ size: CGFloat) -> Font { font(size, weight: .bold) }
    func title(_ size: CGFloat) -> Font { font(size, weight: .bold) }
    func heading(_ size: CGFloat) -> Font { font(size, weight: .semibold) }
    func body(_ size: CGFloat) -> Font { font(size, weight: .regular) }
    func label(_ size: CGFloat) -> Font { font(size, weight: .medium) }
    var footnote: Font { font(13, weight: .regular) }
    func condensed(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        font(size, weight: weight).width(.condensed)
    }
    func monospacedDigits(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        font(size, weight: weight).monospacedDigit()
    }

    func headingFont(size: CGFloat, style: ReaderStyle) -> Font {
        let multiplier = style == .editorial ? Theme.editorialHeadingScale : Theme.plainHeadingScale
        return font(size * multiplier, weight: style == .editorial ? .bold : .regular)
    }

    /// The inline TextKit attachment shares the same resolved point size as SwiftUI headings.
    func headingUIFont(size: CGFloat, style: ReaderStyle) -> UIFont {
        let multiplier = style == .editorial ? Theme.editorialHeadingScale : Theme.plainHeadingScale
        return .systemFont(
            ofSize: scaledSize(size * multiplier),
            weight: style == .editorial ? .bold : .regular
        )
    }

    private func font(_ size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: scaledSize(size), weight: weight, design: .default)
    }
}

private extension DynamicTypeSize {
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

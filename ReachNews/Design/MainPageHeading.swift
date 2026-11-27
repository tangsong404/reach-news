import SwiftUI

/// One title role for the three root screens, independent of reader text scaling.
struct MainPageHeading: View {
    let title: String
    var showsBrand = false
    var body: some View {
        HStack(spacing: 8) {
            if showsBrand { BrandMark(size: 30) }
            Text(title).font(.system(.largeTitle, design: .default).weight(.bold))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .accessibilityAddTraits(.isHeader)
    }
}

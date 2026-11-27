import SwiftUI

/// One title role for the three root screens, independent of reader text scaling.
struct MainPageHeading: View {
    let title: String
    var showsBrand = false
    var body: some View {
        HStack(spacing: 8) {
            if showsBrand { BrandMark(size: 24) }
            Text(title).font(.system(.title, design: .default).weight(.bold))
                .foregroundStyle(Palette.ink)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
    }
}

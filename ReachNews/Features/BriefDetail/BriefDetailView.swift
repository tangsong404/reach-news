import SwiftUI

// MARK: - 日报详情
//
// 分组吸顶、条目内联展开素材；右下角追问胶囊随滚动收起。

struct BriefDetailView: View {
    let brief: Brief
    @State var store: BriefDetailStore
    @Environment(\.appLocale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(AppEnvironment.self) private var env

    @State private var showsAsk = false
    @State private var isPillExpanded = true
    @State private var lastScrollOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                ForEach(store.brief.sections) { section in
                    SectionStickyHeader(
                        title: section.title,
                        count: section.entries.count,
                        locale: locale
                    )
                    .zIndex(1)

                    VStack(spacing: Space.m) {
                        ForEach(section.entries) { entry in
                            EntryCard(
                                entry: entry,
                                store: store,
                                onOpenMaterial: { url in openURL(url) }
                            )
                        }
                    }
                    .padding(.horizontal, Space.xl)
                    .padding(.top, Space.m)
                    .padding(.bottom, Space.s)
                }
            }
            .padding(.bottom, 120)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: proxy.frame(in: .named("detail-scroll")).minY
                    )
                }
            )
        }
        .coordinateSpace(name: "detail-scroll")
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            handleScroll(value)
        }
        .background(Palette.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: Space.s) {
                    ChannelDot(
                        channelID: brief.channelID,
                        diameter: 7,
                        colorIndex: env.channelColors.colorIndex(for: brief.channelID)
                    )
                    NavTitle(text: store.brief.title)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            AskPill(isExpanded: isPillExpanded) {
                showsAsk = true
            }
            .padding(.trailing, Space.l)
            .padding(.bottom, Space.xxl)
        }
        .navigationDestination(isPresented: $showsAsk) {
            AskView(
                brief: brief,
                store: env.makeAskStore(briefID: brief.id)
            )
        }
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("brief-detail")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(store.brief.title)
                .font(TypeFace.title(25))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.s) {
                MetaLine(text: DisplayTime.monthDayTime(store.brief.createdAt, locale: locale))
                DotSeparator()
                MetaLine(text: L10n.format("brief.sectionCount", locale: locale, store.brief.sections.count))
                DotSeparator()
                MetaLine(text: L10n.format("brief.materialCount", locale: locale, store.brief.materialCount))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.l)
        .padding(.bottom, Space.l)
    }

    /// 滚动时收起胶囊，停止滚动后恢复。
    private func handleScroll(_ offset: CGFloat) {
        let delta = offset - lastScrollOffset
        guard abs(delta) > 4 else { return }
        lastScrollOffset = offset

        if isPillExpanded {
            withAnimation(.easeOut(duration: 0.18)) {
                isPillExpanded = false
            }
        }

        // 停止滚动后恢复展开态。
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            await MainActor.run {
                if !isPillExpanded {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isPillExpanded = true
                    }
                }
            }
        }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - 条目卡

struct EntryCard: View {
    let entry: Entry
    @Bindable var store: BriefDetailStore
    var onOpenMaterial: (URL) -> Void

    @Environment(\.appLocale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.title)
                .font(TypeFace.heading(15.5))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !entry.summary.isEmpty {
                Text(entry.summary)
                    .font(TypeFace.body(13))
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)
            }

            Button {
                store.toggleExpanded(entry)
            } label: {
                HStack(spacing: Space.xs) {
                    Text(L10n.format("briefDetail.materialCount", locale: locale, entry.materialIDs.count))
                        .font(TypeFace.label(11.5))
                        .foregroundStyle(Palette.inkTertiary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.inkTertiary)
                        .rotationEffect(.degrees(store.isExpanded(entry) ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 11)
            .disabled(entry.materialIDs.isEmpty)
            .accessibilityIdentifier("entry-toggle-\(entry.id)")

            if store.isExpanded(entry) && !entry.materialIDs.isEmpty {
                VStack(spacing: 0) {
                    ForEach(entry.materialIDs, id: \.self) { materialID in
                        materialRow(materialID: materialID)
                    }
                }
                .padding(.top, Space.s)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, 14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        }
        .accessibilityIdentifier("entry-card-\(entry.id)")
    }

    @ViewBuilder
    private func materialRow(materialID: String) -> some View {
        if let material = store.material(id: materialID) {
            Button {
                onOpenMaterial(material.url)
            } label: {
                HStack(spacing: Space.m) {
                    Text(material.monogram)
                        .font(TypeFace.condensed(10, weight: .bold))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: 22, height: 22)
                        .background(Palette.lineStrong.opacity(0.4), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        // 只展示标题与来源域名；content 永不渲染。
                        Text(material.title)
                            .font(TypeFace.label(12.5))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(material.host)
                            .font(TypeFace.condensed(10.5, weight: .medium))
                            .foregroundStyle(Palette.inkTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.inkTertiary)
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("material-row-\(materialID)")
            .accessibilityLabel(Text("\(material.title), \(material.host)"))
        } else if store.didFail(materialID: materialID) {
            HStack(spacing: Space.s) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                Text(L10n.string("briefDetail.materialFailed", locale: locale))
                    .font(TypeFace.body(11.5))
                Spacer(minLength: 0)
                Button(L10n.string("common.retry", locale: locale)) {
                    Task { await store.loadMaterials(for: entry) }
                }
                .font(TypeFace.label(11.5))
                .foregroundStyle(Palette.inkSecondary)
            }
            .foregroundStyle(Palette.inkTertiary)
            .padding(.vertical, 9)
        } else {
            HStack(spacing: Space.s) {
                ProgressView().controlSize(.mini)
                Text(L10n.string("common.loading", locale: locale))
                    .font(TypeFace.body(11.5))
                    .foregroundStyle(Palette.inkTertiary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
        }
    }
}

// MARK: - 追问胶囊

struct AskPill: View {
    let isExpanded: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isExpanded ? 7 : 0) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 14, weight: .medium))
                if isExpanded {
                    Text(String(localized: "ask.pill"))
                        .font(TypeFace.heading(13.5))
                }
            }
            .foregroundStyle(Palette.canvas)
            .padding(.horizontal, isExpanded ? 15 : 0)
            .padding(.vertical, isExpanded ? 11 : 0)
            .frame(width: isExpanded ? nil : 46, height: isExpanded ? nil : 46)
            .background(.thinMaterial, in: Capsule())
            .background(Palette.askUser.opacity(0.92), in: Capsule())
            .shadow(color: Palette.ink.opacity(0.32), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isExpanded)
        // 两种形态都读作「追问」。
        .accessibilityLabel(Text(String(localized: "ask.pill")))
        .accessibilityIdentifier("ask-pill")
    }
}

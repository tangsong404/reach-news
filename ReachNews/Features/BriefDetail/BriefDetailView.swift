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
    /// 点了「跟踪事件」后要预填到创建页的标题；nil 表示不是事件模式。
    @State private var trackedEventHeading: String?
    @State private var pendingFollowHeading: String?
    /// 收藏前的二次确认。
    @State private var showsSaveConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                // 读者端只呈现正文：分组与条目不再进入这个界面。
                BriefBodyView(
                    content: store.brief.body,
                    onOpenURL: { url in openURL(url) },
                    onTrackHeading: { heading in
                        pendingFollowHeading = heading
                    },
                    style: env.appearance.style
                )
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.m)
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
        .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 顶部栏只给「日报」：标题已在正文区大字号呈现，重复显示没有意义。
            ToolbarItem(placement: .principal) {
                NavTitle(text: L10n.string("brief.detail.title", locale: locale))
            }
            // 收藏入口：详情页是唯一能收藏日报的地方，收藏后从「我的 → 收藏」进入。
            // 图标跟随主题色；点击先确认，确认后才切换。
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsSaveConfirmation = true
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(env.appearance.accent)
                }
                .accessibilityLabel(
                    Text(L10n.string(isSaved ? "me.saved.remove" : "me.saved.add", locale: locale))
                )
                .accessibilityIdentifier("brief-save")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if env.session.capabilities.ask {
                AskPill(isExpanded: isPillExpanded) {
                    showsAsk = true
                }
                .padding(.trailing, Space.l)
                .padding(.bottom, Space.xxl)
            }
        }
        .navigationDestination(isPresented: $showsAsk) {
            AskView(
                brief: brief,
                store: env.makeAskStore(briefID: brief.id)
            )
        }
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("brief-detail")
        // 二次确认用系统原生 alert：屏幕正中、系统圆角，没有气泡尖角。
        .alert(
            L10n.string("brief.heading.follow.confirm.title", locale: locale),
            isPresented: Binding(
                get: { pendingFollowHeading != nil },
                set: { if !$0 { pendingFollowHeading = nil } }
            )
        ) {
            Button(L10n.string("brief.heading.follow.confirm.action", locale: locale)) {
                trackedEventHeading = pendingFollowHeading
                pendingFollowHeading = nil
            }
            Button(L10n.string("common.cancel", locale: locale), role: .cancel) {
                pendingFollowHeading = nil
            }
        } message: {
            if let heading = pendingFollowHeading {
                Text(heading)
            }
        }
        .alert(
            L10n.string(isSaved ? "brief.save.remove.title" : "brief.save.confirm.title", locale: locale),
            isPresented: $showsSaveConfirmation
        ) {
            Button(L10n.string(isSaved ? "brief.save.remove.action" : "brief.save.confirm.action", locale: locale)) {
                env.saved.toggle(brief.id)
            }
            Button(L10n.string("common.cancel", locale: locale), role: .cancel) {}
        }
        .navigationDestination(isPresented: Binding(
            get: { trackedEventHeading != nil },
            set: { if !$0 { trackedEventHeading = nil } }
        )) {
            if let heading = trackedEventHeading {
                // navigationDestination 会多次求值 body，这里用常量绑定避免反复触发 dismiss。
                ChannelCreateSheet(
                    store: env.channels,
                    isPresented: .constant(true),
                    onCreated: { channel in
                        env.channels.replace(channel)
                        trackedEventHeading = nil
                    },
                    eventHeading: heading
                )
            }
        }
    }

    private var isSaved: Bool { env.saved.isSaved(brief.id) }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(store.brief.title)
                .font(Theme.headingFont(size: 25, style: env.appearance.style))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            // 描述紧跟在标题下；为空时整块不渲染，不留空洞。
            if let summary = store.brief.displaySummary {
                Text(summary)
                    .font(TypeFace.body(15))
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("brief-summary")
            }

            // 分组数与素材数来自 sections，读者端不再展示，只留日期时刻。
            MetaLine(text: DisplayTime.monthDayTime(store.brief.createdAt, locale: locale))
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
            // 深底上的浅色文字用语义 token，而不是借用画布色。
            .foregroundStyle(Palette.askUserText)
            .padding(.horizontal, isExpanded ? 15 : 0)
            .padding(.vertical, isExpanded ? 11 : 0)
            .frame(width: isExpanded ? nil : 46, height: isExpanded ? nil : 46)
            // 直接用近黑色实底：再叠一层 thinMaterial 是半透明浅色，会把深色冲淡成灰。
            .background(Palette.askUser, in: Capsule())
            .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isExpanded)
        // 两种形态都读作「追问」。
        .accessibilityLabel(Text(String(localized: "ask.pill")))
        .accessibilityIdentifier("ask-pill")
    }
}

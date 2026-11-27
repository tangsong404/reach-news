import SwiftUI

// MARK: - 追问
//
// 近单色工具风，与日报的编辑风严格分开（ADR 0001）。
// 服务端回答是确定性拼接：不流式、不逐字、不显示「正在思考」。

struct AskView: View {
    let brief: Brief
    @State var store: AskStore
    @Environment(\.appLocale) private var locale
    /// 减弱动态效果时不做滚动动画（HIG：Reduce Motion 时减少自动与重复动画）。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            conversation
            composer
        }
        .background(Palette.askBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: Space.s) {
                    NavTitle(text: L10n.string("ask.nav.title", locale: locale))
                    Spacer(minLength: 0)
                }
            }
        }
        .toolbarBackground(Palette.askBackground, for: .navigationBar)
        .task {
            await store.loadHistoryIfNeeded()
        }
        .accessibilityIdentifier("ask-view")
        // 只有三个一级页面保留标签栏，推入的页面全部隐藏（用户确认）。
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: 会话

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if store.isLoadingHistory {
                        LoadingLine(text: L10n.string("common.loading", locale: locale))
                    } else if let error = store.error, store.turns.isEmpty {
                        MessageStateView(
                            title: L10n.string(error.messageKey, locale: locale),
                            message: error.isOffline ? L10n.string("error.offline.detail", locale: locale) : nil,
                            kind: .error(error),
                            actionTitle: L10n.string("common.retry", locale: locale),
                            action: { Task { await store.loadHistory() } }
                        )
                    } else if store.isEmpty {
                        MessageStateView(
                            title: L10n.string("ask.empty.title", locale: locale),
                            message: L10n.string("ask.empty.message", locale: locale),
                            kind: .empty
                        )
                    } else {
                        if store.hasMore {
                            Button(L10n.string("ask.loadEarlier", locale: locale)) {
                                Task { await store.loadMore() }
                            }
                            .font(TypeFace.label(11.5))
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.s)
                        }

                        ForEach(Array(store.turns.enumerated()), id: \.element.id) { index, turn in
                            if showsDateDivider(at: index) {
                                Text(DisplayTime.monthDayTime(turn.createdAt, locale: locale))
                                    .font(TypeFace.condensed(10.5, weight: .medium))
                                    .foregroundStyle(Palette.inkTertiary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Space.m)
                            }

                            AskBubble(turn: turn, isLast: index == store.turns.count - 1)
                                .id(turn.id)
                        }

                        // 引用素材卡：服务端不返回引用关系，按稿子留位并标开发中。
                        if store.turns.last?.role == .assistant {
                            // 读者端不再展示分组，原来的「看这期分组」动作已移除。
                            citedMaterialsCard
                                .padding(.top, Space.xs)
                                .padding(.bottom, Space.m)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, Space.l)
            }
            .onChange(of: store.turns.count) { _, _ in
                if let last = store.turns.last {
                    if reduceMotion {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func showsDateDivider(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.shanghai.isDate(
            store.turns[index].createdAt,
            inSameDayAs: store.turns[index - 1].createdAt
        )
    }

    /// 「引用的素材 · N 条」内嵌卡。
    /// 服务端从本期 sections 汇总 `citedItemIds`，这里如实呈现，不伪造归属。
    private var citedMaterialsCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.xs) {
                Text(L10n.string("ask.cited.heading", locale: locale))
                    .font(TypeFace.label(11))
                    .foregroundStyle(Palette.inkTertiary)
                Spacer(minLength: 0)
                Text(L10n.format("ask.cited.count", locale: locale, store.lastCitedItemIDs.count))
                    .font(TypeFace.condensed(10.5, weight: .medium))
                    .foregroundStyle(Palette.inkTertiary)
            }

            if store.lastCitedItemIDs.isEmpty {
                Text(L10n.string("ask.cited.empty", locale: locale))
                    .font(TypeFace.body(11.5))
                    .foregroundStyle(Palette.inkTertiary)
            } else {
                ForEach(Array(store.lastCitedItemIDs.enumerated()), id: \.offset) { index, itemID in
                    HStack(alignment: .top, spacing: Space.s) {
                        Text(Self.indexLabel(index))
                            .font(TypeFace.condensed(10, weight: .bold))
                            .foregroundStyle(Palette.inkTertiary)
                            .frame(width: 11, alignment: .leading)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(store.materialTitle(for: itemID))
                                .font(TypeFace.body(12.5))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            if let host = store.materialHost(for: itemID) {
                                Text(host)
                                    .font(TypeFace.condensed(10, weight: .medium))
                                    .foregroundStyle(Palette.inkTertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            if store.lastAnswerWasDeterministic {
                Text(L10n.string("ask.cited.deterministic", locale: locale))
                    .font(TypeFace.body(10.5))
                    .foregroundStyle(Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.askSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityIdentifier("ask-cited-card")
    }

    /// A、B、C… 序号，与稿子一致。
    private static func indexLabel(_ index: Int) -> String {
        guard let scalar = UnicodeScalar(65 + index % 26) else { return "A" }
        return String(Character(scalar))
    }

    // MARK: 输入栏

    private var composer: some View {
        VStack(spacing: Space.s) {
            if let failureKey = store.sendFailureMessage {
                InlineNotice(
                    text: L10n.string(failureKey, locale: locale),
                    kind: .error
                )
                .padding(.horizontal, Space.m)
            }

            HStack(spacing: Space.s) {
                Button {
                    // 稿子里的「+」：暂未定义动作，保持位置。
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: 36, height: 36)
                        .background(Palette.askSurface, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text(String(localized: "ask.composer.add")))
                .accessibilityIdentifier("ask-composer-add")

                @Bindable var store = store
                TextField(String(localized: "ask.composer.placeholder"), text: $store.draft, axis: .vertical)
                    .font(TypeFace.body(13))
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, 10)
                    .background(Palette.askSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityIdentifier("ask-composer-field")

                Button {
                    Task { await store.send() }
                } label: {
                    Image(systemName: store.isSending ? "ellipsis" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(store.canSend ? Palette.canvas : Palette.inkTertiary)
                        .frame(width: 36, height: 36)
                        .background(store.canSend ? Palette.ink : Palette.askSurface, in: Circle())
                }
                .buttonStyle(.pressable)
                .disabled(!store.canSend)
                .accessibilityLabel(Text(String(localized: "ask.composer.send")))
                .accessibilityIdentifier("ask-composer-send")
            }
            .padding(.horizontal, 14)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxs)
        }
        .background(Palette.askBackground)
    }
}

// MARK: - 气泡

struct AskBubble: View {
    let turn: AskTurn
    var isLast: Bool

    var body: some View {
        HStack {
            if turn.role == .user { Spacer(minLength: 40) }

            Text(turn.message)
                .font(TypeFace.body(13.5))
                .foregroundStyle(turn.role == .user ? Palette.askUserText : Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.l)
                .padding(.vertical, 13)
                .background(
                    turn.role == .user ? Palette.askUser : Palette.askBubble,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 19,
                        bottomLeadingRadius: turn.role == .user ? 19 : 6,
                        bottomTrailingRadius: turn.role == .user ? 6 : 19,
                        topTrailingRadius: 19,
                        style: .continuous
                    )
                )
                .accessibilityIdentifier("ask-bubble-\(turn.role.rawValue)")

            if turn.role == .assistant { Spacer(minLength: 40) }
        }
        .padding(.bottom, turn.role == .user ? Space.l : 10)
        .accessibilityElement(children: .combine)
    }
}

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
    /// 底部输入框里正在输入的问题。
    @State private var questionDraft = ""
    /// 带着问题跳进追问页时，那一句要自动发出。
    @State private var pendingQuestion: String?
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
        }
        .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 顶部栏只给「日报」：标题已在正文区大字号呈现，重复显示没有意义。
            ToolbarItem(placement: .principal) {
                NavTitle(text: L10n.string("brief.detail.title", locale: locale))
            }
            // 追问入口放工具栏：HIG 没有浮动按钮（FAB）这种模式，
            // 而且自绘胶囊会压住正文右下角。
            if env.session.capabilities.ask {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsAsk = true
                    } label: {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 16, weight: .regular))
                    }
                    .accessibilityLabel(Text(String(localized: "ask.pill")))
                    .accessibilityIdentifier("ask-pill")
                }
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
        // 底栏是直接提问入口；右上角工具栏入口仍然保留。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if env.session.capabilities.ask {
                askBar
            }
        }
        .navigationDestination(isPresented: $showsAsk) {
            AskView(
                brief: brief,
                store: env.makeAskStore(briefID: brief.id),
                initialQuestion: pendingQuestion
            )
        }
        .accessibilityIdentifier("brief-detail")
        // 只有三个一级页面保留标签栏，推入的页面全部隐藏（用户确认）。
        .toolbar(.hidden, for: .tabBar)
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

    /// 底部提问条：输入即问，走与追问页相同的 store。
    private var askBar: some View {
        HStack(spacing: Space.s) {
            TextField(
                L10n.string("ask.bar.placeholder", locale: locale),
                text: $questionDraft,
                axis: .vertical
            )
            .font(TypeFace.body(14))
            .lineLimit(1...3)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(Palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .submitLabel(.send)
            .onSubmit(sendQuestion)
            .accessibilityIdentifier("brief-ask-field")

            Button(action: sendQuestion) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.onInverse)
                    .frame(width: 34, height: 34)
                    .background(env.appearance.accent, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.pressable)
            .disabled(questionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(questionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            .accessibilityLabel(Text(L10n.string("ask.bar.send", locale: locale)))
            .accessibilityIdentifier("brief-ask-send")
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .background(.bar)
    }

    private func sendQuestion() {
        let question = questionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        pendingQuestion = question
        questionDraft = ""
        showsAsk = true
    }

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

}

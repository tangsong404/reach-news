import SwiftUI

// MARK: - 订阅频道详情（只读）
//
// 订阅频道的一切写入都只发生在订阅关系上：改颜色、fork、取消订阅。
// 频道本身对订阅者只读，因此这里不出现保存、删除、立即运行入口。

struct SubscribedChannelDetail: View {
    let channel: Channel
    var onUpdated: (Channel) -> Void
    var onForked: (Channel) -> Void
    var onUnsubscribed: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.appLocale) private var locale

    @State private var showsColorPicker = false
    @State private var showsUnsubscribeConfirm = false
    @State private var showsForkConfirm = false
    @State private var isWorking = false
    @State private var actionError: APIError?
    @State private var colorSelection: Int = 0
    /// 服务端返回的新版本优先级高于进入页面时的快照。
    @State private var current: Channel?

    private var displayed: Channel { current ?? channel }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error = actionError {
                    InlineNotice(
                        text: L10n.string(error.messageKey, locale: locale),
                        detail: error.detailText,
                        kind: .error
                    )
                    .accessibilityIdentifier("subscribed-detail-error")
                }

                header

                field(titleKey: "channelEdit.prompt") {
                    readonlyBox(text: displayed.prompt)
                        .accessibilityIdentifier("subscribed-detail-prompt")
                }

                field(titleKey: "channelEdit.tone") {
                    readonlyBox(text: displayed.tone.isEmpty
                                ? L10n.string("subscribed.detail.tone.empty", locale: locale)
                                : displayed.tone)
                        .accessibilityIdentifier("subscribed-detail-tone")
                }

                field(titleKey: "channelEdit.schedule") {
                    // 只读呈现：不用带箭头的手选行，避免暗示可以点开编辑。
                    readonlyBox(
                        text: ScheduleDisplay.summary(displayed.schedule, locale: locale)
                            ?? L10n.string("schedule.notSet", locale: locale),
                        isPlaceholder: displayed.schedule.isEmpty
                    )
                    .accessibilityIdentifier("subscribed-detail-schedule")
                }

                field(titleKey: "channelEdit.connectors") {
                    readonlyBox(
                        text: connectorSummary,
                        isPlaceholder: displayed.connectors.isEmpty
                    )
                    .accessibilityIdentifier("subscribed-detail-connectors")
                }

                field(titleKey: "channelEdit.color") {
                    // 标题 + 控件即可，不额外解释颜色只影响本机。
                    Button {
                        showsColorPicker = true
                    } label: {
                        HStack(spacing: Space.s) {
                            Circle()
                                .fill(ChannelTint.color(at: colorSelection))
                                .frame(width: 16, height: 16)
                            Text(ChannelColorName.name(for: colorSelection, locale: locale))
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
                                .fill(Palette.surface)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                                .strokeBorder(Palette.line, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityIdentifier("subscribed-detail-color-field")
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxl)
        }
        .background(Palette.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavTitle(text: L10n.string("subscribed.detail.title", locale: locale))
            }
            // 订阅频道的动作放导航栏菜单，不用底部通栏按钮。
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showsForkConfirm = true
                    } label: {
                        Label(L10n.string("subscribed.fork", locale: locale), systemImage: "square.on.square")
                    }
                    Button(role: .destructive) {
                        showsUnsubscribeConfirm = true
                    } label: {
                        Label(L10n.string("subscribed.unsubscribe", locale: locale), systemImage: "minus.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(Palette.ink)
                }
                .disabled(isWorking)
                .accessibilityIdentifier("subscribed-detail-menu")
            }
        }
        .onAppear {
            colorSelection = env.channelColors.displayIndex(for: displayed)
        }
        .sheet(isPresented: $showsColorPicker) {
            ColorPickerSheet(selection: $colorSelection, isPresented: $showsColorPicker)
                .presentationDetents(SheetMetrics.detents)
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.canvas)
        }
        .onChange(of: showsColorPicker) { _, isPresented in
            // 关闭选色层时才提交，避免每一格点击都发一次请求。
            guard !isPresented else { return }
            Task { await applyColor() }
        }
        .alert(
            L10n.string("subscribed.unsubscribe.confirm.title", locale: locale),
            isPresented: $showsUnsubscribeConfirm
        ) {
            Button(L10n.string("subscribed.unsubscribe", locale: locale), role: .destructive) {
                Task { await unsubscribe() }
            }
            Button(L10n.string("common.cancel", locale: locale), role: .cancel) {}
        } message: {
            Text(L10n.string("subscribed.unsubscribe.confirm.message", locale: locale))
        }
        .alert(
            L10n.string("subscribed.fork.confirm.title", locale: locale),
            isPresented: $showsForkConfirm
        ) {
            Button(L10n.string("subscribed.fork", locale: locale)) {
                Task { await fork() }
            }
            Button(L10n.string("common.cancel", locale: locale), role: .cancel) {}
        } message: {
            Text(L10n.string("subscribed.fork.confirm.message", locale: locale))
        }
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("subscribed-channel-detail")
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                ChannelDot(
                    channelID: displayed.id,
                    diameter: 10,
                    colorIndex: env.channelColors.displayIndex(for: displayed)
                )
                Text(displayed.name)
                    .font(TypeFace.heading(19))
                    .foregroundStyle(Palette.ink)
                Text(L10n.string("channel.kind.subscribed", locale: locale))
                    .font(TypeFace.condensed(9.5, weight: .semibold))
                    .foregroundStyle(Palette.inkTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Palette.lineStrong, lineWidth: 1)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 动作实现

    private func applyColor() async {
        guard !isWorking else { return }
        let previous = displayed
        // 与服务端已存颜色比较，而不是与本地回退色比较：订阅时未给颜色（空字符串）的情况下，
        // 用户选中与回退色相同的颜色也应真正写入服务端。
        guard colorSelection != ChannelTint.paletteIndex(for: previous.subscriptionColor) else { return }
        isWorking = true
        actionError = nil
        defer { isWorking = false }

        if let updated = await env.channels.updateSubscriptionColor(previous.id, colorIndex: colorSelection) {
            current = updated
            onUpdated(updated)
        } else {
            colorSelection = env.channelColors.displayIndex(for: previous)
            actionError = env.channels.error
        }
    }

    private func unsubscribe() async {
        guard !isWorking else { return }
        isWorking = true
        actionError = nil
        defer { isWorking = false }

        if await env.channels.unsubscribe(displayed.id) {
            env.channelColors.forget(displayed.id)
            // 由父视图清空导航绑定来退出本页，避免重复 dismiss。
            onUnsubscribed()
        } else {
            actionError = env.channels.error
        }
    }

    private func fork() async {
        guard !isWorking else { return }
        isWorking = true
        actionError = nil
        defer { isWorking = false }

        if let created = await env.channels.fork(displayed.id) {
            env.channelColors.forget(displayed.id)
            env.channelColors.setColorIndex(
                env.channelColors.displayIndex(for: created),
                for: created.id
            )
            onForked(created)
        } else {
            actionError = env.channels.error
        }
    }

    // MARK: 只读容器

    private var connectorSummary: String {
        let names = displayed.connectors.map(\.displayName)
        if names.isEmpty { return L10n.string("channelEdit.connectors.none", locale: locale) }
        return names.joined(separator: "、")
    }

    private func readonlyBox(text: String, isPlaceholder: Bool = false) -> some View {
        Text(text)
            .font(TypeFace.body(14))
            .foregroundStyle(isPlaceholder ? Palette.inkTertiary : Palette.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Palette.surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            }
    }

    private func field<Content: View>(
        titleKey: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(L10n.string(titleKey, locale: locale))
                .font(TypeFace.label(11))
                .tracking(1)
                .foregroundStyle(Palette.inkTertiary)
            content()
        }
    }
}

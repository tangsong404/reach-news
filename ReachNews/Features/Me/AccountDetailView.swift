import SwiftUI
import PhotosUI

// MARK: - 个人页
//
// 从「我的」页的账号卡片进入。承载与账号相关的全部操作：
// 修改头像、切换昵称、换绑邮箱、修改密码、退出登录。
//
// 其中昵称/邮箱/密码的写接口后端尚未提供（实测 PATCH /api/v1/me、
// POST /api/v1/me/email、POST /api/v1/me/password 均 404）。
// 这些入口照做，但提交按钮置灰并注明暂未支持——不给用户点了没反应的假入口。
// 头像上传与退出登录是真实可用的。

struct AccountDetailView: View {
    let session: SessionStore
    @Environment(\.appLocale) private var locale
    @Environment(AppEnvironment.self) private var env

    @State private var photoItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var avatarError: String?
    @State private var showsNicknameSheet = false
    @State private var showsPasswordSheet = false

    private var profile: ProfileStore { env.profile }

    var body: some View {
        List {
            avatarSection
            profileSection
            securitySection
            signOutSection
        }
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavTitle(text: L10n.string("account.title", locale: locale))
            }
        }
        .accessibilityIdentifier("account-detail")
        .sheet(isPresented: $showsNicknameSheet) {
            NicknameSheet(session: session, initialValue: profile.userName)
                .presentationDetents(SheetMetrics.detents)
        }
        .sheet(isPresented: $showsPasswordSheet) {
            PasswordChangeSheet(session: session)
                .presentationDetents(SheetMetrics.detents)
        }
        .task {
            await session.refreshProfile()
        }
    }

    // MARK: 头像

    private var avatarSection: some View {
        Section {
            VStack(spacing: Space.m) {
                AvatarView(url: profile.avatarURL, size: 88)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    if isUploadingAvatar {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(L10n.string("account.avatar.change", locale: locale))
                            .font(TypeFace.label(12.5))
                            .foregroundStyle(Palette.ink)
                    }
                }
                .disabled(isUploadingAvatar)
                .accessibilityIdentifier("account-avatar-change")

                if let avatarError {
                    Text(avatarError)
                        .font(TypeFace.footnote)
                        .foregroundStyle(Palette.failedForeground)
                }

                // 有头像时才给删除入口：无头像时删了也没有变化。
                if profile.avatarURL != nil {
                    Button(role: .destructive) {
                        Task { await removeAvatar() }
                    } label: {
                        Text(L10n.string("account.avatar.remove", locale: locale))
                            .font(TypeFace.label(12.5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.failedForeground)
                    .accessibilityIdentifier("account-avatar-remove")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s)
        }
        .listRowBackground(Palette.surface)
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            Task { await uploadAvatar(newValue) }
        }
    }

    private func removeAvatar() async {
        avatarError = nil
        let ok = await session.deleteAvatar()
        if !ok {
            avatarError = L10n.string("account.avatar.removeFailed", locale: locale)
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        isUploadingAvatar = true
        avatarError = nil
        defer {
            isUploadingAvatar = false
            photoItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            avatarError = L10n.string("account.avatar.failed", locale: locale)
            return
        }
        let ok = await session.uploadAvatar(imageData: data)
        if !ok {
            avatarError = L10n.string("account.avatar.failed", locale: locale)
        }
    }

    // MARK: 资料

    private var profileSection: some View {
        Section {
            Button {
                showsNicknameSheet = true
            } label: {
                row(
                    titleKey: "account.nickname.label",
                    value: profile.userName,
                    identifier: "account-edit-nickname"
                )
            }
            .buttonStyle(.plain)

            // 邮箱只读展示：服务端没有换绑邮箱接口，不放入口。
            row(
                titleKey: "account.email.label",
                value: profile.email ?? L10n.string("me.account.email.empty", locale: locale),
                identifier: "account-email-readonly"
            )

            HStack {
                Text(L10n.string("account.tier.label", locale: locale))
                    .font(TypeFace.body(13))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer(minLength: Space.s)
                TierBadge(tier: profile.planLabel)
            }
        } header: {
            Text(L10n.string("account.profile.heading", locale: locale))
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: 安全

    private var securitySection: some View {
        Section {
            Button {
                showsPasswordSheet = true
            } label: {
                row(
                    titleKey: "account.password.label",
                    value: nil,
                    identifier: "account-edit-password"
                )
            }
            .buttonStyle(.plain)
        } header: {
            Text(L10n.string("account.security.heading", locale: locale))
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: 退出登录

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                Task { await session.signOut() }
            } label: {
                Text(L10n.string("connection.signOut", locale: locale))
                    .font(TypeFace.body(13.5))
            }
            .accessibilityIdentifier("account-signout")
        }
        .listRowBackground(Palette.surface)
    }

    private func row(titleKey: String, value: String?, identifier: String) -> some View {
        HStack {
            Text(L10n.string(titleKey, locale: locale))
                .font(TypeFace.body(13))
                .foregroundStyle(Palette.inkSecondary)
            Spacer(minLength: Space.s)
            if let value, !value.isEmpty {
                Text(value)
                    .font(TypeFace.label(13))
                    .foregroundStyle(Palette.inkTertiary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.inkTertiary)
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - 头像视图

/// 圆形头像：有 url 时异步加载，失败或没有时显示缺省图形。
struct AvatarView: View {
    let url: URL?
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().fill(Palette.paper)
            if let url {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        glyph
                    }
                }
            } else {
                glyph
            }
        }
        .frame(width: size, height: size)
        .overlay { Circle().strokeBorder(Palette.line, lineWidth: 1) }
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var glyph: some View {
        Image(systemName: "person.fill")
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(Palette.inkTertiary)
    }
}

// MARK: - 套餐标签
//
// 胶囊底 + 小字：admin 紫、ultra 金、free 中性灰。
// 未知档位用中性灰，不猜也不降级成 ultra。

struct TierBadge: View {
    let tier: String

    private var colors: (background: Color, foreground: Color) {
        switch tier.lowercased() {
        case "admin":
            return (Color(hex: 0x6A4FA0).opacity(0.14), Color(hex: 0x6A4FA0))
        case "ultra":
            return (Color(hex: 0xB08615).opacity(0.16), Color(hex: 0x8A6A0F))
        default:
            return (Palette.chip, Palette.inkSecondary)
        }
    }

    var body: some View {
        Text(tier)
            .font(TypeFace.label(10.5))
            .foregroundStyle(colors.foreground)
            .padding(.horizontal, Space.xs)
            .padding(.vertical, 2.5)
            .background(
                Capsule().fill(colors.background)
            )
            .accessibilityIdentifier("account-tier-badge")
    }
}

// MARK: - 改昵称

struct NicknameSheet: View {
    let session: SessionStore
    let initialValue: String

    @Environment(\.appLocale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var value: String = ""
    @State private var error: RegistrationError?
    @State private var isSaving = false

    private var canSave: Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != initialValue && !isSaving
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.l) {
                if let error {
                    InlineNotice(text: message(for: error), kind: .error)
                        .accessibilityIdentifier("nickname-error")
                }

                TextField("", text: $value)
                    .font(TypeFace.body(15))
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
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("nickname-input")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.l)
            .sheetContentInset()
            .background(Palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavTitle(text: L10n.string("account.nickname.title", locale: locale))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string("common.cancel", locale: locale)) { dismiss() }
                        .font(TypeFace.body(14))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.string("common.save", locale: locale))
                                .font(TypeFace.heading(15))
                                .foregroundStyle(canSave ? Palette.ink : Palette.inkTertiary)
                        }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("nickname-save")
                }
            }
        }
        .onAppear { value = initialValue }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        error = nil
        Task {
            let failure = await session.updateNickname(value)
            isSaving = false
            if let failure {
                error = failure
            } else {
                dismiss()
            }
        }
    }

    /// 服务端 message 优先；没有时用 code 对应兜底。
    private func message(for error: RegistrationError) -> String {
        let server = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !server.isEmpty { return server }
        let key = "nickname.error." + error.code
        let fallback = L10n.string(key, locale: locale)
        return fallback == key ? L10n.string("nickname.error.unknown", locale: locale) : fallback
    }
}

// MARK: - 修改密码

struct PasswordChangeSheet: View {
    let session: SessionStore

    @Environment(\.appLocale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var next = ""
    @State private var confirm = ""
    @State private var error: RegistrationError?
    @State private var isSaving = false

    private var canSave: Bool {
        !current.isEmpty && !next.isEmpty && !confirm.isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if let error {
                        InlineNotice(text: message(for: error), kind: .error)
                            .accessibilityIdentifier("password-error")
                    }

                    secureField(labelKey: "account.password.current", text: $current, identifier: "password-current")
                    secureField(labelKey: "account.password.new", text: $next, identifier: "password-new")
                    secureField(labelKey: "account.password.confirm", text: $confirm, identifier: "password-confirm")
                }
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.l)
                .padding(.bottom, 44)
            }
            .sheetContentInset()
            .background(Palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavTitle(text: L10n.string("account.password.title", locale: locale))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string("common.cancel", locale: locale)) { dismiss() }
                        .font(TypeFace.body(14))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.string("common.save", locale: locale))
                                .font(TypeFace.heading(15))
                                .foregroundStyle(canSave ? Palette.ink : Palette.inkTertiary)
                        }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("password-save")
                }
            }
        }
        .accessibilityIdentifier("password-sheet")
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        error = nil
        Task {
            let failure = await session.changePassword(current: current, new: next, confirm: confirm)
            isSaving = false
            if let failure {
                error = failure
            } else {
                // 服务端方案 A：当前 token 仍有效，不踢用户回登录页。
                dismiss()
            }
        }
    }

    private func message(for error: RegistrationError) -> String {
        let server = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !server.isEmpty { return server }
        let key = "password.error." + error.code
        let fallback = L10n.string(key, locale: locale)
        return fallback == key ? L10n.string("password.error.unknown", locale: locale) : fallback
    }

    private func secureField(labelKey: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(L10n.string(labelKey, locale: locale))
                .font(TypeFace.label(11))
                .tracking(1)
                .foregroundStyle(Palette.inkTertiary)
            SecureField("", text: text)
                .font(TypeFace.body(14))
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                }
                .accessibilityIdentifier(identifier)
        }
    }
}

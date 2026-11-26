import SwiftUI
import PhotosUI

// MARK: - 个人页
//
// 从「我的」页的账号卡片进入。承载与账号相关的全部操作：
// 修改头像、切换昵称、修改密码、退出登录。
//
// 昵称（PATCH /api/v1/me）、头像（POST/DELETE /api/v1/me/avatar）与密码
// （POST /api/v1/me/password，需邮箱验证码）都是真实接口；
// 邮箱只读——服务端没有换绑接口。

struct AccountDetailView: View {
    let session: SessionStore
    @Environment(\.appLocale) private var locale
    @Environment(AppEnvironment.self) private var env

    @State private var photoItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var avatarError: String?
    @State private var showsNicknameSheet = false
    @State private var showsPasswordSheet = false
    /// 轻量成功提示；nil 表示不显示。
    @State private var toast: String?
    @State private var showsSignOutConfirmation = false

    private var profile: ProfileStore { env.profile }

    var body: some View {
        List {
            avatarSection
            profileSection
            securitySection
            signOutSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas(for: env.appearance.style))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavTitle(text: L10n.string("account.title", locale: locale))
            }
        }
        .accessibilityIdentifier("account-detail")
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(TypeFace.label(13))
                    .foregroundStyle(Palette.canvas)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.s)
                    .background(Capsule().fill(Palette.ink))
                    .padding(.bottom, Space.xxl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("account-toast")
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast)
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            toast = nil
        }
        // 二次确认用系统原生 alert：屏幕正中、系统圆角，没有气泡尖角。
        .alert(
            L10n.string("account.signout.confirm.title", locale: locale),
            isPresented: $showsSignOutConfirmation
        ) {
            Button(L10n.string("connection.signOut", locale: locale), role: .destructive) {
                Task { await session.signOut() }
            }
            Button(L10n.string("common.cancel", locale: locale), role: .cancel) {}
        }
        .sheet(isPresented: $showsNicknameSheet) {
            NicknameSheet(session: session, initialValue: profile.userName)
                .presentationDetents(SheetMetrics.detents)
        }
        .sheet(isPresented: $showsPasswordSheet) {
            PasswordChangeSheet(session: session) {
                // 成功提示：之前改完只无声关闭，用户不知道到底成没成。
                toast = L10n.string("account.password.changed", locale: locale)
            }
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
        .listRowBackground(Theme.surface(for: env.appearance.style))
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

            // 邮箱是不可修改项：没有换绑接口，因此不显示进入箭头，
            // 也不做成可点的行——免得看起来能点却点不动。
            HStack {
                Text(L10n.string("account.email.label", locale: locale))
                    .font(TypeFace.body(13))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer(minLength: Space.s)
                Text(profile.email ?? L10n.string("me.account.email.empty", locale: locale))
                    .font(TypeFace.label(13))
                    .foregroundStyle(Palette.inkTertiary)
                    .lineLimit(1)
            }
            .accessibilityIdentifier("account-email-readonly")

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
        .listRowBackground(Theme.surface(for: env.appearance.style))
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
        .listRowBackground(Theme.surface(for: env.appearance.style))
    }

    // MARK: 退出登录

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                showsSignOutConfirmation = true
            } label: {
                Text(L10n.string("connection.signOut", locale: locale))
                    .font(TypeFace.body(13.5))
            }
            .accessibilityIdentifier("account-signout")
        }
        .listRowBackground(Theme.surface(for: env.appearance.style))
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
            return (
                Color(light: 0x6A4FA0, dark: 0xA98FD8).opacity(0.16),
                Color(light: 0x6A4FA0, dark: 0xC3B0EE)
            )
        case "ultra":
            return (
                Color(light: 0xB08615, dark: 0xD8B75C).opacity(0.18),
                Color(light: 0x8A6A0F, dark: 0xEBD08D)
            )
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

    @Environment(AppEnvironment.self) private var env
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
                            .fill(Theme.surface(for: env.appearance.style, mode: env.appearance.mode))
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
            .background(Theme.canvas(for: env.appearance.style))
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
//
// 2026-11-26 起该接口必须带邮箱验证码（purpose=change-password）。
// 只有当前密码不够——否则任何拿到已登录设备的人都能把机主锁在外面。
// 当前密码错时验证码不会被消耗，改对后可用同一个码继续。

struct PasswordChangeSheet: View {
    let session: SessionStore

    @Environment(AppEnvironment.self) private var env
    @Environment(\.appLocale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var next = ""
    @State private var confirm = ""
    @State private var emailCode = ""
    @State private var error: RegistrationError?
    @State private var isSaving = false
    @State private var isSendingCode = false
    @State private var codeSent = false
    @State private var resendCountdown = 0

    /// 输入框底色随风格走，和设置页保持一致。
    private var fieldSurface: Color {
        Theme.surface(for: env.appearance.style, mode: env.appearance.mode)
    }
    /// 成功后的回调：由上层负责弹提示。
    var onChanged: (() -> Void)?

    private var canSendCode: Bool {
        !isSendingCode && resendCountdown == 0 && !isSaving
    }

    private var canSave: Bool {
        !current.isEmpty && !next.isEmpty && !confirm.isEmpty
            && !emailCode.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSaving
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

                    // 邮箱验证码：接口要求，缺少会直接 400。
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(L10n.string("account.password.emailCode", locale: locale))
                            .font(TypeFace.label(11))
                            .tracking(1)
                            .foregroundStyle(Palette.inkTertiary)

                        HStack(spacing: Space.s) {
                            TextField("", text: $emailCode)
                                .font(TypeFace.body(14))
                                .keyboardType(.numberPad)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 11)
                                .background(fieldSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Palette.line, lineWidth: 1)
                                }
                                .accessibilityIdentifier("password-email-code")

                            Button {
                                Task { await sendCode() }
                            } label: {
                                if isSendingCode {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text(resendCountdown > 0
                                         ? L10n.format("register.emailCode.resendIn", locale: locale, resendCountdown)
                                         : L10n.string("register.emailCode.send", locale: locale))
                                        .font(TypeFace.label(12))
                                        .foregroundStyle(canSendCode ? Palette.ink : Palette.inkTertiary)
                                        .lineLimit(1)
                                }
                            }
                            .disabled(!canSendCode)
                            .accessibilityIdentifier("password-email-code-send")
                        }

                        if codeSent {
                            Text(L10n.string("register.emailCode.sent", locale: locale))
                                .font(TypeFace.footnote)
                                .foregroundStyle(Palette.runningForeground)
                        } else {
                            Text(L10n.string("account.password.emailCode.hint", locale: locale))
                                .font(TypeFace.footnote)
                                .foregroundStyle(Palette.inkTertiary)
                        }
                    }
                }
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.l)
                .padding(.bottom, 44)
            }
            .sheetContentInset()
            .background(Theme.canvas(for: env.appearance.style))
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

    private func sendCode() async {
        isSendingCode = true
        error = nil
        codeSent = false
        defer { isSendingCode = false }

        // 改密码的验证码不需要 captcha，且发到当前账号绑定的邮箱。
        let email = session.profile?.email ?? ""
        let failure = await session.requestEmailCode(email: email, purpose: "change-password")
        if let failure {
            error = RegistrationError(code: failure.code, message: failure.message)
            if let seconds = failure.retryAfterSeconds, seconds > 0 {
                startCountdown(seconds)
            }
        } else {
            codeSent = true
            startCountdown(60)
        }
    }

    private func startCountdown(_ seconds: Int) {
        resendCountdown = seconds
        Task {
            while resendCountdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                resendCountdown = max(0, resendCountdown - 1)
            }
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        error = nil
        Task {
            let failure = await session.changePassword(
                current: current, new: next, confirm: confirm, emailCode: emailCode
            )
            isSaving = false
            if let failure {
                error = failure
            } else {
                // 服务端方案 A：当前 token 仍有效，不踢用户回登录页。
                dismiss()
                onChanged?()
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
                .background(fieldSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                }
                .accessibilityIdentifier(identifier)
        }
    }
}

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
    @AppTypography private var typography
    let session: SessionStore
    @Environment(\.appLocale) private var locale
    @Environment(AppEnvironment.self) private var env
    /// 减弱动态效果时不播放 toast 过渡。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .settingsListStyle()
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnBackgroundTap()
        .navigationTitle(L10n.string("account.title", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("account-detail")
        // 只有三个一级页面保留标签栏，推入的页面全部隐藏（用户确认）。
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(typography.label(13))
                    .foregroundStyle(Palette.onInverse)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.s)
                    .background(Capsule().fill(Palette.inverseSurface))
                    .padding(.bottom, Space.xxl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("account-toast")
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: toast)
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
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsPasswordSheet) {
            PasswordChangeSheet(session: session) {
                // 成功提示：之前改完只无声关闭，用户不知道到底成没成。
                toast = L10n.string("account.password.changed", locale: locale)
            }
            .presentationDetents([.medium, .large])
        }
        .task {
            await session.refreshProfile()
        }
    }

    // MARK: 头像

    private var avatarSection: some View {
        Section {
            SettingsCard {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle")
                            .font(typography.body(17))
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(width: 28)
                        Text(L10n.string("account.avatar.change", locale: locale))
                            .font(typography.body(17))
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 8)
                        if isUploadingAvatar { ProgressView() }
                        AvatarView(url: profile.avatarURL, size: 56)
                    }
                    .frame(minHeight: 64)
                    .contentShape(Rectangle())
                }
                .disabled(isUploadingAvatar)
                .accessibilityIdentifier("account-avatar-change")
                .settingsCardRow()

                if profile.avatarURL != nil {
                    Divider().padding(.leading, 42)
                    Button(role: .destructive) {
                        Task { await removeAvatar() }
                    } label: {
                        Label(L10n.string("account.avatar.remove", locale: locale), systemImage: "trash")
                            .font(typography.body(17))
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("account-avatar-remove")
                    .buttonStyle(.pressable)
                    .settingsCardRow()
                }
                if let avatarError {
                    Text(avatarError)
                        .font(typography.body(13))
                        .foregroundStyle(Palette.failedForeground)
                }

            }
            .settingsCardContainer()
        } header: {
            SettingsSectionHeader(title: L10n.string("account.avatar.change", locale: locale))
        }
        .listRowBackground(Color.clear)
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
            SettingsCard {
                Button { showsNicknameSheet = true } label: {
                    actionableRow(
                        titleKey: "account.nickname.label", systemImage: "person",
                        value: profile.userName, identifier: "account-edit-nickname"
                    )
                }
                .buttonStyle(.pressable)
                .settingsCardRow()
                Divider().padding(.leading, 42)

                SettingsRow(
                    title: L10n.string("account.email.label", locale: locale),
                    systemImage: "envelope",
                    value: profile.email ?? L10n.string("me.account.email.empty", locale: locale)
                )
                .accessibilityIdentifier("account-email-readonly")
                .settingsCardRow()


            }
            .settingsCardContainer()
        } header: {
            SettingsSectionHeader(title: L10n.string("account.profile.heading", locale: locale))
        }
        .listRowBackground(Color.clear)
    }

    private var securitySection: some View {
        Section {
            SettingsCard {
                Button { showsPasswordSheet = true } label: {
                    actionableRow(
                        titleKey: "account.password.label", systemImage: "lock",
                        value: nil, identifier: "account-edit-password"
                    )
                }
                .buttonStyle(.pressable)
                .settingsCardRow()

            }
            .settingsCardContainer()
        } header: {
            SettingsSectionHeader(title: L10n.string("account.security.heading", locale: locale))
        }
        .listRowBackground(Color.clear)
    }

    private var signOutSection: some View {
        Section {
            SettingsCard {
                Button(role: .destructive) { showsSignOutConfirmation = true } label: {
                    Label(L10n.string("connection.signOut", locale: locale), systemImage: "rectangle.portrait.and.arrow.right")
                        .font(typography.body(17))
                        .frame(minHeight: 28)
                }
                .accessibilityIdentifier("account-signout")
                .buttonStyle(.pressable)
                .settingsCardRow()

            }
            .settingsCardContainer()
        }
        .listRowBackground(Color.clear)
    }

    private func actionableRow(titleKey: String, systemImage: String, value: String?, identifier: String) -> some View {
        HStack(spacing: 8) {
            SettingsRow(title: L10n.string(titleKey, locale: locale), systemImage: systemImage, value: value)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.inkTertiary)
                .accessibilityHidden(true)
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
    @AppTypography private var typography
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
            .font(typography.label(13))
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
    @AppTypography private var typography
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
            List {
                if let error {
                    Section {
                        SettingsCard {
                            InlineNotice(text: message(for: error), kind: .error)
                                .accessibilityIdentifier("nickname-error")
                                .settingsCardRow()

                        }
                        .settingsCardContainer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    SettingsCard {
                        TextField(L10n.string("account.nickname.label", locale: locale), text: $value)
                            .font(typography.body(17))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("nickname-input")
                            .settingsCardRow()

                    }
                    .settingsCardContainer()
                } header: {
                    SettingsSectionHeader(title: L10n.string("account.nickname.label", locale: locale))
                }
                .listRowBackground(Color.clear)
            }
            .settingsListStyle()
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnBackgroundTap()
            .navigationTitle(L10n.string("account.nickname.title", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string("common.cancel", locale: locale)) { dismiss() }
                        .font(typography.body(17))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.string("common.save", locale: locale))
                                .font(typography.heading(17))
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
    @AppTypography private var typography
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
            List {
                if let error {
                    Section {
                        SettingsCard {
                            InlineNotice(text: message(for: error), kind: .error)
                                .accessibilityIdentifier("password-error")
                                .settingsCardRow()

                        }
                        .settingsCardContainer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    SettingsCard {
                        secureField(labelKey: "account.password.current", text: $current, identifier: "password-current")
                            .settingsCardRow()
                        Divider()
                        secureField(labelKey: "account.password.new", text: $next, identifier: "password-new")
                            .settingsCardRow()
                        Divider()
                        secureField(labelKey: "account.password.confirm", text: $confirm, identifier: "password-confirm")
                            .settingsCardRow()

                    }
                    .settingsCardContainer()
                } header: {
                    SettingsSectionHeader(title: L10n.string("account.security.heading", locale: locale))
                }
                .listRowBackground(Color.clear)

                Section {
                    SettingsCard {
                        TextField(L10n.string("account.password.emailCode", locale: locale), text: $emailCode)
                            .font(typography.body(17))
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("password-email-code")
                            .settingsCardRow()
                        Divider()
                        Button {
                            Task { await sendCode() }
                        } label: {
                            HStack {
                                Text(resendCountdown > 0
                                     ? L10n.format("register.emailCode.resendIn", locale: locale, resendCountdown)
                                     : L10n.string("register.emailCode.send", locale: locale))
                                    .font(typography.body(17))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                if isSendingCode { ProgressView() }
                            }
                            .frame(minHeight: 44)
                        }
                        .disabled(!canSendCode)
                        .accessibilityIdentifier("password-email-code-send")
                        .buttonStyle(.pressable)
                        .settingsCardRow()
                        if codeSent {
                            Text(L10n.string("register.emailCode.sent", locale: locale))
                                .font(typography.body(13))
                                .foregroundStyle(Palette.runningForeground)
                        }

                    }
                    .settingsCardContainer()
                } header: {
                    SettingsSectionHeader(title: L10n.string("account.password.emailCode", locale: locale))
                }
                .listRowBackground(Color.clear)
            }
            .settingsListStyle()
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnBackgroundTap()
            .navigationTitle(L10n.string("account.password.title", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string("common.cancel", locale: locale)) { dismiss() }
                        .font(typography.body(17))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.string("common.save", locale: locale))
                                .font(typography.heading(17))
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
        SecureField(L10n.string(labelKey, locale: locale), text: text)
            .font(typography.body(17))
            .textContentType(labelKey == "account.password.current" ? .password : .newPassword)
            .frame(minHeight: 44)
            .accessibilityIdentifier(identifier)
    }
}

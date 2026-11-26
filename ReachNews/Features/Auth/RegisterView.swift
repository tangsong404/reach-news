import SwiftUI

// MARK: - 注册页
//
// 邀请码注册（POST /api/v1/register）。字段顺序按服务端要求：
// 昵称、邮箱、密码、确认密码、邀请码。
//
// 两个要点：
// 1. 注册成功直接进入 App：响应已带 token，不需要再调一次登录。
// 2. 失败提示优先用服务端返回的中文 message（实测服务端已本地化），
//    本地文案只作为 message 缺失时的兜底，避免两份文案漂移。

struct RegisterView: View {
    @Bindable var session: SessionStore
    @Environment(\.appLocale) private var locale
    @Environment(\.dismiss) private var dismiss

    @State private var nickname = ""
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var inviteCode = ""
    @State private var error: RegistrationError?
    @FocusState private var focused: Field?

    /// 人机验证配置；进入页面时取一次。
    @State private var captchaEnabled = false
    @State private var captchaSiteKey: String?
    /// hCaptcha 完成后的 token；enabled 为真时必须先有它才能提交。
    @State private var captchaToken: String?
    /// hCaptcha 初始化或校验失败；给出可见提示并允许重试。
    @State private var captchaFailed = false
    /// 渲染 hCaptcha 的页面 origin；必须是后台登记过的域名。
    @State private var captchaBaseURL: URL?
    /// 递增后重建 WebView，用于「重试」。
    @State private var captchaReloadToken = 0
    /// 人机验证弹窗是否打开。
    @State private var showsCaptchaSheet = false
    /// 用户填写的邮箱验证码。
    @State private var emailCode = ""
    /// SMTP 未配置时（mail_not_configured）不展示验证码行，也不提交该字段。
    @State private var emailVerificationAvailable = true
    /// 验证码发送失败信息。
    @State private var codeFailure: EmailCodeFailure?
    /// 发送成功的提示。
    @State private var codeSent = false
    @State private var isSendingCode = false
    @State private var resendCountdown = 0

    private enum Field {
        case nickname, email, password, passwordConfirm, inviteCode
    }

    private var canSubmit: Bool {
        let base = !nickname.trimmingCharacters(in: .whitespaces).isEmpty
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !passwordConfirm.isEmpty
            && !inviteCode.trimmingCharacters(in: .whitespaces).isEmpty
            && !session.isRegistering
        // 服务端启用 hCaptcha 时，必须先完成人机验证。
        let captchaReady = !captchaEnabled || (captchaToken?.isEmpty == false)
        return base && captchaReady
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                if let error {
                    InlineNotice(text: message(for: error), kind: .error)
                        .accessibilityIdentifier("register-error")
                }

                field(labelKey: "register.nickname") {
                    TextField("", text: $nickname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .nickname)
                        .accessibilityIdentifier("register-nickname")
                }

                field(labelKey: "register.email") {
                    TextField("", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .focused($focused, equals: .email)
                        .accessibilityIdentifier("register-email")
                }

                field(labelKey: "register.password") {
                    SecureField("", text: $password)
                        .focused($focused, equals: .password)
                        .accessibilityIdentifier("register-password")
                }

                field(labelKey: "register.passwordConfirm") {
                    SecureField("", text: $passwordConfirm)
                        .focused($focused, equals: .passwordConfirm)
                        .accessibilityIdentifier("register-password-confirm")
                }

                field(labelKey: "register.inviteCode") {
                    TextField("", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .inviteCode)
                        .accessibilityIdentifier("register-invite")
                }

                if emailVerificationAvailable {
                    emailCodeSection
                }
                if captchaEnabled {
                    captchaSection
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.l)
            .padding(.bottom, 44)
        }
        .background(Palette.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavTitle(text: L10n.string("register.title", locale: locale))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    submit()
                } label: {
                    if session.isRegistering {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(L10n.string("register.submit", locale: locale))
                            .font(TypeFace.heading(15))
                            .foregroundStyle(canSubmit ? Palette.ink : Palette.inkTertiary)
                    }
                }
                .disabled(!canSubmit)
                .accessibilityIdentifier("register-submit")
            }
        }
        .accessibilityIdentifier("register-view")
        .sheet(isPresented: $showsCaptchaSheet) {
            CaptchaSheet(
                siteKey: captchaSiteKey,
                baseURL: captchaBaseURL,
                onToken: { token in
                    captchaToken = token
                    captchaFailed = false
                    showsCaptchaSheet = false
                },
                onFailure: {
                    captchaToken = nil
                    captchaFailed = true
                }
            )
            // 验证组件需要足够高度：medium 只有半屏，减去导航栏与安全区
            // 之后实测会把组件挤得显示不全，改为大尺寸。
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.canvas)
        }
        .task {
            // 进入页面先取人机验证配置：没有它不知道要不要渲染组件。
            let config = await session.loadCaptchaConfig()
            captchaEnabled = config?.enabled ?? false
            captchaSiteKey = config?.siteKey
            // hCaptcha 会校验页面 origin；用服务端地址而不是 about:blank。
            captchaBaseURL = session.resolvedBaseURL
        }
    }

    // MARK: 邮箱验证码

    private var emailCodeSection: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(L10n.string("register.emailCode", locale: locale))
                .font(TypeFace.label(11))
                .tracking(1)
                .foregroundStyle(Palette.inkTertiary)

            HStack(spacing: Space.s) {
                TextField("", text: $emailCode)
                    .font(TypeFace.body(14))
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Palette.line, lineWidth: 1)
                    }
                    .accessibilityIdentifier("register-email-code")

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
                .accessibilityIdentifier("register-email-code-send")
            }

            if codeSent && codeFailure == nil {
                Text(L10n.string("register.emailCode.sent", locale: locale))
                    .font(TypeFace.footnote)
                    .foregroundStyle(Palette.runningForeground)
            }

            if let codeFailure {
                Text(codeFailureMessage(codeFailure))
                    .font(TypeFace.footnote)
                    .foregroundStyle(Palette.failedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("register-email-code-error")
            }
        }
    }

    /// 发送验证码只要求填了邮箱。
    ///
    /// 刻意**不**要求 captcha 已完成：hCaptcha 若因配置问题初始化失败，
    /// 用户就永远拿不到 token，按钮会被永久禁用——表现为「点了完全没反应」。
    /// 服务端需要 captcha 时会返回 captcha_required，那时再明确提示。
    private var canSendCode: Bool {
        guard !isSendingCode, resendCountdown == 0 else { return false }
        return !email.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func codeFailureMessage(_ failure: EmailCodeFailure) -> String {
        let server = failure.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !server.isEmpty { return server }
        if failure.isMailNotConfigured {
            return L10n.string("register.emailCode.mailNotConfigured", locale: locale)
        }
        let key = "register.emailCode.error." + failure.code
        let fallback = L10n.string(key, locale: locale)
        return fallback == key ? L10n.string("register.error.unknown", locale: locale) : fallback
    }

    private func sendCode() async {
        // 邮箱为空时直接反馈，别让按钮看起来「没反应」。
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            codeFailure = EmailCodeFailure.emptyEmail
            return
        }
        isSendingCode = true
        codeFailure = nil
        codeSent = false
        defer { isSendingCode = false }

        let failure = await session.requestEmailCode(email: email, captchaToken: captchaToken)
        if let failure {
            codeFailure = failure
            if failure.isMailNotConfigured {
                emailVerificationAvailable = false
            }
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

    // MARK: 人机验证

    /// 人机验证：表单里只放一行状态 + 入口，真正的验证在弹窗里做。
    ///
    /// 嵌在表单里时高度太小（hCaptcha 官方组件需要约 100pt 且常带阴影/说明），
    /// 实际能点到的区域很局促，所以改成点开弹窗给足空间。
    private var captchaSection: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(L10n.string("register.captcha", locale: locale))
                .font(TypeFace.label(11))
                .tracking(1)
                .foregroundStyle(Palette.inkTertiary)

            Button {
                showsCaptchaSheet = true
            } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: captchaToken == nil ? "shield" : "checkmark.shield.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(captchaToken == nil ? Palette.inkTertiary : Palette.runningForeground)

                    Text(captchaToken == nil
                         ? L10n.string("register.captcha.open", locale: locale)
                         : L10n.string("register.captcha.done", locale: locale))
                        .font(TypeFace.body(13.5))
                        .foregroundStyle(Palette.ink)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.inkTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(captchaToken == nil ? Palette.line : Palette.runningForeground.opacity(0.4), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("register-captcha-open")

            if captchaFailed {
                Text(L10n.string("register.captcha.failed", locale: locale))
                    .font(TypeFace.footnote)
                    .foregroundStyle(Palette.failedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("register-captcha-error")
            }
        }
    }

    /// 服务端 message 优先；没有时用 code 对应的本地兜底。
    private func message(for error: RegistrationError) -> String {
        let serverMessage = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !serverMessage.isEmpty { return serverMessage }
        let key = error.fallbackKey
        let fallback = L10n.string(key, locale: locale)
        // L10n 找不到键时会把键原样返回，此时退回通用文案。
        return fallback == key ? L10n.string("register.error.unknown", locale: locale) : fallback
    }

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        error = nil
        Task {
            let failure = await session.register(
                nickname: nickname,
                email: email,
                password: password,
                passwordConfirm: passwordConfirm,
                inviteCode: inviteCode,
                // 服务端启用时必传；未启用时传 nil，服务端会忽略。
                captchaToken: captchaEnabled ? captchaToken : nil,
                // 邮件服务未配置时不传该字段。
                emailCode: emailVerificationAvailable && !emailCode.isEmpty ? emailCode : nil
            )
            if let failure {
                error = failure
            } else {
                // 注册成功：会话已建立，直接回退让根视图切换到主界面。
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func field<Content: View>(
        labelKey: String,
        hintKey: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(L10n.string(labelKey, locale: locale))
                .font(TypeFace.label(11))
                .tracking(1)
                .foregroundStyle(Palette.inkTertiary)
            content()
                .font(TypeFace.body(14))
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                }
            if let hintKey {
                Text(L10n.string(hintKey, locale: locale))
                    .font(TypeFace.footnote)
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
    }
}

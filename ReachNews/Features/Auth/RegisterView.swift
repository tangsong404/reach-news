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
    @Environment(AppEnvironment.self) private var env

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
    /// 服务端告知邀请码必填后置真；此时平台也把该字段标为必填。
    @State private var inviteRequired = false
    @State private var isSendingCode = false
    @State private var resendCountdown = 0

    private enum Field {
        case nickname, email, password, passwordConfirm, inviteCode
    }

    /// 邀请码是否必填由服务端配置决定（「需要邀请码」模式 / 「开放注册」模式）。
    ///
    /// 客户端不写死：开放注册下不带码也能提交。当前若仍要求邀请码，
    /// 服务端会返回 invite_not_found，据此把该字段标为必填并提示。
    private var canSubmit: Bool {
        let base = !nickname.trimmingCharacters(in: .whitespaces).isEmpty
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !passwordConfirm.isEmpty
            && !session.isRegistering
        // 服务端启用 hCaptcha 时，必须先完成人机验证。
        let captchaReady = !captchaEnabled || (captchaToken?.isEmpty == false)
        // 已确认需要邀请码时才强制非空。
        let inviteReady = !inviteRequired || !inviteCode.trimmingCharacters(in: .whitespaces).isEmpty
        return base && captchaReady && inviteReady
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

                field(labelKey: inviteRequired ? "register.inviteCode.required" : "register.inviteCode") {
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
        .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
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
            // 2/3 高度：够放验证组件，又不像全屏那样空荡。
            .presentationDetents([.fraction(0.66)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
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
                    .background(fieldSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    /// 人机验证入口。
    ///
    /// 三种状态必须一眼可分：已验证（绿勾 + 灰字）、待验证、验证失败（红字 + 重试）。
    /// 已验证后**不再因为改动其他字段而要求重验**——token 只在服务端明确拒绝时作废。
    private var captchaSection: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(L10n.string("register.captcha", locale: locale))
                .font(TypeFace.label(11))
                .tracking(1)
                .foregroundStyle(Palette.inkTertiary)

            HStack(spacing: Space.s) {
                // 左半区：点它开始或重新验证。
                Button {
                    showsCaptchaSheet = true
                } label: {
                    HStack(spacing: Space.s) {
                        statusIcon
                        statusText
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("register-captcha-open")

                if captchaToken != nil {
                    // 已验证时给一个明确的「重新验证」入口（独立按钮，不嵌套）。
                    Button {
                        captchaToken = nil
                        captchaFailed = false
                        showsCaptchaSheet = true
                    } label: {
                        Text(L10n.string("register.captcha.redo", locale: locale))
                            .font(TypeFace.label(11))
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("register-captcha-redo")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.inkTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(rowBorder, lineWidth: 1)
            }

            if captchaFailed {
                Text(L10n.string("register.captcha.failed", locale: locale))
                    .font(TypeFace.footnote)
                    .foregroundStyle(Palette.failedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("register-captcha-error")
            } else if captchaToken == nil {
                Text(L10n.string("register.captcha.hint", locale: locale))
                    .font(TypeFace.footnote)
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if captchaToken != nil {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.runningForeground)
        } else if captchaFailed {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.failedForeground)
        } else {
            Image(systemName: "circle.dashed")
                .font(.system(size: 15))
                .foregroundStyle(Palette.inkTertiary)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if captchaToken != nil {
            Text(L10n.string("register.captcha.done", locale: locale))
                .font(TypeFace.body(13.5))
                .foregroundStyle(Palette.runningForeground)
        } else if captchaFailed {
            Text(L10n.string("register.captcha.open", locale: locale))
                .font(TypeFace.body(13.5))
                .foregroundStyle(Palette.failedForeground)
        } else {
            Text(L10n.string("register.captcha.open", locale: locale))
                .font(TypeFace.body(13.5))
                .foregroundStyle(Palette.ink)
        }
    }

    /// 输入框底色：随风格取卡片色，简洁风是浅灰、编辑风是暖白。
    private var fieldSurface: Color {
        Theme.surface(for: env.appearance.style, mode: env.appearance.mode)
    }

    private var rowBackground: Color {
        if captchaToken != nil { return Palette.runningBackground }
        if captchaFailed { return Palette.failedBackground }
        return fieldSurface
    }

    private var rowBorder: Color {
        if captchaToken != nil { return Palette.runningForeground.opacity(0.35) }
        if captchaFailed { return Palette.failedForeground.opacity(0.35) }
        return Palette.line
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
                inviteCode: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines),
                // 服务端启用时必传；未启用时传 nil，服务端会忽略。
                captchaToken: captchaEnabled ? captchaToken : nil,
                // 邮件服务未配置时不传该字段。
                emailCode: emailVerificationAvailable && !emailCode.isEmpty ? emailCode : nil
            )
            if let failure {
                error = failure
                // 邀请码被拒：说明当前服务端仍是「需要邀请码」模式，
                // 记下来让字段变必填，避免用户反复尝试才明白。
                if failure.code == "invite_not_found" || failure.code == "invite_required" {
                    inviteRequired = true
                }
                // captcha token 一次性有效：校验失败或被用掉后必须重新验证。
                // 主动作废并提示，比让用户带着旧 token 反复提交更好。
                if failure.code == "captcha_failed" || failure.code == "captcha_required" {
                    captchaToken = nil
                    captchaFailed = true
                }
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
                .background(fieldSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

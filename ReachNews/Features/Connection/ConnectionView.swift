import SwiftUI

// MARK: - 登录页
//
// 后端以账号密码换 7 天会话凭证（POST /api/v1/login）。
// 旧的长期 Bearer Token 已全部失效，因此这里不再有 Token 输入。

struct ConnectionView: View {
    @Bindable var session: SessionStore
    var isReplacingCredential: Bool = false

    @Environment(\.appLocale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @FocusState private var focusedField: Field?
    /// 是否正在看注册页；用导航推入，返回即回到登录。
    @State private var showsRegister = false

    private enum Field {
        case username
        case password
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header

                if case .failed(let error) = session.state {
                    InlineNotice(
                        text: L10n.string(error.messageKey, locale: locale),
                        detail: error.isOffline
                            ? L10n.string("error.offline.detail", locale: locale)
                            : (error.isTooManyAttempts
                                ? L10n.string("login.throttled.detail", locale: locale)
                                : error.detailText),
                        kind: .error
                    )
                    .accessibilityIdentifier("connection-error")
                }

                if session.isThrottled {
                    InlineNotice(
                        text: L10n.string("login.throttled.title", locale: locale),
                        detail: L10n.format("login.throttled.wait", locale: locale, session.throttleRemainingSeconds),
                        kind: .warning
                    )
                    .accessibilityIdentifier("connection-throttled")
                }

                field(labelKey: "login.username.heading") {
                    TextField(
                        L10n.string("login.username.placeholder", locale: locale),
                        text: $session.username
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .accessibilityIdentifier("login-username")
                }

                field(labelKey: "login.password.heading") {
                    SecureField(
                        L10n.string("login.password.placeholder", locale: locale),
                        text: $session.password
                    )
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { submit() }
                    .accessibilityIdentifier("login-password")
                }

                PrimaryButton(
                    title: session.isSigningIn
                        ? L10n.string("login.signingIn", locale: locale)
                        : L10n.string("login.submit", locale: locale)
                ) {
                    submit()
                }
                .disabled(!session.canSubmit)
                .opacity(session.canSubmit ? 1 : 0.5)
                .accessibilityIdentifier("connection-submit")

                // 注册入口：只在首次登录时出现，更换凭证时不需要再注册。
                if !isReplacingCredential {
                    Button {
                        showsRegister = true
                    } label: {
                        Text(L10n.string("login.goRegister", locale: locale))
                            .font(TypeFace.body(13))
                            .foregroundStyle(Palette.inkSecondary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("login-go-register")
                }
            }
            .padding(.horizontal, Space.xl)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, minHeight: 520, alignment: .center)
            .padding(.vertical, Space.xl)
        }
        .background(Theme.canvas(for: env.appearance.style, mode: env.appearance.mode))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isReplacingCredential {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text(L10n.string("common.cancel", locale: locale))
                            .font(TypeFace.body(14))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showsRegister) {
            // 注册页复用同一个 session：注册成功即建立会话，根视图会自动切到主界面。
            RegisterView(session: session)
        }
        .accessibilityIdentifier("connection-view")
        .task {
            // 每次进入登录页都从干净的密码框开始。
            session.password = ""
        }
    }

    private func submit() {
        guard session.canSubmit else { return }
        focusedField = nil
        Task {
            let ok = await session.signIn()
            if ok && isReplacingCredential {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func field<Content: View>(labelKey: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(L10n.string(labelKey, locale: locale))
                .font(TypeFace.label(11))
                .tracking(1)
                .foregroundStyle(Palette.inkTertiary)
            content()
                .font(TypeFace.body(14))
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(Theme.surface(for: env.appearance.style, mode: env.appearance.mode), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                }
        }
    }

    /// 品牌区：图形 + 字标。
    /// 只保留品牌本身，不再有 "Connect to Reach News" 这类解释性副标题。
    private var header: some View {
        HStack(spacing: Space.s) {
            BrandMark(size: 30)
            Text("Reach News")
                .font(TypeFace.heading(19))
                .foregroundStyle(Palette.ink)
        }
        .accessibilityIdentifier("connection-brand")
    }
}

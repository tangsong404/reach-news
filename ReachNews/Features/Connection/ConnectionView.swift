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
    @FocusState private var focusedField: Field?

    private enum Field {
        case baseURL
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

                field(labelKey: "connection.baseURL.heading") {
                    TextField(
                        L10n.string("connection.baseURL.placeholder", locale: locale),
                        text: $session.baseURLString
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focusedField, equals: .baseURL)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .username }
                    .accessibilityIdentifier("connection-baseurl")
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
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.xxl)
            .padding(.bottom, 44)
        }
        .background(Palette.canvas)
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
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                BrandMark(assetName: "LogoMarkInk", size: 30)
                Text("Reach News")
                    .font(TypeFace.heading(19))
                    .foregroundStyle(Palette.ink)
            }
            Text(L10n.string("connection.title", locale: locale))
                .font(TypeFace.display(28))
                .foregroundStyle(Palette.ink)
            Text(L10n.string("connection.subtitle", locale: locale))
                .font(TypeFace.body(13.5))
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

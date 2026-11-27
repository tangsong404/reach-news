import SwiftUI
import WebKit

// MARK: - hCaptcha 组件
//
// 服务端决定是否启用（`GET /api/v1/auth/captcha` 返回 enabled + siteKey）。
// 启用时用 WKWebView 加载 hCaptcha 官方 widget，用户完成后通过
// postMessage 把 token 传回原生层。
//
// 这里不用第三方 SDK：hCaptcha 官方推荐 web 集成，WKWebView 足够，
// 也避免为一次验证引入一个依赖。

struct HCaptchaView: UIViewRepresentable {
    let siteKey: String?
    /// 页面 origin 必须落在 hCaptcha 后台登记的域名上，否则会返回
    /// `request not allowed`。因此不能用 about:blank 加载。
    let baseURL: URL?
    let onToken: (String) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onToken: onToken, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "captcha")
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator

        if let siteKey, !siteKey.isEmpty {
            webView.loadHTMLString(Self.html(siteKey: siteKey), baseURL: baseURL)
        } else {
            onFailure()
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // siteKey 到得比视图晚时补载一次。
        guard let siteKey, !siteKey.isEmpty,
              let current = webView.url, current.absoluteString == "about:blank" else { return }
        if webView.isLoading { return }
        let html = Self.html(siteKey: siteKey)
        if context.coordinator.loadedSiteKey != siteKey || context.coordinator.loadedBaseURL != baseURL?.absoluteString {
            context.coordinator.loadedSiteKey = siteKey
            context.coordinator.loadedBaseURL = baseURL?.absoluteString
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "captcha")
    }

    /// 页面只做一件事：渲染 widget，并把 token/过期/失败回传。
    /// 用深色底适配不了的地方交给系统，所以不写死背景色。
    private static func html(siteKey: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <script src="https://js.hcaptcha.com/1/api.js" async defer></script>
        <style>
          html,body{margin:0;padding:0;height:100%;background:transparent;overflow:hidden;}
          /* 垂直居中，而不是贴顶：组件比容器矮时居中，
             比容器高时从中间溢出而不是把顶部切掉。 */
          .wrap{display:flex;justify-content:center;align-items:center;min-height:100%;padding:8px 0;box-sizing:border-box;}
          .h-captcha{transform-origin:center center;}
        </style>
        </head>
        <body>
        <div class="wrap">
          <div class="h-captcha"
               data-sitekey="\(siteKey)"
               data-callback="onSolved"
               data-expired-callback="onExpired"
               data-error-callback="onError"></div>
        </div>
        <script>
          // 容器装不下时按比例缩放，而不是把顶部裁掉。
          // hCaptcha 渲染完成后才知道真实尺寸，因此轮询几次。
          (function() {
            var tries = 0;
            function fit() {
              var el = document.querySelector('.h-captcha');
              if (!el) return;
              var ch = el.offsetHeight, cw = el.offsetWidth;
              if (!ch || !cw) return;
              var availH = window.innerHeight - 16;
              var availW = window.innerWidth - 16;
              var scale = Math.min(1, availH / ch, availW / cw);
              if (scale < 1) {
                el.style.transform = 'scale(' + scale + ')';
              }
            }
            var timer = setInterval(function() {
              fit();
              if (++tries > 20) clearInterval(timer);
            }, 300);
            window.addEventListener('resize', fit);
          })();
        </script>
        <script>
          function post(payload) {
            try { window.webkit.messageHandlers.captcha.postMessage(payload); } catch (e) {}
          }
          function onSolved(token) { post({ kind: "token", token: token }); }
          function onExpired()     { post({ kind: "expired" }); }
          function onError()       { post({ kind: "error" }); }
        </script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let onToken: (String) -> Void
        private let onFailure: () -> Void

        var loadedSiteKey: String?
        var loadedBaseURL: String?

        init(onToken: @escaping (String) -> Void, onFailure: @escaping () -> Void) {
            self.onToken = onToken
            self.onFailure = onFailure
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let payload = message.body as? [String: Any],
                  let kind = payload["kind"] as? String else { return }
            switch kind {
            case "token":
                if let token = payload["token"] as? String, !token.isEmpty {
                    onToken(token)
                } else {
                    onFailure()
                }
            case "expired", "error":
                onFailure()
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // hCaptcha 遇到非法 siteKey 时不会抛 JS error，只是把容器留空。
            // 因此加载完成后主动检查容器里有没有渲染出东西；没有就按失败处理，
            // 否则用户只会看到一个空白区域，完全不知道发生了什么。
            let script = """
            (function() {
              var el = document.querySelector('.h-captcha');
              if (!el) { return 'missing'; }
              if (el.querySelector('iframe')) { return 'ok'; }
              return 'empty';
            })();
            """
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self else { return }
                if let state = result as? String, state == "ok" {
                    self.sawWidget = true
                    return
                }
                // 给 hCaptcha 一点渲染时间再判定一次，避免误报。
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self, !self.sawWidget else { return }
                    webView.evaluateJavaScript(script) { result, _ in
                        if let state = result as? String, state == "ok" {
                            self.sawWidget = true
                        } else {
                            self.onFailure()
                        }
                    }
                }
            }
        }

        var sawWidget = false

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onFailure()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onFailure()
        }
    }
}

// MARK: - 验证弹窗
//
// 表单里只放一行入口，点开后在弹窗里给足空间完成验证。
// hCaptcha 官方组件在窄小的内嵌区域里几乎点不准，弹窗可用「中号」高度
// 让组件居中显示。

struct CaptchaSheet: View {
    @AppTypography private var typography

    let siteKey: String?
    let baseURL: URL?
    let onToken: (String) -> Void
    let onFailure: () -> Void

    @Environment(\.appLocale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false
    @State private var reloadToken = 0

    var body: some View {
        // 组件本身会超过容器：不要再把它按在顶部——
        // 那样上半部分被裁掉、下方却留着空白。这里让它在可用区域里居中，
        // 并用 GeometryReader 把高度交给组件，避免固定值猜错。
        GeometryReader { proxy in
            NavigationStack {
                Group {
                    if failed {
                        failureView
                    } else {
                        HCaptchaView(
                            siteKey: siteKey,
                            baseURL: baseURL,
                            onToken: { token in
                                failed = false
                                onToken(token)
                            },
                            onFailure: {
                                failed = true
                                onFailure()
                            }
                        )
                        .id(reloadToken)
                        .frame(width: proxy.size.width - Space.l * 2,
                               height: proxy.size.height)
                        .accessibilityIdentifier("captcha-sheet-webview")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.canvas)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        NavTitle(text: L10n.string("register.captcha", locale: locale))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.string("common.cancel", locale: locale)) { dismiss() }
                            .font(typography.body(14))
                    }
                }
            }
        }
    }

    private var failureView: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Palette.failedForeground)
            Text(L10n.string("register.captcha.failed", locale: locale))
                .font(typography.body(13))
                .foregroundStyle(Palette.failedForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                failed = false
                reloadToken += 1
            } label: {
                Text(L10n.string("common.retry", locale: locale))
                    .font(typography.label(12.5))
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("captcha-sheet-retry")
        }
        .padding(.horizontal, Space.xl)
    }
}

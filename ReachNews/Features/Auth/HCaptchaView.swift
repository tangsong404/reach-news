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
            webView.loadHTMLString(Self.html(siteKey: siteKey), baseURL: nil)
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
        if context.coordinator.loadedSiteKey != siteKey {
            context.coordinator.loadedSiteKey = siteKey
            webView.loadHTMLString(html, baseURL: nil)
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
          html,body{margin:0;padding:0;background:transparent;}
          .wrap{display:flex;justify-content:center;align-items:center;height:100%;}
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

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onFailure()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onFailure()
        }
    }
}

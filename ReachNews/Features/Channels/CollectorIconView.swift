import SwiftUI
import WebKit

/// Public SVG resource: fetched without Bearer, then rendered as an isolated image.
/// The image document CSP forbids scripts, network subresources and navigation.
struct CollectorIconView: View {
    let iconURLPath: String?
    let origin: URL
    @State private var svgData: Data?

    private var resourceURL: URL? {
        CollectorIconValidation.resourceURL(path: iconURLPath, origin: origin)
    }

    var body: some View {
        ZStack {
            if svgData == nil {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 17)).foregroundStyle(Palette.inkSecondary)
            }
            if let svgData {
                IsolatedSVGImage(data: svgData) { self.svgData = nil }
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
        .task(id: resourceURL) {
            svgData = nil
            guard let resourceURL else { return }
            do {
                var request = URLRequest(url: resourceURL, cachePolicy: .reloadRevalidatingCacheData)
                request.timeoutInterval = 15
                // No credentials/session cookies: public display asset only.
                let configuration = URLSessionConfiguration.ephemeral
                configuration.httpCookieStorage = nil
                let session = URLSession(configuration: configuration, delegate: NoIconRedirects(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                let (data, response) = try await session.data(for: request)
                guard !Task.isCancelled, let http = response as? HTTPURLResponse,
                      http.statusCode == 200, response.mimeType == "image/svg+xml",
                      CollectorIconValidation.isValidSVG(data) else { return }
                svgData = data
            } catch { /* Nil/error/404 remains the system-symbol fallback. */ }
        }
    }
}

/// Validate public display resources before WebKit ever sees them.
enum CollectorIconValidation {
    static func resourceURL(path: String?, origin: URL) -> URL? {
        guard let path, var components = URLComponents(url: origin, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.user == nil, components.password == nil else { return nil }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        guard let base = components.url,
              let url = URL(string: path, relativeTo: base)?.absoluteURL,
              url.scheme == base.scheme, url.host == base.host, url.port == base.port,
              url.user == nil, url.password == nil,
              url.path.hasPrefix("/api/v1/collector-skills/"), url.path.hasSuffix("/icon.svg") else { return nil }
        return url
    }

    static func isValidSVG(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= 65_536,
              let source = String(data: data, encoding: .utf8),
              !source.uppercased().contains("<!DOCTYPE"), !source.uppercased().contains("<!ENTITY") else { return false }
        let delegate = StaticSVGDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        return parser.parse() && delegate.rootIsSVG && delegate.isStatic
    }

    private final class StaticSVGDelegate: NSObject, XMLParserDelegate {
        var rootIsSVG = false
        var isStatic = true
        var depth = 0
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String]) {
            if depth == 0 { rootIsSVG = elementName == "svg" }
            depth += 1
            if ["script", "style", "foreignObject", "image", "use", "iframe"].contains(elementName) { isStatic = false }
            for (name, value) in attributes {
                if name.lowercased().hasPrefix("on") || name == "href" || name == "xlink:href" || name == "style" {
                    isStatic = false
                }
                if value.lowercased().contains("url(") && !value.contains("url(#") { isStatic = false }
            }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { depth -= 1 }
    }
}

/// Never follow an icon redirect to a different origin (or any other resource).
private final class NoIconRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private struct IsolatedSVGImage: UIViewRepresentable {
    let data: Data
    var onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFailure: onFailure) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.lastData != data else { return }
        context.coordinator.lastData = data
        let image = "data:image/svg+xml;base64," + data.base64EncodedString()
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'">
        <style>html,body{margin:0;background:transparent;width:100%;height:100%;overflow:hidden}img{width:100%;height:100%;object-fit:contain}</style></head><body><img alt="" src="\(image)"></body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastData: Data?
        let onFailure: () -> Void
        init(onFailure: @escaping () -> Void) { self.onFailure = onFailure }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let allowed = navigationAction.request.url?.absoluteString == "about:blank"
                && navigationAction.navigationType == .other
            decisionHandler(allowed ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFailure() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onFailure() }
    }
}

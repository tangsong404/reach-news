#if DEBUG
import Foundation

/// Explicit, debug-only launch fixture. Uses the production stores and navigation,
/// but replaces all persistence and HTTP transport; never reads Keychain or sends a request.
@MainActor
enum UITestLaunchFixture {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing") }

    static func makeEnvironment() -> AppEnvironment {
        let credentials = UITestCredentials()
        let preferences = UITestPreferences()
        let client = APIClient(
            baseURL: URL(string: "https://ui-fixture.invalid")!,
            transport: UITestTransport(),
            credentials: credentials
        )
        return AppEnvironment(
            client: client,
            credentials: credentials,
            preferences: preferences,
            savedStorage: UITestSavedBriefs(),
            channelColorStorage: UITestChannelColors()
        )
    }
}

private final class UITestCredentials: CredentialProviding {
    private var value: String? = "non-secret-ui-fixture-token"
    private var expiry = Date.distantFuture
    func token() -> String? { value }
    func store(token: String) throws { value = token }
    func clearToken() { value = nil }
    func expiresAt() -> Date? { expiry }
    func store(expiresAt: Date) { expiry = expiresAt }
}

private final class UITestPreferences: PreferencesStoring {
    var baseURLString = "https://ui-fixture.invalid"
    var languagePreference = "zh-Hans"
    var lastSeenAt: Date?
    var lastUserName = "UI Fixture"
    var readerStyle = ProcessInfo.processInfo.environment["UI_TEST_STYLE"] ?? "editorial"
    var themeTint = "azure"
    var appearanceMode = ProcessInfo.processInfo.environment["UI_TEST_APPEARANCE"] ?? "light"
}

private final class UITestSavedBriefs: SavedBriefsStoring {
    private(set) var savedBriefIDs = Set<String>()
    func toggle(_ briefID: String) -> Set<String> {
        if !savedBriefIDs.insert(briefID).inserted { savedBriefIDs.remove(briefID) }
        return savedBriefIDs
    }
}

private final class UITestChannelColors: ChannelColorStoring {
    private var values: [String: Int] = [:]
    func setColorIndex(_ index: Int, for channelID: String) { values[channelID] = index }
    func colorIndex(for channelID: String) -> Int? { values[channelID] }
    func remove(_ channelID: String) { values.removeValue(forKey: channelID) }
}

/// Fail closed for an unhandled endpoint: this class has no network fallback.
private final class UITestTransport: HTTPTransporting, @unchecked Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let payload: [String: Any]
        switch path {
        case "/health":
            payload = ["ok": true]
        case "/api/v1/me":
            payload = [
                "id": "ui-fixture-user", "name": "UI Fixture", "tier": "admin",
                "email": "fixture@example.invalid", "channelCount": 1,
                "capabilities": ["tier": "admin", "ask": true, "briefImages": false]
            ]
        case "/api/v1/settings":
            payload = ["timeZone": "Asia/Shanghai"]
        case "/api/v1/channels":
            let discover = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.contains { $0.name == "discover" && $0.value == "1" } ?? false
            payload = ["items": discover ? [] : [Self.channel], "nextCursor": NSNull()]
        case "/api/v1/briefs":
            payload = ["items": [Self.brief], "nextCursor": NSNull()]
        case "/api/v1/briefs/ui-fixture-brief":
            payload = Self.brief
        case "/api/v1/cursor":
            payload = ["briefs": [], "channels": []]
        case "/api/v1/connectors", "/api/v1/channels/ui-fixture-channel/runs":
            payload = ["items": [], "nextCursor": NSNull()]
        case "/api/v1/briefs/ui-fixture-brief/ask":
            payload = request.httpMethod == "POST"
                ? ["answer": "这是离线 UI 测试的固定回答。", "citedItemIds": [], "deterministic": true]
                : ["items": [], "nextCursor": NSNull()]
        default:
            throw URLError(.unsupportedURL)
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }

    private static let channel: [String: Any] = [
        "id": "ui-fixture-channel", "name": "离线测试频道", "prompt": "固定测试数据",
        "enabled": true, "owner": "creator", "kind": "channel", "schedule": [:],
        "createdAt": "2026-11-20T00:00:00.000Z"
    ]

    private static let brief: [String: Any] = [
        "id": "ui-fixture-brief", "channelId": "ui-fixture-channel",
        "channelName": "离线测试频道", "title": "离线测试日报：市场与技术动态",
        "summary": "固定测试数据，用于验证文章点击、布局与直接提问。",
        "createdAt": "2026-11-20T00:00:00.000Z", "sections": [],
        "body": ["paragraphs": [["segments": [["type": "text", "text": """
        ## 央行下调存款准备金率与市场影响

        这是完全离线的测试正文。它通过真实页面呈现，验证正文排版、小标题铃铛与底部提问框。

        更多信息见 [来源](https://example.invalid/article)。

        ## 技术进展与后续观察

        继续阅读本期内容，然后通过底部输入框发起提问。界面测试不会连接真实服务器。
        """]]]]]
    ]
}
#endif

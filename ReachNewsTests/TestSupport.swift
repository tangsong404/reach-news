import Foundation
@testable import ReachNews

// MARK: - 固定响应的传输替身
//
// 只在测试里使用；UI 测试与单元测试都不打真实网络。

final class StubTransport: HTTPTransporting, @unchecked Sendable {
    struct Recorded {
        let url: URL
        let method: String
        let authorization: String?
        let body: Data?
    }

    /// 记录并发请求：`ChannelStore.load()` 用 `async let` 同时发两个请求，
    /// 无锁的数组 append 会丢写，因此这里用锁保护。
    private let lock = NSLock()
    private var storage: [Recorded] = []

    var recorded: [Recorded] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    private let handler: (URLRequest) throws -> (Int, Data)

    init(handler: @escaping (URLRequest) throws -> (Int, Data)) {
        self.handler = handler
    }

    /// 固定 JSON + 200。
    convenience init(json: String, status: Int = 200) {
        self.init { _ in (status, Data(json.utf8)) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let entry = Recorded(
            url: request.url ?? URL(fileURLWithPath: "/"),
            method: request.httpMethod ?? "GET",
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            body: request.httpBody
        )
        lock.lock()
        storage.append(entry)
        lock.unlock()
        let (status, data) = try handler(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(fileURLWithPath: "/"),
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (data, response)
    }
}

// MARK: - 凭证与偏好替身

final class InMemoryCredentials: CredentialProviding {
    private(set) var storedToken: String?
    private(set) var storedExpiry: Date?

    init(token: String? = nil, expiresAt: Date? = nil) {
        self.storedToken = token
        self.storedExpiry = expiresAt
    }

    func token() -> String? { storedToken }

    func store(token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KeychainError.emptyToken }
        storedToken = trimmed
    }

    func clearToken() {
        storedToken = nil
        storedExpiry = nil
    }

    func expiresAt() -> Date? { storedExpiry }

    func store(expiresAt: Date) { storedExpiry = expiresAt }
}

final class InMemoryPreferences: PreferencesStoring {
    var baseURLString: String = BaseURLDefaults.host
    var languagePreference: String = LanguagePreference.system.rawValue
    var lastSeenAt: Date?
    var lastUserName: String = ""
}

final class InMemoryChannelColors: ChannelColorStoring {
    private(set) var assignments: [String: Int] = [:]

    func setColorIndex(_ index: Int, for channelID: String) { assignments[channelID] = index }
    func colorIndex(for channelID: String) -> Int? { assignments[channelID] }
    func remove(_ channelID: String) { assignments.removeValue(forKey: channelID) }
}

final class InMemorySavedBriefs: SavedBriefsStoring {
    private(set) var savedBriefIDs: Set<String> = []

    func toggle(_ briefID: String) -> Set<String> {
        if savedBriefIDs.contains(briefID) {
            savedBriefIDs.remove(briefID)
        } else {
            savedBriefIDs.insert(briefID)
        }
        return savedBriefIDs
    }
}

// MARK: - Fixture 读取
//
// 测试样本就是仓库里的 Fixtures/*.json，与文档中的真实形状保持同一份。

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle(for: StubTransport.self).url(forResource: name, withExtension: "json") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    static func string(_ name: String) throws -> String {
        String(decoding: try data(name), as: UTF8.self)
    }

    enum FixtureError: Error {
        case missing(String)
    }
}

// MARK: - 客户端装配

enum TestClient {
    static func make(
        transport: StubTransport,
        token: String? = "test-token",
        baseURL: URL = BaseURLDefaults.url
    ) -> APIClient {
        APIClient(
            baseURL: baseURL,
            transport: transport,
            credentials: InMemoryCredentials(token: token)
        )
    }
}

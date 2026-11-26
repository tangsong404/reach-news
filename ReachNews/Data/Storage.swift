import Foundation
import Security

// MARK: - 凭证存取协议

protocol CredentialProviding: AnyObject {
    func token() -> String?
    func store(token: String) throws
    func clearToken()
    /// 会话的过期时刻；与 token 分开存，便于过期判断。
    func expiresAt() -> Date?
    func store(expiresAt: Date)
}

// MARK: - Keychain
//
// Token 只存 Keychain，不进 UserDefaults，不写日志。
// 失败时抛出明确错误，不静默吞掉。

enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case emptyToken
}

final class KeychainCredentials: CredentialProviding {
    private let service: String
    private let account: String
    private let expiryAccount: String
    private let defaults: UserDefaults

    init(
        service: String = "com.tangsong404.reachnews",
        account: String = "session-token",
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.account = account
        self.expiryAccount = account + ".expiresAt"
        self.defaults = defaults
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func token() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func store(token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KeychainError.emptyToken }
        let data = Data(trimmed.utf8)

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = baseQuery
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    func clearToken() {
        SecItemDelete(baseQuery as CFDictionary)
        defaults.removeObject(forKey: "keychain." + expiryAccount)
    }

    /// 过期时刻不是敏感信息，放 UserDefaults，避免多一次 Keychain 读取。
    func expiresAt() -> Date? {
        let interval = defaults.double(forKey: "keychain." + expiryAccount)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    func store(expiresAt: Date) {
        defaults.set(expiresAt.timeIntervalSince1970, forKey: "keychain." + expiryAccount)
    }
}

/// 只用于写入前的临时验证：不触碰 Keychain。
final class TemporaryCredentials: CredentialProviding {
    private let value: String

    init(token: String) {
        self.value = token
    }

    func token() -> String? { value }
    func store(token: String) throws {}
    func clearToken() {}
    func expiresAt() -> Date? { nil }
    func store(expiresAt: Date) {}
}

// MARK: - 应用偏好
//
// 只存用户偏好与一个轮询基线时间戳（ADR 0003）。
// 不缓存任何日报、素材或运行内容。

protocol PreferencesStoring: AnyObject {
    var baseURLString: String { get set }
    var languagePreference: String { get set }
    var lastSeenAt: Date? { get set }
    /// 上次登录的展示名。冷启动从 Keychain 恢复会话时 `AuthSession.userName` 为空，
    /// 「我的」页头部靠它显示用户名；它不是凭证，改它不影响鉴权。
    var lastUserName: String { get set }
    /// 界面风格（`ReaderStyle.rawValue`）。
    var readerStyle: String { get set }
    /// 主题色（`ThemeTint.rawValue`）。
    var themeTint: String { get set }
    var appearanceMode: String { get set }
}

final class UserDefaultsPreferences: PreferencesStoring {
    private enum Keys {
        static let baseURL = "preferences.baseURL"
        static let language = "preferences.language"
        // 轮询基线单独命名、单独存储，与任何内容缓存无关。
        static let lastSeenAt = "polling.baseline.lastSeenAt"
        static let lastUserName = "preferences.lastUserName"
        static let readerStyle = "preferences.readerStyle"
        static let themeTint = "preferences.themeTint"
        static let appearanceMode = "preferences.appearanceMode"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 服务地址固定，不再从偏好读取用户输入。
    /// 仍然可写：写入被忽略，避免调用方拿到旧值造成不一致。
    var baseURLString: String {
        get { BaseURLDefaults.host }
        set { defaults.removeObject(forKey: Keys.baseURL) }
    }

    var languagePreference: String {
        get { defaults.string(forKey: Keys.language) ?? LanguagePreference.system.rawValue }
        set { defaults.set(newValue, forKey: Keys.language) }
    }

    var lastSeenAt: Date? {
        get {
            let interval = defaults.double(forKey: Keys.lastSeenAt)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: Keys.lastSeenAt)
            } else {
                defaults.removeObject(forKey: Keys.lastSeenAt)
            }
        }
    }

    var lastUserName: String {
        get { defaults.string(forKey: Keys.lastUserName) ?? "" }
        set { defaults.set(newValue, forKey: Keys.lastUserName) }
    }

    var readerStyle: String {
        get { defaults.string(forKey: Keys.readerStyle) ?? "" }
        set { defaults.set(newValue, forKey: Keys.readerStyle) }
    }

    var themeTint: String {
        get { defaults.string(forKey: Keys.themeTint) ?? "" }
        set { defaults.set(newValue, forKey: Keys.themeTint) }
    }

    var appearanceMode: String {
        get { defaults.string(forKey: Keys.appearanceMode) ?? "" }
        set { defaults.set(newValue, forKey: Keys.appearanceMode) }
    }
}

// MARK: - 语言偏好

enum LanguagePreference: String, CaseIterable, Identifiable {
    case system
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .system: return "preferences.language.system"
        case .chinese: return "preferences.language.chinese"
        case .english: return "preferences.language.english"
        }
    }

    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .chinese: return Locale(identifier: "zh-Hans")
        case .english: return Locale(identifier: "en")
        }
    }
}

// MARK: - 频道颜色（仅本机）
//
// 服务端没有颜色字段，颜色属于个人偏好，只存在本机。
// 未设置时按 id 稳定回退到调色板里的一个颜色。

protocol ChannelColorStoring: AnyObject {
    var assignments: [String: Int] { get }
    func setColorIndex(_ index: Int, for channelID: String)
    func colorIndex(for channelID: String) -> Int?
    func remove(_ channelID: String)
}

final class UserDefaultsChannelColors: ChannelColorStoring {
    private let key = "channels.colors"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateLegacyShapeIfNeeded()
    }

    var assignments: [String: Int] {
        (defaults.dictionary(forKey: key) as? [String: Any])?
            .compactMapValues { ($0 as? NSNumber)?.intValue } ?? [:]
    }

    func setColorIndex(_ index: Int, for channelID: String) {
        var current = assignments
        current[channelID] = index
        defaults.set(current, forKey: key)
    }

    func colorIndex(for channelID: String) -> Int? {
        assignments[channelID]
    }

    func remove(_ channelID: String) {
        var current = assignments
        current.removeValue(forKey: channelID)
        defaults.set(current, forKey: key)
    }

    /// 旧版本若存过其它形状，静默丢弃即可，不影响使用。
    private func migrateLegacyShapeIfNeeded() {
        if let raw = defaults.object(forKey: key), !(raw is [String: Any]) {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - 本机收藏
//
// 收藏仅存本机，不同步服务端，不改变服务端任何状态（GLOSSARY「收藏」）。

protocol SavedBriefsStoring: AnyObject {
    var savedBriefIDs: Set<String> { get }
    func toggle(_ briefID: String) -> Set<String>
}

final class UserDefaultsSavedBriefs: SavedBriefsStoring {
    private let key = "saved.briefs"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var savedBriefIDs: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    @discardableResult
    func toggle(_ briefID: String) -> Set<String> {
        var ids = savedBriefIDs
        if ids.contains(briefID) {
            ids.remove(briefID)
        } else {
            ids.insert(briefID)
        }
        defaults.set(Array(ids), forKey: key)
        return ids
    }
}

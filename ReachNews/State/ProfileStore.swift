import Foundation
import Observation

// MARK: - 账号资料
//
// 「我的」页头部的数据来源。全部来自服务端真实字段，不再有本地占位常量：
// - 用户名与邮箱来自 `GET /api/v1/me`；
// - 套餐原样显示服务端 `tier`（实测有 free / ultra / admin，没有 pro）；
// - 头像按 `avatarUrl` 加载，没有时显示缺省图形。
//
// 不发起请求，也不持有凭证：拉取由 `SessionStore.refreshProfile()` 负责。

@MainActor
@Observable
final class ProfileStore {
    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private let preferences: PreferencesStoring

    init(session: SessionStore, preferences: PreferencesStoring) {
        self.session = session
        self.preferences = preferences
    }

    /// 第一行：服务端用户名。
    ///
    /// 冷启动的会话本身不带用户名，所以先等 `/me`；在那之前用上次登录记下的
    /// 展示名兜底，避免第一行空白。两者都没有时显示占位而不是空串。
    var userName: String {
        if let name = session.profile?.name, !name.isEmpty {
            return name
        }
        if let name = session.session?.userName, !name.isEmpty {
            return name
        }
        let cached = preferences.lastUserName
        return cached.isEmpty ? Self.unknownPlaceholder : cached
    }

    /// 第二行：邮箱。服务端可能返回 null（实测 admin 账号即如此），此时显示占位。
    var email: String? {
        guard let email = session.profile?.email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty else {
            return nil
        }
        return email
    }

    /// 第三行：套餐标识。
    ///
    /// 原样返回服务端 `tier`，不做映射：把 `admin` 显示成 `ultra` 是错的。
    /// 只有拿不到资料时才退回占位。
    var planLabel: String {
        let tier = session.profile?.tier ?? ""
        return tier.isEmpty ? Self.unknownPlaceholder : tier
    }

    /// 是否有真实头像可加载。
    var avatarURL: URL? {
        session.profile?.avatarURL(baseURL: session.resolvedBaseURL)
    }

    /// 资料是否还没就绪；界面据此决定是否显示加载态。
    var isResolving: Bool {
        session.profile == nil && session.isRefreshingProfile
    }

    /// 服务端没有给出字段时的统一占位，避免出现空行或字面 null。
    static let unknownPlaceholder = "—"
}

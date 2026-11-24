import Foundation
import Observation

// MARK: - 账号资料
//
// 「我的」页头部的数据来源。用户名来自会话（冷启动时回退到上次登录的展示名），
// 邮箱与套餐当前没有后端字段，由这里给出统一缺省值。
// 不发起任何请求，也不持有凭证。

@MainActor
@Observable
final class ProfileStore {
    /// 没有后端字段时第二行显示的示例地址。
    static let placeholderEmail = "name@example.com"

    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private let preferences: PreferencesStoring

    init(session: SessionStore, preferences: PreferencesStoring) {
        self.session = session
        self.preferences = preferences
    }

    /// 第一行：登录会带用户名；冷启动从 Keychain 恢复时为空，回退到上次登录记下的展示名。
    var userName: String {
        if let name = session.session?.userName, !name.isEmpty {
            return name
        }
        return preferences.lastUserName
    }

    /// 第二行：后端没有邮箱字段，统一显示示例地址。
    var email: String { Self.placeholderEmail }

    /// 第三行：套餐标识，当前没有后端，恒为 `.ultra`。
    var plan: PlanTier { PlanTier.current }

    /// 本轮没有真实头像图片：`nil` 表示界面显示缺省图形。
    /// 接上后端后在这里返回图片资源名即可，视图不必改。
    var avatarImageName: String? { nil }
}

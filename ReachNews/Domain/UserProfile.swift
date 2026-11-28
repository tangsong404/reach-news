import Foundation

// MARK: - 当前用户
//
// 服务端 `GET /api/v1/me` 与登录/注册响应里的 `user` 字段。
// 字段以实测为准：`email` 可能为 null，`tier` 除 free/ultra 外还有 admin。

struct UserProfile: Equatable {
    let id: String
    let name: String
    /// 未填写时为 nil；界面显示占位，不显示字面 null。
    let email: String?
    /// 服务端原样返回的档位，例如 `free` / `ultra` / `admin`。
    let tier: String
    /// 形如 `/api/v1/users/<id>/avatar`；为 nil 表示没有头像。
    let avatarURLPath: String?
    /// 自己拥有的频道数，不含订阅。
    let channelCount: Int?

    /// 拼成可直接请求的绝对地址；没有头像时为 nil。
    ///
    /// 服务端返回的是绝对路径（`/api/v1/users/.../avatar`）。直接交给
    /// `URL(string:relativeTo:)` 会替换掉 baseURL 的 path 部分——这里正是想要的行为，
    /// 但 baseURL 若带路径前缀（自建反代）就会丢前缀，因此用 origin 重新拼。
    func avatarURL(baseURL: URL) -> URL? {
        guard let path = avatarURLPath, !path.isEmpty else { return nil }
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = path.hasPrefix("/") ? path : "/" + path
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

// MARK: - 档位能力
//
// 客户端一律读这里的值，不硬编码档位与数值的对应关系。

struct UserCapabilities: Equatable {
    let tier: String
    let ask: Bool
    let briefImages: Bool
    /// nil 表示不限。
    let channelLimit: Int?

    /// 当前的频道数是否已达上限；只用于提示，真正的判定以服务端 403 为准。
    func reachedChannelLimit(currentCount: Int) -> Bool {
        guard let limit = channelLimit else { return false }
        return currentCount >= limit
    }

    /// 没有后端数据时的保守默认：允许追问、不预留配图、不限频道。
    static let unknown = UserCapabilities(tier: "", ask: true, briefImages: false, channelLimit: nil)
}

// MARK: - 注册错误
//
// 服务端会返回中文 message，客户端优先展示它；这里只保留 code 用于测试与兜底。

struct RegistrationError: Error, Equatable {
    let code: String
    let message: String

    /// 兜底文案的本地化键：仅当服务端没给 message 时使用。
    var fallbackKey: String {
        "register.error." + code
    }
}

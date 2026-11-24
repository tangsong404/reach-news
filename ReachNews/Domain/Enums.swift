import Foundation

// MARK: - 频道类型
//
// 服务端 CHANNEL_KINDS 只剩 channel / follow：订阅是关系，不是类型。
// 旧值与未知值一律降级为普通频道，不丢数据也不崩溃。

enum ChannelKind: String, Equatable, CaseIterable {
    case channel
    case follow

    init(apiValue: String?) {
        self = ChannelKind(rawValue: apiValue ?? "") ?? .channel
    }

    /// `kind` 只区分「用户频道」与「跟踪」，与订阅无关；可写性一律看 `owner`。
    var isFollow: Bool { self == .follow }
}

// MARK: - 当前用户相对频道的身份
//
// 可写性判定的唯一依据：creator 才能编辑、触发运行、删除。

enum ChannelOwner: String, Equatable {
    case creator
    case subscriber

    init(apiValue: String?) {
        self = ChannelOwner(rawValue: apiValue ?? "") ?? .creator
    }

    var isCreator: Bool { self == .creator }
}

// MARK: - 运行状态
//
// 三分法（契约）：进行中不产出日报；published 只呈现日报；missed 不是失败。

enum RunState: String, Equatable, CaseIterable {
    case queued
    case collecting
    case writing
    case published
    case failed
    case missed
    case cancelled

    init(apiValue: String?) {
        self = RunState(rawValue: apiValue ?? "") ?? .cancelled
    }

    var isRunning: Bool {
        switch self {
        case .queued, .collecting, .writing: return true
        case .published, .failed, .missed, .cancelled: return false
        }
    }

    var producedBrief: Bool { self == .published }
}

// MARK: - 错过原因
//
// 服务端会新增原因，未知值必须保留原始字符串，不得丢弃。

enum MissedReason: Equatable, Hashable {
    case noMaterial
    case queueTimeout
    case resumeWriting
    case unknown(String)

    static func parse(_ raw: String?) -> MissedReason? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw {
        case "no-material": return .noMaterial
        case "queue-timeout": return .queueTimeout
        case "resume-writing": return .resumeWriting
        default: return .unknown(raw)
        }
    }

    var rawValue: String {
        switch self {
        case .noMaterial: return "no-material"
        case .queueTimeout: return "queue-timeout"
        case .resumeWriting: return "resume-writing"
        case .unknown(let value): return value
        }
    }
}

// MARK: - 错误码
//
// 未知值保留，不因为新增 code 就丢弃原因。
// not_found 的两义不参与判断：资源是否存在由调用方按路径决定。
// presets_removed 与 not_found 必须区分：前者是「旧接口已停用」。

enum APIErrorCode: Equatable {
    case unauthorized
    case tooManyAttempts
    case invalidConnector
    case notFound
    case invalidInput
    case busy
    case badRequest
    case internalError
    case presetsRemoved
    case notPublished
    case ownChannel
    case subscriberReadOnly
    case unknown(String)

    static func parse(_ raw: String) -> APIErrorCode {
        switch raw {
        case "unauthorized": return .unauthorized
        case "too_many_attempts": return .tooManyAttempts
        case "invalid_connector": return .invalidConnector
        case "not_found": return .notFound
        case "invalid_input": return .invalidInput
        case "busy": return .busy
        case "bad_request": return .badRequest
        case "internal_error": return .internalError
        case "presets_removed": return .presetsRemoved
        case "not_published": return .notPublished
        case "own_channel": return .ownChannel
        case "subscriber_read_only": return .subscriberReadOnly
        default: return .unknown(raw)
        }
    }

    var rawValue: String {
        switch self {
        case .unauthorized: return "unauthorized"
        case .tooManyAttempts: return "too_many_attempts"
        case .invalidConnector: return "invalid_connector"
        case .notFound: return "not_found"
        case .invalidInput: return "invalid_input"
        case .busy: return "busy"
        case .badRequest: return "bad_request"
        case .internalError: return "internal_error"
        case .presetsRemoved: return "presets_removed"
        case .notPublished: return "not_published"
        case .ownChannel: return "own_channel"
        case .subscriberReadOnly: return "subscriber_read_only"
        case .unknown(let value): return value
        }
    }
}

// MARK: - 套餐
//
// 「我的」页头部的第三行展示它。后端尚未提供该字段，因此由客户端给出统一取值；
// 先按三值建模，接上后端后只需替换取值来源，界面不必改动。

enum PlanTier: String, Equatable, CaseIterable {
    case free
    case pro
    case ultra

    /// 界面上原样显示小写的 `free` / `pro` / `ultra`。
    var label: String { rawValue }

    var labelKey: String { "me.account.plan." + rawValue }

    /// 没有后端时的统一取值。
    static let current: PlanTier = .ultra
}

// MARK: - 运行触发方式

enum RunTrigger: String, Equatable {
    case manual
    case schedule
    case regenerate
    case retry
    case resume
    case failureRetry = "failure-retry"
    case unknown

    static func parse(_ raw: String?) -> RunTrigger {
        RunTrigger(rawValue: raw ?? "") ?? .unknown
    }
}

// MARK: - 追问角色

enum AskRole: String, Equatable {
    case user
    case assistant

    static func parse(_ raw: String?) -> AskRole {
        AskRole(rawValue: raw ?? "") ?? .assistant
    }
}

// MARK: - 归一化后的 API 错误

enum APIError: Error, Equatable {
    case offline
    case transport(String)
    case unauthorized
    case notFound
    case invalidInput(String)
    case tooManyAttempts
    case invalidConnector(String)
    case busy(String)
    case badRequest(String)
    case server(String)
    case decodingFailed
    case invalidConfiguration
    /// 旧接口已停用（presets_removed）：与「资源不存在」区分。
    case removed(String)
    /// 频道未公开：订阅或 fork 别人的私有频道。
    case notPublished(String)
    /// 订阅自己的频道。
    case ownChannel(String)
    /// 订阅频道只读：修改频道或触发运行被拒。
    case subscriberReadOnly(String)

    var errorCode: APIErrorCode? {
        switch self {
        case .unauthorized: return .unauthorized
        case .tooManyAttempts: return .tooManyAttempts
        case .invalidConnector: return .invalidConnector
        case .notFound: return .notFound
        case .invalidInput: return .invalidInput
        case .busy: return .busy
        case .badRequest: return .badRequest
        case .server: return .internalError
        case .removed: return .presetsRemoved
        case .notPublished: return .notPublished
        case .ownChannel: return .ownChannel
        case .subscriberReadOnly: return .subscriberReadOnly
        case .offline, .transport, .decodingFailed, .invalidConfiguration: return nil
        }
    }

    var isOffline: Bool {
        if case .offline = self { return true }
        return false
    }

    var isBusy: Bool {
        if case .busy = self { return true }
        return false
    }

    /// 登录限流：不得自动重试，否则会把锁定时间一直续期。
    var isTooManyAttempts: Bool {
        if case .tooManyAttempts = self { return true }
        return false
    }
}

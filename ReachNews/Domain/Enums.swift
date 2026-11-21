import Foundation

// MARK: - 频道类型
//
// 服务端 CHANNEL_KINDS 为 channel / follow / preset。
// preset 是管理员账号的模板频道，且会参与调度，因此不能当作普通频道渲染。

enum ChannelKind: String, Equatable {
    case channel
    case follow
    case preset

    init(apiValue: String?) {
        self = ChannelKind(rawValue: apiValue ?? "") ?? .channel
    }

    /// 是否出现在用户的频道列表中（preset 归管理员，普通用户看不到）。
    var isUserVisible: Bool {
        self != .preset
    }
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
// 已实测六值；unknown 保留，不因为新增 code 就丢弃原因。
// not_found 的两义不参与判断：资源是否存在由调用方按路径决定。

enum APIErrorCode: Equatable {
    case unauthorized
    case tooManyAttempts
    case invalidConnector
    case notFound
    case invalidInput
    case busy
    case badRequest
    case internalError
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
        case .unknown(let value): return value
        }
    }
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

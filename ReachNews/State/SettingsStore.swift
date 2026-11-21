import Foundation
import Observation

// MARK: - 服务端设置
//
// 只读 GET /api/v1/settings，目前只取 timeZone。
// 请求失败或字段缺失时回退 Asia/Shanghai，且不阻断主流程。

@MainActor
@Observable
final class SettingsStore {
    /// 服务端返回的原始时区标识，用于界面展示。
    private(set) var timeZoneIdentifier: String = ServiceTimeZone.fallbackIdentifier
    /// 已生效的时区。
    private(set) var timeZone: TimeZone = ServiceTimeZone.resolve(nil)
    private(set) var isLoaded = false
    private(set) var lastError: APIError?

    @ObservationIgnored private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    /// 展示用文案键的格式化参数。
    var displayTimeZone: String { timeZoneIdentifier }

    var isFallback: Bool {
        timeZoneIdentifier == ServiceTimeZone.fallbackIdentifier && lastError != nil
    }

    func load() async {
        do {
            let dto = try await client.settings()
            apply(dto.timeZone)
            lastError = nil
        } catch let apiError as APIError {
            applyFallback(error: apiError)
        } catch {
            applyFallback(error: .transport(error.localizedDescription))
        }
        isLoaded = true
    }

    /// 应用服务端返回的时区；非法值回退，不抛错。
    func apply(_ raw: String?) {
        let identifier = ServiceTimeZone.displayIdentifier(raw)
        let zone = ServiceTimeZone.resolve(raw)
        timeZoneIdentifier = identifier
        timeZone = zone
        DisplayTime.setTimeZone(zone)
    }

    private func applyFallback(error: APIError) {
        lastError = error
        apply(nil)
    }
}

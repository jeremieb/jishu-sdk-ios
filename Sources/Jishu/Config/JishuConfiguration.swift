import Foundation

struct JishuConfiguration: Sendable {
    let baseURL: URL
    let apiToken: String
    let appId: String
    let environment: String?
    let enableDebugLogs: Bool
}

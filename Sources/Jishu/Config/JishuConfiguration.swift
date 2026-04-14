import Foundation

struct JishuConfiguration: Sendable {
    let server: JishuEnvironment
    let apiToken: String
    let appId: String
    let environment: String?
    let debugLevel: JishuDebugLevel

    var baseURL: URL { server.baseURL }
}

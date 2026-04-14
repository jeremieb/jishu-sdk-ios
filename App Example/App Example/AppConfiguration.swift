import Foundation
import Jishu

struct AppConfiguration {
    let server: JishuEnvironment
    let apiToken: String
    let appID: String

    static func load() -> AppConfiguration? {
        if let fromLocalFile = loadFromLocalFile() {
            return fromLocalFile
        }
        if let fromEnvironment = loadFromEnvironment() {
            return fromEnvironment
        }
        return loadFromInfoPlist()
    }

    private static func loadFromLocalFile() -> AppConfiguration? {
        guard
            !ExampleAppConfig.apiToken.isEmpty,
            !ExampleAppConfig.appID.isEmpty
        else {
            return nil
        }

        return AppConfiguration(
            server: ExampleAppConfig.server,
            apiToken: ExampleAppConfig.apiToken,
            appID: ExampleAppConfig.appID
        )
    }

    private static func loadFromEnvironment() -> AppConfiguration? {
        let env = ProcessInfo.processInfo.environment
        guard
            let apiToken = env["JISHU_API_TOKEN"],
            let appID = env["JISHU_APP_ID"],
            !apiToken.isEmpty,
            !appID.isEmpty
        else {
            return nil
        }

        let server: JishuEnvironment = env["JISHU_BASE_URL"]?.contains("staging") == true ? .staging : .production
        return AppConfiguration(server: server, apiToken: apiToken, appID: appID)
    }

    private static func loadFromInfoPlist() -> AppConfiguration? {
        guard
            let apiToken = Bundle.main.object(forInfoDictionaryKey: "JISHU_API_TOKEN") as? String,
            let appID = Bundle.main.object(forInfoDictionaryKey: "JISHU_APP_ID") as? String,
            !apiToken.isEmpty,
            !appID.isEmpty
        else {
            return nil
        }

        let baseURLString = Bundle.main.object(forInfoDictionaryKey: "JISHU_BASE_URL") as? String ?? ""
        let server: JishuEnvironment = baseURLString.contains("staging") ? .staging : .production
        return AppConfiguration(server: server, apiToken: apiToken, appID: appID)
    }
}

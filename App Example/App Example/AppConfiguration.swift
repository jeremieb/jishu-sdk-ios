import Foundation

struct AppConfiguration {
    let baseURL: URL
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
            let baseURL = URL(string: ExampleAppConfig.baseURL),
            !ExampleAppConfig.apiToken.isEmpty,
            !ExampleAppConfig.appID.isEmpty
        else {
            return nil
        }

        return AppConfiguration(
            baseURL: baseURL,
            apiToken: ExampleAppConfig.apiToken,
            appID: ExampleAppConfig.appID
        )
    }

    private static func loadFromEnvironment() -> AppConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard
            let baseURLString = environment["JISHU_BASE_URL"],
            let baseURL = URL(string: baseURLString),
            let apiToken = environment["JISHU_API_TOKEN"],
            let appID = environment["JISHU_APP_ID"],
            !apiToken.isEmpty,
            !appID.isEmpty
        else {
            return nil
        }

        return AppConfiguration(baseURL: baseURL, apiToken: apiToken, appID: appID)
    }

    private static func loadFromInfoPlist() -> AppConfiguration? {
        guard
            let baseURLString = Bundle.main.object(forInfoDictionaryKey: "JISHU_BASE_URL") as? String,
            let baseURL = URL(string: baseURLString),
            let apiToken = Bundle.main.object(forInfoDictionaryKey: "JISHU_API_TOKEN") as? String,
            let appID = Bundle.main.object(forInfoDictionaryKey: "JISHU_APP_ID") as? String,
            !apiToken.isEmpty,
            !appID.isEmpty
        else {
            return nil
        }

        return AppConfiguration(baseURL: baseURL, apiToken: apiToken, appID: appID)
    }
}

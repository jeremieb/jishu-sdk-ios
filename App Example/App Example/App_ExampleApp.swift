import SwiftUI
import Jishu

@main
struct App_ExampleApp: App {
    init() {
        guard let configuration = AppConfiguration.load() else {
            assertionFailure(
                "Missing Jishu configuration. Set JISHU_BASE_URL, JISHU_API_TOKEN and JISHU_APP_ID in environment variables or Info.plist."
            )
            return
        }

        Jishu.configure(
            baseURL: configuration.baseURL,
            apiToken: configuration.apiToken,
            appId: configuration.appID
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

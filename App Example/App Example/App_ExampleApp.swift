//
//  App_ExampleApp.swift
//  App Example
//
//  Created by Jeremie Berduck on 24/3/26.
//

import SwiftUI
import Jishu

@main
struct App_ExampleApp: App {
    private let isConfigured: Bool

    init() {
        guard let config = AppConfiguration.load() else {
            isConfigured = false
            return
        }

        let environment: String? = config.baseURL.host?.contains("staging") == true ? "staging" : nil

        Jishu.configure(
            baseURL: config.baseURL,
            apiToken: config.apiToken,
            appId: config.appID,
            environment: environment,
            debugLevel: .verbose
        )
        isConfigured = true
    }

    var body: some Scene {
        WindowGroup {
            if isConfigured {
                ContentView()
            } else {
                ConfigurationErrorView()
            }
        }
    }
}

private struct ConfigurationErrorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Missing Jishu configuration")
                .font(.headline)
            Text("Set credentials in ExampleAppConfig.swift, environment variables, or Info.plist.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

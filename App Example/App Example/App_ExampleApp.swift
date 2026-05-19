import SwiftUI
import Jishu
import UIKit

@main
struct App_ExampleApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let isConfigured: Bool
    @State private var didTrackLaunch = false
    @State private var reviewPresenter = JishuReviewPresenter()

    init() {
        guard let config = AppConfiguration.load() else {
            isConfigured = false
            return
        }

        Jishu.configure(
            server: config.server,
            apiToken: config.apiToken,
            appId: config.appID,
            debugLevel: .verbose
        )
        isConfigured = true
    }

    var body: some Scene {
        WindowGroup {
            if isConfigured {
                ContentView()
                    .jishuReviewSheet(presenter: reviewPresenter)
                    .task {
                        await trackLaunchIfPossible()
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        guard newPhase == .active else { return }
                        Task {
                            await trackLaunchIfPossible()
                        }
                    }
            } else {
                ConfigurationErrorView()
            }
        }
    }

    @MainActor
    private func trackLaunchIfPossible() async {
        guard !didTrackLaunch else { return }
        didTrackLaunch = true
        Jishu.reviewUIHandler = reviewPresenter
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        await Jishu.trackLaunch(in: scene)
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

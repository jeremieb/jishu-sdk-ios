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
    
    init() {
        Jishu.configure(
            baseURL: URL(string: "https://staging.jishu.page")!,
            apiToken: "YOUR_API_TOKEN",
            appId: "YOUR_APP_ID"
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

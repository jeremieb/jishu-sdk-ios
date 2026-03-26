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
            apiToken: "f6154c98fed668f1c0e29485a2d831f3093c012d983b323a959774877876b984",
            appId: "77256f33f92487a8e7c392c6f8e46b90"
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

//
//  ContentView.swift
//  App Example
//
//  Created by Jeremie Berduck on 24/3/26.
//

import SwiftUI
import Jishu

struct ContentView: View {
    
    @State private var userID: String = Jishu.displayUserID
    @State private var isGranted: Bool = false
    
    var body: some View {
        VStack {
            GroupBox(label: Label("Jishu User ID", systemImage: "person.fill")) {
                Text(userID)
                    .font(.footnote)
                    .textSelection(.enabled)
                HStack {
                    if isGranted {
                        Text("Access premium granted")
                            .foregroundStyle(Color.green)
                    } else {
                        Text("Access premium refused")
                            .foregroundStyle(Color.red)
                    }
                }
            }
        }
        .padding()
        .onAppear {
            update()
        }
    }
    
    private func update() {
        Task {
            do {
                let result = try await Jishu.checkAccess()
                if result.granted {
                    isGranted = true
                }
            } catch {
                print("‼️ Jishu: Something went wrong — \(error)")
            }
        }
    }
}

#Preview {
    ContentView()
}

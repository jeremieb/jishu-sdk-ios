//
//  ContentView.swift
//  App Example
//
//  Created by Jeremie Berduck on 24/3/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label("Jishu User ID", systemImage: "person.fill")) {
                Text(viewModel.userID)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }

            GroupBox(label: Label("Optional externalUserId", systemImage: "person.badge.key")) {
                TextField("externalUserId (leave empty to use displayUserID)", text: $viewModel.externalUserID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }

            Button {
                viewModel.checkGrant()
            } label: {
                if viewModel.isCheckingGrant {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Check Access")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isCheckingGrant)

            GroupBox(label: Label("Result", systemImage: "checkmark.shield")) {
                Text(viewModel.isGranted ? "Access premium granted" : "Access premium refused")
                    .foregroundStyle(viewModel.isGranted ? Color.green : Color.red)

                Text(viewModel.grantCheckMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

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
    @State private var externalUserID: String = ""
    @State private var isGranted: Bool = false
    @State private var grantCheckMessage: String = "Run a grant check to see details."
    @State private var isCheckingGrant: Bool = false
    @State private var isShowingMessageSheet: Bool = false
    
    var body: some View {
        VStack(spacing: 16) {
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

            GroupBox(label: Label("Grant Check", systemImage: "checkmark.shield")) {
                TextField("External User ID (optional)", text: $externalUserID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Check Grant") {
                    update()
                }
                .buttonStyle(.bordered)
                .disabled(isCheckingGrant)

                Text(grantCheckMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            
            Button("New Message") {
                isShowingMessageSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .onAppear {
            update()
        }
        .sheet(isPresented: $isShowingMessageSheet) {
            ContactMessageSheet()
        }
    }
    
    private func update() {
        isCheckingGrant = true
        let trimmedExternalUserID = externalUserID.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let result: AccessResult

                if trimmedExternalUserID.isEmpty {
                    result = try await Jishu.checkAccess()
                } else {
                    result = try await Jishu.checkAccess(externalUserId: trimmedExternalUserID)
                }

                await MainActor.run {
                    isGranted = result.granted
                    isCheckingGrant = false
                    grantCheckMessage = """
                    Granted: \(result.granted)
                    Identity used: \(trimmedExternalUserID.isEmpty ? "displayUserID (\(userID))" : "externalUserId (\(trimmedExternalUserID))")
                    """
                }
            } catch {
                print("‼️ Jishu checkAccess failed: \(error)")
                await MainActor.run {
                    isGranted = false
                    isCheckingGrant = false
                    grantCheckMessage = "Grant check failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct ContactMessageSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var senderName: String = ""
    @State private var senderEmail: String = ""
    @State private var subject: String = ""
    @State private var bodyText: String = ""
    @State private var status: FormStatus = .idle
    
    private enum FormStatus: Equatable {
        case idle
        case sending
        case success
        case error(String)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Sender") {
                    TextField("Your name (optional)", text: $senderName)
                    TextField("Your email", text: $senderEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                Section("Message") {
                    TextField("Subject (optional)", text: $subject)
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 140)
                }
                
                if case .error(let message) = status {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
                
                if case .success = status {
                    Section {
                        Text("Message sent successfully.")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("New Message")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        sendMessage()
                    }
                    .disabled(!canSend)
                }
            }
        }
    }
    
    private var canSend: Bool {
        !senderEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        status != .sending
    }
    
    private func sendMessage() {
        status = .sending
        
        let message = ContactMessage(
            senderName: senderName.nilIfBlank,
            senderEmail: senderEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            subject: subject.nilIfBlank,
            body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        Task {
            do {
                try await Jishu.sendContactMessage(message)
                await MainActor.run {
                    status = .success
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    dismiss()
                }
            } catch JishuError.httpError(429) {
                print("⚠️ Jishu sendContactMessage failed with 429 (rate limit).")
                await MainActor.run {
                    status = .error("Too many messages. Please try again later.")
                }
            } catch {
                print("‼️ Jishu sendContactMessage failed: \(error)")
                await MainActor.run {
                    status = .error("Could not send the message. Please try again. (\(error.localizedDescription))")
                }
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    ContentView()
}

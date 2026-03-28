import SwiftUI
import Jishu

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()

    var body: some View {
        VStack(spacing: 16) {
            GroupBox(label: Label("Jishu User ID", systemImage: "person.fill")) {
                Text(viewModel.userID)
                    .font(.footnote)
                    .textSelection(.enabled)

                HStack {
                    if viewModel.isGranted {
                        Text("Access premium granted")
                            .foregroundStyle(.green)
                    } else {
                        Text("Access premium refused")
                            .foregroundStyle(.red)
                    }
                }
            }

            GroupBox(label: Label("Grant Check", systemImage: "checkmark.shield")) {
                TextField("External User ID (optional)", text: $viewModel.externalUserID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Check Grant") {
                    viewModel.checkGrant()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isCheckingGrant)

                Text(viewModel.grantCheckMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 12) {
                Button("New Message") {
                    viewModel.isShowingMessageSheet = true
                }
                .buttonStyle(.borderedProminent)

                Button("Feature Requests") {
                    viewModel.isShowingFeedbackSheet = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .onAppear {
            viewModel.checkGrant()
        }
        .sheet(isPresented: $viewModel.isShowingMessageSheet) {
            ContactMessageSheet()
        }
        .sheet(isPresented: $viewModel.isShowingFeedbackSheet) {
            FeedbackSheet()
        }
    }
}

private struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FeedbackViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.proposals.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Retry") {
                            Task { await viewModel.load() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.proposals.isEmpty {
                    ContentUnavailableView(
                        "No Feature Requests",
                        systemImage: "lightbulb",
                        description: Text("Be the first to suggest a feature.")
                    )
                } else {
                    List(viewModel.proposals) { proposal in
                        ProposalRow(
                            proposal: proposal,
                            hasVoted: viewModel.votedIds.contains(proposal.id)
                        ) {
                            Task { await viewModel.vote(on: proposal) }
                        }
                    }
                }
            }
            .navigationTitle("Feature Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.isShowingSubmitSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $viewModel.isShowingSubmitSheet) {
                SubmitProposalSheet { proposal in
                    viewModel.didSubmitProposal(proposal)
                }
            }
        }
    }
}

private struct ProposalRow: View {
    let proposal: JishuProposal
    let hasVoted: Bool
    let onVote: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onVote) {
                VStack(spacing: 2) {
                    Image(systemName: hasVoted ? "chevron.up.circle.fill" : "chevron.up.circle")
                        .font(.title2)
                        .foregroundStyle(hasVoted ? Color.accentColor : Color.secondary)
                    Text("\(proposal.voteCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(proposal.title)
                    .font(.headline)

                if let description = proposal.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(proposal.formattedCreatedAt)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SubmitProposalSheet: View {
    let onSubmitted: (JishuProposal) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SubmitProposalViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Short title", text: $viewModel.title)
                    TextField("Description (optional)", text: $viewModel.description, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                } footer: {
                    Text("Describe the feature you'd like to see. Keep the title concise.")
                }

                if case .error(let message) = viewModel.status {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("New Feature Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.status == .sending {
                        ProgressView()
                    } else {
                        Button("Submit") {
                            Task {
                                do {
                                    let proposal = try await viewModel.submit()
                                    onSubmitted(proposal)
                                    dismiss()
                                } catch {
                                    // Error state already handled in the view model.
                                }
                            }
                        }
                        .disabled(!viewModel.canSubmit)
                    }
                }
            }
        }
    }
}

private struct ContactMessageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ContactMessageViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Sender") {
                    TextField("Your name (optional)", text: $viewModel.senderName)
                    TextField("Your email", text: $viewModel.senderEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Message") {
                    TextField("Subject (optional)", text: $viewModel.subject)
                    TextEditor(text: $viewModel.bodyText)
                        .frame(minHeight: 140)
                }

                if case .error(let message) = viewModel.status {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }

                if case .success = viewModel.status {
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
                        Task {
                            await viewModel.sendMessage()
                            if case .success = viewModel.status {
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.canSend)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

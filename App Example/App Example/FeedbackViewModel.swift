import Foundation
import Combine
import Jishu

@MainActor
final class FeedbackViewModel: ObservableObject {
    @Published var proposals: [JishuProposal] = []
    @Published var votedIds: Set<String> = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isShowingSubmitSheet: Bool = false

    private let client: JishuClientProtocol

    init() {
        self.client = JishuClient()
    }

    init(client: JishuClientProtocol) {
        self.client = client
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            proposals = try await client.fetchProposals()
        } catch JishuError.httpError(let code) {
            errorMessage = "Server error (\(code)). Please try again."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func vote(on proposal: JishuProposal) async {
        guard !votedIds.contains(proposal.id) else { return }

        do {
            let newCount = try await client.vote(on: proposal)
            votedIds.insert(proposal.id)
            if let index = proposals.firstIndex(where: { $0.id == proposal.id }) {
                proposals[index] = JishuProposal(
                    id:          proposal.id,
                    title:       proposal.title,
                    description: proposal.description,
                    status:      proposal.status,
                    voteCount:   newCount,
                    createdAt:   proposal.createdAt   // Date — no change needed
                )
            }
        } catch {
            // Keeping errors quiet in this example app to avoid interrupting UI flow.
        }
    }

    func didSubmitProposal(_ proposal: JishuProposal) {
        proposals.insert(proposal, at: 0)
    }
}

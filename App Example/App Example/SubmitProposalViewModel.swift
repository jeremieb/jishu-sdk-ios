import Foundation
import Combine
import Jishu

@MainActor
final class SubmitProposalViewModel: ObservableObject {
    enum FormStatus: Equatable {
        case idle
        case sending
        case error(String)
    }

    @Published var title: String = ""
    @Published var description: String = ""
    @Published var status: FormStatus = .idle

    private let client: JishuClientProtocol

    init() {
        self.client = JishuClient()
    }

    init(client: JishuClientProtocol) {
        self.client = client
    }

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && status != .sending
    }

    func submit() async throws -> JishuProposal {
        status = .sending

        do {
            let proposal = try await client.submitProposal(
                title: title,
                description: description.isEmpty ? nil : description
            )
            status = .idle
            return proposal
        } catch JishuError.httpError(429) {
            status = .error("Too many requests. Please try again later.")
            throw JishuError.httpError(429)
        } catch {
            status = .error("Could not submit. Please try again. (\(error.localizedDescription))")
            throw error
        }
    }
}

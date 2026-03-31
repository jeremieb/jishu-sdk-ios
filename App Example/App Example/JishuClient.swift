import Foundation
import Jishu

protocol JishuClientProtocol {
    func checkAccess(externalUserID: String?) async throws -> AccessResult
    func fetchProposals() async throws -> [JishuProposal]
    func vote(on proposal: JishuProposal) async throws -> Int
    func submitProposal(title: String, description: String?) async throws -> JishuProposal
    func sendContactMessage(_ message: ContactMessage) async throws
}

struct JishuClient: JishuClientProtocol {
    func checkAccess(externalUserID: String?) async throws -> AccessResult {
        if let externalUserID, !externalUserID.isEmpty {
            return try await Jishu.checkAccess(externalUserId: externalUserID)
        }
        return try await Jishu.checkAccess()
    }

    func fetchProposals() async throws -> [JishuProposal] {
        try await Jishu.fetchProposals()
    }

    func vote(on proposal: JishuProposal) async throws -> Int {
        try await Jishu.vote(on: proposal)
    }

    func submitProposal(title: String, description: String?) async throws -> JishuProposal {
        try await Jishu.submitProposal(title: title, description: description)
    }

    func sendContactMessage(_ message: ContactMessage) async throws {
        try await Jishu.sendContactMessage(message)
    }
}

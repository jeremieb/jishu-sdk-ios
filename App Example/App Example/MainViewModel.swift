import Foundation
import Combine
import Jishu

@MainActor
final class MainViewModel: ObservableObject {
    @Published var userID: String = Jishu.displayUserID
    @Published var externalUserID: String = ""
    @Published var isGranted: Bool = false
    @Published var grantCheckMessage: String = "Run a grant check to see details."
    @Published var isCheckingGrant: Bool = false
    @Published var isShowingMessageSheet: Bool = false
    @Published var isShowingFeedbackSheet: Bool = false

    private let client: JishuClientProtocol

    init() {
        self.client = JishuClient()
    }

    init(client: JishuClientProtocol) {
        self.client = client
    }

    func checkGrant() {
        isCheckingGrant = true
        let trimmedExternalUserID = externalUserID.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let result = try await client.checkAccess(
                    externalUserID: trimmedExternalUserID.isEmpty ? nil : trimmedExternalUserID
                )

                isGranted = result.granted
                isCheckingGrant = false
                grantCheckMessage = """
                Granted: \(result.granted)
                Identity used: \(trimmedExternalUserID.isEmpty ? "displayUserID (\(userID))" : "externalUserId (\(trimmedExternalUserID))")
                """
            } catch {
                isGranted = false
                isCheckingGrant = false
                grantCheckMessage = "Grant check failed: \(error.localizedDescription)"
            }
        }
    }
}

import Foundation
import Combine
import Jishu
import UIKit

@MainActor
final class MainViewModel: ObservableObject {
    @Published var userID: String = Jishu.displayUserID
    @Published var externalUserID: String = ""
    @Published var isGranted: Bool = false
    @Published var grantCheckMessage: String = "Run a grant check to see details."
    @Published var isCheckingGrant: Bool = false
    @Published var isRequestingReview: Bool = false
    @Published var reviewRequestMessage: String = "Tap the button to request review if eligible."
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

    func requestReviewIfEligible() {
        isRequestingReview = true

        Task {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first

            let shown = await Jishu.requestReviewIfEligible(in: scene)

            isRequestingReview = false
            reviewRequestMessage = shown
                ? "Review flow shown."
                : "Review flow not shown (not eligible right now)."
        }
    }
}

import Foundation

/// Implement this protocol to replace the default star rating UI with your own.
/// Assign your handler to ``Jishu/reviewUIHandler`` before calling ``Jishu/trackLaunch(in:)``.
public protocol JishuReviewUIHandler: AnyObject {
    /// Called when the SDK has decided to show the review prompt.
    /// Present a 1–5 star rating UI and return the user's response.
    @MainActor
    func presentReviewPrompt(title: String, question: String) async -> JishuReviewResponse
}

/// The user's response to a review prompt.
public struct JishuReviewResponse: Sendable {
    /// Star rating given by the user (1–5). `nil` if dismissed without rating.
    public let rating: Int?
    /// `true` if the user dismissed the prompt without responding.
    public let dismissed: Bool
    /// Feedback text entered after a below-threshold rating. `nil` if not provided.
    public let feedbackMessage: String?

    public init(rating: Int?, dismissed: Bool = false, feedbackMessage: String? = nil) {
        self.rating = rating
        self.dismissed = dismissed
        self.feedbackMessage = feedbackMessage
    }
}

// MARK: - Default UIAlertController presenter

#if canImport(UIKit)
import UIKit

@MainActor
final class DefaultReviewAlertPresenter {
    func present(config: ReviewConfig, in windowScene: UIWindowScene?) async -> JishuReviewResponse {
        guard
            let windowScene,
            let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? windowScene.windows.first?.rootViewController
        else {
            return JishuReviewResponse(rating: nil, dismissed: true)
        }

        let title    = config.promptTitle.isEmpty    ? "Enjoying the app?"              : config.promptTitle
        let question = config.promptQuestion.isEmpty ? "We'd love to hear what you think." : config.promptQuestion

        // Star rating alert — walk to the topmost presented controller to avoid silent presentation failures
        let rating: Int? = await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: question, preferredStyle: .alert)
            for star in 1...5 {
                let label = String(repeating: "★", count: star) + String(repeating: "☆", count: 5 - star)
                alert.addAction(UIAlertAction(title: label, style: .default) { _ in
                    continuation.resume(returning: star)
                })
            }
            alert.addAction(UIAlertAction(title: "Not now", style: .cancel) { _ in
                continuation.resume(returning: nil)
            })
            var presenter: UIViewController = rootVC
            while let presented = presenter.presentedViewController { presenter = presented }
            presenter.present(alert, animated: true)
        }

        guard let rating else {
            return JishuReviewResponse(rating: nil, dismissed: true)
        }

        // Feedback text input for below-threshold ratings
        var feedbackMessage: String? = nil
        if rating < config.ratingThreshold && config.captureFeedbackOnNegative {
            let prompt = config.feedbackPrompt.isEmpty ? "What could we improve?" : config.feedbackPrompt
            feedbackMessage = await withCheckedContinuation { continuation in
                let alert = UIAlertController(title: prompt, message: nil, preferredStyle: .alert)
                alert.addTextField { field in
                    field.placeholder = "Your feedback"
                    field.returnKeyType = .send
                }
                alert.addAction(UIAlertAction(title: "Send", style: .default) { _ in
                    let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: text?.isEmpty == false ? text : nil)
                })
                alert.addAction(UIAlertAction(title: "Skip", style: .cancel) { _ in
                    continuation.resume(returning: nil)
                })
                // Walk up to the topmost presented controller
                var presenter: UIViewController = rootVC
                while let presented = presenter.presentedViewController { presenter = presented }
                presenter.present(alert, animated: true)
            }
        }

        return JishuReviewResponse(rating: rating, feedbackMessage: feedbackMessage)
    }
}
#endif

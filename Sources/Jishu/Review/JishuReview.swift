import Foundation

#if canImport(UIKit)
import UIKit
import StoreKit

struct JishuReview {
    /// Pure eligibility check — no side effects, no network calls.
    static func isEligible(config: ReviewConfig, store: ReviewStore) async -> Bool {
        guard config.enabled else { return false }

        let promptCount = await store.promptCount
        guard promptCount < config.maxPromptsPerDevice else { return false }

        if let lastInterval = await store.lastPromptDate {
            let daysSince = Calendar.current.dateComponents(
                [.day],
                from: Date(timeIntervalSince1970: lastInterval),
                to: Date()
            ).day ?? 0
            guard daysSince >= config.cooldownDays else { return false }
        }

        let launchCount  = await store.launchCount
        let installDate  = await store.installDate
        let launchesMet  = config.minLaunches == 0 || launchCount >= config.minLaunches
        let daysMet: Bool = {
            guard config.minDaysSinceInstall > 0 else { return true }
            guard installDate > 0 else { return false }
            let days = Calendar.current.dateComponents(
                [.day],
                from: Date(timeIntervalSince1970: installDate),
                to: Date()
            ).day ?? 0
            return days >= config.minDaysSinceInstall
        }()

        return config.triggerLogic == "OR" ? (launchesMet || daysMet) : (launchesMet && daysMet)
    }

    /// Full prompt flow. Must be called on the main actor (presents UI and calls StoreKit).
    @MainActor
    static func runPromptFlow(
        config: ReviewConfig,
        store: ReviewStore,
        client: JishuClient,
        appId: String,
        uiHandler: (any JishuReviewUIHandler)?,
        scene: UIWindowScene?
    ) async {
        // 1. Log shown
        await client.logReviewEvent(appId: appId, eventType: "shown", platform: "ios", rating: nil)

        // 2. Present UI
        let response: JishuReviewResponse
        if let handler = uiHandler {
            response = await handler.presentReviewPrompt(
                title:    config.promptTitle.isEmpty    ? "Enjoying the app?"               : config.promptTitle,
                question: config.promptQuestion.isEmpty ? "We'd love to hear what you think." : config.promptQuestion
            )
        } else {
            response = await DefaultReviewAlertPresenter().present(config: config, in: scene)
        }

        // 3. Dismissed without rating
        if response.dismissed || response.rating == nil {
            await client.logReviewEvent(appId: appId, eventType: "dismissed", platform: "ios", rating: nil)
            return
        }

        let rating = response.rating!

        // 4. Log rating
        await client.logReviewEvent(appId: appId, eventType: "rating_given", platform: "ios", rating: rating)

        // 5. Positive path — native store review
        if rating >= config.ratingThreshold {
            if let scene {
                SKStoreReviewController.requestReview(in: scene)
            }
            await client.logReviewEvent(appId: appId, eventType: "native_requested", platform: "ios", rating: nil)
        }

        // 6. Negative path — capture feedback
        if rating < config.ratingThreshold && config.captureFeedbackOnNegative {
            let feedback = response.feedbackMessage ?? ""
            if !feedback.isEmpty {
                // sendReviewFeedback auto-logs feedback_sent on the server — no second event call needed
                await client.sendReviewFeedback(appId: appId, body: feedback)
            }
        }

        // 7. Update local state
        await store.recordPromptShown()
    }
}
#endif

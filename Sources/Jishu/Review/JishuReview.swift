import Foundation

#if canImport(UIKit)
import UIKit
import StoreKit
#endif

struct JishuReview {
    static func isEligible(config: ReviewConfig, store: ReviewStore, appId: String) async -> Bool {
        guard config.enabled else { return false }

        let promptCount = await store.promptCount(appId: appId)
        guard promptCount < config.maxPromptsPerDevice else { return false }

        if let lastInterval = await store.lastPromptDate(appId: appId) {
            let daysSince = Calendar.current.dateComponents(
                [.day],
                from: Date(timeIntervalSince1970: lastInterval),
                to: Date()
            ).day ?? 0
            guard daysSince >= config.cooldownDays else { return false }
        }

        let launchCount = await store.launchCount(appId: appId)
        let installDate = await store.installDate(appId: appId)
        let launchesMet = config.minLaunches == 0 || launchCount >= config.minLaunches
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

    /// Checks eligibility and, when the logger is verbose, prints a formatted status block
    /// showing each condition's current value, its target, and how many launches/days remain.
    static func logAndCheckEligibility(
        config: ReviewConfig,
        store: ReviewStore,
        appId: String,
        log: JishuLogger
    ) async -> Bool {
        guard config.enabled else {
            log.review("Review: disabled in dashboard config")
            return false
        }

        let promptCount    = await store.promptCount(appId: appId)
        let launchCount    = await store.launchCount(appId: appId)
        let installDate    = await store.installDate(appId: appId)
        let lastPromptDate = await store.lastPromptDate(appId: appId)
        let now            = Date()

        let daysSinceInstall: Int = installDate > 0
            ? (Calendar.current.dateComponents([.day], from: Date(timeIntervalSince1970: installDate), to: now).day ?? 0)
            : 0

        let daysSinceLastPrompt: Int? = lastPromptDate.map {
            Calendar.current.dateComponents([.day], from: Date(timeIntervalSince1970: $0), to: now).day ?? 0
        }

        let capOk      = promptCount < config.maxPromptsPerDevice
        let cooldownOk = daysSinceLastPrompt.map { $0 >= config.cooldownDays } ?? true

        let launchesMet = config.minLaunches == 0 || launchCount >= config.minLaunches
        let daysMet: Bool = {
            guard config.minDaysSinceInstall > 0 else { return true }
            guard installDate > 0 else { return false }
            return daysSinceInstall >= config.minDaysSinceInstall
        }()

        let triggerMet = config.triggerLogic == "OR" ? (launchesMet || daysMet) : (launchesMet && daysMet)
        let eligible   = capOk && cooldownOk && triggerMet

        if log.level == .verbose {
            log.review("Review status — launch #\(launchCount):")

            if config.minLaunches > 0 {
                if launchesMet {
                    log.review("  launches   \(launchCount) / \(config.minLaunches)  ✓")
                } else {
                    log.review("  launches   \(launchCount) / \(config.minLaunches)  (\(config.minLaunches - launchCount) to go)")
                }
            } else {
                log.review("  launches   —")
            }

            if config.minDaysSinceInstall > 0 {
                if daysMet {
                    log.review("  days       \(daysSinceInstall) / \(config.minDaysSinceInstall)  ✓")
                } else {
                    log.review("  days       \(daysSinceInstall) / \(config.minDaysSinceInstall)  (\(config.minDaysSinceInstall - daysSinceInstall) to go)")
                }
            } else {
                log.review("  days       —")
            }

            if let d = daysSinceLastPrompt {
                if cooldownOk {
                    log.review("  cooldown   \(d) / \(config.cooldownDays) days  ✓")
                } else {
                    log.review("  cooldown   \(d) / \(config.cooldownDays) days  (\(config.cooldownDays - d) to go)")
                }
            } else {
                log.review("  cooldown   never prompted  ✓")
            }

            if capOk {
                log.review("  prompts    \(promptCount) / \(config.maxPromptsPerDevice)")
            } else {
                log.review("  prompts    \(promptCount) / \(config.maxPromptsPerDevice)  ❌ cap reached")
            }

            if eligible {
                log.review("  → eligible — showing prompt")
            } else if !capOk {
                log.review("  → not eligible — prompt cap reached")
            } else if !cooldownOk {
                let remaining = config.cooldownDays - (daysSinceLastPrompt ?? 0)
                log.review("  → not eligible — cooldown (\(remaining) day\(remaining == 1 ? "" : "s") remaining)")
            } else {
                var blockers: [String] = []
                if config.minLaunches > 0, !launchesMet {
                    blockers.append("launches (\(config.minLaunches - launchCount) to go)")
                }
                if config.minDaysSinceInstall > 0, !daysMet {
                    blockers.append("days (\(config.minDaysSinceInstall - daysSinceInstall) to go)")
                }
                let joinWord = config.triggerLogic == "OR" ? " or " : " + "
                log.review("  → not eligible — waiting on \(blockers.joined(separator: joinWord))")
            }
        }

        return eligible
    }

#if canImport(UIKit)
    @MainActor
    static func runPromptFlow(
        config: ReviewConfig,
        store: ReviewStore,
        client: JishuClient,
        appId: String,
        uiHandler: (any JishuReviewUIHandler)?,
        scene: UIWindowScene?
    ) async -> Bool {
        let title    = config.promptTitle.isEmpty    ? "Enjoying the app?"                : config.promptTitle
        let question = config.promptQuestion.isEmpty ? "We'd love to hear what you think." : config.promptQuestion

        let response: JishuReviewResponse
        if let handler = uiHandler {
            response = await handler.presentReviewPrompt(title: title, question: question)
        } else {
            guard let presented = await DefaultReviewAlertPresenter().present(config: config, in: scene) else {
                return false
            }
            response = presented
        }

        let platform = currentPlatform()
        await client.logReviewEvent(appId: appId, eventType: "shown", platform: platform, rating: nil)

        if response.dismissed || response.rating == nil {
            await client.logReviewEvent(appId: appId, eventType: "dismissed", platform: platform, rating: nil)
            await store.recordPromptShown(appId: appId)
            return true
        }

        let rating = response.rating!
        await client.logReviewEvent(appId: appId, eventType: "rating_given", platform: platform, rating: rating)

        if rating >= config.ratingThreshold, let scene {
            SKStoreReviewController.requestReview(in: scene)
            await client.logReviewEvent(appId: appId, eventType: "native_requested", platform: platform, rating: nil)
        }

        if rating < config.ratingThreshold && config.captureFeedbackOnNegative {
            let prompt = config.feedbackPrompt.isEmpty ? "What could we improve?" : config.feedbackPrompt
            let feedbackText: String?
            if let handler = uiHandler {
                feedbackText = await handler.presentFeedbackPrompt(prompt: prompt)
            } else {
                feedbackText = response.feedbackMessage
            }
            if let text = feedbackText, !text.isEmpty {
                await client.sendReviewFeedback(appId: appId, body: text)
            }
        }

        await store.recordPromptShown(appId: appId)
        return true
    }
#else
    // watchOS / macOS — no UIWindowScene, no SKStoreReviewController.
    // A reviewUIHandler must be set; without one the prompt is silently skipped.
    @MainActor
    static func runPromptFlow(
        config: ReviewConfig,
        store: ReviewStore,
        client: JishuClient,
        appId: String,
        uiHandler: (any JishuReviewUIHandler)?
    ) async -> Bool {
        guard let handler = uiHandler else { return false }

        let title    = config.promptTitle.isEmpty    ? "Enjoying the app?"                : config.promptTitle
        let question = config.promptQuestion.isEmpty ? "We'd love to hear what you think." : config.promptQuestion

        let response = await handler.presentReviewPrompt(title: title, question: question)

        let platform = currentPlatform()
        await client.logReviewEvent(appId: appId, eventType: "shown", platform: platform, rating: nil)

        if response.dismissed || response.rating == nil {
            await client.logReviewEvent(appId: appId, eventType: "dismissed", platform: platform, rating: nil)
            await store.recordPromptShown(appId: appId)
            return true
        }

        let rating = response.rating!
        await client.logReviewEvent(appId: appId, eventType: "rating_given", platform: platform, rating: rating)

        if rating < config.ratingThreshold && config.captureFeedbackOnNegative {
            let prompt = config.feedbackPrompt.isEmpty ? "What could we improve?" : config.feedbackPrompt
            let feedbackText = await handler.presentFeedbackPrompt(prompt: prompt)
            if let text = feedbackText, !text.isEmpty {
                await client.sendReviewFeedback(appId: appId, body: text)
            }
        }

        await store.recordPromptShown(appId: appId)
        return true
    }
#endif
}

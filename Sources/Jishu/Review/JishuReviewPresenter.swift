import Observation

@MainActor @Observable
public final class JishuReviewPresenter: JishuReviewUIHandler {

    public var isPresented = false
    public var promptTitle = ""
    public var promptQuestion = ""

    // Set to true when presentFeedbackPrompt is active so JishuReviewView shows the feedback step
    var showFeedbackStep = false
    var feedbackPromptText = ""

    private var continuation: CheckedContinuation<JishuReviewResponse, Never>?
    private var feedbackContinuation: CheckedContinuation<String?, Never>?

    public nonisolated init() {}

    public func presentReviewPrompt(title: String, question: String) async -> JishuReviewResponse {
        promptTitle = title
        promptQuestion = question
        showFeedbackStep = false
        isPresented = true
        return await withCheckedContinuation { self.continuation = $0 }
    }

    public func presentFeedbackPrompt(prompt: String) async -> String? {
        feedbackPromptText = prompt.isEmpty ? "What could we improve?" : prompt
        showFeedbackStep = true
        isPresented = true
        return await withCheckedContinuation { self.feedbackContinuation = $0 }
    }

    public func submit(rating: Int) {
        isPresented = false
        let captured = continuation
        continuation = nil
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            captured?.resume(returning: JishuReviewResponse(rating: rating))
        }
    }

    public func submitFeedback(text: String?) {
        isPresented = false
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let captured = feedbackContinuation
        feedbackContinuation = nil
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            captured?.resume(returning: trimmed?.isEmpty == false ? trimmed : nil)
        }
    }

    public func skipFeedback() {
        isPresented = false
        let captured = feedbackContinuation
        feedbackContinuation = nil
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            captured?.resume(returning: nil)
        }
    }

    public func dismissReview() {
        isPresented = false
        showFeedbackStep = false
        // Resume whichever continuation is active
        if let captured = feedbackContinuation {
            feedbackContinuation = nil
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                captured.resume(returning: nil)
            }
        } else {
            let captured = continuation
            continuation = nil
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                captured?.resume(returning: JishuReviewResponse(rating: nil, dismissed: true))
            }
        }
    }
}

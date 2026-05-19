import Observation

@MainActor @Observable
public final class JishuReviewPresenter: JishuReviewUIHandler {

    public var isPresented = false
    public var promptTitle = ""
    public var promptQuestion = ""

    private var continuation: CheckedContinuation<JishuReviewResponse, Never>?

    public nonisolated init() {}

    public func presentReviewPrompt(title: String, question: String) async -> JishuReviewResponse {
        promptTitle = title
        promptQuestion = question
        isPresented = true
        return await withCheckedContinuation { self.continuation = $0 }
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

    public func dismissReview() {
        isPresented = false
        let captured = continuation
        continuation = nil
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            captured?.resume(returning: JishuReviewResponse(rating: nil, dismissed: true))
        }
    }
}

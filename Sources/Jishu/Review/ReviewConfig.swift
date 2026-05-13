import Foundation

/// Review prompt configuration fetched from the Jishu dashboard.
public struct ReviewConfig: Codable, Sendable {
    public let enabled: Bool
    public let triggerMode: String
    public let minLaunches: Int
    public let minDaysSinceInstall: Int
    public let triggerLogic: String
    public let cooldownDays: Int
    public let maxPromptsPerDevice: Int
    public let promptTitle: String
    public let promptQuestion: String
    /// Ratings >= this value route to the native App Store review dialog.
    /// Ratings below route to the feedback text input.
    public let ratingThreshold: Int
    public let feedbackPrompt: String
    public let captureFeedbackOnNegative: Bool
}

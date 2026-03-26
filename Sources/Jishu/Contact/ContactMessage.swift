import Foundation

/// Input for a contact form submission via ``Jishu/sendContactMessage(_:)``.
public struct ContactMessage: Sendable {
    /// Optional display name of the sender.
    public var senderName: String?
    /// Email address of the sender.
    public var senderEmail: String
    /// Optional message subject.
    public var subject: String?
    /// Message body. Must not be empty.
    public var body: String
    /// Optional user identifier — the same ID you use for entitlement checks.
    /// When `nil`, the SDK automatically fills in `Jishu.displayUserID` so the app
    /// owner can add the sender directly to a promo grant from the dashboard.
    public var userId: String?

    public init(
        senderName: String? = nil,
        senderEmail: String,
        subject: String? = nil,
        body: String,
        userId: String? = nil
    ) {
        self.senderName = senderName
        self.senderEmail = senderEmail
        self.subject = subject
        self.body = body
        self.userId = userId
    }
}

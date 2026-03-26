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

    public init(
        senderName: String? = nil,
        senderEmail: String,
        subject: String? = nil,
        body: String
    ) {
        self.senderName = senderName
        self.senderEmail = senderEmail
        self.subject = subject
        self.body = body
    }
}

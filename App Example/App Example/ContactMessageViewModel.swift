import Foundation
import Combine
import Jishu

@MainActor
final class ContactMessageViewModel: ObservableObject {
    enum FormStatus: Equatable {
        case idle
        case sending
        case success
        case error(String)
    }

    @Published var senderName: String = ""
    @Published var senderEmail: String = ""
    @Published var subject: String = ""
    @Published var bodyText: String = ""
    @Published var status: FormStatus = .idle

    private let client: JishuClientProtocol

    init() {
        self.client = JishuClient()
    }

    init(client: JishuClientProtocol) {
        self.client = client
    }

    var canSend: Bool {
        !senderEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        status != .sending
    }

    func sendMessage() async {
        status = .sending

        let message = ContactMessage(
            senderName: senderName.isEmpty ? nil : senderName,
            senderEmail: senderEmail,
            subject: subject.isEmpty ? nil : subject,
            body: bodyText
        )

        do {
            try await client.sendContactMessage(message)
            status = .success
        } catch JishuError.httpError(429) {
            status = .error("Too many messages. Please try again later.")
        } catch {
            status = .error("Could not send the message. Please try again. (\(error.localizedDescription))")
        }
    }
}

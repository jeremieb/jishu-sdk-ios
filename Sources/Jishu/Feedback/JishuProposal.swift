import Foundation

// MARK: - Public Models

/// A feature request proposal submitted to a Jishu app.
public struct JishuProposal: Codable, Identifiable, Sendable {
    /// Unique proposal identifier.
    public let id: String
    /// Short title describing the requested feature.
    public let title: String
    /// Optional longer description.
    public let description: String?
    /// Current review status.
    public let status: JishuProposalStatus
    /// Total number of upvotes.
    public let voteCount: Int
    /// Creation timestamp decoded from the server's ISO 8601 string.
    public let createdAt: Date

    /// Locale-aware abbreviated display string for `createdAt`, e.g. "Mar 28, 2026".
    public var formattedCreatedAt: String {
        createdAt.formatted(date: .abbreviated, time: .omitted)
    }

    /// Backward-compatible ISO 8601 string representation of `createdAt`.
    @available(*, deprecated, message: "Use createdAt (Date) for display formatting.")
    public var createdAtString: String {
        ISO8601DateFormatter().string(from: createdAt)
    }

    public init(id: String, title: String, description: String?, status: JishuProposalStatus, voteCount: Int, createdAt: Date) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.voteCount = voteCount
        self.createdAt = createdAt
    }

    public enum CodingKeys: String, CodingKey {
        case id, title, description, status, voteCount, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id          = try container.decode(String.self,              forKey: .id)
        title       = try container.decode(String.self,              forKey: .title)
        description = try container.decodeIfPresent(String.self,     forKey: .description)
        status      = try container.decode(JishuProposalStatus.self, forKey: .status)
        voteCount   = try container.decode(Int.self,                 forKey: .voteCount)

        let dateString = try container.decode(String.self, forKey: .createdAt)
        guard let date = Self.parseISO8601(dateString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt, in: container,
                debugDescription: "Cannot parse ISO 8601 date: \(dateString)"
            )
        }
        createdAt = date
    }

    // Handles both "2026-03-28T20:35:11.844Z" (with fractional seconds)
    // and "2026-03-28T20:35:11Z" (without).
    private static func parseISO8601(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }

        let withoutFractional = ISO8601DateFormatter()
        withoutFractional.formatOptions = [.withInternetDateTime]
        return withoutFractional.date(from: string)
    }
}

/// The review status of a feature proposal.
public enum JishuProposalStatus: String, Codable, Sendable {
    case open
    case planned
    case inProgress  = "in_progress"
    case shipped
    case rejected
}

// MARK: - Internal response wrappers

struct ProposalListResponse: Decodable {
    let proposals: [JishuProposal]
}

struct SingleProposalResponse: Decodable {
    let proposal: JishuProposal
}

struct VoteCountResponse: Decodable {
    let voteCount: Int
}

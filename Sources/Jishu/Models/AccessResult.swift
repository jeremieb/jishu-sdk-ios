import Foundation

public struct AccessResult: Sendable {
    public let granted: Bool
    public let grantId: String?
    public let matchType: MatchType
    public let expiresAt: Date?
    public let serverTime: Date
}

extension AccessResult: Decodable {}

public enum MatchType: String, Sendable, Decodable {
    case user
    case device
    case none
}

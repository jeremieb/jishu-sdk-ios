import Foundation

public enum JishuError: Error, Sendable {
    case notConfigured
    case invalidBaseURL
    case httpError(Int)
    case decodingFailed(any Error)
}

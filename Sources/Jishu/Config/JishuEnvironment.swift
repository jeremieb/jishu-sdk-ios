import Foundation

/// Identifies which Jishu backend the SDK should connect to.
public enum JishuEnvironment: Sendable, CustomStringConvertible {
    /// The live production backend at `https://jishu.page`. Default.
    case production
    /// The staging backend at `https://staging.jishu.page`.
    case staging

    /// The base URL for this environment.
    var baseURL: URL {
        switch self {
        case .production: URL(string: "https://jishu.page")!
        case .staging:    URL(string: "https://staging.jishu.page")!
        }
    }

    public var description: String {
        switch self {
        case .production: "production"
        case .staging:    "staging"
        }
    }
}

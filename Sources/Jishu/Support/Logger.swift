import Foundation

/// Controls the verbosity of Jishu SDK console output.
public enum JishuDebugLevel: Sendable {
    /// Prints only errors, prefixed with "‼️ Jishu -". This is the default.
    case `default`
    /// Prints all SDK activity (requests, responses, retries), prefixed with "📱 Jishu -".
    case verbose
}

struct JishuLogger: Sendable {
    let level: JishuDebugLevel

    /// Logs an error message. Always printed in both `.default` and `.verbose` modes.
    func error(_ message: @autoclosure () -> String) {
        switch level {
        case .default:
            print("‼️ Jishu - \(message())")
        case .verbose:
            print("📱 Jishu - \(message())")
        }
    }

    /// Logs a verbose message. Only printed in `.verbose` mode.
    func verbose(_ message: @autoclosure () -> String) {
        guard level == .verbose else { return }
        print("📱 Jishu - \(message())")
    }
}

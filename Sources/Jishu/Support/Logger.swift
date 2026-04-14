import Foundation

/// Controls the verbosity of Jishu SDK console output.
public enum JishuDebugLevel: Sendable {
    /// Prints only errors and retry attempts. This is the default.
    case `default`
    /// Prints all SDK activity: configuration, every request, response, retry, and error.
    case verbose
}

struct JishuLogger: Sendable {
    let level: JishuDebugLevel

    /// ❌  Always printed — error or unexpected condition.
    func error(_ message: @autoclosure () -> String) {
        print("❌ [Jishu] \(message())")
    }

    /// 🔄  Always printed — retry attempt.
    func retry(_ message: @autoclosure () -> String) {
        print("🔄 [Jishu] \(message())")
    }

    /// 🚀  Verbose only — outgoing network request.
    func request(method: String, url: String) {
        guard level == .verbose else { return }
        print("🚀 [Jishu] \(method) \(url)")
    }

    /// ✅ / ⚠️  Verbose only — received HTTP response.
    func response(status: Int, method: String, url: String) {
        guard level == .verbose else { return }
        let emoji = (200..<300).contains(status) ? "✅" : "⚠️"
        print("\(emoji) [Jishu] \(status) \(method) \(url)")
    }

    /// ⚙️  Verbose only — SDK configuration log.
    func configure(_ message: @autoclosure () -> String) {
        guard level == .verbose else { return }
        print("⚙️ [Jishu] \(message())")
    }

    /// 💬  Verbose only — general informational message.
    func info(_ message: @autoclosure () -> String) {
        guard level == .verbose else { return }
        print("💬 [Jishu] \(message())")
    }

    /// 📦  Verbose only — pretty-printed JSON response body.
    func responseBody(_ data: Data) {
        guard level == .verbose, !data.isEmpty else { return }
        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
            let string = String(data: pretty, encoding: .utf8)
        else { return }
        print("📦 [Jishu]\n\(string)")
    }
}

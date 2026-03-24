import Foundation

struct JishuLogger: Sendable {
    let isEnabled: Bool

    func debug(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("[Jishu] \(message())")
    }
}

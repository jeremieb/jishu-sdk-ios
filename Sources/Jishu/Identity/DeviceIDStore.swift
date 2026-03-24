import Foundation

enum DeviceIDStore {
    private static let key = "jishu.deviceID"

    /// Returns the persistent device ID, generating and storing one on first call.
    /// Pass a custom `UserDefaults` suite during testing to avoid polluting the standard suite.
    static func deviceID(from defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key) {
            return existing
        }
        let newID = UUID().uuidString
        defaults.set(newID, forKey: key)
        return newID
    }
}

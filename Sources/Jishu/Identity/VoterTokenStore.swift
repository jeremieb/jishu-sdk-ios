import Foundation

enum VoterTokenStore {
    private static let key = "jishu.voterToken"

    /// Returns a stable device-scoped voter token used for anonymous proposal submission and voting.
    /// Generated once on first call and persisted in `UserDefaults`.
    /// Pass a custom `UserDefaults` suite during testing to avoid polluting the standard suite.
    static func voterToken(from defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key) {
            return existing
        }
        let newToken = UUID().uuidString
        defaults.set(newToken, forKey: key)
        return newToken
    }
}

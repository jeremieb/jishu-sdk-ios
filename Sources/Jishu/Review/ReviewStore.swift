import Foundation

actor ReviewStore {
    private let defaults: UserDefaults

    private enum Key {
        static let installDate    = "jishu.review.installDate"
        static let launchCount    = "jishu.review.launchCount"
        static let lastPromptDate = "jishu.review.lastPromptDate"
        static let promptCount    = "jishu.review.promptCount"
        static let configCache    = "jishu.review.configCache"
        static let configCachedAt = "jishu.review.configCachedAt"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func namespacedKey(_ base: String, appId: String) -> String {
        "\(base).\(appId)"
    }

    func installDate(appId: String) -> Double {
        defaults.double(forKey: namespacedKey(Key.installDate, appId: appId))
    }

    func launchCount(appId: String) -> Int {
        defaults.integer(forKey: namespacedKey(Key.launchCount, appId: appId))
    }

    func lastPromptDate(appId: String) -> Double? {
        let v = defaults.double(forKey: namespacedKey(Key.lastPromptDate, appId: appId))
        return v > 0 ? v : nil
    }

    func promptCount(appId: String) -> Int {
        defaults.integer(forKey: namespacedKey(Key.promptCount, appId: appId))
    }

    func setInstallDateIfNeeded(appId: String) {
        let key = namespacedKey(Key.installDate, appId: appId)
        guard defaults.double(forKey: key) == 0 else { return }
        defaults.set(Date().timeIntervalSince1970, forKey: key)
    }

    func incrementLaunchCount(appId: String) {
        let key = namespacedKey(Key.launchCount, appId: appId)
        defaults.set(launchCount(appId: appId) + 1, forKey: key)
    }

    func recordPromptShown(appId: String) {
        defaults.set(Date().timeIntervalSince1970, forKey: namespacedKey(Key.lastPromptDate, appId: appId))
        defaults.set(promptCount(appId: appId) + 1, forKey: namespacedKey(Key.promptCount, appId: appId))
    }

    /// Returns cached config if it is within the 1-hour TTL.
    func cachedConfig(appId: String) -> ReviewConfig? {
        let cachedAt = defaults.double(forKey: namespacedKey(Key.configCachedAt, appId: appId))
        guard cachedAt > 0 else { return nil }
        guard Date().timeIntervalSince1970 - cachedAt < 3600 else { return nil }
        guard let data = defaults.data(forKey: namespacedKey(Key.configCache, appId: appId)) else { return nil }
        return try? JSONDecoder().decode(ReviewConfig.self, from: data)
    }

    func cacheConfig(_ config: ReviewConfig, appId: String) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: namespacedKey(Key.configCache, appId: appId))
        defaults.set(Date().timeIntervalSince1970, forKey: namespacedKey(Key.configCachedAt, appId: appId))
    }

    func invalidateConfigCache(appId: String) {
        defaults.removeObject(forKey: namespacedKey(Key.configCache, appId: appId))
        defaults.removeObject(forKey: namespacedKey(Key.configCachedAt, appId: appId))
    }
}

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

    var installDate: Double {
        defaults.double(forKey: Key.installDate)
    }

    var launchCount: Int {
        defaults.integer(forKey: Key.launchCount)
    }

    var lastPromptDate: Double? {
        let v = defaults.double(forKey: Key.lastPromptDate)
        return v > 0 ? v : nil
    }

    var promptCount: Int {
        defaults.integer(forKey: Key.promptCount)
    }

    func setInstallDateIfNeeded() {
        guard defaults.double(forKey: Key.installDate) == 0 else { return }
        defaults.set(Date().timeIntervalSince1970, forKey: Key.installDate)
    }

    func incrementLaunchCount() {
        defaults.set(launchCount + 1, forKey: Key.launchCount)
    }

    func recordPromptShown() {
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lastPromptDate)
        defaults.set(promptCount + 1, forKey: Key.promptCount)
    }

    /// Returns cached config if it is within the 1-hour TTL.
    func cachedConfig() -> ReviewConfig? {
        let cachedAt = defaults.double(forKey: Key.configCachedAt)
        guard cachedAt > 0 else { return nil }
        guard Date().timeIntervalSince1970 - cachedAt < 3600 else { return nil }
        guard let data = defaults.data(forKey: Key.configCache) else { return nil }
        return try? JSONDecoder().decode(ReviewConfig.self, from: data)
    }

    func cacheConfig(_ config: ReviewConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Key.configCache)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.configCachedAt)
    }
}

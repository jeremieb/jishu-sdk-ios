import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Jishu promo access SDK.
///
/// Call `configure(baseURL:apiToken:appId:)` once at app startup before using any other API.
public enum Jishu {
    /// The current SDK version.
    public static let version = "0.1.5"

    private nonisolated(unsafe) static var _configuration: JishuConfiguration?
    private nonisolated(unsafe) static var _client: JishuClient?
    private static let _cache = AccessCache()
    private static let _reviewStore = ReviewStore()

    /// Optional custom UI handler for the review prompt.
    ///
    /// Assign before calling ``trackLaunch(in:)``. When `nil`, the SDK presents a
    /// `UIAlertController`-based star rating dialog.
    /// - Note: Declared `nonisolated(unsafe)` to match `_configuration` and `_client`
    ///   (Swift 6 strict concurrency — caller is responsible for setting this once at startup).
    nonisolated(unsafe) public static weak var reviewUIHandler: (any JishuReviewUIHandler)?

    /// Configure the SDK. Must be called before `checkAccess` or reading `displayUserID` in production.
    ///
    /// - Parameters:
    ///   - server: Which Jishu backend to connect to. Defaults to `.production`.
    ///   - apiToken: Bearer token issued from Account → API access.
    ///   - appId: The app identifier registered in the Jishu dashboard.
    ///   - environment: Optional release-channel hint sent with entitlement checks
    ///     (`"production"`, `"staging"`, `"testflight"`, `"internal"`).
    ///   - debugLevel: Controls console output verbosity. `.default` prints errors and retries only;
    ///     `.verbose` prints all SDK activity. Defaults to `.default`.
    public static func configure(
        server: JishuEnvironment = .production,
        apiToken: String,
        appId: String,
        environment: String? = nil,
        debugLevel: JishuDebugLevel = .default
    ) {
        let config = JishuConfiguration(
            server: server,
            apiToken: apiToken,
            appId: appId,
            environment: environment,
            debugLevel: debugLevel
        )
        _configuration = config
        _client = JishuClient(configuration: config)
        JishuLogger(level: debugLevel).configure(
            "Configured — server: \(server) | appId: \(appId) | debugLevel: \(debugLevel)"
        )
    }

    /// A stable device-scoped identifier exposed to app developers.
    ///
    /// Generated once and stored in `UserDefaults`. Reinstalling the app produces a new ID,
    /// which invalidates any grant tied to the old ID. Prefer passing `externalUserId` when
    /// the user is authenticated.
    public static var displayUserID: String {
        DeviceIDStore.deviceID()
    }

    /// Submit a contact message from the app user.
    ///
    /// The message is associated with the `appId` supplied to `configure(baseURL:apiToken:appId:)`.
    /// No authentication is required — the endpoint is public and rate-limited by IP.
    ///
    /// - Parameter message: The contact message to send.
    /// - Throws: `JishuError.notConfigured` if `configure` has not been called.
    public static func sendContactMessage(_ message: ContactMessage) async throws {
        guard let client = _client, let config = _configuration else {
            throw JishuError.notConfigured
        }
        try await client.sendContactMessage(message, appId: config.appId)
    }

    /// Fetch open feature proposals for the configured app, sorted by votes descending.
    ///
    /// This is a public endpoint — no API token is required on the server side, but `configure` must
    /// still be called so the SDK knows the `baseURL` and `appId`.
    ///
    /// - Returns: An array of `JishuProposal` values sorted by vote count.
    /// - Throws: `JishuError.notConfigured` if `configure` has not been called.
    public static func fetchProposals() async throws -> [JishuProposal] {
        guard let client = _client, let config = _configuration else {
            throw JishuError.notConfigured
        }
        return try await client.fetchProposals(appId: config.appId)
    }

    /// Submit a new feature proposal on behalf of the current device.
    ///
    /// Uses a stable, device-scoped voter token stored in `UserDefaults`. The endpoint is public
    /// and rate-limited (3 proposals per hour per IP per app).
    ///
    /// - Parameters:
    ///   - title: A short, descriptive title (required, max 255 characters).
    ///   - description: Optional longer description (max 2 000 characters).
    /// - Returns: The newly created `JishuProposal`.
    /// - Throws: `JishuError.notConfigured`, or `JishuError.httpError(429)` when rate-limited.
    public static func submitProposal(title: String, description: String? = nil) async throws -> JishuProposal {
        guard let client = _client, let config = _configuration else {
            throw JishuError.notConfigured
        }
        return try await client.submitProposal(
            appId: config.appId,
            title: title,
            description: description,
            voterToken: VoterTokenStore.voterToken()
        )
    }

    /// Upvote a feature proposal. Idempotent — voting twice from the same device has no effect.
    ///
    /// - Parameter proposal: The `JishuProposal` to vote on.
    /// - Returns: The updated vote count.
    /// - Throws: `JishuError.notConfigured` if `configure` has not been called.
    public static func vote(on proposal: JishuProposal) async throws -> Int {
        guard let client = _client, let config = _configuration else {
            throw JishuError.notConfigured
        }
        return try await client.voteOnProposal(
            appId: config.appId,
            proposalId: proposal.id,
            voterToken: VoterTokenStore.voterToken()
        )
    }

    /// Check whether the current user or device has an active Jishu promo grant.
    ///
    /// - Parameter externalUserId: Stable ID from your own auth system. Pass `nil` to fall back
    ///   to the device-scoped `displayUserID`.
    /// - Returns: An `AccessResult` describing the grant state.
    /// - Throws: `JishuError.notConfigured` if `configure` has not been called.
    public static func checkAccess(externalUserId: String? = nil) async throws -> AccessResult {
        guard let client = _client else {
            throw JishuError.notConfigured
        }
        let deviceId = DeviceIDStore.deviceID()
        let cacheKey = externalUserId ?? deviceId

        if let cached = await _cache.get(key: cacheKey) {
            return cached
        }

        let result = try await client.checkAccess(externalUserId: externalUserId, deviceId: deviceId)
        await _cache.set(key: cacheKey, result: result)
        return result
    }

#if canImport(UIKit)
    /// Track a cold app launch and, when `triggerMode` is `"auto"`, show the review prompt
    /// if eligibility conditions are met.
    ///
    /// Call once per cold start — **not** from `applicationDidBecomeActive` or
    /// `sceneDidBecomeActive`, which fire on every foreground transition.
    /// Recommended placement: `application(_:didFinishLaunchingWithOptions:)` in `AppDelegate`,
    /// or a `.task` modifier scoped to the root scene guarded against re-entry.
    ///
    /// - Parameter scene: The active `UIWindowScene`, used to present the prompt and to call
    ///   `SKStoreReviewController.requestReview(in:)`. Pass `nil` to skip native review.
    @MainActor
    public static func trackLaunch(in scene: UIWindowScene? = nil) async {
        guard let client = _client, let config = _configuration else { return }
        await _reviewStore.setInstallDateIfNeeded()
        await _reviewStore.incrementLaunchCount()

        guard let reviewConfig = try? await client.fetchReviewConfig(appId: config.appId, store: _reviewStore),
              reviewConfig.triggerMode == "auto" else { return }

        guard await JishuReview.isEligible(config: reviewConfig, store: _reviewStore) else { return }

        await JishuReview.runPromptFlow(
            config: reviewConfig,
            store: _reviewStore,
            client: client,
            appId: config.appId,
            uiHandler: reviewUIHandler,
            scene: scene
        )
    }

    /// Manually trigger the review flow at a meaningful moment in your app.
    ///
    /// Always records the launch (increments launch count and sets install date on first call).
    /// The SDK still respects `cooldownDays` and `maxPromptsPerDevice`.
    /// Use this when `triggerMode` is `"manual"`.
    ///
    /// - Parameter scene: The active `UIWindowScene`.
    /// - Returns: `true` if the prompt was shown.
    @MainActor
    @discardableResult
    public static func requestReviewIfEligible(in scene: UIWindowScene? = nil) async -> Bool {
        guard let client = _client, let config = _configuration else {
            JishuLogger(level: .default).error("requestReviewIfEligible called before configure()")
            return false
        }
        let log = JishuLogger(level: config.debugLevel)

        // Always record the launch — even in manual mode
        await _reviewStore.setInstallDateIfNeeded()
        await _reviewStore.incrementLaunchCount()

        // Bypass the cache for manual triggers — the developer is explicitly requesting the prompt,
        // so always fetch fresh config to pick up any dashboard changes made since last launch.
        await _reviewStore.invalidateConfigCache()

        // Fetch config; fall back to defaults so a network hiccup never silently blocks a manual trigger
        let reviewConfig: ReviewConfig
        do {
            reviewConfig = try await client.fetchReviewConfig(appId: config.appId, store: _reviewStore)
        } catch {
            log.info("Could not fetch review config (\(error.localizedDescription)) — using defaults")
            reviewConfig = .manualFallback
        }

        // In manual mode skip launch/day conditions — developer chose the moment
        guard reviewConfig.enabled else {
            log.info("Review prompt is disabled in dashboard config")
            return false
        }
        let promptCount = await _reviewStore.promptCount
        guard promptCount < reviewConfig.maxPromptsPerDevice else {
            log.info("Review prompt skipped — maxPromptsPerDevice (\(reviewConfig.maxPromptsPerDevice)) reached")
            return false
        }
        if let lastInterval = await _reviewStore.lastPromptDate {
            let daysSince = Calendar.current.dateComponents(
                [.day],
                from: Date(timeIntervalSince1970: lastInterval),
                to: Date()
            ).day ?? 0
            guard daysSince >= reviewConfig.cooldownDays else {
                log.info("Review prompt skipped — cooldown active (\(daysSince)/\(reviewConfig.cooldownDays) days elapsed)")
                return false
            }
        }

        await JishuReview.runPromptFlow(
            config: reviewConfig,
            store: _reviewStore,
            client: client,
            appId: config.appId,
            uiHandler: reviewUIHandler,
            scene: scene
        )
        return true
    }
#endif
}

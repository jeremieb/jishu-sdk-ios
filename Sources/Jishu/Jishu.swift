import Foundation

/// Jishu promo access SDK.
///
/// Call `configure(baseURL:apiToken:appId:)` once at app startup before using any other API.
public enum Jishu {
    /// The current SDK version.
    public static let version = "1.1.0"

    private nonisolated(unsafe) static var _configuration: JishuConfiguration?
    private nonisolated(unsafe) static var _client: JishuClient?
    private static let _cache = AccessCache()

    /// Configure the SDK. Must be called before `checkAccess` or reading `displayUserID` in production.
    ///
    /// - Parameters:
    ///   - baseURL: Root origin only, e.g. `https://jishu.page`. Must not contain a path component.
    ///   - apiToken: Bearer token issued from Account → API access.
    ///   - appId: The app identifier registered in the Jishu dashboard.
    ///   - environment: Optional environment override (`"production"`, `"staging"`, `"testflight"`, `"internal"`).
    ///   - debugLevel: Controls console output verbosity. `.default` prints errors only; `.verbose` prints all SDK activity. Defaults to `.default`.
    public static func configure(
        baseURL: URL,
        apiToken: String,
        appId: String,
        environment: String? = nil,
        debugLevel: JishuDebugLevel = .default
    ) {
        let pathComponents = baseURL.pathComponents.filter { $0 != "/" }
        precondition(
            pathComponents.isEmpty,
            "[Jishu] baseURL must be a root origin with no path components. Received: \(baseURL.absoluteString)"
        )
        let config = JishuConfiguration(
            baseURL: baseURL,
            apiToken: apiToken,
            appId: appId,
            environment: environment,
            debugLevel: debugLevel
        )
        _configuration = config
        _client = JishuClient(configuration: config)
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
}

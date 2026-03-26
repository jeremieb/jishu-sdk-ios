import Foundation

/// Jishu promo access SDK.
///
/// Call `configure(baseURL:apiToken:appId:)` once at app startup before using any other API.
public enum Jishu {
    /// The current SDK version.
    public static let version = "1.0.0"

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
    ///   - enableDebugLogs: When `true`, emits debug output to stdout. Defaults to `false`.
    public static func configure(
        baseURL: URL,
        apiToken: String,
        appId: String,
        environment: String? = nil,
        enableDebugLogs: Bool = false
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
            enableDebugLogs: enableDebugLogs
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

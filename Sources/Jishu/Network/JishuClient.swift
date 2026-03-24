import Foundation

struct JishuClient: Sendable {
    private let configuration: JishuConfiguration
    private let session: URLSession
    private let logger: JishuLogger

    init(configuration: JishuConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10
            self.session = URLSession(configuration: config)
        }
        self.logger = JishuLogger(isEnabled: configuration.enableDebugLogs)
    }

    func checkAccess(externalUserId: String?, deviceId: String) async throws -> AccessResult {
        let request = try buildRequest(externalUserId: externalUserId, deviceId: deviceId)
        return try await perform(request, retriesLeft: 1)
    }

    // MARK: - Private

    private func perform(_ request: URLRequest, retriesLeft: Int) async throws -> AccessResult {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw JishuError.invalidBaseURL
            }
            logger.debug("HTTP \(http.statusCode)")

            switch http.statusCode {
            case 200:
                return try decode(data)
            case 400..<500:
                throw JishuError.httpError(http.statusCode)
            case 500...:
                if retriesLeft > 0 {
                    logger.debug("Retrying after \(http.statusCode)")
                    return try await perform(request, retriesLeft: retriesLeft - 1)
                }
                throw JishuError.httpError(http.statusCode)
            default:
                throw JishuError.httpError(http.statusCode)
            }
        } catch let error as JishuError {
            throw error
        } catch {
            if retriesLeft > 0 {
                logger.debug("Retrying after transport error: \(error.localizedDescription)")
                return try await perform(request, retriesLeft: retriesLeft - 1)
            }
            throw error
        }
    }

    private func buildRequest(externalUserId: String?, deviceId: String) throws -> URLRequest {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw JishuError.invalidBaseURL
        }
        components.path = "/api/v1/mobile/entitlements/check"
        guard let url = components.url else {
            throw JishuError.invalidBaseURL
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = EntitlementCheckRequest(
            appId: configuration.appId,
            externalUserId: externalUserId,
            deviceId: deviceId,
            environment: configuration.environment
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func decode(_ data: Data) throws -> AccessResult {
        do {
            return try Self.decoder.decode(AccessResult.self, from: data)
        } catch {
            throw JishuError.decodingFailed(error)
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        nonisolated(unsafe) let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot parse date: \(string)"
            )
        }
        return d
    }()
}

// MARK: - Request body

private struct EntitlementCheckRequest: Encodable {
    let appId: String
    let platform: String = "ios"
    let externalUserId: String?
    let deviceId: String
    let environment: String?

    private enum CodingKeys: String, CodingKey {
        case appId, platform, externalUserId, deviceId, environment
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(appId, forKey: .appId)
        try c.encode(platform, forKey: .platform)
        try c.encode(deviceId, forKey: .deviceId)
        try c.encodeIfPresent(externalUserId, forKey: .externalUserId)
        try c.encodeIfPresent(environment, forKey: .environment)
    }
}

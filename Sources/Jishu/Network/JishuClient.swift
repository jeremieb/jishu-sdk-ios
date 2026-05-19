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
        self.logger = JishuLogger(level: configuration.debugLevel)
    }

    func checkAccess(externalUserId: String?, deviceId: String) async throws -> AccessResult {
        let request = try buildRequest(externalUserId: externalUserId, deviceId: deviceId)
        return try await perform(request, retriesLeft: 1)
    }

    func sendContactMessage(_ message: ContactMessage, appId: String) async throws {
        let sanitized = message.sanitized(deviceUserID: DeviceIDStore.deviceID())
        let request = try buildContactRequest(message: sanitized, appId: appId)
        try await performContact(request, retriesLeft: 1)
    }

    func fetchProposals(appId: String) async throws -> [JishuProposal] {
        let request = try buildProposalsRequest(appId: appId)
        return try await performDecoding(request, retriesLeft: 1) { data in
            try Self.plainDecoder.decode(ProposalListResponse.self, from: data).proposals
        }
    }

    func submitProposal(appId: String, title: String, description: String?, voterToken: String) async throws -> JishuProposal {
        let request = try buildSubmitProposalRequest(appId: appId, title: title, description: description, voterToken: voterToken)
        return try await performDecoding(request, retriesLeft: 0) { data in
            try Self.plainDecoder.decode(SingleProposalResponse.self, from: data).proposal
        }
    }

    func voteOnProposal(appId: String, proposalId: String, voterToken: String) async throws -> Int {
        let request = try buildVoteRequest(appId: appId, proposalId: proposalId, voterToken: voterToken)
        return try await performDecoding(request, retriesLeft: 0) { data in
            try Self.plainDecoder.decode(VoteCountResponse.self, from: data).voteCount
        }
    }

    // MARK: - Review

    /// Fetch review config, using a 1-hour in-process TTL backed by ReviewStore.
    func fetchReviewConfig(appId: String, store: ReviewStore) async throws -> ReviewConfig {
        if let cached = await store.cachedConfig(appId: appId) {
            return cached
        }
        let request = try buildReviewConfigRequest(appId: appId)
        let config = try await performDecoding(request, retriesLeft: 1) { data in
            try Self.plainDecoder.decode(ReviewConfig.self, from: data)
        }
        await store.cacheConfig(config, appId: appId)
        return config
    }

    /// Fire-and-forget event log. Swallows all errors.
    func logReviewEvent(appId: String, eventType: String, platform: String, rating: Int?, feedback: String? = nil) async {
        do {
            let request = try buildReviewEventRequest(appId: appId, eventType: eventType, platform: platform, rating: rating, feedback: feedback)
            try await performContact(request, retriesLeft: 0)
        } catch {
            logger.error("Review event error (\(eventType)): \(error.localizedDescription)")
        }
    }

    /// Fire-and-forget feedback submission. Swallows all errors.
    func sendReviewFeedback(appId: String, body: String) async {
        do {
            let request = try buildReviewFeedbackRequest(appId: appId, body: body)
            try await performContact(request, retriesLeft: 1)
        } catch {
            logger.error("Review feedback error: \(error.localizedDescription)")
        }
    }

    // MARK: - Private review builders

    private func buildReviewConfigRequest(appId: String) throws -> URLRequest {
        let base = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedAppId = appId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? appId
        guard let url = URL(string: "\(base)/api/apps/\(encodedAppId)/review/config") else {
            throw JishuError.invalidBaseURL
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        return request
    }

    private func buildReviewEventRequest(appId: String, eventType: String, platform: String, rating: Int?, feedback: String?) throws -> URLRequest {
        let base = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedAppId = appId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? appId
        guard let url = URL(string: "\(base)/api/apps/\(encodedAppId)/review/events") else {
            throw JishuError.invalidBaseURL
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ReviewEventBody(eventType: eventType, platform: platform, rating: rating, feedback: feedback))
        return request
    }

    private func buildReviewFeedbackRequest(appId: String, body: String) throws -> URLRequest {
        let base = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedAppId = appId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? appId
        guard let url = URL(string: "\(base)/api/apps/\(encodedAppId)/review/feedback") else {
            throw JishuError.invalidBaseURL
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let meta = deviceMetaInfo()
        request.httpBody = try JSONEncoder().encode(ReviewFeedbackBody(
            body: body,
            platform: currentPlatform(),
            osName: meta.osName,
            osVersion: meta.osVersion,
            deviceName: meta.deviceName
        ))
        return request
    }

    // MARK: - Private

    private func perform(_ request: URLRequest, retriesLeft: Int) async throws -> AccessResult {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? ""
        logger.request(method: method, url: url)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw JishuError.invalidBaseURL
            }
            logger.response(status: http.statusCode, method: method, url: url)

            logger.responseBody(data)
            switch http.statusCode {
            case 200:
                return try decode(data)
            case 400..<500:
                logger.error("HTTP \(http.statusCode) — \(url)")
                throw JishuError.httpError(http.statusCode)
            case 500...:
                if retriesLeft > 0 {
                    logger.retry("Server error \(http.statusCode), retrying \(url)")
                    return try await perform(request, retriesLeft: retriesLeft - 1)
                }
                logger.error("Server error \(http.statusCode) — no retries left")
                throw JishuError.httpError(http.statusCode)
            default:
                logger.error("Unexpected status \(http.statusCode) — \(url)")
                throw JishuError.httpError(http.statusCode)
            }
        } catch let error as JishuError {
            throw error
        } catch {
            if retriesLeft > 0 {
                logger.retry("Transport error, retrying \(url): \(error.localizedDescription)")
                return try await perform(request, retriesLeft: retriesLeft - 1)
            }
            logger.error("Transport error: \(error.localizedDescription)")
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

    private func performContact(_ request: URLRequest, retriesLeft: Int) async throws {
        let method = request.httpMethod ?? "POST"
        let url = request.url?.absoluteString ?? ""
        logger.request(method: method, url: url)
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw JishuError.invalidBaseURL
            }
            logger.response(status: http.statusCode, method: method, url: url)
            switch http.statusCode {
            case 200, 201:
                return
            case 400..<500:
                logger.error("HTTP \(http.statusCode) — \(url)")
                throw JishuError.httpError(http.statusCode)
            case 500...:
                if retriesLeft > 0 {
                    logger.retry("Server error \(http.statusCode), retrying \(url)")
                    return try await performContact(request, retriesLeft: retriesLeft - 1)
                }
                logger.error("Server error \(http.statusCode) — no retries left")
                throw JishuError.httpError(http.statusCode)
            default:
                logger.error("Unexpected status \(http.statusCode) — \(url)")
                throw JishuError.httpError(http.statusCode)
            }
        } catch let error as JishuError {
            throw error
        } catch {
            if retriesLeft > 0 {
                logger.retry("Transport error, retrying \(url): \(error.localizedDescription)")
                return try await performContact(request, retriesLeft: retriesLeft - 1)
            }
            logger.error("Transport error: \(error.localizedDescription)")
            throw error
        }
    }

    private func buildContactRequest(message: ContactMessage, appId: String) throws -> URLRequest {
        let base = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedAppId = appId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? appId
        guard let url = URL(string: "\(base)/api/apps/\(encodedAppId)/contact") else {
            throw JishuError.invalidBaseURL
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let meta = deviceMetaInfo()
        let body = ContactMessageBody(
            senderName: message.senderName,
            senderEmail: message.senderEmail,
            subject: message.subject,
            body: message.body,
            userId: message.userId,// filled by sanitized(deviceUserID:)
            platform: currentPlatform(),
            osName: meta.osName,
            osVersion: meta.osVersion,
            deviceName: meta.deviceName
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    // Generic perform+decode helper for feedback endpoints (public, no auth).
    private func performDecoding<T: Sendable>(
        _ request: URLRequest,
        retriesLeft: Int,
        decode: (Data) throws -> T
    ) async throws -> T {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? ""
        logger.request(method: method, url: url)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw JishuError.invalidBaseURL
            }
            logger.response(status: http.statusCode, method: method, url: url)
            logger.responseBody(data)
            switch http.statusCode {
            case 200, 201:
                do { return try decode(data) } catch { throw JishuError.decodingFailed(error) }
            case 400..<500:
                logger.error("HTTP \(http.statusCode) — \(url)")
                throw JishuError.httpError(http.statusCode)
            case 500...:
                if retriesLeft > 0 {
                    logger.retry("Server error \(http.statusCode), retrying \(url)")
                    return try await performDecoding(request, retriesLeft: retriesLeft - 1, decode: decode)
                }
                logger.error("Server error \(http.statusCode) — no retries left")
                throw JishuError.httpError(http.statusCode)
            default:
                logger.error("Unexpected status \(http.statusCode) — \(url)")
                throw JishuError.httpError(http.statusCode)
            }
        } catch let error as JishuError {
            throw error
        } catch {
            if retriesLeft > 0 {
                logger.retry("Transport error, retrying \(url): \(error.localizedDescription)")
                return try await performDecoding(request, retriesLeft: retriesLeft - 1, decode: decode)
            }
            logger.error("Transport error: \(error.localizedDescription)")
            throw error
        }
    }

    private func buildProposalsRequest(appId: String) throws -> URLRequest {
        let base = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedAppId = appId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? appId
        guard let url = URL(string: "\(base)/api/apps/\(encodedAppId)/proposals?sort=votes&status=open") else {
            throw JishuError.invalidBaseURL
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        return request
    }

    private func buildSubmitProposalRequest(appId: String, title: String, description: String?, voterToken: String) throws -> URLRequest {
        let base = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedAppId = appId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? appId
        guard let url = URL(string: "\(base)/api/apps/\(encodedAppId)/proposals") else {
            throw JishuError.invalidBaseURL
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let meta = deviceMetaInfo()
        request.httpBody = try JSONEncoder().encode(
            SubmitProposalBody(
                title: title,
                description: description,
                voterToken: voterToken,
                osName: meta.osName,
                osVersion: meta.osVersion,
                deviceName: meta.deviceName
            )
        )
        return request
    }

    private func buildVoteRequest(appId: String, proposalId: String, voterToken: String) throws -> URLRequest {
        let base = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedAppId      = appId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? appId
        let encodedProposalId = proposalId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? proposalId
        guard let url = URL(string: "\(base)/api/apps/\(encodedAppId)/proposals/\(encodedProposalId)/vote") else {
            throw JishuError.invalidBaseURL
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let meta = deviceMetaInfo()
        request.httpBody = try JSONEncoder().encode(
            VoteBody(
                voterToken: voterToken,
                osName: meta.osName,
                osVersion: meta.osVersion,
                deviceName: meta.deviceName
            )
        )
        return request
    }

    private static let plainDecoder = JSONDecoder()

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

// MARK: - Request bodies

private struct EntitlementCheckRequest: Encodable {
    let appId: String
    let platform: String = currentPlatform()
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

private struct SubmitProposalBody: Encodable {
    let title: String
    let description: String?
    let voterToken: String
    let osName: String
    let osVersion: String
    let deviceName: String
    enum CodingKeys: String, CodingKey {
        case title, description, osName, osVersion, deviceName
        case voterToken = "voter_token"
    }
}

private struct VoteBody: Encodable {
    let voterToken: String
    let osName: String
    let osVersion: String
    let deviceName: String
    enum CodingKeys: String, CodingKey {
        case osName, osVersion, deviceName
        case voterToken = "voter_token"
    }
}

private struct ContactMessageBody: Encodable {
    let senderName: String?
    let senderEmail: String
    let subject: String?
    let body: String
    let userId: String?
    let platform: String
    let osName: String
    let osVersion: String
    let deviceName: String
}

private struct ReviewEventBody: Encodable {
    let eventType: String
    let platform: String
    let rating: Int?
    let feedback: String?
}

private struct ReviewFeedbackBody: Encodable {
    let body: String
    let platform: String
    let osName: String
    let osVersion: String
    let deviceName: String
}

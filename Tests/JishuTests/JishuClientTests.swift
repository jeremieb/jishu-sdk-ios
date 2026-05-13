import Testing
import Foundation
@testable import Jishu

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeClient(enableDebugLogs: Bool = false) -> JishuClient {
    let config = JishuConfiguration(
        server: .staging,
        apiToken: "test_token",
        appId: "app_test",
        environment: "staging",
        debugLevel: enableDebugLogs ? .verbose : .default
    )
    return JishuClient(configuration: config, session: makeSession())
}

private let successJSON = """
{
  "granted": true,
  "grantId": "grant_abc",
  "matchType": "user",
  "expiresAt": "2026-04-24T12:00:00.000Z",
  "serverTime": "2026-03-24T12:00:00.000Z"
}
""".data(using: .utf8)!

private let reviewConfigJSON = """
{
  "enabled": true,
  "triggerMode": "manual",
  "minLaunches": 1,
  "minDaysSinceInstall": 0,
  "triggerLogic": "AND",
  "cooldownDays": 7,
  "maxPromptsPerDevice": 2,
  "promptTitle": "Enjoying the app?",
  "promptQuestion": "Tell us what you think.",
  "ratingThreshold": 4,
  "feedbackPrompt": "What could we improve?",
  "captureFeedbackOnNegative": true
}
""".data(using: .utf8)!

private func makeHTTPResponse(status: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://staging.jishu.page")!,
        statusCode: status,
        httpVersion: nil,
        headerFields: nil
    )!
}

private func requestBodyData(from request: URLRequest?) throws -> Data {
    let request = try #require(request)
    if let body = request.httpBody {
        return body
    }
    if let stream = request.httpBodyStream {
        return try readBody(from: stream)
    }
    throw NSError(domain: "JishuClientTests", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Expected request body data"
    ])
}

private func readBody(from stream: InputStream) throws -> Data {
    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: bufferSize)
        if count < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeRawData)
        }
        if count == 0 {
            break
        }
        data.append(buffer, count: count)
    }

    return data
}

// MARK: - Tests

@Suite("JishuClient", .serialized)
struct JishuClientTests {
    @Test("Returns AccessResult on 200 response")
    func returns200Result() async throws {
        MockURLProtocol.requestHandler = { _ in
            (makeHTTPResponse(status: 200), successJSON)
        }
        let client = makeClient()
        let result = try await client.checkAccess(externalUserId: "user_1", deviceId: "device_1")
        #expect(result.granted == true)
        #expect(result.grantId == "grant_abc")
        #expect(result.matchType == .user)
    }

    @Test("Throws httpError on 401 without retrying")
    func throws401WithoutRetry() async throws {
        var callCount = 0
        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            return (makeHTTPResponse(status: 401), Data())
        }
        let client = makeClient()
        do {
            _ = try await client.checkAccess(externalUserId: nil, deviceId: "device_1")
            Issue.record("Expected throw")
        } catch JishuError.httpError(let code) {
            #expect(code == 401)
            #expect(callCount == 1)
        }
    }

    @Test("Retries once on 500 then throws")
    func retries500Once() async throws {
        var callCount = 0
        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            return (makeHTTPResponse(status: 500), Data())
        }
        let client = makeClient()
        do {
            _ = try await client.checkAccess(externalUserId: nil, deviceId: "device_1")
            Issue.record("Expected throw")
        } catch JishuError.httpError(let code) {
            #expect(code == 500)
            #expect(callCount == 2)
        }
    }

    @Test("Succeeds on second attempt after 500")
    func succeedsOnRetryAfter500() async throws {
        var callCount = 0
        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return (makeHTTPResponse(status: 500), Data())
            }
            return (makeHTTPResponse(status: 200), successJSON)
        }
        let client = makeClient()
        let result = try await client.checkAccess(externalUserId: "user_1", deviceId: "device_1")
        #expect(result.granted == true)
        #expect(callCount == 2)
    }

    @Test("Request includes Authorization header")
    func requestIncludesAuthHeader() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (makeHTTPResponse(status: 200), successJSON)
        }
        let client = makeClient()
        _ = try await client.checkAccess(externalUserId: nil, deviceId: "device_1")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test_token")
    }

    @Test("submitProposal encodes device metadata in request body")
    func submitProposalEncodesDeviceMetadata() async throws {
        var capturedRequest: URLRequest?
        let responseJSON = """
        {
          "proposal": {
            "id": "prop_new",
            "title": "Dark mode",
            "description": "Please add dark mode",
            "status": "open",
            "voteCount": 1,
            "createdAt": "2026-03-28T20:35:11.844Z"
          }
        }
        """.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (makeHTTPResponse(status: 201), responseJSON)
        }
        let client = makeClient()
        _ = try await client.submitProposal(
            appId: "app_test",
            title: "Dark mode",
            description: "Please add dark mode",
            voterToken: "vote_token_123"
        )
        let request = try #require(capturedRequest)
        #expect(request.url?.path == "/api/apps/app_test/proposals")
        #expect(request.httpMethod == "POST")
        let bodyData = try requestBodyData(from: capturedRequest)
        struct DecodedBody: Decodable {
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
        let decoded = try JSONDecoder().decode(DecodedBody.self, from: bodyData)
        #expect(decoded.title == "Dark mode")
        #expect(decoded.description == "Please add dark mode")
        #expect(decoded.voterToken == "vote_token_123")
        #expect(decoded.osName.isEmpty == false)
        #expect(decoded.osVersion.isEmpty == false)
        #expect(decoded.deviceName.isEmpty == false)
    }


    @Test("voteOnProposal encodes device metadata in request body")
    func voteOnProposalEncodesDeviceMetadata() async throws {
        var capturedRequest: URLRequest?
        let responseJSON = """
        {
          "vote_count": 7
        }
        """.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (makeHTTPResponse(status: 200), responseJSON)
        }
        let client = makeClient()
        _ = try await client.voteOnProposal(
            appId: "app_test",
            proposalId: "prop_123",
            voterToken: "vote_token_456"
        )
        let request = try #require(capturedRequest)
        #expect(request.url?.path == "/api/apps/app_test/proposals/prop_123/vote")
        #expect(request.httpMethod == "POST")
        let bodyData = try requestBodyData(from: capturedRequest)
        struct DecodedBody: Decodable {
            let voterToken: String
            let osName: String
            let osVersion: String
            let deviceName: String
            enum CodingKeys: String, CodingKey {
                case osName, osVersion, deviceName
                case voterToken = "voter_token"
            }
        }
        let decoded = try JSONDecoder().decode(DecodedBody.self, from: bodyData)
        #expect(decoded.voterToken == "vote_token_456")
        #expect(decoded.osName.isEmpty == false)
        #expect(decoded.osVersion.isEmpty == false)
        #expect(decoded.deviceName.isEmpty == false)
    }

    @Test("fetchReviewConfig uses cached value for the same app")
    func fetchReviewConfigUsesCachedValueForSameApp() async throws {
        var callCount = 0
        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            return (makeHTTPResponse(status: 200), reviewConfigJSON)
        }
        let client = makeClient()
        let suiteName = "JishuClientTests.fetchReviewConfigUsesCachedValueForSameApp"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ReviewStore(defaults: defaults)

        _ = try await client.fetchReviewConfig(appId: "app_one", store: store)
        _ = try await client.fetchReviewConfig(appId: "app_one", store: store)

        #expect(callCount == 1)
    }

    @Test("fetchReviewConfig cache is isolated per app id")
    func fetchReviewConfigCacheIsIsolatedPerAppId() async throws {
        var requestedPaths: [String] = []
        MockURLProtocol.requestHandler = { request in
            requestedPaths.append(request.url?.path ?? "")
            return (makeHTTPResponse(status: 200), reviewConfigJSON)
        }
        let client = makeClient()
        let suiteName = "JishuClientTests.fetchReviewConfigCacheIsIsolatedPerAppId"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ReviewStore(defaults: defaults)

        _ = try await client.fetchReviewConfig(appId: "app_one", store: store)
        _ = try await client.fetchReviewConfig(appId: "app_two", store: store)

        #expect(requestedPaths == ["/api/apps/app_one/review/config", "/api/apps/app_two/review/config"])
    }

}

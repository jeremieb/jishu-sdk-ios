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
        baseURL: URL(string: "https://staging.jishu.page")!,
        apiToken: "test_token",
        appId: "app_test",
        environment: "staging",
        enableDebugLogs: enableDebugLogs
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

private func makeHTTPResponse(status: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://staging.jishu.page")!,
        statusCode: status,
        httpVersion: nil,
        headerFields: nil
    )!
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
}

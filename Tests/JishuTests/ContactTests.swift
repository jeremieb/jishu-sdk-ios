import Testing
import Foundation
@testable import Jishu

@Suite("Contact", .serialized)
struct ContactTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeClient() -> JishuClient {
        let config = JishuConfiguration(
            baseURL: URL(string: "https://staging.jishu.page")!,
            apiToken: "test_token",
            appId: "app_test",
            environment: "staging",
            enableDebugLogs: false
        )
        return JishuClient(configuration: config, session: makeSession())
    }

    private func makeHTTPResponse(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://staging.jishu.page")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    @Test("sendContactMessage succeeds on 201")
    func succeeds201() async throws {
        MockURLProtocol.requestHandler = { _ in
            (makeHTTPResponse(status: 201), Data())
        }
        let client = makeClient()
        try await client.sendContactMessage(
            ContactMessage(senderEmail: "user@example.com", body: "Hello!"),
            appId: "app_test"
        )
    }

    @Test("sendContactMessage succeeds on 200")
    func succeeds200() async throws {
        MockURLProtocol.requestHandler = { _ in
            (makeHTTPResponse(status: 200), Data())
        }
        let client = makeClient()
        try await client.sendContactMessage(
            ContactMessage(senderEmail: "user@example.com", body: "Hello!"),
            appId: "app_test"
        )
    }

    @Test("sendContactMessage throws httpError on 429")
    func throws429() async throws {
        MockURLProtocol.requestHandler = { _ in
            (makeHTTPResponse(status: 429), Data())
        }
        let client = makeClient()
        do {
            try await client.sendContactMessage(
                ContactMessage(senderEmail: "user@example.com", body: "Hello!"),
                appId: "app_test"
            )
            Issue.record("Expected throw")
        } catch JishuError.httpError(let code) {
            #expect(code == 429)
        }
    }

    @Test("sendContactMessage retries once on 500 then succeeds")
    func retries500() async throws {
        var callCount = 0
        MockURLProtocol.requestHandler = { _ in
            callCount += 1
            return callCount == 1
                ? (makeHTTPResponse(status: 500), Data())
                : (makeHTTPResponse(status: 201), Data())
        }
        let client = makeClient()
        try await client.sendContactMessage(
            ContactMessage(senderEmail: "user@example.com", body: "Hello!"),
            appId: "app_test"
        )
        #expect(callCount == 2)
    }

    @Test("sendContactMessage targets correct URL and omits auth header")
    func requestURLAndNoAuth() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (makeHTTPResponse(status: 201), Data())
        }
        let client = makeClient()
        try await client.sendContactMessage(
            ContactMessage(senderEmail: "user@example.com", body: "Test"),
            appId: "app_test"
        )
        #expect(capturedRequest?.url?.path == "/api/apps/app_test/contact")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(capturedRequest?.httpMethod == "POST")
    }

    @Test("sendContactMessage sanitizes blank optional fields to nil")
    func sanitizesBlankFields() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (makeHTTPResponse(status: 201), Data())
        }
        let client = makeClient()
        try await client.sendContactMessage(
            ContactMessage(
                senderName: "   ",   // blank → should become nil
                senderEmail: "  user@example.com  ",
                subject: "",          // blank → should become nil
                body: "  Hello  "
            ),
            appId: "app_test"
        )
        let bodyData = try #require(capturedRequest?.httpBody)
        struct DecodedBody: Decodable {
            let senderName: String?
            let senderEmail: String
            let subject: String?
            let body: String
        }
        let decoded = try JSONDecoder().decode(DecodedBody.self, from: bodyData)
        #expect(decoded.senderName == nil)
        #expect(decoded.senderEmail == "user@example.com")
        #expect(decoded.subject == nil)
        #expect(decoded.body == "Hello")
    }

    @Test("sendContactMessage preserves non-blank optional fields after trimming")
    func preservesTrimmedOptionalFields() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (makeHTTPResponse(status: 201), Data())
        }
        let client = makeClient()
        try await client.sendContactMessage(
            ContactMessage(
                senderName: "  Alice  ",
                senderEmail: "alice@example.com",
                subject: "  Hello  ",
                body: "World"
            ),
            appId: "app_test"
        )
        let bodyData = try #require(capturedRequest?.httpBody)
        struct DecodedBody: Decodable {
            let senderName: String?
            let subject: String?
        }
        let decoded = try JSONDecoder().decode(DecodedBody.self, from: bodyData)
        #expect(decoded.senderName == "Alice")
        #expect(decoded.subject == "Hello")
    }

    @Test("sendContactMessage encodes all fields in request body")
    func encodesAllFields() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (makeHTTPResponse(status: 201), Data())
        }
        let client = makeClient()
        try await client.sendContactMessage(
            ContactMessage(
                senderName: "Alice",
                senderEmail: "alice@example.com",
                subject: "Hello",
                body: "World"
            ),
            appId: "app_test"
        )
        let bodyData = try #require(capturedRequest?.httpBody)
        struct DecodedBody: Decodable {
            let senderName: String?
            let senderEmail: String
            let subject: String?
            let body: String
        }
        let decoded = try JSONDecoder().decode(DecodedBody.self, from: bodyData)
        #expect(decoded.senderName == "Alice")
        #expect(decoded.senderEmail == "alice@example.com")
        #expect(decoded.subject == "Hello")
        #expect(decoded.body == "World")
    }
}

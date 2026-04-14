import Testing
import Foundation
@testable import Jishu

final class ContactMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = ContactMockURLProtocol.requestHandler else {
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

@Suite("Contact", .serialized)
struct ContactTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ContactMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeClient() -> JishuClient {
        let config = JishuConfiguration(
            server: .staging,
            apiToken: "test_token",
            appId: "app_test",
            environment: "staging",
            debugLevel: .default
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

    private func requestBodyData(from request: URLRequest?) throws -> Data {
        let request = try #require(request)
        if let body = request.httpBody {
            return body
        }
        if let stream = request.httpBodyStream {
            return try readBody(from: stream)
        }
        throw NSError(domain: "ContactTests", code: 1, userInfo: [
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

    @Test("sendContactMessage succeeds on 201")
    func succeeds201() async throws {
        ContactMockURLProtocol.requestHandler = { _ in
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
        ContactMockURLProtocol.requestHandler = { _ in
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
        ContactMockURLProtocol.requestHandler = { _ in
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
        ContactMockURLProtocol.requestHandler = { _ in
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
        ContactMockURLProtocol.requestHandler = { request in
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
        ContactMockURLProtocol.requestHandler = { request in
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
        let bodyData = try requestBodyData(from: capturedRequest)
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
        ContactMockURLProtocol.requestHandler = { request in
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
        let bodyData = try requestBodyData(from: capturedRequest)
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
        ContactMockURLProtocol.requestHandler = { request in
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
        let bodyData = try requestBodyData(from: capturedRequest)
        struct DecodedBody: Decodable {
            let senderName: String?
            let senderEmail: String
            let subject: String?
            let body: String
            let platform: String
            let osName: String
            let osVersion: String
            let deviceName: String
        }
        let decoded = try JSONDecoder().decode(DecodedBody.self, from: bodyData)
        #expect(decoded.senderName == "Alice")
        #expect(decoded.senderEmail == "alice@example.com")
        #expect(decoded.subject == "Hello")
        #expect(decoded.body == "World")
        #expect(decoded.platform == "ios")
        #expect(decoded.osName.isEmpty == false)
        #expect(decoded.osVersion.isEmpty == false)
        #expect(decoded.deviceName.isEmpty == false)
    }
}

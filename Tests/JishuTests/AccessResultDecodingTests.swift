import Testing
import Foundation
@testable import Jishu

@Suite("AccessResult decoding")
struct AccessResultDecodingTests {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = fmt.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date: \(s)")
        }
        return d
    }()

    @Test("Decodes a full granted response")
    func decodesGrantedResponse() throws {
        let json = """
        {
          "granted": true,
          "grantId": "grant_abc",
          "matchType": "user",
          "expiresAt": "2026-04-24T12:00:00.000Z",
          "serverTime": "2026-03-24T12:00:00.000Z"
        }
        """.data(using: .utf8)!

        let result = try Self.decoder.decode(AccessResult.self, from: json)
        #expect(result.granted == true)
        #expect(result.grantId == "grant_abc")
        #expect(result.matchType == .user)
        #expect(result.expiresAt != nil)
        #expect(result.serverTime.timeIntervalSince1970 > 0)
    }

    @Test("Decodes matchType 'none' with granted false")
    func decodesNoneMatchType() throws {
        let json = """
        {
          "granted": false,
          "grantId": null,
          "matchType": "none",
          "expiresAt": null,
          "serverTime": "2026-03-24T12:00:00.000Z"
        }
        """.data(using: .utf8)!

        let result = try Self.decoder.decode(AccessResult.self, from: json)
        #expect(result.granted == false)
        #expect(result.grantId == nil)
        #expect(result.matchType == .none)
        #expect(result.expiresAt == nil)
    }

    @Test("Decodes matchType 'device'")
    func decodesDeviceMatchType() throws {
        let json = """
        {
          "granted": true,
          "grantId": "grant_xyz",
          "matchType": "device",
          "expiresAt": "2026-05-01T00:00:00.000Z",
          "serverTime": "2026-03-24T12:00:00.000Z"
        }
        """.data(using: .utf8)!

        let result = try Self.decoder.decode(AccessResult.self, from: json)
        #expect(result.matchType == .device)
        #expect(result.granted == true)
    }
}

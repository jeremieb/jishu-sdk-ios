import Testing
import Foundation
@testable import Jishu

@Suite("JishuProposal decoding")
struct ProposalDecodingTests {

    private func decode(_ json: String) throws -> JishuProposal {
        try JSONDecoder().decode(JishuProposal.self, from: Data(json.utf8))
    }

    @Test("Decodes ISO 8601 date with fractional seconds")
    func decodesDateWithFractionalSeconds() throws {
        let json = """
        {
          "id": "prop_abc",
          "title": "Dark mode",
          "description": "Add dark mode support",
          "status": "open",
          "voteCount": 5,
          "createdAt": "2026-03-28T20:35:11.844Z"
        }
        """
        let proposal = try decode(json)
        #expect(proposal.id == "prop_abc")
        #expect(proposal.title == "Dark mode")
        #expect(proposal.description == "Add dark mode support")
        #expect(proposal.status == .open)
        #expect(proposal.voteCount == 5)
        #expect(proposal.createdAt.timeIntervalSince1970 > 0)
    }

    @Test("Decodes ISO 8601 date without fractional seconds")
    func decodesDateWithoutFractionalSeconds() throws {
        let json = """
        {
          "id": "prop_xyz",
          "title": "Offline mode",
          "description": null,
          "status": "planned",
          "voteCount": 12,
          "createdAt": "2026-03-28T20:35:11Z"
        }
        """
        let proposal = try decode(json)
        #expect(proposal.status == .planned)
        #expect(proposal.voteCount == 12)
        #expect(proposal.description == nil)
        #expect(proposal.createdAt.timeIntervalSince1970 > 0)
    }

    @Test("Decodes in_progress status")
    func decodesInProgressStatus() throws {
        let json = """
        {
          "id": "prop_1",
          "title": "Push notifications",
          "description": null,
          "status": "in_progress",
          "voteCount": 0,
          "createdAt": "2026-03-28T20:35:11.000Z"
        }
        """
        let proposal = try decode(json)
        #expect(proposal.status == .inProgress)
    }

    @Test("Throws on invalid date string")
    func throwsOnInvalidDate() {
        let json = """
        {
          "id": "prop_bad",
          "title": "Test",
          "description": null,
          "status": "open",
          "voteCount": 0,
          "createdAt": "not-a-date"
        }
        """
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(JishuProposal.self, from: Data(json.utf8))
        }
    }

    @Test("Decodes fractional and non-fractional dates to the same second")
    func fractionalAndNonFractionalMatchToSecond() throws {
        let withFractional    = try decode(makeJSON(date: "2026-03-28T20:35:11.000Z"))
        let withoutFractional = try decode(makeJSON(date: "2026-03-28T20:35:11Z"))
        #expect(Int(withFractional.createdAt.timeIntervalSince1970) ==
                Int(withoutFractional.createdAt.timeIntervalSince1970))
    }

    @Test("Provides a non-empty formatted display date")
    func providesFormattedCreatedAt() throws {
        let proposal = try decode(makeJSON(date: "2026-03-28T20:35:11Z"))
        #expect(!proposal.formattedCreatedAt.isEmpty)
    }

    @Test("Round-trips through JSONEncoder and JSONDecoder")
    func roundTripsThroughCodable() throws {
        let proposal = JishuProposal(
            id: "prop_roundtrip",
            title: "Round trip",
            description: "Verify custom encode matches decode",
            status: .inProgress,
            voteCount: 3,
            createdAt: Date(timeIntervalSince1970: 1_743_194_111.844)
        )

        let data = try JSONEncoder().encode(proposal)
        let decoded = try JSONDecoder().decode(JishuProposal.self, from: data)

        #expect(decoded.id == proposal.id)
        #expect(decoded.title == proposal.title)
        #expect(decoded.description == proposal.description)
        #expect(decoded.status == proposal.status)
        #expect(decoded.voteCount == proposal.voteCount)
        #expect(decoded.createdAt == proposal.createdAt)
    }

    private func makeJSON(date: String) -> String {
        """
        {"id":"p","title":"T","description":null,"status":"open","voteCount":0,"createdAt":"\(date)"}
        """
    }
}

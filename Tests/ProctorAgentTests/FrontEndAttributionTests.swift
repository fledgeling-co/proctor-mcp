import Foundation
import Testing
@testable import ProctorAgent
@testable import ProctorCore

// PRO-0073 A3. The operator CLI reaches the same socket, the same policy gate,
// the same queue lane and the same trail as the MCP shim, so nothing else in a
// row tells a person's `proctor act` from a model's `proctor_act`. That
// distinction is the whole reason a refusal can be argued about afterwards.
//
// The identity comes from the peer process rather than from the request, for the
// same reason the project name does: a caller that could name itself could name
// itself as the other one, in the very record used to argue about what it did.

@Suite("Front-end attribution")
struct FrontEndAttributionTests {

    @Test("each shipped front end maps to its own name in the trail")
    func shippedFrontEndsAreNamed() {
        #expect(SessionIdentity.frontEnd(named: "proctor-cli") == "cli")
        #expect(SessionIdentity.frontEnd(named: "proctor-shim") == "mcp")
    }

    @Test("an unrecognised peer is nil rather than guessed at")
    func unknownPeerIsNotGuessed() {
        for name in ["proctor-agent", "Proctor", "python3", "xctest", ""] {
            #expect(SessionIdentity.frontEnd(named: name) == nil,
                    "\(name) was given a front-end name it has not earned")
        }
    }

    @Test("the peer's executable is read from the kernel, not from the caller")
    func executableNameComesFromTheProcess() {
        // The running test process is the only peer available here, and the
        // assertion that matters is the shape: a name comes back, and it is a
        // filename rather than a path.
        let name = SessionIdentity.executableName(for: getpid())
        #expect(name != nil)
        #expect(name?.contains("/") == false)
    }

    @Test("a record with no front end is stamped with the connected one")
    func stampingNamesAnUnnamedRecord() {
        let record = AuditRecord(timestamp: 1, tool: "proctor_act",
                                 outcome: AuditRecord.Outcome.refused)
        #expect(AuditLog.stamping(record, frontEnd: "cli").via == "cli")
    }

    @Test("a record that already names a front end keeps it")
    func stampingLeavesAnAuthoredRecordAlone() {
        let record = AuditRecord(timestamp: 1, tool: "proctor_history",
                                 outcome: AuditRecord.Outcome.ok, via: "mcp")
        #expect(AuditLog.stamping(record, frontEnd: "cli").via == "mcp")
    }

    @Test("an unreadable peer leaves the field absent rather than reading as MCP")
    func absenceIsNotMistakenForTheOlderFrontEnd() {
        let record = AuditRecord(timestamp: 1, tool: "proctor_act",
                                 outcome: AuditRecord.Outcome.ok)
        #expect(AuditLog.stamping(record, frontEnd: nil).via == nil)
    }

    @Test("the front end survives the line the seal is taken over")
    func frontEndSurvivesTheSealedLine() throws {
        let record = AuditRecord(timestamp: 1, tool: "proctor_act",
                                 outcome: AuditRecord.Outcome.refused, via: "cli")
        let line = record.jsonLine()
        #expect(line.contains("\"via\":\"cli\""))
        let back = try JSONDecoder().decode(AuditRecord.self, from: Data(line.utf8))
        #expect(back.via == "cli")
    }

    @Test("a row sealed before this field existed still decodes, with it absent")
    func olderRowsStillDecode() throws {
        let older = #"{"timestamp":1,"tool":"proctor_act","outcome":"ok"}"#
        let back = try JSONDecoder().decode(AuditRecord.self, from: Data(older.utf8))
        #expect(back.via == nil)
        #expect(back.tool == "proctor_act")
    }

    @Test("the identity a peer is given carries its front end")
    func identityCarriesTheFrontEnd() {
        let identity = RunSessionIdentity(project: "proctor-mcp", connection: "a3f1",
                                          key: "1:2", frontEnd: "cli")
        #expect(identity.frontEnd == "cli")
        // Equality is judged on the key alone, so attribution never merges or
        // splits two clients' queue allowances.
        #expect(identity == RunSessionIdentity(project: "other", connection: "0000", key: "1:2"))
    }
}

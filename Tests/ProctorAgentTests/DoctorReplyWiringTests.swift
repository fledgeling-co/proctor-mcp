import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0036 — the health report a caller actually receives, as opposed to the one
// the type can encode.
//
// This suite exists because of a defect found by building the status window and
// looking at it, which no test in either PRO-0050 or PRO-0036 could have caught
// from the inside. `proctor_doctor`'s reply is assembled by the dispatcher: it
// encodes `DoctorReport` and then adds blocks the report has no field for. One of
// those additions used to *overwrite* `policy`, replacing PRO-0050's posture with
// the full ungated status.
//
// It cost two things at once. Every allow, block and sensitive entry, the
// filesystem roots, the trail's path and its key id went back into the first call
// the Proctor skill tells a model to make, so PRO-0050's clause 12 held for the
// type and not for the wire. And the substitute carries none of the posture's
// keys, so `DoctorReport` could not decode its own agent's reply: the status
// window reported a healthy agent as "not answering", permanently.
//
// The lesson these tests encode: a claim about what a caller receives has to be
// tested where the caller receives it.

@Suite("The doctor reply a caller receives")
struct DoctorReplyWiringTests {

    private func session() -> Session {
        Session(ax: FakeAX(bundleId: "com.example.app"), capture: FakeCapture())
    }

    private func doctorReply(_ session: Session) async throws -> [String: JSONValue] {
        let response = await Dispatcher(session: session).handle(
            AgentRequest(id: "d", tool: "proctor_doctor", arguments: .object([:])))
        #expect(response.ok)
        return try #require(response.result?.objectValue)
    }

    @Test("the reply decodes into the report type the window reads")
    func theReplyDecodesAsADoctorReport() async throws {
        // The regression that broke the status window: an optional field that is
        // *present but wrong-shaped* still throws, so one mismatched block took
        // the whole report down and the window blamed the agent for it.
        let reply = try await doctorReply(session())
        let data = try JSONEncoder().encode(JSONValue.object(reply))
        let report = try JSONDecoder().decode(DoctorReport.self, from: data)
        #expect(report.agentRunning)
        #expect(report.policy != nil, "the posture must survive assembly, not be replaced")
    }

    @Test("the policy block on the wire carries posture, never rules")
    func theWirePolicyBlockCarriesNoRules() async throws {
        let session = self.session()
        // Rules a leak would have to name. The bundle id also mints a scoped
        // token, so the token's own bundle id is in play as well.
        await session.installPolicy(AppPolicy(allow: ["com.acme.vault"],
                                            block: ["com.acme.forbidden"],
                                            sensitive: ["com.acme.secret"]))

        let reply = try await doctorReply(session)
        let policy = try #require(reply["policy"]?.objectValue)
        let encoded = String(decoding: try JSONEncoder().encode(JSONValue.object(policy)),
                             as: UTF8.self)

        for rule in ["com.acme.vault", "com.acme.forbidden", "com.acme.secret"] {
            #expect(!encoded.contains(rule),
                    "a health check is the wrong place to hand out configuration")
        }
        for key in ["allow", "block", "sensitive", "fsRoots", "auditPath", "auditKeyId"] {
            #expect(policy[key] == nil,
                    "\(key) belongs to proctor_policy status, which is unchanged and still full")
        }
        // And it is a posture rather than an empty object.
        #expect(policy["mode"] != nil)
        #expect(policy["allowCount"] != nil)
    }

    @Test("proctor_policy status still answers in full")
    func theUngatedStatusToolIsUnchanged() async throws {
        // The convention this item restores is about `doctor` alone. PRO-0050 said
        // plainly that it is a convention rather than a boundary, because this tool
        // answers freely; narrowing it is somebody's decision and not a side effect
        // of fixing a health report.
        let session = self.session()
        await session.installPolicy(AppPolicy(allow: ["com.acme.vault"]))
        let status = try #require(await session.policyStatus().objectValue)
        #expect(status["allow"] != nil)
    }
}

import Foundation
import ProctorCore

/// A recorded flow: the steps, the selector each step resolved through, and the
/// per-step canonical hashes from the recording run. Replay compares against
/// those hashes, so a divergent replay says where and how rather than only that
/// it failed.
struct RecordedFlow: Codable, Sendable {
    var name: String
    var description: String?
    var window: String?
    var app: String?
    var appBundleId: String?
    var createdAt: Double
    var updatedAt: Double
    var steps: [RecordedStep]

    init(name: String, description: String? = nil, window: String? = nil,
         app: String? = nil, appBundleId: String? = nil,
         createdAt: Double = Date().timeIntervalSince1970,
         updatedAt: Double = Date().timeIntervalSince1970,
         steps: [RecordedStep] = []) {
        self.name = name; self.description = description; self.window = window
        self.app = app; self.appBundleId = appBundleId
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.steps = steps
    }
}

struct RecordedStep: Codable, Sendable {
    var step: ActionStep
    /// How the step's node was identified at record time — role, identifier,
    /// title. A raw node id does not survive the app relaunching; this does.
    var selector: JSONValue?
    var plane: ActuationPlane?
    var stateHash: String?
    var settleReason: SettleReport.Reason?
    /// Which backend actuated this step when it was recorded.
    ///
    /// Optional, so a flow recorded before PRO-0044 reads back unchanged and
    /// replays exactly as it did. It exists because a replay's whole claim is
    /// that it repeats the recorded run: replay a flow through a different
    /// actuation path and a divergence measures the paths rather than the
    /// application, which is the one comparison a determinism score must not
    /// quietly make.
    var backend: ActuationBackendID?

    init(step: ActionStep, selector: JSONValue? = nil, plane: ActuationPlane? = nil,
         stateHash: String? = nil, settleReason: SettleReport.Reason? = nil,
         backend: ActuationBackendID? = nil) {
        self.step = step; self.selector = selector; self.plane = plane
        self.stateHash = stateHash; self.settleReason = settleReason
        self.backend = backend
    }
}

/// Flows live on disk so a campaign survives the MCP host restarting.
enum FlowStore {

    /// The operator's own flow directory, always — the path the agent reads and
    /// writes on a real Mac. It stays truthful in a test process so a test can name
    /// the directory it must not touch.
    static var operatorDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/\(Wire.bundleIdentifier)/flows",
                                           isDirectory: true)
    }

    /// Where flows live for this process. `PolicyStore.live`'s interlock and
    /// `CaptureEngineImpl.defaultCaptureDirectory`'s, applied to the third path that
    /// writes the operator's state without being told where.
    ///
    /// FOUND BY THE REQ-055 WITNESS, not by reading: a clean `./scripts/test.sh` run
    /// rewrote `login-flow.json` and `sweep.json` under the operator's own root.
    /// `AcceptanceE2ETests` records a flow named `login-flow`, and
    /// `NativePlaneLaneTests` and `StabilityPageContentTests` record one named
    /// `sweep`; every one of them reached this static, which had no injection seam
    /// at all. Two names, so a person with a real flow of either name had it
    /// overwritten by running the tests. DEF-164.
    ///
    /// Unlike `PolicyStore.live` this is one directory per process rather than one
    /// per read: `save` and `loadAll` have to agree about where they are looking,
    /// and a fresh UUID per access would make a saved flow unfindable. That leaves
    /// suites in one process sharing a flow directory — which is exactly the sharing
    /// they had before, minus the operator.
    static var directory: URL {
        guard AuditLog.isTestProcess else { return operatorDirectory }
        return testFallbackFlowRoot
    }

    /// Where an un-pathed flow lands in a test process. Named for what it is, so a
    /// stray directory in `/tmp` explains itself.
    static let testFallbackFlowRoot = URL(fileURLWithPath: NSTemporaryDirectory(),
                                          isDirectory: true)
        .appendingPathComponent("proctor-test-flows-\(ProcessInfo.processInfo.processIdentifier)",
                                isDirectory: true)

    /// A flow name becomes a filename, so it is validated rather than escaped.
    /// Escaping invites two names collapsing onto one file.
    static func sanitised(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._-")
        guard !trimmed.isEmpty,
              trimmed != ".", trimmed != "..",
              !trimmed.hasPrefix("."),
              trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw AgentError(
                code: .invalidArguments,
                message: "flow name \(name.debugDescription) is not usable as a filename",
                remedy: "Use letters, digits, spaces, dots, underscores and hyphens, not starting with a dot.")
        }
        return trimmed
    }

    static func url(for name: String) throws -> URL {
        directory.appendingPathComponent("\(try sanitised(name)).json", isDirectory: false)
    }

    static func loadAll() -> [String: RecordedFlow] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: nil) else {
            return [:]
        }
        var out: [String: RecordedFlow] = [:]
        let decoder = JSONDecoder()
        for entry in entries where entry.pathExtension == "json" {
            guard let data = try? Data(contentsOf: entry),
                  let flow = try? decoder.decode(RecordedFlow.self, from: data) else { continue }
            out[flow.name] = flow
        }
        return out
    }

    static func save(_ flow: RecordedFlow) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(flow)
        try data.write(to: try url(for: flow.name), options: .atomic)
    }

    static func delete(_ name: String) throws -> Bool {
        let target = try url(for: name)
        guard FileManager.default.fileExists(atPath: target.path) else { return false }
        try FileManager.default.removeItem(at: target)
        return true
    }
}

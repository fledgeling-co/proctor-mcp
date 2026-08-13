import Foundation
import ProctorCore

// The filesystem jail, agent half. The containment decision is pure and tested in
// ProctorCore (FSJail); this file holds the session's jail, loads its roots from
// the environment once, and enforces it at the point a caller supplies a path.
// Like the policy gate it is inert until configured: with no PROCTOR_FS_ROOTS set
// the jail admits every path, so installing the mechanism changes nothing until an
// operator declares the roots.

extension Session {

    /// The environment variable that declares the roots, colon-separated, mirroring
    /// the `FS_ROOTS` convention of the source project.
    static let fsRootsEnvVar = "PROCTOR_FS_ROOTS"

    func loadFSJailIfNeeded() {
        guard !fsJailLoadedFlag else { return }
        let raw = ProcessInfo.processInfo.environment[Session.fsRootsEnvVar]
        fsJail = FSJail(roots: FSJail.parseRoots(raw))
        fsJailLoadedFlag = true
    }

    /// Refuse a caller-supplied path that escapes the declared roots. A no-op when
    /// the caller supplied no path (the tool falls back to its own trusted session
    /// directory) or when no roots are declared (the jail is dormant).
    func enforceFSJail(path: String?) throws {
        guard let path else { return }
        loadFSJailIfNeeded()
        guard let jail = fsJail, !jail.isEmpty else { return }
        if case .refuse(let reason) = jail.check(path) {
            throw AgentError(
                code: .policyDenied,
                message: reason,
                remedy: "Write inside a declared filesystem root, or change \(Session.fsRootsEnvVar). "
                      + "Declared roots: \(jail.roots.joined(separator: ", ")).")
        }
    }

    /// The declared roots, for the auditability surface (proctor_policy status).
    func fsRootsList() -> [String] {
        loadFSJailIfNeeded()
        return fsJail?.roots ?? []
    }
}

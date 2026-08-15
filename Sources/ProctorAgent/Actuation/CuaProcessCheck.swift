import Foundation
import Security
import Darwin

// PRO-0045, slice 4. Establishing which build is actually running.
//
// **Why this is not the check `CuaPreflight` already does.** That one reads the
// binary at a path and decides whether to execute it at all, which is a real and
// separate job — it is the gate that keeps Proctor, holding Accessibility, from
// running an unverified file out of a user-writable directory. What it cannot do
// is tell you what is running afterwards. Verifying a path and then spawning that
// path is a time-of-check / time-of-use gap, and the lane record that came out of
// it would attest build A while build B acted.
//
// An audit feature writing a confident, wrong attestation is worse than one
// writing none: every other failure here loses evidence, and that one
// manufactures it. So identity is established against the process that is going
// to act.
//
// **The key would ideally be the child's audit token rather than its pid**, since
// a pid names a slot rather than an incarnation and a recycled one would be
// attested with perfect confidence. `PROC_PIDAUDITTOKEN` is not in the public
// SDK — it appears in neither `sys/proc_info.h` nor `libproc.h` — and the
// alternatives (`task_name_for_pid` and `task_info`) are restricted under the
// hardened runtime, so `kSecGuestAttributePid` is the documented public route and
// is what this uses.
//
// What that costs is stated rather than hidden, and it is much smaller than what
// it replaces. A path check followed by a spawn leaves a window an attacker
// chooses: the file can be swapped at any point before `exec`. This check runs
// immediately after the spawn, on a child Proctor started and holds a handle for,
// so the only remaining window is the child dying and its pid being reused
// between the spawn and the check a few microseconds later. Materially better,
// and not perfect; `attested` means the process at that pid satisfied the
// requirement when it was checked, which is what the lane record says.

/// What Proctor established about the process it is talking to.
struct CuaProcessIdentity: Sendable, Equatable {
    /// True only when the running process was checked against the requirement.
    /// False means unattested, which is a reportable state rather than a failure:
    /// the lane still refuses, and its record says the identity could not be
    /// pinned rather than claiming one it does not have.
    var attested: Bool
    /// Recorded as evidence, never used as the check. The requirement is what
    /// pins identity; a hash read back from the thing being checked proves
    /// nothing on its own.
    var cdhash: String?
    /// Why it could not be attested, when it could not.
    var reason: String?
}

enum CuaProcessCheck {

    /// Verify a running child against the signing requirement.
    static func verify(pid: Int32, requirement text: String) -> CuaProcessIdentity {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement else {
            return CuaProcessIdentity(attested: false, cdhash: nil,
                                      reason: "the signing requirement could not be built")
        }

        let attributes = [kSecGuestAttributePid: pid as CFNumber] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else {
            return CuaProcessIdentity(attested: false, cdhash: nil,
                                      reason: "the running process could not be located for "
                                            + "checking")
        }

        guard SecCodeCheckValidity(code, [], requirement) == errSecSuccess else {
            return CuaProcessIdentity(
                attested: false, cdhash: nil,
                reason: "the running process does not satisfy the signing requirement")
        }
        return CuaProcessIdentity(attested: true, cdhash: cdhash(of: code), reason: nil)
    }

    private static func cdhash(of code: SecCode) -> String? {
        var stat: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &stat) == errSecSuccess, let stat else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(stat, flags, &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let hash = dictionary[kSecCodeInfoUnique as String] as? Data else { return nil }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

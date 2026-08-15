import Foundation

// PRO-0044, slice 5. Which builds of the driver this build of Proctor will talk to.
//
// "Whatever is installed" is not a dependency on a project shipping 130+ commits
// a week; it is a variable. The supported window is one minor version, because
// the driver is pre-1.0 and a pre-1.0 minor is the compatibility unit — a range
// wider than that is a wish.
//
// The range was chosen from documentation rather than from contact: the driver is
// not installed on the machine this was written on, and installing it as a side
// effect of anything is forbidden. That is what the capability probe is for. The
// version number is a claim the driver makes about itself; the probe is evidence.
// Both have to pass.

public struct CuaVersion: Sendable, Equatable, Comparable, CustomStringConvertible {

    public var major: Int
    public var minor: Int
    public var patch: Int
    /// Anything after the numbers — a nightly stamp, a release candidate. Kept
    /// because a pre-release of the next minor is not the next minor, and
    /// silently rounding it to one would let an unsupported build through.
    public var prerelease: String?

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major; self.minor = minor; self.patch = patch
        self.prerelease = prerelease
    }

    /// The lowest build this Proctor will drive.
    public static let lowestSupported = CuaVersion(major: 0, minor: 13, patch: 0)
    /// The first build it will not. Exclusive.
    public static let firstUnsupported = CuaVersion(major: 0, minor: 14, patch: 0)

    public static let supportedRangeDescription = ">= 0.13.0, < 0.14.0"

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.map { "\(core)-\($0)" } ?? core
    }

    /// Parse a version as a driver might print it: bare, `v`-prefixed, with a
    /// pre-release suffix, or embedded in a line like `cua-driver 0.13.2`.
    ///
    /// Nil rather than a lenient guess when nothing parses. A build whose version
    /// cannot be read is exactly as unsupported as one outside the range, and
    /// treating an unreadable string as "probably fine" would defeat the gate on
    /// precisely the builds most likely to be strange.
    public static func parse(_ raw: String) -> CuaVersion? {
        let scalars = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = scalars.range(of: #"\d+\.\d+(\.\d+)?([-+][0-9A-Za-z.\-]+)?"#,
                                        options: .regularExpression) else { return nil }
        var token = String(scalars[range])

        var prerelease: String?
        if let mark = token.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            prerelease = String(token[token.index(after: mark)...])
            token = String(token[..<mark])
        }
        let parts = token.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return CuaVersion(major: parts[0], minor: parts[1],
                          patch: parts.count > 2 ? parts[2] : 0,
                          prerelease: prerelease)
    }

    /// Is this build inside the supported window?
    ///
    /// **A pre-release is never supported**, whatever its numbers say, and that
    /// is the rule rather than an oversight. Semver orders a pre-release below
    /// the release it leads to, so a naive `< 0.14.0` bound would *admit*
    /// `0.14.0-nightly` — a build of the next minor, which is the one thing the
    /// upper bound exists to keep out. The same ordering puts `0.13.0-rc1` below
    /// the floor, where it also does not belong. The driver ships a nightly
    /// channel, so this is a real build somebody will have, and refusing it by
    /// default with a stamped override is the same fail-closed posture the
    /// signature and vocabulary checks take.
    public var isSupported: Bool {
        guard prerelease == nil else { return false }
        return self >= CuaVersion.lowestSupported && self < CuaVersion.firstUnsupported
    }

    public static func < (a: CuaVersion, b: CuaVersion) -> Bool {
        if a.major != b.major { return a.major < b.major }
        if a.minor != b.minor { return a.minor < b.minor }
        if a.patch != b.patch { return a.patch < b.patch }
        switch (a.prerelease, b.prerelease) {
        case (nil, nil): return false
        // A pre-release precedes the release it leads to.
        case (_?, nil):  return true
        case (nil, _?):  return false
        case (let x?, let y?): return x < y
        }
    }
}

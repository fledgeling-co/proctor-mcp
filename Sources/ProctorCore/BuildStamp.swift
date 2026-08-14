import Foundation

// Whether the app running is the app on disk.
//
// This exists because of a bug report that was not a bug. Proctor's menu bar was
// showing a status symbol where the idle character should have been, and the
// three named suspects — a readiness rule reaching too far, art that would not
// decode, a phase that never arrived — were all ruled out by measurement. The
// real cause: an upgrade had replaced /Applications/Proctor.app underneath a
// menu bar app that had been running for eight hours, since before the character
// existed at all.
//
// launchd brings the *agent* back on the new binary. Nothing brings the UI back,
// and nothing anywhere said the two halves of one bundle were now different
// builds. That is a thing a person cannot see and a thing a diagnosis has to
// rediscover from timestamps every time.
//
// TWO THINGS THIS IS NOT, both deliberate:
//
//   NOT A VERSION COMPARISON. `AgentBuild.version` is a hardcoded 0.1.0 and would
//   not have differed across the eight hours above. File identity would have.
//
//   NOT A MODIFICATION TIME. `touch` moves a modification time and replaces
//   nothing, and a copy can preserve one. Inode and size are what actually move
//   when a file is replaced: an upgrade writes a new file and unlinks the old
//   one, which the running process is still holding open, so the inode differs
//   even when everything else was preserved.
public struct BuildStamp: Sendable, Equatable {
    public let inode: UInt64
    public let size: UInt64

    public init(inode: UInt64, size: UInt64) {
        self.inode = inode
        self.size = size
    }

    /// Nil when the path cannot be read. A path nobody can stat is not evidence
    /// of an upgrade, and a banner nagging about one would be worse than silence.
    public static func of(path: String) -> BuildStamp? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value,
              let size = (attrs[.size] as? NSNumber)?.uint64Value
        else { return nil }
        return BuildStamp(inode: inode, size: size)
    }

    /// Whether a different build is on disk from the one running.
    ///
    /// Several paths, not one, because the picture that went missing in the
    /// report behind this is an *asset*: a reinstall that replaced only the
    /// resource bundle would leave a Mach-O stamp untouched and the character
    /// still wrong. Any one path moving is enough.
    ///
    /// A nil on either side of a pair is not a difference. A path that could not
    /// be stamped at launch, or cannot be stamped now, says nothing about an
    /// upgrade — and treating "I could not look" as "it changed" is how a
    /// permanent banner gets shipped.
    public static func replaced(running: [BuildStamp?], onDisk: [BuildStamp?]) -> Bool {
        for (was, now) in zip(running, onDisk) {
            guard let was, let now else { continue }
            if was != now { return true }
        }
        return false
    }
}

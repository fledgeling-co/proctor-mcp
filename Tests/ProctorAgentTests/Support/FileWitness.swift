import Foundation
import CryptoKit

// PRO-0098, DEF-110 and DEF-111. PRO-0089 built this reader inside
// `PolicyStoreSeamTests` and armed it correctly: the same instrument, over the
// same call, reports the injected file changing while the operator's does not, so
// its "unchanged" is a measurement rather than a reader that says unchanged
// whatever happens. Two requirements now stand on it, so it is lifted here rather
// than copied — a second copy is a second thing to arm, and an unarmed copy of an
// armed instrument is exactly the shape this campaign keeps finding.
//
// It gained two things in the lift. A **sha256**, because size and mtime agree
// across a rewrite that lands the same length within one filesystem timestamp
// tick. And a **directory sweep**, because REQ-055's claim is about the operator's
// state and not about one file of it: a suite that stopped touching `policy.json`
// and started touching `flows/` would satisfy a one-file reader completely.

/// What a path looked like at one moment: whether it is there, its bytes, when it
/// was last written, and a digest of its contents. Equality across a call is the
/// claim, in both directions — a witness is only worth something when the same
/// reader is shown reporting a difference where one exists.
struct FileWitness: Equatable, CustomStringConvertible {
    let exists: Bool
    let bytes: Data?
    let modified: Date?
    let digest: String?

    static func read(_ url: URL) -> FileWitness {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let data = try? Data(contentsOf: url)
        return FileWitness(exists: FileManager.default.fileExists(atPath: url.path),
                           bytes: data,
                           modified: attributes?[.modificationDate] as? Date,
                           digest: data.map { SHA256.hash(data: $0).map { b in
                               String(format: "%02x", b) }.joined() })
    }

    var description: String {
        guard exists else { return "absent" }
        return "\(bytes?.count ?? -1) bytes, modified "
            + (modified.map(String.init(describing:)) ?? "unknown")
            + ", sha256 " + (digest?.prefix(16).description ?? "unread")
    }
}

/// Every file under a root, by path relative to that root, each read through
/// `FileWitness`. An absent root reads as an empty sweep rather than as an error,
/// because "the operator has no policy directory at all" is a legitimate state of
/// the machine and must not be confused with a failed reading — which is why
/// `rootExists` is reported separately.
struct DirectoryWitness: Equatable {
    let rootExists: Bool
    let files: [String: FileWitness]
    /// Every DIRECTORY under the root, by relative path. PRO-0099 gap-fix: the
    /// file sweep cannot see what `maestroDebugDirectory(run:)` and
    /// `deviceFramePath` actually do, which is create an empty directory and hand
    /// back a name inside it. A sweep that cannot see the effect of the call it
    /// brackets reports zero whatever happens, and that is the one result this
    /// instrument may not produce.
    let directories: Set<String>

    static func read(_ root: URL) -> DirectoryWitness {
        var found: [String: FileWitness] = [:]
        var directories: Set<String> = []
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let present = fm.fileExists(atPath: root.path, isDirectory: &isDirectory)
        guard present, isDirectory.boolValue else {
            return DirectoryWitness(rootExists: present, files: [:], directories: [])
        }
        // `skipsHiddenFiles` is deliberately NOT set: a suite that wrote a dotfile
        // into the operator's directory would be invisible to a reader that skipped
        // them, and invisible is the one result this instrument may not produce.
        // Resolved on both sides. `NSTemporaryDirectory()` hands back `/var/...`
        // while the enumerator reports the same file as `/private/var/...`, so a
        // prefix test against the unresolved root matches nothing and every path
        // comes back absolute — which turns a `changed(...) == ["policy.json"]`
        // assertion into one that can never hold. Measured on this machine, and
        // exactly the shape of silent-instrument failure this reader exists to
        // rule out.
        let base = root.resolvingSymlinksInPath().path
        let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                   options: [])
        while let next = walker?.nextObject() as? URL {
            let resolved = next.resolvingSymlinksInPath().path
            let relative = resolved.hasPrefix(base + "/")
                ? String(resolved.dropFirst(base.count + 1))
                : resolved
            let values = try? next.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if values?.isRegularFile == true {
                found[relative] = FileWitness.read(next)
            } else if values?.isDirectory == true {
                directories.insert(relative)
            }
        }
        return DirectoryWitness(rootExists: present, files: found, directories: directories)
    }

    /// Paths whose reading differs between two sweeps — created, deleted, or
    /// rewritten. This is the number the witness reports: for REQ-063 it is the
    /// count of files the write actually produced, and for REQ-055 it is the count
    /// the control arm produces while the operator's own sweep produces none.
    static func changed(from before: DirectoryWitness, to after: DirectoryWitness) -> [String] {
        var paths = Set(before.files.keys)
        paths.formUnion(after.files.keys)
        return paths.filter { before.files[$0] != after.files[$0] }.sorted()
    }

    /// `changed`, plus every directory that appeared or vanished, spelled with a
    /// trailing `/` so the two are told apart in a failure message.
    ///
    /// PRO-0099 gap-fix. `changed` alone reports zero over a call whose whole
    /// effect is `mkdir`, so a case bracketing `maestroDebugDirectory(run:)` with
    /// it was asserting a number that could not have come out otherwise. This is
    /// the reading those cases claim on, and the one their arming arms.
    static func changedEntries(from before: DirectoryWitness,
                               to after: DirectoryWitness) -> [String] {
        let directories = before.directories.symmetricDifference(after.directories)
        return (changed(from: before, to: after) + directories.map { $0 + "/" }).sorted()
    }
}

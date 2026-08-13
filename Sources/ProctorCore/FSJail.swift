import Foundation

// The filesystem jail: a containment convention, decision half. A tool with broad
// control over the machine should not be able to read or write outside a declared
// set of roots, and stating those roots up front makes the guarantee auditable.
//
// Everything here is pure but for `realpath(3)`, which is the only honest way to
// answer "does this path escape the root?": a lexical check cannot see a symlink
// inside the root that points out of it. Resolution is therefore part of the
// decision, not an optimisation. The jail is inert until an operator declares
// roots — no roots means every path is admitted, exactly as an empty AppPolicy
// allows every app, so installing the mechanism changes nothing until it is
// configured.

public struct FSJail: Sendable, Equatable {
    /// Declared roots, normalised to absolute symlink-resolved paths without a
    /// trailing slash. A path is admitted only when it lands at or under one.
    public let roots: [String]

    public init(roots: [String]) {
        self.roots = roots
            .map { FSJail.canonicalize($0) }
            .map { $0.count > 1 && $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
    }

    /// No roots declared: the jail admits everything. This is the pre-feature
    /// behaviour, so the mechanism is dormant until `FS_ROOTS` is set.
    public var isEmpty: Bool { roots.isEmpty }

    /// The jail's verdict for one path. A refusal carries a reason a model can act
    /// on — where the path resolved and which roots were in force — rather than a
    /// bare denial it will retry.
    public enum Decision: Sendable, Equatable {
        case allow(resolved: String)
        case refuse(reason: String)
    }

    public func check(_ path: String) -> Decision {
        let expanded = (path as NSString).expandingTildeInPath

        // Inert when unconfigured. Still return the resolved form so a caller can
        // use one code path whether or not the jail is armed.
        if roots.isEmpty { return .allow(resolved: FSJail.canonicalize(expanded)) }

        // A raw parent-directory component is refused before any resolution, so the
        // reason names the traversal itself rather than wherever it resolved to.
        let components = expanded.split(separator: "/", omittingEmptySubsequences: true)
        if components.contains("..") {
            return .refuse(reason:
                "\(path.debugDescription) contains a \"..\" traversal component; the filesystem "
                + "jail refuses relative escapes. Declared roots: \(roots.joined(separator: ", ")).")
        }

        guard expanded.hasPrefix("/") else {
            return .refuse(reason:
                "\(path.debugDescription) is not an absolute path; the filesystem jail admits only "
                + "absolute paths at or under a declared root (\(roots.joined(separator: ", "))).")
        }

        // Resolution includes symlinks: a link that lives inside a root but points
        // outside it resolves outside and is refused. This is the escape a lexical
        // containment check cannot see.
        let resolved = FSJail.canonicalize(expanded)
        for root in roots where resolved == root || resolved.hasPrefix(root + "/") {
            return .allow(resolved: resolved)
        }
        return .refuse(reason:
            "\(resolved.debugDescription) resolves outside every declared filesystem root "
            + "(\(roots.joined(separator: ", "))); the operation is refused.")
    }

    // MARK: - Configuration

    /// Parse a colon-separated `FS_ROOTS` value into individual roots, dropping
    /// empty entries so a stray leading/trailing colon does not become a "" root
    /// that canonicalises to the current directory.
    public static func parseRoots(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw.split(separator: ":", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Path resolution

    /// Resolve a path to its real location, resolving symlinks on the longest
    /// prefix that exists and re-appending the literal tail that does not. A path
    /// whose target does not exist yet — a capture PNG about to be written — is
    /// still resolved as far as its existing parent, which is what makes the
    /// containment check honest for writes as well as reads.
    static func canonicalize(_ path: String) -> String {
        var absolute = path
        if !absolute.hasPrefix("/") {
            absolute = FileManager.default.currentDirectoryPath + "/" + absolute
        }
        let parts = absolute.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        var resolvedPrefix = "/"
        var tail = parts
        var count = parts.count
        while count >= 0 {
            let candidate = "/" + parts[0..<count].joined(separator: "/")
            if let real = FSJail.resolveSymlinks(candidate) {
                resolvedPrefix = real
                tail = Array(parts[count...])
                break
            }
            if count == 0 { resolvedPrefix = "/"; tail = parts; break }
            count -= 1
        }

        var result = resolvedPrefix
        for component in tail where component != "." {
            result = result == "/" ? "/" + component : result + "/" + component
        }
        return result
    }

    /// Thin wrapper over the POSIX `realpath(3)`; nil when the path does not exist.
    static func resolveSymlinks(_ path: String) -> String? {
        path.withCString { cString -> String? in
            guard let resolved = realpath(cString, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }
}

import Foundation

// Reading an application's scripting definition (sdef) — its suites, commands,
// classes, properties and enumerations — and reducing it to a structured form
// plus a one-line capability summary. This is what makes the Apple-Events plane
// self-describing: an agent can ask whether an app is scriptable and choose the
// scripting route where it is exact, rather than guessing or hard-coding
// AppleScript.
//
// Parsing lives here, pure and testable, the same way CUAFacade and SetOfMarks
// do: hand it the sdef bytes and it yields a value. Resolving the bytes for a
// running PID and caching them is the agent's job (SessionDictionary), because
// that is where the process, the bundle and the TCC surface live.
//
// A malformed or empty dictionary is not an error. "This app is not scriptable"
// is a real, useful answer — it is exactly the signal that tells a caller to use
// the accessibility route instead — so the parser degrades to a not-scriptable
// result rather than throwing.

public struct AppScriptingDictionary: Codable, Sendable, Equatable {
    public var appName: String
    /// True when the dictionary exposes at least one command. A dictionary of
    /// only type definitions is not something an app can be *told* to do, so it
    /// reads as not scriptable for route-selection purposes.
    public var scriptable: Bool
    public var suites: [Suite]
    public var counts: Counts
    /// One line naming the app, whether it is scriptable, and the shape of what
    /// it exposes. This is the `get_app_capabilities` view — enough to route on
    /// without reading the whole dictionary.
    public var summary: String

    public struct Suite: Codable, Sendable, Equatable {
        public var name: String
        public var code: String
        public var description: String?
        public var hidden: Bool
        public var commands: [Command]
        public var classes: [Class]
        public var enumerations: [Enumeration]
        public init(name: String, code: String, description: String? = nil,
                    hidden: Bool = false, commands: [Command] = [],
                    classes: [Class] = [], enumerations: [Enumeration] = []) {
            self.name = name; self.code = code; self.description = description
            self.hidden = hidden; self.commands = commands
            self.classes = classes; self.enumerations = enumerations
        }
    }

    public struct Command: Codable, Sendable, Equatable {
        public var name: String
        public var code: String
        public var description: String?
        public var parameters: [Parameter]
        public var resultType: String?
        public init(name: String, code: String, description: String? = nil,
                    parameters: [Parameter] = [], resultType: String? = nil) {
            self.name = name; self.code = code; self.description = description
            self.parameters = parameters; self.resultType = resultType
        }
    }

    /// A command parameter. A `direct-parameter` has no name; a named parameter
    /// carries its four-char code. `optional` defaults to required, matching sdef.
    public struct Parameter: Codable, Sendable, Equatable {
        public var name: String?
        public var code: String?
        public var type: String?
        public var optional: Bool
        public var description: String?
        public var direct: Bool
        public init(name: String? = nil, code: String? = nil, type: String? = nil,
                    optional: Bool = false, description: String? = nil, direct: Bool = false) {
            self.name = name; self.code = code; self.type = type
            self.optional = optional; self.description = description; self.direct = direct
        }
    }

    public struct Class: Codable, Sendable, Equatable {
        public var name: String
        public var code: String
        public var description: String?
        public var inherits: String?
        public var plural: String?
        public var properties: [Property]
        public var elements: [String]
        /// A class-extension adds to a class defined elsewhere; `name` is the
        /// class it extends and `code` is empty. Kept distinct so a caller can
        /// tell an extension from a first definition.
        public var isExtension: Bool
        public init(name: String, code: String, description: String? = nil,
                    inherits: String? = nil, plural: String? = nil,
                    properties: [Property] = [], elements: [String] = [],
                    isExtension: Bool = false) {
            self.name = name; self.code = code; self.description = description
            self.inherits = inherits; self.plural = plural
            self.properties = properties; self.elements = elements
            self.isExtension = isExtension
        }
    }

    public struct Property: Codable, Sendable, Equatable {
        public var name: String
        public var code: String?
        public var type: String?
        /// "r", "w" or "rw". sdef omits the attribute for read-write, so that is
        /// the default here.
        public var access: String
        public var description: String?
        public init(name: String, code: String? = nil, type: String? = nil,
                    access: String = "rw", description: String? = nil) {
            self.name = name; self.code = code; self.type = type
            self.access = access; self.description = description
        }
    }

    public struct Enumeration: Codable, Sendable, Equatable {
        public var name: String
        public var code: String
        public var enumerators: [Enumerator]
        public init(name: String, code: String, enumerators: [Enumerator] = []) {
            self.name = name; self.code = code; self.enumerators = enumerators
        }
    }

    public struct Enumerator: Codable, Sendable, Equatable {
        public var name: String
        public var code: String
        public var description: String?
        public init(name: String, code: String, description: String? = nil) {
            self.name = name; self.code = code; self.description = description
        }
    }

    public struct Counts: Codable, Sendable, Equatable {
        public var suites: Int
        public var commands: Int
        public var classes: Int
        public var properties: Int
        public var enumerations: Int
        public init(suites: Int = 0, commands: Int = 0, classes: Int = 0,
                    properties: Int = 0, enumerations: Int = 0) {
            self.suites = suites; self.commands = commands; self.classes = classes
            self.properties = properties; self.enumerations = enumerations
        }
    }

    public init(appName: String, scriptable: Bool, suites: [Suite],
                counts: Counts, summary: String) {
        self.appName = appName; self.scriptable = scriptable; self.suites = suites
        self.counts = counts; self.summary = summary
    }

    /// A dictionary for an app that exposes nothing scriptable. Returned instead
    /// of throwing, because "not scriptable" is the answer a caller routes on.
    public static func notScriptable(appName: String, reason: String) -> AppScriptingDictionary {
        AppScriptingDictionary(
            appName: appName, scriptable: false, suites: [], counts: Counts(),
            summary: "\(appName) is not scriptable (\(reason)); drive it through the "
                   + "accessibility route (proctor_snapshot / proctor_act) instead.")
    }
}

public enum ScriptingDictionary {

    /// Parse merged sdef XML into a structured dictionary. Expects the output of
    /// `/usr/bin/sdef`, which has already resolved the `xi:include` of the
    /// standard suite and merged scripting terminology, so this parser never has
    /// to fetch anything.
    ///
    /// External entities are never resolved (`.nodeLoadExternalEntitiesNever`):
    /// the sdef DOCTYPE names an external DTD, and the bytes come from an
    /// arbitrary application bundle, so loading external entities would be an XXE
    /// hole. Anything the parser cannot make sense of degrades to a
    /// not-scriptable result rather than throwing.
    public static func parse(sdefXML data: Data, appName: String) -> AppScriptingDictionary {
        guard !data.isEmpty,
              let doc = try? XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]),
              let root = doc.rootElement(), root.name == "dictionary" else {
            return .notScriptable(appName: appName, reason: "no readable scripting definition")
        }

        var suites: [AppScriptingDictionary.Suite] = []
        for suiteEl in root.elements(forName: "suite") {
            suites.append(parseSuite(suiteEl))
        }

        var counts = AppScriptingDictionary.Counts(suites: suites.count)
        for suite in suites {
            counts.commands += suite.commands.count
            counts.classes += suite.classes.count
            counts.enumerations += suite.enumerations.count
            for cls in suite.classes { counts.properties += cls.properties.count }
        }

        let scriptable = counts.commands > 0
        var dict = AppScriptingDictionary(appName: appName, scriptable: scriptable,
                                          suites: suites, counts: counts, summary: "")
        dict.summary = summary(for: dict)
        return dict
    }

    /// A single deterministic line describing what the app can be told to do.
    public static func summary(for dict: AppScriptingDictionary) -> String {
        guard dict.scriptable else {
            return "\(dict.appName) is not scriptable (no commands); drive it through the "
                 + "accessibility route (proctor_snapshot / proctor_act) instead."
        }
        let c = dict.counts
        let verbs = dict.suites.flatMap(\.commands).map(\.name).prefix(5)
        let verbList = verbs.isEmpty ? "" : " Commands include \(verbs.joined(separator: ", "))."
        return "\(dict.appName) is scriptable via Apple Events: "
             + "\(c.suites) \(plural(c.suites, "suite")), "
             + "\(c.commands) \(plural(c.commands, "command")), "
             + "\(c.classes) \(plural(c.classes, "class", "classes")), "
             + "\(c.properties) \(plural(c.properties, "property", "properties")). "
             + "Prefer the scripting route where a command is exact; fall back to "
             + "accessibility where it is not.\(verbList)"
    }

    // MARK: - Element parsing

    private static func parseSuite(_ el: XMLElement) -> AppScriptingDictionary.Suite {
        var suite = AppScriptingDictionary.Suite(
            name: attr(el, "name") ?? "",
            code: attr(el, "code") ?? "",
            description: attr(el, "description"),
            hidden: attr(el, "hidden") == "yes")
        for cmd in el.elements(forName: "command") { suite.commands.append(parseCommand(cmd)) }
        for cls in el.elements(forName: "class") { suite.classes.append(parseClass(cls, isExtension: false)) }
        for ext in el.elements(forName: "class-extension") { suite.classes.append(parseClass(ext, isExtension: true)) }
        for en in el.elements(forName: "enumeration") { suite.enumerations.append(parseEnumeration(en)) }
        return suite
    }

    private static func parseCommand(_ el: XMLElement) -> AppScriptingDictionary.Command {
        var command = AppScriptingDictionary.Command(
            name: attr(el, "name") ?? "",
            code: attr(el, "code") ?? "",
            description: attr(el, "description"))
        for direct in el.elements(forName: "direct-parameter") {
            command.parameters.append(parseParameter(direct, direct: true))
        }
        for param in el.elements(forName: "parameter") {
            command.parameters.append(parseParameter(param, direct: false))
        }
        if let result = el.elements(forName: "result").first {
            command.resultType = attr(result, "type")
        }
        return command
    }

    private static func parseParameter(_ el: XMLElement, direct: Bool) -> AppScriptingDictionary.Parameter {
        AppScriptingDictionary.Parameter(
            name: attr(el, "name"),
            code: attr(el, "code"),
            type: attr(el, "type"),
            optional: attr(el, "optional") == "yes",
            description: attr(el, "description"),
            direct: direct)
    }

    private static func parseClass(_ el: XMLElement, isExtension: Bool) -> AppScriptingDictionary.Class {
        // A class-extension names the class it extends in `extends`, not `name`.
        let name = isExtension ? (attr(el, "extends") ?? "") : (attr(el, "name") ?? "")
        var cls = AppScriptingDictionary.Class(
            name: name,
            code: attr(el, "code") ?? "",
            description: attr(el, "description"),
            inherits: attr(el, "inherits"),
            plural: attr(el, "plural"),
            isExtension: isExtension)
        for prop in el.elements(forName: "property") { cls.properties.append(parseProperty(prop)) }
        for element in el.elements(forName: "element") {
            if let type = attr(element, "type") { cls.elements.append(type) }
        }
        return cls
    }

    private static func parseProperty(_ el: XMLElement) -> AppScriptingDictionary.Property {
        AppScriptingDictionary.Property(
            name: attr(el, "name") ?? "",
            code: attr(el, "code"),
            type: attr(el, "type"),
            // sdef omits `access` for read-write properties.
            access: attr(el, "access") ?? "rw",
            description: attr(el, "description"))
    }

    private static func parseEnumeration(_ el: XMLElement) -> AppScriptingDictionary.Enumeration {
        var enumeration = AppScriptingDictionary.Enumeration(
            name: attr(el, "name") ?? "",
            code: attr(el, "code") ?? "")
        for enumerator in el.elements(forName: "enumerator") {
            enumeration.enumerators.append(AppScriptingDictionary.Enumerator(
                name: attr(enumerator, "name") ?? "",
                code: attr(enumerator, "code") ?? "",
                description: attr(enumerator, "description")))
        }
        return enumeration
    }

    private static func attr(_ el: XMLElement, _ name: String) -> String? {
        el.attribute(forName: name)?.stringValue
    }

    private static func plural(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        n == 1 ? singular : (plural ?? singular + "s")
    }
}

/// A per-application cache of parsed dictionaries, keyed by the app handle id.
///
/// The handle id is `app:<pid>:<epoch>` and the epoch changes when the app
/// relaunches, so keying on it gives per-PID caching that invalidates on
/// relaunch for free: a relaunched app is a different handle, so the stale entry
/// is never served and a fresh sdef is read.
public struct ScriptingDictionaryCache: Sendable {
    private var entries: [String: AppScriptingDictionary] = [:]
    public init() {}

    public func value(for app: AppHandle) -> AppScriptingDictionary? { entries[app.id] }

    public mutating func store(_ dictionary: AppScriptingDictionary, for app: AppHandle) {
        entries[app.id] = dictionary
    }

    public mutating func drop(for app: AppHandle) { entries.removeValue(forKey: app.id) }
    public mutating func dropHandle(_ id: String) { entries.removeValue(forKey: id) }

    public var count: Int { entries.count }
}

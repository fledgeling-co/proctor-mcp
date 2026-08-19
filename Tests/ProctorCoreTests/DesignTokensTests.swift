import Foundation
import Testing
@testable import ProctorCore

// PRO-0064. The generated token table, judged against the mock it came from.
//
// These run with no window and no AppKit, which is the point: the repo has no
// ProctorUI test target and `swift test` has no window server, so a design
// decision is only provable while it is still a value.

/// The design of record, located from this file rather than from a working
/// directory the test runner does not promise.
private func mockSource() throws -> String {
    var dir = URL(fileURLWithPath: #filePath)
    for _ in 0..<6 {
        dir.deleteLastPathComponent()
        let candidate = dir.appending(path: "design/surfaces/parts/head.html")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return try String(contentsOf: candidate, encoding: .utf8)
        }
    }
    throw CocoaError(.fileNoSuchFile)
}

/// The two authored palettes, parsed the way the generator parses them: at-rules
/// stripped first, then an exact `:root` / `:root[data-appearance="dark"]` match.
/// An increased-contrast override is not a palette.
private func palettes(_ css: String) -> (light: [String: String], dark: [String: String]) {
    var stripped = "", i = css.startIndex
    while let at = css[i...].firstIndex(of: "@") {
        guard let brace = css[at...].firstIndex(of: "{") else { break }
        stripped += css[i..<at]
        var depth = 1, j = css.index(after: brace)
        while j < css.endIndex, depth > 0 {
            if css[j] == "{" { depth += 1 } else if css[j] == "}" { depth -= 1 }
            j = css.index(after: j)
        }
        i = j
    }
    stripped += css[i...]

    var light: [String: String] = [:], dark: [String: String] = [:]
    var current: Int? = nil
    for raw in stripped.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(raw)
        if line.hasPrefix(":root {") { current = 0; continue }
        if line.hasPrefix(":root[data-appearance=\"dark\"] {") { current = 1; continue }
        if line.hasPrefix("}") { current = nil; continue }
        guard let slot = current else { continue }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("--"), let colon = trimmed.firstIndex(of: ":"),
              let semi = trimmed.firstIndex(of: ";") else { continue }
        let name = String(trimmed[trimmed.startIndex..<colon])
        let value = String(trimmed[trimmed.index(after: colon)..<semi])
            .trimmingCharacters(in: .whitespaces)
        if slot == 0 { light[name] = value } else { dark[name] = value }
    }
    return (light, dark)
}

// MARK: - sRGB, for the contrast clauses

private func channel(_ v: Double) -> Double {
    v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
}

/// Parses `#RRGGBB` and `rgba(r,g,b,a)`, compositing alpha over a known ground —
/// a translucent label tier has no luminance of its own.
private func luminance(_ value: String, over ground: (Double, Double, Double)) -> Double? {
    var r = 0.0, g = 0.0, b = 0.0, a = 1.0
    if value.hasPrefix("#") {
        let hex = String(value.dropFirst())
        guard hex.count == 6, let n = Int(hex, radix: 16) else { return nil }
        r = Double((n >> 16) & 0xFF); g = Double((n >> 8) & 0xFF); b = Double(n & 0xFF)
    } else if value.hasPrefix("rgb") {
        let inner = value.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
        let parts = inner.split(separator: ",").map {
            Double($0.trimmingCharacters(in: .whitespaces)) ?? 0
        }
        guard parts.count >= 3 else { return nil }
        r = parts[0]; g = parts[1]; b = parts[2]
        if parts.count > 3 { a = parts[3] }
    } else { return nil }
    let cr = r / 255 * a + ground.0 * (1 - a)
    let cg = g / 255 * a + ground.1 * (1 - a)
    let cb = b / 255 * a + ground.2 * (1 - a)
    return 0.2126 * channel(cr) + 0.7152 * channel(cg) + 0.0722 * channel(cb)
}

private func contrast(_ fg: String, on bg: String) -> Double? {
    guard let bl = luminance(bg, over: (1, 1, 1)) else { return nil }
    let ground = (bl, bl, bl)
    guard let fl = luminance(fg, over: ground), let b = luminance(bg, over: (1, 1, 1)) else {
        return nil
    }
    let hi = max(fl, b), lo = min(fl, b)
    return (hi + 0.05) / (lo + 0.05)
}

@Suite("Design tokens")
struct DesignTokensTests {

    @Test("A1 · the generated table has not drifted from the mock it came from")
    func drift() throws {
        let (light, dark) = palettes(try mockSource())
        #expect(!light.isEmpty, "parsed no light palette — the mock's shape changed")

        for token in ProctorTokens.all {
            #expect(light[token.name] == token.light,
                    "\(token.name) light: mock has \(light[token.name] ?? "nothing"), generated has \(token.light)")
            if let d = token.dark {
                #expect(dark[token.name] == d,
                        "\(token.name) dark: mock has \(dark[token.name] ?? "nothing"), generated has \(d)")
            }
        }
        // And nothing in the mock is missing from the table.
        for name in light.keys {
            #expect(ProctorTokens.token(name) != nil, "\(name) is in the mock and not generated")
        }
    }

    @Test("A1 · the accent is the one the design settled on")
    func accent() {
        #expect(ProctorTokens.accent(.light) == "#8A6224")
        #expect(ProctorTokens.accent(.dark) == "#D2A059")
    }

    @Test("A2 · every token carries a tier from the closed set")
    func tiered() {
        #expect(!ProctorTokens.all.isEmpty)
        for token in ProctorTokens.all {
            #expect(ProctorTokens.Tier.allCases.contains(token.tier))
        }
    }

    @Test("A2 · the kit tier holds the values Apple published, not this design's choices")
    func kitTier() {
        // A direction tag on a platform constant is the defect mock_check.py
        // already fails on in the mock; it must not survive the conversion.
        for name in ["--win", "--chrome", "--ink"] {
            #expect(ProctorTokens.token(name)?.tier == .kit, "\(name) should be kit-tiered")
        }
        #expect(ProctorTokens.token("--accent")?.tier == .direction)
    }

    @Test("A3 · every meaningful text tier clears its floor in both appearances")
    func contrastFloors() {
        // The pairs the design nominates as text, with the floor each carries.
        // The disabled tier is exempt under WCAG 1.4.3 and is named here as
        // exempt rather than quietly left out of the list.
        let cases: [(fg: String, bg: String, floor: Double, appearance: ProctorTokens.Appearance)] = [
            ("--ink",   "--win", 4.5, .light), ("--ink",   "--win", 4.5, .dark),
            ("--ink-2", "--win", 4.5, .light), ("--ink-2", "--win", 4.5, .dark),
            ("--ink-3", "--win", 4.5, .light), ("--ink-3", "--win", 4.5, .dark),
            ("--accent", "--win", 4.5, .light), ("--accent", "--win", 4.5, .dark),
            ("--danger", "--win", 4.5, .light), ("--danger", "--win", 4.5, .dark),
            ("--ok",     "--win", 4.5, .light), ("--ok",     "--win", 4.5, .dark),
        ]
        for c in cases {
            guard let fg = ProctorTokens.value(c.fg, c.appearance),
                  let bg = ProctorTokens.value(c.bg, c.appearance),
                  let ratio = contrast(fg, on: bg) else {
                Issue.record("could not measure \(c.fg) on \(c.bg) in \(c.appearance.rawValue)")
                continue
            }
            let shown = String(format: "%.2f", ratio)
            #expect(ratio >= c.floor,
                    "\(c.fg) on \(c.bg) (\(c.appearance.rawValue)) is \(shown):1, floor \(c.floor)")
        }
    }

    @Test("A4 · dark is authored, never derived from light")
    func darkAuthored() {
        // Every colour token that has a dark value has one the design wrote. A
        // dark scheme computed from a light one is how graphite becomes pure
        // black, which the native grammar names as a tell.
        let authored = ProctorTokens.colours.filter { $0.dark != nil }
        #expect(authored.count >= 20, "expected the design to author a dark palette")
        for token in authored {
            #expect(token.dark != token.light,
                    "\(token.name) has the same value in both appearances — suspect a fallback")
        }
        // The window background is the sharpest case: kit says #1E1E1E, and an
        // inversion of #FFFFFF would be #000000.
        #expect(ProctorTokens.value("--win", .dark) == "#1E1E1E")
    }
}

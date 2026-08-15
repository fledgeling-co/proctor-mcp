import Testing
import Foundation
@testable import ProctorCore

// PRO-0047: how much history is kept, and what happens when that is passed.
// Pure decision only — the moving is `AuditLog`'s.

@Suite("History retention")
struct HistoryRetentionTests {

    private let day: Double = 86_400

    // MARK: - The caps

    @Test("the entry cap fires on its own")
    func entryCap() {
        let caps = HistoryRetention.Caps(days: 90, entries: 100)
        #expect(HistoryRetention.decide(entries: 100, oldest: 0, now: 1000, caps: caps)
                == .rotate(.size))
        #expect(HistoryRetention.decide(entries: 99, oldest: 0, now: 1000, caps: caps) == .keep)
    }

    @Test("the age cap fires on its own")
    func ageCap() {
        let caps = HistoryRetention.Caps(days: 14, entries: 100_000)
        let start: Double = 1_000_000
        #expect(HistoryRetention.decide(entries: 1, oldest: start,
                                        now: start + 14 * day, caps: caps) == .rotate(.age))
        #expect(HistoryRetention.decide(entries: 1, oldest: start,
                                        now: start + 13 * day, caps: caps) == .keep)
    }

    @Test("an unknown start time leaves the age cap dormant and the entry cap live")
    func noStartTimeStillCapsBySize() {
        // An end-mark written before retention existed carries no start time.
        // The trail must not rotate on a guess, and must not become unbounded
        // either.
        let caps = HistoryRetention.Caps(days: 1, entries: 100)
        #expect(HistoryRetention.decide(entries: 5, oldest: nil, now: 9_999_999, caps: caps)
                == .keep)
        #expect(HistoryRetention.decide(entries: 100, oldest: nil, now: 9_999_999, caps: caps)
                == .rotate(.size))
    }

    @Test("a clock moved backwards does not rotate")
    func clockMovedBack() {
        // Wall clock is the only clock the records are stamped with, so a
        // backwards clock delays rotation. The entry cap is the backstop, and
        // this pins that the age test never goes negative into a rotation.
        let caps = HistoryRetention.Caps(days: 14, entries: 100_000)
        let start: Double = 1_000_000
        #expect(HistoryRetention.decide(entries: 5, oldest: start,
                                        now: start - 30 * day, caps: caps) == .keep)
    }

    @Test("a zero start time is treated as unknown rather than as 1970")
    func zeroStartIsUnknown() {
        let caps = HistoryRetention.Caps(days: 14, entries: 100_000)
        #expect(HistoryRetention.decide(entries: 5, oldest: 0, now: 2_000_000_000, caps: caps)
                == .keep)
    }

    // MARK: - Clamping

    @Test("days clamp to their range")
    func clampDays() {
        #expect(HistoryRetention.Caps(days: 0, entries: 1000).days
                == HistoryRetention.Caps.minimumDays)
        #expect(HistoryRetention.Caps(days: -5, entries: 1000).days
                == HistoryRetention.Caps.minimumDays)
        #expect(HistoryRetention.Caps(days: 9999, entries: 1000).days
                == HistoryRetention.Caps.maximumDays)
    }

    @Test("entries clamp to their range")
    func clampEntries() {
        #expect(HistoryRetention.Caps(days: 14, entries: 0).entries
                == HistoryRetention.Caps.minimumEntries)
        #expect(HistoryRetention.Caps(days: 14, entries: 10_000_000).entries
                == HistoryRetention.Caps.maximumEntries)
    }

    @Test("no environment value means unbounded")
    func noUnboundedSetting() {
        // The whole point of the cap is that a complete permanent record of
        // everything an agent did on somebody's Mac is a surveillance artifact.
        // A setting that switched it off would put the artifact back.
        for raw in ["0", "-1", "", "  ", "off", "never", "999999999"] {
            let caps = HistoryRetention.Caps.read(from: [
                "PROCTOR_HISTORY_DAYS": raw, "PROCTOR_HISTORY_ENTRIES": raw
            ])
            #expect(caps.days <= HistoryRetention.Caps.maximumDays)
            #expect(caps.days >= HistoryRetention.Caps.minimumDays)
            #expect(caps.entries <= HistoryRetention.Caps.maximumEntries)
            #expect(caps.entries >= HistoryRetention.Caps.minimumEntries)
        }
    }

    @Test("an unset environment takes the defaults")
    func defaults() {
        let caps = HistoryRetention.Caps.read(from: [:])
        #expect(caps.days == HistoryRetention.Caps.defaultDays)
        #expect(caps.entries == HistoryRetention.Caps.defaultEntries)
    }

    @Test("a set environment is honoured within the range")
    func honoursEnvironment() {
        let caps = HistoryRetention.Caps.read(from: [
            "PROCTOR_HISTORY_DAYS": "3", "PROCTOR_HISTORY_ENTRIES": "500"
        ])
        #expect(caps.days == 3)
        #expect(caps.entries == 500)
    }

    // MARK: - How much is left

    @Test("the window remaining reports both dials")
    func remaining() {
        let caps = HistoryRetention.Caps(days: 10, entries: 100)
        let start: Double = 1_000_000
        let left = HistoryRetention.remaining(entries: 50, oldest: start,
                                              now: start + 5 * day, caps: caps)
        #expect(abs((left.byAge ?? 0) - 0.5) < 0.001)
        #expect(abs(left.byEntries - 0.5) < 0.001)
    }

    @Test("a full window reports nothing left rather than a negative")
    func remainingFloorsAtZero() {
        let caps = HistoryRetention.Caps(days: 10, entries: 100)
        let left = HistoryRetention.remaining(entries: 400, oldest: 1_000_000,
                                              now: 1_000_000 + 90 * day, caps: caps)
        #expect(left.byEntries == 0)
        #expect(left.byAge == 0)
    }

    // MARK: - The attestation

    @Test("the rotation note commits to what was discarded")
    func noteCommitsToTheHead() {
        // This sentence is the only surviving statement about history that is
        // gone. Without the head hash, "the history is gone" and "the history was
        // never there" are the same claim.
        let note = HistoryRetention.rotationNote(
            reason: .size, discarded: 4321, from: 1_000_000, to: 2_000_000,
            trailId: "trail-7", head: "abc123")
        #expect(note.contains("4321"))
        #expect(note.contains("trail-7"))
        #expect(note.contains("abc123"))
        #expect(note.contains("size limit"))
        #expect(note.contains("no copy"))
    }

    @Test("a person's clear is told apart from a cap being reached")
    func noteNamesWhoAsked() {
        let person = HistoryRetention.rotationNote(reason: .person, discarded: 2, from: nil,
                                                   to: 100, trailId: nil, head: nil)
        let age = HistoryRetention.rotationNote(reason: .age, discarded: 2, from: nil,
                                                to: 100, trailId: nil, head: nil)
        #expect(person.contains("A person cleared"))
        #expect(age.contains("age limit"))
        #expect(person != age)
    }

    @Test("a note with nothing to say about the span still reads")
    func noteWithoutSpan() {
        let note = HistoryRetention.rotationNote(reason: .person, discarded: 1, from: nil,
                                                 to: 100, trailId: nil, head: nil)
        #expect(note.contains("1 entry was discarded"))
        #expect(!note.contains("covering"))
    }
}

import Foundation
import Security
import Darwin
import IOKit.pwr_mgt
import os

/// Drives the lock screen for an authorized unlock turn.
///
/// The capability is deliberately narrow: open a short turn, ask macOS to
/// evaluate the screen-unlock right (which runs the installed mechanism, which
/// asks the broker, which sees the open turn and allows), then relock when the
/// turn ends or a human touches the machine. Every unlock is its own turn with
/// its own TTL; nothing holds the door open across a session.
///
/// The safety properties live in the pieces around this: the authorization rule
/// keeps `use-login-window-ui` so a human is never locked out, the broker only
/// answers a verified peer, and the turn self-expires. This type is just the
/// sequencing.
final class UnlockCoordinator: @unchecked Sendable {
    static let shared = UnlockCoordinator()
    private let log = Logger(subsystem: "app.fledgeling.procter", category: "unlock")
    private let lock = NSLock()
    private var inputMonitor: Any?

    struct Outcome: Codable {
        var requested: Bool
        var rightGranted: Bool
        var screenLocked: Bool
        var ttlMs: Int
        var note: String
    }

    /// Whether the screen is locked, read from the session dictionary. This is
    /// the same `CGSSessionScreenIsLocked` flag the research used as ground
    /// truth, so the outcome reports the real state rather than an assumption.
    static func screenIsLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Int) == 1
    }

    /// Open a turn without touching the screen. Used to prove the mechanism and
    /// broker handshake in isolation before any lock-path evaluation.
    func openTurn(ttlMs: Int) {
        UnlockTurn.shared.open(ttl: Double(ttlMs) / 1000)
    }

    func closeTurn() {
        UnlockTurn.shared.close()
    }

    /// Unlock the screen for a turn.
    ///
    /// The mechanism that actually dismisses the lock screen is the lock-screen
    /// *transition*, not evaluating the right in the abstract: re-asserting the
    /// lock while a turn is open makes loginwindow re-run the unlock rule, the
    /// Proctor branch approves, and the session unlocks. Evaluating the right
    /// directly (AuthorizationCopyRights) grants it but leaves the lock UI up,
    /// so this uses the transition. If the screen is not locked there is nothing
    /// to do. The outcome reports the real before/after lock state rather than
    /// assuming success.
    func requestUnlock(ttlMs: Int) -> Outcome {
        lock.lock(); defer { lock.unlock() }
        let wasLocked = Self.screenIsLocked()
        UnlockTurn.shared.open(ttl: Double(ttlMs) / 1000)

        guard wasLocked else {
            return Outcome(requested: false, rightGranted: false, screenLocked: false,
                           ttlMs: ttlMs, note: "the screen was not locked; nothing to unlock")
        }

        // An already-locked screen has no pending transition to ride, and
        // re-asserting the lock on it is a no-op — so nothing makes loginwindow
        // re-evaluate. Declaring user activity first (the same nudge a returning
        // person's mouse gives) wakes loginwindow, and re-asserting the lock
        // then produces a real transition that evaluates the rule, at which the
        // Proctor branch approves. This is the piece that turns "unlock a screen
        // we just locked" into "unlock a machine that was already locked".
        declareUserActivity()
        Thread.sleep(forTimeInterval: 0.6)
        lockScreen()
        var stillLocked = true
        for _ in 0..<25 {  // up to ~2.5s
            Thread.sleep(forTimeInterval: 0.1)
            if !Self.screenIsLocked() { stillLocked = false; break }
        }

        let note = stillLocked
            ? "a turn is open and the transition was re-asserted after a wake, but the lock screen "
              + "has not dismissed"
            : "unlocked for the turn"
        log.log("unlock: wasLocked=\(wasLocked) stillLocked=\(stillLocked)")
        return Outcome(requested: true, rightGranted: !stillLocked, screenLocked: stillLocked,
                       ttlMs: ttlMs, note: note)
    }

    /// Wake the display and register user activity, so loginwindow is live
    /// enough for the next lock assertion to be a real transition. Uses the
    /// power-management assertion API — the supported way to say "treat this as
    /// user activity" without synthesising input, which Secure Event Input would
    /// block on a locked screen anyway.
    private func declareUserActivity() {
        var assertionID: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity(
            "Proctor unlock" as CFString, kIOPMUserActiveLocal, &assertionID)
    }

    /// Relock immediately and end the turn.
    func relock() {
        UnlockTurn.shared.close()
        lockScreen()
    }

    /// Lock the screen without touching the turn. Used to set up a locked test:
    /// open a turn, lock, then evaluate the unlock right, all under program
    /// control rather than needing a human to lock the machine.
    func lockOnly() {
        lockScreen()
    }

    private func lockScreen() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/login.framework/Versions/A/login", RTLD_NOW)
            ?? dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW),
              let sym = dlsym(handle, "SACLockScreenImmediate") else {
            log.error("lock: SACLockScreenImmediate not found")
            return
        }
        typealias LockFn = @convention(c) () -> Int32
        _ = unsafeBitCast(sym, to: LockFn.self)()
    }
}

@_silgen_name("CGSessionCopyCurrentDictionary")
func CGSessionCopyCurrentDictionary() -> CFDictionary?

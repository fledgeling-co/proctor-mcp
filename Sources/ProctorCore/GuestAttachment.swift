import Foundation

// PRO-0076. What it means for a session to be attached to a guest, and which
// handles may resolve while it is.
//
// **Everything here is pure.** The socket, the provider and the scheduler live
// in `ProctorAgent`; this file decides what an attachment is, which witness tier
// it carries, and when a handle belongs to the wrong machine. That is what makes
// the tier derivation and the three refusals provable with no VM.
//
// WHY AN ATTACHMENT IS KEYED BY SESSION AND NOT HELD ON THE SESSION.
// There is exactly one `Session` in this agent (`main.swift` builds it once) and
// callers are told apart by `SessionIdentity.current`, a task-local read from the
// peer process. So an attach that wrote a field on the session would move every
// connected client onto the guest at once. The attachment is per identity, and
// that is also what makes A4 mechanical rather than aspirational: a handle minted
// under one identity is simply not in another identity's attachment.

/// One session's attachment to one guest.
public struct GuestAttachment: Sendable, Equatable {

    /// The machine this session's runs now happen on. Its `tier` is DERIVED
    /// here (see `machine(for:)`) and never supplied by the attach site.
    public var machine: Machine
    /// The guest's `gst-` handle, as `proctor_guest list` hands it out.
    public var handle: String
    /// Which adapter reached it.
    public var provider: String
    /// The guest's name at its provider.
    public var name: String
    /// The forwarded unix socket this session talks to the guest's Proctor
    /// through. **Proctor does not create this forward** — a person opens the
    /// SSH StreamLocal tunnel that `proctor_guest reach` describes, and attach
    /// connects to the end of it. A socket nothing is listening on is a refusal,
    /// never an attempt to open one.
    public var localSocket: String
    /// Whether THIS agent started the guest. The only thing that licenses
    /// stopping it later: a guest a person started is never stopped to free a
    /// slot, because stopping a running VM discards its state.
    public var startedByThisAgent: Bool
    /// Whether this attachment still holds its pool slot.
    ///
    /// The idempotence bit. Detach, a vanished guest, a dead peer, the idle
    /// ceiling and a start timeout can all release, and two of them firing on
    /// one attachment must decrement the pool once. A second decrement
    /// underflows the count and admits two waiters where one slot freed, and on
    /// the waiter side resuming a continuation twice traps the process.
    public var slotHeld: Bool
    /// When it attached, and when it was last used — the idle ceiling reads the
    /// second one.
    public var attachedAt: Double
    public var lastUsedAt: Double

    public init(machine: Machine, handle: String, provider: String, name: String,
                localSocket: String, startedByThisAgent: Bool,
                slotHeld: Bool = true, attachedAt: Double, lastUsedAt: Double? = nil) {
        self.machine = machine
        self.handle = handle
        self.provider = provider
        self.name = name
        self.localSocket = localSocket
        self.startedByThisAgent = startedByThisAgent
        self.slotHeld = slotHeld
        self.attachedAt = attachedAt
        self.lastUsedAt = lastUsedAt ?? attachedAt
    }

    /// The guest, as the pool keys it.
    public var poolGuestKey: String {
        GuestPool.guestKey(provider: provider, name: name)
    }

    /// The `Machine` for a guest of this platform.
    ///
    /// **The tier is derived, never passed in.** `Machine.tier` has no default
    /// precisely so a construction site that forgot to say cannot describe a
    /// Linux guest as carrying a frame-status channel and an accessibility tree
    /// it does not have. This function is the derivation, so there is no attach
    /// site that *could* supply one: macOS is native because a full Proctor runs
    /// inside it, and everything else — including a platform the provider did
    /// not name — is delegated, which is the fail-closed direction.
    public static func machine(for record: GuestRecord) -> Machine {
        Machine(kind: .guest, name: record.name, provider: record.provider,
                platform: record.platform,
                tier: record.platform == .macos ? .native : .delegated)
    }
}

// MARK: - Which handles may resolve, and for whom

/// A4. A window handle belongs to the machine that minted it, and to the session
/// that was attached when it did.
///
/// Two failures are being prevented and they are not the same one. A host window
/// id used under a guest session would, without this, resolve against the host's
/// own window map and drive the wrong computer while the result said "guest". And
/// a guest id used under a *different* guest session would miss the map and come
/// back as `windowNotFound` — a lookup that happens to miss, which reads as "the
/// window closed" and sends a caller round a retry loop for a window that was
/// never theirs.
///
/// So the refusal names BOTH machines. That is the difference between a scoping
/// rule and an accident.
public enum GuestHandleScope {

    /// Where a window handle was minted.
    public enum Origin: Sendable, Equatable {
        /// Minted by this Mac's own accessibility walk.
        case host
        /// Minted inside a guest, under the session identity given.
        case guest(session: String, machine: String)
    }

    /// Why this handle may not resolve for this caller, or nil when it may.
    ///
    /// `sessionIsGuest` is the caller's own machine; `origin` is where the
    /// handle came from; `session` is the caller's identity key.
    public static func refusal(handle: String,
                               callerMachine: Machine,
                               callerSession: String,
                               origin: Origin) -> (message: String, remedy: String)? {
        switch origin {
        case .host:
            guard callerMachine.isGuest else { return nil }
            return (message: "\(handle) is a window on this Mac and this session is attached to "
                           + "\(callerMachine.line). A window handle belongs to the machine that "
                           + "minted it, so it is refused here rather than resolved against the "
                           + "wrong computer.",
                    remedy: "Call proctor_apps on this session to list the windows of the guest "
                          + "you are attached to, and use a handle from that listing. To drive "
                          + "this Mac instead, detach first with proctor_guest action \"detach\".")

        case .guest(let owner, let machineLine):
            if !callerMachine.isGuest {
                return (message: "\(handle) is a window inside \(machineLine) and this session is "
                               + "on this Mac. A window handle belongs to the machine that minted "
                               + "it, so it is refused here rather than resolved against the wrong "
                               + "computer.",
                        remedy: "Attach to that guest with proctor_guest action \"attach\" to use "
                              + "its handles, or call proctor_apps here for this Mac's windows.")
            }
            if owner != callerSession {
                // Both sides are guests, so a machine-only check would let this
                // through. This is the case A4's wording is actually about:
                // handles resolve only within the session that attached them.
                return (message: "\(handle) was minted inside \(machineLine) by a different "
                               + "session, and a guest handle resolves only within the session "
                               + "that attached it. It is refused here rather than looked up and "
                               + "missed.",
                        remedy: "Call proctor_apps on this session to list the windows of the "
                              + "guest it is attached to. Two sessions attached to the same guest "
                              + "still hold their own handles.")
            }
            return nil
        }
    }
}

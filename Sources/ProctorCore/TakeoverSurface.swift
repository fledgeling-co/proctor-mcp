import Foundation

// PRO-0070. What the takeover notice says, and what it deliberately does not
// claim.
//
// The overlay's meaning is narrow and exact: **Proctor holds the system event
// stream.** It is not "Proctor is doing something significant". PRO-0026's
// finding 10 recorded the gap and the reader carried it rather than speccing it
// — an all-accessibility run can delete a file through `AXPress` with this
// overlay never appearing, because nothing entered the event stream. The copy
// here states the mechanism and stops there.
//
// **A correction to the mock, made while implementing.** The surface set draws a
// second overlay state: a veil carrying the guest-route refusal. That is wrong,
// and the product's own logic says so. `refuseHostTakeoverIfRouted` throws
// *before* any step runs, so a refused batch never takes the machine — and a
// veil announcing "Proctor is driving this Mac" over a batch that was refused
// would make the overlay mean two incompatible things. A refusal is a notice,
// not a takeover. The refusal copy lives here and belongs on the menu bar and in
// the run line; the veil stays for the one state it describes.

public enum TakeoverSurface {

    /// The states this surface actually has.
    public enum State: String, Sendable, CaseIterable {
        /// A batch is holding the event stream. The veil is up.
        case armed
        /// Nothing is holding it.
        case absent
    }

    public enum Copy {
        public static let title = "Proctor is driving this Mac"
        /// Says what is happening and what the person can still do. It does not
        /// claim the run is significant, because the overlay cannot know that.
        public static let body =
            "Your keyboard and mouse are your own. Move the pointer or type and the run pauses."

        /// What the overlay is careful *not* to say. Kept as a value so the test
        /// can assert its absence rather than a reviewer having to notice it.
        public static let forbiddenClaims = [
            "is about to change", "is modifying", "will edit", "is deleting",
        ]
    }

    /// The guest-route refusal, as a notice rather than a veil.
    ///
    /// `GuestRoute` already computes the decision, names the configured guest
    /// and carries the remedy; this is only where a surface reads it.
    public struct Refusal: Sendable, Equatable {
        public let guest: String
        public let message: String
        public let remedy: String
    }

    public static func refusal(for route: GuestRoute) -> Refusal? {
        guard case .refuseHost(let configured, _) = route,
              let text = GuestRouteConfig.refusal(for: route) else { return nil }
        return Refusal(guest: configured, message: text.message, remedy: text.remedy)
    }

    /// Stop is reachable whenever the veil is up.
    ///
    /// Not negotiable and stated as a value: the veil covers the screen, so a
    /// person whose Stop is underneath it has no way to halt a run that is
    /// holding their keyboard.
    public static func offersStop(in state: State) -> Bool { state == .armed }

    public enum ID {
        public static func overlay(_ s: State) -> String { "proctor.takeover.\(s.rawValue)" }
        public static let stop = "proctor.takeover.stop"
        public static let pause = "proctor.takeover.pause"
        public static let refusal = "proctor.takeover.refusal"
    }
}

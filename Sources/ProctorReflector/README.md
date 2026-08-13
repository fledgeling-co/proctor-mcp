# ProctorReflector

There is no cross-process `getComputedStyle` on macOS. For an app you do not own, the
ceiling is the accessibility tree plus pixels: geometry and roles, no resolved colours,
no fonts, no corner radii, no constraints.

For an app you *do* own, this package removes that ceiling. Add it behind `#if DEBUG` and
the Proctor agent can read resolved style values out of your running app — which turns
visual-fidelity checking from an opinion into a measurement.

## Adopting it

```swift
// Package.swift
.package(url: "https://github.com/fledgeling-co/proctor-mcp.git", from: "1.0.0")
// then, in your app target's dependencies:
.product(name: "ProctorReflector", package: "proctor-mcp")
```

```swift
import ProctorReflector

func applicationDidFinishLaunching(_ note: Notification) {
    #if DEBUG
    ProctorReflector.start()
    #endif
}
```

That is the whole adoption. The default socket is
`~/Library/Application Support/app.fledgeling.procter/reflector-<pid>.sock`; the agent
discovers reflectors by scanning that directory and matching the pid, so keep the name
unless you also configure the agent.

## What the app gains

Over a Unix socket, framed as a 4-byte big-endian length then JSON
(`{"id","op","params"}` in, `{"id","ok","result","error"}` out):

| op | answers |
|---|---|
| `hierarchy` | the `NSView` tree for one window (`window`: window number) or all of them |
| `node` | one subtree by structural id |
| `idle` | whether the app considers itself settled, and why not |
| `revision` | a monotonic render counter |
| `ping` | pid, protocol version, bundle id |

Each node carries its structural id, class, `NSUserInterfaceItemIdentifier`, frame and
frame-in-window, hidden/alpha/flipped, appearance and effective appearance, and — where a
layer exists — background and border colour, border width, corner radius, masked corners,
opacity, shadow, `masksToBounds`, contents scale and transform. `NSTextField`, `NSButton`
and `NSText` add the string, resolved font family/size/weight, resolved text colour,
alignment and line-break mode. Pass `includeConstraints: true` for each view's
`NSLayoutConstraint`s with item ids, attributes, relation, multiplier, constant, priority
and active flag.

Colours resolve to sRGB hex plus alpha **and keep their catalog and semantic name** when
they had one: `NSColor.labelColor` reports `labelColor` alongside `#FFFFFF` at alpha 0.85.
The name is what a designer specified; reducing it to a number throws that away. Layer
colours are `CGColor`s and have already lost any name by the time CoreAnimation stores
them, so their name fields are null.

Every layer value is emitted twice, as `model` and `presentation`, with `animating` set
when they differ. That is the honest settle signal: they diverge exactly while something
is in flight, and the app is answering for itself rather than being guessed at from
outside. `idle` is the conjunction of three claims — no open activity tokens, no layer
mid-animation, no pending layout pass. An app that knows it is busy can say so directly:

```swift
let token = ProctorReflector.beginActivity("loading document")
defer { ProctorReflector.endActivity(token) }
```

SwiftUI: `NSHostingView` subtrees walk as ordinary `NSView`s, so you see the hosting view
and whatever AppKit backing views SwiftUI created. That is not SwiftUI introspection —
there is no supported way to read resolved SwiftUI modifier values from outside the
framework, and this package does not pretend to.

## What it costs

A debug-only Unix socket, mode `0600`, in your Application Support directory, answering
anything that can open it as your user. A `CADisplayLink` that wakes while layers are
moving and pauses itself after two quiet seconds, checking only the layers the last walk
saw. An `NSWindow.didUpdateNotification` observer. And the honest one: **the reflector's
presence is observable to the app under test** — it adds a thread, holds references to
your layers, and makes main-thread work happen when an inspector asks for a walk. If your
app's behaviour can depend on that, it will.

None of this exists in a build compiled without `DEBUG` or `PROCTOR_REFLECTOR`. In that
build `start()` returns immediately, no socket is created, no observers are registered and
no display link is made; the implementation is not compiled at all, so the binary carries
no reference to `socket`, `bind`, `NSApplication` or `CADisplayLink` from this package.

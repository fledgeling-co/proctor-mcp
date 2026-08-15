# Drive iOS through deep links

**Read `00-WAVE-7-DIRECTION.md` first.**

## The problem

Proctor drives macOS. A large share of the UI worth testing is an iOS app, and the
cheapest reliable way into an iOS app's state is not clicking through it: it is opening
the URL that puts it where you want it.

`acceptance-e2e` already documents the lane and this item follows it rather than
inventing one: navigate deep-link-first with `xcrun simctl openurl`.

## What it should do

Let a caller target an iOS Simulator, list what is available, and put an app into a
named state by opening a deep link, with the result reported in Proctor's own shape.

## The hard parts, named

- **A simulator is not a window, and Proctor's whole model is windows.** `proctor_apps`
  attaches to a process and retains element references. A simulator is a device holding
  apps. Decide whether an iOS target is a new kind of handle or a fiction layered onto
  the existing one, and be honest in the tool descriptions, because a model that thinks
  it can `proctor_snapshot` an iOS app because it got a handle will waste a campaign.
- **`openurl` returning zero proves the URL was delivered, not that the app went
  anywhere.** That is the same silent-success class this whole wave exists to catch.
  Say what evidence makes a deep-link navigation *verified* rather than *sent*.
- **The simulator's accessibility tree is not reachable the way a Mac app's is.** The
  Mac's AX API does not cross into the simulated device. Whatever verification is
  offered comes from the simulator's own surface or from Maestro, not from
  `AXUIElement`. State the ceiling rather than implying parity with the macOS lane.
- **Booting and shutting down simulators is slow and stateful.** Decide whether Proctor
  boots one, requires one already booted, or refuses, and what it does with a device
  left running.

## Worth knowing

`xcrun simctl` is part of Xcode, not macOS. A machine without Xcode has no lane here at
all, which is a `proctor_doctor` row rather than a runtime surprise.

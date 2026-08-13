# Proctor site copy (Luke voice, marketing register)

## 1. Hero
- Eyebrow: Computer use for macOS
- Headline: Give any agent real hands on a Mac
- Standfirst: Proctor lets any model or harness read what's on screen and drive it; click, type, check what the app actually drew. It works on background windows, without taking over your machine. The same primitives make it a proper Mac test harness.
- Primary CTA: Get started
- Secondary CTA: See it drive an app

## 2. Dual-positioning band
### Card A
- Title: Computer use for any agent
- Body: Any MCP host, any harness. Proctor hands the model on the other end a real Mac to work: the accessibility tree to read, the pointer and keyboard to drive, the screen to check what happened. It isn't a script. It's hands.
### Card B
- Title: A test harness that measures itself
- Body: The same tools, plus the discipline testing needs. Settle before you assert, replay to tell flaky from broken, measure a build against its mock with real numbers. You get a result you can trust, and the gaps stated instead of hidden.

## 3. Feature slices

### a. Background
- Kicker: Runs in the background
- Title: It works on windows you're not looking at
- Body: Proctor drives through the accessibility and Apple Events planes. They don't need a window in front, or even on screen, so it reaches background and occluded windows and other Spaces without stealing your focus. You keep working; it keeps going.

### b. Runs while locked
- Kicker: Runs while locked
- Title: It keeps going when the Mac is locked
- Body: The planes Proctor drives through don't need the screen, so a run carries on while the Mac is locked and you're away from it. When a task genuinely needs the machine unlocked, an optional login-path capability opens a short turn bounded by a timeout, does the work, and relocks; the password prompt stays as the fallback, so nobody gets locked out.

### c. Capture
- Kicker: Capture
- Title: A screenshot you can trust, or a flag
- Body: Every window capture carries its freshness: the frame status, the dirty rects, the content rect. A stale frame gets flagged, not handed back as if it were current. A green run never rests on a picture of the old state.

### c. Read the layout
- Kicker: Read the real layout
- Title: Geometry, and the style behind it
- Body: The accessibility tree gives you roles, values, and frames. For an app you own, an in-process reflector adds the resolved colours, fonts, corner radius, constraints, and the CALayer model and presentation values, with a render revision. Those are the numbers that check a build against a mock and stand behind a real assertion.

### d. Tools
- Kicker: The tools
- Title: One tool per decision, actions batched
- Body: Attach to an app, snapshot a pruned tree with stable ids and since-revision diffs, find by predicate, act on a batch of steps. A six-step flow is one call; each step settles and reports its outcome, a post-state hash, and what changed.

### e. Settle
- Kicker: Settle, then assert
- Title: No bare sleeps, no guessed waits
- Body: Settle is a conjunction: quiet frames, and no relevant accessibility notifications, and the app's own idle signal when it has one, and a timeout. Determinism is measured by replay, so a race is filed as flaky, not as a bug.

### f. Permissions
- Kicker: Permissions
- Title: Granted once, to a stable identity
- Body: Proctor installs as its own signed background agent, so macOS attributes the grant to Proctor itself, not to whatever tool is driving it. Grant it once, drag it into the list, and it keeps working when you change the model or the harness.

### g. Remote
- Kicker: Remote
- Title: Drive it from another machine, on your terms
- Body: There's a built-in MCP server over HTTP, with optional bearer-token auth. Local by default; you open it up only when you mean to.

## 3b. For testing
- Intro title: Built to run a real test campaign
- Intro body: Driving an app is the easy half. Proctor carries the parts a test actually needs: a way to know a step finished, a way to tell a flake from a defect, and a report that admits what it didn't cover.
- List:
  - An exploratory sweep to map the app before you script a thing.
  - Acceptance criteria turned into executable flows.
  - State-matrix coverage: light and dark, text sizes, displays.
  - An accessibility audit against the platform's own rules.
  - Fidelity checking: the build measured against its mock, not eyeballed.
  - Determinism and flake measured by replay, with the first divergence named.
  - Honest coverage; skipped is never counted as passed.
  - The observer effect disclosed, because setting the accessibility flag changes what you're testing.
  - Tri-observer disagreement as a defect oracle: when the tree, the layout, and the pixels disagree about one instant, that's a finding, not noise.
  - Hand it a suite and every case is traced to the flow and the assertion that verifies it.

## 4. Works with your stack
- Line: Works with any MCP host and any harness. If your model can call a tool, it can drive a Mac.

## 5. Closing CTA band
- Headline: Give your agent a Mac to work
- Body: Install the agent, point your model at it, and let it read and drive a real app.
- CTA: Get started

## 6. Honest note (footer)
- Two honest limits. macOS has no cross-process way to read computed styles, so for an app you don't own, accessibility geometry and sampled pixels are the ceiling; the reflector that reads resolved styles is for apps you build. And real parallelism is bounded by the hardware, so Proctor scales across many windows in one session rather than pretending a laptop is a fleet.

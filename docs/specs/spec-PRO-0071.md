# PRO-0071: The history window, and the skipped verdict

**ID:** PRO-0071 · **Status:** Ready for Plan · **Created:** 2026-08-20
**Brief:** `docs/features-to-triage/65-history-window-to-the-mock.md`
**Branch:** `ai/pro-0071` off `ai/wave-9` · **Depends on:** PRO-0064, PRO-0065
**Mock:** `#mac/history/ideal`, `#mac/history/empty`

## The problem

`HistoryWindow.swift` lists runs. The mock adds an empty state that names the action filling
it, and a per-run detail showing each assertion's verdict — **including the skipped ones, with
their reason**.

The skipped verdict is the point. Proctor's whole thesis is that a check which could not run is
not a check that passed. A detail pane showing three passes and silently omitting a fourth
because no reflector was available would be the product's own UI committing the failure the
product exists to prevent.

## Acceptance criteria

1. **A1** — `skipped` renders differently from both `pass` and `fail` and carries its reason.
   A test asserts a skipped assertion can never be counted into a pass total.
2. **A2** — the empty state names the action that fills it rather than reporting no data.
3. **A3** — no redacted fingerprint, post-state hash, key id or session handle is reachable
   from any view in this window. The test runs over the projection's field list, so a later
   widening of `RunHistory` fails here rather than leaking.
4. **A4** — an application is identified by bundle id, never by the `app-3` handle, which is
   meaningless once the agent restarts.
5. **A5** — retention is stated on the surface: 14 days or 10,000 entries.

## Decisions taken at triage

- **`RunHistory`'s exclusions are the guarantee and are not widened.** A field not on the face
  of the window is not in the type.
- **Every string here came from somewhere else.** App titles are authored by the application
  under test, flow and run names by the calling model. Both are fenced by `RunHistory.Object`
  and the view renders through the fence — the compiler is the rule, because the failure is
  invisible.
- **Rotation is not pruning and the copy says rotates.** The trail is hash-chained from a
  genesis over its own prefix, so removing entries from the front is unrepresentable: the first
  survivor would link to a record that is gone.

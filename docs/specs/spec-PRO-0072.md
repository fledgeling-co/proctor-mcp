# PRO-0072: The consent sheets, and the asymmetry

**ID:** PRO-0072 · **Status:** Ready for Plan · **Created:** 2026-08-20
**Brief:** `docs/features-to-triage/66-consent-sheets.md`
**Branch:** `ai/pro-0072` off `ai/wave-9` · **Depends on:** PRO-0066
**Mock:** `#mac/consent/input`, `…/pairing`, `…/lane`, `…/unlock`

## The problem

Two switches hand something away — a person's keyboard, and a browser holding their real
logins — and a third action unlocks the screen. `SwitchCatalogue` already carries
`requiresConsent` and the pairing warnings as tested pure values, and **nothing renders them**.
The disclosure exists with no surface.

## Acceptance criteria

1. **A1** — turning a `requiresConsent` switch on raises the sheet; turning it off does not.
   Four cases: both capability switches, both directions.
2. **A2** — the pairing sheet appears exactly when the capability is on and its announcing
   drawing switch is off; the four combinations are already covered by the existing pure test.
3. **A3** — the prominent action in the pairing sheet is the **recovery**, not the risky path,
   which stays available and unfilled.
4. **A4** — no sheet ships a shell command. A command in a surface a model can read is a
   command a model will run — the same rule the browser handoff already holds.
5. **A5** — `PROCTOR_YIELD_INPUT` does not confirm, asserted. It observes input to notice a
   person sooner and intercepts nothing; a confirmation there would train people to click
   through the two that matter.
6. **A6** — each sheet states that a capability applies at the next agent start, so nobody
   presses the button, sees nothing change, and presses it again.

## Decisions taken at triage

- **Turning a capability ON asks; turning it OFF never does.** A person withdrawing a
  capability must not be argued with, and the asymmetry mirrors the defaults'.
- **The disclosure is true and the consequence comes first.** The takeover-input tap is the
  same API a keylogger uses, on a grant Proctor already holds. Saying so plainly is what makes
  the consent meaningful; the mock's copy is the settled wording and softening it would make
  the sheet a formality.

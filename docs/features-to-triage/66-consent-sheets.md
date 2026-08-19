# The consent sheets, and the asymmetry that runs through them

**Wave 9, brief 8 of 11.** Reads `58`, `59`, lands after `60`. Mock anchors:
`#mac/consent/input`, `…/pairing`, `…/lane`, `…/unlock`.

## The problem

Two switches hand something away — a person's own keyboard, and a browser holding their real
logins — and a third action unlocks the screen. `SwitchCatalogue` already carries
`requiresConsent` on the two switches and the pairing warnings, and there is no sheet. The
disclosure exists as a value with nothing rendering it.

## What it should do

Four sheets, and one rule that governs all of them.

- **Hold the keyboard and mouse** — names the consequence, names the mechanism honestly
  ("the same mechanism a keylogger uses, on the grant Proctor already holds"), and states the
  two invariants: Stop always works, and the block never survives the process.
- **Pairing warning** — the capability is going on while the notice that would explain it is
  off. The recovery is the prominent action; the risky path stays available and unfilled.
- **Second browser lane** — browser-use is an autonomous agent driving a real browser with
  real credentials, outside the audit trail. No command template ships with it.
- **Screen unlock** — an explicit duration, a self-expiring turn, and the login window kept
  available so nobody is locked out.

**The rule: turning a capability ON asks; turning it OFF never does.** A person withdrawing a
capability must not be argued with, and the asymmetry mirrors the defaults'.

## The conversion contract

- `SwitchCatalogue.requiresConsent` and `SwitchCatalogue.pairingWarning` already hold the
  decisions and are pure and tested. The sheets render them.
- The sheet copy joins the catalogue rather than living in the view.

## Acceptance

1. Turning a `requiresConsent` switch on raises the sheet; turning it off does not. Tested
   for both capability switches and both directions — four cases.
2. `pairingWarning` fires exactly when the capability is on and its announcing drawing switch
   is off, and the four combinations are already covered by the existing pure test; this
   brief asserts the sheet appears on precisely that condition.
3. The prominent action in the pairing sheet is the **recovery**, not the risky path.
4. No sheet ships a shell command. This is the same rule the browser handoff already holds —
   a command in a surface a model can read is a command a model will run.
5. `PROCTOR_YIELD_INPUT` deliberately does **not** confirm, and a test asserts it. It observes
   input to notice a person sooner and intercepts nothing; a confirmation there would train
   people to click through the two that matter.

## The hard parts, named

**The disclosure has to be true and the consequence has to be first.** The takeover-input tap
is the same API a keylogger uses. Saying so plainly is what makes the consent meaningful, and
softening it would make the sheet a formality. The mock's copy is the settled wording.

**A capability applies at the next agent start, and the sheet must say so** — otherwise a
person presses the button, sees nothing change, and presses it again.

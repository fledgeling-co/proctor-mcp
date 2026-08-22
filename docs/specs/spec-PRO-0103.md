# PRO-0103: A reckoning worth comparing against

**ID:** PRO-0103
**Status:** Needs More Info
**Created:** 2026-08-22
**Last updated:** 2026-08-22
**Brief:** `docs/features-to-triage/94-a-reckoning-worth-comparing-against.md`

## Feature description

# A reckoning worth comparing against

- origin: proposed while running the first reckoning · 2026-08-22
- audience: whoever wants to know whether the not-knowing is shrinking
- platforms: n/a — pipeline bookkeeping
- proposed-by-ai: true

## What and why

The reckoning that ran today is a snapshot, and a snapshot answers the smaller question. It says how
much is unmeasured now. It cannot say whether that figure is falling, and it cannot catch the failure
it most needs to: an item quietly reclassified from unmeasured to something else across runs, until
nothing remembers it was never checked.

The tool already carries the mechanism — a ratchet that compares two ledgers and enforces that an
item may leave unmeasured only by being measured. It has nothing to compare against, because this was
the first run. A second run is what turns the ratchet on, and after that the interesting number stops
being the total and becomes the delta.

The honest reason to propose this rather than assume it: a reckoning is only worth repeating if
somebody reads it. One run produced three tool defects and a structural fix worth taking, which is a
decent return, but that is one data point about a tool's first contact with a new repository, not
evidence that the tenth run will earn its keep. So the question this brief really asks is what
cadence makes it useful without making it wallpaper — after a wave closes, before a release, or on a
clock.

## Acceptance sketch

- A second reckoning exists to compare the first against, and the comparison runs rather than being
  described.
- An item that leaves the unmeasured class does so because somebody measured it, and a run that
  cannot show that fails rather than reporting a smaller number.
- The report leads with what changed since the last one, not with the totals.
- Somebody who reads two consecutive reckonings can say whether coverage is improving without
  recomputing anything.
- A cadence is chosen and written down, so the second run is not simply whenever somebody remembers.

## Assumptions made writing this

- Assuming the cadence question is genuinely open rather than obviously "every wave", because the
  cost of a reckoning nobody reads is that the next one gets skipped.
- Assuming the ratchet is worth turning on before the join is perfect, since the delta is meaningful
  even over a partial denominator as long as the denominator is stated.
- Assuming this is proposed rather than asked-for, so deleting this file is the way to say no.

---

<!-- Triage, plan link, and progress sections are appended below. -->

## Triage — 2026-08-22

**Sentinel review:** S1 — Block pending the essential question below. Everything except the
cadence is buildable today and is recorded as an assumption; the cadence is a judgement about
how much of your attention a recurring report is worth, and the proposal itself declines to
guess it. This item was proposed rather than requested, so "not at all" is a real answer and
is offered as one.

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** **nothing customer-facing changes.** A second "what is left" report
  for this project, and a written note saying when the next one runs *(internal)*.
- **What users will see:** a report that opens with what changed since the last one instead of
  with totals, and refuses outright if something stopped being counted as unmeasured without
  anybody having measured it.
- **Behaviour changes:** the interesting number becomes the movement rather than the total.

**Assumptions**
- `[Operations]` The comparison is run, not described. *(a described comparison proves nothing.)*
- `[Operations]` The check is switched on before the matching-up is perfect, with the partial denominator stated. *(the movement is meaningful over a stated floor.)*
- `[Operations]` The second report is taken after the report tool's known misreadings are repaired. *(comparing against a run with three known faults measures the faults.)*
- `[Operations]` The first report stays as it is and is not re-run to make a tidier baseline. *(a baseline edited to suit is not a baseline.)*
- `[Operations]` A run that cannot show something was measured fails rather than reporting a smaller number. *(that failure is the whole point of the check.)*

**Essential Questions**
1. *[Operations]* How often should this report run — and should it run again at all? The
   proposal is honest that one run is one data point: it returned three tool faults and a
   structural fix, which is a decent first contact with a new project and no evidence about
   the tenth run. Whichever you pick becomes the written cadence, which is the fifth thing the
   proposal asks for.
   a) When a wave closes *(this is my lean, not a finding: the project already has a natural
      boundary there, and it ties the report to a moment when the answer would change
      something. I have not measured what a second run costs, so the lean is weak.)*
   b) Before a release only — rarer, tied to a moment somebody is already reading carefully.
   c) On a clock (weekly, monthly — say which).
   d) Not again. Retire this item; the first report was worth having and a second is not.
      *(The proposal named deleting its own file as the way to decline. Triage consumed that
      file into this record, so retiring this record is now what deletion meant.)*

*Easy reply — edit your answer under the question (or correct any assumption), then re-run
`/triage PRO-0103`:*
> `1. <a | b | c + interval | d>`

*Once that is answered I'll mark this Ready for Implementation Plan.*

---

### Pipeline record — PRO-0103 *(machine trailer; not part of the review above)*

- The comparison mechanism exists and was read rather than assumed: `ratchet(prev, cur)` at
  `reckon.py:725` in `~/Dev/fledgeling-plugins/plugins/reckon/skills/reckon/scripts/`, exposed
  as the `ratchet` subcommand, exit code 3 on a violation. It needs two ledgers; only
  `docs/reckoning/2026-08-22/ledger.json` exists.
- Divergence test on the question: options (a), (b) and (c) produce the same build and differ
  only in one written line, which would normally make this an assumption. It survives as a
  question because option (d) exists — the item is `proposed-by-ai: true`, the proposal names
  deletion as the way to decline, and no default can choose deletion on the owner's behalf.
- Sequencing recorded rather than asked: this item depends on PRO-0102 landing first, per the
  third assumption.

---

### Out-of-family spec review — PRO-0100, PRO-0101, PRO-0102, PRO-0103

*(Shared record for all four items triaged 2026-08-22; the other three specs point here.)*

**Lane:** `agy --model gemini-3.7-flash-high`, read-only, grounded in this tree.
**Lane accounting:** the preferred lane, codex `gpt-5.6-sol`, is switched off for this
repository; the `grok` lane returned **402, balance exhausted** earlier today and was not
retried. Gemini is out-of-family, so this is a lane substitution, **not** an in-family
downgrade — no fully in-family fallback was needed.

**Verdicts:** AGREE on PRO-0100, PRO-0101, PRO-0102 with zero objections. DISAGREE on
PRO-0103, arguing it should be Ready with an assumed cadence. Three objections raised.

**Tally: 1 accepted, 2 rejected.**

- **Accepted** — that option (d) as first written treated deleting the proposal file as the
  live opt-out, when triage had already consumed that file. The option is reworded above to
  say what declining now means.
- **Rejected** — "options a, b and c produce the same build, so the cadence is an assumption."
  The divergence test was already run and recorded, and the same-build reading is why. It does
  not settle the question, because the written cadence is itself the fifth thing the proposal
  asks for: the deliverable is the decision, not a setting on one. How often a recurring report
  is worth reading is a judgement about the owner's attention, and the item's own reasoning is
  that the cost of a report nobody reads is the next one being skipped.
- **Rejected** — "no implementation blocker remains." Correct and not the bar. Triage blocks on
  what only the owner can settle, not on what the builder cannot start; option (d) is exactly
  that, and no default may choose retirement on the owner's behalf for an item nobody asked
  for.

No objection reached Critical or High, and none exposed an external dependency wearing a
default, so nothing escalated to a new Essential Question.

**Assumptions gate:** this run is unattended, so the recorded assumptions were checked against
"would this surprise the owner?" by the same out-of-family reviewer above, which reported none
in that class across the four items.

---
generated-by: tailings
tailings-sources: [A279]
reckon-sources: [REQ-120, REQ-122]
status: to-triage
---
# Nothing counts the ledger's status words

- origin: tailings pass over Wave 27 · 2026-08-25
- audience: Anyone reporting a backlog's state from the ledger
- platforms: n/a
- proposed-by-ai: false

## What and why
A wave was reported as every row merged. The ledger held two rows in a different terminal state, so the figure was wrong by two while the sentence built on it — that nothing was outstanding — was right. The gate over the ledger checks that each row has a spec on disk and that git agrees with the status, and never counts how the statuses are distributed, so both the true sentence and the false figure passed it.

A status distribution is the cheapest possible check and it is the figure people quote. Publishing it removes the step where somebody counts by eye and rounds two rows into a headline.

## Acceptance sketch
- The status distribution across all ledger rows is published, summing to the row count
- A terminal status that is not the merged one is named rather than folded into it
- A status word the gate does not recognise is reported rather than counted as one of the known ones
- A report quoting a merged count can be checked against the distribution without recounting
- The outstanding count and the merged count are stated as separate figures

## Assumptions made writing this
- Assuming the terminal statuses are worth distinguishing in the headline rather than collapsing, since a retired row and a merged row were reached differently
- Assuming the distribution belongs beside the existing gate rather than in a new one

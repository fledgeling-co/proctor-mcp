---
generated-by: tailings
tailings-sources: [A278]
reckon-sources: [REQ-120, REQ-134]
status: to-triage
---
# A gate that reads the number and not the word

- origin: tailings pass over Wave 27 · 2026-08-25
- audience: Anyone planning from a committed evidence page or a delivery note
- platforms: n/a
- proposed-by-ai: false

## What and why
A committed evidence page stated that a test run failed, under a heading saying the work was complete. The gate written to catch exactly that kind of drift passed over it: it matches a figure and its subject, reads the number, and never reads the verdict the same sentence carries. So a page can say a suite failed while the gate above it stays green.

The figure and the verdict travel together in the sentence a person reads, and a scanner that takes one and ignores the other measures the easier half. A verdict word beside a figure is as checkable as the figure — more so, since the vocabulary is small and closed.

## Acceptance sketch
- A stated figure is read together with the verdict word in the same sentence
- A page asserting a failure under a heading asserting success is reported
- A verdict word the scanner cannot classify is reported rather than ignored
- The report distinguishes a wrong number from a right number beside a wrong word
- An evidence page written from a temporary file that has since changed is reported as stale

## Assumptions made writing this
- Assuming the verdict vocabulary is small and closed enough to enumerate, rather than needing a model to read prose
- Assuming a page with no verdict word at all is unbacked rather than contradicted

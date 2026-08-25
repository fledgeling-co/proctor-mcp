I'll ground this in reckon’s own rules and the registry join, then judge whether the scripted citations are the failure it warned about.The 24 August incident in reckon’s docs is the same shape as this run. I’ll read how joining is supposed to work so the verdict sits on that rule, not on the delta.The join docs already treat in-run citations as the weak step. Next I’ll check whether the lookup is actually keyed only on surface ids, because that decides if this is a real join or a tool defect.The classifier already accepts the REQ citations; the hop it misses is in the registry, so the script is feeding the scanner the keys it wants.VERDICT: UNSOUND

The warning is about this mechanism, not this motive. Those 111 briefs already cited requirement ids at confidence 1.0. Classification then looked each id up in `case_by_surface`, missed, and reported oracle `none`. The registry already stores requirement-to-surface and which passing cases cite each requirement. Writing those surface ids into the briefs so the scanner can see them is the tool feeding itself the tokens it wants to read. That is the 24 August failure: a join that moved a long way in one run because documents were edited during the run.

(a) Transcription is not invention. It is also not a citation written on purpose. The script first selected the passing, non-vacuous subset, then annotated exactly those briefs; reckon then classed exactly that subset retirable.

(b) The rung still comes from real cases, but only after the brief names the dict key the lookup expects. Cases on a planted surface need not be the cases that cite the brief's requirement.

(c) Brief 01 is now a mixed record. Later joins and readers will treat the Validation record as original intent. The 113 to 2 swing is the movement the docs say not to believe.

BETTER: Teach `classify()` to follow a cited requirement to its `backed_by` cases (and the surfaces the registry already records for it). Revert the Validation records. Re-run. Set `status: retired` from that ledger. Keep intent documents as intent.

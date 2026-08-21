# PRO-0097 — the reconciliation of the 23 (24 with the row a merge had dropped)

One row per defect that read `open` when this item started. `Settled by` names the item whose
work closed it and the note on each record carries the citation that was read to establish it.

| Id | Status after | Settled by | What |
|---|---|---|---|
| DEF-024 | fixed | PRO-0089; row restored and reconciled by PRO-0097 | A bounded-probe test asserts wall-clock elapsed and fails on a loaded  |
| DEF-025 | fixed | PRO-0088 (as DEF-097); reconciled by PRO-0097 | proctor_capture reports a fully transparent frame as status complete a |
| DEF-026 | open | left open | A run whose MCP peer dies keeps the agent queue past the 900-second pa |
| DEF-027 | open | left open | Forty events swallowed by the takeover block produced no yield and no  |
| DEF-028 | fixed | PRO-0088 (as DEF-095/DEF-096); reconciled by PRO-0097 | An agent window reports sharingState 1 where CASE-0032 records all thr |
| DEF-029 | fixed | PRO-0089; reconciled by PRO-0097 | A bounded-probe test asserts wall-clock elapsed and fails on a loaded  |
| DEF-040 | fixed | PRO-0091; the dropped value restored by PRO-0097 | REQ-024's declared effect class and provider name a boundary the brows |
| DEF-041 | fixed | PRO-0091, released in test-campaign 0.9.4; reconciled by PRO-0097 | campaign.py check prints a capped list of unwitnessed requirements, an |
| DEF-042 | fixed | PRO-0089; reconciled by PRO-0097 | PolicyStore has no test seam, so a test that configures the policy wri |
| DEF-043 | fixed | PRO-0087, verified by PRO-0095 (as DEF-100); reconciled by PRO-0097 | Session.doctor blocks a cooperative thread inside SecStaticCodeCheckVa |
| DEF-044 | fixed | PRO-0087 (as DEF-050); reconciled by PRO-0097 | SignatureVerdictCache verifies outside its own lock, so N cold caches  |
| DEF-030 | fixed | left open | The census control exercises one of the gate's two passes, so unclasse |
| DEF-032 | fixed | left open | The mutation runner's integer-literal operator mutates closure shortha |
| DEF-033 | open | left open | Nineteen of twenty-two trustworthy-scored ProctorAgent mutants survive |
| DEF-035 | fixed | PRO-0081; reconciled by PRO-0097 | StatusSurface.Copy held three sentences the status window has never re |
| DEF-037 | open | left open | The status window's agent-not-answering branch cannot be reached, and  |
| DEF-039 | open | left open | Four sibling views in ProctorUI hold 258 user-facing string literals t |
| DEF-055 | fixed | left open | CASE-0074's note records a starting load of 11.20 where its own eviden |
| DEF-056 | open | left open | Both walkthrough grant rows draw a prominent button, so nothing says w |
| DEF-057 | fixed | left open | Four cases carry an oracle rung that is not on the ladder, so they cou |
| DEF-058 | fixed | left open | An orchestrator merge silently dropped a flow, unpublishing a judged c |
| DEF-051 | fixed | PRO-0089; reconciled by PRO-0097 | ScreenRecordingProbeWiringTests's 0.2s bound with 5s of headroom fails |
| DEF-099 | open | left open | REQ-028 cites a source file the branch under test does not contain |
| DEF-106 | open | left open | A bounded socket client's test asserts measured elapsed time against a |

Counts: 24 examined, 16 flipped to `fixed`, 8 left `open` (DEF-106 closes later in this item).

The eleven values a merge had dropped are restored from the commits that set them; see
`dropped-values.txt` in this directory.

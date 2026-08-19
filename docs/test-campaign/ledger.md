# proctor-mcp — campaign ledger

Lanes: macos, mcp-stdio, cli

**Sample:** full multi-witness coverage across all 21 MCP tools, status/walkthrough/overlay UI surfaces, and guest/takeover controls

16 surfaces · 8 flows · 14 components · 28 cases
26 pass · 0 fail · 0 skip · 2 n/a · 0 open · armed 26/26

| Case | Surface | State | Lane | Status | Armed | Evidence |
|---|---|---|---|---|---|---|
| CASE-0001 | SURF-001  |  |  | pass | yes | 2 |
| CASE-0002 | SURF-002  |  |  | pass | yes | 1 |
| CASE-0003 | SURF-003  |  |  | pass | yes | 1 |
| CASE-0014 | SURF-003  |  |  | pass | yes | 1 |
| CASE-0026 | SURF-003  |  |  | pass | yes | 1 |
| CASE-0004 | SURF-004  |  |  | pass | yes | 2 |
| CASE-0008 | SURF-004  |  |  | n/a: Run HUD sets sharingType=.none (RunHUDPanel.ensurePanel); ScreenCaptureKit cannot photograph it. On-Space attach of win:3:3 352×200 with doctor hud.onScreen=true still captureFailed at 8000ms (no PNG written; instrument said "not on the active Space" while attach isOnActiveSpace=false). Off-Space earlier: SCFrameStatus=.none. Design-sprite copies (260² character states) and the Status-window 476×514 file were removed from the wall; they are not HUD frames. | yes | 0 |
| CASE-0021 | SURF-004  |  |  | pass | yes | 1 |
| CASE-0009 | SURF-005  |  |  | pass | yes | 1 |
| CASE-0010 | SURF-005  |  |  | n/a: Takeover overlay is excluded from capture (sharingType=.none, TakeoverOverlay). Window-scoped SCK of Agent display windows returned SCFrameStatus=complete of 100% transparent frames (3456×2234 and 5120×2880, unique_sample=1, meanRGBA 0,0,0,0) — completeness is not the shield. The 1024² sprite-states sheet was removed from the wall; it is not the shield. | yes | 0 |
| CASE-0005 | SURF-006  |  |  | pass | yes | 1 |
| CASE-0006 | SURF-006  |  |  | pass | yes | 1 |
| CASE-0007 | SURF-007  |  |  | pass | yes | 1 |
| CASE-0011 | SURF-008  |  |  | pass | yes | 1 |
| CASE-0027 | SURF-008  |  |  | pass | yes | 2 |
| CASE-0028 | SURF-008  |  |  | pass | yes | 4 |
| CASE-0012 | SURF-009  |  |  | pass | yes | 1 |
| CASE-0013 | SURF-010  |  |  | pass | yes | 1 |
| CASE-0015 | SURF-011  |  |  | pass | yes | 1 |
| CASE-0016 | SURF-011  |  |  | pass | yes | 1 |
| CASE-0017 | SURF-012  |  |  | pass | yes | 1 |
| CASE-0018 | SURF-012  |  |  | pass | yes | 1 |
| CASE-0019 | SURF-013  |  |  | pass | yes | 1 |
| CASE-0020 | SURF-013  |  |  | pass | yes | 1 |
| CASE-0022 | SURF-014  |  |  | pass | yes | 1 |
| CASE-0023 | SURF-015  |  |  | pass | yes | 1 |
| CASE-0025 | SURF-015  |  |  | pass | yes | 1 |
| CASE-0024 | SURF-016  |  |  | pass | yes | 2 |

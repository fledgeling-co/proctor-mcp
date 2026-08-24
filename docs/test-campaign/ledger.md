# proctor-mcp — campaign ledger

Lanes: macos, mcp-stdio, cli

**Sample:** full multi-witness coverage across all 21 MCP tools, status/walkthrough/overlay UI surfaces, and guest/takeover controls

40 surfaces · 11 flows · 14 components · 467 cases
464 pass · 0 fail · 0 skip · 3 n/a · 0 open · armed 446/464

| Case | Surface | State | Lane | Status | Armed | Evidence |
|---|---|---|---|---|---|---|
| CASE-0001 | SURF-001  |  |  | pass | yes | 2 |
| CASE-0038 | SURF-001  |  |  | pass | yes | 1 |
| CASE-0002 | SURF-002  |  |  | pass | yes | 2 |
| CASE-0074 | SURF-002  |  |  | pass | yes | 2 |
| CASE-0102 | SURF-002  |  | headless | pass | yes | 5 |
| CASE-0103 | SURF-002  |  | headless | pass | yes | 1 |
| CASE-0104 | SURF-002  |  | headless | pass | yes | 5 |
| CASE-0105 | SURF-002  |  | headless | pass | yes | 1 |
| CASE-0154 | SURF-002  |  | headless | pass | yes | 2 |
| CASE-0370 | SURF-002  |  | headless | pass | yes | 4 |
| CASE-0372 | SURF-002  |  | headless | pass | yes | 4 |
| CASE-0373 | SURF-002  |  | headless | pass | yes | 4 |
| CASE-0374 | SURF-002  |  | headless | pass | yes | 4 |
| CASE-0397 | SURF-002  |  | headless | pass | yes | 4 |
| CASE-0398 | SURF-002  |  | headless | pass | yes | 3 |
| CASE-0399 | SURF-002  |  | headless | pass | yes | 3 |
| CASE-0400 | SURF-002  |  | headless | pass |  | 2 |
| CASE-0457 | SURF-002  |  | headless | pass | yes | 3 |
| CASE-0458 | SURF-002  |  | headless | pass | yes | 3 |
| CASE-0459 | SURF-002  |  | headless | pass | yes | 3 |
| CASE-0460 | SURF-002  |  | headless | pass | yes | 3 |
| CASE-0461 | SURF-002  |  | headless | pass | yes | 3 |
| CASE-0462 | SURF-002  |  | headless | pass | yes | 3 |
| CASE-0469 | SURF-002  |  | headless | pass | yes | 2 |
| CASE-0470 | SURF-002  |  | headless | pass | yes | 3 |
| CASE-0471 | SURF-002  |  | headless | pass | yes | 3 |
| CASE-0003 | SURF-003  |  |  | pass | yes | 1 |
| CASE-0014 | SURF-003  |  |  | pass | yes | 1 |
| CASE-0026 | SURF-003  |  |  | pass | yes | 1 |
| CASE-0069 | SURF-003  |  | macos-glass | pass | yes | 8 |
| CASE-0070 | SURF-003  |  | macos-glass | pass | yes | 2 |
| CASE-0087 | SURF-003  |  |  | pass | yes | 8 |
| CASE-0075 | SURF-003  |  |  | pass | yes | 2 |
| CASE-0138 | SURF-003  |  | headless | pass | yes | 1 |
| CASE-0110 | SURF-003  |  |  | pass | yes | 2 |
| CASE-0112 | SURF-003  |  |  | pass | yes | 2 |
| CASE-0113 | SURF-003  |  |  | pass |  | 2 |
| CASE-0115 | SURF-003  |  |  | pass | yes | 3 |
| CASE-0116 | SURF-003  |  |  | pass | yes | 2 |
| CASE-0197 | SURF-003  |  |  | pass | yes | 2 |
| CASE-0242 | SURF-003  |  | headless | pass | yes | 2 |
| CASE-0243 | SURF-003  |  | headless | pass | yes | 2 |
| CASE-0244 | SURF-003  |  | headless | pass | yes | 2 |
| CASE-0004 | SURF-004  |  |  | pass | yes | 2 |
| CASE-0008 | SURF-004  |  |  | pass | yes | 2 |
| CASE-0021 | SURF-004  |  |  | pass | yes | 1 |
| CASE-0030 | SURF-004  |  |  | pass | yes | 2 |
| CASE-0032 | SURF-004  |  |  | pass | yes | 4 |
| CASE-0065 | SURF-004  |  | macos-glass | pass | yes | 3 |
| CASE-0089 | SURF-004  |  |  | pass | yes | 9 |
| CASE-0079 | SURF-004  |  |  | pass | yes | 2 |
| CASE-0127 | SURF-004  |  |  | pass | yes | 3 |
| CASE-0128 | SURF-004  |  |  | pass | yes | 3 |
| CASE-0230 | SURF-004  |  | headless | pass | yes | 2 |
| CASE-0231 | SURF-004  |  | headless | pass | yes | 2 |
| CASE-0232 | SURF-004  |  | headless | pass | yes | 2 |
| CASE-0233 | SURF-004  |  | headless | pass | yes | 2 |
| CASE-0234 | SURF-004  |  | headless | pass | yes | 2 |
| CASE-0235 | SURF-004  |  | headless | pass | yes | 2 |
| CASE-0241 | SURF-004  |  | headless | pass | yes | 2 |
| CASE-0245 | SURF-004  |  | headless | n/a: Proctor never observes the driver's cursor, so no instrument on this lane can read whether that cursor is over a covered target. The reachable half was measured and agreed: CASE-0242 shows a non-suppressible driver leaves the run recording deferredToDriver, the state in which Proctor draws no pointer of its own. |  | 2 |
| CASE-0246 | SURF-004  |  | macos | n/a: the runs the report's first clause describes are driven by another automation stack entirely, so there is no Proctor run to instrument. What WAS measured is the attribution, and it is exact. |  | 2 |
| CASE-0218 | SURF-004  |  | headless | pass | yes | 3 |
| CASE-0262 | SURF-004  |  | headless | pass | yes | 3 |
| CASE-0290 | SURF-004  |  | headless | pass | yes | 3 |
| CASE-0291 | SURF-004  |  | headless | pass | yes | 2 |
| CASE-0292 | SURF-004  |  | headless | pass | yes | 2 |
| CASE-0293 | SURF-004  |  | headless | pass | yes | 1 |
| CASE-0297 | SURF-004  |  | headless | pass | yes | 2 |
| CASE-0298 | SURF-004  |  | headless | pass | yes | 2 |
| CASE-0299 | SURF-004  |  | headless | pass | yes | 1 |
| CASE-0393 | SURF-004  |  | headless | pass | yes | 3 |
| CASE-0463 | SURF-004  |  | headless | pass | yes | 3 |
| CASE-0464 | SURF-004  |  | headless | pass | yes | 3 |
| CASE-0009 | SURF-005  |  |  | pass | yes | 1 |
| CASE-0010 | SURF-005  |  |  | pass | yes | 2 |
| CASE-0031 | SURF-005  |  |  | pass | yes | 2 |
| CASE-0052 | SURF-005  |  |  | pass | yes | 1 |
| CASE-0053 | SURF-005  |  |  | pass | yes | 1 |
| CASE-0054 | SURF-005  |  |  | pass | yes | 1 |
| CASE-0058 | SURF-005  |  |  | pass | yes | 2 |
| CASE-0066 | SURF-005  |  | macos-glass | pass | yes | 4 |
| CASE-0067 | SURF-005  |  | macos-glass | n/a: PersonInput.isAPerson requires sourcePid == 0, which only hardware carries and no second process can forge, so the human-input path REQ-007 names cannot be driven by any instrument available on this lane. The instrument that would settle it is a physical HID event during a held run, or a signed virtual HID driver posting at pid 0. The reachable half was measured and did not yield: 40 events swallowed by the takeover tap across three runs produced no yield record and no held reason. |  | 9 |
| CASE-0068 | SURF-005  |  | macos-glass | pass | yes | 6 |
| CASE-0236 | SURF-005  |  | headless | pass | yes | 2 |
| CASE-0237 | SURF-005  |  | headless | pass | yes | 2 |
| CASE-0238 | SURF-005  |  | headless | pass | yes | 2 |
| CASE-0294 | SURF-005  |  | headless | pass | yes | 3 |
| CASE-0295 | SURF-005  |  | headless | pass | yes | 1 |
| CASE-0296 | SURF-005  |  | headless | pass | yes | 3 |
| CASE-0465 | SURF-005  |  | headless | pass | yes | 3 |
| CASE-0005 | SURF-006  |  |  | pass | yes | 1 |
| CASE-0006 | SURF-006  |  |  | pass | yes | 1 |
| CASE-0064 | SURF-006  |  | macos-glass | pass | yes | 9 |
| CASE-0077 | SURF-006  |  |  | pass | yes | 2 |
| CASE-0135 | SURF-006  |  | headless | pass | yes | 2 |
| CASE-0136 | SURF-006  |  | headless | pass | yes | 1 |
| CASE-0137 | SURF-006  |  | headless | pass | yes | 1 |
| CASE-0120 | SURF-006  |  |  | pass | yes | 2 |
| CASE-0121 | SURF-006  |  |  | pass | yes | 1 |
| CASE-0122 | SURF-006  |  |  | pass | yes | 1 |
| CASE-0123 | SURF-006  |  |  | pass | yes | 1 |
| CASE-0124 | SURF-006  |  |  | pass | yes | 1 |
| CASE-0125 | SURF-006  |  |  | pass | yes | 1 |
| CASE-0126 | SURF-006  |  |  | pass | yes | 2 |
| CASE-0129 | SURF-006  |  |  | pass | yes | 3 |
| CASE-0199 | SURF-006  |  |  | pass | yes | 2 |
| CASE-0216 | SURF-006  |  | headless | pass | yes | 2 |
| CASE-0217 | SURF-006  |  | headless | pass | yes | 2 |
| CASE-0007 | SURF-007  |  |  | pass | yes | 1 |
| CASE-0011 | SURF-008  |  |  | pass | yes | 1 |
| CASE-0027 | SURF-008  |  |  | pass | yes | 2 |
| CASE-0028 | SURF-008  |  |  | pass | yes | 1 |
| CASE-0029 | SURF-008  |  |  | pass | yes | 1 |
| CASE-0039 | SURF-008  |  |  | pass | yes | 2 |
| CASE-0042 | SURF-008  |  |  | pass | yes | 1 |
| CASE-0062 | SURF-008  |  |  | pass | yes | 4 |
| CASE-0084 | SURF-008  |  |  | pass | yes | 6 |
| CASE-0111 | SURF-008  |  |  | pass | yes | 2 |
| CASE-0253 | SURF-008  |  | headless | pass | yes | 3 |
| CASE-0254 | SURF-008  |  | headless | pass | yes | 3 |
| CASE-0255 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0256 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0261 | SURF-008  |  | headless | pass | yes | 5 |
| CASE-0263 | SURF-008  |  | headless | pass | yes | 3 |
| CASE-0264 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0265 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0276 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0277 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0278 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0279 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0280 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0281 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0282 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0350 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0351 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0352 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0355 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0356 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0357 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0358 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0359 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0363 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0368 | SURF-008  |  | headless | pass | yes | 2 |
| CASE-0369 | SURF-008  |  | headless | pass | yes | 6 |
| CASE-0012 | SURF-009  |  |  | pass | yes | 1 |
| CASE-0100 | SURF-009  |  | macos-glass | pass | yes | 3 |
| CASE-0101 | SURF-009  |  | macos-glass | pass | yes | 1 |
| CASE-0106 | SURF-009  |  | macos-glass | pass | yes | 2 |
| CASE-0250 | SURF-009  |  | headless | pass | yes | 3 |
| CASE-0251 | SURF-009  |  | headless | pass | yes | 3 |
| CASE-0252 | SURF-009  |  | headless | pass | yes | 2 |
| CASE-0267 | SURF-009  |  | headless | pass | yes | 2 |
| CASE-0310 | SURF-009  |  | headless | pass | yes | 3 |
| CASE-0311 | SURF-009  |  | headless | pass | yes | 2 |
| CASE-0312 | SURF-009  |  | headless | pass | yes | 3 |
| CASE-0313 | SURF-009  |  | headless | pass | yes | 3 |
| CASE-0319 | SURF-009  |  | headless | pass | yes | 4 |
| CASE-0314 | SURF-009  |  | headless | pass | yes | 2 |
| CASE-0315 | SURF-009  |  | headless | pass | yes | 3 |
| CASE-0317 | SURF-009  |  | headless | pass | yes | 3 |
| CASE-0316 | SURF-009  |  | macos-glass | pass | yes | 3 |
| CASE-0318 | SURF-009  |  | macos-glass | pass | yes | 2 |
| CASE-0365 | SURF-009  |  | headless | pass | yes | 2 |
| CASE-0366 | SURF-009  |  | headless | pass | yes | 2 |
| CASE-0367 | SURF-009  |  | headless | pass | yes | 2 |
| CASE-0390 | SURF-009  |  | headless | pass | yes | 4 |
| CASE-0391 | SURF-009  |  | headless | pass | yes | 5 |
| CASE-0392 | SURF-009  |  | headless | pass | yes | 3 |
| CASE-0013 | SURF-010  |  |  | pass | yes | 1 |
| CASE-0037 | SURF-010  |  |  | pass | yes | 1 |
| CASE-0257 | SURF-010  |  | headless | pass | yes | 5 |
| CASE-0258 | SURF-010  |  | headless | pass | yes | 3 |
| CASE-0259 | SURF-010  |  | headless | pass | yes | 2 |
| CASE-0260 | SURF-010  |  | headless | pass | yes | 2 |
| CASE-0266 | SURF-010  |  | headless | pass | yes | 2 |
| CASE-0015 | SURF-011  |  |  | pass | yes | 1 |
| CASE-0016 | SURF-011  |  |  | pass | yes | 1 |
| CASE-0071 | SURF-011  |  | macos-glass | pass | yes | 4 |
| CASE-0017 | SURF-012  |  |  | pass | yes | 1 |
| CASE-0018 | SURF-012  |  |  | pass | yes | 1 |
| CASE-0061 | SURF-012  |  |  | pass | yes | 4 |
| CASE-0076 | SURF-012  |  |  | pass | yes | 2 |
| CASE-0078 | SURF-012  |  |  | pass | yes | 2 |
| CASE-0130 | SURF-012  |  | headless | pass | yes | 1 |
| CASE-0131 | SURF-012  |  | headless | pass | yes | 3 |
| CASE-0132 | SURF-012  |  | headless | pass | yes | 2 |
| CASE-0133 | SURF-012  |  | headless | pass | yes | 1 |
| CASE-0134 | SURF-012  |  | headless | pass | yes | 1 |
| CASE-0114 | SURF-012  |  |  | pass | yes | 3 |
| CASE-0190 | SURF-012  |  |  | pass | yes | 2 |
| CASE-0191 | SURF-012  |  |  | pass | yes | 2 |
| CASE-0192 | SURF-012  |  |  | pass | yes | 2 |
| CASE-0193 | SURF-012  |  |  | pass | yes | 2 |
| CASE-0198 | SURF-012  |  |  | pass | yes | 2 |
| CASE-0270 | SURF-012  |  | headless | pass | yes | 6 |
| CASE-0271 | SURF-012  |  | headless | pass | yes | 5 |
| CASE-0272 | SURF-012  |  | headless | pass | yes | 2 |
| CASE-0273 | SURF-012  |  | headless | pass | yes | 2 |
| CASE-0274 | SURF-012  |  | headless | pass | yes | 2 |
| CASE-0275 | SURF-012  |  | headless | pass | yes | 2 |
| CASE-0285 | SURF-012  |  | headless | pass | yes | 3 |
| CASE-0320 | SURF-012  |  | headless | pass | yes | 3 |
| CASE-0330 | SURF-012  |  | headless | pass | yes | 5 |
| CASE-0331 | SURF-012  |  | headless | pass | yes | 5 |
| CASE-0332 | SURF-012  |  | headless | pass | yes | 5 |
| CASE-0333 | SURF-012  |  | headless | pass | yes | 4 |
| CASE-0334 | SURF-012  |  | headless | pass | yes | 4 |
| CASE-0335 | SURF-012  |  | headless | pass | yes | 3 |
| CASE-0360 | SURF-012  |  | headless | pass | yes | 2 |
| CASE-0361 | SURF-012  |  | headless | pass | yes | 2 |
| CASE-0362 | SURF-012  |  | headless | pass | yes | 2 |
| CASE-0364 | SURF-012  |  | headless | pass | yes | 2 |
| CASE-0394 | SURF-012  |  | headless | pass | yes | 3 |
| CASE-0466 | SURF-012  |  | headless | pass | yes | 3 |
| CASE-0336 | SURF-012  |  | headless | pass | yes | 2 |
| CASE-0019 | SURF-013  |  |  | pass | yes | 1 |
| CASE-0020 | SURF-013  |  |  | pass | yes | 1 |
| CASE-0059 | SURF-013  |  |  | pass | yes | 4 |
| CASE-0371 | SURF-013  |  | headless | pass | yes | 5 |
| CASE-0022 | SURF-014  |  |  | pass | yes | 2 |
| CASE-0060 | SURF-014  |  |  | pass | yes | 4 |
| CASE-0023 | SURF-015  |  |  | pass | yes | 1 |
| CASE-0025 | SURF-015  |  |  | pass | yes | 1 |
| CASE-0088 | SURF-015  |  |  | pass | yes | 5 |
| CASE-0024 | SURF-016  |  |  | pass | yes | 2 |
| CASE-0033 | SURF-017  |  |  | pass | yes | 2 |
| CASE-0034 | SURF-017  |  |  | pass | yes | 2 |
| CASE-0035 | SURF-017  |  |  | pass | yes | 1 |
| CASE-0036 | SURF-017  |  |  | pass | yes | 1 |
| CASE-0040 | SURF-017  |  |  | pass | yes | 3 |
| CASE-0041 | SURF-017  |  |  | pass | yes | 2 |
| CASE-0043 | SURF-017  |  | macos | pass | yes | 1 |
| CASE-0082 | SURF-017  |  |  | pass | yes | 6 |
| CASE-0083 | SURF-017  |  |  | pass | yes | 6 |
| CASE-0353 | SURF-017  |  | headless | pass | yes | 2 |
| CASE-0354 | SURF-017  |  | headless | pass | yes | 2 |
| CASE-0044 | SURF-018  |  |  | pass | yes | 2 |
| CASE-0045 | SURF-018  |  |  | pass | yes | 1 |
| CASE-0046 | SURF-018  |  |  | pass | yes | 2 |
| CASE-0057 | SURF-018  |  |  | pass | yes | 1 |
| CASE-0080 | SURF-018  |  |  | pass | yes | 8 |
| CASE-0081 | SURF-018  |  |  | pass | yes | 6 |
| CASE-0047 | SURF-019  |  |  | pass | yes | 1 |
| CASE-0050 | SURF-019  |  |  | pass | yes | 1 |
| CASE-0056 | SURF-019  |  | guest-glass | pass | yes | 3 |
| CASE-0085 | SURF-019  |  |  | pass | yes | 6 |
| CASE-0048 | SURF-020  |  |  | pass | yes | 1 |
| CASE-0049 | SURF-020  |  |  | pass | yes | 1 |
| CASE-0055 | SURF-020  |  |  | pass | yes | 1 |
| CASE-0086 | SURF-020  |  |  | pass | yes | 6 |
| CASE-0051 | SURF-021  |  |  | pass | yes | 1 |
| CASE-0063 | SURF-022  |  |  | pass | yes | 8 |
| CASE-0072 | SURF-022  |  |  | pass | yes | 1 |
| CASE-0073 | SURF-022  |  |  | pass | yes | 2 |
| CASE-0139 | SURF-022  |  | headless | pass | yes | 6 |
| CASE-0150 | SURF-022  |  | headless | pass | yes | 1 |
| CASE-0151 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0152 | SURF-022  |  | headless | pass | yes | 1 |
| CASE-0153 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0155 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0156 | SURF-022  |  | headless | pass | yes | 1 |
| CASE-0157 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0158 | SURF-022  |  | headless | pass | yes | 1 |
| CASE-0159 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0194 | SURF-022  |  |  | pass | yes | 2 |
| CASE-0195 | SURF-022  |  |  | pass | yes | 2 |
| CASE-0196 | SURF-022  |  |  | pass | yes | 2 |
| CASE-0200 | SURF-022  |  | headless | pass | yes | 1 |
| CASE-0210 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0211 | SURF-022  |  | headless | pass | yes | 1 |
| CASE-0212 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0213 | SURF-022  |  | headless | pass | yes | 1 |
| CASE-0214 | SURF-022  |  | headless | pass | yes | 1 |
| CASE-0215 | SURF-022  |  | headless | pass | yes | 1 |
| CASE-0219 | SURF-022  |  | headless | pass | yes | 4 |
| CASE-0220 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0221 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0222 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0223 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0224 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0268 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0269 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0283 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0284 | SURF-022  |  | headless | pass | yes | 5 |
| CASE-0395 | SURF-022  |  | headless | pass | yes | 5 |
| CASE-0396 | SURF-022  |  | headless | pass |  | 3 |
| CASE-0545 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0546 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0547 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0550 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0560 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0563 | SURF-022  |  | headless | pass | yes | 2 |
| CASE-0410 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0411 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0412 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0413 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0414 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0415 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0416 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0417 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0418 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0419 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0420 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0421 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0422 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0423 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0424 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0425 | SURF-023  |  | headless | pass | yes | 3 |
| CASE-0426 | SURF-023  |  | headless | pass | yes | 4 |
| CASE-0427 | SURF-023  |  | headless | pass | yes | 4 |
| CASE-0428 | SURF-023  |  | headless | pass | yes | 4 |
| CASE-0429 | SURF-023  |  | headless | pass | yes | 5 |
| CASE-0500 | SURF-023  | classifying | headless | pass | yes | 1 |
| CASE-0501 | SURF-023  | classifying | headless | pass | yes | 1 |
| CASE-0502 | SURF-023  | classifying | headless | pass | yes | 1 |
| CASE-0503 | SURF-023  | classifying | headless | pass | yes | 1 |
| CASE-0504 | SURF-023  | classifying | headless | pass | yes | 1 |
| CASE-0505 | SURF-023  | classifying | headless | pass | yes | 1 |
| CASE-0506 | SURF-023  | classifying | headless | pass | yes | 1 |
| CASE-0507 | SURF-023  | reporting | headless | pass | yes | 2 |
| CASE-0508 | SURF-023  | reporting | headless | pass | yes | 1 |
| CASE-0509 | SURF-023  | reporting | headless | pass | yes | 2 |
| CASE-0510 | SURF-023  | reporting | headless | pass | yes | 1 |
| CASE-0511 | SURF-023  | reporting | headless | pass | yes | 1 |
| CASE-0512 | SURF-023  | reporting | headless | pass | yes | 1 |
| CASE-0513 | SURF-023  | classifying | headless | pass | yes | 1 |
| CASE-0514 | SURF-023  | classifying | headless | pass | yes | 1 |
| CASE-0515 | SURF-023  | reporting | headless | pass | yes | 1 |
| CASE-0516 | SURF-023  | classifying | headless | pass | yes | 1 |
| CASE-0527 | SURF-023  | classifying | headless | pass | yes | 2 |
| CASE-0441 | SURF-025  |  | headless | pass | yes | 3 |
| CASE-0442 | SURF-025  |  | headless | pass | yes | 2 |
| CASE-0443 | SURF-025  |  | headless | pass | yes | 3 |
| CASE-0444 | SURF-025  |  | headless | pass | yes | 2 |
| CASE-0445 | SURF-025  |  | headless | pass | yes | 2 |
| CASE-0446 | SURF-025  |  | headless | pass | yes | 2 |
| CASE-0447 | SURF-025  |  | headless | pass | yes | 2 |
| CASE-0448 | SURF-025  |  | headless | pass | yes | 3 |
| CASE-0449 | SURF-025  |  | headless | pass | yes | 2 |
| CASE-0450 | SURF-025  |  | headless | pass | yes | 2 |
| CASE-0451 | SURF-025  |  | headless | pass | yes | 2 |
| CASE-0452 | SURF-025  |  | headless | pass | yes | 2 |
| CASE-0453 | SURF-025  |  | headless | pass | yes | 2 |
| CASE-0454 | SURF-025  |  | headless | pass | yes | 3 |
| CASE-0455 | SURF-025  |  | headless | pass | yes | 3 |
| CASE-0456 | SURF-025  |  | headless | pass | yes | 2 |
| CASE-0430 | SURF-024  |  | headless | pass | yes | 4 |
| CASE-0431 | SURF-024  |  | headless | pass | yes | 4 |
| CASE-0432 | SURF-024  |  | headless | pass | yes | 5 |
| CASE-0433 | SURF-024  |  | headless | pass | yes | 4 |
| CASE-0434 | SURF-024  |  | headless | pass | yes | 4 |
| CASE-0435 | SURF-024  |  | headless | pass | yes | 4 |
| CASE-0436 | SURF-024  |  | headless | pass | yes | 4 |
| CASE-0437 | SURF-024  |  | headless | pass | yes | 4 |
| CASE-0438 | SURF-024  |  | headless | pass | yes | 5 |
| CASE-0439 | SURF-024  |  | headless | pass | yes | 5 |
| CASE-0440 | SURF-024  |  | headless | pass | yes | 5 |
| CASE-0517 | SURF-024  | cited by path | headless | pass | yes | 2 |
| CASE-0518 | SURF-024  | cited by path | headless | pass | yes | 2 |
| CASE-0519 | SURF-024  | cited by path | headless | pass | yes | 2 |
| CASE-0520 | SURF-024  | registered as unclaimed | headless | pass | yes | 2 |
| CASE-0521 | SURF-024  | registered as unclaimed | headless | pass | yes | 2 |
| CASE-0522 | SURF-024  | registered as unclaimed | headless | pass | yes | 2 |
| CASE-0523 | SURF-024  | registered as unclaimed | headless | pass | yes | 2 |
| CASE-0524 | SURF-024  | cited by path | headless | pass | yes | 2 |
| CASE-0525 | SURF-024  | declared no brief | headless | pass | yes | 2 |
| CASE-0526 | SURF-024  | registered as unclaimed | headless | pass | yes | 2 |
| CASE-0528 | SURF-024  | declared no brief | headless | pass | yes | 2 |
| CASE-0467 | SURF-026  |  | headless | pass | yes | 3 |
| CASE-0468 | SURF-026  |  | headless | pass | yes | 3 |
| CASE-0540 | SURF-026  |  | headless | pass | yes | 2 |
| CASE-0541 | SURF-026  |  | headless | pass | yes | 2 |
| CASE-0542 | SURF-026  |  | headless | pass | yes | 3 |
| CASE-0543 | SURF-026  |  | headless | pass | yes | 2 |
| CASE-0544 | SURF-026  |  | headless | pass | yes | 2 |
| CASE-0551 | SURF-026  |  | headless | pass | yes | 1 |
| CASE-0554 | SURF-026  |  | headless | pass | yes | 2 |
| CASE-0555 | SURF-026  |  | headless | pass | yes | 2 |
| CASE-0556 | SURF-026  |  | headless | pass | yes | 1 |
| CASE-0558 | SURF-026  |  | headless | pass | yes | 2 |
| CASE-0559 | SURF-026  |  | headless | pass | yes | 2 |
| CASE-0564 | SURF-026  |  | headless | pass | yes | 2 |
| CASE-0472 | SURF-027  |  | headless | pass | yes | 3 |
| CASE-0473 | SURF-027  |  | headless | pass |  | 3 |
| CASE-0474 | SURF-027  |  | headless | pass | yes | 3 |
| CASE-0475 | SURF-027  |  | headless | pass |  | 1 |
| CASE-0476 | SURF-027  |  | headless | pass |  | 3 |
| CASE-0477 | SURF-027  |  | headless | pass |  | 2 |
| CASE-0478 | SURF-027  |  | headless | pass |  | 2 |
| CASE-0479 | SURF-027  |  | headless | pass |  | 3 |
| CASE-0480 | SURF-027  |  | headless | pass |  | 2 |
| CASE-0548 | SURF-027  |  | headless | pass | yes | 2 |
| CASE-0549 | SURF-027  |  | headless | pass | yes | 2 |
| CASE-0552 | SURF-027  |  | headless | pass | yes | 2 |
| CASE-0553 | SURF-027  |  | headless | pass | yes | 2 |
| CASE-0557 | SURF-027  |  | headless | pass | yes | 2 |
| CASE-0561 | SURF-027  |  | headless | pass | yes | 2 |
| CASE-0562 | SURF-027  |  | headless | pass | yes | 2 |
| CASE-0565 | SURF-027  |  | headless | pass | yes | 2 |
| CASE-0566 | SURF-027  |  | headless | pass | yes | 2 |
| CASE-0570 | SURF-027  |  | headless | pass |  | 1 |
| CASE-0571 | SURF-027  |  | headless | pass |  | 1 |
| CASE-0572 | SURF-027  |  | headless | pass |  | 1 |
| CASE-0573 | SURF-027  |  | headless | pass |  | 1 |
| CASE-0574 | SURF-027  |  | headless | pass |  | 1 |
| CASE-0576 | SURF-027  |  | headless | pass |  | 1 |
| CASE-0577 | SURF-027  |  | headless | pass |  | 1 |
| CASE-0575 | SURF-028  |  | headless | pass |  | 1 |
| CASE-0590 | SURF-029  |  | headless | pass | yes | 2 |
| CASE-0591 | SURF-029  |  | headless | pass | yes | 2 |
| CASE-0592 | SURF-029  |  | headless | pass | yes | 2 |
| CASE-0593 | SURF-029  |  | headless | pass | yes | 2 |
| CASE-0594 | SURF-029  |  | headless | pass | yes | 2 |
| CASE-0595 | SURF-029  |  | headless | pass | yes | 2 |
| CASE-0596 | SURF-029  |  | headless | pass | yes | 2 |
| CASE-0597 | SURF-029  |  | headless | pass | yes | 2 |
| CASE-0600 | SURF-030  |  | headless | pass | yes | 2 |
| CASE-0601 | SURF-030  |  | headless | pass | yes | 1 |
| CASE-0602 | SURF-030  |  | headless | pass | yes | 1 |
| CASE-0620 | SURF-031  |  | headless | pass | yes | 1 |
| CASE-0621 | SURF-031  |  | headless | pass | yes | 1 |
| CASE-0622 | SURF-031  |  | headless | pass | yes | 1 |
| CASE-0623 | SURF-031  |  | headless | pass | yes | 1 |
| CASE-0624 | SURF-031  |  | headless | pass | yes | 1 |
| CASE-0625 | SURF-031  |  | headless | pass | yes | 1 |
| CASE-0626 | SURF-031  |  | headless | pass | yes | 1 |
| CASE-0630 | SURF-031  |  | headless | pass | yes | 1 |
| CASE-0631 | SURF-031  |  | headless | pass | yes | 1 |
| CASE-0632 | SURF-031  |  | headless | pass | yes | 1 |
| CASE-0633 | SURF-031  |  | headless | pass | yes | 2 |
| CASE-0634 | SURF-031  |  | headless | pass | yes | 2 |
| CASE-0635 | SURF-031  |  | headless | pass | yes | 2 |
| CASE-0636 | SURF-031  |  | headless | pass | yes | 2 |
| CASE-0637 | SURF-031  |  | headless | pass | yes | 2 |
| CASE-0638 | SURF-031  |  | headless | pass | yes | 2 |
| CASE-0650 | SURF-032  |  | headless | pass | yes | 1 |
| CASE-0651 | SURF-032  |  | headless | pass | yes | 1 |
| CASE-0652 | SURF-032  |  | headless | pass | yes | 1 |
| CASE-0653 | SURF-032  |  | headless | pass | yes | 1 |
| CASE-0670 | SURF-033  |  | headless | pass | yes | 1 |
| CASE-0671 | SURF-033  |  | headless | pass | yes | 1 |
| CASE-0672 | SURF-033  |  | headless | pass | yes | 1 |
| CASE-0700 | SURF-035  |  | headless | pass | yes | 2 |
| CASE-0701 | SURF-035  |  | headless | pass | yes | 2 |
| CASE-0702 | SURF-035  |  | headless | pass | yes | 2 |
| CASE-0750 | SURF-038  |  | headless | pass | yes | 1 |
| CASE-0751 | SURF-038  |  | headless | pass | yes | 1 |
| CASE-0752 | SURF-038  |  | headless | pass | yes | 1 |
| CASE-0753 | SURF-038  |  | headless | pass | yes | 1 |
| CASE-0754 | SURF-038  |  | headless | pass | yes | 1 |
| CASE-0730 | SURF-037  |  | headless | pass | yes | 2 |
| CASE-0731 | SURF-037  |  | headless | pass | yes | 2 |
| CASE-0732 | SURF-037  |  | headless | pass | yes | 2 |
| CASE-0733 | SURF-037  |  | headless | pass | yes | 2 |
| CASE-0734 | SURF-037  |  | headless | pass | yes | 2 |
| CASE-0710 | SURF-036  |  | headless | pass | yes | 2 |
| CASE-0711 | SURF-036  |  | headless | pass | yes | 2 |
| CASE-0712 | SURF-036  |  | headless | pass | yes | 2 |
| CASE-0713 | SURF-036  |  | macos | pass | yes | 1 |
| CASE-0714 | SURF-036  |  | headless | pass | yes | 1 |
| CASE-0715 | SURF-036  |  | headless | pass | yes | 2 |
| CASE-0760 | SURF-039  |  | headless | pass | yes | 2 |
| CASE-0761 | SURF-039  |  | headless | pass | yes | 2 |
| CASE-0762 | SURF-039  |  | headless | pass | yes | 2 |
| CASE-0780 | SURF-041  |  | headless | pass | yes | 2 |
| CASE-0790 | SURF-042  |  | headless | pass | yes | 2 |

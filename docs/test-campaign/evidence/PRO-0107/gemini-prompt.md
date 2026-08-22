Review a delivered work item in the proctor-mcp repository. The item id is PRO-0107. Answer about PRO-0107 and nothing else; if this prompt does not look like PRO-0107 to you, say so instead of answering.

## The item

`capture-lineage.py --gate` (test-campaign 0.9.6) exited 2 on the integration branch:
`published captures: 8 · distinct images: 8 · files in shots dir: 43`, with 35 UNACCOUNTED — an image in `docs/test-campaign/evidence/shots/` that no subject publishes and no manifest entry names. The gate's own remedy text: "Publish it, delete it, or record `unpublishedReason` on its captures.json entry."

The gate's reasoning, verbatim from its source: "Everything the gate had was derived from PUBLISHED captures, so an image nobody publishes contributed to no finding: measured on a real campaign as `published captures: 0 · files in shots dir: 11`, exit 0, and the sentence 'Every published capture names a target that ties to its subject' — true, and covering nothing."

The gate's UNACCOUNTED pass, verbatim:

```python
    published_paths = set(published.values())
    unaccounted = []
    for rel in images:
        if rel in published_paths:
            continue
        entry = by_path.get(rel) or {}
        reason = str(entry.get("unpublishedReason") or "").strip()
        if reason:
            manual.append(f"declared unpublished: {rel} — {reason}")
        elif rel in by_path:
            unaccounted.append(f"{rel}: the manifest names it and no subject publishes it, and "
                               f"it records no `unpublishedReason`")
        else:
            unaccounted.append(f"{rel}: no subject publishes it and no manifest entry names it")
```

And the pass that decides whether a published capture is sound (relevant because publishing was the alternative disposition):

```python
    for sid, shot in sorted(published.items()):
        rec = subjects[sid]
        entry = by_path.get(shot) or {}
        if shot not in by_path:
            unsourced.append(f"{sid} → {shot}: no entry in {MANIFEST}. The capture step "
                             f"recorded nothing, so the only thing binding this picture to "
                             f"{sid} is its filename.")
        elif not entry.get("target"):
            unsourced.append(f"{sid} → {shot}: entry names no target")
        ...
        if entry.get("sha256") and h and entry["sha256"] != h:
            reconstructed.append(f"{sid} → {shot}: manifest sha256 disagrees with the bytes "
                                 f"on disk. A manifest written after the fact records what "
                                 f"somebody believed, not what the channel did.")
```

The instruction to the runner included: "A filename is not evidence of what a picture depicts. This campaign's founding failure was a set of twenty captures filed by filename where twenty files held six distinct images and a step captioned 'Open pairing QR code sheet' showed a questionnaire about developer credentials. So open each image and look at it." And: "Deletion is not the default, though the tool offers it. Delete only a file you can show is debris — a zero-byte file, an exact duplicate of another already published." And: "Raise the ratchet only by what the change actually earns."

## What the runner did

All 35 images were opened and looked at. All 35 received an `unpublishedReason` on a `captures.json` entry. **None was published. None was deleted.**

Counts: published 8 before, 8 after. Files in the shots directory 43 before, 43 after. UNACCOUNTED 35 → 0. Gate exit 2 → 0. Judged 6 of 8 before and after. **Ratchet 6, deliberately not raised**, on the grounds that a ratchet pins judged captures, nothing became judgeable, and a raise would record a bar nothing new passed under.

Reason nothing was published: publishing requires the subject to be given a `shot` in `inventory.json` AND a `captures.json` row carrying a `target` recorded at capture time. None of the 35 has a recorded target — for several, a sibling JSON record exists (window bounds, layer, sharingState, distinct-colour counts, md5s) but no target string. The runner's position: writing a target now would be a manifest written after the fact, which the gate's own text calls "what somebody believed, not what the channel did", and it would make the pass rest on the filename, which is the failure the gate exists for. Nine of the 35 additionally have no subject that depicts them at all.

Reason nothing was deleted: no file is zero bytes (smallest 10,680), and no byte-identical group contains a published file, so no file is an exact duplicate of something already shown. Three of the four duplicate groups are themselves the evidence for two of the findings below.

## What looking at the pictures found

1. **Nine files named for nine engine surfaces are app-icon renders.** `surf-001-mcp-stdio.png`, `surf-002-tool-catalogue.png`, `surf-003-process-directed.png`, `surf-011-stability.png`, `surf-012-audit-policy.png`, `surf-013-guest-provider.png`, `surf-014-ios-maestro.png`, `surf-015-reflector.png`, `surf-016-install-notarize.png`. Every one shows the Proctor app icon (a dark window dissolving into orange squares) at exactly 1024x1024. Mechanism found in the repo: `scripts/build_test_campaign.py` lines 282-296 copy `design/icon/audit-renders/*` and `design/icon/runs/*/candidate-1024.png` into the shots directory under surface-shaped destination names. `surf-016-install-notarize.png` is byte-identical (sha256 a67cf67af07e…) to `design/icon/icon-proctor-1024.png`. Four other destinations in that same copy list were later replaced by real window captures with manifests written at the shutter, which is why those four are published and these nine are not.

2. **`sweepL-status-agent-down.png` depicts a READY status window** — green Ready pill, Accessibility and Screen Recording both Granted, "Ready. Every permission Proctor needs is granted." No agent-down state in the frame. The two frames that do show "Agent down" are `sweepL-status-t0.6.png` and `sweepL-status-t3.5.png`, and those two are byte-identical to each other. The sweep's own record (`evidence/sweeps-kl.json`) says: "Agent down at t+0.71s and t+3.63s after bootout+SIGKILL … The earlier Ready frame was captured inside one 2s doctor tick. DEF-002 retracted."

3. **One image carries three captions across two unrelated sweeps.** `sweepK-theme-before.png`, `sweepL-wedged-t1.png` and `sweepL-wedged-recovered.png` are byte-identical (670a93988315…); the picture is a dark Ready status window. `evidence/sweepL-halfopen.json` records `recoveredAfterSIGCONT: true`, and the recovery frame is the same bytes as the earliest wedged frame. Separately `sweepL-wedged-t7.png` and `sweepL-wedged-t14.png` are byte-identical to each other (both show "Agent down — the Proctor agent did not answer within 5s").

4. **Three files named for the takeover shield contain no image**: `surf-005-takeover-sck-external/laptop/window.png` have 0 non-transparent pixels of 14,745,600 / 7,720,704 / 677,888 and exactly 1 distinct RGBA each (measured with Pillow off the files). Their own record, `evidence/hud-capture-channels.json`, already lists all three under `framesThatWereNotEvidence` with the note "Kept as the record of the false raster pass this campaign corrected: SCFrameStatus complete frames that are entirely transparent."

5. **`evidence/sweepK-scaling.json` lists two frames its own mode table has no capture of.** Its `shots` array names four files; its mode table records capture sizes 970x773, 820x654, 970x773 and 781x961. `sweepK-scale-small.png` is 970x773 and `sweepK-scale-1x.png` is 820x654, so two tie. `sweepK-external.png` and `sweepK-laptop.png` are both 900x833, matching no mode, and no file in the directory is 781x961, so the sweep's baseline frame is absent.

6. **Two files' surface prefixes name a surface the picture does not show.** `surf-004-drawn-pointer.png` is prefixed for SURF-004 (the Run HUD) and is the pointer glyph alone on an otherwise empty 3456x2234 frame (3,739 non-transparent pixels of 7,720,704, 173 distinct RGBA) with no HUD in it. `surf-008-about.png` is prefixed for SURF-008 (the Status & Diagnostics Window) and is the About panel ("Proctor", "Version 0.1.0 (1)", "Proctor is released under the MIT licence.").

Findings 1 and 4 and 6 mean the item's own brief was wrong where it assumed: it said the surface-shaped names "are most likely real captures taken in earlier waves and never published, which is the recoverable case rather than the worrying one."

These six are recorded as DEF-218 to DEF-223, all `open` and all marked `(recorded)` rather than claimed as fixed, on the grounds that the repairs (re-capture per surface, remove the copy list from the build script, rename evidence files, re-run two sweeps, add an inventory surface for the About panel) are new work outside this item. DEF-209, the 35-unaccounted defect itself, is flipped to `fixed`.

Both new checks were watched to fail, with each mutation confirmed landed before its verdict was read: removing one `unpublishedReason` returned exit 2 naming that file; replacing one sha256 in the audit file returned the disposition checker to exit 1 naming that file. Both restored, both reproducing the passing reading.

## The questions

1. **Is declaring all 35 unpublished an honest disposition, or is it clearing a gate by declaration?** The gate offers three remedies and this uses one of them 35 times. Argue the strongest case that this is the wrong call, then say whether it holds.
2. **Was refusing to publish right?** Specifically for the cases where the filename IS honest and a sibling JSON record exists at capture time but carries no target string (`surf-004-run-hud.png` — genuinely the Run HUD; `surf-005-takeover-shield.png` — genuinely the takeover shield; `sweepK-extras-open.png` — corroborated by the menu text recorded at click time). Is "no target recorded at the shutter, so it stays unpublished" too strict, given the gate would have passed a target written now?
3. **Was leaving the ratchet at 6 right**, or does accounting for 35 files earn a raise?
4. **Is any of the six findings overclaimed?** In particular: is finding 3's reading of the recovery frame fair, and is finding 5 a real defect or an artifact of how a `shots` array is used?
5. **What did this item miss** that a reader of the evidence page would notice?

Be concise and specific. Name the finding numbers you are addressing.

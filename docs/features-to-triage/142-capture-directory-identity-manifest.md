---
generated-by: tailings
tailings-sources: [R4]
reckon-sources: [REQ-133, REQ-111]
status: to-triage
---
# Capture Directory Identity Manifest

- origin: tailings audit R4 (no capture directory found; capture identity unchecked) · 2026-08-25
- audience: Audit passes verifying that published visual evidence depicts what it claims
- platforms: mac
- proposed-by-ai: false

## What and why
Audit passes that verify published captures need a discoverable capture directory carrying identity metadata for every image. When the capture directory cannot be located from repository conventions alone, the capture identity probe cannot run and reports unchecked rather than clean. A discoverable capture manifest declares where captures live and what each one was pointed at.

## Acceptance sketch
- Capture directory location is declared in a discoverable configuration entry
- Each capture carries a recorded subject and the target the channel was pointed at
- Image digests are recorded at capture time rather than derived afterward
- Audit tooling locates the manifest without repository-specific path knowledge
- Captures with no manifest entry are reported as unsourced rather than silently accepted

## Assumptions made writing this
- Assuming capture manifests are written at capture time rather than reconstructed later
- Assuming manifest discovery follows standard configuration conventions rather than hardcoded paths

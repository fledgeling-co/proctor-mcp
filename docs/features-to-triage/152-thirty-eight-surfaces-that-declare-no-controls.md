---
generated-by: test-campaign
campaign-sources: [campaign.check.controls]
reckon-sources: [REQ-009, REQ-011]
status: retired
validated-by: REQ-009, REQ-011 via CASE-0013, CASE-0062, CASE-0791, CASE-0792, CASE-0795, CASE-0011 (6 of 7 citing case(s))
validated-rungs: effect-witness, outcome, raster-visual
validated-provider: Darwin.bind/listen/accept in Sources/ProctorAgent/Server.swift; Darwin.connect in Sources/ProctorCore/Transport.swift
---
# Thirty-eight surfaces that declare no controls

- origin: full campaign run, the control census · 2026-08-25
- audience: Anyone deciding whether a green campaign means the product works
- platforms: mac
- proposed-by-ai: false

## What and why
The control census reads four of thirty-four controls actuated. Both numbers come from two surfaces; the other thirty-eight declare no controls at all, so the fraction describes 5% of the surface list rather than the product. A campaign once reported thirty-two of thirty-two passing over an application whose every button ran an empty closure, and the census exists so that cannot happen quietly — but a census over two surfaces cannot catch it on the other thirty-eight either.

Enumerating a surface's controls is cheap and mechanical where the surface has a typed catalogue or an accessibility tree, and the denominator it creates is what makes a low actuation count visible instead of absent. The count going down when the list grows is the correct outcome and should be expected rather than avoided.

## Acceptance sketch
- Every surface that offers controls declares them, taken from its own source of truth
- A surface with genuinely no controls says so rather than being silently absent from the census
- The actuated count is published against the full declared list, not against the enumerated subset
- Adding a surface's controls lowers the actuated fraction, and that is recorded as progress
- A declared control that no case actuates is named rather than counted only in aggregate

## Assumptions made writing this
- Assuming the list comes from a typed catalogue or a live accessibility read rather than being hand-written, since a hand-written list drifts from what renders
- Assuming an engine surface with no user-facing controls declares an empty list explicitly, because absent and empty are different denominators

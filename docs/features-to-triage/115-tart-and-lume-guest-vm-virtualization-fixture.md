# Tart and Lume Guest VM Virtualization Fixture

- origin: docs/reckoning/2026-08-24-final/reckoning.md · 2026-08-24
- audience: Automated test suites verifying guest VM management across multi-architecture nodes
- platforms: mac
- proposed-by-ai: false

## What and why
Guest virtualization tests require reliable verification of virtual machine provisioning, attachment, and stop operations. When virtualization hosts are busy or missing specific guest images, guest operations remain unmeasured in closed-world test campaigns. A deterministic virtualization fixture enables robust verification of multi-architecture VM attachment and isolation guarantees without requiring persistent cloud infrastructure.

## Acceptance sketch
- Virtual machine provider identifies available local guest images and hypervisor backends
- Guest attachment establishes bidirectional communication with guest agent instances
- Concurrent test sessions respect host capacity limits and queue requests when at capacity
- Machine stop commands terminate guest execution cleanly and verify state transition
- Unreachable guest nodes report connection failures with specific diagnostic details

## Assumptions made writing this
- Assuming local hypervisor frameworks are utilized when available rather than remote network hypervisors
- Assuming guest instances execute in lightweight ephemeral containers rather than persistent full-disk clones

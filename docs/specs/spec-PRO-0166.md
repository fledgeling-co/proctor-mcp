# Spec PRO-0166 — Exit Codes That Survive a Pipe

**Brief:** `docs/features-to-triage/158-unsuppressed-gate-execution-and-exit-verification.md`
**Status:** Merged
**Created:** 2026-08-25
**Surfaces:** SURF-029
**Defects:** none

## Context & Purpose
A gate piped to tail reports tail's status. Output suppression must not cost the exit code, and a gate whose failure is invisible is a gate that is off.

## Acceptance Criteria
1. A gate's exit code is read from the gate rather than from a downstream stage of its pipeline.
2. Suppressing a gate's output leaves its failure visible on stderr.
3. A repository sweep names every invocation that reads a pipeline's status instead of the command's.
4. The sweep prints its denominator: how many invocations were examined.

#!/usr/bin/env python3
"""DEF-228: standing gate for docs/feature-specs/LEDGER.md.

Verifies:
  1. Every merged branch / feature claims `Merged` (or `Retired`) in LEDGER.md.
  2. Every spec file on disk (docs/specs/spec-PRO-*.md) has a row in LEDGER.md.
  3. Every ledger row with no spec file is declared in `## Rows with no spec file`
     with a non-empty reason, and no declared row has a spec on disk (stale declaration).

    python3 scripts/campaign/ledger_gate.py [--ledger FILE] [--specs DIR] [--repo DIR]
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

REPO_DEFAULT = Path(__file__).resolve().parents[2]
MIN_REASON = 20

MERGE_COMMIT_RE = re.compile(
    r"\bmerge\s+(?:branch\s+['\"]?(?:ai/)?|ai/)?(PRO-\d+)\b",
    re.I,
)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Standing gate for LEDGER.md")
    p.add_argument("--ledger", type=Path, default=None, help="Path to LEDGER.md")
    p.add_argument("--specs", type=Path, default=None, help="Path to docs/specs directory")
    p.add_argument("--repo", type=Path, default=None, help="Path to repository root")
    p.add_argument("-v", "--verbose", action="store_true", help="Verbose output")
    p.add_argument("--json", action="store_true", help="Emit JSON output")
    return p.parse_args(argv)


def git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repo)] + list(args),
        capture_output=True,
        text=True,
    )


def read_ledger(ledger_path: Path) -> tuple[dict[str, dict], dict[str, str]]:
    """Parse LEDGER.md into (main_rows, declared_no_spec).

    main_rows: {id: {"title": str, "created": str, "status": str}}
    declared_no_spec: {id: reason}
    """
    text = ledger_path.read_text(encoding="utf-8")
    main_rows: dict[str, dict] = {}
    declared_no_spec: dict[str, str] = {}

    sections = text.split("## Rows with no spec file")
    main_section = sections[0]

    for line in main_section.splitlines():
        m = re.match(r"^\|\s*(PRO-\d+)\s*\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|", line)
        if m:
            id_, title, created, status = (g.strip() for g in m.groups())
            if id_ != "ID":
                main_rows[id_] = {"title": title, "created": created, "status": status}

    if len(sections) > 1:
        no_spec_section = sections[1]
        for line in no_spec_section.splitlines():
            m = re.match(r"^\|\s*(PRO-\d+)\s*\|[^|]*\|[^|]*\|\s*([^|]+)\|", line)
            if m:
                id_, reason = m.group(1).strip(), m.group(2).strip()
                if id_ != "ID":
                    declared_no_spec[id_] = reason

    return main_rows, declared_no_spec


def find_merged_features(repo: Path) -> set[str]:
    """Identify PRO-xxxx items whose branches/work are merged in git history."""
    merged = set()
    log_res = git(repo, "log", "--format=%s")
    if log_res.returncode == 0:
        for line in log_res.stdout.splitlines():
            for match in MERGE_COMMIT_RE.finditer(line):
                for grp in match.groups():
                    if grp:
                        merged.add(grp.upper())
    return merged


def audit_ledger(
    ledger_path: Path, specs_dir: Path, repo: Path
) -> dict:
    if not ledger_path.is_file():
        return {"fatal": f"no ledger file at {ledger_path}"}
    if not specs_dir.is_dir():
        return {"fatal": f"no specs directory at {specs_dir}"}

    main_rows, declared_no_spec = read_ledger(ledger_path)
    merged_in_git = find_merged_features(repo)

    # Specs on disk
    spec_files = {p.name: p for p in specs_dir.glob("spec-PRO-*.md")}
    spec_ids = {}
    for name in spec_files:
        m = re.match(r"^spec-(PRO-\d+)\.md$", name)
        if m:
            spec_ids[m.group(1)] = name

    # 1. Every spec on disk must have a ledger row
    specs_without_row = sorted(
        f"{name} ({id_})" for id_, name in spec_ids.items() if id_ not in main_rows
    )

    # 2. Rows with no spec file must be declared with a reason
    missing_specs = set(main_rows) - set(spec_ids)
    orphaned_declarations = sorted(
        f"{id_} (declared in no-spec table but absent from main ledger table)"
        for id_ in declared_no_spec
        if id_ not in main_rows
    )
    undeclared_no_spec = sorted(
        f"{id_} ({main_rows[id_]['title']}, status: {main_rows[id_]['status']})"
        for id_ in missing_specs
        if id_ not in declared_no_spec
    )
    thin_reasons = sorted(
        f"{id_} (reason length {len(declared_no_spec[id_])} < {MIN_REASON}: {declared_no_spec[id_]!r})"
        for id_ in declared_no_spec
        if len(declared_no_spec[id_]) < MIN_REASON
    )
    stale_declarations = sorted(
        f"{id_} (spec exists on disk: {spec_ids[id_]})"
        for id_ in declared_no_spec
        if id_ in spec_ids
    )

    # 3. Every merged branch/commit in git must claim Merged (or Retired) in LEDGER.md
    unclaimed_merges = []
    for id_ in sorted(merged_in_git):
        if id_ not in main_rows:
            unclaimed_merges.append(
                f"{id_} merged in git history but has no row in LEDGER.md"
            )
        else:
            status = main_rows[id_]["status"]
            if not (status.lower().startswith("merged") or status.lower().startswith("retired")):
                unclaimed_merges.append(
                    f"{id_} merged in git but ledger status is {status!r} ({main_rows[id_]['title']})"
                )

    failures = []
    if specs_without_row:
        failures.append(f"{len(specs_without_row)} spec(s) on disk have no ledger row: {'; '.join(specs_without_row)}")
    if orphaned_declarations:
        failures.append(f"{len(orphaned_declarations)} declared no-spec row(s) are absent from main ledger: {'; '.join(orphaned_declarations)}")
    if undeclared_no_spec:
        failures.append(f"{len(undeclared_no_spec)} ledger row(s) lack a spec file and are undeclared: {'; '.join(undeclared_no_spec)}")
    if thin_reasons:
        failures.append(f"{len(thin_reasons)} declared no-spec row(s) have thin reasons (<{MIN_REASON} chars): {'; '.join(thin_reasons)}")
    if stale_declarations:
        failures.append(f"{len(stale_declarations)} declared no-spec row(s) actually have a spec on disk: {'; '.join(stale_declarations)}")
    if unclaimed_merges:
        failures.append(f"{len(unclaimed_merges)} merged feature(s) issue in ledger: {'; '.join(unclaimed_merges)}")

    return {
        "ledger_rows": len(main_rows),
        "specs_on_disk": len(spec_ids),
        "declared_no_spec": len(declared_no_spec),
        "merged_in_git": len(merged_in_git),
        "specs_without_row": specs_without_row,
        "orphaned_declarations": orphaned_declarations,
        "undeclared_no_spec": undeclared_no_spec,
        "thin_reasons": thin_reasons,
        "stale_declarations": stale_declarations,
        "unclaimed_merges": unclaimed_merges,
        "failures": failures,
    }


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    repo = args.repo or REPO_DEFAULT
    ledger = args.ledger or (repo / "docs/feature-specs/LEDGER.md")
    specs = args.specs or (repo / "docs/specs")

    res = audit_ledger(ledger, specs, repo)
    if res.get("fatal"):
        print(f"FATAL: {res['fatal']}")
        return 2

    if args.json:
        print(json.dumps(res, indent=2))
        return 1 if res["failures"] else 0

    print(
        f"LEDGER gate: {res['ledger_rows']} ledger rows · {res['specs_on_disk']} specs on disk · "
        f"{res['declared_no_spec']} declared without spec · {res['merged_in_git']} merged in git"
    )

    if res["failures"]:
        print(f"\n{len(res['failures'])} FAILURE(S):")
        for f in res["failures"]:
            print(f"  FAILED: {f}")
        return 1

    print("PASS: Every merged branch claims Merged, all specs on disk have rows, and every no-spec row is declared.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

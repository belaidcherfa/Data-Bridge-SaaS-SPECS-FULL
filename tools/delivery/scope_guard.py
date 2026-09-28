#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6"]
# ///
"""CI scope guard for agent pull requests (ORCHESTRATION §6, ADR-018 §4).

Usage: uv run tools/delivery/scope_guard.py [--base origin/main] [--task FIN-003] [--labels "lock:lockfiles,agent"]

- Task ID: --task, else env TASK_ID, else the branch name `agt/<id-lower>-<slug>` (env GITHUB_HEAD_REF or git).
  Branches that are not agent branches are skipped (exit 0) unless --task is given.
- Every changed file must match the packet's `writes` globs or an always-allowed path for that task.
- Files guarded by a serialization lock need the lock in the packet `locks` or a `lock:<name>` PR label
  granted by the orchestrator (env PR_LABELS or --labels).
- Protected files (PRD, agent policy, CODEOWNERS) may never change in an agent PR; protected checksums in
  delivery/protected-files.sha256 must still match.
Exit 1 on any violation.
"""
from __future__ import annotations

import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
LOCK_PATHS = [
    (r"^(uv\.lock|pnpm-lock\.yaml|.*/uv\.lock|.*/package\.json|.*/pyproject\.toml|pyproject\.toml|package\.json)$", "lock:lockfiles"),
    (r"^services/[^/]+/migrations/", "lock:pg-migrations"),
    (r"^infra/snowflake/migrations/", "lock:sf-migrations"),
    (r"^contracts/openapi/openapi\.yaml$", "lock:openapi-root"),
    (r"^\.github/workflows/", "lock:ci-workflows"),
    (r"^infra/terraform/stacks/([^/]+)/", "lock:terraform-state"),
]
PROTECTED = [r"^docs/00-project/PRD\.md$", r"^\.claude/settings(\.local)?\.json$", r"^\.claude/hooks/",
             r"^\.github/CODEOWNERS$", r"^delivery/protected-files\.sha256$", r"^tools/delivery/scope_guard\.py$"]


def glob_to_regex(g: str) -> re.Pattern[str]:
    out, i = "", 0
    while i < len(g):
        if g.startswith("**/", i):
            out += "(?:.*/)?"; i += 3
        elif g.startswith("**", i):
            out += ".*"; i += 2
        elif g[i] == "*":
            out += "[^/]*"; i += 1
        elif g[i] == "?":
            out += "[^/]"; i += 1
        else:
            out += re.escape(g[i]); i += 1
    if g.endswith("/"):
        out += ".*"
    return re.compile("^" + out + "$")


def git(*a: str) -> str:
    return subprocess.run(["git", *a], capture_output=True, text=True, check=True, cwd=ROOT).stdout


def main() -> int:
    args = sys.argv[1:]
    opt = lambda k, d=None: args[args.index(k) + 1] if k in args else d  # noqa: E731
    base = opt("--base", "origin/main")
    task = opt("--task") or os.environ.get("TASK_ID")
    if not task:
        branch = os.environ.get("GITHUB_HEAD_REF") or git("rev-parse", "--abbrev-ref", "HEAD").strip()
        m = re.match(r"^agt/([a-z]{2,3})-(\d{3})(?:-|$)", branch)
        if not m:
            print(f"scope-guard: '{branch}' is not an agent branch; skipped")
            return 0
        task = f"{m.group(1).upper()}-{m.group(2)}"
    labels = {x.strip() for x in (opt("--labels") or os.environ.get("PR_LABELS", "")).split(",") if x.strip()}
    packet = ROOT / "delivery/packets" / f"{task}.md"
    if not packet.exists():
        print(f"scope-guard: no packet for {task}")
        return 1
    fm = yaml.safe_load(packet.read_text().split("---")[1])
    allowed = list(fm.get("writes") or []) + [
        f"docs/evidence/{task}/**", f"tests/spec/{task}/**", f"tests/live/{task}/**",
        f"delivery/escalations/*-{task}.md", f"delivery/human-gates/{task}.md"]
    patterns = [glob_to_regex(g) for g in allowed]
    locks = set(fm.get("locks") or []) | {l for l in labels if l.startswith("lock:")}
    changed = [l for l in git("diff", "--name-only", f"{base}...HEAD").splitlines() if l]
    errors: list[str] = []
    for f in changed:
        if any(re.search(p, f) for p in PROTECTED):
            errors.append(f"protected file changed: {f}")
            continue
        if not any(p.match(f) for p in patterns):
            errors.append(f"outside packet writes: {f}")
        for rx, lock in LOCK_PATHS:
            if re.search(rx, f) and not any(l == lock or l.startswith(lock + "/") for l in locks):
                errors.append(f"{f} requires {lock} (declare in packet locks or get the PR label from the orchestrator)")
    sums = ROOT / "delivery/protected-files.sha256"
    for line in sums.read_text().splitlines() if sums.exists() else []:
        digest, name = line.split(maxsplit=1)
        p = ROOT / name.strip().lstrip("*")
        if not p.exists() or hashlib.sha256(p.read_bytes()).hexdigest() != digest:
            errors.append(f"protected checksum mismatch: {name.strip()}")
    for e in errors:
        print("SCOPE", e)
    print(f"scope-guard {task}: {len(changed)} file(s) changed, {len(errors)} violation(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

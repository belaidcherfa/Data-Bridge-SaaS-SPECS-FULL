---
name: verify-task
description: Independently re-run a task's checks and oracles from a clean checkout of the PR head and compare with its evidence manifest. Use before any merge.
---

# Verify a task

1. `git worktree add /tmp/verify-<ID> <pr-head-sha>`; install from lockfiles only (`uv sync --frozen`, `pnpm install --frozen-lockfile`).
2. Run every command in the packet `checks`; run each locally executable micro-step oracle.
3. Compare results with `docs/evidence/<ID>/<sha>/index.json` (commands, exit codes, expected vs observed, checksums).
4. Output a table: command → PASS/FAIL → excerpt. Overall PASS only if all pass and the evidence matches. Remove the temporary worktree.

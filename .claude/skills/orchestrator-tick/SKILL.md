---
name: orchestrator-tick
description: Run one orchestration tick for the Bridge delivery system — sync state, reconcile PRs and leases, plan ready tasks, dispatch workers in worktrees, run reviews, merge green PRs, write the report. Use as the orchestrator (Opus 5.5 / Fable 5.1) every 30 minutes or when asked to "continue the delivery".
---

# Orchestrator tick

Source of truth: docs/23-agentic-delivery/ORCHESTRATION.md. Durable state: delivery/state.json (schema delivery/state.schema.json).

## 1. Sync
- `git fetch --all --prune`; `git checkout main && git pull --ff-only`.
- Read `delivery/state.json`. If `control.paused` is true: do only steps 2 and 6, then stop.
- List open PRs with label `agent` (`gh pr list --label agent --json number,headRefName,statusCheckRollup,reviewDecision,labels`).
- Read answered escalations (`delivery/escalations/*.md` with `status: ANSWERED`) and apply them (update decision record if it is a decision; unblock tasks).

## 2. Reconcile
- For each merged PR since the last tick: set the task's `steps_done`, `pr`, `evidence`; set `DONE` only if every micro-step is done, evidence exists and human gates are approved; else keep `NEEDS_HUMAN`/`IN_PROGRESS` (slices).
- Red CI on an agent PR → send the failure log to its worker (same lease) or re-dispatch with attempt+1.
- Lease with no commit for `lease_ttl_hours` → reclaim; attempts ≥ 2 → dispatch `rescuer`; attempts ≥ 3 → escalate (severity blocking-task).
- Main red → revert the culprit PR (`git revert` via a PR labelled `revert`), reopen its task, pause dispatch this tick.

## 3. Plan
- `make packets` then `make next-tasks` (JSON: `uv run tools/delivery/next_tasks.py --json`).
- Admit in rank order while: workers < `max_workers`; lane load < `lane_cap`; no `writes` overlap with running leases; required `locks` free (acquire them in state); today's budget allows `estimate_high × usd_per_estimated_hour`; human gates that block *starting* are satisfied.

## 4. Dispatch
For each admitted task:
- `git worktree add /srv/bridge/worktrees/<ID> -b agt/<id-lower>-<slug> origin/main`
- Reserve migration numbers / Alembic revision IDs if the packet needs them (record in state).
- Launch the agent by tier: tier A → `worker-critical`; B → `worker`; C → `worker` with a smaller budget. Prompt: the dispatch template in ORCHESTRATION §5 with the packet path, budget and max turns. In interactive mode use the Agent tool with worktree isolation; in headless mode `claude -p` in the worktree (see tools/orchestrator).
- Record the lease (task, worker id, branch, worktree, model, start, budget, attempt) and set status IN_PROGRESS.

## 5. Review and merge
For each PR marked ready by its worker:
- Run `verifier`; then `reviewer`; then each specialized reviewer listed in the packet `reviewers`.
- All APPROVE + CI green + no human gate → enable squash auto-merge / merge queue; release locks; lease closed.
- Human gate → label `needs-human`, list it in the report with the exact action needed.
- REQUEST_CHANGES → back to the worker with numbered findings (same lease, counts toward attempts only if CI/oracle failed).

## 6. Report and persist
- Update `delivery/state.json` (validate with `make state-validate`) and commit alone: `chore(delivery): tick <UTC>`; push to the delivery branch or main per branch protection (state commits go through a PR with auto-merge if main is protected).
- Append to `delivery/reports/<UTC-date>.md` using the `daily-report` skill (once per day full report; otherwise a short tick log section).
- Stop conditions: budget exhausted, main red twice, error rate > 30 % of attempts in 24 h, an open `blocking-all` escalation → set `control.paused=true` with reason and report.

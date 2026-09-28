# AGT — Agentic delivery tooling (lane A0)

Canonical contract: [ADR-018](../../architecture/adr/ADR-018-agentic-delivery.md), [ORCHESTRATION](../../23-agentic-delivery/ORCHESTRATION.md), [STATE_AND_REPORTING](../../23-agentic-delivery/STATE_AND_REPORTING.md), [TASK_PACKET_FORMAT](../../23-agentic-delivery/TASK_PACKET_FORMAT.md), [PARALLELISM](../../23-agentic-delivery/PARALLELISM.md). Reviewer: orchestrator design, 2026-09-28. Status of all tasks: NOT_STARTED.

## 1. Verdict

The delivery system is itself software with failure modes (double dispatch, lost leases, runaway spend, silent red main, reports that hide failures). Wave-0 artifacts exist (packets, state schema, hooks, skills, agents, CI guards) but the autonomous loop, the server, the reporting pipeline, the evaluation harness and the contract ratification are not built. These seven tasks are delivered first, in interactive mode A, by the orchestrator with one human reviewer, and they gate unattended multi-day runs (mode B). They do not block product tasks in mode A: FND-001 may start in parallel.

## 2. Findings

### G-AGT-01 · Orchestrator state cannot live on protected `main`
Severity: HIGH · Type: GAP. Resolution: ledger branch `delivery-ledger` (ADR-018 §5); tools accept `--state`.
### G-AGT-02 · Graph is 42 levels deep and 1 task wide at start
Severity: HIGH · Type: RISK. Resolution: dependency kinds (runtime / contract / decision) and contract-gated starts with integration slices ([PARALLELISM](../../23-agentic-delivery/PARALLELISM.md)); contract ratification wave AGT-007.
### G-AGT-03 · No measurement of agent quality
Severity: MEDIUM · Type: GAP. Resolution: AGT-006 golden tasks and seeded-defect review evaluation before raising `max_workers` or changing models.
### G-AGT-04 · Spend is unbounded without accounting from real usage
Severity: HIGH · Type: RISK. Resolution: AGT-003 reads usage/cost from each worker's result stream and enforces per-task and daily budgets.

## 3. Tasks

### AGT-001 — Provision the delivery server and credentials
Release: R1 · Estimate: 10–16 h · Risk: M · Decisions: D-19 · Closes: —
Dependency changes: none (root).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| AGT-001-S01 | Write the server specification and bootstrap script: Ubuntu 24.04, user `bridge-agent`, git, Docker, Python 3.13 + uv, Node 24 + pnpm, Claude Code CLI, GitHub CLI, AWS CLI v2, Terraform, Snowflake CLI; directories `/srv/bridge/{repo,ledger,worktrees,logs}` | `tools/server/bootstrap.sh`, `docs/23-agentic-delivery/SERVER.md` | Script is idempotent (second run makes no change, checked by `shellcheck` + a container run in CI) | 3 |
| AGT-001-S02 | Credential placement: root-owned `/etc/bridge-agent/env` (mode 0600, owner `bridge-agent`) for `ANTHROPIC_API_KEY` or subscription login, GitHub App private key path, DEV-only AWS SSO profile; nothing in the repository | `docs/23-agentic-delivery/SERVER.md` §Credentials | Checklist reviewed; `tools/server/doctor.sh` reports each credential present without printing it | 2 |
| AGT-001-S03 | `tools/server/doctor.sh`: versions, disk ≥ 50 GB free, Docker running, `claude --version`, `gh auth status`, GitHub App can read the repo and push `agt/*` and `delivery-ledger`, no production profile configured | `tools/server/doctor.sh` | Exit 0 on a healthy host; each failure prints a named remediation | 3 |
| AGT-001-S04 | systemd units: `bridge-orchestrator.service` + `.timer` (tick every 30 min), log rotation, nightly `git worktree prune` and disk alarm | `tools/server/systemd/*` | `systemd-analyze verify` passes; timer listed by `systemctl list-timers` on the host | 2 |
| AGT-001-S05 | Optional MCP servers for the host (github, snowflake-dev, postgres-local, aws-api-dev, cloudwatch-dev) from `delivery/mcp/optional-servers.example.json`, DEV read-only credentials | host `~/.claude.json` (not committed) | `claude mcp list` shows only approved servers; none has production credentials | 1 |
| AGT-001-S06 | Smoke run: an interactive orchestrator session executes one tick in dry-run on the host | `docs/evidence/AGT-001/<sha>/index.json` | Tick log written to the ledger; no dispatch in dry-run | 1 |
Task acceptance:
- [ ] `tools/server/doctor.sh` exits 0 on the delivery host.
- [ ] No credential appears in the repository, logs or process listings.
- [ ] Human gate: owner provisions the host, the Anthropic credential and the GitHub App.

### AGT-002 — Harden packet, graph and state tooling
Release: R1 · Estimate: 16–24 h · Risk: M · Decisions: D-19 · Closes: G-AGT-01, G-AGT-02
Dependency changes: none.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| AGT-002-S01 | Unit tests for `build_packets.py` (lane, tier, writes normalization, contracts_read from manifests, overrides, drift check) on a synthetic mini-graph | `tools/delivery/tests/test_build_packets.py` | `uv run pytest tools/delivery/tests` green; a hand-edited packet makes `--check` exit 1 | 4 |
| AGT-002-S02 | `next_tasks.py` reads `delivery/dependency-kinds.yaml`: a task is startable when runtime deps are DONE and contract/decision deps have all owned contracts ACCEPTED (manifests) or are DONE; output marks `integration_pending` | `tools/delivery/next_tasks.py` | Fixture graph: contract-gated task listed only after its dependency's manifest entries become ACCEPTED | 4 |
| AGT-002-S03 | `validate_state.py --sync` and ledger-aware `--state`; `sync_ledger.py` bootstraps `delivery-ledger` from `main` and mirrors escalation files from agent branches | `tools/delivery/validate_state.py`, `tools/delivery/sync_ledger.py` | New graph task appears NOT_STARTED after sync; unknown task in state fails | 3 |
| AGT-002-S04 | Writes-overlap and lock checker used at dispatch: glob intersection between two packets (conservative prefix test), lock availability | `tools/delivery/admission.py` | Property test: overlapping globs always reported; disjoint lanes admitted | 4 |
| AGT-002-S05 | `parallelism.py` waves and critical-path report regenerated from graph + dependency kinds; CI check that `dependency-kinds.yaml` covers every graph edge | `tools/delivery/parallelism.py`, `docs/23-agentic-delivery/PARALLELISM.md` | `--check` exits 1 on a missing edge | 2 |
| AGT-002-S06 | Fix packet `writes` heuristics flagged by reviewers (bare `tests/*.sql` → `data/dbt/tests/**`, conventions paths over backlog paths) with overrides | `tools/delivery/build_packets.py`, `delivery/packet-overrides.yaml` | No packet writes a root-level file other than documented ones (test) | 3 |
Task acceptance:
- [ ] `make delivery-check` green in CI; tools covered ≥ 85 % lines.
- [ ] Ready list on the real graph after wave 1 contains ≥ 12 tasks across ≥ 5 lanes (from PARALLELISM analysis) when contracts are ACCEPTED.

### AGT-003 — Build the headless orchestrator loop
Release: R1 · Estimate: 40–60 h · Risk: H · Decisions: D-19 · Closes: G-AGT-04
Dependency changes: AGT-002.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| AGT-003-S01 | Package `tools/orchestrator` (Python 3.13, `claude-agent-sdk`, `pyyaml`, `jsonschema`), CLI `bridge-orch tick [--dry-run]`, config from ledger `control` | `tools/orchestrator/pyproject.toml`, `src/bridge_orch/cli.py` | `bridge-orch tick --dry-run` prints SYNC→REPORT plan on a fixture repo | 4 |
| AGT-003-S02 | SYNC/RECONCILE: read ledger, `gh pr list/checks` JSON, merged PRs → steps_done/DONE rules, stale leases, attempts → rescuer/escalation, red main detection → revert PR | `src/bridge_orch/reconcile.py` | Scenario tests with recorded `gh` JSON fixtures cover each transition in STATE_AND_REPORTING §1 | 8 |
| AGT-003-S03 | PLAN/ADMIT: next_tasks + admission (caps, overlaps, locks, budget), contract-gated starts and integration slices | `src/bridge_orch/plan.py` | Property test: never two leases with overlapping writes; never over lane cap or budget | 6 |
| AGT-003-S04 | DISPATCH: worktree + branch, worker process `claude -p` (or SDK `query()`) with model per tier, `--max-turns`, allowed tools, `BRIDGE_ROLE=worker`, stream-json log to `/srv/bridge/logs/<task>/<attempt>.jsonl`; lease recorded | `src/bridge_orch/dispatch.py` | Fake `claude` binary test: lease created, log captured, exit codes mapped | 6 |
| AGT-003-S05 | Cost accounting: parse result messages (usage, total cost), update per-task and daily budget; kill a worker exceeding its budget or TTL | `src/bridge_orch/budget.py` | Fixture stream over budget → worker terminated, task back to READY with note | 4 |
| AGT-003-S06 | REVIEW: run verifier, reviewer and specialized reviewers as separate `claude -p` sessions on the PR head; post reviews; apply `needs-human`; enable auto-merge in merge queue for approved green PRs | `src/bridge_orch/review.py` | Recorded scenario: approve path queues merge; request-changes path returns findings to worker | 6 |
| AGT-003-S07 | PERSIST/REPORT: ledger commit + push with retry, tick log, daily report trigger, escalation issues | `src/bridge_orch/persist.py` | Concurrent tick guarded by a file lock; interrupted tick re-run is idempotent (test) | 4 |
| AGT-003-S08 | Stop conditions and kill switch (`control.paused`, `delivery-pause` label), crash recovery on start, `--once` and `--loop` modes, systemd integration | `src/bridge_orch/control.py` | Chaos test: kill -9 mid-dispatch then restart → no duplicate lease, orphan worktree reclaimed | 4 |
| AGT-003-S09 | Evidence and runbook `docs/23-agentic-delivery/RUNBOOK.md` (start/stop, pause, drain, rotate credentials, recover ledger) | runbook + evidence | Dry-run of every runbook command on the host recorded | 2 |
Task acceptance:
- [ ] 48-hour supervised pilot on AGT/FND tasks: zero duplicate dispatch, zero writes-overlap, spend within budget ± 10 %.
- [ ] Every state transition covered by a scenario test.
- [ ] Human gate: owner authorizes unattended mode B after the pilot report.

### AGT-004 — Enforce CI guards and merge policy
Release: R1 · Estimate: 12–18 h · Risk: M · Decisions: D-19 · Closes: —
Dependency changes: AGT-002.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| AGT-004-S01 | Tests for `scope_guard.py` (glob semantics, locks via labels, protected checksums, non-agent branches skipped) | `tools/delivery/tests/test_scope_guard.py` | Each violation class has a failing fixture | 3 |
| AGT-004-S02 | Ruleset-as-code: script that applies branch rulesets, merge queue, required checks, labels (dry-run default; applied by the owner) | `tools/github/apply_rulesets.py`, `docs/development/ci-checks.md` | Dry-run output equals the documented policy (snapshot test) | 4 |
| AGT-004-S03 | CODEOWNERS proposal mapping tier-A paths to human reviewer groups (owner commits it; agents cannot edit CODEOWNERS) | `docs/development/codeowners.proposal` | Every tier-A domain root covered (test) | 2 |
| AGT-004-S04 | Revert automation: on red `main` after merge, open a revert PR labelled `revert` and reopen the task | `tools/github/revert_culprit.py` | Recorded scenario opens exactly one revert PR | 3 |
| AGT-004-S05 | Evidence-manifest check for `agt/*` PRs (schema-valid, commit matches head) | `tools/delivery/check_evidence.py` | Missing/invalid manifest fails; valid passes | 2 |
Task acceptance:
- [ ] Required checks enabled on `main` (human gate: owner applies rulesets and CODEOWNERS).
- [ ] A test PR violating scope, secrets and PRD integrity is blocked by three distinct checks.

### AGT-005 — Automate owner reporting and escalation routing
Release: R1 · Estimate: 12–18 h · Risk: L · Decisions: D-19 · Closes: —
Dependency changes: AGT-003.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| AGT-005-S01 | Metrics writer: per tick JSON lines (tasks, attempts, spend, CI minutes red, escalations) without personal data | `tools/delivery/metrics.py`, `delivery/metrics/*.jsonl` (ledger) | Schema-validated lines; rerun deduplicates | 3 |
| AGT-005-S02 | Daily report generator (French template of STATE_AND_REPORTING §3) with numbers computed by code and narrative by the `reporter` agent | `tools/delivery/report.py` | Report on fixture ledger matches golden file; numbers never invented by the model (computed block) | 4 |
| AGT-005-S03 | Weekly report: velocity, DORA-style metrics, cost per estimated hour, critical-path re-forecast | `tools/delivery/report.py --weekly` | Golden weekly report on fixture ledger | 3 |
| AGT-005-S04 | Publish: GitHub issue comment on the control issue; optional Slack/Linear/Notion adapters behind config | `tools/delivery/publish.py` | Dry-run shows payloads; no adapter enabled without config | 2 |
| AGT-005-S05 | Escalation routing: one issue per escalation, answer parsing from the issue or file, D-39+ append helper | `tools/delivery/escalations.py` | Answered fixture escalation unblocks its task in the next tick | 3 |
Task acceptance:
- [ ] Owner receives one French daily report per day with a "Décisions / actions attendues" section first.
- [ ] Reported numbers reconcile with the ledger (test).

### AGT-006 — Evaluate agent quality with golden tasks and seeded defects
Release: R1 · Estimate: 16–24 h · Risk: M · Decisions: D-19 · Closes: G-AGT-03
Dependency changes: AGT-003.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| AGT-006-S01 | Six golden tasks in a sandbox repo copy (API endpoint, dbt model with money, RLS table, React screen state, Terraform module, migration) with hidden acceptance tests | `tools/agent_eval/golden/*` | Reference solutions pass hidden tests; empty solutions fail | 6 |
| AGT-006-S02 | Seeded-defect PRs (float money, missing tenant predicate, weakened test, scope creep, secret in log, unknown-as-zero) for reviewer evaluation | `tools/agent_eval/defects/*` | Each defect detectable by a deterministic check (ground truth) | 4 |
| AGT-006-S03 | Harness: run worker/reviewer per model, score pass rate, defects caught, false positives, cost, turns | `tools/agent_eval/run.py` | Report JSON per run; reproducible with fixed seeds where applicable | 4 |
| AGT-006-S04 | Policy: minimum scores before raising `max_workers`, switching models or enabling mode B; weekly re-run | `docs/23-agentic-delivery/QUALITY_GATES.md` | Orchestrator reads thresholds from the ledger `control` block | 2 |
Task acceptance:
- [ ] Baseline scores recorded for Opus 5.5 and Sonnet 5 workers and Opus 5.5 reviewers.
- [ ] Reviewer catches ≥ 5 of 6 seeded defects before mode B is authorized.

### AGT-007 — Ratify contracts (wave 1)
Release: R1 · Estimate: 24–40 h · Risk: H · Decisions: D-19 · Closes: G-AGT-02
Dependency changes: AGT-002.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| AGT-007-S01 | Resolve every `contracts/_handoffs/*` item between lanes (one PR per pair of lanes, owning lane decides; decisions → escalations) | updated contracts + handoff files marked RESOLVED | No OPEN handoff item left, or each has an escalation | 8 |
| AGT-007-S02 | Per lane K1–K10: contract-author review against backlog micro-steps and ADRs; fill gaps; examples valid/invalid/foreign-tenant | contract files | `make contracts-check --strict` 0 errors; Spectral clean | 12 |
| AGT-007-S03 | Cross-lane consistency: every OpenAPI `x-capability` exists in authz, every problem code referenced exists, every event consumed is produced, every FK target exists, every dataset referenced by a serving view is declared | `tools/contracts/cross_check.py` | Script passes; seeded inconsistency fails | 6 |
| AGT-007-S04 | Set `status: ACCEPTED` per file (manifests updated) with reviewer approval; regenerate packets | contracts, `contracts/_manifests/*.yaml`, `delivery/packets/*` | `next_tasks.py` shows the wave-2 ready set | 2 |
| AGT-007-S05 | Owner ratification summary (French): what was decided, open questions, impacts | `docs/23-agentic-delivery/CONTRACT_RATIFICATION.md` | Human gate approved | 2 |
Task acceptance:
- [ ] All contracts owned by R1 tasks ACCEPTED or explicitly deferred with an escalation.
- [ ] Human gate: a human reviewer skims the ratification summary and approves.

# Agentic delivery — orchestration architecture

Status: ACCEPTED 2026-09-28 (D-19, [ADR-018](../architecture/adr/ADR-018-agentic-delivery.md)). Audience: the orchestrator model, worker agents, human reviewers and the owner.

The product is implemented by coding agents under a strong orchestrator model, with 1–2 human reviewers and an owner who reads summaries. This document defines who does what, how work flows, how parallel work avoids collisions, which gates need a human, and how the system keeps running for days without drifting.

## 1. Roles

| Role | Actor | Default model | Responsibilities | Never |
|---|---|---|---|---|
| Owner | Human | — | Records decisions, supplies identifiers in `config/environments/`, approves human-only gates, reads daily summaries, answers escalations | Writes code |
| Human reviewer (1–2) | Human | — | Reviews PRs labelled `needs-human`, executes or witnesses live gates that need real credentials, approves production changes | Merges unreviewed agent code |
| Orchestrator | Agent | **Opus 5.5** (`claude-opus-5-5`) or **Fable 5.1** (`claude-fable-5-1`) | Plans waves, dispatches workers, keeps `delivery/state.json`, runs reviews, merges green PRs, resolves conflicts, escalates, writes reports | Writes product features itself; bypasses CI; merges a red PR; edits `docs/00-project/PRD.md` |
| Worker (implementer) | Agent | Tier-dependent (§4) | Implements one task packet in its own worktree and branch, micro-step by micro-step, with tests and evidence; opens one PR | Touches files outside its packet's `writes`; changes an ACCEPTED contract it does not own; merges |
| Reviewer | Agent | **Opus 5.5** | Independent review of each PR against the packet, contracts, conventions and the review rubric (§7); specialized reviewers for security, finance, data, frontend | Approves its own work; approves without running the oracle |
| Verifier | Agent | **Sonnet 5** (`claude-sonnet-5`) | Re-runs the task oracle and required checks from a clean checkout; reproduces failures | Edits code |
| Rescuer | Agent | **Opus 5.5** | Takes over a task after two failed worker attempts, writes a root-cause note, fixes or escalates | Relabels a failure as flake without evidence |

Model IDs are the current ones (Opus 5.5 `claude-opus-5-5`, Fable 5.1 `claude-fable-5-1`, Sonnet 5 `claude-sonnet-5`, Haiku 4.5 `claude-haiku-4-5-20251001`). Aliases (`opus`, `sonnet`, `haiku`, `fable`) may be used in agent definitions; the orchestrator records the model actually used for every task in the state file.

## 2. Unit of work: the task packet

Every task in [revised-task-graph.json](../22-implementation-readiness/revised-task-graph.json) has a generated, self-contained **task packet** in `delivery/packets/<TASK-ID>.md` (format: [TASK_PACKET_FORMAT.md](TASK_PACKET_FORMAT.md)). A packet carries its dependencies, the contracts to read and write, the file globs it may write, the micro-steps with oracles and hours, task acceptance, human/live gates, test commands and the evidence path. Workers read the packet first and follow its links; they do not browse the whole repository.

One task = one branch = one PR by default. A task above ~24 h estimate is delivered as **slices** (consecutive micro-steps, each slice a PR ≤ ~800 changed lines excluding generated files), all on the same task ID.

## 3. The orchestration loop ("tick")

The orchestrator is stateless between ticks: all durable state is in git (`delivery/state.json`, reports, packets) and GitHub (PRs, checks). A tick is safe to repeat and safe to interrupt.

```text
tick:
  1. SYNC       git fetch; read delivery/state.json, open PRs, check runs, answered escalations,
                owner decisions, budget counters.
  2. RECONCILE  merged PRs → mark micro-steps/tasks DONE when evidence + acceptance present;
                red CI on an agent branch → back to its worker (attempt+1);
                leases older than lease_ttl without a commit → reclaim (attempt+1);
                attempts ≥ 2 → Rescuer; attempts ≥ 3 → escalate to human.
  3. PLAN       ready = tasks whose dependencies are DONE, not blocked by an open escalation or
                missing owner input, release in scope, gates satisfiable now.
                Rank: critical path first (REVISED_CRITICAL_PATH), then lane balance, then oldest.
                Admit while: global_workers < max_workers, lane_workers < lane_cap,
                no write-glob overlap with running tasks, required serialization locks free,
                daily budget not exhausted.
  4. DISPATCH   for each admitted task: create worktree + branch agt/<task-id>-<slug> from main,
                reserve migration numbers/revision IDs if the packet needs them,
                launch a Worker with the packet prompt (§5), record the lease in state.
  5. REVIEW     for each PR ready for review: Verifier re-runs oracle + required checks;
                Reviewer(s) apply the rubric; if the packet has a human gate → label needs-human.
                Approved + green + no human gate → add to merge queue (squash merge).
  6. REPORT     update delivery/state.json and delivery/reports/<UTC-date>.md;
                publish the summary (GitHub issue "Delivery report <date>"; optional Slack/Linear/Notion).
  7. STOP?      stop dispatching when: main is red for > 1 tick, daily budget exhausted,
                error rate > threshold, a SEV-class escalation is open, or the owner sets
                delivery/state.json → control.paused = true. Always finish REVIEW/REPORT.
```

Default parameters (tunable in `delivery/state.json → control`): tick every 30 minutes; `max_workers` 6 (2 human reviewers) or 3 (1 reviewer); `lane_cap` 2; `lease_ttl` 4 h; worker `max_turns` 150; per-task budget = estimate_high × `usd_per_estimated_hour` (default 6 USD, reviewed weekly); daily budget cap set by the owner.

## 4. Model tiers

The packet's `model_tier` decides who implements and who reviews:

| Tier | When | Worker | Reviewers |
|---|---|---|---|
| A — critical | Security boundaries, money, ledger, allocation conservation, publication/revision model, IAM/provisioning, RLS, sanitizer, anything with tenant isolation risk (SEC, FIN, ALC, CTL-101, DBT-101, ORC-005, ORC-101, INF-103, SEC-105, API-002/003, LCH-105) | Opus 5.5 | Opus 5.5 reviewer + specialized reviewer (security or finops) + human reviewer on merge |
| B — standard | Most backend, data, frontend and infra tasks | Sonnet 5 | Opus 5.5 reviewer (+ specialized reviewer where the rubric requires) |
| C — mechanical | Docs formatting, generated clients, fixtures conversion, renames, runbook formatting | Sonnet 5 or Haiku 4.5 | Sonnet 5 reviewer |

A worker that hits two failed attempts is replaced by the Rescuer (Opus), whatever the tier.

## 5. Worker prompt (dispatch template)

```text
You are a worker agent implementing task {TASK_ID} in /srv/bridge/worktrees/{TASK_ID} on branch {BRANCH}.
Read, in this order: AGENTS.md, delivery/packets/{TASK_ID}.md, the contracts it lists under contracts_read,
the canonical docs it links. Implement the micro-steps in order. After each micro-step: run the listed
checks, commit with message "<type>(<domain>): {TASK_ID}-Sxx <summary>", and update the packet's
progress block in your PR description. Write only files matching the packet's `writes` globs; if you
need anything else, stop and write an escalation (skill: escalate). Never weaken a test, never skip a
check, never touch secrets. When all micro-steps and task acceptance items pass, write the evidence
manifest to docs/evidence/{TASK_ID}/<short-sha>/ and open the PR with the template. Budget: {BUDGET_USD} USD,
{MAX_TURNS} turns. If a live gate or human gate is required, prepare everything and hand off.
```

## 6. Parallelism without collisions

1. **Lanes.** Tasks belong to lanes A1, A2, B, C, D, E, F, G (see [REVISED_CRITICAL_PATH](../22-implementation-readiness/REVISED_CRITICAL_PATH.md)) plus A0 (delivery tooling, AGT) and H (SaaS surfaces, SAS/PRO). At most `lane_cap` workers per lane.
2. **Write globs.** Each packet declares `writes` (globs). The orchestrator never runs two tasks whose `writes` overlap. A worker whose diff touches a path outside `writes` fails the `scope-guard` CI check.
3. **Serialization locks** (one holder at a time, recorded in state): `lock:lockfiles` (`uv.lock`, `pnpm-lock.yaml`), `lock:pg-migrations` (Alembic head), `lock:sf-migrations/<block>` (Snowflake version block), `lock:openapi-root` (`contracts/openapi/openapi.yaml`), `lock:ci-workflows` (`.github/workflows/**`), `lock:terraform-state/<stack>`.
4. **Contracts.** Code depends only on `ACCEPTED` contracts. A worker needing a contract change opens a separate `contract-change` PR against the owning lane; the Reviewer from the owning lane approves; dependants rebase.
5. **Dependencies (packages).** Adding a library requires the `lock:lockfiles` lock and a justification in the PR (license, maintenance, size). Versions follow [STACK.md](STACK.md); major upgrades are separate tasks.
6. **Rebase, not merge, on agent branches** (branches are agent-owned). The merge queue re-runs CI on the rebased head; conflicts go back to the worker, or to the orchestrator for trivial conflicts in generated files.
7. **Main is always green.** A red main blocks new dispatch; the orchestrator's first action is to revert the culprit PR (revert commit) and reopen the task.

## 7. Review rubric (every PR)

- **Scope**: diff within `writes`; micro-steps listed in the PR match the packet; no drive-by refactors.
- **Contracts**: implementation matches ACCEPTED contracts (OpenAPI, DDL, schemas, state machines); contract tests pass; no new unowned enum, error code or event.
- **Correctness oracle**: the packet's oracle re-run by the Verifier from a clean checkout; expected vs observed recorded.
- **Tests**: new behavior has unit/contract tests written before the implementation (fixture-first); negative cases present; no skipped, xfail or quarantined test introduced; coverage of changed lines ≥ 85 % (Python) / 80 % (TypeScript) unless justified.
- **Tenant isolation** (any tenant-scoped code): foreign-tenant, missing-context and revoked-scope tests present and passing at API, PostgreSQL RLS and Snowflake policy level as applicable.
- **Money** (any amount): decimal strings / `Decimal` / `NUMBER(38,12)` only; golden fixtures pass; no float, no silent rounding, unknown ≠ 0.
- **Security**: no secrets, no credentials in logs, input validation, authz check per capability, SSRF/injection defenses where relevant.
- **Observability**: named metrics/log fields from `packages/telemetry` registries; no PII in logs.
- **UX** (screens): all states (empty/loading/partial/error/denied/success), keyboard access, axe clean, strings externalized, no client-side financial arithmetic.
- **Docs**: runbook/doc updates listed in the packet are present; ADR needed? → escalate instead of improvising.
- **Evidence**: `docs/evidence/<task>/<sha>/index.json` present and complete.

## 8. Gates

| Gate | Who | Examples |
|---|---|---|
| Automatic | CI + Verifier + Reviewer | Every PR |
| Specialized review | Security / FinOps / Data reviewer agents | Tier A tasks; any PR touching `contracts/authz`, RLS, sanitizer, ledger, allocation |
| Live (non-production) | Agents in CI with OIDC → test estate (INF-101), witnessed by a human reviewer for the first run of each gate type | WIF positive/negative/revocation, Snowflake policy attacks, Snowpipe receipts, dbt live build, restore drills in staging |
| Human-only | Human reviewer / owner | Production Terraform apply and deploy approval, making the repository private, IAM permission boundaries in prod, penetration-test scoping, legal/commercial documents, customer onboarding steps, payment evidence (LCH-002), go-live (LCH-003), anything that sends messages to real customers |

Human-only gates are listed per task in its packet (`human_gates`). The orchestrator prepares everything (plan output, evidence, checklists) so the human action takes minutes.

## 9. Escalations and decisions

A worker, reviewer or the orchestrator escalates when: a contract or decision is missing or contradictory; an ACCEPTED contract must change; a vendor behavior differs from the spec (`TO VERIFY LIVE` failed); credentials or budget are needed; two attempts failed; a security or financial invariant might be violated. Escalations are files `delivery/escalations/<id>.md` (template in [STATE_AND_REPORTING.md](STATE_AND_REPORTING.md)) with options and a recommendation; the owner answers in the file (or in the linked GitHub issue); the orchestrator applies the answer and, when it is a decision, appends it to the [decision record](../22-implementation-readiness/DECISIONS_REQUIRED.md).

## 10. Runtime modes

| Mode | How | Use it for |
|---|---|---|
| **A — Interactive orchestrator** | A Claude Code session (Opus 5.5 or Fable 5.1) on the delivery server, following the `orchestrator-tick` skill and spawning worker subagents with worktree isolation | Wave 0 (bootstrap), supervision days, complex conflict resolution |
| **B — Headless loop (recommended steady state)** | `tools/orchestrator` (task AGT-003) runs a tick every 30 min under systemd; workers are `claude -p` processes (or Claude Agent SDK `query()` calls, package `claude-agent-sdk`) in separate worktrees with `--model`, `--max-turns`, restricted `--allowedTools`, `--output-format stream-json` logs | Multi-day autonomous runs |
| **C — GitHub Actions** | `anthropics/claude-code-action@v1` jobs dispatched per task (`workflow_dispatch`) and a scheduled orchestrator tick; self-hosted runners inside the VPC for live gates | Teams preferring CI-hosted isolation and logs |
| **D — Scheduled routines** | Claude Code on the web routines firing the `orchestrator-tick` skill on a cron | Light supervision without a server |

All modes use the same packets, state file, skills, agents, hooks and reports, so they can be switched without losing progress.

## 11. Server for modes A/B

Ubuntu 24.04 LTS VM (8–16 vCPU, 32–64 GB RAM, 250 GB SSD) in the DEV AWS account or on a dedicated host; dedicated Unix user `bridge-agent`; tools from [STACK.md](STACK.md) (git, Docker, Python 3.13 + uv, Node 24 LTS + pnpm, Claude Code CLI, GitHub CLI with a fine-grained token or GitHub App, AWS CLI v2 with SSO/OIDC profiles for DEV only, Terraform, Snowflake CLI for the DEV sandbox); worktrees under `/srv/bridge/worktrees`; orchestrator as a systemd service with log rotation; Anthropic API key or Claude subscription credentials in a root-owned env file readable only by the service user; nightly `git worktree prune` and disk alarms. No production credentials on this server.

## 12. Safety invariants for autonomous operation

1. No agent has production write credentials; production changes flow only through the reviewed release pipeline with human approval.
2. Hooks (`.claude/settings.json`) deterministically block: pushes to `main`, force pushes, `terraform apply` outside DEV, destructive shell commands, reading or writing secret files, edits to the PRD, and commits containing secret patterns.
3. CI blocks: scope violations, contract drift, secrets, license violations, failing tests, coverage regression, missing evidence.
4. Budgets and turn limits bound every worker; the orchestrator stops on budget exhaustion and reports.
5. Every merged change is traceable: task ID → PR → evidence → reviewer → model used.

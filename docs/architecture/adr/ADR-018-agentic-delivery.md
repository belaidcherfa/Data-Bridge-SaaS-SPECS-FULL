# ADR-018 — Agentic delivery system

Status: Accepted 2026-09-28 (owner decision D-19: coding agents with 1–2 human reviewers). Date: 2026-09-28.

## Context

The product (≈ 250 tasks, 7,100–10,500 estimated hours for R1) is implemented by coding agents supervised by one orchestrating model and 1–2 human reviewers. The owner wants multi-day autonomous runs and to check only summaries, escalations and a short list of human gates. Unsupervised agents fail in predictable ways: they drift out of scope, invent contracts, collide on shared files (lockfiles, migrations, OpenAPI root), weaken tests to get green, leak secrets, loop on the same failure, overspend, and report success without evidence. Autonomy therefore needs deterministic structure around the models, not only instructions.

## Decision

1. **Roles and models.** One orchestrator (Opus 5.5 `claude-opus-5-5` or Fable 5.1 `claude-fable-5-1`), workers by tier (A: Opus 5.5; B: Sonnet 5 `claude-sonnet-5`; C: Sonnet 5 or Haiku 4.5), independent reviewers (Opus 5.5, plus security/finops/data/frontend specialists), a verifier (Sonnet 5) that re-runs oracles from a clean checkout, and a rescuer (Opus 5.5) after two failed attempts. Definitions live in `.claude/agents/`; procedures in `.claude/skills/`; rules in `AGENTS.md` ([ORCHESTRATION](../../23-agentic-delivery/ORCHESTRATION.md)).
2. **Task packets are generated, not written.** `tools/delivery/build_packets.py` derives one self-contained packet per task from the revised graph, the backlogs, the contract manifests and `delivery/packet-overrides.yaml` (lane, tier, reviewers, `writes`, `locks`, `contracts_read`, human/live gates, checks). CI fails on drift (`make packets-check`). Packets are the only instructions a worker needs.
3. **Contract-first parallelism.** Lanes code against `ACCEPTED` executable contracts (`contracts/`, ADR-017). Contracts are authored first (K1–K10), then ratified in wave 1 before dependent code starts. Contract changes go through `contract-change` escalations and the owning lane.
4. **Collision control.** Disjoint `writes` globs for concurrently running tasks, serialization locks (`lock:lockfiles`, `lock:pg-migrations`, `lock:sf-migrations/<block>`, `lock:openapi-root`, `lock:ci-workflows`, `lock:terraform-state/<stack>`), per-lane caps and a CI `scope-guard` that fails any PR touching files outside its packet.
5. **Durable state on a ledger branch.** `main` is protected (PR + required checks + merge queue). The orchestrator's live state (`delivery/state.json`, `delivery/reports/`, `delivery/escalations/`, `delivery/metrics/`, `delivery/human-gates/`) is committed every tick to the unprotected branch **`delivery-ledger`**, which only the orchestrator identity may push (branch ruleset). `main` carries the schema, the initial state and the packets. Workers never read the ledger to decide anything: the orchestrator only dispatches tasks whose dependencies are `DONE`. A weekly PR snapshots the ledger into `main` for history.
6. **Deterministic guardrails beat instructions.** Claude Code hooks (`.claude/hooks/`, wired in `.claude/settings.json`) block pushes to `main`, force pushes, `--no-verify`, `terraform apply` outside DEV, reads of secrets, production profiles, edits of the PRD/policy files/real environment files and commits containing secret patterns. CI enforces scope, contracts, tests, coverage, secrets, licenses and evidence. Branch protection and CODEOWNERS enforce human review of tier-A paths. Agents never hold production credentials.
7. **Evidence-based done.** A task is `DONE` only when its PR is merged, every micro-step oracle passed, the evidence manifest (`docs/evidence/schema/evidence.schema.json`) is present and human gates are approved. Live gates are prepared by agents (`live-gate-handoff`) and executed by the CI live job on DEV/test estate or by a human.
8. **Bounded autonomy.** Per-task budget (estimate_high × USD per estimated hour), daily budget, turn limits, lease TTL, attempt limits (2 → rescuer, 3 → human), automatic pause on red `main`, budget exhaustion, error rate > 30 % or a `blocking-all` escalation. The owner's kill switch is `control.paused` in the ledger state (or the `delivery-pause` GitHub label on the control issue, read at SYNC).
9. **Runtime modes.** A (interactive orchestrator session), B (headless loop `tools/orchestrator` with `claude -p` / `claude-agent-sdk` workers under systemd — steady state), C (GitHub Actions with `anthropics/claude-code-action@v1`), D (scheduled Claude Code routines). All share packets, state, skills, hooks and reports.
10. **Reporting in the owner's language.** Daily and weekly reports in French (`daily-report` skill), escalations with options and a recommendation, answered in the file or its GitHub issue; answered decisions extend the decision record (D-39+).

## Alternatives considered

- *One long-running agent doing everything*: context exhaustion, no independent review, single point of failure.
- *Humans write task prompts ad hoc*: drift between prompts and specs, no reproducibility.
- *State in a database or in GitHub issues only*: harder to audit and diff; git keeps state reviewable and replayable, GitHub issues mirror it for notifications.
- *Orchestrator commits state to `main` through PRs every tick*: 48 PRs/day of noise and merge-queue contention; rejected in favour of the ledger branch.
- *Agents with staging/production credentials to "finish" live gates*: unacceptable blast radius; live gates run in CI with OIDC to DEV/test estate, production only through the reviewed release pipeline.

## Consequences

The delivery tooling becomes a product of its own (lane A0, tasks AGT-001…AGT-007) that must be built and trusted before product lanes run unattended. Throughput is bounded by review capacity (Opus reviewers + 1–2 humans), not by worker count; `max_workers` defaults to 6 with two human reviewers, 3 with one. Every merged change is traceable: task → PR → evidence → reviewers → model → cost.

## Revisit conditions

Agent review quality measured by AGT-006 falls below the threshold (escaped defects per 10 merged PRs > 1), costs exceed the budget per estimated hour by > 50 % for two consecutive weeks, or GitHub/Claude Code gain native capabilities that replace the ledger branch or the custom loop.

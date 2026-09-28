# Task packet format (v1)

A task packet is the single file a worker agent needs to start a task. Packets are **generated** by `tools/delivery/build_packets.py` from [revised-task-graph.json](../22-implementation-readiness/revised-task-graph.json), the domain [backlog files](../22-implementation-readiness/backlog/) and `delivery/packet-overrides.yaml`, and written to `delivery/packets/<TASK-ID>.md`. Do not hand-edit generated packets: change the backlog, the graph or the overrides file and regenerate (`make packets`). The orchestrator regenerates packets at the start of every tick.

## Front matter (YAML)

```yaml
packet_version: 1
id: FIN-003
title: Implement classic warehouse compute, query attribution and idle
domain: FIN
lane: C                      # A0, A1, A2, B, C, D, E, F, G, H
release: R1                  # R1 | R2
status: NOT_STARTED          # mirrored from delivery/state.json at generation time
model_tier: A                # A critical | B standard | C mechanical (ORCHESTRATION §4)
estimate_hours: [50, 75]
depends_on: [FIN-002, FIN-102, FIN-103, DBT-003]
blocks: [FIN-009, INS-002, ...]
decisions: [D-12, D-14]
adrs: [ADR-002, ADR-015]
backlog_ref: docs/22-implementation-readiness/backlog/FIN.md#fin-003--...
original_task: docs/tasks/FIN/FIN-003.md
canonical_refs: [docs/08-finops-ledger/ledger.md]
contracts_read: [contracts/CONVENTIONS.md, data/contracts/ledger/fct_charge.schema.json, ...]
writes:                      # globs the worker may modify; CI scope-guard enforces
  - data/dbt/models/ledger/warehouse/**
  - data/dbt/tests/warehouse/**
  - tests/spec/FIN-003/**
  - docs/evidence/FIN-003/**
locks: []                    # serialization locks needed (ORCHESTRATION §6)
human_gates: []              # human-only actions required before merge/done
live_gates: [snowflake-test-estate]
checks:                      # commands the worker must run green before the PR
  - make validate-task TASK=FIN-003 ENV=local
  - make test-contract
evidence_path: docs/evidence/FIN-003/<short-sha>/
micro_steps: [FIN-003-S01, FIN-003-S02, ...]
```

## Body

1. **Objective** — one paragraph from the backlog task.
2. **Read first** — ordered list: `AGENTS.md`, contracts, ADRs, canonical doc sections, related RECONCILIATION rulings, dependency outputs.
3. **Micro-steps** — the backlog table verbatim (Step | Micro-task | Deliverable | Done when | h). Workers implement them in order and tick them in the PR description.
4. **Task acceptance** — the backlog's task-specific checklist.
5. **Definition of done for agents** — AGENTS.md §DoD plus task-specific evidence.
6. **Out of scope** — everything not in the micro-steps; work for other tasks is listed by ID so the worker does not drift.
7. **Escalate when** — standard triggers plus task-specific ones (e.g. "a live Snowflake view lacks a documented column").

## Derivation rules used by the generator

| Field | Source |
|---|---|
| `lane` | REVISED_CRITICAL_PATH lane lists; AGT → A0; SAS/PRO → H; overrides file wins |
| `model_tier` | Domain/task rules in ORCHESTRATION §4; overrides file wins |
| `writes` | Paths in the Deliverable column of the micro-step table (backticked), normalized to directory globs, plus `tests/spec/<ID>/**` and `docs/evidence/<ID>/**`; overrides file adds/removes |
| `contracts_read` | `contracts/CONVENTIONS.md` always; contract paths cited in the task section; contract files owned by the dependency tasks (from `contracts/_manifests/*.yaml`) |
| `human_gates` | Overrides file (curated list per task) |
| `live_gates` | Micro-steps mentioning staging/live/Snowflake estate/AWS staging |
| `locks` | Deliverables under lockfiles, migrations, OpenAPI root, workflows, Terraform stacks |
| `checks` | Standard per domain + `make validate-task TASK=<ID> ENV=local` |

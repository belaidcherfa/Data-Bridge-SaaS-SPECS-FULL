# Implementation-readiness review

Review date: 2026-09-27/28 UTC. Scope: the entire specification set in this repository (PRD, 13 ADRs, 20 domain contracts, 151 task files, machine index, UI/UX design set, React prototype). Purpose: surface every gap, contradiction, subtlety and missing piece of logic **before** production implementation starts, and replace the thin task files with an implementable, production-grade backlog.

Production implementation remains **NOT_STARTED**. This review changes no accepted ADR or canonical contract by itself: where it recommends a change, it is listed as a decision in [DECISIONS_REQUIRED.md](DECISIONS_REQUIRED.md) that the owner must accept.

## Verdict

**Keep the architecture; do not start coding from the current task files.**

The canonical contracts are rigorous on the things that matter most: one additive charge truth separate from attribution, maturity/reconciliation/close as independent states, manifest-based batch acceptance, tenant keys everywhere with deny-by-default, unknown ≠ zero, exact signed decimals. The published fixtures are arithmetically correct.

But the specification is not yet implementable as a production system:

- The 151 task files are ~70 % identical boilerplate, with three real micro-steps each and identical acceptance criteria ([AUDIT X-01…X-04](AUDIT_CROSS_CUTTING.md)).
- Physical designs are missing: no DDL, no Snowflake physical/publication model, no registry formats, no OpenAPI, no state machines ([X-06](AUDIT_CROSS_CUTTING.md)).
- The review recorded **317 findings: 29 BLOCKER, 151 HIGH, 123 MEDIUM, 14 LOW.** The blockers include money computed wrongly (the Snowflake Python connector yields float64 unless configured, estimates cannot be replaced by billing as keyed), data silently lost (long-running queries, dbt identity), tenant-isolation holes (secondary roles default to `ALL`, a Dagster launcher role override, sibling-spend derivation from shares) and missing recovery design ([AUDIT §7](AUDIT_CROSS_CUTTING.md#7-blocking-findings-from-the-domain-audits)).
- First revenue required 147 of 151 tasks through a 73-task serial chain.

All of this is resolvable without changing the product vision. The deliverables below close it.

## Key numbers

| Measure | Before review | After review |
|---|---:|---:|
| Tasks | 151 | 249 (151 original + 98 new; 1 merged) |
| Real micro-steps | 453 (+151 identical "checkpoint" steps) | 2,792, each with a deliverable, a verifiable oracle and hours |
| Contract-first artifacts specified | 0 | 233 |
| Decisions to record | — | 34 (9 need owner input) |
| Longest dependency chain | 73 tasks | 42 tasks (1,360–2,003 h) |
| Breadth gating first payment | everything (41 detectors, 8 templates, public API, AI/SPCS…) | R1 slice only (8 detectors, 4 templates, 3 channels, no public API) |

Effort (senior-engineer hours including tests, review fixes and evidence; from [revised-task-graph.json](revised-task-graph.json)):

| Release | Tasks | Hours |
|---|---:|---:|
| R1 — first paying customer, production grade | 218 | 6,779–9,974 |
| R1\* — only if the first customer needs it (D-20) | 9 | 239–354 |
| R2 — breadth | 21 | 647–1,010 |

Calendar arithmetic (not a commitment; assumptions in [REVISED_CRITICAL_PATH.md](REVISED_CRITICAL_PATH.md)): about 19–28 months with 3 engineers, 12–18 months with 5, 11–17 months with 8 (beyond ~5 engineers the dependency chain, not headcount, binds). Owner decisions, vendor lead times and customer elapsed time (installation, backfill, month close, payment) come on top.

## Reading order

1. [AUDIT_CROSS_CUTTING.md](AUDIT_CROSS_CUTTING.md) — cross-domain findings X-01…X-47 and the 29 blockers by theme.
2. [DECISIONS_REQUIRED.md](DECISIONS_REQUIRED.md) — 34 decisions with recommended defaults; answer the owner-input ones first (D-17 pricing model, D-18 localization, D-19 team capacity, D-20 first-customer profile, D-25 compliance, D-30 invoicing channel, D-32 non-production budget).
3. [RELEASE_PLAN.md](RELEASE_PLAN.md) and [REVISED_CRITICAL_PATH.md](REVISED_CRITICAL_PATH.md) — R1/R2 slicing, lanes, tenant zero and design partner, critical path, staffing scenarios.
4. [CONTRACT_FIRST_ARTIFACTS.md](CONTRACT_FIRST_ARTIFACTS.md) — what to author before the first line of production code, in order.
5. [backlog/](backlog/) — one file per domain: verdict, findings with evidence, contract artifacts, the revised task decomposition (micro-steps, oracles, hours), new tasks, estimates, owner questions.
6. [RECONCILIATION.md](RECONCILIATION.md) — rulings on overlapping tasks and cross-domain contradictions; its rulings take precedence over individual backlog files.
7. [revised-task-graph.json](revised-task-graph.json) — machine-readable revised plan (validated: all dependencies exist, acyclic, no R1 task depends on R1\*/R2).

| Domain backlog | Domain backlog | Domain backlog | Domain backlog |
|---|---|---|---|
| [FND](backlog/FND.md) engineering foundation | [INF](backlog/INF.md) AWS platform | [SEC](backlog/SEC.md) identity & isolation | [CTL](backlog/CTL.md) control plane |
| [CON](backlog/CON.md) Snowflake connectivity | [ING](backlog/ING.md) ingestion | [ORC](backlog/ORC.md) orchestration | [DBT](backlog/DBT.md) transformation |
| [FIN](backlog/FIN.md) ledger & reconciliation | [API](backlog/API.md) semantic API | [UX](backlog/UX.md) product UX & UI docs | [WRK](backlog/WRK.md) workloads |
| [ALC](backlog/ALC.md) allocation | [GOV](backlog/GOV.md) budgets & monitors | [INS](backlog/INS.md) insights & savings | [RPT](backlog/RPT.md) reporting |
| [OPS](backlog/OPS.md) operations | [REL](backlog/REL.md) release | [ONB](backlog/ONB.md) onboarding | [LCH](backlog/LCH.md) commercial launch |

## How to start implementation from here

1. Record the 34 decisions (accept the recommendation or replace it). Turn D-02, D-04, D-05/D-06, D-07 and D-26 into ADR amendments or a new ADR-014.
2. Approve the non-production budget (D-32) and order the Snowflake test estate (INF-101); it gates every live test.
3. Author the phase-P0 contract artifacts in the order of [CONTRACT_FIRST_ARTIFACTS.md §1](CONTRACT_FIRST_ARTIFACTS.md#1-cross-domain-artifacts-to-author-first-phase-p0). Freeze the widened source projections (ING-101) before any backfill: fields not extracted then are lost for history.
4. Start lanes A1 (platform) and A2 (identity/control plane) in parallel, then B and C; connect **tenant zero** (Bridge's own Snowflake accounts) as soon as acquisition works, and a design partner by mid-lane C.
5. Execute tasks from the backlog files, not from the original task files' micro-steps. The original task files keep their IDs, objectives and canonical links; the backlog supersedes their steps, dependencies and acceptance criteria once the decisions are recorded.

## Method and limits

- The lead reviewer read the PRD, all ADRs and all domain contracts in full, measured the task files and dependency graph programmatically, and wrote the cross-cutting audit and decision register. Nine domain audits ran in parallel against a shared brief; an integration pass reconciled them and rebuilt the graph; a final pass applied the rulings to the backlog files.
- Vendor behavior is marked **VERIFIED** (182 occurrences, with source) or **TO VERIFY LIVE** (160 occurrences) in the backlog files. `docs.snowflake.com` could not be fetched directly during the review; Snowflake facts were verified through search results, connector/adapter source code on GitHub and PyPI. Every VERIFIED claim still needs the live proof its task specifies.
- No live AWS or Snowflake test was run. Estimates are bottom-up engineering estimates with explicit low–high ranges, not commitments.
- Commercial, legal and tax statements (e-invoicing, VAT, DPA) are prompts for qualified counsel and an accountant, not advice.

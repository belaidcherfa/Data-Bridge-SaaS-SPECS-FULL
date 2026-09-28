# Implementation-readiness review

Review date: 2026-09-27/28 UTC. Scope: the entire specification set in this repository (PRD, 13 ADRs, 20 domain contracts, 151 task files, machine index, UI/UX design set, React prototype). Purpose: surface every gap, contradiction, subtlety and missing piece of logic **before** production implementation starts, and replace the thin task files with an implementable, production-grade backlog.

Production implementation remains **NOT_STARTED**. **Update 2026-09-28: the owner recorded all 38 decisions** ([decision record](DECISIONS_REQUIRED.md)); the ADRs and canonical contracts were amended accordingly (ADR-014 to ADR-016 added), and the revised task graph and domain backlogs are now the execution plan.

## Verdict

**Keep the architecture; execute from the revised backlog, not from the original task files.**

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
| Tasks | 151 | 249 (151 original + 99 new; 1 merged) |
| Real micro-steps | 453 (+151 identical "checkpoint" steps) | 2,809, each with a deliverable, a verifiable oracle and hours |
| Contract-first artifacts specified | 0 | 234 |
| Decisions | — | 38, all recorded on 2026-09-28 |
| Longest dependency chain | 73 tasks | 42 tasks (1,362–2,006 h) |
| Breadth gating first payment | everything (41 detectors, 8 templates, public API, AI/SPCS…) | R1: every service family, edition and contract type (D-20), 8 detectors, 4 templates, 4 channels, no public API |

Effort after the owner's decisions (senior-engineer-equivalent hours including tests, review fixes and evidence; from [revised-task-graph.json](revised-task-graph.json)):

| Release | Tasks | Hours |
|---|---:|---:|
| R1 — first paying customer, production grade, all Snowflake editions/contracts/services (D-20) | 229 | 7,116–10,488 |
| R2 — breadth | 20 (+ R2 parts of R1 tasks) | 614–948 |

Delivery model (D-19): coding agents execute the backlog under 1–2 human reviewers. The dependency chain (42 tasks), review capacity (2–3 agent lanes per reviewer) and human-run live gates bound the calendar; for comparison, a human team would need about 20–29 months with 3 engineers, 12–18 with 5, 11.5–17 with 8 ([RELEASE_PLAN.md §5](RELEASE_PLAN.md#5-estimates)).

## Reading order

1. [AUDIT_CROSS_CUTTING.md](AUDIT_CROSS_CUTTING.md) — cross-domain findings X-01…X-47 and the 29 blockers by theme.
2. [DECISIONS_REQUIRED.md](DECISIONS_REQUIRED.md) — the decision record: 38 decisions recorded on 2026-09-28, with the consequences of the owner's choices.
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

1. Decisions are recorded and the ADRs amended (ADR-014 analytical revisions, ADR-015 financial grain/maturity/attribution, ADR-016 customer coverage/residency/reachability). Open questions left for the owner are listed in section 7 of the relevant backlog files (e.g. spend-band tables, whether a paid pilot satisfies M12).
2. Order the Snowflake test estate (INF-101) within the approved non-production budget (D-32); it gates every live test.
3. Author the phase-P0 contract artifacts in the order of [CONTRACT_FIRST_ARTIFACTS.md §1](CONTRACT_FIRST_ARTIFACTS.md#1-cross-domain-artifacts-to-author-first-phase-p0). Freeze the widened source projections (ING-101) before any backfill: fields not extracted then are lost for history.
4. Write `AGENTS.md` (FND-006) so coding agents follow the review, evidence and live-gate rules; then start lanes A1 (platform) and A2 (identity/control plane), then B and C. Connect **tenant zero** (Bridge's own Snowflake accounts) as soon as acquisition works, and a contracted pilot customer by mid-lane C.
5. Execute tasks from the backlog files and the revised graph, not from the original task files' micro-steps ([DELIVERY_METHODOLOGY.md](../../DELIVERY_METHODOLOGY.md) now says so).

## Method and limits

- The lead reviewer read the PRD, all ADRs and all domain contracts in full, measured the task files and dependency graph programmatically, and wrote the cross-cutting audit and decision register. Nine domain audits ran in parallel against a shared brief; an integration pass reconciled them and rebuilt the graph; a final pass applied the rulings to the backlog files.
- Vendor behavior is marked **VERIFIED** (182 occurrences, with source) or **TO VERIFY LIVE** (160 occurrences) in the backlog files. `docs.snowflake.com` could not be fetched directly during the review; Snowflake facts were verified through search results, connector/adapter source code on GitHub and PyPI. Every VERIFIED claim still needs the live proof its task specifies.
- No live AWS or Snowflake test was run. Estimates are bottom-up engineering estimates with explicit low–high ranges, not commitments.
- Commercial, legal and tax statements (e-invoicing, VAT, DPA) are prompts for qualified counsel and an accountant, not advice.

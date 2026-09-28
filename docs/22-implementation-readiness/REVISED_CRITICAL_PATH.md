# Revised critical path and delivery arithmetic

> **Recomputed 2026-09-28 after the owner's decisions.** D-20 moved all nine former R1\* tasks (FIN-004, FIN-012, FIN-017, FIN-018, FIN-019, FIN-020, UX-007, WRK-003, SEC-003) and the R1 part of ING-105 into R1; D-17 added LCH-105. R1 is now **229 tasks, 7,116–10,488 h**; R2 614–948 h. The critical path is unchanged in shape — **42 tasks, 1,362–2,006 h** — because the added work has slack; LCH-002 (first payment) now requires 227 of the 228 other R1 tasks (all but LCH-004), since OPS-011 qualification gates every service family. List-scheduled makespan at 120 h per engineer-month: 3 engineers 19.9–29.4 months, 5 engineers 12.4–18.4, 8 engineers 11.5–16.7. With coding agents (D-19) the calendar is bounded by the chain, reviewer capacity and human-run live gates rather than headcount ([RELEASE_PLAN §5](RELEASE_PLAN.md#5-estimates)). The detailed tables below were computed before these changes (R1 218 tasks, 6,779–9,974 h); their chain composition and lane structure remain valid.

Computed on 2026-09-28 from [revised-task-graph.json](revised-task-graph.json) (249 entries; rulings in [RECONCILIATION.md](RECONCILIATION.md)). The scripts (`validate_graph.py`, `compute_cp.py`) were run by the integration reviewer; every figure below is reproducible from the JSON. This is arithmetic on estimates, not a delivery commitment.

## 0. Assumptions

1. **Scope.** R1 = the 218 live tasks tagged `R1` (6,779–9,974 h). R1\* (9 tasks, 239–354 h, plus FIN-008's 8–12 h replication part) is shown separately; R2 (21 tasks) is excluded. The merged task CTL-103 is excluded.
2. **Edges.** X → Y means X cannot be DONE before Y is DONE. Step-level, contract-only and soft dependencies are not edges; live/staging gates are (RECONCILIATION §0).
3. **Hours.** One senior engineer-hour including tests, review fixes and evidence (D-19); low and high estimates from the backlogs after de-duplication.
4. **Execution.** One engineer works a task at a time (no splitting), a task starts when all its dependencies are DONE, and engineers are interchangeable. The last point is optimistic (see risk R-07).
5. **Capacity.** 120 productive hours per engineer-month (meetings, support and leave already removed).
6. **Not in the hours.** Owner-decision latency, vendor lead times (Snowflake organization creation, SES production access, pentest booking), customer elapsed time (procurement, script runs, backfill, month close, payment terms). They are listed in §(d).

## (a) Longest R1 dependency chain

| Measure | Original index (151 tasks) | Revised graph (R1) |
|---|---:|---:|
| Longest chain in task count | 73 | **42** |
| Hour-weighted longest chain, low | 2,596 h (71 tasks)¹ | **1,360 h** (41 tasks) |
| Hour-weighted longest chain, high | 3,810 h (71 tasks)¹ | **2,003 h** (40 tasks) |
| Chain as calendar time for one engineer at 120 h/month | 21.6–31.8 months | **11.3–16.7 months** |

¹ The original dependency structure weighted with the backlog §6 hours of the same 151 tasks (the 73-task chain itself carries 2,551–3,723 h). It excludes the 98 new tasks, so it understates the original plan.

Original 73-task chain, for reference: FND-001 → FND-002 → FND-003 → FND-004 → FND-005 → FND-006 → INF-001 → INF-002 → INF-003 → INF-004 → INF-005 → INF-006 → SEC-002 → SEC-004 → CTL-001 → CON-001 → CON-002 → CON-003 → CON-004 → CON-005 → ING-001 → ING-002 → ING-003 → ING-004 → ING-005 → ING-006 → ING-007 → ING-008 → ORC-002 → ORC-003 → ORC-004 → DBT-001 → DBT-002 → DBT-003 → DBT-004 → DBT-005 → FIN-001 → FIN-002 → FIN-003 → FIN-004 → FIN-009 → API-001 → WRK-001 → ALC-001 → ALC-002 → ALC-003 → ALC-004 → ALC-005 → ALC-006 → ALC-007 → GOV-001 → GOV-002 → GOV-004 → GOV-006 → GOV-007 → GOV-008 → RPT-003 → RPT-004 → RPT-005 → OPS-005 → OPS-006 → OPS-010 → OPS-011 → REL-001 → REL-002 → REL-003 → LCH-001 → ONB-003 → ONB-004 → ONB-005 → LCH-002 → LCH-003 → LCH-004

**By task count (42 tasks, 1,333–1,946 h):**

FND-001 → INF-001 → INF-102 → INF-002 → INF-004 → CTL-101 → SEC-004 → CTL-001 → CTL-002 → CTL-004 → ING-002 → ORC-003 → ING-106 → ING-007 → ING-008 → DBT-002 → DBT-003 → DBT-004 → DBT-005 → FIN-103 → FIN-011 → FIN-007 → FIN-009 → API-101 → API-002 → API-003 → API-004 → ALC-003 → ALC-004 → ALC-005 → ALC-101 → ALC-102 → ALC-006 → ALC-007 → UX-008 → OPS-011 → REL-004 → LCH-003 → ONB-003 → ONB-004 → ONB-005 → LCH-002

**Hour-weighted, low estimates (1,360 h; the high estimates of the same 41 tasks sum to 1,987 h):**

| # | Task | Release | Lane | h (low–high) | Cumulative low–high |
|---:|---|---|---|---:|---:|
| 1 | FND-001 Create monorepo boundaries and dependency rules | R1 | A1 | 18–26 | 18–26 |
| 2 | INF-001 Bootstrap AWS organization, accounts, state and environment guards | R1 | A1 | 34–48 | 52–74 |
| 3 | INF-102 Terraform delivery pipeline: OIDC plan/apply roles, plan policy and drift detection | R1 | A1 | 18–26 | 70–100 |
| 4 | INF-002 Create VPC, endpoints, controlled egress and in-VPC runners | R1 | A1 | 32–44 | 102–144 |
| 5 | INF-004 Provision Aurora and Valkey with safe resource budgets | R1 | A1 | 28–40 | 130–184 |
| 6 | CTL-101 Control DB kernel (migration runner, roles, unit of work, outbox/idempotency/audit tables) | R1 | A2 | 36–56 | 166–240 |
| 7 | SEC-004 Implement scoped RBAC and tenant RLS foundation | R1 | A2 | 52–80 | 218–320 |
| 8 | CTL-001 Extend tenant, organization, account and team schemas | R1 | A2 | 30–46 | 248–366 |
| 9 | CTL-002 Migration safety, indexes and bounded connection pools | R1 | A2 | 38–58 | 286–424 |
| 10 | CTL-004 Outbox dispatcher and fenced job leases | R1 | A2 | 40–60 | 326–484 |
| 11 | ING-002 Implement UTC window planning, pass schedules and source horizons | R1 | B | 36–52 | 362–536 |
| 12 | ORC-003 Implement fair admission, schedules and idempotent sensors | R1 | B | 38–54 | 400–590 |
| 13 | ING-106 Account-cycle runner and extractor ↔ control-plane trust path (D-07) | R1 | B | 37–54 | 437–644 |
| 14 | ING-007 Build file receipts and complete-batch acceptance | R1 | B | 44–64 | 481–708 |
| 15 | ORC-101 Processing ledger, build snapshot and workset planner | R1 | C | 34–48 | 515–756 |
| 16 | DBT-002 Implement staging dedup and complete-partition selection | R1 | C | 34–48 | 549–804 |
| 17 | DBT-003 Resolve resource history, account membership and workload joins | R1 | C | 28–40 | 577–844 |
| 18 | DBT-004 Implement workset-bounded rebuilds and shadow rebuild | R1 | C | 34–48 | 611–892 |
| 19 | DBT-005 Build golden financial tests and tenant-safe CI | R1 | C | 34–50 | 645–942 |
| 20 | FIN-103 Exact attribution framework (allocate_exact, residual kinds, bridge conventions) | R1 | C | 26–40 | 671–982 |
| 21 | FIN-003 Implement classic warehouse compute, query attribution and idle | R1 | C | 50–75 | 721–1,057 |
| 22 | FIN-009 Build reconciliation controls and financial health UX | R1 | C | 70–100 | 791–1,157 |
| 23 | API-101 Bind the registry to published serving views and certify it on Snowflake (new, split from API-001) | R1 | D | 24–34 | 815–1,191 |
| 24 | API-002 Safe analytical planner and Snowflake query broker | R1 | D | 48–68 | 863–1,259 |
| 25 | API-003 Response metadata, sealed cursors, publication pins and cache | R1 | D | 36–50 | 899–1,309 |
| 26 | API-004 Asynchronous analysis jobs and cancellation | R1 | D | 32–46 | 931–1,355 |
| 27 | ALC-003 Build simulation, review and ruleset publication | R1 | E | 54–77 | 985–1,432 |
| 28 | ALC-004 Implement usage group sets and effective hierarchies | R1 | E | 37–53 | 1,022–1,485 |
| 29 | ALC-005 Implement allocation methods and conservation | R1 | E | 49–70 | 1,071–1,555 |
| 30 | ALC-101 Group-scope authorization and restricted allocation serving | R1 | E | 31–44 | 1,102–1,599 |
| 31 | ALC-102 Allocation metrics and group dimensions in the semantic registry | R1 | E | 13–18 | 1,115–1,617 |
| 32 | ALC-006 Build allocation studio and quality remediation | R1 | E | 37–53 | 1,152–1,670 |
| 33 | ALC-007 Build scoped showback portal | R1 | E | 30–43 | 1,182–1,713 |
| 34 | UX-008 End-to-end product-state, accessibility and navigation qualification | R1 | D | 38–52 | 1,220–1,765 |
| 35 | OPS-011 Complete cross-product QA and release evidence matrix | R1 | G | 44–66 | 1,264–1,831 |
| 36 | REL-004 Approve immutable release candidate and production gate | R1 | G | 12–18 | 1,276–1,849 |
| 37 | LCH-003 Production go-live for the first customer and monitored rollout | R1 | G | 12–20 | 1,288–1,869 |
| 38 | ONB-003 Prepare authorized first-customer environment and identities | R1 | G | 18–30 | 1,306–1,899 |
| 39 | ONB-004 Complete historical synchronization and customer reconciliation (FV-1 financial evidence) | R1 | G | 26–42 | 1,332–1,941 |
| 40 | ONB-005 Complete FV-1 workshop and customer acceptance | R1 | G | 20–32 | 1,352–1,973 |
| 41 | LCH-002 Verify first customer acceptance and payment evidence (M12 gate) | R1 | G | 8–14 | 1,360–1,987 |

**Hour-weighted, high estimates (2,003 h, 40 tasks).** The first 24 tasks are identical to the low path (through API-002, cumulative 863–1,259 h); it then runs through governance and reporting instead of allocation:

| # | Task | Release | Lane | h (low–high) | Cumulative low–high |
|---:|---|---|---|---:|---:|
| 1 | FND-001 Create monorepo boundaries and dependency rules | R1 | A1 | 18–26 | 18–26 |
| 2 | INF-001 Bootstrap AWS organization, accounts, state and environment guards | R1 | A1 | 34–48 | 52–74 |
| 3 | INF-102 Terraform delivery pipeline: OIDC plan/apply roles, plan policy and drift detection | R1 | A1 | 18–26 | 70–100 |
| 4 | INF-002 Create VPC, endpoints, controlled egress and in-VPC runners | R1 | A1 | 32–44 | 102–144 |
| 5 | INF-004 Provision Aurora and Valkey with safe resource budgets | R1 | A1 | 28–40 | 130–184 |
| 6 | CTL-101 Control DB kernel (migration runner, roles, unit of work, outbox/idempotency/audit tables) | R1 | A2 | 36–56 | 166–240 |
| 7 | SEC-004 Implement scoped RBAC and tenant RLS foundation | R1 | A2 | 52–80 | 218–320 |
| 8 | CTL-001 Extend tenant, organization, account and team schemas | R1 | A2 | 30–46 | 248–366 |
| 9 | CTL-002 Migration safety, indexes and bounded connection pools | R1 | A2 | 38–58 | 286–424 |
| 10 | CTL-004 Outbox dispatcher and fenced job leases | R1 | A2 | 40–60 | 326–484 |
| 11 | ING-002 Implement UTC window planning, pass schedules and source horizons | R1 | B | 36–52 | 362–536 |
| 12 | ORC-003 Implement fair admission, schedules and idempotent sensors | R1 | B | 38–54 | 400–590 |
| 13 | ING-106 Account-cycle runner and extractor ↔ control-plane trust path (D-07) | R1 | B | 37–54 | 437–644 |
| 14 | ING-007 Build file receipts and complete-batch acceptance | R1 | B | 44–64 | 481–708 |
| 15 | ORC-101 Processing ledger, build snapshot and workset planner | R1 | C | 34–48 | 515–756 |
| 16 | DBT-002 Implement staging dedup and complete-partition selection | R1 | C | 34–48 | 549–804 |
| 17 | DBT-003 Resolve resource history, account membership and workload joins | R1 | C | 28–40 | 577–844 |
| 18 | DBT-004 Implement workset-bounded rebuilds and shadow rebuild | R1 | C | 34–48 | 611–892 |
| 19 | DBT-005 Build golden financial tests and tenant-safe CI | R1 | C | 34–50 | 645–942 |
| 20 | FIN-103 Exact attribution framework (allocate_exact, residual kinds, bridge conventions) | R1 | C | 26–40 | 671–982 |
| 21 | FIN-003 Implement classic warehouse compute, query attribution and idle | R1 | C | 50–75 | 721–1,057 |
| 22 | FIN-009 Build reconciliation controls and financial health UX | R1 | C | 70–100 | 791–1,157 |
| 23 | API-101 Bind the registry to published serving views and certify it on Snowflake (new, split from API-001) | R1 | D | 24–34 | 815–1,191 |
| 24 | API-002 Safe analytical planner and Snowflake query broker | R1 | D | 48–68 | 863–1,259 |
| 25 | GOV-001 Implement scoped budgets and actuals | R1 | E | 42–60 | 905–1,319 |
| 26 | GOV-003 Define monitor DSL, validation and schedule planner | R1 | E | 45–64 | 950–1,383 |
| 27 | GOV-004 Implement partition evaluation, incident state and suppression | R1 | E | 47–67 | 997–1,450 |
| 28 | GOV-007 Implement delivery outbox, retries, DLQ and premium alerts | R1 | E | 39–55 | 1,036–1,505 |
| 29 | RPT-004 Implement calendar schedules and report occurrence planning | R1 | E | 40–60 | 1,076–1,565 |
| 30 | RPT-005 Implement report history, secure access and retention | R1 | E | 25–38 | 1,101–1,603 |
| 31 | OPS-004 Run adversarial tenant isolation and internal security qualification | R1 | G | 56–84 | 1,157–1,687 |
| 32 | OPS-010 Publish runbooks, incident process and run incident exercises | R1 | G | 46–70 | 1,203–1,757 |
| 33 | REL-002 Rehearse production deployment and rollback (code, publication, forward fix) | R1 | G | 36–56 | 1,239–1,813 |
| 34 | REL-003 Assemble operational, commercial and support readiness pack | R1 | G | 22–34 | 1,261–1,847 |
| 35 | REL-004 Approve immutable release candidate and production gate | R1 | G | 12–18 | 1,273–1,865 |
| 36 | LCH-003 Production go-live for the first customer and monitored rollout | R1 | G | 12–20 | 1,285–1,885 |
| 37 | ONB-003 Prepare authorized first-customer environment and identities | R1 | G | 18–30 | 1,303–1,915 |
| 38 | ONB-004 Complete historical synchronization and customer reconciliation (FV-1 financial evidence) | R1 | G | 26–42 | 1,329–1,957 |
| 39 | ONB-005 Complete FV-1 workshop and customer acceptance | R1 | G | 20–32 | 1,349–1,989 |
| 40 | LCH-002 Verify first customer acceptance and payment evidence (M12 gate) | R1 | G | 8–14 | 1,357–2,003 |

**Where the chain runs.** Low path by lane: A1 platform 5 tasks, A2 security/control plane 5, B acquisition 4, C analytical kernel 8, D API/UX 5, E allocation 7, G launch 7. The spine is fixed by the architecture: platform kernel (INF → CTL-101 → SEC-004 → CTL-001/002/004) → acquisition (ING-002 → ORC-003 → ING-106 → ING-007) → analytical kernel (ORC-101 → DBT-002…005 → FIN-103 → FIN-003 → FIN-009) → serving (API-101 → API-002) → either allocation (ALC-003…ALC-007 → UX-008 → OPS-011) or governance/reporting (GOV-001…RPT-005 → OPS-004 → OPS-010 → REL-002/003) → launch tail (REL-004 → LCH-003 → ONB-003 → ONB-004 → ONB-005 → LCH-002). The first 22 tasks alone (through FIN-009) are 791–1,157 h.

**What shortened it (from 73 tasks).** FND is no longer a six-task prefix (INF-001 −FND-006, FND-004/005 parallel); the INF chain dropped from 8 to 4 (INF-102 first, INF-003/005/006/008 parallel); SEC-002 no longer waits for edge/DNS and SEC-004 no longer waits for Cognito; ING-001 precedes CON-005 and DBT-001 no longer waits for ORC-004; FIN-001 precedes DBT-005; API-001 and ALC-001 no longer wait for FIN-009; WRK, INS, GOV-002, RPT-003, UX-007 and all R1\*/R2 detail left the chain; OPS foundations moved to M1–M5; LCH-003 go-live precedes customer onboarding; REL-001 no longer waits for OPS-011 (C-29).

**Levers not applied (quantified).**
- Treating the API-101 certification as a staging gate for API-002 instead of a DONE gate shortens the chain to **1,153–1,697 h** (−207 / −306 h); the next binding chain then runs FIN-009 → API-101 → API-104 → UX-002 → INS-101 → INS-006 → INS-007 → OPS-011 (again a live-gate edge: UX-002 +API-104). The cost is integration risk found later (risk R-05).
- Making FIN-108 (crosswalk v1) step-level for FIN-002 does not change the chain (FIN-108 has 84–118 h of slack).
- Splitting FIN-009 (70–100 h: controls engine vs financial-health UX) and pairing on the heaviest chain tasks (FIN-009, ALC-003, SEC-004, FIN-003, ALC-005, API-002, ING-007) are the remaining levers. Illustration: if two engineers take each of the 15 heaviest low-path tasks (668 h) at 65 % of single-engineer duration, the low chain falls by ≈ 234 h to ≈ 1,126 h.
- Scope decisions under D-20 do not move the chain: all nine R1\* tasks have slack (R1+R1\* chain = R1 chain).

## (b) Prerequisites of the first payment (LCH-002)

| | Original index | Revised graph |
|---|---|---|
| LCH-002 transitive prerequisites | 147 of the other 150 tasks (98 %) | 216 of the other 217 R1 tasks; **0** of the 9 R1\* and **0** of the 21 R2 tasks |
| Tasks not required | SEC-003, LCH-003, LCH-004 | LCH-004 only (day-30 validation after launch) |
| Original tasks among the prerequisites | 147 | 138 (FIN-004, FIN-012, FIN-017, FIN-018, FIN-019, FIN-020, SEC-003, UX-007, WRK-003, API-006, INS-005 left; LCH-003 joined, because go-live now precedes onboarding) |
| Breadth on the path | all 41 detectors, 8 report templates, 4 channels, public API, AI/SPCS pages, Adaptive/Cortex/SPCS/marketplace ledgers | 8 detectors, 4 templates, Email/Slack/Webhook, no public API, no AI/SPCS pages, no R1\* ledgers |
| Hours gating LCH-002 | — | 6,759–9,942 h (all R1 work except LCH-004) |
| Hours no longer gating LCH-002 | — | 886–1,364 h of R1\*/R2 tasks + 24–38 h of R1\*/R2 parts of R1 tasks |

The count is not the useful metric: R1 is, by construction (D-01), the slice the first paying customer needs, so every R1 task except post-launch validation must precede the first payment. What changed is the **shape** (a 42-task chain instead of 73, and eight lanes that can run concurrently) and the **breadth** (≈ 0.9–1.4 k hours of detail no longer gate revenue). The count grew only because 78 new R1 tasks make previously hidden work explicit (IAM provisioning, test estate, revision/publication design, money library, entitlements, legal pack, operator plane…).

## (c) Parallel lanes

Lane assignment is by domain with the overrides noted in RECONCILIATION (OPS/REL foundations join lane A1; ORC publication tasks join the analytical kernel; LCH-101 joins A2 because it gates admission from M2).

| Lane | Scope | R1 tasks | R1 h (low–high) | Engineer-months at 120 h | Lane-internal longest chain (low h, tasks) | R1* tasks in lane (h) |
|---|---|---:|---:|---:|---:|---|
| A1 | Platform, infrastructure & ops foundations | 31 | 783–1,147 | 6.5–9.6 | 224 h, 8 | — |
| A2 | Identity, security & control plane | 21 | 833–1,287 | 6.9–10.7 | 341 h, 9 | SEC-003 (56–84) |
| B | Data acquisition (CON, ING, extraction orchestration) | 34 | 1,082–1,583 | 9.0–13.2 | 307 h, 8 | — |
| C | Analytical kernel (dbt, publication, ledger) | 41 | 1,209–1,761 | 10.1–14.7 | 448 h, 11 | FIN-004, FIN-012, FIN-017, FIN-018, FIN-019, FIN-020 (131–196) |
| D | Product API, UX & workloads | 27 | 847–1,192 | 7.1–9.9 | 324 h, 9 | UX-007, WRK-003 (52–74) |
| E | Allocation, governance & reporting | 28 | 934–1,343 | 7.8–11.2 | 376 h, 10 | — |
| F | Optimization (insights) | 8 | 274–406 | 2.3–3.4 | 163 h, 4 | — |
| G | Qualification, release, onboarding & launch | 28 | 817–1,255 | 6.8–10.5 | 256 h, 10 | — |

Observations:
- **C (analytical kernel) and B (acquisition) are the capacity bottlenecks**: at one engineer each they would take 10.1–14.7 and 9.0–13.2 months — as long as the whole critical path — and lane C holds 8 of the 41 chain tasks. Both need a second engineer at their peak (M3–M6).
- **A1 and A2 front-load**: all of the first 10 chain tasks are theirs; they free up by roughly month 3–4 and can move to G (qualification) and E.
- **F (optimization) is small and late** (274–406 h, all after FIN/GOV): staff it from C or E rather than with a dedicated engineer.
- **G mixes early and late work**: the legal/commercial pack (LCH-102/103/104) and the cost model start at P0 with owner input; qualification (OPS-003/004/008/010/011) and launch converge at the end.

Suggested staffing (one engineer = one lane at a time):

| Engineers | Mapping |
|---|---|
| 3 | (1) A1 + A2, then G qualification; (2) B then C; (3) D, then E and F. Lane C starts only when B's acquisition chain is done, which is why 3 engineers are capacity-bound (below). |
| 5 | (1) A1 → G; (2) A2 → E (governance); (3) B → F; (4) C; (5) D → E (allocation). The C engineer is on the chain for ~8 months; B's engineer joins C after ING-007. |
| 8 | One per lane A1, A2, B, C, D, E, G; the eighth works C in parallel from M3 and moves to F. Beyond this the chain, not headcount, binds (utilization 62 %). |

Task lists per lane (R1):

- **A1 · Platform, infrastructure & ops foundations** (31 R1 tasks, 783–1,147 h): FND-001, FND-002, FND-003, FND-004, FND-005, FND-006, FND-101, FND-102, FND-103, INF-001, INF-002, INF-003, INF-004, INF-005, INF-006, INF-007, INF-008, INF-101, INF-102, INF-103, INF-104, INF-105, OPS-001, OPS-006, OPS-102, OPS-104, OPS-106, OPS-108, REL-101, REL-102, REL-104.
- **A2 · Identity, security & control plane** (21 R1 tasks, 833–1,287 h): CTL-001, CTL-002, CTL-003, CTL-004, CTL-005, CTL-006, CTL-101, CTL-102, LCH-101, SEC-001, SEC-002, SEC-004, SEC-005, SEC-006, SEC-007, SEC-008, SEC-101, SEC-102, SEC-103, SEC-104, SEC-105. R1*: SEC-003.
- **B · Data acquisition (CON, ING, extraction orchestration)** (34 R1 tasks, 1,082–1,583 h): CON-001, CON-002, CON-003, CON-004, CON-005, CON-006, CON-101, CON-102, ING-001, ING-002, ING-003, ING-004, ING-005, ING-006, ING-007, ING-008, ING-009, ING-010, ING-011, ING-012, ING-101, ING-102, ING-103, ING-104, ING-106, ING-107, INS-102, OPS-101, OPS-103, OPS-105, ORC-001, ORC-002, ORC-003, ORC-102.
- **C · Analytical kernel (dbt, publication, ledger)** (41 R1 tasks, 1,209–1,761 h): DBT-001, DBT-002, DBT-003, DBT-004, DBT-005, DBT-006, DBT-101, DBT-102, DBT-103, FIN-001, FIN-002, FIN-003, FIN-005, FIN-006, FIN-007, FIN-008, FIN-009, FIN-010, FIN-011, FIN-013, FIN-014, FIN-015, FIN-016, FIN-021, FIN-101, FIN-102, FIN-103, FIN-104, FIN-105, FIN-106, FIN-107, FIN-108, OPS-002, OPS-007, ORC-004, ORC-005, ORC-006, ORC-101, ORC-103, ORC-104, ORC-105. R1*: FIN-004, FIN-012, FIN-017, FIN-018, FIN-019, FIN-020.
- **D · Product API, UX & workloads** (27 R1 tasks, 847–1,192 h): API-001, API-002, API-003, API-004, API-005, API-101, API-102, API-104, CTL-007, REL-103, UX-001, UX-002, UX-003, UX-004, UX-005, UX-006, UX-008, UX-102, UX-103, UX-104, WRK-001, WRK-002, WRK-004, WRK-005, WRK-101, WRK-102, WRK-104. R1*: UX-007, WRK-003.
- **E · Allocation, governance & reporting** (28 R1 tasks, 934–1,343 h): ALC-001, ALC-002, ALC-003, ALC-004, ALC-005, ALC-006, ALC-007, ALC-008, ALC-101, ALC-102, ALC-103, ALC-104, GOV-001, GOV-002, GOV-003, GOV-004, GOV-005, GOV-006, GOV-007, GOV-008, GOV-101, GOV-102, GOV-103, RPT-001, RPT-002, RPT-003, RPT-004, RPT-005.
- **F · Optimization (insights)** (8 R1 tasks, 274–406 h): INS-001, INS-002, INS-003, INS-004, INS-006, INS-007, INS-101, INS-105.
- **G · Qualification, release, onboarding & launch** (28 R1 tasks, 817–1,255 h): LCH-001, LCH-002, LCH-003, LCH-004, LCH-102, LCH-103, LCH-104, ONB-001, ONB-002, ONB-003, ONB-004, ONB-005, ONB-101, ONB-102, OPS-003, OPS-004, OPS-005, OPS-008, OPS-009, OPS-010, OPS-011, OPS-107, OPS-109, OPS-110, REL-001, REL-002, REL-003, REL-004.

## (d) Calendar scenarios (arithmetic, not a promise)

Capacity bound = R1 hours ÷ (engineers × 120 h). Chain bound = critical-path hours ÷ 120 h (one engineer per task). List-scheduled = a greedy simulation that always starts the ready task with the longest remaining chain, with interchangeable engineers.

| Engineers | Capacity bound (months) | Chain bound (months) | Lower bound = max | List-scheduled makespan (months) | Engineer utilization |
|---:|---:|---:|---:|---:|---:|
| 2 | 28.2–41.6 | 11.3–16.7 | 28.2–41.6 | 28.4–41.8 | 0.99 |
| **3** | **18.8–27.7** | 11.3–16.7 | **18.8–27.7** | **19.2–28.4** | 0.98 |
| 4 | 14.1–20.8 | 11.3–16.7 | 14.1–20.8 | 14.8–21.9 | — |
| **5** | **11.3–16.6** | **11.3–16.7** | **11.3–16.7** | **12.1–17.9** | 0.93 |
| 6 | 9.4–13.9 | 11.3–16.7 | 11.3–16.7 | 11.5–17.0 | — |
| **8** | 7.1–10.4 | **11.3–16.7** | **11.3–16.7** | **11.4–16.7** | 0.62 |
| 10 | 5.6–8.3 | 11.3–16.7 | 11.3–16.7 | 11.3–16.7 | — |

Adding all R1\* work (247–366 h): 3 engineers 19.7–28.9 months; 5 engineers 12.1–17.9; 8 engineers 11.4–16.7 (unchanged).

Reading the table:
- **Three engineers** are capacity-bound: about 1.6–2.4 years of engineering before first payment.
- **Five engineers** is the knee: capacity and chain bounds coincide (≈ 11–17 months), and utilization stays above 90 %.
- **Eight engineers** do not beat five by much (11.4–16.7 vs 12.1–17.9 months) because the chain binds; the extra capacity only helps if chain tasks are split or paired (levers in §(a)) or if part of R2 is pulled forward.
- These figures assume interchangeable engineers. With one Snowflake/dbt specialist and one security specialist, lanes C and A2 serialize further (R-07). A planning allowance for integration and rework (assumption: +15 %) would give ≈ 14–21 months at five engineers.

Elapsed time that is **not** in these hours and adds to the calendar:
- Owner decisions D-01, D-17, D-19, D-20, D-25, D-30, D-32 before P0 exits (D-32 gates the test estate).
- Snowflake test-estate organization creation and commercial approval (INF-101 "plus calendar lead time"); INF-101 has only 149–229 h of slack and CON-002 50–77 h.
- SES production access (days), pentest vendor booking (OPS-107 has 39–58 h of slack; book at M6), counsel/accountant turnaround for LCH-102/LCH-103 (LCH-102 slack 55–80 h).
- Customer side: procurement and DPA, installation by the customer's ACCOUNTADMIN (CON-003), network allowlisting (D-09), backfill 1–4 days (ONB-004), FV-1 needs a MONTH_STABLE month (month end + 5 days, D-13) — up to ≈ 5 weeks of waiting — and payment terms before LCH-002 evidence exists.

## (e) Top 10 schedule risks

| # | Risk | Evidence in the graph | Mitigation |
|---|---|---|---|
| R-01 | **Serial spine through the data platform.** 22 chain tasks (791–1,157 h) must finish in order before any serving task is DONE; FIN-009 (70–100 h), FIN-003 (50–75 h) and SEC-004 (52–80 h) are the largest. | Chain tasks 1–22 in §(a). | Split FIN-009; pair on spine tasks; keep DBT-101, FIN-001, FIN-106, API-001, UX-001 contract work at P0 (they already have 171–590 h of slack at low estimates). |
| R-02 | **Owner decisions not yet taken.** D-20 moves 247–366 h of R1\* in or out; D-32 gates the test estate and therefore every live gate; D-17/D-30 gate LCH-001/LCH-103. | DECISIONS_REQUIRED "owner input" rows. | Decide at P0 exit; default to the recommended options (the backlog is written against them). |
| R-03 | **Live vendor verification on the spine.** WIF ARN/path matching (CON-002, INF-103), secondary-role/session-policy behaviour (SEC-005), long-query visibility and QAH latency (ING-101), revisioned-materialization and CAS publish (DBT-101, ORC-005), VPC Lattice for the broker (INF-005-S11), CloudFront VPC origins (INF-006). A failure reopens a DONE task. | TO VERIFY LIVE items in SEC/CON/ING/DBT/ORC/INF backlogs. | Run the verification micro-steps first inside each task; DBT-101's benchmark (≤ 200 credits) before any revisioned model. |
| R-04 | **Test-estate lead time.** INF-101 (organizations, accounts, generators) gates CON-002/003/005 and ING-101…104. | INF-101 slack 149–229 h; CON-002 slack 50–77 h. | Request the Snowflake organizations at P0 (D-32); provisional install per INF-101-S10. |
| R-05 | **Live-gate edges.** API-101 → API-002 costs 207–306 h of chain; UX-002 → API-104 and UX-003 → API-101 tie UX to certified serving views. | What-if in §(a). | Keep the edges but build against contracts (OpenAPI + MSW, DuckDB fixtures) so only certification waits. |
| R-06 | **Couplings not modelled as edges, and unreconciled backlog text.** about 18 step-level dependencies (e.g. DBT-004-S08…S11 → ORC-005, API-005-S05 → ALC-005/FIN-010, GOV-004-S15 → GOV-002, UX-102-S05 → OPS-005), plus about 90 backlog steps that RECONCILIATION removes or re-owns. | RECONCILIATION §0 and §5. | Track at micro-step level; update the backlog texts before sprint planning so no one builds a duplicate. |
| R-07 | **Specialist concentration.** Lane C (dbt/finance, 1,209–1,761 h) and lane A2 (security/control plane, 833–1,287 h) hold 13 of the 41 chain tasks; the calendar assumes interchangeable engineers. | §(c) lane table. | Two data engineers from M3; a security engineer dedicated to A2 through M5. |
| R-08 | **Estimate spread and first-contact rework.** High/low ≈ 1.47 on the chain (1,360 vs 2,003 h); 29 BLOCKER findings were design gaps; real Account Usage data (long queries, reseller billing, grants, network policies) typically forces rework in ING/FIN. | AUDIT §7; ONB and FIN findings. | Tenant zero at P2 (FIN-108 on the INF-101 org), design partner at P3 (RELEASE_PLAN §4). |
| R-09 | **Customer and calendar elapsed time.** Procurement, DPA, script runs, allowlisting, backfill, month close for FV-1 and payment terms. | §(d) list; ONB-003/004/005, LCH-002. | Start legal pack (LCH-102) and customer pre-work during P3; plan onboarding so the first closed month ends soon after go-live. |
| R-10 | **Release-tail serialization and gate loops.** OPS-011 → REL-004 → LCH-003 → ONB-003 → ONB-004 → ONB-005 → LCH-002 is 140–222 h strictly serial; pentest findings (OPS-107), restore drills (OPS-006/007) or isolation failures (OPS-004) loop back into lanes A2/C. | Chain tasks 35–41. | Dark production from M5 (REL-104), isolation suite from M1 (SEC-008), restore drills at M2/M5 (OPS re-milestoning), pentest booked at M6. |

# Release plan: R1 production slice, parallel lanes and estimates

This plan replaces the big-bang path to the first paying customer ([AUDIT X-05](AUDIT_CROSS_CUTTING.md)) with a production-grade **R1** slice and an **R2** breadth release, delivered through parallel lanes. It keeps every architectural non-negotiable. It assumes the recommended options in [DECISIONS_REQUIRED.md](DECISIONS_REQUIRED.md); D-01, D-19 and D-20 must be confirmed by the owner.

## 1. Principles

1. **Production quality is not negotiable in R1**: tenant isolation at API/PostgreSQL/Snowflake, WIF only, immutable journal with manifest acceptance, exact signed ledger with financial coverage of every billed service, reconciliation and close, recovery drills, audit, on-call and runbooks.
2. **Breadth is negotiable**: detail pages, detector families, report templates, notification channels and federation protocols ship when the first customer needs them.
3. **Money coverage is never deferred**: a service without a detailed adapter still appears as its billing-bucket charge (D-12) or `UNMAPPED_BILLABLE_SERVICE` (FIN-021). R2 adds explanation, not money.
4. **Real data early**: synthetic fixtures cannot reproduce Account Usage diversity. Introduce real data long before M11 (see §4).
5. **Contract before code**: the artifacts in [CONTRACT_FIRST_ARTIFACTS.md](CONTRACT_FIRST_ARTIFACTS.md) are authored and reviewed at the start of each lane.

## 2. R1 / R2 scope by domain

`R1*` = in R1 only if the first-customer profile (D-20) requires it; otherwise R2. Financial coverage for R1* services is still R1 through billing buckets and FIN-021.

| Domain | R1 | R1* (conditional) | R2 |
|---|---|---|---|
| FND | all | | |
| INF | all | | PrivateLink ingress path (D-09) |
| SEC | SEC-001, 002, 004, 005, 006, 007, 008 | SEC-003 (SAML/OIDC for the customer's IdP) | additional IdP protocols |
| CTL | all (saved views; commercial records are owned by LCH-001/LCH-101 per RECONCILIATION U-08) | | CTL-103 merged into UX-101 (R2 dashboards) |
| CON | all | | PrivateLink-only accounts |
| ING | ING-001…011; ING-012 Data Health UX | | ING-012 hot path (D-24) |
| ORC | all | | |
| DBT | all | | |
| FIN | 001, 002, 003, 005, 006, 007, 008 (transfer), 009, 010, 011, 013, 014, 015, 016, 021, 101–108 | 004 Adaptive, 012 Streaming, 017 QAS, 018 Cortex, 019 SPCS, 020 Marketplace, 008 replication | FX display conversion |
| API | 001–005 | 006 (only if the customer integrates via API) | 006 public API credentials, SDK |
| UX | 001–006, 008 | 007 (AI/Cortex, SPCS pages) | FR localization (D-18) |
| WRK | 001, 002 (dbt), 004 (tasks/procedures), 005 comparison | 003 (Power BI) | 005 on-demand operator evidence |
| ALC | all | | regex rule operators (D-16) |
| GOV | 001, 003, 004, 006 (Email, Slack, Webhook), 007, 008; 002 run-rate + seasonal-naive; 005 MAD anomaly | 006 Teams | 002 Theil–Sen selection + calibrated intervals |
| INS | 001, 006, 007, 101, 102, 105; detectors WH01 (+WH04), WH02, Q01, Q02, Q03, Q07, ST03, ST04 | | 005 AI/SPCS detectors, INS-103/104/106 remaining detectors |
| RPT | 001, 002, 004, 005; 003 with Executive FinOps, CFO Monthly, Team Showback, Chargeback Statement (PDF + CSV, secure links) | | RPT-101 other 4 templates + PNG, RPT-102 external recipients/attachments, RPT-103 dashboards |
| OPS | all, re-milestoned earlier (see backlog/OPS.md) | | multi-region DR |
| REL, ONB, LCH | all | | self-service payment provider |

This table summarizes. The authoritative per-task release tags and hours are in [revised-task-graph.json](revised-task-graph.json) (after the reconciliation rulings) and in each [backlog](backlog/) file. Notable integration rulings: TASK_HISTORY and dynamic-table refresh history are R1 (needed by WRK-004); the R1 insight detectors are WH01 (with WH04 folded in), WH02, Q01, Q02, Q03, Q07, ST03 and ST04; the R1 report templates are Executive FinOps, CFO Monthly, Team Showback and Chargeback Statement.

## 3. Parallel lanes

Eight lanes, from [REVISED_CRITICAL_PATH.md §(c)](REVISED_CRITICAL_PATH.md), which lists every task per lane:

| Lane | Scope | R1 tasks | R1 hours | Notes |
|---|---|---:|---:|---|
| A1 | Platform, infrastructure & ops foundations (FND, INF, early OPS/REL) | 31 | 783–1,147 | Front-loaded; first 5 chain tasks |
| A2 | Identity, security & control plane (SEC, CTL, LCH-101 entitlements) | 21 | 833–1,287 | Front-loaded; next 5 chain tasks |
| B | Data acquisition (CON, ING, extraction orchestration) | 34 | 1,082–1,583 | Capacity bottleneck at M3–M6 |
| C | Analytical kernel (dbt, publication, ledger) | 41 | 1,209–1,761 | Largest lane; 8 chain tasks; needs a second engineer at peak |
| D | Product API, UX & workloads | 27 | 847–1,192 | UX-001 starts day 1 against contracts |
| E | Allocation, governance & reporting | 28 | 934–1,343 | Starts after FIN-001 contracts; engines after FIN-009 |
| F | Optimization (insights) | 8 | 274–406 | Small and late; staff from C or E |
| G | Qualification, release, onboarding & launch | 28 | 817–1,255 | Legal/commercial pack from P0 (owner-driven); qualification at the end |

Corrected dependency edges enabling these lanes: [RECONCILIATION.md §3](RECONCILIATION.md) and the "Dependency changes" line of each task in the backlog files.

## 4. "Tenant zero" and a design partner

- **Tenant zero (dogfooding).** Connect Bridge's own DEV/STAGING central Snowflake accounts (and the Bridge Snowflake organization's billing views) as the first tenant through the normal WIF onboarding path as soon as CON-005 and ING-007 work. This yields real Account Usage/Organization Usage data, real latency, real billing revisions and a real invoice to reconcile — at no customer risk.
- **Design partner.** Recruit one friendly customer under a pilot agreement to connect read-only once ING/FIN reach staging quality (lane C mid-point). Real-data surprises (grants, reseller billing, network policies, long queries, volumes) are the dominant schedule risk and must surface months before M11. The pilot agreement covers consent, data processing and the fact that R1 gates are not yet passed.

## 5. Estimates

Senior-engineer hours including tests, review fixes and evidence (D-19), low–high, after de-duplication of overlapping tasks ([RECONCILIATION.md](RECONCILIATION.md)). Source: [revised-task-graph.json](revised-task-graph.json). The table counts tasks by their release tag. Including the conditional replication part of FIN-008 (8–12 h), R1\* is **247–366 h**; including the R2 parts of otherwise-R1 tasks, R2 is **663–1,036 h** ([RECONCILIATION.md](RECONCILIATION.md) §4). GOV-006's Teams adapter (≈ 6–9 h) is inside R1 and only needed if the customer uses Teams.

| Domain | R1 (tasks · h) | R1\* (tasks · h) | R2 (tasks · h) | Backlog |
|---|---:|---:|---:|---|
| FND | 9 · 189–280 | — | — | [FND](backlog/FND.md) |
| INF | 13 · 379–542 | — | 1 · 16–26 | [INF](backlog/INF.md) |
| SEC | 12 · 504–786 | 1 · 56–84 | 1 · 40–64 | [SEC](backlog/SEC.md) |
| CTL | 9 · 332–505 | — | — | [CTL](backlog/CTL.md) |
| CON | 8 · 284–418 | — | 1 · 40–80 | [CON](backlog/CON.md) |
| ING | 18 · 608–885 | — | 2 · 110–185 | [ING](backlog/ING.md) |
| ORC | 11 · 304–435 | — | — | [ORC](backlog/ORC.md) |
| DBT | 9 · 260–374 | — | 1 · 10–14 | [DBT](backlog/DBT.md) |
| FIN | 23 · 665–975 | 6 · 131–196 | 1 · 24–36 | [FIN](backlog/FIN.md) |
| API | 8 · 262–371 | — | 1 · 32–46 | [API](backlog/API.md) |
| UX | 10 · 330–459 | 1 · 28–40 | 1 · 30–44 | [UX](backlog/UX.md) |
| WRK | 7 · 198–276 | 1 · 24–34 | 2 · 46–66 | [WRK](backlog/WRK.md) |
| ALC | 12 · 410–584 | — | — | [ALC](backlog/ALC.md) |
| GOV | 11 · 345–490 | — | 2 · 40–57 | [GOV](backlog/GOV.md) |
| INS | 9 · 297–440 | — | 4 · 158–237 | [INS](backlog/INS.md) |
| RPT | 5 · 179–269 | — | 3 · 79–119 | [RPT](backlog/RPT.md) |
| OPS | 21 · 690–1,047 | — | 1 · 22–36 | [OPS](backlog/OPS.md) |
| REL | 8 · 186–283 | — | — | [REL](backlog/REL.md) |
| ONB | 7 · 195–302 | — | — | [ONB](backlog/ONB.md) |
| LCH | 8 · 162–253 | — | — | [LCH](backlog/LCH.md) |
| **Total** | **218 · 6,779–9,974** | **9 · 239–354** | **21 · 647–1,010** | |

Critical path and staffing ([REVISED_CRITICAL_PATH.md](REVISED_CRITICAL_PATH.md)): the longest R1 chain is 42 tasks and 1,360–2,003 hours (11.3–16.7 months for the engineer carrying it). Arithmetic calendar at 120 productive hours per engineer-month: 3 engineers ≈ 19–28 months (capacity-bound), 5 engineers ≈ 12–18 months (balanced), 8 engineers ≈ 11–17 months (chain-bound, 62 % utilization). Owner decisions, vendor lead times and customer elapsed time come on top. The main levers are scope (D-01/D-20), splitting the heaviest chain tasks (FIN-009, ALC-003, SEC-004, FIN-003, ALC-005, API-002, ING-007) and a second engineer on lanes B and C at their peak.

## 6. Proposed phase gates (replacing M0–M12 ordering, keeping their exit evidence)

| Phase | Exit evidence (subset of the original milestone gates) | Original milestones covered |
|---|---|---|
| P0 Contracts & foundations | Decisions D-01…D-34 recorded; contract-first artifacts reviewed; monorepo, locked runtime matrix (dbt-snowflake ≥ 1.12), CI, AWS accounts/state/guards, cost model v1 | M0, part of M1 |
| P1 Secure control plane & connectivity | Cognito/BFF, RBAC, PG FORCE RLS, tenant WIF serving identity + profile roles, audit/outbox/leases, account WIF with install/revoke scripts, capability probes, telemetry + alert routing + PG backup | M1, M2 |
| P2 Durable ingestion | Account-cycle extraction, Parquet/manifest commit, Snowpipe + receipts, accepted batches, contiguous coverage, backfill/catch-up, replay, Data Health; tenant zero connected | M3 |
| P3 Financial kernel & serving | Billing-bucket ledger, service families required by D-20, reconciliation controls incl. invoice intake, close/restatement, insert-only publication, serving views with row policies, semantic API; design partner connected | M4, part of M5 |
| P4 Product & ownership | Home, Explorer, warehouse/query, storage/serverless, dbt/tasks workloads, Explain, tags/rules/simulation/publication, groups, allocation, showback, chargeback | M5, M6 |
| P5 Governance, reporting, optimization | Budgets, forecasts (R1 methods), monitors with corrected confirmation semantics, notifications, R1 report templates, R1 detectors, actions and verified savings | M7, M8 (R1 subset) |
| P6 Qualification & launch | Isolation attack suite, SLO/alerting, restore drills (PG + analytical snapshot), capacity at R1 targets, unit economics, release rehearsal, legal/commercial pack, onboarding, first value, payment evidence | M9–M12 |

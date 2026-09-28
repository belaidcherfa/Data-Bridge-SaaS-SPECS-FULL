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
| CTL | all (saved views, commercial records) | | custom dashboard builder depth |
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
| INS | 001, 006, 007; detector subset from 002/003/004 (see backlog/INS.md) | 005 AI/SPCS detectors | remaining detectors |
| RPT | 001, 002, 004, 005; 003 with Executive FinOps, Team Showback, Chargeback Statement (+ CFO Monthly if requested) | | remaining templates |
| OPS | all, re-milestoned earlier (see backlog/OPS.md) | | multi-region DR |
| REL, ONB, LCH | all | | self-service payment provider |

The exact per-task R1/R2 tags and hours are in each [backlog](backlog/) file; section 5 consolidates them.

## 3. Parallel lanes

| Lane | Domains | Starts | Hard prerequisites from other lanes |
|---|---|---|---|
| A · Platform & security | FND, INF, SEC, CTL, OPS (telemetry, alerting, backup) | Day 1 | — |
| B · Data acquisition | CON, ING, ORC | After FND-002 matrix, INF-001…003, SEC-004 | A: identities, buckets, KMS, PG schema |
| C · Financial kernel | DBT, FIN (contracts and fixtures from day 1; SQL after RAW exists) | Contracts: day 1 · SQL: after ING-007 | B: accepted RAW; A: central Snowflake |
| D · Product API & UX | API, UX, WRK | UX-001 day 1; API-001 registry contract after FIN-001 | C: serving views; A: broker identities |
| E · Allocation & governance | ALC, GOV, RPT | Contracts after FIN-001; engines after FIN-009 | C, D |
| F · Optimization | INS | After GOV-005 statistics and core FIN | C, D, E |
| G · Qualification & launch | OPS qualification, REL, ONB, LCH | Legal/commercial pack from day 1 (owner-driven); qualification after lanes converge | all |

Corrected dependency edges enabling these lanes are listed per task under "Dependency changes" in the backlog files.

## 4. "Tenant zero" and a design partner

- **Tenant zero (dogfooding).** Connect Bridge's own DEV/STAGING central Snowflake accounts (and the Bridge Snowflake organization's billing views) as the first tenant through the normal WIF onboarding path as soon as CON-005 and ING-007 work. This yields real Account Usage/Organization Usage data, real latency, real billing revisions and a real invoice to reconcile — at no customer risk.
- **Design partner.** Recruit one friendly customer under a pilot agreement to connect read-only once ING/FIN reach staging quality (lane C mid-point). Real-data surprises (grants, reseller billing, network policies, long queries, volumes) are the dominant schedule risk and must surface months before M11. The pilot agreement covers consent, data processing and the fact that R1 gates are not yet passed.

## 5. Estimates

Consolidated from the per-domain backlog files (senior-engineer hours including tests, review fixes and evidence; low–high). Filled in after the domain audits; see the table below.

<!-- ESTIMATES_TABLE -->

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

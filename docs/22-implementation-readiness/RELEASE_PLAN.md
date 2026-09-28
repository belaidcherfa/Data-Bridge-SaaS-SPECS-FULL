# Release plan: R1 production slice, parallel lanes and estimates

This plan replaces the big-bang path to the first paying customer ([AUDIT X-05](AUDIT_CROSS_CUTTING.md)) with a production-grade **R1** slice and an **R2** breadth release, delivered through parallel lanes. It keeps every architectural non-negotiable. It assumes the recommended options in [DECISIONS_REQUIRED.md](DECISIONS_REQUIRED.md); D-01, D-19 and D-20 must be confirmed by the owner.

## 1. Principles

1. **Production quality is not negotiable in R1**: tenant isolation at API/PostgreSQL/Snowflake, WIF only, immutable journal with manifest acceptance, exact signed ledger with financial coverage of every billed service, reconciliation and close, recovery drills, audit, on-call and runbooks.
2. **Breadth is negotiable**: detail pages, detector families, report templates, notification channels and federation protocols ship when the first customer needs them.
3. **Money coverage is never deferred**: a service without a detailed adapter still appears as its billing-bucket charge (D-12) or `UNMAPPED_BILLABLE_SERVICE` (FIN-021). R2 adds explanation, not money.
4. **Real data early**: synthetic fixtures cannot reproduce Account Usage diversity. Introduce real data long before M11 (see §4).
5. **Contract before code**: the artifacts in [CONTRACT_FIRST_ARTIFACTS.md](CONTRACT_FIRST_ARTIFACTS.md) are authored and reviewed at the start of each lane.

## 2. R1 / R2 scope by domain

**Updated after the owner's decisions (2026-09-28).** D-20 puts every Snowflake edition, organization form, contract type, workload and service family in R1, so the former conditional R1\* tasks are R1. Snowflake trial accounts are demonstration-only (D-35). Insight detector and report-template breadth still follow D-01.

| Domain | R1 | R2 |
|---|---|---|
| FND | all | |
| INF | all | INF-106 egress inspection / PrivateLink ingress (D-09) |
| SEC | all, including SEC-003 SAML + OIDC (Entra ID, Okta, Google) | SEC-106 resource-level scopes, SCIM |
| CTL | all (saved views; commercial records owned by LCH-001/LCH-101 per RECONCILIATION U-08) | CTL-103 merged into UX-101 (dashboards) |
| CON | all, including trial-account detection (D-35) | CON-103 PrivateLink-only accounts |
| ING | ING-001…012 (Data Health UX), ING-101…107, ING-105 service-family activation | ING-112 hot path (D-24); remaining ING-105 extension families |
| ORC | all | |
| DBT | all | DBT-104 schema-breaking cutover |
| FIN | all service families: 001–021 (incl. 004 Adaptive, 012 Streaming, 017 QAS, 018 Cortex/AI, 019 SPCS, 020 Marketplace, 008 transfer + replication), 101–108 | FIN-109 FX display conversion |
| API | 001–005, 101, 102, 104 | API-006 public API credentials, SDK |
| UX | 001–008 (incl. 007 AI/Cortex and SPCS pages), 102–104 | UX-101 dashboards; FR localization (D-18) |
| WRK | 001–005 (incl. 003 Power BI), 101, 102, 104 | WRK-103 operator evidence, WRK-105 native/custom apps |
| ALC | all | regex rule operators (D-16) |
| GOV | 001–008 (Email, Slack, Teams, Webhook), 101–103; 002 run-rate + seasonal-naive; 005 MAD anomaly | GOV-104 fiscal calendars, GOV-105 Theil–Sen selection + calibrated intervals |
| INS | 001, 006, 007, 101, 102, 105; detectors WH01 (+WH04), WH02, Q01, Q02, Q03, Q07, ST03, ST04 | INS-005 AI/SPCS detectors, INS-103/104/106 remaining detectors |
| RPT | 001–005 with Executive FinOps, CFO Monthly, Team Showback, Chargeback Statement (PDF + CSV, secure links) | RPT-101 other 4 templates + PNG, RPT-102 external recipients/attachments, RPT-103 dashboards |
| OPS | all, re-milestoned earlier (see backlog/OPS.md) | OPS-111 multi-region DR |
| REL, ONB | all | |
| LCH | all, including LCH-105 managed-spend metering (D-17) | automated billing / payment provider (D-30) |

The authoritative per-task release tags and hours are in [revised-task-graph.json](revised-task-graph.json) and in each [backlog](backlog/) file.

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

Senior-engineer-equivalent hours including tests, review fixes and evidence, low–high, after de-duplication ([RECONCILIATION.md](RECONCILIATION.md)) and after the owner's decisions of 2026-09-28. Source: [revised-task-graph.json](revised-task-graph.json). R2 also includes 37–63 h of R2 parts inside otherwise-R1 tasks (API-102, ING-105 and others itemized in the backlog files), for **614–948 h** in total.

| Domain | R1 (tasks · h) | R2 (tasks · h) | Backlog |
|---|---:|---:|---|
| FND | 9 · 194–287 | — | [FND](backlog/FND.md) |
| INF | 13 · 379–542 | 1 · 16–26 | [INF](backlog/INF.md) |
| SEC | 13 · 567–881 | 1 · 40–64 | [SEC](backlog/SEC.md) |
| CTL | 9 · 332–505 | — | [CTL](backlog/CTL.md) |
| CON | 8 · 287–422 | 1 · 40–80 | [CON](backlog/CON.md) |
| ING | 19 · 657–973 | 1 · 40–60 | [ING](backlog/ING.md) |
| ORC | 11 · 304–435 | — | [ORC](backlog/ORC.md) |
| DBT | 9 · 261–375 | 1 · 10–14 | [DBT](backlog/DBT.md) |
| FIN | 29 · 808–1,189 | 1 · 24–36 | [FIN](backlog/FIN.md) |
| API | 8 · 262–371 | 1 · 32–46 | [API](backlog/API.md) |
| UX | 11 · 358–499 | 1 · 30–44 | [UX](backlog/UX.md) |
| WRK | 8 · 222–310 | 2 · 46–66 | [WRK](backlog/WRK.md) |
| ALC | 12 · 410–584 | — | [ALC](backlog/ALC.md) |
| GOV | 11 · 345–490 | 2 · 40–57 | [GOV](backlog/GOV.md) |
| INS | 9 · 297–440 | 4 · 158–237 | [INS](backlog/INS.md) |
| RPT | 5 · 179–269 | 3 · 79–119 | [RPT](backlog/RPT.md) |
| OPS | 21 · 692–1,050 | 1 · 22–36 | [OPS](backlog/OPS.md) |
| REL | 8 · 186–283 | — | [REL](backlog/REL.md) |
| ONB | 7 · 198–306 | — | [ONB](backlog/ONB.md) |
| LCH | 9 · 178–277 | — | [LCH](backlog/LCH.md) |
| **Total** | **229 · 7,116–10,488** | **20 · 577–885** | |

Critical path ([REVISED_CRITICAL_PATH.md](REVISED_CRITICAL_PATH.md), recomputed 2026-09-28): 42 tasks, 1,362–2,006 hours; the first payment (LCH-002) now requires every R1 task except the post-launch review (LCH-004), because D-20 makes all service families part of the paid release.

**Calendar with coding agents (D-19).** Hours measure effort, not agent wall-clock time. With coding agents and 1–2 human reviewers, the binding constraints become: (1) the dependency chain — the 42 chain tasks must complete in order, each through review and, where required, a human-run live gate; (2) review capacity — plan 2–3 concurrent agent lanes per reviewer (4–6 lanes with two reviewers); (3) external lead times (Snowflake estate setup, SES production access, penetration test booking, customer installation, backfill and month close). For comparison with a human team at 120 productive hours per engineer-month: 3 engineers ≈ 20–29 months, 5 ≈ 12–18 months, 8 ≈ 11.5–17 months.

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

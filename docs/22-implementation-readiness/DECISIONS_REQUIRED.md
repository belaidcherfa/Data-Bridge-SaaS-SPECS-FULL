# Decisions required before implementation

Each decision below must be recorded (accepted as recommended, or replaced) before the tasks it blocks start. Decisions that change an accepted ADR are recorded as an ADR amendment or a superseding ADR, per the repository's ADR process. The [revised backlog](backlog/) is written against the **recommended** option and tags dependent micro-steps with the decision ID, so accepting a recommendation requires no backlog rewrite.

Legend — **Type**: ARCH (architecture), FIN (financial semantics), PRODUCT, BUSINESS. **Owner input**: the recommendation cannot be made by engineering alone.

## Summary

| ID | Decision | Type | Recommendation | Must be decided before |
|---|---|---|---|---|
| D-01 | Release slicing | PRODUCT | R1 thin-but-complete production slice; R2 breadth | Planning (now) |
| D-02 | Serving authorization identity model | ARCH (amends ADR-005) | Tenant WIF user + per-profile Snowflake role | SEC-005 |
| D-03 | Snowpipe usage mode | ARCH | Auto-ingest steady state; orchestrated COPY for replay | ING-006 |
| D-04 | Config publication transport | ARCH (amends ADR-007) | Direct idempotent insert by config-publisher identity | CTL-005 |
| D-05 | Analytical write model | ARCH | Insert-only revisioned partitions + publication map | DBT-001 |
| D-06 | dbt run granularity | ARCH | Multi-tenant set-based runs, per-tenant publication gating | DBT-001, ORC-004 |
| D-07 | Extraction execution model | ARCH | One ECS task per account-cycle | ORC-002, ING-003 |
| D-08 | Customer-side extraction footprint | PRODUCT/ARCH | Dedicated XS warehouse, resource monitor, query tag, disclosed cost | CON-003 |
| D-09 | Network reachability | ARCH | Fixed egress IPs + optional network policy; PrivateLink R2 | INF-002, CON-003 |
| D-10 | Personal data in the immutable journal | ARCH/LEGAL | Per-tenant HMAC pseudonyms + deletable identity dictionary | SEC-007, ING-003 |
| D-11 | Query-level retention tiering | PRODUCT | 90 days query grain; 400 days family×day aggregates | ING-001, DBT-003 |
| D-12 | Canonical charge grain | FIN | Billing-bucket grain; estimates at same grain | FIN-001 |
| D-13 | FINAL maturity horizons | FIN | Numeric per-source defaults in registry | ING-001, FIN-001 |
| D-14 | Temporal attribution of long queries | FIN | Prorate by execution overlap with metering hours | FIN-003 |
| D-15 | Default allocation per charge family | FIN/PRODUCT | Seeded editable default book | ALC-005 |
| D-16 | Rule evaluation engine | ARCH | Data-driven predicate tables, set-based SQL | ALC-002 |
| D-17 | Commercial plan model | BUSINESS · owner input | Plan-agnostic quota entitlements; price model TBD | LCH-001 (design CTL-007) |
| D-18 | Localization | PRODUCT · owner input | EN R1 with externalized strings; FR R2 | UX-001 |
| D-19 | Delivery capacity | BUSINESS · owner input | — (needed to turn hours into a schedule) | Planning (now) |
| D-20 | First-customer profile | BUSINESS · owner input | — (drives R1 FIN/WRK/INS detail scope) | FIN-001 scoping |
| D-21 | Central Snowflake authentication | ARCH | WIF everywhere, dbt-snowflake ≥ 1.12 | FND-002 |
| D-22 | Query broker placement | ARCH | Separate internal service | API-002 |
| D-23 | Data residency | BUSINESS/ARCH | Single EU stack R1; regional stacks later | INF-001 |
| D-24 | Hot path (PRD §37) | PRODUCT | Defer to R2 | ING-012 |
| D-25 | Compliance posture | BUSINESS · owner input | SOC 2-ready controls in R1; certification timing TBD | SEC-008, OPS-005 |

## Details

### D-01 · Release slicing

- **Context.** First revenue currently requires 147/151 tasks through a 73-task serial chain ([AUDIT X-05](AUDIT_CROSS_CUTTING.md)). "Production, not POC" is about quality bars (security, correctness, recoverability, operability), not about shipping every feature at once.
- **Options.** (a) Keep big bang. (b) R1 = production-grade thin-but-complete slice for the first paying customer, R2 = breadth. (c) Private beta without payment first.
- **Recommendation.** (b). R1 keeps every non-negotiable (isolation, WIF, immutable ingestion, exact ledger with **financial coverage of every billed service**, reconciliation, close, allocation/showback/chargeback, budgets, monitors, reports, recovery, onboarding, commercial activation) but narrows breadth: core sources, the detail families the first customer actually uses (D-20), a subset of insight detectors, three to four report templates, Email + Slack + Webhook (Teams if required by the customer), local MFA + one federation protocol if required. The full R1/R2 split is in [RELEASE_PLAN.md](RELEASE_PLAN.md).
- **Consequence.** Milestones M8 (insights breadth) and parts of M5/M7 move to R2; the first-customer path shortens materially.

### D-02 · Serving authorization identity model (amends ADR-005)

- **Context.** ADR-005 binds each normalized permission profile to its own WIF principal. With AWS WIF that means a Snowflake user and an IAM role per profile, created at runtime ([X-10](AUDIT_CROSS_CUTTING.md)).
- **Options.** (a) ADR-005 as written. (b) Tenant-level WIF user + Snowflake role per profile. (c) Signed-context trusted broker with a single service user (ADR-005 already lists this as a revisit option).
- **Recommendation.** (b). Tenant isolation remains identity-enforced (distinct user and IAM role per tenant); intra-tenant scope is role-enforced by row access policies; no IAM mutation on scope changes; pools keyed (tenant user, profile role, epoch). Verify live whether one AWS ARN may back several Snowflake users (not required by (b)).
- **Blocks.** SEC-005, SEC-006, API-002, OPS-004.

### D-03 · Snowpipe usage mode

- **Context.** The PRD mandates Snowpipe. Auto-ingest is event-driven and serverless; acceptance must then poll load history. Replay after load-metadata expiry needs new keys.
- **Options.** (a) Auto-ingest only. (b) Auto-ingest for steady state, orchestrated `COPY INTO … FILES=(…)` over a WIF SQL session for replay/repair. (c) Orchestrated COPY only (would need a PRD amendment).
- **Recommendation.** (b). Keeps PRD compliance and cheap serverless loads, while replay becomes deterministic.
- **Blocks.** ING-006, ING-007, ING-011.

### D-04 · Configuration publication transport (amends ADR-007)

- **Context.** Kilobyte-sized config versions currently travel outbox → S3 → Snowpipe → Snowflake ([X-17](AUDIT_CROSS_CUTTING.md)).
- **Recommendation.** Keep the transactional outbox and immutable versions; replace the transport with a direct insert-only write by a dedicated `config-publisher` WIF identity keyed by `config_version` (duplicates are no-ops), plus an S3 archival copy for recovery. Draft simulations use `simulation_input`, never published config tables.
- **Blocks.** CTL-005, ALC-003.

### D-05 · Analytical write model

- **Context.** MERGE-in-place and pointer-selected revisions are both mentioned; neither is physically specified ([X-11](AUDIT_CROSS_CUTTING.md)).
- **Recommendation.** Insert-only revisioned partitions `(tenant_id, dataset, partition_key, revision_id)` for ledger, attribution, allocation and serving; per-tenant publication map; serving secure views select the published revision; clustering on `(tenant_id, partition_date)`; garbage collection of superseded revisions once no statement/report/job pins them and retention allows. MERGE only for staging deduplication.
- **Blocks.** DBT-001, DBT-004, DBT-006, ORC-005, OPS-007.

### D-06 · dbt run granularity

- **Recommendation.** One multi-tenant, set-based dbt run per cadence over a processing ledger of accepted-but-unprocessed batches; per-tenant failure isolation happens at publication (a tenant whose checks fail keeps its previous pointer). Per-tenant runs are reserved for targeted replay/repair.
- **Consequence.** Central compute cost per tenant must be allocated by rows/bytes processed, not by query tag ([backlog/OPS.md](backlog/OPS.md)).
- **Blocks.** DBT-001, DBT-004, ORC-004.

### D-07 · Extraction execution model

- **Context.** ~216,000 runs/day at the benchmark profile if each (account, source, window) is a run ([X-12](AUDIT_CROSS_CUTTING.md)).
- **Recommendation.** One ECS task per account-cycle (all due sources, one warehouse resume) using that account's task role; Dagster schedules/sensors enqueue durable work items in PostgreSQL; Dagster run and event-log retention purge.
- **Blocks.** ORC-002, ORC-003, ING-003, ING-010.

### D-08 · Customer-side extraction footprint

- **Context.** Extraction consumes customer credits (≈ 1.6 credits/day/account at a 15-minute cadence before runtime) and pollutes the customer's own cost data ([X-13](AUDIT_CROSS_CUTTING.md)).
- **Recommendation.** Install script creates `BRIDGE_FINOPS_WH` (XSMALL, `AUTO_SUSPEND=60`, resource monitor with a customer-chosen monthly quota); `QUERY_TAG='bridge_finops:<component>'`; "Bridge overhead" workload classification; estimated monthly credits shown before consent; hourly batched default cadence.
- **Blocks.** CON-003, CON-006, ING-003, WRK-001.

### D-09 · Network reachability

- **Recommendation.** Publish fixed NAT Elastic IPs per environment; the install script optionally creates a user-level network policy; detect network-policy denials as a distinct probe outcome; PrivateLink-only accounts are an R2 capability with an explicit R1 blocker message.
- **Blocks.** INF-002, CON-003, CON-005.

### D-10 · Personal data in the immutable journal

- **Context.** Immutable Parquet and Time Travel cannot honour erasure by tombstones alone ([X-15](AUDIT_CROSS_CUTTING.md)).
- **Recommendation.** Pseudonymize user identifiers at extraction with a per-tenant HMAC key (Secrets Manager/KMS-protected); maintain a per-tenant identity dictionary (pseudonym → display name) as a small, separately journaled, deletable dataset; UI resolves names only for authorized profiles; erasure = dictionary deletion + documented Snowflake Time Travel/Fail-safe residual window. Legal review confirms sufficiency.
- **Blocks.** SEC-007, ING-003, OPS-005.

### D-11 · Query-level retention tiering

- **Recommendation.** Query-grain facts hot for 90 days (plan-configurable); query-family × day aggregates keyed by `QUERY_PARAMETERIZED_HASH` for 400 days. UI states which tier a view reads.
- **Owner check.** Confirm that 90-day query-level drilldown is commercially acceptable.
- **Blocks.** ING-001, DBT-003, WRK-005, UX-005.

### D-12 · Canonical charge grain

- **Recommendation.** `fct_charge` key = (tenant, organization, scope_kind, account nullable only for organization scope, usage_date UTC, service_type, rating_type, billing_type, balance_source if it affects monetary meaning, currency, is_adjustment, source_revision). Estimates are aggregated to exactly this key before publication so the authoritative bucket replaces them 1:1. Resource/hour/query money lives only in attribution bridges.
- **Blocks.** FIN-001 and every FIN service task.

### D-13 · FINAL maturity horizons

- **Recommendation.** Per-source numeric defaults stored in the source registry and versioned; initial values from documented latency plus margin (e.g. hourly metering FINAL at hour end + 24 h, QAH + 24 h, METERING_DAILY + 24 h, USAGE_IN_CURRENCY_DAILY + 72 h, month billing-stable at month end + 5 days, configurable). Later corrections still create revisions. Measured lateness revises the defaults (ADR-003 revisit condition).
- **Blocks.** ING-001, FIN-001, GOV-004.

### D-14 · Temporal attribution of long queries

- **Recommendation.** Prorate each query's attributed credits over metering hours by execution-window overlap; expose per-hour residual (WMH attributed − Σ prorated QAH) as an explicit unattributed component.
- **Blocks.** FIN-003, FIN-004.

### D-15 · Default allocation per charge family

- **Recommendation.** Seed an editable default book at onboarding: warehouse compute by query cost; idle proportional to consumers; cloud services proportional to gross cloud-services credits; storage by database owner; serverless by owning object; transfer, replication and organization fees to a platform/shared bucket; anything else unallocated.
- **Blocks.** ALC-005, ONB-004.

### D-16 · Rule evaluation engine

- **Recommendation.** Rules compile to rows in versioned predicate tables (dimension, operator, value, priority, rule_version); a generic set-based SQL model evaluates them for all tenants; R1 operators: `eq`, `in`, `prefix`, `suffix`, `contains`, `is_null`; regex in R2 after cost testing; no per-tenant code generation.
- **Blocks.** ALC-002, ALC-003.

### D-17 · Commercial plan model — owner input

- **Question.** How is Bridge priced: per connected Snowflake account, by band of managed Snowflake spend, per seat, flat platform fee, or a combination? What billing currency and cadence?
- **Engineering default.** Entitlements are plan-agnostic quotas: connected accounts, users, history days, report schedules, API clients, query-level retention days.
- **Blocks.** LCH-001, CTL-007 (commercial records), OPS-009 margin targets.

### D-18 · Localization — owner input

- **Question.** Is French (or another language) required for the first customer?
- **Recommendation.** English UI in R1 with all strings externalized and locale-aware number/date/currency formatting from UX-001; French in R2 unless the first customer requires it.
- **Blocks.** UX-001, RPT-001, GOV-007 (notification templates).

### D-19 · Delivery capacity — owner input

- **Question.** Who implements: how many engineers, which specialties (Snowflake/data, backend, frontend, SRE, security), and whether coding agents execute tasks under human review?
- **Why.** The backlog totals are in engineer-hours; the calendar and number of parallel lanes depend on this.

### D-20 · First-customer profile — owner input

- **Questions.** Snowflake edition(s); number of accounts; clouds/regions; organization account or ORGADMIN; reseller or direct contract; currency; use of Cortex, SPCS, Adaptive warehouses, marketplace, Snowpipe Streaming, replication; dbt / Power BI usage; identity provider (Entra ID, Okta, other); network policies/PrivateLink; data residency constraints.
- **Why.** Determines which FIN/WRK/INS detail tasks are R1 and which onboarding blockers must be solved first.

### D-21 · Central Snowflake authentication

- **Recommendation.** WIF for every central service including dbt Core, pinning dbt-snowflake ≥ 1.12.0 (WIF support merged 2026-05-20, [dbt-adapters#1316](https://github.com/dbt-labs/dbt-adapters/pull/1316)). No RSA or PAT fallback. Live proof remains in CON-002.
- **Blocks.** FND-002, CON-002, DBT-001.

### D-22 · Query broker placement

- **Recommendation.** Separate internal service with its own task role — the only component allowed to assume tenant serving identities — reached by the API over private, authenticated transport with a server-signed query plan.
- **Blocks.** API-002, INF-005.

### D-23 · Data residency

- **Recommendation.** R1: single EU deployment, processing region shown during onboarding. Later regions are separate stacks from the same code and Terraform modules; no cross-region tenant data movement.
- **Blocks.** INF-001, LCH-001 (contract wording).

### D-24 · Hot path

- **Recommendation.** Defer INFORMATION_SCHEMA "hot" extraction to R2; R1 shows PROVISIONAL Account Usage data with explicit "source current through" and "published at" timestamps.
- **Blocks.** ING-012 scope.

### D-25 · Compliance posture — owner input

- **Question.** Is SOC 2 Type I/II (or ISO 27001) expected by the first customers, and when?
- **Recommendation.** Build SOC 2-ready controls in R1 regardless (audit trail, access reviews, change management evidence, backup/restore evidence, vendor list, incident process); certification timing is a business decision.
- **Blocks.** SEC-008, OPS-005, OPS-010, REL-003.

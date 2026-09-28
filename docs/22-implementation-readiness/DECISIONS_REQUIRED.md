# Decision record

**Status: all 38 decisions RECORDED on 2026-09-28** by the product owner (answers collected in the review session; engineering recommendations accepted where the owner delegated). This file started as the list of decisions required before implementation; it is now the accepted decision record. Decisions that change an accepted ADR are carried by ADR amendments and new ADRs (ADR-014 to ADR-016) in [docs/architecture/adr](../architecture/adr/README.md).

Legend — **Type**: ARCH (architecture), FIN (financial semantics), PRODUCT, BUSINESS. **Basis**: OWNER = answered explicitly by the owner; OWNER·REC = owner accepted the engineering recommendation; DELEGATED = owner delegated technical choices to engineering ("take the best production-grade decisions"), recommendation applied.

## Summary

| ID | Decision | Type | Recorded decision | Basis | Blocks |
|---|---|---|---|---|---|
| D-01 | Release slicing | PRODUCT | R1 production-grade slice for the first paying customer; R2 breadth | OWNER·REC | Planning |
| D-02 | Serving authorization identity model | ARCH | Tenant WIF user + per-profile Snowflake role; `CURRENT_ROLE()`-only row policies; secondary roles disabled (amends ADR-005) | OWNER·REC | SEC-005 |
| D-03 | Snowpipe usage mode | ARCH | Auto-ingest steady state; orchestrated `COPY INTO … FILES=` for replay/repair | OWNER·REC | ING-006 |
| D-04 | Config publication transport | ARCH | Direct insert-only write by a config-publisher identity + S3 archive (amends ADR-007) | OWNER·REC | CTL-005 |
| D-05 | Analytical write model | ARCH | Insert-only revisioned partitions + SCD2 publication map (ADR-014) | OWNER·REC | DBT-001 |
| D-06 | dbt run granularity | ARCH | Multi-tenant set-based runs; per-tenant publication gating (ADR-014) | OWNER·REC | DBT-001, ORC-004 |
| D-07 | Extraction execution model | ARCH | One ECS task per account-cycle, started by a dedicated launcher; no Dagster run per cycle (amends ADR-008) | OWNER·REC | ORC-002, ING-003 |
| D-08 | Customer-side extraction footprint | PRODUCT/ARCH | Dedicated XS warehouse + OPERATE, resource monitor, query tag, "Bridge overhead" label, cost shown before consent | OWNER·REC | CON-003 |
| D-09 | Network reachability | ARCH | Fixed egress IPs + optional network policy in R1; PrivateLink in R2 | OWNER·REC | INF-002, CON-003 |
| D-10 | Personal data in the immutable journal | ARCH/LEGAL | Per-tenant HMAC pseudonyms; PG identity dictionary; tombstone log; per-tenant KMS key (amends ADR-009) | OWNER·REC | SEC-007, ING-003 |
| D-11 | Query-level retention | PRODUCT | **365 days of query-level detail** (owner choice, replaces the 90-day recommendation); family × day aggregates with sketches for 400 days; execution-level facts 400 days | OWNER | ING-001, DBT-003 |
| D-12 | Canonical charge grain | FIN | Billing-bucket identity; family-bucket supersession of estimates; `int_alloc_unit` layer (ADR-015) | DELEGATED | FIN-001 |
| D-13 | FINAL maturity horizons | FIN | Numeric per-source horizons (+24 h metering, +72 h QAH and daily billing, MONTH_STABLE at month end + 5 days) (ADR-015) | OWNER·REC | ING-001, FIN-001 |
| D-14 | Temporal attribution of long queries | FIN | Prorate by execution overlap with metering hours; explicit hourly residual (ADR-015) | DELEGATED | FIN-003 |
| D-15 | Default allocation per charge family | FIN/PRODUCT | Seeded editable default book (query cost, proportional idle, cloud-services driver, storage by database owner, fees to platform) | DELEGATED | ALC-005 |
| D-16 | Rule evaluation engine | ARCH | Data-driven predicate tables, set-based SQL; R1 operators eq/in/prefix/suffix/contains/is_null; regex R2 | DELEGATED | ALC-002 |
| D-17 | Commercial plan model | BUSINESS | **Platform fee + band of managed Snowflake spend, priced in USD; no free trial — contracted pilot instead** | OWNER | LCH-001, LCH-101 |
| D-18 | Localization | PRODUCT | English in R1 with externalized strings and locale formatting; French in R2 | OWNER·REC | UX-001 |
| D-19 | Delivery capacity | BUSINESS | **Coding agents execute the backlog; 1–2 human reviewers** approve PRs and run live gates | OWNER | Planning |
| D-20 | Customer coverage | BUSINESS | **All Snowflake editions, organization forms and contract types; all workloads and services in R1** (every former R1\* task becomes R1) | OWNER | FIN, WRK, UX, SEC scope |
| D-21 | Central Snowflake authentication | ARCH | WIF everywhere, dbt-snowflake ≥ 1.12; only a transient human bootstrap credential at account creation (amends ADR-010) | OWNER·REC | FND-002 |
| D-22 | Query broker placement | ARCH | Separate internal service, SigV4-authenticated, epoch recheck and query cancellation (amends ADR-005) | OWNER·REC | API-002 |
| D-23 | Data residency | BUSINESS/ARCH | Single EU deployment in R1; other regions later as separate stacks (ADR-016) | OWNER·REC | INF-001 |
| D-24 | Hot path (PRD §37) | PRODUCT | Deferred to R2 | OWNER·REC | ING-012 |
| D-25 | Compliance posture | BUSINESS | SOC 2-ready controls in R1; certification later | OWNER·REC | SEC-008, OPS-108 |
| D-26 | Journal/RAW retention | ARCH | 400 days for billing/metering/storage sources; 90 days for query-grain sources (amends ADR-009) | OWNER·REC | ING-005, DBT-004 |
| D-27 | Default monitor maturity | PRODUCT | Alert on PROVISIONAL by default with maturity shown; FINAL opt-in | OWNER·REC | GOV-003 |
| D-28 | Frontend hosting and edge | ARCH | SPA on S3 + CloudFront OAC; API through CloudFront VPC origin to an internal ALB | OWNER·REC | INF-005, INF-006 |
| D-29 | Backfill vs steady state | ARCH | Steady-state sync first; fair background backfill; no separate catch-up phase | OWNER·REC | ING-010 |
| D-30 | Customer invoicing channel | BUSINESS | **Not a priority: manual invoices or a Stripe payment link for now**; automation later under its own ADR; Bridge stores references and payment evidence only | OWNER | LCH-001 |
| D-31 | Availability objectives | PRODUCT | Control plane 99.9 %; analytics 99.5 % | OWNER·REC | OPS-003 |
| D-32 | Non-production spend budget | BUSINESS | Approved: test estate ≤ 150 credits/month within a 500 credits/month non-prod ceiling; one-off benchmarks ≤ 600 credits | OWNER·REC | INF-101, INF-105, OPS-008 |
| D-33 | Interactive, export and report jobs | ARCH | Long-lived workers claiming PG jobs via the broker; no Dagster report lane; simulations stay Dagster dbt jobs | OWNER·REC | API-004, RPT-002 |
| D-34 | Workload classification engine | ARCH | Set-based dbt SQL classifier; Python reference as test oracle | OWNER·REC | WRK-001 |
| D-35 | Snowflake trial accounts | PRODUCT | **Accepted for demonstrations only**: excluded from paid scope, financial gates and reconciliation claims | OWNER | CON-005, ONB-001 |
| D-36 | Invoicing entity | BUSINESS | **French entity**: French VAT and e-invoicing rules apply to whichever tool issues invoices | OWNER | LCH-102 |
| D-37 | Support model at launch | BUSINESS | EU business hours (Mon–Fri 09:00–18:00 CET), SEV1 best effort outside hours; no contractual 24×7 | OWNER·REC | OPS-010, LCH-104 |
| D-38 | Onboarding mode | PRODUCT | Complete self-service wizard + a Bridge-led first-value workshop for the first customer | OWNER·REC | ONB-001, ONB-005 |

## Consequences of the owner's choices

- **D-20 (everything in R1).** FIN-004 (Adaptive), FIN-012 (Streaming), FIN-017 (QAS), FIN-018 (Cortex/AI), FIN-019 (SPCS), FIN-020 (Marketplace/native apps), FIN-008 replication, UX-007 (AI/SPCS pages), WRK-003 (Power BI) and SEC-003 (SAML/OIDC SSO) move from R1\* to R1: +247–366 h. Capability degradation for Standard edition (no ACCESS_HISTORY, no native tags), reseller contracts (approved rate tables, FIN-105) and standalone accounts (no organization views) remains mandatory. Insight detector breadth stays per D-01 (8 detectors in R1).
- **D-11 (365-day query detail).** The COLD extraction tier disappears inside the 365-day Account Usage window: every backfilled day carries sanitized query text. Consequences: ≈ 4× central query-grain storage and dbt volume versus 90 days; more sanitizer CPU and customer warehouse time during backfill (CON-101 estimate updated); `hot_days` stays a plan-configurable parameter (default 365, maximum bounded by Account Usage retention); simulation windows default to 90 days for cost but may extend to 365. Query-grain journal retention stays 90 days (D-26): query facts older than 90 days are rebuilt by re-extraction, which Account Usage allows up to 365 days.
- **D-17 (fee + spend band, USD, no free trial).** A new task LCH-105 meters each tenant's managed Snowflake spend from MONTH_STABLE ledger totals and assigns the band. Bands are defined per spend currency in the plan catalog (no FX dependency, FIN-109 FX stays R2). The subscription state `TRIAL` becomes `PILOT` (a contracted pilot, possibly discounted), never an unpaid self-service trial.
- **D-19 (coding agents + 1–2 reviewers).** Hours remain the effort measure; the practical bottleneck becomes human review, live-gate execution with real credentials and external lead times. Run at most ~2–3 concurrent agent lanes per reviewer; every PR carries its task's evidence manifest; live gates (WIF, Snowflake policies, restore drills, payment) are executed or witnessed by a human.
- **D-30 / D-36.** Manual invoices or Stripe payment links are acceptable for the first customer; the chosen invoicing tool must satisfy French e-invoicing and VAT obligations (confirm with an accountant). Bridge records invoice and payment references (ADR-012) and never card data.

## Details

### D-01 · Release slicing

- **Context.** First revenue currently requires 147/151 tasks through a 73-task serial chain ([AUDIT X-05](AUDIT_CROSS_CUTTING.md)). "Production, not POC" is about quality bars (security, correctness, recoverability, operability), not about shipping every feature at once.
- **Options.** (a) Keep big bang. (b) R1 = production-grade thin-but-complete slice for the first paying customer, R2 = breadth. (c) Private beta without payment first.
- **Recommendation.** (b). R1 keeps every non-negotiable (isolation, WIF, immutable ingestion, exact ledger with **financial coverage of every billed service**, reconciliation, close, allocation/showback/chargeback, budgets, monitors, reports, recovery, onboarding, commercial activation) but narrows breadth: core sources, the detail families the first customer actually uses (D-20), a subset of insight detectors, three to four report templates, Email + Slack + Webhook (Teams if required by the customer), local MFA + one federation protocol if required. The full R1/R2 split is in [RELEASE_PLAN.md](RELEASE_PLAN.md).
- **Consequence.** Milestones M8 (insights breadth) and parts of M5/M7 move to R2; the first-customer path shortens materially.

### D-02 · Serving authorization identity model (amends ADR-005)

- **Context.** ADR-005 binds each normalized permission profile to its own WIF principal. With AWS WIF that means a Snowflake user and an IAM role per profile, created at runtime ([X-10](AUDIT_CROSS_CUTTING.md)).
- **Options.** (a) ADR-005 as written. (b) Tenant-level WIF user + Snowflake role per profile. (c) Signed-context trusted broker with a single service user (ADR-005 already lists this as a revisit option).
- **Recommendation.** (b). Tenant isolation remains identity-enforced (distinct user and IAM role per tenant); intra-tenant scope is role-enforced by row access policies; no IAM mutation on scope changes. Verify live whether one AWS ARN may back several Snowflake users (not required by (b)).
- **Refinements from the SEC/INF audits.** Row access policies test `CURRENT_ROLE()` only — **not** `IS_ROLE_IN_SESSION()`, which with secondary roles would widen a restricted profile to every profile of the tenant. Tenant users are created with `DEFAULT_SECONDARY_ROLES = ()` plus a session policy blocking secondary roles, because new users default to `('ALL')` since behavior-change bundle 2024_08 (VERIFIED, see [backlog/SEC.md](backlog/SEC.md) G-SEC-01). Profiles are content-addressed and immutable, so pools are keyed (tenant user, profile role) and the permission epoch belongs in cursors, jobs, cache keys and download links, not in pool keys. The broker reaches the tenant user through the Python connector's `workload_identity_impersonation_path` (VERIFIED); dbt-snowflake has no such parameter, so each dbt task role must itself be the WIF identity. Separation between profiles of the same tenant ultimately rests on the broker — no weaker than ADR-005 as written. Full amendment text and DDL: [backlog/SEC.md](backlog/SEC.md) Appendix A.
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
- **Recommendation.** Insert-only revisioned partitions `(tenant_id, dataset, partition_key, revision_id)` for ledger, attribution, allocation and serving; per-tenant publication map; serving secure views select the published revision; clustering on `(tenant_id, partition_date)`; garbage collection of superseded revisions once no statement/report/job pins them and retention allows.
- **Refinements from the ORC/DBT audits.** dbt-snowflake's built-in `insert_overwrite` truncates the whole table and `microbatch` deletes a time slice for all tenants (VERIFIED), so a custom `revisioned` materialization is required (new ADR-014, task DBT-101). Staging becomes read-time deduplication views over accepted RAW (no MERGE at all). Query-grain facts use hour partitions, charges use day partitions. The publication pointer is DML-only (DDL auto-commits — VERIFIED) and advanced by one `PUBLISH_BATCH` compare-and-swap over an SCD2 publication map; readers pin `pub_seq`. See [backlog/ORC.md](backlog/ORC.md) G-ORC-06 and [backlog/DBT.md](backlog/DBT.md) G-DBT-01.
- **Blocks.** DBT-001, DBT-004, DBT-006, ORC-005, OPS-007.

### D-06 · dbt run granularity

- **Recommendation.** One multi-tenant, set-based dbt run per cadence over a processing ledger of accepted-but-unprocessed batches; per-tenant failure isolation happens at publication (a tenant whose checks fail keeps its previous pointer). Per-tenant runs are reserved for targeted replay/repair.
- **Consequence.** Central compute cost per tenant must be allocated by rows/bytes processed, not by query tag ([backlog/OPS.md](backlog/OPS.md)).
- **Blocks.** DBT-001, DBT-004, ORC-004.

### D-07 · Extraction execution model

- **Context.** ~216,000 runs/day at the benchmark profile if each (account, source, window) is a run ([X-12](AUDIT_CROSS_CUTTING.md)).
- **Recommendation.** One ECS task per account-cycle (all due sources, one warehouse resume) using that account's task role; Dagster schedules/sensors enqueue durable work items in PostgreSQL; Dagster run and event-log retention purge.
- **Refinements from the ORC/INF/ING audits.** dagster-aws `EcsRunLauncher` only sets a per-run task role through the user-writable `ecs/task_overrides` run tag, and ECS RunTask overrides cannot be constrained by IAM (both VERIFIED): anyone able to launch a run could choose any passable customer role. Therefore a dedicated extraction launcher (ING-106, not Dagster) resolves `connection_id → role` from PostgreSQL and starts the extractor task; Dagster only enqueues; the Dagster webserver is read-only by default. **There is no Dagster run per account-cycle**: ORC-003 admission marks cycles ADMITTED in PostgreSQL, the launcher claims them and calls `RunTask`, an ECS task-state event completes the cycle, and a Dagster sensor records outcomes as asset observations; only the launcher holds `iam:PassRole` on connection roles ([RECONCILIATION.md](RECONCILIATION.md) C-04). Extractor tasks hold no database credentials and report through an internal `sync-api` authenticated by their AWS role. See G-ORC-03, G-INF-08, G-ING-08/09.
- **Blocks.** ORC-002, ORC-003, ING-003, ING-010.

### D-08 · Customer-side extraction footprint

- **Context.** Extraction consumes customer credits (≈ 1.6 credits/day/account at a 15-minute cadence before runtime) and pollutes the customer's own cost data ([X-13](AUDIT_CROSS_CUTTING.md)).
- **Recommendation.** Install script creates `BRIDGE_FINOPS_WH` (XSMALL, `AUTO_SUSPEND=60`, resource monitor with a customer-chosen monthly quota) and grants `OPERATE` on it so the extractor can suspend it explicitly at the end of each cycle; `QUERY_TAG='bridge_finops:<component>'`; "Bridge overhead" workload classification; estimated monthly credits shown before consent; hourly batched default cadence.
- **Quantified by the CON/OPS audits.** ≈ 12.6–13.2 credits/month per account with explicit suspend vs ≈ 20.6–27.2 with auto-suspend only ([backlog/CON.md](backlog/CON.md) §3.3); ≈ 90–120 credits/month for a 5-account customer overall including backfill amortization ([backlog/ONB.md](backlog/ONB.md)). The hourly cadence changes the freshness SLO: it is measured from manifest commit to publication, and query-history freshness is ~1–2 h, not 15 min ([backlog/OPS.md](backlog/OPS.md)).
- **Blocks.** CON-003, CON-006, ING-003, WRK-001.

### D-09 · Network reachability

- **Recommendation.** Publish fixed NAT Elastic IPs per environment; the install script optionally creates a user-level network policy; detect network-policy denials as a distinct probe outcome; PrivateLink-only accounts are an R2 capability with an explicit R1 blocker message.
- **Blocks.** INF-002, CON-003, CON-005.

### D-10 · Personal data in the immutable journal

- **Context.** Immutable Parquet and Time Travel cannot honour erasure by tombstones alone ([X-15](AUDIT_CROSS_CUTTING.md)).
- **Recommendation.** Pseudonymize user identifiers at extraction with a per-tenant HMAC key (KMS-protected); keep the per-tenant identity dictionary (pseudonym → display name) in PostgreSQL — **not** in an immutable journal — and resolve names in the API only for authorized profiles; erasure = dictionary deletion, plus replay of an append-only deletion tombstone log after any restore (backups would otherwise resurrect names), plus per-tenant KMS key deletion at offboarding; documented Snowflake Time Travel/Fail-safe residual window. Legal review confirms sufficiency. See G-SEC-16, G-OPS-07 (task OPS-104).
- **Blocks.** SEC-007, ING-003, OPS-005.

### D-11 · Query-level retention tiering

- **Owner decision (2026-09-28).** 365 days of query-level detail instead of the recommended 90; aggregates and execution-level facts keep 400 days. See *Consequences* above.

- **Recommendation.** Query-grain facts hot for 90 days (plan-configurable); query-family × day aggregates keyed by `QUERY_PARAMETERIZED_HASH` for 400 days. UI states which tier a view reads.
- **Refinements from the API/WRK/INS audits.** A family × day aggregate is not enough on its own: (1) percentiles and distinct counts cannot be re-derived from daily values (fixture: true p95 = 1 s, average of daily p95s = 50.5 s), so aggregates store mergeable sketch states (t-digest / HLL, Snowflake functions VERIFIED) — G-API-04; (2) savings re-measurement after the 90-day purge needs attributed credits, spill and workload identity in the aggregate — G-INS; (3) workload identity (dbt node, Power BI activity) must be extracted for the full 365-day backfill even where SQL text is dropped, by projecting only the trailing dbt comment for older windows — otherwise a year of dbt identity is lost irreversibly (G-WRK-01/15).
- **Integration ruling ([RECONCILIATION.md](RECONCILIATION.md) C-01), as updated by the owner decision.** Extraction tiers: HOT (sanitized text) for the whole `hot_days` window — 365 days by default, i.e. the full Account Usage window; COLD (trailing comment only, computed in the customer warehouse, parsed and never stored as text) only when a plan sets `hot_days` below 365; NONE. One aggregate `fct_query_family_daily` owned by WRK-104 holds the union of the API sketches, INS savings measures and the D-15 cloud-services driver; execution-level facts (dbt invocations, Power BI activities, task-graph runs, dynamic-table refreshes) are 400-day facts. Allocation simulations default to 90 days for cost and may extend to the hot tier (365 days).
- **Owner check — answered 2026-09-28.** The owner chose 365 days of query-level detail.
- **Blocks.** ING-001, DBT-003, WRK-005, UX-005.

### D-12 · Canonical charge grain

- **Recommendation.** `fct_charge` identity = (tenant, organization, scope_kind, account nullable only for organization scope, usage_date UTC, service_type, rating_type, billing_type, balance_source where it changes monetary meaning, currency, is_adjustment); versions are `revision_id` under D-05, not part of the identity. Resource/hour/query money lives only in attribution bridges, produced by one exact allocator with explicit residual rows.
- **Correction from the FIN audit (G-FIN-01).** Estimates cannot know rating/billing type, capacity vs overage or adjustments in advance (estimate 200 → billed 160 + 50 would show 410 under key-based replacement). Replacement is therefore **family-bucket supersession**: estimates exist at (tenant, org, scope, account, usage_date, service_family, currency); an accepted authoritative row deactivates the estimate for its family bucket, and a mature daily billing snapshot deactivates all estimates for that account-day; metered usage with no billing after maturity stays visible as `BILLING_MISSING` and fails control C2. Allocation additionally needs an `int_alloc_unit` layer that splits each charge into query/idle/residual/resource units summing exactly to the charge (G-ALC-01).
- **Blocks.** FIN-001 and every FIN service task.

### D-13 · FINAL maturity horizons

- **Recommendation.** Per-source numeric defaults stored in the source registry and versioned; initial values from documented latency plus margin (hourly metering FINAL at hour end + 24 h; METERING_DAILY + 24 h; USAGE_IN_CURRENCY_DAILY + 72 h). Later corrections still create revisions. Measured lateness revises the defaults (ADR-003 revisit condition).
- **Corrections from the FIN audit (G-FIN-08).** Query attribution cannot be FINAL at + 24 h: a query can run for the maximum statement timeout (48 h default), so QAH is FINAL at hour end + statement timeout + 24 h (72 h by default). Daily FINAL and month stability are distinct states: a day can be FINAL at + 72 h while the month still changes; a separate `MONTH_STABLE` state is reached at month end + 5 days (configurable) and gates close.
- **Blocks.** ING-001, FIN-001, GOV-004.

### D-14 · Temporal attribution of long queries

- **Recommendation.** Prorate each query's attributed credits over metering hours by execution-window overlap; expose per-hour residual (WMH attributed − Σ prorated QAH) as an explicit unattributed component.
- **Blocks.** FIN-003, FIN-004.

### D-15 · Default allocation per charge family

- **Recommendation.** Seed an editable default book at onboarding: warehouse compute by query cost; idle proportional to consumers; cloud services proportional to gross cloud-services credits; storage by database owner; serverless by owning object; transfer, replication and organization fees to a platform/shared bucket; anything else unallocated.
- **Prerequisite found by the ALC audit (G-ALC-11).** The cloud-services driver requires `CREDITS_USED_CLOUD_SERVICES` (and database/schema) in the QUERY_HISTORY projection, which the source catalog does not extract today; ING-101 freezes them (with the 16 INS columns, database/schema identity and a new AU.SESSIONS contract) before the first backfill ([RECONCILIATION.md](RECONCILIATION.md) C-10). Until available, the fallback is a labelled query-cost share.
- **Blocks.** ALC-005, ONB-004.

### D-16 · Rule evaluation engine

- **Recommendation.** Rules compile to rows in versioned predicate tables (dimension, operator, value, priority, rule_version); a generic set-based SQL model evaluates them for all tenants; R1 operators: `eq`, `in`, `prefix`, `suffix`, `contains`, `is_null`; regex in R2 after cost testing; no per-tenant code generation.
- **Blocks.** ALC-002, ALC-003.

### D-17 · Commercial plan model — owner input

- **Owner decision (2026-09-28).** Platform fee + band of managed Snowflake spend, priced in USD. No free trial: prospects enter a contracted pilot. New task LCH-105 (spend-band metering).

- **Question.** How is Bridge priced: per connected Snowflake account, by band of managed Snowflake spend, per seat, flat platform fee, or a combination? What billing currency and cadence?
- **Engineering default.** Entitlements are plan-agnostic quotas: connected accounts, users, history days, report schedules, API clients, query-level retention days.
- **Blocks.** LCH-001, CTL-007 (commercial records), OPS-009 margin targets.

### D-18 · Localization — owner input

- **Question.** Is French (or another language) required for the first customer?
- **Recommendation.** English UI in R1 with all strings externalized and locale-aware number/date/currency formatting from UX-001; French in R2 unless the first customer requires it.
- **Blocks.** UX-001, RPT-001, GOV-007 (notification templates).

### D-19 · Delivery capacity — owner input

- **Owner decision (2026-09-28).** Coding agents implement the backlog under 1–2 human reviewers.

- **Question.** Who implements: how many engineers, which specialties (Snowflake/data, backend, frontend, SRE, security), and whether coding agents execute tasks under human review?
- **Why.** The backlog totals are in engineer-hours; the calendar and number of parallel lanes depend on this.

### D-20 · First-customer profile — owner input

- **Owner decision (2026-09-28).** Support all Snowflake editions (Standard, Enterprise, Business Critical, VPS where reachable), organization accounts, ORGADMIN-enabled accounts, multi-account organizations and standalone accounts, direct capacity, on-demand and reseller contracts, and every workload and service family in R1. Snowflake trial accounts: demonstration only (D-35).

- **Questions.** Snowflake edition(s); number of accounts; clouds/regions; organization account or ORGADMIN; reseller or direct contract; currency; use of Cortex, SPCS, Adaptive warehouses, marketplace, Snowpipe Streaming, replication; dbt / Power BI usage; identity provider (Entra ID, Okta, other); network policies/PrivateLink; data residency constraints.
- **Why.** Determines which FIN/WRK/INS detail tasks are R1 and which onboarding blockers must be solved first.

### D-21 · Central Snowflake authentication

- **Recommendation.** WIF for every central service including dbt Core, pinning dbt-snowflake ≥ 1.12.0 (WIF support merged 2026-05-20, [dbt-adapters#1316](https://github.com/dbt-labs/dbt-adapters/pull/1316)). No RSA or PAT fallback. Live proof remains in CON-002.
- **Blocks.** FND-002, CON-002, DBT-001.

### D-22 · Query broker placement

- **Recommendation.** Separate internal service with its own task role — the only component allowed to assume tenant serving identities — reached by the API over private, authenticated transport (SigV4 through VPC Lattice preferred over mTLS to avoid a private CA — TO VERIFY LIVE) with a server-signed query plan; the broker rechecks the permission epoch and cancels running queries on revocation.
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

### D-26 · Journal and RAW retention for financial sources (amends ADR-009)

- **Context.** ADR-009 sets S3 journal and RAW retention to 90 days while canonical facts live 400 days. The DBT and ING audits show that any rebuild of a financial partition older than 90 days (bug fix, new service mapping, restatement) then requires re-extraction from the customer — impossible beyond Account Usage retention and costly on the customer's warehouse.
- **Recommendation.** Retain journal and RAW for billing/metering/storage sources 400 days (small volumes); keep 90 days for query-grain sources (large volumes, D-11). Privacy is unaffected by D-10 pseudonymization.

### D-27 · Default monitor maturity

- **Recommendation.** Monitors evaluate PROVISIONAL data by default and state the maturity in every alert; `minimum_data_status: FINAL` is an explicit opt-in, because FINAL delays alerts by 2–5 days under D-13 (G-GOV).

### D-28 · Frontend hosting and edge (refines PRD §5)

- **Recommendation.** Serve the React SPA from S3 through CloudFront with Origin Access Control instead of a Fargate `frontend` service; reach the API through a CloudFront VPC origin to an internal ALB (VERIFIED capability) instead of a public ALB protected by a secret header. Fewer moving parts, no public ALB. See G-INF.

### D-29 · Backfill vs steady-state ordering (refines PRD §40)

- **Recommendation.** Start steady-state synchronization immediately after capability validation and run the historical backfill in a fair background lane; coverage merges contiguously, so no separate "catch-up T0 → now" phase is needed and fresh data appears on day 1. See G-ING.

### D-30 · Customer invoicing channel — owner input

- **Owner decision (2026-09-28).** Not a priority now: manual invoices or a Stripe payment link; automated billing later with its own ADR. The invoicing entity is French (D-36).

- **Context.** If the invoicing entity is French, the e-invoicing reform has applied since 2026-09-01 (VERIFIED by the LCH audit; obligations depend on company size and must be confirmed with an accountant).
- **Recommendation.** Do not generate invoices in the product. Issue them from an accounting tool connected to an approved e-invoicing platform; Bridge stores invoice/payment references and verified payment evidence only (consistent with ADR-012).

### D-31 · Availability objectives

- **Recommendation.** Control plane (login, settings, workflows) 99.9 % monthly; analytical reads 99.5 %, because they cannot exceed Snowflake's own service commitment. Low-traffic periods are measured with synthetic probes. See G-OPS-02…04.

### D-32 · Non-production spend budget — owner input

- **Question.** Approve (a) one Snowflake test estate — two test organizations, several accounts, workload generators, canaries and tenant zero — capped at 150 credits/month ([backlog/INF.md](backlog/INF.md) INF-101); (b) an overall non-production ceiling of 500 credits/month covering the estate, central DEV/STAGING builds, dbt CI and developer sandboxes (INF-105); (c) one-off benchmarks of ≤ 200 (DBT-101), ≤ 100 (OPS-105) and ≤ 300 (OPS-008) credits. Without them, every "live" gate in the plan is untestable ([RECONCILIATION.md](RECONCILIATION.md) C-24).

### D-33 · Analysis-job execution (refines semantic-api.md)

- **Context.** "An outbox schedules Dagster" for heavy interactive analyses puts Dagster run latency and the D-07 run-volume concerns into a user-facing path.
- **Recommendation.** Long-lived worker services (analysis-worker, render worker) claim interactive analysis, export and report snapshot/render jobs from PostgreSQL with fenced leases, execute reads only through the query broker, write results and reauthorize on read; there is no Dagster `report` lane. Dagster stays a batch orchestrator: allocation simulations are dbt builds under the transform identity, so they run as Dagster dbt jobs (concurrency 1 per tenant) while an API job record gives the user status and cancellation. See G-API ([backlog/API.md](backlog/API.md)) and [RECONCILIATION.md](RECONCILIATION.md) C-05.

### D-34 · Workload classification engine (refines PRD §53–§54)

- **Context.** The PRD lists workload classification as a Python algorithm. The classifier's rules (query tags, dbt comments, client application, precedence, confidence) are deterministic and must run over up to a million queries per account per day.
- **Recommendation.** Implement classification as set-based dbt SQL over parsed metadata columns; keep a Python reference implementation as the test oracle. PRD §2.5's golden rule ("deterministic and efficient in SQL → dbt") supports this. See [backlog/WRK.md](backlog/WRK.md) and [backlog/API.md](backlog/API.md).

### D-35 · Snowflake trial accounts

- **Owner decision (2026-09-28).** A Snowflake trial account may be connected for demonstrations only. The connection carries a `TRIAL_ACCOUNT` capability flag (detected at probe time; exact signals TO VERIFY LIVE), the UI labels all figures as demonstration data, and the account is excluded from paid entitlements, reconciliation claims, close and chargeback.

### D-36 · Invoicing entity

- **Owner decision (2026-09-28).** The entity invoicing customers is French. French VAT rules (EU B2B reverse charge where applicable) and the e-invoicing reform apply to the invoicing tool; accounting-record retention is multi-year. Qualified accounting advice is required before the first invoice.

### D-37 · Support model at launch

- **Decision.** Business-hours support in the EU (Mon–Fri 09:00–18:00 CET), SEV1 best effort outside those hours; no contractual 24×7 commitment until a staffed rota exists (consistent with RUNBOOKS). Published in the support policy (LCH-104) and the runbooks (OPS-010).

### D-38 · Onboarding mode

- **Decision.** The onboarding wizard is fully usable without Bridge staff (PRD §158), and the first customer additionally receives a Bridge-led first-value workshop (ONB-005).


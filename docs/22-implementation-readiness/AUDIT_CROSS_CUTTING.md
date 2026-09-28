# Cross-cutting implementation-readiness audit

Review date: 2026-09-27/28 UTC. Scope: every file in this repository (PRD, 13 ADRs, 20 domain contracts, 151 task files, machine index, UI/UX design set, prototype). Method: full read of the PRD, ADRs and domain contracts by the lead reviewer; quantitative analysis of task files and the dependency graph; nine parallel domain audits whose detailed output lives in [backlog/](backlog/); targeted vendor verification where a design decision depends on it.

Domain-specific findings (`G-<DOM>-nn`) are in the per-domain backlog files. This document holds the findings that span domains (`X-nn`). Decisions referenced as `D-nn` are defined in [DECISIONS_REQUIRED.md](DECISIONS_REQUIRED.md).

## 1. Verdict

**The architecture is sound and should be kept. The specification set is not yet implementable as a production system.**

What is genuinely strong and must be preserved: one additive charge truth separated from attribution (ADR-002); maturity / reconciliation / close as three independent axes (ADR-003); manifest-based batch acceptance with contiguous coverage instead of `MAX(timestamp)` (ADR-006); tenant keys physically everywhere, deny-by-default at API + PostgreSQL RLS + Snowflake row policies; unknown-is-not-zero everywhere; signed adjustments; conservation invariants with exact decimals; honest capability degradation; evidence-driven gates. These are the right instincts and are rarer than they should be in FinOps products.

What prevents a production implementation from starting today:

1. **Task files are ~70 % boilerplate** (X-01). Each of the 151 tasks carries ~150–250 words of task-specific content and three real micro-steps. An engineer or coding agent would have to re-derive the design for almost every task.
2. **The physical designs are missing** (X-06, X-11). There is no DDL, no Snowflake physical model (how revisions, publication pointers, row policies and clustering fit together), no OpenAPI, no event/outbox catalog, no state-machine catalog, no source registry files, no metric registry v1, no capability matrix.
3. **Several architecture choices do not survive a scale or cost check** as written: per-profile Snowflake identities with per-profile IAM roles (X-10), one orchestrator run per account × source × window (X-12), S3/Snowpipe transport for kilobyte-sized configuration (X-17), and unquantified customer-side and central Snowflake costs (X-13, X-26).
4. **Critical logic is under-specified** where money is computed: the grain at which estimates are replaced by billing (X-18), maturity horizons (X-19), long-running query extraction and temporal attribution (X-20), default allocation of cloud services/storage/fees (X-21), monitor confirmation semantics (X-30).
5. **Delivery shape is a big bang**: the first paying customer transitively requires 147 of 151 tasks through a 73-task serial chain (X-05), with unrealistic 2–6 h task estimates (X-04).
6. **Business inputs are absent**: pricing model, first-customer profile, team capacity, localization, legal/e-invoicing obligations (X-40…X-45).

None of these require abandoning the design. They require (a) the 34 decisions in [DECISIONS_REQUIRED.md](DECISIONS_REQUIRED.md), (b) the contract-first artifacts listed in [CONTRACT_FIRST_ARTIFACTS.md](CONTRACT_FIRST_ARTIFACTS.md), (c) the revised micro-task backlog in [backlog/](backlog/), and (d) the release re-slicing in [RELEASE_PLAN.md](RELEASE_PLAN.md).

## 2. Findings about the specification set itself

### X-01 · Task files are mostly identical template text · BLOCKER for agent-driven implementation

Measured over all 151 task files (normalizing task IDs and links):

| Section | Distinct texts across 151 tasks |
|---|---:|
| Inputs, Observability, Acceptance criteria, Definition of Done, Operational runbook, Documentation impact | **1** (identical everywhere) |
| Dependencies footer, Hierarchy metadata | 9 / 26 |
| Security and tenant isolation; Idempotency / retries | 20 (one per domain, not per task) |
| UX behavior | 51 (101 tasks share one paragraph) |
| Objective, Why, Steps, Data model, API, Failure scenarios, Oracle | ~151 (task-specific, but one line each) |

Only **29.4 %** of the text is unique. The task-specific payload (steps + data model + API + failures + oracle) is **751–1283 characters per task, median 896** — roughly one paragraph. Examples:

- `ALC-005` micro-task 1: "Implement direct/fixed/proportional/query-cost/usage/weighted methods with explicit eligible scope and denominator." Six allocation algorithms in one step.
- `SEC-005` data model: `SECURITY.principal_entitlement(principal,tenant,profile,account,group_set,group,epoch,active)` — the entire serving-authorization schema in one line, with no policy body, no provisioning flow and no revocation mechanics.
- `FIN-003` failure list: "long query crosses days" — named as a failure but no rule for how it is attributed.

Resolution: every task is re-decomposed in [backlog/](backlog/) into 8–20 verifiable micro-steps with concrete deliverables and oracles, and task-specific acceptance criteria replace the shared checklist.

### X-02 · "604 micro-tasks" overstates granularity

604 = 151 × 4, and the fourth step of every task is the same "Prove and checkpoint" paragraph. There are 453 real steps, many of which bundle days of work (see X-01). The machine index `micro_task_ids` (`FIN-003.1…4`) should not be used to plan work.

### X-03 · No task-specific exit criteria

The five acceptance checkboxes and the Definition of Done are identical for all tasks ("Every micro-task output exists…", "The deterministic oracle above passes…"). The only task-specific acceptance signal is the one-line oracle. For a production system this makes "done" non-reviewable. Resolution: task acceptance lists in each backlog file.

### X-04 · Effort estimates are not credible

`DELIVERY_METHODOLOGY.md` sizes each task at "typically 2–6 engineering hours". That would put the whole platform at 300–900 hours. Tasks such as SEC-005 (identity-bound Snowflake row policies with provisioning and revocation), ING-007 (complete-batch acceptance), FIN-009 (reconciliation controls and health UX) or ALC-005 (nine allocation methods with conservation) are each multi-day to multi-week efforts. Realistic, bottom-up estimates are in each backlog file and consolidated in [RELEASE_PLAN.md](RELEASE_PLAN.md).

### X-05 · Big-bang delivery: 73-task serial chain, 147/151 tasks before first revenue

Computed from `docs/00-project/task-index.json`:

- Longest dependency chain: **73 tasks**, strictly serial: `FND-001 → … → INF-006 → SEC-002 → SEC-004 → CTL-001 → CON-001…005 → ING-001…008 → ORC-002…004 → DBT-001…005 → FIN-001…004 → FIN-009 → API-001 → WRK-001 → ALC-001…007 → GOV-001…008 → RPT-003…005 → OPS-005/006/010/011 → REL-001…004 → ONB-003…005 → LCH-002…004`.
- `LCH-002` (first payment evidence) transitively requires **147 of 151** tasks. Only `SEC-003` (SAML/OIDC SSO) is not on the path.
- All 41 insight detectors, all 8 report templates, all four notification channels, the public API (API-006) and all AI/SPCS/marketplace detail pages sit on the path to the first invoice.

Many edges encode "needs live evidence of X" where "needs X's contract or code" would suffice and would allow parallel lanes:

| Edge | Why it over-serializes |
|---|---|
| `DBT-001 ← ORC-004` | The dbt project, conventions and fixture tests do not need Dagster. |
| `FIN-001 ← DBT-005` | The charge schema and golden fixtures are contract work that should *precede* DBT-005, not follow it. |
| `API-001 ← FIN-009` | The metric registry format and v1 metric list can be authored from the ledger contract. |
| `SEC-002 ← INF-006` | Local Cognito/BFF development does not need production edge/DNS. |
| `GOV-003 ← API-006` | The monitor DSL does not depend on public API credentials. |
| `GOV-001 ← ALC-007` | Account/service budgets do not need the showback portal; only team budgets need allocation. |
| `GOV-002 ← WRK-005` | Forecasting does not depend on workload comparison or operator evidence. |
| `OPS-001 … OPS-011 mostly at M9` | Telemetry, alert routing, backups and restore drills must exist from M1–M3 (see OPS backlog). |

Resolution: corrected edges per domain in the backlog files; a lane-based plan with an R1 slice in [RELEASE_PLAN.md](RELEASE_PLAN.md) (D-01).

### X-06 · Contract-first artifacts do not exist

Missing before any code can be written consistently by more than one engineer or agent: PostgreSQL DDL per schema; Snowflake physical model (databases/schemas, RAW tables per source, revisioned fact tables, publication map, secure views, row access policies, clustering); OpenAPI 3.1 for the control and analytical APIs; outbox event catalog with JSON Schemas; state-machine catalog (connection, batch attempt, backfill plan, onboarding, rule lifecycle, incident episode, insight, action, statement, subscription); error-code catalog; configuration parameter catalog with defaults; source registry files for each activated source; semantic metric registry v1; RBAC capability matrix. Consolidated list and owners: [CONTRACT_FIRST_ARTIFACTS.md](CONTRACT_FIRST_ARTIFACTS.md).

### X-07 · The coherence audit certifies form, not design soundness

`COHERENCE_AUDIT.md` reports PASS on links, anchors, acyclicity, section presence and "17 independent numerical fixture calculations". Those fixtures recompute the specification's own illustrative numbers; they do not test whether the design handles, for example, long-running queries, billing-bucket replacement or monitor confirmation (all found below). The lead reviewer independently recomputed the published fixtures (F-270 = 270; account scope 268; correction 269; Adaptive 1.00 → 1.05; allocation 120/80 and 84/56/60; budget 150/130/300/7.142857 %; anomaly 4.04694456; workload 20 + 20 = 40; savings 60 and −20; margin 70 %) — **all arithmetically correct**. The gap is coverage of scenarios, not arithmetic.

## 3. Architecture challenges

### X-10 · Per-profile Snowflake identities (ADR-005) are costly and add no security over per-profile roles · HIGH → D-02

ADR-005: "central WIF reader principals per tenant and distinct normalized permission profile". With AWS WIF, each Snowflake SERVICE user is bound to an AWS identity, so every new permission profile implies a new Snowflake user **and** a new IAM role, created synchronously when an administrator changes someone's scope (IAM is eventually consistent; the provisioner needs `iam:CreateRole` and Snowflake `CREATE USER`). IAM role quotas become a scaling limit, and connection pools multiply per profile.

The security benefit is illusory: the query broker must be able to assume *every* profile role, so a compromised broker has the same reach whether profiles are users or roles. What profiles actually protect against is a bug in query construction — and a Snowflake **role per profile** under a **tenant-level** WIF user gives the same protection, with the tenant boundary still enforced by a distinct identity.

Resolution (D-02): one WIF SERVICE user + IAM role per tenant; one Snowflake role per normalized permission profile; row access policies check `CURRENT_ROLE()` only (not `IS_ROLE_IN_SESSION()`, which secondary roles would widen) against tenant/profile entitlements, with secondary roles disabled on tenant users; pools keyed by (tenant user, profile role), the permission epoch living in cursors, jobs, caches and links; role creation is a Snowflake-only DDL through a narrowly privileged provisioner. Whether Snowflake allows several users to share one AWS ARN is **TO VERIFY LIVE**; the proposed design does not need it. Detailed design: [backlog/SEC.md](backlog/SEC.md).

### X-11 · The analytical write/publication model is not physically specified · BLOCKER → D-05, D-06

The ORC contract says a publication manifest "maps tenant, dataset and each partition to a physical revision… Reuse unchanged partitions; do not copy 500M rows", and one Snowflake transaction "advances the tenant publication pointer". DBT contract says "Use a serialized per-tenant/dataset/partition lease for overlapping dbt runs; dedup source before MERGE". These two ideas (MERGE-in-place vs. revision selection through a pointer) are not reconciled, and no one has written how a serving query selects "the published revision" under a row access policy, what the clustering key is, or how superseded revisions are garbage-collected while statements and reports pin them.

Vendor check: current Snowflake documentation states that UPDATE/DELETE/MERGE locks block only concurrent DML on the **same rows**; DML on different rows of the same table can progress — VERIFIED via search of `docs.snowflake.com/en/sql-reference/transactions` (2026-09-27). So per-tenant parallel MERGEs are not inherently serialized. They still rewrite whole micro-partitions shared with other tenants unless the table is clustered by tenant and date (write amplification, Time Travel churn), and they make "select a coherent published version" hard.

Resolution (D-05/D-06): insert-only revisioned partitions for ledger/allocation/serving facts, keyed `(tenant_id, dataset, partition_key, revision_id)`; a per-tenant publication map; serving secure views joining the map; clustering on `(tenant_id, partition_date)`; multi-tenant set-based dbt runs over a processing ledger of accepted-but-unprocessed batches, with per-tenant publication gating. MERGE stays in staging deduplication only. Physical design ADR: [backlog/ORC.md](backlog/ORC.md), [backlog/DBT.md](backlog/DBT.md).

### X-12 · One orchestrator run per account × source × window does not scale · HIGH → D-07

The ORC contract implies materializations per tenant/account/window; ADR-004 wants extraction on Fargate task roles per account. At the benchmark profile (100 tenants × 5 accounts), with ~15 activated sources on hourly cadence and QUERY_HISTORY every 15 minutes: 500 × 15 × 24 + 500 × 72 ≈ **216,000 runs/day**. Each would be a Dagster run with event-log rows and a Fargate task with tens of seconds of provisioning and a one-minute billing floor. Dagster's metadata database and ECS would be the bottleneck long before Snowflake.

A security defect compounds the scale problem: dagster-aws `EcsRunLauncher` sets a per-run task role only through the user-writable `ecs/task_overrides` run tag, and ECS RunTask overrides cannot be constrained by IAM (VERIFIED, G-ORC-03, G-INF-08) — anyone able to launch a run could pick any customer's role.

Resolution (D-07): a dedicated extraction launcher, not Dagster, resolves the role from PostgreSQL; one ECS task per **account-cycle** (all due sources, one customer warehouse resume) with that account's task role → 500 × 24 = 12,000 tasks/day at the benchmark, far fewer for R1; Dagster schedules/sensors enqueue durable work items; a Dagster run/event retention purge policy. Details: [backlog/ORC.md](backlog/ORC.md), [backlog/ING.md](backlog/ING.md).

### X-13 · Bridge's extraction costs the customer money, and nobody specified it · HIGH → D-08

Querying `SNOWFLAKE.ACCOUNT_USAGE` requires a running warehouse **in the customer account**. Snowflake bills per second with a 60-second minimum per resume. Polling QUERY_HISTORY every 15 minutes on a dedicated XSMALL warehouse (1 credit/hour) costs at least 96 × 60 s = 96 minutes/day ≈ **1.6 credits/day ≈ 48 credits/month per account** before any actual query runtime — roughly USD 100–200/month per account at typical USD 2–4/credit list prices. Batched hourly cycles cut the floor substantially; the CON audit's detailed model gives ≈ 12.6–13.2 credits/month per account with an explicit suspend after each cycle (requires `OPERATE` on the warehouse) and ≈ 20.6–27.2 with auto-suspend only ([backlog/CON.md](backlog/CON.md) §3.3). The 365-day backfill of a large account adds a one-off cost. None of this appears in the specs (grep for customer warehouse / extraction warehouse / customer credits: no match), and Bridge's own queries will show up in the customer's QUERY_HISTORY and spend — a FinOps product that silently adds to the bill it reports on.

Resolution (D-08): the installation script creates `BRIDGE_FINOPS_WH` (XSMALL, `AUTO_SUSPEND=60`, resource monitor with a customer-chosen quota); every extractor query sets `QUERY_TAG='bridge_finops:<component>'`; the product classifies these as a "Bridge overhead" workload; the connection wizard shows an estimated monthly credit footprint before consent; default cadence is batched hourly.

### X-14 · Customer network reachability is not designed · HIGH → D-09

Many enterprise Snowflake accounts enforce network policies; some only accept PrivateLink. The specs mention "network policy prerequisites" once but define no egress IPs, no allowlisting instructions and no PrivateLink path (grep for Elastic IP / NAT IP / egress IP: no match). Resolution (D-09): fixed NAT Elastic IPs per environment published in the wizard and the install script (optional user-level network policy); PrivateLink-only accounts are R2 with an explicit, early onboarding-blocker message in R1.

### X-15 · The immutable journal conflicts with erasure of personal data · HIGH → D-10

S3 Parquet objects are immutable by design (ADR-006) and retained 90 days (ADR-009); RAW 90 days; canonical 400 days. They contain Snowflake user names (often corporate e-mail addresses), roles and sanitized SQL. ADR-009 proposes "deletion tombstones" reapplied on restore, but a tombstone does not remove the personal data from the immutable Parquet files or from Time Travel. Resolution (D-10): pseudonymize user identifiers at extraction with a per-tenant HMAC key; resolve display names through a small per-tenant identity dictionary that is itself deletable (crypto-shredding-lite). The journal stays immutable and erasure becomes a dictionary deletion plus Snowflake residual disclosure. Design in [backlog/SEC.md](backlog/SEC.md).

### X-16 · Query-level volume and retention are unbounded in cost · MEDIUM → D-11

The benchmark profile in `operations.md` is 182.5 billion query rows per year (100 tenants × 5 accounts × 1 M/day × 365). Even at a few hundred bytes per row compressed, that is tens of terabytes of query-grain facts in central Snowflake, plus dbt incremental processing over them, plus the one-year backfill per new customer. Resolution (D-11): query-level detail hot for 90 days (plan-configurable), query-family × day aggregates (by `QUERY_PARAMETERIZED_HASH`) for the 400-day canonical horizon. The Query Explorer states the tier boundary explicitly.

### X-17 · Kilobyte configuration shipped through S3 + Snowpipe is disproportionate · MEDIUM → D-04

ADR-007 exports every immutable configuration version (rules, budgets, schedules) through the outbox → S3 → Snowpipe → Snowflake. That adds Snowpipe latency (typically a minute or more) and a second acceptance protocol to every rule simulation and publication, for payloads of a few kilobytes. Idempotency and reproducibility come from immutable, versioned keys, not from the transport. Resolution (D-04): a dedicated `config-publisher` WIF identity inserts immutable config versions directly (insert-only, keyed by `config_version`), with an S3 archival copy; draft simulations write to a separate `simulation_input` schema.

### X-18 · The grain at which estimates are replaced by billing is undefined · BLOCKER → D-12

The ledger contract says: "Before currency billing, estimates are explicitly provisional and replaced by the corresponding authoritative bucket version, not appended." Estimates are naturally produced at warehouse-hour grain (credits × rate); authoritative `USAGE_IN_CURRENCY_DAILY` arrives at organization/account × day × service-type (+ rating/billing type, balance source, adjustment flag). If the two grains differ, "replace, not append" has no key to replace on, and either double counting or orphaned estimates follow. Resolution (D-12): `fct_charge` grain is the **billing bucket**; estimates are aggregated to that bucket before publication; resource/hour/query money exists only in attribution bridges, obtained by applying the bucket's effective rate to operational quantities with an explicit rounding residual. Detailed in [backlog/FIN.md](backlog/FIN.md).

### X-19 · FINAL has no numbers · HIGH → D-13

ADR-003: "FINAL means source-mature under a documented policy." No document states the policy values (grep for maturity windows: only the ADR sentence and "maturation lag" as a registry field name). Every PROVISIONAL → FINAL transition, every monitor with `minimum_data_status: FINAL`, and every chargeback depends on them. Resolution (D-13): numeric, versioned per-source defaults in the source registry (e.g. `WAREHOUSE_METERING_HISTORY` FINAL at hour end + 24 h; `USAGE_IN_CURRENCY_DAILY` at day end + 72 h; month billing-stable at month end + N days), all revisable by later corrections.

### X-20 · Long-running queries break both extraction and attribution · HIGH → D-14

Two separate holes:

1. **Extraction.** QUERY_HISTORY is extracted by `START_TIME` in half-open windows with a 2-hour overlap (source catalog). A query that starts at 01:00 and finishes at 07:00 becomes visible in Account Usage only after completion plus latency (up to 45 min). By then the windows covering `START_TIME = 01:00` have been re-extracted for the last time, so the query can be lost. Statement timeouts default to 48 hours, so this is not exotic. The same applies to QUERY_ATTRIBUTION_HISTORY (up to 8 h latency). The catalog's "separate pending-query refresh until completion" presupposes knowing which queries are pending, which Account Usage may not expose (**TO VERIFY LIVE** whether running queries appear). A completion-time (`END_TIME`) sweep or a horizon equal to the maximum statement timeout is required. See [backlog/ING.md](backlog/ING.md).
2. **Attribution.** QAH gives credits per query, not per hour. A query spanning midnight contributes to two days of WAREHOUSE_METERING_HISTORY. Assigning all credits to the start date makes daily query sums disagree with daily warehouse compute and makes idle negative on some days. Resolution (D-14): prorate by execution-window overlap with metering hours; expose the hourly residual explicitly.

### X-21 · No default allocation for cloud services, storage, serverless, transfer and fees · MEDIUM → D-15

The allocation contract lists methods but not which one applies to which charge family when a tenant is onboarded. Onboarding step 11 ("simulate allocation") and FIRST_VALUE item 6 ("verify allocated plus unallocated equals eligible ledger total") therefore produce either nothing or arbitrary numbers. Resolution (D-15): a seeded, editable default book per family.

### X-22 · Rule evaluation engine is unspecified · HIGH → D-16

"Rules use a typed bounded expression AST… No arbitrary SQL/Python/eval." Where and how the AST is evaluated over up to a million queries per account per day is not stated. Python evaluation would violate PRD §2.5 ("Python must not quietly become another analytical database"); per-tenant generated SQL would mean per-tenant dbt compilation. Resolution (D-16): data-driven predicate tables evaluated by generic set-based SQL, with a restricted operator set in R1.

### X-23 · dbt Core WIF support now exists — V01 narrows

`OPEN_VALIDATIONS.md` V01 treats dbt adapter WIF compatibility as an open risk. dbt-labs/dbt-adapters PR #1316 ("Adding support for Snowflake Workload Identity Federation") was merged on 2026-05-20 with milestone **dbt-snowflake v1.12.0** — VERIFIED ([PR](https://github.com/dbt-labs/dbt-adapters/pull/1316)). Pin dbt-snowflake ≥ 1.12 in FND-002 (D-21). The live proof in CON-002 is still required, but a pre-agreed fallback is no longer needed.

### X-24 · Query-broker placement is ambiguous · MEDIUM → D-22

ADR-005 calls for an "isolated query broker"; the API contract says "The API authorizes current user scope, chooses the corresponding constrained Snowflake principal". If the broker lives inside the API process, compromising the API grants every tenant role. Resolution (D-22): a separate internal service with its own task role, the only component able to assume tenant serving identities.

### X-25 · The hot path adds a second extraction family for little FinOps value in R1 · LOW → D-24

ING-012 includes "bounded hot history" (PRD §37). INFORMATION_SCHEMA table functions have different privileges, retention and row limits from Account Usage and would need their own contracts, reconciliation with later Account Usage rows and precedence rules. FinOps decisions tolerate the 45 min–3 h Account Usage latency. Resolution (D-24): defer to R2 and show honest "current through" timestamps.

### X-26 · Central Snowflake and AWS run costs are modelled only at M9 · HIGH

Unit economics (`OPS-009`) is an M9 task, but architecture choices made at M1–M4 fix the cost structure: serving warehouse strategy (an XSMALL kept warm for 12 business hours ≈ 12 credits/day ≈ 360 credits/month before Redis hits), monitor evaluation (e.g. 100 tenants × 20 monitors × 24 hourly evaluations = 48,000 queries/day unless batched per dataset/window), dbt cadence, NAT gateways and interface endpoints per AZ per environment (the INF audit estimates up to ≈ USD 795/month for interface endpoints alone across environments, and flags AWS Config recording of task network interfaces at D-07 scale as a further trap). Snowpipe file counts are **no longer** a cost driver: since 2025-12-08 Snowpipe bills a flat 0.0037 credits per GB with no per-file charge (VERIFIED by the ING and INS audits), which also removes the savings basis of the tiny-file detectors PI01–PI04. Resolution: a cost model is a contract-first artifact at M1, refreshed at each milestone ([backlog/OPS.md](backlog/OPS.md), [backlog/INF.md](backlog/INF.md)).

### X-27 · Single EU central region, no residency strategy · MEDIUM → D-23

`eu-west-1` is the default. A US customer's user names and SQL metadata would be processed in the EU, and a Snowflake account on Azure or GCP would be extracted cross-cloud over the internet. Resolution (D-23): R1 is a single EU deployment; additional regions are separate stacks from the same code with per-region configuration; the onboarding flow states the processing region.

### X-28 · Preview-stage Snowflake features sit on the critical path · MEDIUM

Adaptive warehouses (`QUERY_METERING_HISTORY`, FIN-004 on the 73-task chain) and some Cortex usage views are recent. The FIN audit found Adaptive warehouses generally available on AWS since 2026-06-16 (search snippet; some Azure/GCP regions later), so the issue is not maturity but relevance: the first customer may not use them. The Cortex authority view also changed (CORTEX_AI_FUNCTIONS_USAGE_HISTORY, data from 2026-01-05), making the source catalog's choice outdated (G-FIN-06). Putting FIN-004 on the critical path makes the first release depend on a feature the first customer may not use. Resolution: capability-gated, R2 unless D-20 says the first customer uses it; financial coverage of those charges is guaranteed by the billing-bucket ledger (D-12) and FIN-021 regardless.

## 4. Logic defects found in the canonical contracts

### X-30 · Monitor confirmation counts ticks, not new evidence · HIGH

`governance.md`: "Default evaluation is hourly UTC over the last complete daily window… Sustained threshold breach requires 2 eligible evaluations." Two consecutive hourly ticks evaluate **the same completed day with the same input publication**, so "sustained for 2 evaluations" is satisfied one hour later by re-reading identical data — the hysteresis does nothing. The worked example ("observations 101/102 … the next hourly 103") implicitly assumes the value changes every hour, which contradicts a fixed daily window. Resolution: count confirmations only across **distinct evaluation windows** (or distinct input publications that change the observed value); for daily-window monitors, sustained = 2 distinct days. Detailed in [backlog/GOV.md](backlog/GOV.md).

### X-31 · Report retention (30 days) conflicts with immutable chargeback statements

ADR-009: "reports 30 days". Chargeback statements are "immutable" and "reference evidence" (ADR-003, allocation contract), and CFO/chargeback reports are generated artifacts. Deleting a delivered statement's PDF after 30 days breaks restatement audit trails; accounting evidence often has multi-year retention obligations. Resolution: a separate `financial_statement` retention class (configurable, multi-year), distinct from convenience reports.

### X-32 · Detectors depend on source columns that are not extracted

The source catalog's required QUERY_HISTORY projection excludes spill, partition-pruning and rows-affected columns ("Add hash versions and performance fields only through verified optional projection"), yet detectors Q03 (spill), Q04 (pruning), PL01/PL03 (change signal) and the query-detail screens need them. WH02 needs current warehouse settings (auto-suspend) for which no source is catalogued. Resolution: detector-to-source column matrix and projection additions in [backlog/INS.md](backlog/INS.md) and [backlog/ING.md](backlog/ING.md).

### X-33 · "Explain This Number down to source batch/file" is not bounded

PRD §87 and API-005 promise lineage from a chargeback line to "source batch/file". A monthly team statement line aggregates millions of attribution rows from thousands of files. Materializing that lineage per number is infeasible; the API must be a lazy, paginated tree evaluated at the pinned publication, summarizing file sets at the leaves. See [backlog/API.md](backlog/API.md).

## 5. Product, business and delivery gaps

| ID | Gap | Consequence | Decision |
|---|---|---|---|
| X-40 | No pricing / plan model (grep: only "plan quotas" in launch.md) | Entitlements, quotas, unit-economics targets and the manual invoice cannot be designed | D-17 |
| X-41 | No localization strategy (grep: no i18n) | Retrofitting string externalization and locale formatting across 87 screens is expensive | D-18 |
| X-42 | Team size and composition unknown; owners are personas | Estimates cannot become a schedule; parallel lanes cannot be staffed | D-19 |
| X-43 | First-customer profile unknown | Cannot decide which of FIN-004/018/019/020, WRK-003, INS AI/SP detectors are R1 | D-20 |
| X-44 | Legal/commercial pack is a checklist line | DPA (GDPR art. 28), subprocessor list, VAT treatment and — if the company is French — the e-invoicing reform obligations must be settled before the first invoice (**TO VERIFY** with counsel; see [backlog/LCH.md](backlog/LCH.md)) | D-17, D-25 |
| X-45 | SOC 2 / ISO posture unstated | Enterprise FinOps buyers ask early; controls are cheaper to build in than retrofit | D-25 |
| X-46 | Time-to-first-value assumes a reconcilable closed month | A customer onboarded mid-month cannot see RECONCILED data until the month closes and billing matures (+72 h and later adjustments); FIRST_VALUE step 5 needs a "last closed month" rule and a week-1 value definition | [backlog/ONB.md](backlog/ONB.md) |
| X-47 | No invoice-reference intake | The named INVOICE reconciliation control needs a customer-supplied statement; no task covers upload, parsing or manual entry | [backlog/FIN.md](backlog/FIN.md) |

## 6. Where each cross-cutting finding is resolved

| Finding | Decision | Resolved in |
|---|---|---|
| X-01…X-04 | — | every [backlog/](backlog/) file; [RELEASE_PLAN.md](RELEASE_PLAN.md) |
| X-05 | D-01 | [RELEASE_PLAN.md](RELEASE_PLAN.md); dependency changes in each backlog file |
| X-06 | — | [CONTRACT_FIRST_ARTIFACTS.md](CONTRACT_FIRST_ARTIFACTS.md) |
| X-10, X-24 | D-02, D-22 | [backlog/SEC.md](backlog/SEC.md), [backlog/API.md](backlog/API.md) |
| X-11, X-17 | D-04, D-05, D-06 | [backlog/ORC.md](backlog/ORC.md), [backlog/DBT.md](backlog/DBT.md), [backlog/CTL.md](backlog/CTL.md) |
| X-12, X-13, X-14, X-20, X-25 | D-07, D-08, D-09, D-14, D-24 | [backlog/CON.md](backlog/CON.md), [backlog/ING.md](backlog/ING.md) |
| X-15 | D-10 | [backlog/SEC.md](backlog/SEC.md), [backlog/OPS.md](backlog/OPS.md) |
| X-16 | D-11 | [backlog/ING.md](backlog/ING.md), [backlog/WRK.md](backlog/WRK.md) |
| X-18, X-19, X-28, X-47 | D-12, D-13, D-20 | [backlog/FIN.md](backlog/FIN.md) |
| X-21, X-22, X-30 | D-15, D-16 | [backlog/ALC.md](backlog/ALC.md), [backlog/GOV.md](backlog/GOV.md) |
| X-23 | D-21 | [backlog/FND.md](backlog/FND.md), [backlog/CON.md](backlog/CON.md) |
| X-26 | — | [backlog/OPS.md](backlog/OPS.md), [backlog/INF.md](backlog/INF.md) |
| X-31, X-32, X-33 | — | [backlog/RPT.md](backlog/RPT.md), [backlog/INS.md](backlog/INS.md), [backlog/API.md](backlog/API.md) |
| X-40…X-46 | D-17…D-20, D-23, D-25 | [DECISIONS_REQUIRED.md](DECISIONS_REQUIRED.md), [backlog/LCH.md](backlog/LCH.md), [backlog/ONB.md](backlog/ONB.md) |

## 7. Blocking findings from the domain audits

The nine domain audits recorded 29 BLOCKER and about 150 HIGH findings. The blockers, grouped by theme (details, evidence and resolutions in the linked backlog files):

| Theme | Blocking findings |
|---|---|
| Money is computed wrongly or cannot be computed | [G-FIN-01](backlog/FIN.md) estimate replacement impossible as keyed · [G-FIN-02](backlog/FIN.md) / [G-ING-02](backlog/ING.md) the Snowflake Python connector converts scaled NUMBER to float64 unless `arrow_number_to_decimal=True` (VERIFIED in connector source) · [G-ALC-01](backlog/ALC.md) no allocation input grain under billing-bucket charges · [G-API-02](backlog/API.md) `spend` cannot be grouped by warehouse/user without a conserving `attributed_cost` metric |
| Data is silently lost | [G-ING-01](backlog/ING.md) START_TIME windows lose queries longer than ~75–120 min (QUERY_HISTORY) and ~15 h (QAH) · [G-WRK-01](backlog/WRK.md) dbt/Power BI identity is irreversibly lost unless extracted inside the sanitizer at M1 · [G-INS-01](backlog/INS.md) / [G-INS-02](backlog/INS.md) detector inputs and warehouse settings are never extracted |
| Tenant isolation / security | [G-SEC-01](backlog/SEC.md) no implementable serving-authorization design; new Snowflake users default to secondary roles `ALL` (VERIFIED) · [G-SEC-02](backlog/SEC.md) scope grammar is prose only · [G-SEC-04](backlog/SEC.md) no capability matrix or maker-checker · [G-SEC-10](backlog/SEC.md) PG RLS mechanics missing (FK checks bypass RLS — VERIFIED) · [G-ALC-03](backlog/ALC.md) team readers can derive sibling spend from shares · [G-ALC-04](backlog/ALC.md) no task turns group grants into Snowflake entitlements · [G-ORC-03](backlog/ORC.md) Dagster launcher role override · [G-INF-02](backlog/INF.md) runtime IAM role creation undefined |
| Physical design missing | [G-CTL-01](backlog/CTL.md) no control-plane DDL · [G-DBT-01](backlog/DBT.md) dbt `insert_overwrite`/`microbatch` on Snowflake cannot give per-tenant atomic publication (VERIFIED) · [G-ORC-06](backlog/ORC.md) publication transaction under-specified; DDL auto-commits · [G-API-01](backlog/API.md) semantic registry has no format or compile model · [G-ALC-02](backlog/ALC.md) rule engine has no predicate model |
| Scale | [G-ORC-01](backlog/ORC.md) run/partition model exceeds Dagster limits (182,500 partitions per asset vs ~100k guidance) |
| Operations and recovery | [G-OPS-01](backlog/OPS.md) operational foundations scheduled after all product work · [G-OPS-06](backlog/OPS.md) analytical snapshot has no physical design · [G-OPS-07](backlog/OPS.md) deletion tombstones are rolled back by restores · [G-INF-01](backlog/INF.md) no Snowflake test estate for live gates |
| Customer and launch | [G-CON-01](backlog/CON.md) customer-side warehouse/cost absent · [G-LCH-01](backlog/LCH.md) go-live sequenced after the customer is already in production |

Integration of duplicate tasks and cross-domain contradictions: [RECONCILIATION.md](RECONCILIATION.md). Revised dependency graph and critical path: [revised-task-graph.json](revised-task-graph.json), [REVISED_CRITICAL_PATH.md](REVISED_CRITICAL_PATH.md).


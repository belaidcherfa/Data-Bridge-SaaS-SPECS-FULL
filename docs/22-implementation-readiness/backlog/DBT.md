# DBT — Implementation-readiness review and production backlog

Canonical contract: [transformation.md](../../07-dbt/transformation.md). Related: [ledger.md](../../08-finops-ledger/ledger.md), [orchestration.md](../../06-dagster/orchestration.md), [ADR-002](../../architecture/adr/ADR-002-financial-grains.md), [ADR-005](../../architecture/adr/ADR-005-analytical-authorization.md), [ADR-009](../../architecture/adr/ADR-009-privacy-and-retention.md), [ORC backlog](ORC.md) (publication, processing ledger). Tasks reviewed: DBT-001, DBT-002, DBT-003, DBT-004, DBT-005, DBT-006. Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

## 1. Verdict

Not implementable as specified. The layer ownership, exact-decimal and independence rules are sound, but the physical write model is contradictory: the contract says "MERGE", "per-tenant/dataset/partition lease" and "typed tenant, account scope, window" run context, while D-05/D-06 require insert-only revisions and multi-tenant set-based builds; none of the six tasks defines the revisioned tables, materialization, serving views, policy attachment or GC. Verified dbt-snowflake behaviour rules out the built-in strategies for per-tenant publication (`insert_overwrite` truncates the whole table, `microbatch` deletes a time slice across all tenants). Two further blockers: a uniform (tenant, day) partition grain rewrites query-grain facts 24–48× per day, and a 90-day RAW retention makes the promised shadow/full rebuild impossible beyond 90 days. Author DBT-101 (ADR-014 + DDL + benchmark) first; DBT-001/101/102 can start at M2 instead of waiting for ORC-004. Realistic effort ~264–380 h R1.

## 2. Findings

### G-DBT-01 · Physical write model undefined; built-in incremental strategies cannot provide per-tenant atomic publication
Severity: BLOCKER · Type: CONTRADICTION (challenges `transformation.md` "dedup source before MERGE", PRD §50 "MERGE latest 2–7 days", PRD §126 "MERGE")
Evidence: VERIFIED (github.com/dbt-labs/dbt-adapters `dbt-snowflake/.../materializations/incremental/insert_overwrite.sql` and `merge.sql`, main, 2026-09-27): Snowflake `insert_overwrite` "causes the entire target table to be cleared (essentially a TRUNCATE) before the new data is inserted"; `microbatch` is `delete from target where event_time >= start and < end` then insert — every tenant's rows in that time slice; `merge`/`delete+insert` mutate rows in place. `orchestration.md` requires "No user sees a half-new ledger/half-old allocation snapshot" and "API responses, cursors, reports and monitor evaluations pin one publication manifest".
Why it matters: in-place mutation destroys the version a pinned cursor/report is reading and exposes half-built state between models; table swap is DDL (auto-commit, all tenants at once); microbatch reprocessing tenant A's day rewrites every tenant's rows of that day (write amplification × tenants, extra Time Travel storage).
Resolution (D-05): DBT-101/ADR-014 — revisioned tables `*_R(tenant_id, scope_id, partition_start, revision_id, build_id, …)`, custom `revisioned` materialization (DML-only transaction: delete own unpublished build rows for retry idempotency → `INSERT … SELECT … ORDER BY tenant_id, scope_id, partition_start` restricted to `BUILD_WORKSET` → register every workset partition in `PARTITION_REVISION` with row_count and `HASH_AGG` checksum, including zero-row partitions), SCD2 publication map (ORC-005), secure serving views exposing `_pub_from/_pub_to`. No MERGE anywhere in R1 (refines D-05: staging dedup is read-time, see G-DBT-12). MERGE remains the fallback only if the DBT-101 benchmark shows read-time dedup too costly.
Affects: DBT-002, DBT-004, DBT-006, DBT-101, ORC-005, FIN-001.

### G-DBT-02 · A uniform (tenant, day) partition grain multiplies query-grain writes 24–48×
Severity: HIGH · Type: RISK
Evidence: D-05 "Clustering on (tenant_id, partition date)"; `operations.md` benchmark "up to1M queries/account/day"; D-08 hourly cadence.
Why it matters: rebuilding a 1M-row (account, day) partition on each of 24 hourly builds writes 24M rows/account/day; with a 2-day overlap 48M; at 500 accounts ≈ **24B rows/day** written for ≈ 0.5B natural rows. Charge-grain datasets (D-12) are tiny per partition and unaffected.
Resolution: partition grain is declared per dataset in `data/contracts/datasets.yaml`: `fct_query_compute` and query-grain bridges = (account, **hour**), 365-day hot retention (D-11 owner decision 2026-09-28; 90 days as first recommended) → with ~3 rebuilds per hour partition ≈ 3M rows/account/day (≈ 1.5B/day at 500 accounts, 3× natural), unchanged by retention, while retained query-grain volume grows ≈ 4×; charges/attribution/allocation/serving = (scope, day); monthly marts = (tenant, month); Python outputs = (tenant, as_of day). Map cardinality check: 500 accounts × 24 × 365 = 4.38M map rows for the hour-grain dataset (1.08M at 90 days) — acceptable for a clustered table, measured in DBT-101-S09 (TO VERIFY LIVE).
Affects: DBT-101, DBT-004, DBT-006, ORC-101.

### G-DBT-03 · Run-context contract contradicts multi-tenant builds (D-06)
Severity: HIGH · Type: CONTRADICTION
Evidence: `transformation.md` — "Model invocations receive typed tenant, account scope, window and config/publication IDs from trusted run context" and "Use a serialized per-tenant/dataset/partition lease for overlapping dbt runs".
Why it matters: a set-based build covers hundreds of tenants with different windows and config versions; passing them as vars forces one dbt invocation per tenant (rejected by D-06) and per-partition PostgreSQL leases would be tens of thousands of lease rows per build.
Resolution: the only dbt var is `build_id` (UUID). Everything else is data: `BUILD_WORKSET` (exact partitions), `BUILD.snapshot_seq` (accepted input bound), `BUILD_CONFIG_PIN` (per-tenant config version, D-04). Concurrency safety = one lane lease + fence (ORC-005) + publish rule "candidate snapshot_seq ≥ published snapshot_seq per partition". Macros `in_workset()`, `accepted_source()`, `pinned_config()` (DBT-103).
Affects: DBT-001, DBT-004, DBT-103, ORC-101.

### G-DBT-04 · `publication_id` as a mandatory row column defeats partition reuse
Severity: HIGH · Type: CONTRADICTION
Evidence: `ledger.md` Financial schema — "Mandatory: … source_view/batch/file, model_version, publication_id."; `orchestration.md` — "Reuse unchanged partitions; do not copy 500M rows on every publication."
Why it matters: a row stamped with publication_id must be rewritten every time a publication includes its unchanged partition — exactly the copy the orchestration contract forbids.
Resolution: rows carry `revision_id` and `build_id`; publication membership is resolved through the map (`_pub_from/_pub_to` in serving views; API meta returns the pinned `pub_seq`). FIN-001 schema replaces `publication_id` with `revision_id`.
Affects: FIN-001, DBT-101, DBT-006, API-002.

### G-DBT-05 · 90-day RAW retention makes the promised rebuild horizon impossible
Severity: HIGH · Type: CONTRADICTION (challenges ADR-009 default "RAW 90 days")
Evidence: ADR-009 — "Default S3 replay 90 days, RAW 90 days, canonical 400 days"; `transformation.md` — "Full refresh in production is a controlled shadow rebuild"; PRD §51 full rebuild for "critical bug fix / major ledger algorithm change".
Why it matters: a ledger algorithm fix cannot be applied to days 91–400 — they can only be carried forward unchanged, contradicting "shadow rebuild followed by comparison".
Resolution: retention by source class in the registry: financial/metering/billing sources (no personal data) RAW 400 days (these are small); query-level and user-bearing sources 90 days (D-26; since the owner's D-11 decision query-level facts are kept 365 days, so query facts older than 90 days are rebuilt by re-extraction within Account Usage's 365 days, not from RAW); staging stays views over RAW. Rebuild horizon per dataset is declared (`rebuild_horizon_days`) and a request beyond it returns `REBUILD_HORIZON_EXCEEDED`; query-grain facts and family aggregates beyond the 90-day RAW horizon are canonical and only carried forward (or re-extracted within 365 days). Needs Security/Privacy sign-off (§7).
Affects: DBT-002, DBT-004, ING-006, OPS-007.

### G-DBT-06 · Row access policy attachment point and view replacement are unsafe
Severity: HIGH · Type: RISK
Evidence: DBT-006 MT2 — "Apply policy bindings to every new serving object before grants"; `security.md` — "Apply row access policy to every readable serving boundary, including new versions". DDL auto-commits (VERIFIED via search snippet of docs.snowflake.com/en/sql-reference/transactions, 2026-09-27). Whether `CREATE OR REPLACE VIEW … COPY GRANTS` retains policy associations: TO VERIFY LIVE (search did not confirm).
Why it matters: dbt recreates views/tables on every run; a post-hook `ALTER … ADD ROW ACCESS POLICY` leaves a window where a view exists with copied grants and no policy; a `--full-refresh` of a protected table drops its policy.
Resolution: attach RAP to the stable insert-only `*_R` base tables (never replaced: `revisioned` materialization raises on full refresh) and to `PY_REV` tables; serving secure views are deployed by release migrations, not by dbt runs; policy body per D-02 (`CURRENT_USER()`→tenant, `CURRENT_ROLE()`→profile entitlements, `IS_ROLE_IN_SESSION('<transformer/publisher>')` exemption); a migration/CI gate queries `POLICY_REFERENCES` and fails if any `*_R` table or serving view source lacks a policy.
Affects: DBT-006, DBT-101, SEC-005.

### G-DBT-07 · Model contracts do not enforce keys on Snowflake; custom materializations must opt in
Severity: HIGH · Type: VENDOR-FACT
Evidence: "Snowflake accepts PRIMARY KEY, FOREIGN KEY, and UNIQUE constraints but does not enforce them … NOT NULL is the single exception" (VERIFIED via search snippet of docs.getdbt.com/reference/resource-properties/constraints and Snowflake-Labs/dbt_constraints, 2026-09-27). dbt ≥ 1.10 requires custom keys under `config.meta` (VERIFIED via search snippet of docs.getdbt.com/reference/deprecations, `CustomKeyInObjectDeprecation`). `transformation.md` — "Each model declares grain, unique key, tenant key … in YAML metadata".
Why it matters: teams will read `contract: enforced` as uniqueness enforcement; a custom materialization that doesn't call dbt's contract assertion macros silently skips even column/type enforcement.
Resolution: metadata under `config.meta.bridge` validated by JSON Schema (`data/contracts/dbt_meta.schema.json`); `revisioned` materialization calls the contract assertion (`get_assert_columns_equivalent`) — tested by removing a column; uniqueness/relationships enforced by check models (DBT-005).
Affects: DBT-001, DBT-005, DBT-101.

### G-DBT-08 · "Tenant-safe join" tests cannot detect a missing join predicate on non-colliding data
Severity: HIGH · Type: GAP
Evidence: `transformation.md` — "custom SQL tests for tenant-safe keys"; PRD §52 "no cross-tenant joins"; DBT-005 oracle — "deliberate cross-tenant join … fail".
Why it matters: a join `ON a.account_id = b.account_id` without tenant_id returns correct results whenever account ids are globally unique in the fixture; a data test only fails when ids collide.
Resolution: two independent detectors: (1) static checker `tools/dbt_lint/tenant_join.py` (sqlglot, Snowflake dialect) over compiled SQL: for every JOIN whose both sides expose `tenant_id` (tracked through CTEs/subqueries) require a top-level conjunct `l.tenant_id = r.tenant_id` or `USING (tenant_id…)`; reject CROSS/comma joins between tenant-bearing relations; check IN/EXISTS subqueries; explicit exemption comment for global reference relations; (2) colliding-id golden fixture (FND-004: tenants A/B share account locator, warehouse names and query id Q1) with per-tenant exact totals. Mutation meta-test removes a tenant predicate and expects both to fail.
Affects: DBT-005, DBT-102.

### G-DBT-09 · Slim-CI deferral to production contradicts CI isolation
Severity: HIGH · Type: CONTRADICTION
Evidence: `transformation.md` — "dependency deferral only to approved compatible manifests"; DBT-005 oracle — "CI schema cannot read production"; `readiness.md` — "customer data never enters CI".
Why it matters: standard `--defer --state prod/` resolves unmodified refs to production relations, i.e., CI queries customer data.
Resolution: defer only to a **fixture-built CI baseline** (`BRIDGE_CI.BASELINE_*`, rebuilt nightly and on merge from FND-004 fixtures; its `manifest.json` is the state); CI identity (GitHub OIDC → AWS → Snowflake WIF, D-21) owns only `BRIDGE_CI`; TTL cleanup by ownership (janitor role owns only `CI_PR*` schemas), never by name regex; financial layer changes always run the full golden E2E, not only `state:modified+`.
Affects: DBT-005, DBT-102.

### G-DBT-10 · PRD non-negativity tests contradict signed ledger entries
Severity: MEDIUM · Type: CONTRADICTION (challenges PRD §52)
Evidence: PRD §52 — "cost >= 0 / credits >= 0"; ADR-002 — "Never impose universal cost>=0 on adjustment rows"; FIN-GOLD-01 cloud adjustment −10 credits, rebate −3.
Resolution: sign rule keyed by `entry_kind`: USAGE ≥ 0; ADJUSTMENT/REBATE/CREDIT/CORRECTION any sign; `allocated_cost <= source_cost + tolerance` replaced by exact conservation Σ children = parent per attribution set (signed), with coverage on absolute basis per `ledger.md`.
Affects: DBT-005, FIN-001.

### G-DBT-11 · dbt snapshots are non-deterministic under replay
Severity: MEDIUM · Type: RISK (challenges PRD §44/§151 `snapshots/`)
Evidence: PRD §44 tree contains `snapshots/`; `transformation.md` — "For snapshot-only metadata, capture SCD2 from first observation".
Why it matters: `dbt snapshot` mutates in place using run time, so replaying the journal or a shadow rebuild cannot reproduce validity ranges, and it is not workset/tenant aware.
Resolution: SCD2 built as deterministic models from the extracted observation log (LAG over `observed_at`, half-open ranges, pre-enrollment uncertainty row); `snapshots/` directory prohibited by lint.
Affects: DBT-001, DBT-003.

### G-DBT-12 · Staging dedup semantics conflict between "legit duplicates" and overlap windows
Severity: MEDIUM · Type: AMBIGUITY
Evidence: DBT-002 oracle — "100 duplicated source rows yield 100 canonical rows"; failure — "row-hash collapses legitimate duplicates"; `ingestion.md` — "For mutable daily billing, retrieve complete scoped day partitions and select the newest accepted partition snapshot".
Why it matters: row-hash dedup collapses legitimate identical rows; window selection with overlapping windows double-counts.
Resolution: registry `dedup_mode`: NATURAL_KEY (e.g., QUERY_ID; latest by authority_rank, source_revision, extracted_at, accepted_seq, file, row) or WINDOW_SNAPSHOT (pick one accepted batch per logical window, keep all its rows); WINDOW_SNAPSHOT sources must have aligned, non-overlapping windows equal to partitions (registry validation). Worked example: attempts 1 and 2 of the same window, each 100 rows including 10 identical pairs → 100 rows; correction attempt 3 with 10 rows → 10 rows; accepted empty window → 0 rows and the partition is still rebuilt so old rows disappear.
Affects: DBT-002, ING-001, ING-008.

### G-DBT-13 · Build consistency needs an accepted-input snapshot
Severity: HIGH · Type: GAP — detailed in [G-ORC-07](ORC.md). dbt side: every staging read goes through `accepted_source()` with `accepted_seq <= snapshot_seq`; lint forbids direct `source('raw', …)` outside it.
Affects: DBT-001, DBT-002.

### G-DBT-14 · Shadow rebuild lacks a cutover and comparison procedure
Severity: MEDIUM · Type: GAP
Evidence: DBT-004 MT3 — "shadow rebuild a changed model and atomically publish only after checks".
Why it matters: new code must coexist with steady-state builds for hours; publishing a tenant with some partitions from old code and some from new code yields an incoherent history; intentional number changes cannot pass an "equality" gate.
Resolution: shadow code location pinned to the new image builds SHADOW revisions chunked by month; steady builds dual-run new partitions until cutover; comparison per tenant/dataset/partition (row count, Σ by currency/service, checksum) → diff report bound to an approval (sha256) → publication only when all affected partitions of a tenant are at the new code version (code-version homogeneity gate, ORC-005-S03); closed periods excluded (FIN-010 restatement). Schema-breaking changes use versioned relations + union views (DBT-104, R2).
Affects: DBT-004, DBT-104, ORC-005.

### G-DBT-15 · Generated docs can leak production metadata
Severity: LOW · Type: RISK
Evidence: `transformation.md` — "Publish generated model docs privately".
Resolution: `dbt docs generate` only against the fixture CI baseline (catalog stats then contain fixture data only), hosted on private S3 + CloudFront/ALB with SSO; never generated in production targets.
Affects: DBT-102.

### G-DBT-16 · Dependency corrections
Severity: HIGH · Type: CONTRADICTION
Evidence: `TASK_INDEX.md` — "DBT-001 … ORC-004, ING-008"; DBT-003 ← CTL-001; DBT-005 ← SEC-008; FIN-001 ← DBT-005.
Resolution: DBT-001 −ORC-004 −ING-008 +CON-002 +INF-008 +FND-004 +ING-001 (ORC-004 needs DBT-001's manifest, see G-ORC-12); DBT-002 +ORC-101 +DBT-101; DBT-003 −CTL-001 +DBT-103 (membership arrives via CTL-005 config snapshots, D-04, not PostgreSQL); DBT-004 +DBT-101 +ORC-101 (ORC-005 only for shadow-publication steps S08–S11); DBT-005 −SEC-008 (API audit/attack suite not used) +DBT-102 +FND-004; DBT-006 +ORC-005; FIN-001 −DBT-005 +DBT-001 +DBT-101 (schema/fixtures can precede the golden harness; FIN model gates still need DBT-005). Net effect: the dbt chain starts at M2 (after CON-002/INF-008) instead of after ORC-001…004.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by (task/micro-task) |
|---|---|---|
| ADR-014 analytical revisions and publication | Decision, rejected strategies with verified semantics, pin semantics, GC, RAP attachment, benchmark results | DBT-101-S01/S11 |
| `data/contracts/datasets.yaml` | dataset_id → physical `*_R` table, scope (account/organization/tenant), time grain (hour/day/month), retention, rebuild_horizon_days, RAP policy, clustering, upstream partition mappings | DBT-101-S02 |
| Revision table DDL template | `tenant_id, scope_id, partition_start, revision_id NUMBER(38,0), build_id, <business columns>`; `CLUSTER BY (tenant_id, partition_start)` with automatic clustering suspended initially; `DATA_RETENTION_TIME_IN_DAYS=1`; RAP attached | DBT-101-S03 |
| `PARTITION_REVISION` DDL | tenant_id, dataset_id, scope_id, partition_start, revision_id, build_id, row_count, checksum, snapshot_seq, code_version, config_versions, status CANDIDATE/PUBLISHED/SUPERSEDED/PURGED | DBT-101-S03 |
| `revisioned` materialization spec | statements, transaction boundary, zero-row registration, contract assertion, full-refresh refusal, error codes | DBT-101-S04 |
| Serving view template | secure view joining `*_R` to `PUBLICATION_MAP` exposing `_pub_from/_pub_to`; pinned query template | DBT-101-S05/S08 |
| `data/contracts/dbt_meta.schema.json` | `config.meta.bridge`: layer, dataset_id, grain, unique_key, tenant_key, partition{scope,time_column,grain}, upstream_partition_map, authority, measure_role, coverage_policy, privacy, owner, release, retention_days | DBT-001-S04 |
| `data/contracts/checks.yaml` | check_id, version, dataset, severity required/advisory, tenant-scoped vs structural, evidence columns | DBT-005-S01 |
| Lint rule catalog | L01 meta present/valid; L02 grain/tenant columns exist; L03 allowed materializations per layer; L04 no money arithmetic in staging; L05 union by explicit registry; L06 RAW only via `accepted_source()`; L07 tenant-safe joins; L08 var allowlist {build_id}; L09 no `snapshots/`; L10 no `is_incremental()` in revisioned models | DBT-102-S07, DBT-005-S04 |
| `data/contracts/lineage.json` | `LINEAGE.CHARGE_SOURCE` and `LINEAGE.PARTITION_EDGE` schemas and explain resolution algorithm | DBT-006-S06/S07 |
| CONFIG source contract (D-04) | CONFIG_VERSION, ACCOUNT_MEMBERSHIP, ORGANIZATION, TEAM, ALLOCATION_RULE, TAG_RULE_PREDICATE, RATE_CARD, USAGE_GROUP, BUDGET column contracts | DBT-103-S01 (with CTL-005) |

## 4. Revised production backlog

### DBT-001 — Bootstrap dbt Core project, profiles and model contracts
Release: R1 · Estimate: 28–40 h · Risk: M · Decisions: D-05, D-06, D-21 · Closes: G-DBT-07, G-DBT-11, G-DBT-16
Dependency changes: `−ORC-004 (inverted edge)`, `−ING-008 (+ING-001 contract)`, `+CON-002 (live WIF incl. dbt debug)`, `+INF-008`, `+FND-004`, `+FND-101` (developer inner loop / `dev` target; RECONCILIATION C-29, U-15); S07 macros finalized after DBT-101/DBT-103.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| DBT-001-S01 | Create project skeleton per PRD §151 without `snapshots/`: staging, intermediate, ledger/{warehouse,storage,serverless,cortex,transfer}, allocation, marts, serving, checks; seeds only static reference (calendar, currency minor units) | `data/dbt/dbt_project.yml`, dirs | `dbt parse` succeeds; lint L09 fails if `snapshots/` added | 2 |
| DBT-001-S02 | Pin dbt-core and dbt-snowflake ≥ 1.12 (WIF) from FND-002 lock; minimal pinned packages | `data/dbt/packages.yml`, lockfile | Version manifest matches lock | 1 |
| DBT-001-S03 | Write `profiles.yml` (single owner; FND-101 contributes the `dev` target — RECONCILIATION U-15) targets ci/staging/prod with WIF authenticator parameters from dbt-adapters PR #1316 (exact keys proven by CON-002), role/warehouse/database from env allowlist, default `query_tag`, statement timeout | `data/dbt/profiles.yml` | Lint rejects `password`, `private_key`, `token` keys; `dbt debug` passes under WIF in CI | 3 |
| DBT-001-S04 | Write meta JSON Schema for `config.meta.bridge` and validator over `manifest.json` | `data/contracts/dbt_meta.schema.json`, `tools/dbt_lint/meta.py` | Model missing grain or tenant_key fails CI | 3 |
| DBT-001-S05 | Set layer defaults: `contract.enforced` for ledger/allocation/marts/serving; document that only NOT NULL is enforced by Snowflake | `dbt_project.yml`, `data/dbt/README.md` | Removing a contracted column from a revisioned model fails the build | 3 |
| DBT-001-S06 | Generate `_sources.yml` for RAW, ACCEPTED_BATCH, CONFIG, PY from the ING-001 registry; CI diff check | `tools/dbt_sources_gen.py`, `models/staging/_sources.yml` | Registry change without regenerated sources fails CI | 3 |
| DBT-001-S07 | Create macro library: `bridge_build_id()` (UUID assert), `in_workset(dataset)`, `accepted_source(src)`, `pinned_config(kind)`, `tenant_join(l, r, keys)`, `money(col)` → NUMBER(38,12), `safe_decimal(col, reason)` | `data/dbt/macros/*.sql` | Compile tests of each macro output | 3 |
| DBT-001-S08 | Enforce var allowlist: `on-run-start` asserts `build_id` present/UUID in prod targets; lint allows `var('build_id')` only | `macros/hooks.sql`, lint L08 | `--vars '{"tenant":"x"}'` fails | 2 |
| DBT-001-S09 | Wire lint rules L01–L06 into CI (runner from DBT-102) including staging money-arithmetic ban | `.github/workflows/dbt.yml` | Seeded `credits * rate` in staging fails | 2 |
| DBT-001-S10 | Add environment guard: `on-run-start` asserts `CURRENT_ROLE()` and `CURRENT_ACCOUNT()` match target | `macros/hooks.sql` | Running prod target with staging identity aborts before any DML | 2 |
| DBT-001-S11 | Fixture build: one staging view + one toy revisioned model on FND-004 fixture in CI DB under WIF | CI evidence | `dbt build` evidence with adapter versions recorded | 3 |
| DBT-001-S12 | Negative auth tests: missing WIF parameter, revoked CI user | CI evidence | Both fail closed; no fallback authenticator attempted | 2 |
Task acceptance:
- [ ] Every model validates against the meta schema; missing grain/tenant key fails CI.
- [ ] `dbt debug`/`build` succeed under WIF; profiles contain no secret-bearing keys.
- [ ] Only `build_id` is accepted as a var; wrong account/role aborts before DML.
- [ ] Contract violation fails the build.

### DBT-002 — Implement staging dedup and complete-partition selection
Release: R1 · Estimate: 34–48 h · Risk: H · Decisions: D-03, D-05, D-10, D-13 · Closes: G-DBT-05, G-DBT-12, G-DBT-13
Dependency changes: `+ORC-101 (accepted_seq/snapshot)`, `+DBT-101`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| DBT-002-S01 | Add registry fields `dedup_mode` (NATURAL_KEY/WINDOW_SNAPSHOT), key/revision/authority columns; validate WINDOW_SNAPSHOT windows are aligned and non-overlapping | ING-001 registry schema + validator | Overlapping WINDOW_SNAPSHOT definition rejected | 2 |
| DBT-002-S02 | Implement staging pattern (views): `accepted_source()` join ACCEPTED_BATCH with `accepted_seq <= snapshot_seq`, registry casts, UTC normalization (LTZ/TZ→UTC; NTZ per declared semantic), provenance columns | `models/staging/_macros/staging_select.sql` | Unaccepted RAW rows never appear (fixture with partial batch) | 3 |
| DBT-002-S03 | Implement NATURAL_KEY dedup: `QUALIFY ROW_NUMBER() OVER (PARTITION BY tenant_id, account_id, <key> ORDER BY authority_rank DESC, source_revision DESC, source_extracted_at DESC, accepted_seq DESC, file_name, file_row_number) = 1` | macro `dedup_natural_key` | FINAL row kept when a later PROVISIONAL copy arrives | 3 |
| DBT-002-S04 | Implement WINDOW_SNAPSHOT selection: one accepted batch per (tenant, scope, source, logical_window_id) by max(complete_partition, accepted_seq); keep all its rows | macro `select_window_snapshot` | 100 rows incl. 10 identical pairs → 100; correction 30→10 → 10; empty window → 0 | 3 |
| DBT-002-S05 | Implement decimal normalization with `safe_decimal`: non-null source value that fails TRY_TO_DECIMAL → `QUALITY.STAGING_REJECT` row + FAIL check for tenant/source | `models/checks/chk_staging_reject.sql` | `'12.5x'` rejected, tenant publication gated, value never NULL-coerced into sums | 3 |
| DBT-002-S06 | Keep pseudonymized user identifiers (D-10) opaque; no identity-dictionary join in staging | meta privacy=pseudonymized | Lint L09-privacy passes; dictionary not referenced | 1 |
| DBT-002-S07 | Declare retention class and `rebuild_horizon_days` per source (financial 400, query-level 90) | `datasets.yaml`, registry | Rebuild request for query-level day 120 returns REBUILD_HORIZON_EXCEEDED | 2 |
| DBT-002-S08 | Implement R1 staging models per source family (WMH, METERING_DAILY, USAGE_IN_CURRENCY_DAILY, RATE_SHEET_DAILY, QUERY_HISTORY, QAH, STORAGE, serverless families used by FIN tasks) | `models/staging/stg_*.sql` + YAML | Contracts and meta valid for each | 6 |
| DBT-002-S09 | Write dbt unit tests per dedup mode: same-time conflicting revisions (tie broken by file/row deterministically), null key → reject, provisional-after-final | `models/staging/_unit_tests.yml` | All pass | 4 |
| DBT-002-S10 | Duplicate-transport test: same file loaded twice under replay keys | fixture | One canonical copy (NATURAL_KEY) / one selected batch (WINDOW_SNAPSHOT) | 2 |
| DBT-002-S11 | Timezone tests including DST boundary 2026-10-25 01:00 UTC and NTZ declared-UTC source | fixture | Hour buckets match expected UTC | 2 |
| DBT-002-S12 | Pruning check on benchmark: staging reads for workset partitions | QUERY_HISTORY evidence | partitions_scanned/partitions_total ≤ 5% for a 1% workset | 2 |
| DBT-002-S13 | Evidence pack | `docs/evidence/DBT-002/<commit>/` | FND-005 schema validates | 1 |
Task acceptance:
- [ ] 100 legitimate duplicate rows → 100; corrected 30→10 → 10; accepted empty window removes old rows.
- [ ] Malformed decimals are quarantined and gate that tenant's publication.
- [ ] FINAL/authoritative rows are never replaced by later PROVISIONAL copies.
- [ ] Staging reads only accepted batches ≤ snapshot and prunes to the workset.

### DBT-003 — Resolve resource history, account membership and workload joins
Release: R1 · Estimate: 28–40 h · Risk: H · Decisions: D-04, D-10, D-12, D-16, D-34 · Closes: G-DBT-11 (G-ORC-09 classification placement → WRK-001 per RECONCILIATION U-16)
Dependency changes: `−CTL-001`, `+DBT-103 (CONFIG membership via CTL-005)`; coordinate contract with WRK-001 and SEC-007. DBT-003 keeps resource history, membership and the `as_of_join`; workload classification is WRK-001's (D-34, RECONCILIATION U-16).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| DBT-003-S01 | Build `int_resource_identity`: UUIDv5(tenant_id, account_id, resource_type, source_object_id) using Snowflake internal ids (WAREHOUSE_ID, TABLE_ID …); name is an attribute | `models/intermediate/int_resource_identity.sql` | Rename keeps id; drop+recreate same name → new id | 3 |
| DBT-003-S02 | Build SCD2 from observation logs (LAG over observed_at, half-open ranges, pre-enrollment row with NULL attributes and `pre_enrollment=true`) | `models/dimensions/dim_*_history.sql` | Replay of the same observation log yields identical ranges (checksum) | 4 |
| DBT-003-S03 | Add non-overlap check model per dimension (tenant-scoped PASS/FAIL) | `models/checks/chk_scd_overlap.sql` | Seeded overlap → FAIL for that tenant only | 2 |
| DBT-003-S04 | Build account/org membership from pinned CONFIG.ACCOUNT_MEMBERSHIP plus ORGANIZATION_USAGE evidence; transfers effective-dated | `models/dimensions/dim_account_membership.sql` | Cost dated before transfer stays with old org | 3 |
| DBT-003-S05 | Implement `as_of_join(fact, dim, ts)` (`ts >= valid_from AND ts < valid_to` + tenant/account keys) with fanout assertion | `macros/as_of_join.sql` | Fixture: row count before = after join | 3 |
| DBT-003-S06 | Moved to WRK-001 per RECONCILIATION U-16, C-06 (D-34: set-based dbt SQL classification with the Python reference oracle; `fct_query_workload` replaces `PY_WORKLOAD_CLASSIFICATION`) — consume its output through `as_of_join` here | — | — | 0 |
| DBT-003-S07 | Build many-to-many bridges: `bridge_query_object_access` non-additive (weight NULL) or explicit weights with Σ weight = 1 per query (check \|Σ−1\| ≤ 1e-12) | `models/intermediate/bridge_*.sql` | 10-credit query on 2 tables: drilldown 10 each non-additive, additive total 10 | 3 |
| DBT-003-S08 | Foreign-tenant session test with colliding session_id | fixture | No cross-tenant match | 2 |
| DBT-003-S09 | Map missing dimension to explicit UNKNOWN member and count in coverage | model + check | Unmatched fact retained with UNKNOWN | 2 |
| DBT-003-S10 | Source-id reuse across accounts → distinct resources | fixture | Two resources for same WAREHOUSE_ID in two accounts | 1 |
| DBT-003-S11 | Unit + E2E fixtures for rename, recreate, transfer, colliding ids | `models/**/_unit_tests.yml` | All pass | 4 |
| DBT-003-S12 | Evidence pack | evidence | Validates | 1 |
Task acceptance:
- [ ] Rename keeps cost on the same resource id; recreate creates a new id.
- [ ] Two accessed tables never double a query's cost in additive metrics.
- [ ] Foreign-tenant sessions/resources never match.
- [ ] SCD2 ranges are non-overlapping and reproducible under replay.

### DBT-004 — Implement workset-bounded rebuilds and shadow rebuild
Release: R1 · Estimate: 34–48 h · Risk: H · Decisions: D-05, D-06 · Closes: G-DBT-03, G-DBT-14
Dependency changes: `+DBT-101, +ORC-101`; ORC-005 needed only for S08–S11.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| DBT-004-S01 | Replace time-based incremental predicates with `upstream_for_workset(ref, mapping)`; lint L10 forbids `is_incremental()` in revisioned models | `macros/upstream_for_workset.sql` | Model reading outside workset fails compile test | 3 |
| DBT-004-S02 | Drive late/correction windows from registry overlap and anti-entropy, not a universal cutoff | ORC-101 impact map integration | QAH 8 h late → correct hour partitions re-selected | 2 |
| DBT-004-S03 | Build determinism harness: 3 arrival orders with builds in between vs one clean build | `tests/dbt/rebuild/arrival_orders.py` | Per-partition HASH_AGG identical across all orders | 4 |
| DBT-004-S04 | Test overlapping lanes: steady and repair build same partition | test | Higher snapshot_seq revision published; other marked STALE | 3 |
| DBT-004-S05 | Add unbounded-scan guard on benchmark (query profile per model) | CI job | Revisioned model scanning > threshold for a 1% workset fails | 3 |
| DBT-004-S06 | Implement shadow planner `bridge-admin rebuild plan --datasets <sel> --since <date> --code-version <sha>` (reason SHADOW, monthly chunks) running in `cl-dbt-shadow` pinned to new image | `services/admin/rebuild.py` | Dry-run lists partitions and credit estimate | 3 |
| DBT-004-S07 | Implement comparison gate: per tenant/dataset/partition row count, Σ by currency/service, checksum → `QUALITY.SHADOW_DIFF` + private diff report | `models/checks/chk_shadow_diff.sql`, report job | IDENTICAL/CHANGED classification on fixture | 4 |
| DBT-004-S08 | Bind publication of shadow revisions to an approval referencing the diff report sha256 | PostgreSQL approval record + gate | Unapproved shadow publication blocked | 2 |
| DBT-004-S09 | Enforce code-version homogeneity per tenant and exclude closed periods | ORC-005 gate rule | Mixed-version tenant not published | 2 |
| DBT-004-S10 | Implement dual-run of new partitions during migration and per-tenant cutover | planner + gate | Cutover tenant sees only new-code revisions; others only old | 4 |
| DBT-004-S11 | Kill shadow build midway | test | Old publication remains readable; no partial publish | 2 |
| DBT-004-S12 | Block `--full-refresh` in prod (materialization raises; CLI wrapper refuses flag) | materialization + wrapper | Attempt returns FULL_REFRESH_FORBIDDEN | 1 |
| DBT-004-S13 | Runbook: shadow rebuild with credit estimate (partitions × measured credits/partition) | `docs/runbooks/dbt.md` | Reviewed | 2 |
Task acceptance:
- [ ] Full and incremental results are checksum-identical for all tested arrival orders.
- [ ] Concurrent writers cannot publish an older snapshot over a newer one.
- [ ] Shadow rebuild publishes only after approved comparison and per-tenant code homogeneity.
- [ ] Production full refresh is impossible.

### DBT-005 — Build golden financial tests and tenant-safe CI
Release: R1 · Estimate: 34–50 h · Risk: H · Decisions: D-06, D-12 · Closes: G-DBT-08, G-DBT-10, G-ORC-08
Dependency changes: `−SEC-008`, `+DBT-102, +FND-004`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| DBT-005-S01 | Create check-model framework writing the single result store `QUALITY.CHECK_RESULT(build_id, candidate_revision_id, tenant_id, check_id, check_version, dataset_id, partition_start, status PASS/FAIL/WARN, failing_rows, evidence)` keyed by candidate revision, with a row per (tenant in workset, check); registry required/advisory; OPS-002's gate checks write here and ORC-005-S03 is the only eligibility evaluator (RECONCILIATION U-19, C-23) | `models/checks/_framework.sql`, `data/contracts/checks.yaml` | Tenant without a row is treated FAIL by gate (test) | 4 |
| DBT-005-S02 | Implement check macros: key uniqueness, not-null keys, tenant-inclusive relationships, accepted-batch-only lineage, no double service inclusion (CHARGE registry), exact conservation Σ attribution = parent, sign validity by entry_kind | `macros/checks/*.sql` | Each has a failing and passing fixture | 4 |
| DBT-005-S03 | Implement `assert_no_fanout(model, parent, key)` before financial sums | macro | Seeded fanout fails | 2 |
| DBT-005-S04 | Implement sqlglot tenant-join checker (CTE tracking, CROSS/comma joins, IN/EXISTS, exemption comment) | `tools/dbt_lint/tenant_join.py` | Test corpus of 20 SQL cases (10 violating) classified exactly | 6 |
| DBT-005-S05 | Assert per-tenant golden totals on the colliding-id fixture | fixture assertions | A = 270.000000000000 USD; B = its own expected; any leak changes totals | 2 |
| DBT-005-S06 | Build golden E2E harness: fixture → RAW → accepted → planner → build → publish → serving query vs expected decimal strings | `tests/dbt/golden/run_golden.py` | FIN-GOLD-01 270 USD; EUR 20 separate; correction 12→11 → 269 | 4 |
| DBT-005-S07 | Write dbt unit tests for formula models | `_unit_tests.yml` | Idle 100−70 = 30 credits → 60 USD at 2 USD/credit; cloud 15−10 = 5 credits → 10 USD | 3 |
| DBT-005-S08 | Rounding oracle: three entries 33.333333333333 USD | fixture | Ledger sum 99.999999999999 exact; statement display 100.00 only at boundary (ledger-level NUMBER(38,2) cast mutation fails) | 2 |
| DBT-005-S09 | Mutation meta-tests: drop tenant predicate; union includes ATTRIBUTION (270→470); money cast NUMBER(38,2) at ledger | `tests/mutations/*.patch`, CI job | Each mutation fails its named gate | 4 |
| DBT-005-S10 | CI isolation proofs: CI role reads nothing outside `BRIDGE_CI`; on-run-start asserts `CI_` schema prefix | CI evidence | Cross-DB select fails; wrong schema aborts | 2 |
| DBT-005-S11 | Record `QUALITY.TEST_RUN(build_id, git_sha, model_versions, results_sha)` and export evidence | model + export | Evidence validates | 2 |
| DBT-005-S12 | Evidence pack | evidence | Validates | 1 |
Task acceptance:
- [ ] All three deliberate defects (cross-tenant join, double inclusion, rounding change) fail their gates.
- [ ] Golden E2E yields 270 USD, EUR 20 separate, and 269 after correction, as exact decimal strings.
- [ ] Missing check rows block publication; signed adjustments are accepted.
- [ ] CI cannot read any non-CI database.

### DBT-006 — Build serving partition revisions and explainable lineage
Release: R1 · Estimate: 34–48 h · Risk: H · Decisions: D-02, D-11, D-12 · Closes: G-DBT-06
Dependency changes: `+ORC-005 (views read the map)`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| DBT-006-S01 | Define serving grain catalog tied to API-001 registry: serving_daily_charge, serving_daily_group, serving_warehouse_daily, serving_workload_daily, serving_query_family_daily (serves WRK-104's `fct_query_family_daily`, grain and columns per RECONCILIATION U-17/C-01; 400 d), serving_budget_daily; each lists entitlement dimensions | `datasets.yaml`, `models/serving/_serving.yml` | Every API-001 metric/dimension pair maps to exactly one serving dataset | 3 |
| DBT-006-S02 | Implement serving models as revisioned day partitions from ledger/allocation revisions in workset | `models/serving/*.sql` | Fixture totals equal ledger totals per currency | 4 |
| DBT-006-S03 | Encode authorized-grain rule with SEC-005: team-restricted profile sees only its group rows; account totals require account entitlement | RAP bodies per table | Restricted user on serving_daily_charge gets 0 rows, not partial totals | 3 |
| DBT-006-S04 | Deploy secure serving views via migration (DBT-101 template) with `_pub_from/_pub_to`; reader grants on SERVING only | migration | Reader select on `*_R` fails; view works with pin | 3 |
| DBT-006-S05 | Add protection gate: fail if any `*_R` table lacks RAP or any SERVING view selects from a non-RAP table | `tools/snowflake/policy_gate.py` | Unprotected fixture table fails the gate | 2 |
| DBT-006-S06 | Write lineage tables: `LINEAGE.CHARGE_SOURCE` from fct_charge materialization; `LINEAGE.PARTITION_EDGE` from workset expansion | models + materialization hook | Each charge row has ≥ 1 accepted batch/file | 4 |
| DBT-006-S07 | Implement explain resolver SQL at pin (≤ 1,000 charge rows then summarized) | `data/contracts/lineage.json`, SQL | 270 USD fixture traces to exact source files | 3 |
| DBT-006-S08 | Old-publication explainability after new revision | test | Explain at old pin returns old evidence; purged → RESTART_REQUIRED | 2 |
| DBT-006-S09 | Benchmark API query shapes (30-day by service, by account, top-20 warehouses, group showback) | evidence | Warm p95 ≤ 2 s, cold ≤ 10 s on benchmark, or recorded gap with mitigation | 4 |
| DBT-006-S10 | Add volume guard: rows per tenant-day within band; alarm on 10× jump | check model | Seeded 10× widening triggers WARN | 2 |
| DBT-006-S11 | Negative test: reader roles lack RAW/STAGING grants; golden API SQL references only SERVING | test | Pass | 1 |
| DBT-006-S12 | Statement pin retention test (FIN-010 interface) after 30 publications | test | Month partitions intact | 2 |
| DBT-006-S13 | Evidence pack | evidence | Validates | 1 |
Task acceptance:
- [ ] A restricted reader cannot obtain totals that include hidden groups.
- [ ] Every serving table is RAP-protected before any grant; the gate fails otherwise.
- [ ] Current and previous publications both resolve evidence to source files.
- [ ] API query shapes meet the latency target or have a recorded mitigation.

## 5. New tasks required

### DBT-101 — Physical analytical revision and publication design (ADR-014) with live benchmark
Release: R1 · Estimate: 33–47 h · Risk: H · Decisions: D-02, D-05, D-06, D-11, D-12 · Closes: G-DBT-01, G-DBT-02, G-DBT-04, G-DBT-06
Why/where: no task defines the physical model all of DBT-002/004/006, ORC-005/101/105, FIN-001 and API-002 depend on. Starts after INF-008 and SEC-005 design (M1/M2); blocks DBT-002, ORC-005, ORC-101, FIN-001.
Dependency changes: `+INF-008, +SEC-005`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| DBT-101-S01 | Write ADR-014: revisioned partitions + SCD2 map + pinned reads; rejected alternatives with verified dbt-snowflake semantics (merge, delete+insert, append, insert_overwrite, microbatch), table swap, per-tenant tables | `docs/architecture/adr/ADR-014-analytical-revisions.md` | Reviewed by FIN, API, SEC, ORC owners | 4 |
| DBT-101-S02 | Write dataset catalog with grains (hour for query-grain, day for charge/allocation/serving, month for monthly marts), retention, rebuild horizon, policy, clustering | `data/contracts/datasets.yaml` | Every R1 dataset listed; schema-validated | 3 |
| DBT-101-S03 | Write DDL templates for `*_R`, `PARTITION_REVISION`, publication tables (shared with ORC-005) | `data/snowflake/migrations/analytics/V0xx__revisions.sql` | Apply twice no-op in staging | 3 |
| DBT-101-S04 | Implement `revisioned` materialization (DML-only transaction; delete own build rows; ordered insert filtered by workset; register all workset partitions incl. zero-row with HASH_AGG checksum; contract assertion; full-refresh refusal) | `data/dbt/macros/materializations/revisioned.sql` | Retry of same build leaves one copy; zero-row partition registered; contract mutation fails | 4 |
| DBT-101-S05 | Write serving secure view template and internal "current" view | migration template | Pinned query returns exactly one revision per partition | 3 |
| DBT-101-S06 | Attach RAP to all `*_R` and `PY_REV` tables (D-02 body with transformer/publisher exemption); migration asserts `POLICY_REFERENCES` | migration + gate | Every revision table reports a policy | 3 |
| DBT-101-S07 | Allocate `revision_id` from PostgreSQL `platform.analytics_revision_seq` per (build, dataset) | interface doc + planner hook | Monotonic ids across builds | 1 |
| DBT-101-S08 | Write golden pinned-query templates for API-002 | `data/contracts/serving_queries/*.sql` | API-002 contract tests consume them | 2 |
| DBT-101-S09 | Run live benchmark (budget ≤ 200 credits): 100 tenants × 5 accounts × 100k queries/day × 30 days (~1.5B rows) — hourly partition rebuild cost, pinned-read p95 with 1 vs 3 retained revisions, GC delete cost, MERGE alternative write amplification (partitions rewritten); plus pinned-read p95 and map lookup over a synthesized 365-day hour-partition publication map (≈ 4.4M rows, D-11 owner decision) | `docs/evidence/DBT-101/<commit>/benchmark.md` | Numbers recorded (TO VERIFY LIVE items resolved) | 7 |
| DBT-101-S10 | Compare secure vs plain view latency under RAP and decide with Security | evidence | Decision recorded | 2 |
| DBT-101-S11 | Sign-off and publish DDL version | ADR status Accepted | Owners' approvals recorded | 1 |
Task acceptance:
- [ ] ADR-014 accepted with measured write/read/GC numbers.
- [ ] Materialization is retry-idempotent and records zero-row partitions.
- [ ] All revision tables carry a row access policy; full refresh is refused.

### DBT-102 — dbt CI platform: isolated schemas, fixture baseline deferral, TTL, lint, private docs
Release: R1 · Estimate: 22–32 h · Risk: M · Decisions: D-21 · Closes: G-DBT-09, G-DBT-15
Why/where: CI isolation is needed from DBT-002 onward but is currently buried in DBT-005 (fifth in chain). Plugs after DBT-001.
Dependency changes: `+DBT-001, +FND-004, +FND-005, +INF-007`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| DBT-102-S01 | Implement `generate_schema_name`: ci → `CI_PR<nr>_<sha7>_<layer>`; staging/prod → layer | `macros/generate_schema_name.sql` | Compile snapshot tests | 2 |
| DBT-102-S02 | Create workflow with GitHub OIDC → AWS → Snowflake WIF CI user; CI role owns only `BRIDGE_CI` | `.github/workflows/dbt.yml`, INF-008 grants | Select on non-CI DB fails | 3 |
| DBT-102-S03 | Load FND-004 fixtures into CI RAW + ACCEPTED_BATCH + CONFIG with production shapes | `tests/dbt/fixtures/load.py` | Row counts equal fixture manifest | 3 |
| DBT-102-S04 | Build nightly/on-merge baseline `BRIDGE_CI.BASELINE_*`; upload its manifest as deferral state | workflow job | Artifact available to PR jobs | 2 |
| DBT-102-S05 | PR job: `state:modified+ --defer --state baseline/`; full golden E2E when ledger/allocation/serving/macros change | workflow | Change in a ledger macro triggers full E2E | 2 |
| DBT-102-S06 | TTL janitor dropping `CI_PR*` schemas older than 24 h by ownership | scheduled workflow | Janitor cannot drop BASELINE schemas (privilege error recorded) | 2 |
| DBT-102-S07 | Implement lint runner and rules L01–L10 | `tools/dbt_lint/` | Each rule has a failing fixture | 4 |
| DBT-102-S08 | Generate docs from baseline only; host privately with SSO | workflow + TF | catalog.json contains only fixture identifiers; unauthenticated request denied | 2 |
| DBT-102-S09 | Report CI gates to FND-005 dispatcher; compile-only never counts as build PASS | `make validate-task` integration | Skipped live gate → SKIPPED_REQUIRED | 2 |
| DBT-102-S10 | Set CI budget: XS warehouse, 600 s statement timeout, PR p95 ≤ 15 min | config | Measured p95 recorded | 1 |
Task acceptance:
- [ ] CI never reads outside `BRIDGE_CI`; deferral targets the fixture baseline only.
- [ ] Stale CI schemas are removed within 24 h without any risk to baseline or shared schemas.
- [ ] Docs contain no production metadata and are not publicly reachable.

### DBT-103 — Config snapshot consumption and build-context macros (D-04)
Release: R1 · Estimate: 14–22 h · Risk: M · Decisions: D-04, D-16 · Closes: G-DBT-03
Why/where: nothing specifies how dbt reads pinned config per tenant in multi-tenant builds. Plugs after CTL-005 and ORC-101; blocks DBT-003 and ALC tasks.
Dependency changes: `+CTL-005, +ORC-101`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| DBT-103-S01 | Declare CONFIG sources (CONFIG_VERSION, ACCOUNT_MEMBERSHIP, ORGANIZATION, TEAM, ALLOCATION_RULE, TAG_RULE_PREDICATE, RATE_CARD, USAGE_GROUP, BUDGET) with contracts | `models/staging/config/_sources.yml` | Contract matches CTL-005 DDL | 2 |
| DBT-103-S02 | Implement `pinned_config(kind)` (join BUILD_CONFIG_PIN on build/tenant/kind/version), `build_context()`, `accepted_source()` | `macros/build_context.sql` | Compiled SQL contains pin join | 3 |
| DBT-103-S03 | Simulation mode: `pinned_config` reads `SIMULATION_INPUT.*` when BUILD kind = SIMULATION and writes to never-mapped SIM revisions | macro + materialization branch | Simulation output never appears in PUBLICATION_MAP | 3 |
| DBT-103-S04 | Test: config inserted during build invisible; tenant A version never applied to B (colliding rule ids) | fixture | Pass | 2 |
| DBT-103-S05 | Effective-dating test: rule effective 2026-09-15 in version 7 | fixture | Applies to charges dated ≥ 2026-09-15 only | 2 |
| DBT-103-S06 | Draft isolation test: SIMULATION_INPUT rows invisible to normal builds | fixture | Pass | 1 |
| DBT-103-S07 | Record config versions per tenant in PUBLICATION from pins | publisher hook | Publication lists exact versions | 1 |
Task acceptance:
- [ ] Each tenant's rows use exactly its pinned config version; mid-build changes are invisible.
- [ ] Draft/simulation config can never reach a published revision.

### DBT-104 — Schema-breaking model versions with union-view cutover
Release: R2 · Estimate: 10–14 h · Risk: M · Decisions: D-05 · Closes: G-DBT-14 (schema-breaking part)
Why/where: R1 restricts analytical schema changes to additive (expand) changes; breaking changes need versioned relations. Plugs after DBT-004.
Dependency changes: `+DBT-004`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| DBT-104-S01 | Define versioned relation naming (`fct_charge_v2_r`) and dataset ids `fct_charge@2` | `datasets.yaml` | Schema-validated | 2 |
| DBT-104-S02 | Write the internal union view template over storage-level fact versions mapping v1/v2 columns (NULL for absent) — never a serving namespace; REL-103's version namespaces are the R1 serving contract (RECONCILIATION C-21) | migration template | Both branches return identical column list | 3 |
| DBT-104-S03 | Per-tenant cutover via map only (no DDL at cutover) | planner/publisher | Tenant switch is one publication | 2 |
| DBT-104-S04 | Contract phase: drop v1 branch after all tenants cut over and no pins reference v1 | procedure | Drop refused while a pin exists | 2 |
| DBT-104-S05 | End-to-end test with a renamed column | test | Readers never see a mixed schema | 2 |
Task acceptance:
- [ ] A breaking schema change is cut over per tenant without DDL in the publication path.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| DBT-001 | R1 | 28 | 40 |
| DBT-002 | R1 | 34 | 48 |
| DBT-003 | R1 | 28 | 40 |
| DBT-004 | R1 | 34 | 48 |
| DBT-005 | R1 | 34 | 50 |
| DBT-006 | R1 | 34 | 48 |
| DBT-101 | R1 | 33 | 47 |
| DBT-102 | R1 | 22 | 32 |
| DBT-103 | R1 | 14 | 22 |
| DBT-104 | R2 | 10 | 14 |
| **Total R1** | | **261** | **375** |
| **Total R2** | | **10** | **14** |

## 7. Owner questions (only those not already covered by D-01…D-25)

1. Approve per-class RAW retention (financial/metering/billing sources 400 days; query-level and user-bearing sources 90 days), challenging ADR-009's uniform 90-day RAW default, so ledger bugs can be corrected by rebuild across the full 400-day history? — Resolved by D-26 (RECONCILIATION C-02).
2. Approve a one-off central Snowflake benchmark budget (≈ 200 credits) for DBT-101 before FIN model work begins?
3. Accept that R1 analytical schema changes are additive-only (breaking changes wait for DBT-104 in R2)?
4. Who approves shadow-rebuild diff reports that intentionally change customer numbers in open periods (analytics lead alone, or analytics + FinOps)?

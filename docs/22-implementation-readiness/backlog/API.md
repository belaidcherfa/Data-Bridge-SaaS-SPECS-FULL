# API — Implementation-readiness review and production backlog

Canonical contract: [semantic-api.md](../../09-api/semantic-api.md). Tasks reviewed: API-001, API-002, API-003, API-004, API-005, API-006 (plus the API surface implied by UX-002…UX-008, WRK-002…WRK-005, CTL-007, RPT-001 and the 87-screen catalog in [docs/21-ui-ux](../../21-ui-ux/SCREEN_INDEX.md)). Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

Related reviews: [SEC.md](SEC.md) (serving identity, scope grammar, revocation — G-SEC-01/-12/-13 are prerequisites of this file), [FIN.md](FIN.md) (money format G-FIN-19, org-scope leakage G-FIN-25), [UX.md](UX.md), [WRK.md](WRK.md).

## 1. Verdict

The domain is not implementable as specified. The semantic contract states good invariants (registry-only identifiers, bound literals, exact decimals, pinned publication, signed cursor, 15 s deadline, async jobs, Explain), but it gives no registry file format, no query-plan IR, no dimension-compatibility model, no additivity rules, no cursor or token format, no cost-estimation statistics, no error catalogue and no bounded Explain design. The 14-row metric table is a glossary. The 87 screens use **176 metric keys**. About 30 of them need registry metrics that do not exist, and the other ~120 are control-plane counts that need non-registry APIs. There is one structural contradiction. D-12 puts `spend` at billing-bucket grain, but PRD §74 and the explorer drilldown group spend by warehouse, user, database and query hash. Without an explicit "attributed cost + unattributed residual" rewrite, those groupings either fail or silently drop money. The largest risks are: cross-profile leakage in the broker (handled with SEC G-SEC-01), an unbounded Explain, a 15 s deadline that ignores queue time, and exact-percentile promises that D-11 retention cannot keep. Author these before coding: the registry JSON Schemas and the v1 catalog (§3.1), the plan IR, OpenAPI plus the problem-code catalogue, and the sealed-token spec. API-001 can start right after FIN-001; it does not need FIN-009.

## 2. Findings

### G-API-01 · The "registry" has no format, compile model or aggregation semantics
Severity: BLOCKER · Type: GAP
Evidence: `semantic-api.md` says "`packages/semantic_metrics` defines versioned metric IDs, source relation/grain, expression reference, additive behavior…" but gives no schema. The table under it is prose, for example "storage_bytes | Latest or time-weighted snapshot as requested". PRD §71 shows a 7-line YAML example (`aggregation: sum`, `supports:`). The only API-001 data model is "Metric schema defined above".
Why it matters: every engineer or agent will invent a different metric format and a different SQL generator. Non-additive metrics (ratios, percentiles, gauges, distinct counts) will be summed or averaged somewhere (the oracle already warns "p95 … never averaged"). Top-N + Other will be wrong for ratios. No lint can stop an author from declaring `aggregation: sum` on a ratio.
Resolution: the registry is YAML files in `packages/semantic_metrics/{metrics,dimensions,relations}/*.yaml`, validated by JSON Schema draft 2020-12 in `schema/*.schema.json`. A build step compiles them into `data/contracts/metrics.json`, and `registry_version` is the SHA-256 of that compiled artifact. Required metric fields:
- `id`, `version` (integer, bumped on semantic change), `status` (ACTIVE|DEPRECATED|RETIRED), `label_key`/`description_key` (i18n, D-18).
- `unit` {kind: money|credits|bytes|seconds|count|ratio|percent, currency_policy: SINGLE_CURRENCY_REQUIRED|NOT_APPLICABLE}.
- `relation` (serving relation id), `measure` {type: sum|latest|twa|ratio|percentile|count|count_distinct|max; column_ref; numerator/denominator metric refs; p; population filter ref}.
- `additivity` {across_dimensions: all|listed|none, across_time: sum|latest|twa|none}.
- `dimensions` (allowed ids), `filters` (allowed ops per dimension), `required_sources`, `maturity_policy`, `null_policy` (e.g. zero denominator → null ZERO_DENOMINATOR).
- `denominator_scope` (SEC G-SEC-13), `privacy.capability` (e.g. `query.read`), `exactness` per retention tier (EXACT|APPROX_TDIGEST|APPROX_HLL), `substitution` (G-API-02), `deprecation` {replaced_by, migration: EQUIVALENT|PARAM_MAP|MANUAL, map}, `explain_template`.
The compiler turns a validated request into a typed **QueryPlan IR** (§3), and SQL is generated only from the IR. Aggregation rules are fixed in code, not per metric:
- `sum`: SUM at the output grain.
- `ratio`: SUM(numerator) / NULLIF(SUM(denominator), 0) at the output grain; the ratio is never summed.
- `percentile`: PERCENTILE_CONT over eligible rows in the hot tier, or APPROX_PERCENTILE_ESTIMATE(APPROX_PERCENTILE_COMBINE(state)) in the aggregate tier (G-API-04).
- `latest`/`twa` gauges: LAST by time, or Σ(value×seconds)/Σseconds across time, summed across non-time dimensions.
- `count_distinct`: exact in the hot tier, HLL_COMBINE in the aggregate tier.
- Top-N + Other: rank the groups, then **re-aggregate the base measures** for Other. Summing ratios is not allowed.
A registry lint rejects `measure.type=ratio|percentile|count_distinct` with `additivity.across_dimensions≠none`.
Affects: API-001, API-002, API-101, CTL-007, RPT-001, GOV-001, WRK-001.

### G-API-02 · `spend` at billing-bucket grain cannot be grouped by resource dimensions; the explorer needs a conserving metric substitution
Severity: BLOCKER · Type: CONTRADICTION
Evidence: D-12 says "`fct_charge` grain = billing bucket (tenant, organization, scope_kind, account, usage_date UTC, service_type, rating_type, billing_type, currency, is_adjustment) … resource/hour/query detail lives only in attribution bridges". `semantic-api.md` defines spend as "Sum selected `fct_charge.cost_effective`". PRD §74 lists spend dimensions "warehouse, database, schema, object, user, role, application, workload, team, … query hash, dbt project, dbt model". `product.md` requires "Preserve filters when drilling account→service→resource→workload→query". The UX-004 oracle is "Every supported grouping conserves 270".
Why it matters: `SUM(fct_charge.cost_effective) GROUP BY warehouse` is not computable, because the column does not exist at that grain. A naive join to `bridge_charge_attribution` without residual rows loses the unattributed part: the explorer shows warehouse 200 as 140 + 60 only if idle is an explicit row. Cloud services (10) and anything without detail disappear, so "spend by warehouse" totals less than spend by service. That is the silent-drop failure the ledger forbids.
Resolution:
- (1) `spend` declares `dimensions` only at bucket grain (organization, account, scope_kind, service_category, service_type, rating_type, billing_type, currency, is_adjustment, day/week/month, data_status).
- (2) A second metric, `attributed_cost`, reads `serving_attribution_daily`, whose rows come from `bridge_charge_attribution` **including one explicit residual row per parent charge** (`resource_id='__UNATTRIBUTED__'`, `attribution_method='NONE'`). This guarantees Σ attributed_cost by any resource dimension = spend of the same buckets. DBT-006/FIN-003 must emit the residual rows; the dbt test is `sum(attributed) = parent charge` per charge.
- (3) `spend.substitution = {when_dimensions_any_of: [warehouse, database, schema, user, role, workload, dbt_project, dbt_model, query_parameterized_hash, compute_pool, …], use: attributed_cost}`. The planner rewrites and returns `meta.metric_substitution = {requested: "spend", served: "attributed_cost@1", unattributed_row_key: "…"}`, and the UI shows the banner (UX-004-S06).
- (4) Dimensions that have no attribution path are **unsupported** and return 422 `DIMENSION_INCOMPATIBLE` with `supported_alternatives`. Examples: compute cost by database/schema/object (a query touches many objects), and storage by user. They are never invented. ACCESS_HISTORY-based fractional attribution by object is R2 and labelled HEURISTIC.
Affects: API-001, API-002, API-101, DBT-006, FIN-003, FIN-006, UX-004, UX-005.

### G-API-03 · 30 metrics used by the screens are missing from the registry; three definitions contradict the screens
Severity: HIGH · Type: GAP / CONTRADICTION
Evidence: the KPI tables in `docs/21-ui-ux/pages/*.md` contain 176 distinct metric keys (extracted by script). The registry has 14. The mismatches are:
- `queries.md` `p95`: "P95 execution: 18.6 s | Individual query percentile". The same page's query detail shows "12.4 s = 0.4 compile + 0.2 queue + 11.8 execution". The registry has only `query_elapsed_p95`, and elapsed ≠ execution.
- `home.md` `allocation`: "Warehouse allocation 100% = 20,000 allocated / 20,000 absolute source". The registry's `attribution_coverage` says "assigned" without saying assigned to what. Resource attribution, group allocation and tag coverage are three different ratios.
- The UI keys (`warehouse`, `querycompute`, `potential`, …) are not registry IDs (`warehouse_compute_cost`, `query_compute_cost`, `potential_savings`).
Why it matters: every missing metric becomes a page-specific formula in a route handler or in React, which PRD §69 and `product.md` ("Avoid duplicate cost formulas") forbid. The p95 label will show one number computed on a different population.
Resolution: §3.1 is the v1 catalog of 44 metrics (14 existing + 30 new) and §3.3 maps every screen key. New R1 metrics include: `attributed_cost`, `unattributed_cost`, `allocated_cost`, `unallocated_cost`, `allocation_coverage`, `allocation_share`, `tag_coverage`, `workload_classification_coverage`, `query_count`, `failed_query_count`, `query_execution_p95` (EXECUTION_TIME), `query_queued_time_sum`, `bytes_scanned`, `bytes_spilled_remote`, `warehouse_credits` (metering, pre-adjustment), `execution_count`, `failed_execution_count`, `execution_failure_rate`, `execution_wall_time_sum`, `execution_time_sum`, `execution_duration_p95`, `budget_amount`, `budget_actual_to_date`, `budget_remaining`, `run_rate_daily`, `files_loaded`, `bytes_loaded`, `dynamic_table_lag_p95`. R1* (D-20): `ai_tokens`, `ai_request_count`, `ai_cost_per_million_tokens`, `spcs_node_hours` (source TO VERIFY LIVE). `warehouse_utilization` is declared with capability UNSUPPORTED, because the screen shows "—" and the value is never inferred. Coverage definitions are split:
- `attribution_coverage` = Σ|charge amount attributed to a non-residual resource| / Σ|eligible charge|.
- `allocation_coverage(book)` = Σ|allocated to non-UNALLOCATED groups| / Σ|eligible source in book|.
- `tag_coverage(tag_key)` = Σ|cost of resources carrying the tag| / Σ|eligible cost|.
All three have a null denominator → ZERO_DENOMINATOR, and `denominator_scope` is set.
Affects: API-001, UX-003…UX-007, WRK-002…WRK-005, ALC-006, GOV-001.

### G-API-04 · Exact percentiles and distinct counts beyond the 90-day hot tier (D-11) are impossible without mergeable states
Severity: HIGH · Type: GAP
Evidence: `semantic-api.md` says "query_elapsed_p95 | Percentile over individual eligible query elapsed times; not average of daily percentiles". D-11 says "Query-level detail hot for 90 days; query-family × day aggregates … 400 days". The scope-bar presets include 180 and 365 days (`product.md`).
Why it matters: after 90 days the individual rows are gone, so a 365-day p95 can be computed only by averaging daily p95s, which the contract forbids. Example: day A has 100 queries at 1 s and day B has 5 queries at 100 s. The average of the daily p95s is (1+100)/2 = 50.5 s. The true p95 over 105 queries is PERCENTILE_CONT(0.95) → position 0.95×104 = 98.8, which falls between the 99th and 100th values, both 1 s, so p95 = **1 s**. The same problem applies to "distinct users" or "distinct query hashes" across days.
Resolution: the aggregate tier stores `APPROX_PERCENTILE_ACCUMULATE(elapsed_ms)` and `APPROX_PERCENTILE_ACCUMULATE(execution_ms)` per (tenant, account, warehouse, query_parameterized_hash, day), plus `HLL_ACCUMULATE` states for distinct counts. These are t-Digest/HLL states, mergeable with APPROX_PERCENTILE_COMBINE/HLL_COMBINE (VERIFIED, search snippets of docs.snowflake.com/en/sql-reference/functions/approx_percentile_accumulate and …/approx_percentile_combine, 2026-09-27). The registry declares `exactness: {HOT: EXACT, AGGREGATE: APPROX_TDIGEST}`. The planner chooses the tier by `period.start ≥ now − hot_days` and returns `meta.retention_tier` and `meta.exactness`. The UI labels "≈ approximate (t-digest)". The error bound is measured on the fixture in WRK-104, not assumed.
Affects: API-001, API-002, WRK-104, UX-005, WRK-005.

### G-API-05 · The broker session contract is missing: secondary roles, pool keys, session parameters and the post-execution recheck
Severity: HIGH · Type: VENDOR-FACT / GAP
Evidence: ADR-005 says "Pools are keyed by principal and authorization epoch, secondary roles disabled". D-02 has one tenant user holding every profile role. New users default to `DEFAULT_SECONDARY_ROLES=('ALL')` (BCR-1692, generally enabled since 2025 — VERIFIED, search snippet of docs.snowflake.com/en/release-notes/bcr-bundles/2024_08/bcr-1692, 2026-09-27). The API-002 failure list is "pool leaks principal".
Why it matters: under D-02 a session with primary role = profile A also holds the object privileges of every other profile role of the tenant, unless secondary roles are off at the user level **and** asserted per connection. A pool keyed with the epoch also drops all pools on unrelated edits (SEC G-SEC-01).
Resolution: adopt SEC G-SEC-01 (CURRENT_ROLE()-only policies, `DEFAULT_SECONDARY_ROLES=()`, session policy `ALLOWED_SECONDARY_ROLES=()`, content-addressed profile roles, pool key `(env, tenant_user, profile_role)`). The broker adds the following:
- On each checkout it runs `SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_SECONDARY_ROLES()` (cached per connection, re-asserted every 60 s) and discards the connection on any mismatch.
- Session parameters at connect: `QUERY_TAG='bridge:api:<request_id>'` (no names), `TIMEZONE='UTC'`, `WEEK_START=1`, `STATEMENT_TIMEOUT_IN_SECONDS` and `STATEMENT_QUEUED_TIMEOUT_IN_SECONDS` per class (G-API-06), `USE_CACHED_RESULT=TRUE`.
- The compiled SQL is parsed once (sqlglot, logger silenced per G-SEC-14) and must be a single SELECT/WITH with no USE/ALTER/CALL/SET.
- After execution and **before** serialization, the API re-reads `identity.resolve_session()` (SEC Appendix F). If the membership epoch or profile hash changed, it discards the result and returns 409 `SCOPE_CHANGED`.
Affects: API-002, SEC-005, SEC-006, OPS-004.

### G-API-06 · "15-second deadline" and "route to jobs by estimated scan/group cardinality" have no mechanism or statistics
Severity: HIGH · Type: GAP
Evidence: `semantic-api.md` says "15-second query deadline and bounded concurrency; high-cardinality/deep requests route to jobs based on estimated scan/group cardinality". The API-002 failure list is "Planner estimate wrong … client disconnect leaves costly query".
Why it matters:
- A Snowflake STATEMENT_TIMEOUT alone does not bound queue time in a saturated warehouse. The statement can wait in the queue and then run for 15 s.
- The FastAPI worker keeps running after the browser disconnects.
- Without statistics, the planner cannot route before executing, so every heavy request burns 15 s of warehouse time and then fails.
Resolution:
- (1) **Deadline budget** measured from request receipt: admission wait ≤ 2 s (per-tenant semaphore). Snowflake gets `STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = remaining` and `STATEMENT_TIMEOUT_IN_SECONDS = ceil(remaining)`. The client-side watchdog cancels via `SYSTEM$CANCEL_QUERY(sfqid)`, using the connector's async execute + poll so the query ID is known before completion. The API detects disconnects through an ASGI cancellation scope and cancels the broker call. The exact cancel semantics are TO VERIFY LIVE in the API-002-S13 benchmark (cancelled status visible in QUERY_HISTORY, credits consumed).
- (2) **Statistics**: at every publication, ORC writes `ops.serving_partition_stats(tenant_id, dataset, partition_date, revision_id, row_count, bytes)` and `ops.serving_dimension_ndv(tenant_id, dataset, dimension_id, window_days ∈ {7,30,90,365}, ndv_estimate)` to PostgreSQL. These are a few hundred thousand rows of operational metadata, not an analytical mirror (PRD §142), and estimation needs no Snowflake round trip.
- (3) **Estimator**: est_scan_rows = Σ row_count(days in range) × Π filter selectivity (|values|/NDV for `in`, 1 otherwise). est_groups = min(est_scan_rows, Π NDV(dim, window)).
- (4) **Routing thresholds** go in `planner_limits.yaml`, calibrated in OPS-008: sync if est_scan_rows ≤ 50 M ∧ est_groups ≤ 100 k ∧ dims ≤ 4 ∧ range ≤ 366 d ∧ records-mode range ≤ 31 d. A learned guard (EWMA of actual elapsed per plan shape, Redis) forces async when EWMA > 8 s.
- (5) **Response**: with `Prefer: respond-async` (RFC 7240; the UI always sends it) → 202 + job; without it → 422 `QUERY_REQUIRES_ASYNC` carrying the job request body. A deadline hit returns 503 `QUERY_DEADLINE_EXCEEDED` with `Retry-After` and the job suggestion, and updates the EWMA.
Affects: API-002, API-004, OPS-008, ORC-005 (stats writer).

### G-API-07 · Cursor, ETag and pagination are specified by intent only; ETag as described is wrong for this response shape
Severity: HIGH · Type: GAP
Evidence: `semantic-api.md` says "Cursor binds query hash, stable sort tuple, tenant/profile/permission_epoch, publication and expiry with server signature" and "ETag binds publication/query/scope". Every response also carries `request_id` in `meta`.
Why it matters:
- A strong ETag over a body that contains a per-request `request_id` is never byte-identical, which violates RFC 9110 strong validator semantics.
- A signed but unencrypted cursor exposes sort-key values (warehouse names, amounts) in access logs when it is used in `GET /v1/cost?cursor=`.
- No key-rotation rule exists, and no GC rule protects the old publication revision that a cursor pins (D-05 GC).
- `Cache-Control` is unspecified, so financial JSON lands in the browser's disk cache and survives logout.
Resolution:
- (1) **Sealed tokens** (one library, three purposes: `cursor`, `explain`, `export`). Format `bt1.<kid>.<b64url(nonce‖ciphertext‖tag)>`, AES-256-GCM, AAD = `purpose|tenant_id|subject_id`. The plaintext cursor carries {v, tenant_id, subject_id, membership_epoch, profile_hash (SEC G-SEC-12), publication_id, request_hash, metric_versions, sort:[[key,dir]…,["row_key","asc"]], after:[typed values], iat, exp=iat+3600}. The key ring lives in Secrets Manager `bridge/<env>/api/token-keys`, rotated every 30 days, keeping the previous two kids for verification (≥ max token TTL + deploy skew). Instances reload every 5 min.
- (2) **Validation order** (§3 error table): decrypt → unknown kid/tamper/foreign tenant → 400 `CURSOR_INVALID`, with an identical body for all three. Then expired → 410 `CURSOR_EXPIRED` (restart); epoch/profile changed → 409 `SCOPE_CHANGED`; request hash differs → 400 `CURSOR_MISMATCH`; publication retired → 410 `PUBLICATION_RETIRED`.
- (3) **ETag** = weak `W/"<b32(sha256(publication_id|registry_version|request_hash|profile_hash|currency|privacy_mode|schema_version))>"`. It is computed before execution, so a matching `If-None-Match` returns 304 without touching Snowflake, **after** authorization.
- (4) Analytical responses send `Cache-Control: no-store`. The UI stores the ETag with the TanStack entry and revalidates manually.
- (5) **Publication pins**: `ops.publication_pin(tenant_id, publication_id, holder_kind ∈ {CURSOR, JOB, STATEMENT, REPORT, SAVED_SNAPSHOT}, holder_id, expires_at)`. Revision GC (ORC/DBT, D-05) must not drop a revision with a live pin. The default grace for unpinned superseded revisions is 24 h.
Affects: API-003, API-004, API-005, ORC-005, DBT-006, CTL-006, UX-002.

### G-API-08 · Explain This Number must be a lazy, paginated, permission-trimmed tree over existing facts
Severity: HIGH · Type: GAP
Evidence: PRD §87 "Chargeback → Allocation rules → Usage groups → Resources → Canonical ledger → Raw Snowflake source → source batch/file". API-005 "Trace fixture chargeback amount through allocation to 270 source ledger". AUDIT X-33 "Materializing that lineage per number is infeasible".
Why it matters: a monthly Finance statement line (12,000 in the UI fixture) aggregates every attributed query of the month. That is millions of rows, tens of thousands of hourly buckets and thousands of files. A materialized lineage per displayed number would dwarf the ledger. An eager API response would time out, and naive permission filtering would reveal hidden groups through child counts.
Resolution: store **no per-number lineage**. Explain is computed on demand from facts that already exist at the pinned publication:
- statement lines (ALC-008), allocation results with (rule_version, method, weight numerator/denominator) (ALC-005)
- `serving_attribution_daily` (charge → resource, with residual)
- `fct_charge` (billing bucket, source_key/revision)
- `charge_source_set(charge_id, source_view, batch_id, row_count, min_ts, max_ts, checksum)` (DBT-006; one row per charge × contributing batch, not per source row)
- the batch → file manifest in PostgreSQL (ING).
Node schema and edges are in §3. Rules:
- (a) `GET /v1/explain/{ref}` returns the root: the value is recomputed at the pinned publication, and the oracle is root.amount = displayed amount.
- (b) `GET /v1/explain/nodes/{node_ref}/children?cursor&limit≤50` sorts by |amount| desc, then node key. Each page carries a `REMAINDER` node = parent − Σ(children so far), so any partial expansion still adds up.
- (c) Children are read through the broker under the caller's profile role, so row policies apply. A `RESTRICTED_REMAINDER` = parent.amount − Σ visible children is shown **without count, names or IDs**. This is safe only because the parent amount was itself authorized. If the parent is not readable (G-SEC-13 denominator scope), the node is `UNAVAILABLE(DENOMINATOR_OUTSIDE_SCOPE)`. The same rule applies to allocation weights. A group-scoped reader expanding their statement line sees the method and their own basis (8,400), but not the denominator (14,000) or the shared parent charge (6,000), because 14,000 − 8,400 would reveal the hidden group's 5,600. Disclosing denominators to chargeback recipients is a tenant policy switch, off by default.
- (d) Leaves: `QUERY_SET` exists only while the hot tier retains the queries; afterwards it becomes `UNAVAILABLE(RETENTION_EXPIRED)`. `FILE_SET` shows file count, byte count, checksums and batch IDs. It never shows S3 URLs.
- (e) Limits: depth ≤ 8, a cycle guard on the node-identity path inside the token, ≤ 20 expansions/min per user.
- (f) Statement-pinned publications stay explainable for as long as the statement is retained (FIN-010 pin). A retired unpinned publication returns 410 with a link to the current value.
Affects: API-005, ALC-005, ALC-008, DBT-006, FIN-010, ING (manifest API), UX-104.

### G-API-09 · Exports have no owner, no limits and a heuristic formula-injection rule
Severity: HIGH · Type: GAP
Evidence: `semantic-api.md` says "CSV/PDF/PNG export uses the same semantic query and report service; async result count/size bounds and formula-injection protection apply". No task owns interactive export: RPT-002 renders scheduled reports, and UX-004 "export" reuses an API that does not exist. The prototype's `csvCell()` (`prototypes/finops-react/src/data/financial.ts`) escapes by value pattern (`/^[\s\u0000-\u001f]*[=+@-]/` unless the value "looks numeric") over **display strings**.
Why it matters:
- A value-based heuristic exports rounded, locale-formatted strings, which breaks exact money.
- It lets text such as `+1,2` through.
- It misses full-width `＝＋－＠`.
- With no bounds, a 50-million-row explorer export is attempted in an HTTP worker.
Resolution: new task **API-102**.
- Same request → planner → broker path (records or aggregate mode). Sync CSV only if est_rows ≤ 10,000 and ≤ 5 MB; otherwise an async job (API-004) writes gzip CSV parts to S3 `exports/<tenant>/<job>/` (KMS, 7-day lifecycle), capped at 1,000,000 rows / 250 MB compressed; above that → 422 `EXPORT_TOO_LARGE` with a narrowing hint.
- **Type-driven escaping**: numeric/decimal columns are emitted raw from the decimal string and validated by `^-?\d+(\.\d+)?$`. Text columns are prefixed with `'` when the first non-whitespace character ∈ {`=`,`+`,`-`,`@`,`\t`,`\r`,`＝`,`＋`,`－`,`＠`}, then RFC 4180-quoted.
- The ZIP contains `data.csv` plus `manifest.json` (request, publication_id, metric versions, coverage, row count, SHA-256).
- Downloads go through `GET /v1/exports/{id}/download`, which re-authorizes and then redirects to a 30 s presigned URL (SEC Appendix F).
- PNG/PDF (R2) render through the RPT-002 isolated worker from the same stored result snapshot, never from a screenshot of the user's browser.
Affects: API-102, API-004, RPT-002, UX-104, UX-004.

### G-API-10 · Entity detail, record listings and dimension-value autocomplete are not in any task
Severity: HIGH · Type: GAP
Evidence: UX-005 "Warehouse/query endpoints use serving data and bounded drilldown". PRD §76 query columns (query_id, hash, cost, credits, warehouse, user, role, … spill, tables, query_tag). `product.md` says "a restricted user cannot discover hidden resources through autocomplete/counts". The planner in API-002 is aggregate-only.
Why it matters: query detail, execution explorer, billing ledger, dbt invocation lists, task runs and the scope-bar account picker all need record-level or dictionary reads. Built ad hoc per page, they will bypass the registry, the pagination and the non-enumeration rules.
Resolution: new task **API-104**.
- `POST /v1/analytics/records` over allowlisted record datasets: `billing_ledger`, `query_executions` (hot tier only), `model_executions`, `dbt_invocations`, `pbi_activities`, `task_graph_runs`, `dt_refreshes`, `storage_objects`. Each has registry-declared columns, filters and sort, keyset pagination, and `privacy.capability` gating (for example `sql_text` requires `query.sql.read` and privacy mode FULL).
- `GET /v1/entities/{kind}/{opaque_id}` for attributes and capability flags. IDs are internal durable UUIDs (DBT-003), and queries use `(account_uuid, snowflake_query_id)`.
- `GET /v1/dimensions/{id}/values?q=&limit≤20` executes through the broker under row policies. Minimum prefix is 2 characters for high-cardinality dimensions. It returns no total count, only `has_more`, and is rate limited to 10/s per user.
- Unknown, foreign and unauthorized IDs all take the same broker lookup path and return an identical 404 body, which also avoids a timing oracle.
Affects: API-104, UX-002, UX-004, UX-005, WRK-002…WRK-004.

### G-API-11 · Public API credentials: Cognito M2M economics and revocation semantics change the design
Severity: MEDIUM · Type: VENDOR-FACT
Evidence: API-006 "credential secret is Cognito-managed/rotated". Vendor facts:
- M2M is billed per successful token request, $2.25 per 1,000, tiered. The per-app-client monthly fee was removed in Nov 2025 — VERIFIED (search snippets of aws.amazon.com/about-aws/whats-new/2025/11/amazon-cognito-removes-machine-machine-app-client-price-dimension and aws.amazon.com/cognito/pricing, 2026-09-27).
- The token endpoint client_credentials quota is 150 RPS — VERIFIED (search snippet of docs.aws.amazon.com/cognito/latest/developerguide/quotas.html, 2026-09-27).
- Scopes per app client are limited to 50 (re:Post, 2026-09-27). The per-resource-server scope limit is TO VERIFY LIVE.
- Client-credentials grants return no refresh token, so there is nothing to revoke in Cognito and an issued access token stays valid until it expires.
Why it matters:
- A customer script that fetches a token per call at 1 req/s costs 86,400 × 30 / 1000 × $2.25 ≈ **$5,832/month**, billed to Bridge. A client caching a 60-minute token costs 720 × $2.25/1000 ≈ $1.62/month.
- Per-tenant Cognito scopes (`tenant-<uuid>/read`) would exhaust scope limits.
- "Revoked client denied" (the oracle) cannot rely on Cognito.
Resolution:
- Cognito scopes express **capabilities only** (`analytics.read`, `explain.read`, `jobs.write`, `jobs.read`, `exports.read`). Tenant and data scope come from `identity.machine_client(client_id PK, tenant_id, profile_hash, capabilities[], status, expires_at, …)` in PostgreSQL, so the tenant is never taken from a scope string.
- The status check runs on every request, so revocation is immediate.
- Access-token validity is 60 min. The generated SDKs cache the token until `exp − 60 s`.
- A cost guard counts token issuance per client from Cognito logs/CUR (TO VERIFY LIVE which log source exposes client_id) and alarms at > 200 tokens/client/day. An optional AWS WAF rate-based rule on the token endpoint is keyed on the Authorization header (TO VERIFY LIVE that WAF association covers the token endpoint).
- Rotation = successor client + ≤ 7-day overlap + revoke. No native-rotation dependency is assumed.
Affects: API-006, SEC-008 (audit), LCH-001 (api_clients quota, D-17).

### G-API-12 · Interactive analysis jobs should not be Dagster runs
Severity: MEDIUM · Type: RISK (challenges `semantic-api.md` "an outbox schedules Dagster" and the API-004 dependency on ORC-006)
Evidence: `semantic-api.md` says "PostgreSQL stores definition/status/…, Snowflake stores results; an outbox schedules Dagster". PRD §140 says "API → job record → Dagster/Python worker → Snowflake result table". D-07 moved extraction away from one Dagster run per unit of work for scale reasons.
Why it matters:
- A Dagster run launched on ECS adds tens of seconds of launch latency per user-triggered analysis (TO VERIFY LIVE; typical ECS run-launcher cold start).
- It adds per-run event-log rows to the Dagster database for interactive traffic, and it couples user-facing latency to orchestrator health during backfills.
- Analysis jobs need neither assets nor lineage.
Resolution: an `analysis-worker` ECS service (Python) consumes the outbox relay queue (SQS), claims the job with the CTL-004 fenced lease, and submits the compiled plan to the broker's `JOB` class. That class uses the serving jobs warehouse, a 1,800 s statement timeout, and async execute + poll. The result is written server-side (INSERT … SELECT into `SERVING_JOBS.JOB_RESULT`, §3). Dagster stays for scheduled/batch work. PRD §140 already allows a "Python worker". Dependency −ORC-006, +INF-005.
Affects: API-004, ORC-006, INF-005, OPS-008.

### G-API-13 · The active tenant must be a per-request selector, not session state (multi-tab cross-tenant rendering)
Severity: HIGH · Type: GAP
Evidence: `semantic-api.md` says "Tenant is derived from authenticated active membership". `security.md` says "Invalidate principal pools and browser caches on tenant switch/logout". The BFF uses one opaque session cookie shared by all tabs. UX-002 oracle: "Switch A→B shows no A rows even briefly".
Why it matters: if the server stores an "active tenant" in the session, then after a switch in tab 2, tab 1 (still showing tenant A labels, URL and cached filters) sends its next request and receives tenant B data. The labels say A and the numbers are B. No cache-clearing rule in one tab can fix a server-side state change made by another tab.
Resolution:
- The tenant is a **selector on every request**: header `X-Bridge-Tenant: <tenant_uuid>`, mirrored by the route prefix `/t/{tenant_slug}/…`. It is authorized per request against durable membership (`identity.resolve_session()`). There is no active-tenant field in the session.
- Every response echoes `meta.tenant_id`. The UI fetch wrapper drops any response whose `meta.tenant_id` ≠ the requesting key's tenant (UX-002-S02).
- Machine clients are bound to exactly one tenant, and a mismatching header returns 403.
- This does not contradict "not accepted as an authorization claim": the header selects among the tenants the subject is a member of and grants nothing.
Affects: API-003, UX-002, SEC-006, SEC-002.

### G-API-14 · `currency`, comparison and maturity parameters have undefined semantics
Severity: MEDIUM · Type: AMBIGUITY
Evidence: the request example has `"currency": "USD"`. The ledger says "Never sum EUR and USD … unless a customer-approved, versioned FX dataset is configured". `product.md` says "Comparison aligns complete equivalent periods and explicitly marks a partial current period" and "maturity filter".
Why it matters: `currency: "USD"` can mean "filter USD rows", which silently drops EUR accounts, or "convert", which needs FX that R1 lacks. A comparison of a partial current month against a full prior month overstates declines. The maturity filter hides recent days.
Resolution:
- `currency` is a **filter**. If the authorized scope contains more than one currency and no `currency` is given, the planner forces `currency` into the dimensions and never returns a single money total (422 `CURRENCY_MIXED` only for top-level scalar tiles). Excluded currencies are listed in `meta.warnings[CURRENCY_EXCLUDED]` with amounts per currency. FX display is R2.
- `compare: {mode: PREVIOUS_PERIOD|SAME_PERIOD_LAST_YEAR|CUSTOM, period}` runs both at the same publication. The server returns `delta` and `delta_pct` (null when base = 0) and `comparison_status` ∈ COMPLETE|PARTIAL_CURRENT|BASE_INCOMPLETE|UNAVAILABLE. By default the current period is truncated to its last complete UTC day and the base is aligned to the same length.
- `maturity: ALL|FINAL_OR_BETTER|RECONCILED_ONLY` adds `meta.coverage.excluded_by_maturity`.
Affects: API-002, API-003, UX-002, UX-004.

### G-API-15 · Metric versioning and saved-view migration need rules, not intent
Severity: MEDIUM · Type: GAP
Evidence: `semantic-api.md` says "Maintain compatible metric versions for saved views/reports; deprecations have migration instructions". API-006 oracle "unsupported metric version returns migration guidance". CTL-007 "Validate saved filters/metrics against registry version".
Why it matters: without a rule for what bumps a version, a formula fix changes every saved report silently. Without a support window, retiring a version breaks scheduled reports in the middle of the month.
Resolution:
- Any change to population, formula, unit or null policy is a **semantic change** and requires `version+1`. Label or description changes do not.
- Deprecated versions are served for ≥ 6 months, or until their relation is retired. The response carries `meta.warnings[METRIC_DEPRECATED]{replaced_by, sunset}`.
- Auto-migration of saved views/reports happens only for `migration: EQUIVALENT|PARAM_MAP`. MANUAL migrations mark the saved object `needs_review` and keep serving the old version until sunset.
- After sunset the API returns 410 `METRIC_VERSION_RETIRED` with `{replaced_by, migration}`.
- `migrate_saved_query(query, registry)` is a pure function shared by CTL-007, RPT-001, GOV-003 and the API.
Affects: API-001, API-006, CTL-007, RPT-001, GOV-003.

### G-API-16 · Dependency edges are over-serialized, one is missing, and one runs the wrong way
Severity: MEDIUM · Type: GAP
Evidence: task-index.json: API-001 ← FIN-009, DBT-006; API-004 ← ORC-006; API-005 ← FIN-010; API-006 ← API-005; GOV-003 ← API-006; WRK-001 ← API-001; CTL-007 (M1) validates saved views "against registry version" but has no edge to API-001 (M5); UX-002 ← API-003.
Why it matters: API-001 sits on the 73-task critical path (AUDIT X-05), yet the registry format and the v1 catalog need only the charge schema (FIN-001) and the dbt model-contract conventions (DBT-001). CTL-007 cannot implement its own first micro-task.
Resolution:
- API-001: −FIN-009, −DBT-006, +FIN-001, +DBT-001. Binding and certification against live serving views move to the new API-101 (← DBT-006, FIN-009, SEC-005).
- API-004: −ORC-006, +INF-005.
- API-005: split the statement-line explain (needs FIN-010/ALC-008) from charge-level explain (needs only DBT-006). Keep FIN-010 as a live-gate dependency only.
- API-006: −API-005.
- CTL-007 +API-001.
- GOV-003 −API-006 (the lead has already recorded this).
- WRK-001 −API-001.
- UX-002 depends on API-003's OpenAPI contract to build, and on live API-003 only for its staging gate.
Affects: API-001, API-004, API-005, API-006, CTL-007, GOV-003, WRK-001, UX-002.

### G-API-17 · The cache key uses a per-dataset version, but a response spans datasets and must be publication-consistent
Severity: MEDIUM · Type: AMBIGUITY
Evidence: `control-plane.md` gives the key `bridge:v1:{environment}:{tenant}:{profile}:{permission_epoch}:{dataset}:{dataset_version}:{metric_version}:…`. PRD §64 gives `finops:{tenant}:home:{period}:{filters_hash}`, which has no profile. D-05 has a per-tenant publication map.
Why it matters: a Home batch reads charges, budgets and insights. Keying by one `dataset_version` can serve a cached charge tile from publication N next to a budget tile from N+1, which is exactly the mixed-version display `product.md` forbids. PRD §64's key would share cached aggregates across profiles of the same tenant. The CTL contract fixes that, but the PRD example must not be copied.
Resolution: the analytical cache key replaces `{dataset}:{dataset_version}` with `{publication_id}`, the per-tenant publication-map version that pins every dataset at once. `{permission_epoch}` becomes `{profile_hash}`, following SEC G-SEC-01/-12, because content-addressed profiles make the epoch unnecessary in data keys. CTL-006 keeps the key builder. API-003-S10 uses it.
Affects: CTL-006, API-003.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by (task/micro-task) |
|---|---|---|
| `packages/semantic_metrics/schema/{metric,dimension,relation,join_path}.schema.json` | JSON Schema 2020-12 with the fields listed in G-API-01. Enums are closed. `$comment` references the canonical contract section. | API-001-S01 |
| `packages/semantic_metrics/relations/*.yaml` | Serving relations: `v_charge_daily` (D-12 grain), `v_attribution_daily` (charge→resource/workload with residual rows), `v_allocation_daily` (book, group, method, rule_version), `v_query_exec` (hot, 90 d), `v_query_family_daily` (aggregate tier with t-digest/HLL states), `v_storage_daily` (bytes by class; latest/twa), `v_budget_daily`, `v_forecast`, `v_insight_summary`, `v_workload_exec` (invocations/activities/task runs), `v_charge_source_set`. Each has grain keys, time column, tenant column, publication binding and policy name (from SEC-005). | API-001-S03 (names agreed with DBT-006) |
| v1 metric catalog (§3.1) | 44 YAML files with populations and null policies | API-001-S04…S06 |
| Dimension catalog (§3.2) | ~38 YAML files: type, cardinality class, entitlement flag, pii flag (D-10), hierarchy, autocomplete flag | API-001-S07 |
| QueryPlan IR `schema/query_plan.schema.json` | `{plan_version, tenant_id, subject_id, profile_hash, membership_epoch, publication_id, registry_version, mode: AGGREGATE\|RECORDS, class: INTERACTIVE\|JOB, period:[start,end), grain, metrics:[{id,version,relation,measure}], dimensions:[{id,column_ref,join_path}], filters:[{dimension,op,param_refs}], params:{p1:typed value}, compare?, top_n?, sort:[…,row_key], limit, keyset_after?, currency_rule, maturity, privacy_mode, substitution?, tier: HOT\|AGGREGATE, exp, sig}` — signed with Ed25519 (API signing key in Secrets Manager; broker holds the public key); canonical JSON = RFC 8785 | API-002-S03, S06 |
| OpenAPI 3.1 `docs/api/openapi.yaml` | Paths: `POST /v1/analytics/query`, `POST /v1/analytics/batch` (≤12 items, one publication), `GET /v1/cost`, `POST /v1/analytics/records`, `GET /v1/dimensions/{id}/values`, `GET /v1/entities/{kind}/{id}`, `GET /v1/metrics`, `GET /v1/dimensions`, `GET /v1/me/context`, `GET /v1/publications/current`, `POST/GET /v1/analysis-jobs`, `GET /v1/analysis-jobs/{id}`, `POST /v1/analysis-jobs/{id}/cancel`, `GET /v1/analysis-jobs/{id}/result`, `GET /v1/explain/{ref}`, `GET /v1/explain/nodes/{ref}/children`, `POST /v1/exports`, `GET /v1/exports/{id}`, `GET /v1/exports/{id}/download`, `GET/POST /v1/machine-clients`, `POST /v1/machine-clients/{id}/rotate`, `POST /v1/machine-clients/{id}/revoke` | API-003-S01 (skeleton), extended by API-004/005/102/104/006 |
| Response meta JSON Schema `packages/api_contracts/meta.schema.json` | `{request_id, api_version, tenant_id, scope:{organization_ids, account_ids, summary_key}, publication_id, publication_as_of, registry_version, metric_versions:{id:int}, source_as_of:[{source_id, complete_through}], materialized_at, data_status:{overall, composition:{PROVISIONAL:dec,FINAL:dec,RECONCILED:dec}}, reconciliation_status: PENDING\|MATCHED\|WARNING\|FAILED\|NOT_APPLICABLE, close_status: OPEN\|CLOSED\|RESTATED\|NOT_APPLICABLE, coverage:{source_ratio, attribution_ratio, missing_sources:[…], excluded_by_maturity}, price_basis:[…], currency, retention_tier, exactness, metric_substitution?, comparison_status?, totals:{metric:dec\|null}, null_reasons_totals?, planner:{route, est_rows_bucket}, warnings:[{code, params}], page:{limit, next_cursor, has_more}, explain:{query_token}}` | API-003-S01 |
| Value encoding | Decimal = JSON string `^-?(0\|[1-9]\d*)(\.\d{1,12})?$`, no exponent, no `-0`, at least minor-unit digits for money (G-FIN-19). Row = `{key, dims:{…}, values:{metric: dec\|int\|null}, null_reasons:{metric: NullReason}}`. `NullReason` enum: PRICE_UNKNOWN, SOURCE_MISSING, SOURCE_NOT_ENABLED, ATTRIBUTION_UNAVAILABLE, CAPABILITY_UNSUPPORTED, ZERO_DENOMINATOR, DENOMINATOR_OUTSIDE_SCOPE, RETENTION_EXPIRED, PRIVACY_SUPPRESSED, NOT_APPLICABLE_SCOPE, INSUFFICIENT_HISTORY, CURRENCY_EXCLUDED | API-003-S01/S02 |
| Problem catalogue `packages/api_contracts/problems.yaml` | RFC 9457 `application/problem+json` with the CTL fields `code, message, request_id, retryable, field_errors`. Codes/status: VALIDATION_FAILED 422, METRIC_UNKNOWN 422, DIMENSION_INCOMPATIBLE 422, CURRENCY_MIXED 422, RANGE_TOO_LARGE 422, QUERY_REQUIRES_ASYNC 422, EXPORT_TOO_LARGE 422, METRIC_VERSION_RETIRED 410, CURSOR_INVALID 400, CURSOR_MISMATCH 400, CURSOR_EXPIRED 410, PUBLICATION_RETIRED 410, SCOPE_CHANGED 409, RESULT_SCOPE_CHANGED 409, IDEMPOTENCY_KEY_REUSED 409, ALREADY_COMPLETED 409, FORBIDDEN 403, NOT_FOUND 404 (non-enumerating), TENANT_BUSY 429, RATE_LIMITED 429, QUOTA_EXCEEDED 429, QUERY_DEADLINE_EXCEEDED 503, UPSTREAM_UNAVAILABLE 503 | API-003-S01 |
| Sealed-token spec `docs/09-api/tokens.md` | Format, purposes, AAD, plaintext fields per purpose, TTLs (cursor 1 h, explain 24 h, export link 30 s redirect), key ring JSON, rotation runbook, validation order table (G-API-07) | API-003-S05 |
| `planner_limits.yaml` | deadline_ms 15000; admission_wait_ms 2000; tenant_interactive_concurrency 4; principal_interactive_concurrency 2; sync_max_range_days 366; sync_max_dims 4; sync_max_rows 500; sync_max_est_scan_rows 5e7; sync_max_est_groups 1e5; records_sync_max_range_days 31; ewma_async_ms 8000; batch_max_items 12; tenant_heavy_jobs 2; principal_heavy_jobs 1; machine_max_heavy_jobs_per_tenant 1; job_timeout_s 1800; job_result_ttl_days 7; export_sync_max_rows 10000; export_max_rows 1e6; export_max_bytes_gz 250 MB | API-002-S05, API-004-S03, API-102-S02 |
| PG DDL `ops.serving_partition_stats`, `ops.serving_dimension_ndv`, `ops.publication_pin`, `analytics.analysis_job`, `analytics.export_job`, `identity.machine_client` | Keys, FKs incl. tenant_id, FORCE RLS, indexes (tenant_id, status, created_at) | API-002-S05, API-003-S08, API-004-S02, API-102-S01, API-006-S01 |
| Snowflake DDL `SERVING_JOBS.JOB_RESULT` | `(tenant_id, job_id, attempt, row_num, row_key, dims VARIANT, vals VARIANT, created_at)`, insert granted to profile roles, row access policy (tenant user + job's profile role), clustered by (tenant_id, job_id), purge after TTL | API-004-S04 (with SEC-005) |
| Analysis job state machine | QUEUED→RUNNING→{SUCCEEDED, FAILED, CANCELLED}; RUNNING→CANCEL_REQUESTED→CANCELLED; SUCCEEDED→EXPIRED; guards = lease token + expected status (CAS) | API-004-S01 |
| Explain node schema `data/contracts/explain.json` | `{node_ref, kind ∈ METRIC\|FORMULA_OPERAND\|STATEMENT_LINE\|ALLOCATION_RULE\|GROUP\|RESOURCE\|CHARGE\|ATTRIBUTION_SET\|QUERY_SET\|SOURCE_BATCH\|FILE_SET\|RATE\|CONFIG_VERSION\|REMAINDER\|RESTRICTED_REMAINDER\|UNAVAILABLE, label_key, label_params, amount:dec\|null, currency, unit, role (e.g. PARENT_CHARGE, ALLOCATED_SHARE, RESIDUAL), method, weight:{numerator, denominator}, rule_ref:{ruleset_version, rule_id, rule_version}, evidence_ids[], maturity, coverage, has_children, null_reason}` + edge table (parent kind → child kinds → resolver) | API-005-S01 |
| Machine-client and rate-limit policy | Capabilities list, default limits (per client 5 req/s burst 10 for analytics, 1 heavy job; per tenant 20 req/s), headers (Retry-After normative; RateLimit/RateLimit-Policy per IETF draft informative), deprecation headers (`Deprecation` RFC 9745, `Sunset` RFC 8594, `Link rel=deprecation`) | API-006-S01, S05, S07 |

### 3.1 v1 metric catalog (registry content to author)

`R1*` = conditional on D-20. "Tier" = exactness in HOT / AGGREGATE tier.

| Metric id | Relation | Measure / population | Additivity | Release |
|---|---|---|---|---|
| spend | v_charge_daily | SUM(cost_effective), measure_role=CHARGE, selected revision | all dims of relation; substitution→attributed_cost | R1 |
| billed_credits | v_charge_daily | SUM(effective_credits) where rating_type credit-rated; non-credit rows excluded, reported in coverage | all | R1 |
| warehouse_compute_cost | v_charge_daily | spend where service_type ∈ warehouse metering types | all | R1 |
| warehouse_credits | v_attribution_daily | SUM(credits_used_compute) from WMH (operational, pre-adjustment) | all | R1 |
| query_compute_cost | v_attribution_daily | SUM(amount) where attribution_method ∈ {QAH, QMH}; excludes idle/cloud services | all | R1 |
| idle_cost / idle_credits | v_attribution_daily | method=CLASSIC_IDLE; null CAPABILITY_UNSUPPORTED for Adaptive | all | R1 |
| attributed_cost | v_attribution_daily | SUM(amount) incl. `__UNATTRIBUTED__` residual rows | all | R1 |
| unattributed_cost | v_attribution_daily | amount where resource_id='__UNATTRIBUTED__' | all | R1 |
| attribution_coverage | v_attribution_daily | Σ\|non-residual\| / Σ\|all\|; ZERO_DENOMINATOR; denominator_scope | none (ratio) | R1 |
| allocated_cost | v_allocation_daily | SUM(allocated_amount) per book | all within one book; book required | R1 |
| unallocated_cost | v_allocation_daily | group='__UNALLOCATED__' | within book | R1 |
| allocation_coverage | v_allocation_daily | Σ\|allocated non-UNALLOCATED\| / Σ\|eligible source\| | none | R1 |
| allocation_share | v_allocation_daily | group allocated / book total in scope; DENOMINATOR_OUTSIDE_SCOPE | none | R1 |
| tag_coverage | v_attribution_daily ⋈ tag facts | Σ\|cost of resources with tag_key\| / Σ\|eligible\| | none | R1 |
| storage_bytes | v_storage_daily | gauge: latest (default) or twa over time; sum across databases/classes | across_time latest/twa | R1 |
| query_count | v_query_exec / v_query_family_daily | COUNT(*) completed; status taxonomy version | all | R1 |
| failed_query_count | same | status ∈ failed set | all | R1 |
| query_failure_rate | same | failed / (succeeded+failed), cancelled excluded; versioned taxonomy | none | R1 |
| query_elapsed_p95 | same | p95 TOTAL_ELAPSED_TIME; tier EXACT/APPROX_TDIGEST | none | R1 |
| query_execution_p95 | same | p95 EXECUTION_TIME (label "execution") | none | R1 |
| query_queued_time_sum | same | Σ(QUEUED_OVERLOAD_TIME+QUEUED_PROVISIONING_TIME) | all | R1 |
| bytes_scanned / bytes_spilled_remote | same | Σ; spill columns capability-gated on source projection (AUDIT X-32) | all | R1 |
| workload_classification_coverage | v_attribution_daily ⋈ workload | Σ\|query compute with workload_type≠UNKNOWN\| / Σ\|query compute\| | none | R1 |
| execution_count | v_workload_exec | COUNT DISTINCT verified execution_id (invocation, activity, graph run, DT refresh) | none (count distinct); HLL in aggregate tier | R1 |
| failed_execution_count / execution_failure_rate | v_workload_exec | executions with any failed leaf / executions | count: none; rate: none | R1 |
| execution_wall_time_sum | v_workload_exec | Σ over complete executions of (max(end)−min(start)) | sum across executions only | R1 |
| execution_time_sum | v_workload_exec | Σ query execution time of leaves | all | R1 |
| execution_duration_p95 | v_workload_exec | p95 of per-execution wall time | none | R1 |
| budget_amount | v_budget_daily | plan amount prorated by declared calendar policy | within budget | R1 |
| budget_actual_to_date | v_budget_daily | spend in budget scope over complete days | within budget | R1 |
| budget_remaining | derived | budget_amount − budget_actual_to_date (may be negative) | none | R1 |
| budget_variance (+ _pct) | derived | actual − budget; pct null if budget = 0 | none | R1 |
| forecast_total | v_forecast | actual-to-date + modeled remaining; method/interval in meta | none | R1 |
| forecast_variance (+ _pct) | v_forecast | forecast − budget; pct null if budget = 0 | none | R1 |
| run_rate_daily | v_budget_daily | actual / complete days; INSUFFICIENT_HISTORY if < 3 complete days | none | R1 |
| potential_savings | v_insight_summary | deduplicated compatible opportunities; range low/high | never added to realized | R1 |
| realized_savings | v_insight_summary | verified normalized savings; negative allowed | across non-overlapping actions | R1 |
| files_loaded / bytes_loaded | v_attribution_daily (pipe detail) | Σ from pipe usage detail | all | R1 |
| dynamic_table_lag_p95 | v_workload_exec (DT refresh) | p95 of (refresh end − data_timestamp) | none | R1 |
| ai_tokens / ai_request_count | v_attribution_daily (AI detail) | Σ native units by family; null when the unit is not emitted | all | R1* |
| ai_cost_per_million_tokens | derived | cost / tokens × 1e6 at same grain; null when tokens null | none | R1* |
| spcs_node_hours | v_attribution_daily (SPCS) | TO VERIFY LIVE source availability; else CAPABILITY_UNSUPPORTED | all | R1* |
| warehouse_utilization | — | always null CAPABILITY_UNSUPPORTED in R1 | — | R1 (declared) |

### 3.2 v1 dimension catalog

Time: `day`, `week` (ISO, Monday), `month` (UTC calendar).
Billing grain: `organization`, `account`, `region`, `cloud`, `scope_kind`, `service_category`, `service_type`, `sub_service`, `rating_type`, `billing_type`, `currency`, `is_adjustment`, `data_status`, `price_basis`.
Resource: `warehouse`, `warehouse_type` (CLASSIC|ADAPTIVE), `warehouse_size`, `database`, `schema` (storage only), `compute_pool`, `spcs_service`, `pipe`, `task`, `dynamic_table`, `ai_family`, `ai_model`, `storage_class`.
Actor: `user` (pseudonym per D-10, resolved to a name only with `people.read`), `role`, `client_application`.
Workload: `workload_type`, `workload` (project/application), `environment`, `dbt_project`, `dbt_model`, `dbt_resource_type`, `pbi_mode`, `query_parameterized_hash` (high cardinality → async beyond 31 d).
Ownership: `group_set`, `group` (usage group; entitlement dimension), `book`, `allocation_method`, `tag` (key=value, R1 via group sets).
Not supported for compute cost in R1: `object`, `schema`, `database` (G-API-02).

### 3.3 Screen metric keys → API source (all 176 keys)

| Screen keys (docs/21-ui-ux/pages) | Serve from |
|---|---|
| spend, accountcost, orgnet, storage, serverless, cortex, spcs, taskcost, pipecost, otherServerless, aifunctioncost, aisearchcost, aianalystcost, appfees | `spend` + filters (scope_kind, service_category, service_type, sub_service) |
| warehouse | `warehouse_compute_cost` |
| querycompute, eligible, dbtcost, pbicost, runcost, modelcost, pbiactivitycost | `query_compute_cost` + workload/execution filters |
| idle | `idle_cost` |
| analyticsstorage, spcsservicecost, pipelinecost, spcsunallocated | `attributed_cost` / `unattributed_cost` |
| financealloc, marketingalloc, financequery, financeidle, unallocated | `allocated_cost` / `unallocated_cost` (book = Teams) |
| allocation, financeweight, marketingweight, tagcoverage, classified, aicoverage | `allocation_coverage`, `allocation_share`, `tag_coverage`, `workload_classification_coverage`, `attribution_coverage` |
| bytes, retained, timeTravel, failsafe, analyticsbytes | `storage_bytes` by `storage_class` (latest) |
| queries, pbiqueries, pbiquerycount, failed, p95 | `query_count`, `failed_query_count`, `query_execution_p95` |
| dbtruns, modelruns, pbiactivities, runmodels, dbtfail, modelfailure, runduration, pbiduration, modelp95, lag | `execution_count`, `failed_execution_count`, `execution_failure_rate`, `execution_wall_time_sum`, `execution_duration_p95`, `dynamic_table_lag_p95` |
| budget, budgetactual, remaining, burnday, forecast, forecastvariance | `budget_amount`, `budget_actual_to_date`, `budget_remaining`, `run_rate_daily`, `forecast_total`, `forecast_variance` |
| potential, teamopportunity, verifiedsavings | `potential_savings`, `realized_savings` |
| aitokens, aicalltokens, aiexecutions, aifunctioncalls, tokenrate, poolhours | `ai_tokens`, `ai_request_count`, `ai_cost_per_million_tokens`, `spcs_node_hours` (R1*) |
| files, ingested, loadfail, utilization | `files_loaded`, `bytes_loaded`, load-failure records (API-104), `warehouse_utilization` (UNSUPPORTED) |
| dbtmodels, pipelines, poolcount, servicecount, databases, unknown | `GET /v1/dimensions/{id}/values` count semantics (`count_distinct` of a dimension, non-additive) |
| singlequery, duration, queue, rows, runstatus, aicallcost, aiduration | Entity attributes (API-104 `GET /v1/entities/query/…`, `…/ai_request/…`) |
| baseline, postcost, normalized, confidence, insightcount, highconfidence, actionopen, actiondone | INS-006/INS-007 study/action APIs (control plane + Snowflake summary), not registry |
| recon, ledgercompare, invoicecompare, recondelta, reconfailed, conservation | FIN-009 reconciliation/control results API |
| statementtotal, statementcount, statementdraft, close | ALC-008 / FIN-010 statement and close APIs |
| coverage, sources, sourcefailed, lastsync, batchcount, retrycount, watermark, history | ING-012 Data Health API; `history` = GOV-002 forecast metadata |
| budgets/monitors: monitors, incidents, insufficient, silenced, incidentvalue, threshold, occurrences, incidentage | GOV-003/GOV-004/GOV-008 APIs |
| reporttemplates, reportschedules, reportfail, reportready, nextdelivery, dashboardcount, sharedviews, privateviews, widgets | RPT-001…005, CTL-007 APIs |
| tagrules, tagconflicts, unowned, tagmatches, tagbefore, tagafter, groupbooks, groupleaves, groupconflicts, groupmembers | ALC-001…ALC-004 APIs (tagbefore/after = ALC-003 simulation job output) |
| connections, capabilities, destinationcount, integrationissues, accounts, onboardingsteps | CON-004/CON-005/GOV-006/ONB-001 APIs |
| members, teams, roles, auditcount, pendinginvites, sso, mfa, sessions, securityevents, auditactors, auditfail, auditretention, sanitized, rawsql, retention, privacyexceptions, deliverysuccess, deliveryfailed, deliverypending, subscription, billingstatus, billingcontacts, renewal, supportopen, supportresolved | CTL-003, SEC-002…SEC-008, GOV-007, LCH-001, UX-102 APIs |
| unavailable | Null-reason exemplar (not a metric) |

## 4. Revised production backlog

### API-001 — Registry schema, v1 catalog, validator and compiler core
Release: R1 · Estimate: 38–54 h · Risk: H · Decisions: D-05, D-10, D-11, D-12, D-18 · Closes: G-API-01, G-API-02, G-API-03, G-API-04 (registry side), G-API-15
Dependency changes: `−FIN-009` (catalog authored from the ledger contract, certified later in API-101), `−DBT-006` (binding moves to API-101), `+FIN-001` (charge schema), `+DBT-001` (model contract YAML conventions). New dependents: `CTL-007`, `WRK-001` no longer waits (see WRK.md).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| API-001-S01 | Write JSON Schemas for metric, dimension, relation and join_path with closed enums, required fields per G-API-01 and one valid + three invalid examples each | `packages/semantic_metrics/schema/*.schema.json`, `tests/spec/API-001/schema_examples/` | `check-jsonschema` passes valid examples and rejects invalid ones with the expected JSON pointer | 3 |
| API-001-S02 | Implement Pydantic v2 models + loader that validates YAML against the schemas and cross-references (dimension ids exist, relation columns exist in the dbt `manifest.json` column contracts, join paths acyclic) | `packages/semantic_metrics/registry.py` | Loading the fixture registry succeeds; a metric referencing column `cost_efective` fails with `UNKNOWN_COLUMN` naming file:line | 4 |
| API-001-S03 | Author relation YAMLs for the 11 serving relations in §3 (grain keys, time column, tenant column, policy name, publication dataset id, tier) agreed with DBT-006 owners | `packages/semantic_metrics/relations/*.yaml` | Reviewed by DBT/FIN owners; each relation's grain keys are unique in the DBT-005 golden fixture (dbt `unique_combination_of_columns` test green) | 3 |
| API-001-S04 | Author financial metrics: spend, billed_credits, warehouse_compute_cost, warehouse_credits, query_compute_cost, idle_cost/credits, attributed_cost, unattributed_cost, attribution_coverage, allocated_cost, unallocated_cost, allocation_coverage, allocation_share, tag_coverage — populations, null policies, denominator_scope, substitution rule | `metrics/finance/*.yaml` | Lint green; each has label/description i18n keys and `required_sources` | 4 |
| API-001-S05 | Author query/workload metrics: query_count, failed_query_count, query_failure_rate (status taxonomy v1 file), query_elapsed_p95, query_execution_p95, queued/bytes/spill metrics, workload_classification_coverage, execution_* metrics, dynamic_table_lag_p95, files/bytes_loaded, storage_bytes (latest/twa) with `exactness` per tier | `metrics/performance/*.yaml`, `taxonomies/query_status_v1.yaml` | Lint green; percentile metrics declare HOT=EXACT, AGGREGATE=APPROX_TDIGEST | 3 |
| API-001-S06 | Author governance metrics: budget_amount, budget_actual_to_date, budget_remaining, budget_variance(+pct), forecast_total, forecast_variance(+pct), run_rate_daily, potential_savings, realized_savings; R1* AI/SPCS metrics with capability flags; warehouse_utilization as UNSUPPORTED | `metrics/governance/*.yaml`, `metrics/ai_spcs/*.yaml` | Lint green; forecast/budget pct metrics null on budget 0 | 2 |
| API-001-S07 | Author ~38 dimension YAMLs (§3.2) with type, cardinality class (LOW ≤ 100, MED ≤ 10k, HIGH), entitlement flag (account, organization, group_set, group), pii flag (`user` → pseudonym D-10), hierarchy (organization→account; group_set→group), autocomplete flag | `dimensions/*.yaml` | Lint green; every HIGH dimension has `autocomplete.min_prefix=2` | 3 |
| API-001-S08 | Implement the compatibility engine: metric×dimension reachability via relation join paths, substitution rewrite (spend→attributed_cost for resource dims), currency policy, grain derivation (day→week/month), filter-op allowlist; expose `compatible_dimensions(metric)` and `explain_incompatibility()` | `packages/semantic_metrics/compat.py` | Matrix snapshot test: spend×warehouse → SUBSTITUTED(attributed_cost); query_compute_cost×database → INCOMPATIBLE with alternatives [warehouse, workload]; storage_bytes×user → INCOMPATIBLE | 4 |
| API-001-S09 | Implement aggregation builders per measure type (sum, ratio, percentile hot/aggregate, latest/twa, count_distinct exact/HLL) and Top-N+Other that re-aggregates base measures | `packages/semantic_metrics/aggregation.py` | Unit tests: ratio Other = Σnum/Σden of members (not Σ ratios); twa of bytes 10 TB for 20 d + 12 TB for 10 d over 30 d = 10.666… TB; latest = 12 TB | 4 |
| API-001-S10 | Implement versioning: version bump lint (a CI diff that detects semantic field changes without version+1), deprecation metadata, `migrate_saved_query()` pure function for EQUIVALENT/PARAM_MAP/MANUAL | `packages/semantic_metrics/versioning.py`, CI job `registry-diff` | Changing `measure.column_ref` without a version bump fails CI; migrating a saved query using `spend@1` (EQUIVALENT→`spend@2`) returns the rewritten query, and MANUAL returns `needs_review` | 3 |
| API-001-S11 | Build the compiled artifact and generated types: `data/contracts/metrics.json` (hash = registry_version) and TypeScript enums/types for the web (metric ids, dimension ids, NullReason, units) | `data/contracts/metrics.json`, `apps/web/src/generated/registry.ts` | CI regenerates the artifact deterministically (byte-identical on rerun) and fails if the committed copy drifts | 2 |
| API-001-S12 | Implement `GET /v1/metrics` and `GET /v1/dimensions` filtered by caller capabilities, tenant source capabilities (CON-005) and plan entitlements (D-17); dimension values are NOT included | `apps/api/analytics/registry_routes.py` | Viewer without `query.read` does not receive query metrics; tenant without Adaptive warehouses sees `idle_cost` with capability note; response validates against OpenAPI | 3 |
| API-001-S13 | Encode golden oracles on FIN-GOLD-01 as compiler-level tests against DuckDB fixtures of the serving relations: spend=270; warehouse 200 = query 140 + idle 60; spend by warehouse (substituted) + unattributed = 270; USD 270 + EUR 20 without currency dim → CURRENCY_MIXED, with currency → two rows; attribution_coverage with zero denominator → null ZERO_DENOMINATOR; p95 of {100×1 s, 5×100 s} = 1 s, never 50.5 s | `tests/spec/API-001/test_golden.py` | All assertions pass; the DuckDB SQL dialect gap is documented (real Snowflake execution is covered by API-101) | 4 |
| API-001-S14 | Write the registry authoring guide (how to add a metric, versioning rules, review checklist) and update the canonical contract with the file format and the v1 catalog link | `packages/semantic_metrics/README.md`, `docs/09-api/semantic-api.md` (change request via ADR process) | Reviewed by FIN and UX owners | 2 |

Task acceptance:
- [ ] All 44 v1 metrics and ~38 dimensions load and pass the lint, and the compiled artifact is deterministic.
- [ ] The compatibility matrix snapshot is reviewed. Every grouping of `spend` by a resource dimension is SUBSTITUTED with a residual row. The spend × database/schema/object groupings return INCOMPATIBLE.
- [ ] The golden tests prove conservation (270), non-averaged p95 (1 s), zero-denominator null and currency separation.
- [ ] A semantic change without a version bump fails CI.
- [ ] Every screen key in §3.3 maps to a registry metric or to a named non-registry API.

### API-101 — Bind the registry to published serving views and certify it on Snowflake (new, split from API-001)
Release: R1 · Estimate: 24–34 h · Risk: M · Decisions: D-02, D-05, D-12 · Closes: G-API-02 (live), G-API-04 (live)
Dependency changes: new task; depends on `API-001`, `DBT-006`, `FIN-009`, `SEC-005`. Dependents: API-002 live gate, UX-003…UX-006 staging gates.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| API-101-S01 | Compare every relation YAML with the live `INFORMATION_SCHEMA.COLUMNS` of the staging serving schema (names, types NUMBER(38,12), nullability) | `tools/registry_bind_check.py` | Zero drift; a deliberately renamed column in a scratch schema is reported | 3 |
| API-101-S02 | Compile every v1 metric × its default dimension set and execute it under fixture tenant A's owner profile; compare with the dbt golden expectations (FIN-GOLD-01 loaded via DBT-005) | `tests/spec/API-101/test_live_golden.py` | All values equal to the last decimal; results archived with publication_id | 4 |
| API-101-S03 | Verify residual rows: for every charge in the fixture, Σ attributed rows = parent charge (dbt test) and the substituted query spend by warehouse = spend by service = 270 | dbt test `assert_attribution_conserves`, API test | Both pass, and deleting one residual row in a scratch revision makes both fail | 3 |
| API-101-S04 | Verify pruning: `EXPLAIN USING JSON` for 10 representative plans shows `partitionsAssigned ≪ partitionsTotal` when a tenant/date predicate is present. The compiler always adds `tenant_id = ?` for clustering pruning, and security still relies on the RAP | `tests/spec/API-101/test_pruning.py` | Assigned/total ratio ≤ 5 % on the 400-day synthetic volume table (TO VERIFY LIVE numbers recorded) | 3 |
| API-101-S05 | Verify t-digest tier: compute query_elapsed_p95 exactly on the hot table and approximately from the aggregate-tier states for the same 30 days; record the relative error | `tests/spec/API-101/test_tdigest_error.py` | Error recorded; UI label threshold decided (e.g. show "≈" always in AGGREGATE tier) | 3 |
| API-101-S06 | Row policy smoke via the registry: profile B (Finance+A1) compiles the same plans and gets only authorized rows. The compiled plan with the tenant predicate removed (test-only build flag) still returns zero foreign rows | `tests/spec/API-101/test_rap_smoke.py` | Zero foreign rows; counts match the entitlement fixture | 3 |
| API-101-S07 | Publication binding: a query pinned to publication P1 after P2 is published returns P1 values (insert-only revisions, D-05) | test | P1 and P2 values differ in the fixture, and each is served by its own pin | 2 |
| API-101-S08 | Baseline latency table for 12 Home/Explorer plans (cold, warm, result-cache) on the chosen serving warehouse size | `docs/evidence/API-101/<commit>/latency.md` | p95 cold ≤ 5 s on the fixture volume, or a documented gap feeds OPS-008 | 3 |
| API-101-S09 | Record certification evidence and the registry_version ↔ dbt manifest hash pairing in the publication manifest (ORC) | evidence + manifest field `registry_version` | The publication manifest carries the registry version it was certified with | 2 |

Task acceptance:
- [ ] Every v1 R1 metric executes on Snowflake with golden equality.
- [ ] Conservation through residual rows is proven live.
- [ ] The RAP smoke test shows no foreign rows even when the compiler's tenant predicate is removed.
- [ ] The t-digest error is measured and recorded.

### API-002 — Safe analytical planner and Snowflake query broker
Release: R1 · Estimate: 48–68 h · Risk: H · Decisions: D-02, D-22, D-10, D-11 · Closes: G-API-05, G-API-06, G-API-13 (server side), G-API-14
Dependency changes: `+INF-005` (broker ECS service and task role), `+API-101` (live gate only; local build starts after API-001), keep `SEC-005`, `CTL-006`. `+SEC-101` (scope grammar library, SEC backlog) for scope intersection.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| API-002-S01 | Define the strict request model (Pydantic v2, `extra=forbid`): half-open UTC period, grain, metrics ≤ 10 (with optional `@version`), dims ≤ 4, filters (eq, in ≤ 500 values, not_in, prefix ≥ 2 chars on allowlisted dims, is_null, between for time), sort, limit ≤ 500, currency, maturity, compare, publication ("latest"\|id), top_n ≤ 100. Canonicalize (sorted sets, normalized timestamps) → `request_hash` | `apps/api/analytics/request.py` | Property test: permuting `in` values or dims order yields the same hash; timestamps with offsets normalize to Z | 3 |
| API-002-S02 | Resolve authorization: `X-Bridge-Tenant` → `identity.resolve_session()` → membership, profile_hash, epochs, scope clauses (SEC-101). Intersect filters with scope. Unauthorized or unknown filter values are dropped with one count-free warning `FILTER_VALUES_UNAVAILABLE` | `apps/api/analytics/authz.py` | Foreign tenant header → 403; an account filter with 1 valid + 1 foreign UUID returns data for the valid one plus the warning, and the body is identical when the foreign UUID does not exist | 4 |
| API-002-S03 | Build the QueryPlan IR from request + registry (substitution, currency forcing, compare expansion, tier choice) and validate it against `query_plan.schema.json` | `apps/api/analytics/plan.py` | Snapshot tests for 20 representative requests; an invalid IR is impossible to emit (schema validated in tests and at runtime) | 4 |
| API-002-S04 | Implement the SQL compiler (shared lib used by the broker): identifiers only from the relation catalog (quoted), every literal as a bound parameter, tenant predicate for pruning, keyset predicate, Top-N+Other CTE. The emitted SQL is parsed with sqlglot (logger silenced, G-SEC-14) and asserted to be a single SELECT/WITH | `packages/semantic_metrics/compiler.py` | Golden SQL snapshots; fuzz 10k requests with random allowlisted values → zero non-parameter literals in the emitted SQL | 5 |
| API-002-S05 | Implement the cost estimator reading `ops.serving_partition_stats` / `ops.serving_dimension_ndv` (PG) + the Redis EWMA per plan shape; apply `planner_limits.yaml`; record `meta.planner.route` | `apps/api/analytics/estimator.py`, PG DDL migration | 365-day spend by query_parameterized_hash for 17 accounts routes ASYNC; 7-day team daily cost routes SYNC (PRD §140/§141 examples) | 4 |
| API-002-S06 | Stand up the broker service (D-22): separate ECS service whose task role is the only principal allowed `sts:AssumeRole` on tenant serving IAM roles; accepts only Ed25519-signed IR (exp ≤ 30 s) over Service Connect TLS; re-validates the IR with the registry; compiles SQL itself | `services/query_broker/`, IAM policy in INF | Unsigned/expired/tampered IR → 401 at the broker; the API task role cannot assume tenant roles (IAM simulator test) | 5 |
| API-002-S07 | Implement pools keyed `(env, tenant_user, profile_role)`: lazy create, max 3 per key, 150 per broker task, LRU eviction of idle > 300 s, max lifetime 3,600 s. Checkout assertion of CURRENT_USER/CURRENT_ROLE/CURRENT_SECONDARY_ROLES (G-API-05); session parameters | `services/query_broker/pools.py` | Test: a connection whose role was switched out of band is discarded; a secondary-roles-enabled test user is refused | 4 |
| API-002-S08 | Implement deadline and cancellation: budget from request receipt; admission ≤ 2 s; STATEMENT_QUEUED_TIMEOUT/STATEMENT_TIMEOUT per remaining budget; async execute + poll; watchdog `SYSTEM$CANCEL_QUERY`; ASGI disconnect → cancel | `services/query_broker/execute.py`, `apps/api/analytics/deadline.py` | A 60 s synthetic query (`SYSTEM$WAIT`-style fixture view) ends ≤ 16 s with 503 QUERY_DEADLINE_EXCEEDED and shows as cancelled in QUERY_HISTORY; client abort at 3 s cancels within 2 s (TO VERIFY LIVE) | 5 |
| API-002-S09 | Implement admission control: Redis semaphores per tenant (4) and principal (2) with lease TTL = deadline; on Redis loss fall back to a per-broker-instance local semaphore at 50 % of limits; 429 TENANT_BUSY + Retry-After | `services/query_broker/admission.py` | Load test: tenant A at 50 rps does not raise tenant B's p95 by > 20 %; Redis flush during load causes no unbounded burst | 3 |
| API-002-S10 | Implement the post-execution re-authorization (G-API-05) and response assembly hand-off to API-003 | `apps/api/analytics/service.py` | Revoke the membership while the query runs → 409 SCOPE_CHANGED, no rows returned | 2 |
| API-002-S11 | Implement `POST /v1/analytics/batch` (≤ 12 items, resolves "latest" once, per-item problem) and `GET /v1/cost` as a canonical-request adapter | routes | Batch items all carry the same publication_id; `GET /v1/cost?…` and the equivalent POST produce the same request_hash | 3 |
| API-002-S12 | Security negative suite: SQL/Unicode injection in filter values, metric ids, dimension ids, sort keys, `@version`; foreign tenant header; profile B executing a plan signed for profile A; replay of a signed IR after 30 s; attempted `USE ROLE` via a crafted relation name in a test registry | `tests/spec/API-002/test_security.py` | All rejected or safely scoped; no foreign rows; broker logs contain no SQL text | 4 |
| API-002-S13 | Staging benchmark: 12 representative plans cold/warm/result-cache; cancellation cost; high-cardinality routing accuracy (estimated vs actual rows within 10×) | `docs/evidence/API-002/<commit>/bench.md` | Numbers recorded; thresholds in `planner_limits.yaml` updated from the measurements | 4 |
| API-002-S14 | Observability: `api_query_duration_seconds{route,class,outcome}`, `planner_route_total{decision}`, `broker_pool_connections{state}`, `broker_admission_wait_seconds`, `snowflake_statement_cancelled_total`, `broker_role_assertion_failures_total` (page on > 0); log fields request_id, tenant_hash, plan_shape_hash, sfqid, outcome — never SQL or values | OPS dashboards JSON | Alarm fires in staging on an injected role-assertion failure | 2 |
| API-002-S15 | Runbook entries: pool exhaustion, WIF login failures, stuck/uncancellable query, EWMA misrouting | `docs/16-observability/RUNBOOKS.md` additions | Tabletop walk-through done with SRE | 2 |

Task acceptance:
- [ ] No request can produce SQL containing a caller-supplied literal or identifier outside a bind parameter (fuzz evidence).
- [ ] Profile B never receives profile A rows, including when the compiler's tenant predicate is removed in the test build.
- [ ] A queue-saturated warehouse cannot hold a sync request beyond 16 s. Cancelled statements are visible as cancelled.
- [ ] Heavy requests route to async before execution in ≥ 95 % of the benchmark's heavy set.
- [ ] Revocation during execution yields 409 and returns no data.

### API-003 — Response metadata, sealed cursors, publication pins and cache
Release: R1 · Estimate: 36–50 h · Risk: H · Decisions: D-05, D-11 · Closes: G-API-07, G-API-13 (meta echo), G-API-17
Dependency changes: none upstream beyond API-002. Downstream: UX-002 depends only on the OpenAPI output of S01 to start building (see UX.md).

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| API-003-S01 | Author the OpenAPI components (Decimal, NullReason, Meta, Row, Problem + codes) and the path skeletons in §3; generate examples for every state (empty confirmed, filtered empty, partial, stale publication, denied) | `docs/api/openapi.yaml`, `packages/api_contracts/*.json` | `oasdiff`/spectral lint passes; examples validate | 4 |
| API-003-S02 | Implement decimal serialization from Snowflake NUMBER(38,12) via Python Decimal with the FIN-106 context (G-FIN-19): plain string, no exponent, no `-0`, money padded to ISO 4217 minor units | `apps/api/analytics/serialize.py` | `Decimal('-0.000000000000')` → `"0.00"` (USD); `Decimal('1E+3')` → `"1000.00"`; `12345678901234567890.123456789012` round-trips exactly | 2 |
| API-003-S03 | Assemble meta from the publication manifest (as-of, materialized_at, source_as_of), coverage marts, reconciliation/close status and data_status composition (computed with GROUPING SETS in the same statement); totals for the full result (not the page) | `apps/api/analytics/meta.py` | Fixture: a partial month shows composition PROVISIONAL 15,000 / RECONCILED 0 and `comparison_status=PARTIAL_CURRENT` | 4 |
| API-003-S04 | Distinguish empty-confirmed vs no-coverage vs forbidden: empty rows + coverage complete → 200 empty; coverage missing → rows empty + `data_status.overall=UNAVAILABLE` + missing_sources; unauthorized → 403/404 | code + tests | Three fixtures produce three distinct, schema-valid responses | 2 |
| API-003-S05 | Implement the sealed-token library (AES-256-GCM, kid ring, purpose AAD) and the rotation Lambda/job; spec doc | `packages/sealed_tokens/`, `docs/09-api/tokens.md` | A token minted under kid k1 validates after rotation to k2; a k0 token after its retirement → CURSOR_INVALID; a purpose-swapped token (explain used as cursor) fails | 4 |
| API-003-S06 | Implement keyset pagination for aggregate and records modes: sort tuple + `row_key` (hash of dims, or `(account_id, query_id)`), NULLS LAST encoded, typed `after` values | `apps/api/analytics/pagination.py` | 1,000 rows all with spend `"10.00"` paginate at 100/page with each row_key exactly once | 4 |
| API-003-S07 | Implement the cursor validation matrix (G-API-07 order) with identical bodies for tamper/foreign/unknown kid | code + tests | Foreign-tenant cursor and random bytes produce byte-identical problem bodies (except request_id) | 2 |
| API-003-S08 | Implement publication resolution and pins: "latest" → id at request start; `ops.publication_pin` rows for cursors (1 h), jobs (TTL), statements (no expiry), reports; publish the GC contract to ORC/DBT; 410 PUBLICATION_RETIRED | PG migration, `apps/api/analytics/publication.py`, contract note in ORC backlog | While a cursor pin exists, the GC dry-run lists the revision as protected; after expiry + 24 h it becomes collectible | 3 |
| API-003-S09 | Implement weak ETag + `If-None-Match` → 304 after authorization; `Cache-Control: no-store` on analytical routes | middleware | Unchanged publication → 304 with no Snowflake call (broker counter unchanged); revoked user with a valid ETag → 403, not 304 | 2 |
| API-003-S10 | Integrate the CTL-006 cache with the publication-keyed layout (G-API-17), single-flight and value metadata (publication, as-of, coverage) | `apps/api/analytics/cache.py` | 100 identical concurrent misses → 1 broker execution; a profile-B request never hits profile-A keys (key inspection test) | 3 |
| API-003-S11 | Implement `GET /v1/me/context` (tenant, profile_hash, capabilities, current publication, plan quotas, locale) and `GET /v1/publications/current` (ETag-able, ≤ 1 KB) | routes | Both validate against OpenAPI; `/publications/current` p95 ≤ 50 ms warm | 3 |
| API-003-S12 | Oracle test: paginate 1,000 tied rows while a new publication is published after page 3 → all pages from the old publication, each row once; after TTL → CURSOR_EXPIRED | `tests/spec/API-003/test_pinned_paging.py` | Passes locally (DuckDB fixture) and on staging (Snowflake) | 3 |
| API-003-S13 | Revocation tests: epoch bump after page 1 → page 2 SCOPE_CHANGED; missing price → value null + `PRICE_UNKNOWN`; partial source state visible in meta | tests | All pass | 2 |
| API-003-S14 | Observability (`api_cursor_rejections_total{reason}`, `api_cache_hits_total{layer}`, `publication_pin_active{holder_kind}`) + docs | dashboards, README | Metrics visible in staging | 2 |

Task acceptance:
- [ ] Every analytical response validates against the meta schema, and money is always a decimal string or null with a reason.
- [ ] Tied-value pagination across a publication change returns each ID exactly once.
- [ ] Foreign/tampered cursors are indistinguishable. Expired, retired and scope-changed cursors return distinct restart codes.
- [ ] No analytical response is stored in the browser HTTP cache (`no-store` verified).
- [ ] GC never removes a pinned revision.

### API-004 — Asynchronous analysis jobs and cancellation
Release: R1 · Estimate: 32–46 h · Risk: M · Decisions: D-22 · Closes: G-API-12
Dependency changes: `−ORC-006` (no Dagster in the interactive path), `+INF-005` (analysis-worker ECS service), keep `API-003`, `CTL-004`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| API-004-S01 | Specify the job state machine with guards and fencing (CAS on status + lease token), including CANCEL_REQUESTED and EXPIRED | `docs/09-api/analysis-jobs.md` | Reviewed; the transition table is used as a test parametrization | 2 |
| API-004-S02 | Create `analytics.analysis_job` (tenant_id, job_id, principal_kind, subject_id, profile_hash, membership_epoch, scope_hash, request_hash, idempotency_key, definition JSONB ≤ 32 KB, kind ∈ {query, records, workload_compare, export}, publication_id, registry_version, status, progress JSONB, attempt, lease_owner, lease_token, lease_expires_at, result_rows, result_bytes, error_code, created_at, expires_at). FORCE RLS; unique (tenant_id, subject_id, idempotency_key) | PG migration | RLS test: tenant B cannot select tenant A jobs even with a known job_id | 2 |
| API-004-S03 | Implement submit: validate, quota (2 per tenant, 1 per principal, ≤ 1 tenant slot held by machine clients), estimate, insert job + outbox event in one transaction; 202 + Location + `Retry-After: 2`; same key + same body → same job; same key + different body → 409 IDEMPOTENCY_KEY_REUSED | `apps/api/analysis_jobs/routes.py` | Identical submissions ×10 → 1 job row; third concurrent job → 429 QUOTA_EXCEEDED | 3 |
| API-004-S04 | Implement `analysis-worker`: consume the outbox relay (SQS), claim with a fenced lease, pin the publication, call the broker JOB class (jobs warehouse, 1,800 s timeout), write results via `INSERT INTO SERVING_JOBS.JOB_RESULT SELECT … ` bound to (tenant_id, job_id, attempt) | `services/analysis_worker/` | A 365-day by-hash job for the synthetic 17-account tenant completes; no result rows pass through the worker's memory (worker RSS < 300 MB) | 5 |
| API-004-S05 | Validate before publishing the result: row count > 0 or coverage-confirmed empty; totals checksum = re-aggregation of JOB_RESULT for the attempt; then status SUCCEEDED | worker | A corrupted attempt (deleted rows) fails validation → FAILED with `RESULT_VALIDATION_FAILED` | 3 |
| API-004-S06 | Implement cancel: POST /cancel → CANCEL_REQUESTED; the worker polls every 2 s and calls `SYSTEM$CANCEL_QUERY`; completion racing cancel is resolved by CAS (the first writer wins; a late cancel returns 409 ALREADY_COMPLETED) | code + tests | 100 randomized race runs → never both SUCCEEDED and CANCELLED; cancel latency p95 ≤ 5 s | 3 |
| API-004-S07 | Implement result read: `GET /{id}/result?cursor` re-authorizes (subject, membership epoch, profile hash); if the scope hash changed → 409 RESULT_SCOPE_CHANGED (rerun offered); keyset paging via API-003 | route | A revoked requester cannot read a finished result; another tenant member without the job's scope gets 404 | 3 |
| API-004-S08 | Implement retries: lease expiry → re-claim with attempt+1; the previous attempt's rows are ignored (reads filter by the final attempt) and purged | worker | Killing the worker mid-INSERT produces a correct final result and no duplicate rows visible | 3 |
| API-004-S09 | Implement expiry/GC: results TTL 7 days; purge rows; EXPIRED; release the publication pin | scheduled job | After TTL, the result returns 410 and the JOB_RESULT rows are gone | 2 |
| API-004-S10 | Negative tests: foreign job id → 404; job of a user whose tenant membership was removed; tenant quota isolation (tenant A saturated does not delay tenant B job start by > 30 s) | `tests/spec/API-004/` | All pass | 3 |
| API-004-S11 | Observability: `analysis_jobs_queued{tenant_class}`, `analysis_job_age_seconds`, `analysis_job_duration_seconds{kind,outcome}`, `analysis_job_cancel_latency_seconds`; alarm on queue age > 5 min | dashboards | Alarm fires on an injected stuck worker | 2 |
| API-004-S12 | Runbook (stuck job, orphaned Snowflake statement, result validation failure) + job-status contract for UX-104 | docs | Reviewed by SRE and UX | 2 |

Task acceptance:
- [ ] An identical idempotency key creates exactly one job. A reused key with a different body returns 409.
- [ ] Cancel and completion races never produce two terminal states.
- [ ] A revoked or narrowed requester cannot read a finished result.
- [ ] No analytical rows are stored in PostgreSQL or Redis, and none transit the worker's memory beyond metadata.

### API-005 — Explain This Number: lazy lineage tree
Release: R1 · Estimate: 32–46 h · Risk: H · Decisions: D-05, D-12, D-15 · Closes: G-API-08
Dependency changes: `API-003`, `DBT-006` (charge/attribution/source-set explain), `ALC-005` + `FIN-010` only for the statement-line resolvers (S05 is gated; the other steps are not). Add `+ING` batch-manifest read API (the owner is the ING backlog).

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| API-005-S01 | Author `data/contracts/explain.json`: node kinds, fields, the edge table (parent kind → child kinds → resolver id → relation) and remainder semantics | contract | Reviewed with FIN/ALC; covers PRD §87's seven levels | 3 |
| API-005-S02 | Mint explain refs: KPI tiles get `explain` sealed tokens; table cells use `meta.explain.query_token` + row key + metric → `GET /v1/explain/{ref}` | token purpose `explain`, TTL 24 h | A ref from tenant A used in tenant B → 404 identical to a random ref | 2 |
| API-005-S03 | Resolve the root: recompute the value at the pinned publication through the planner; FORMULA_OPERAND children for ratio/derived metrics (numerator, denominator; budget − actual) | `apps/api/explain/root.py` | Root amount equals the displayed amount for all Home tiles in the fixture; ratio root shows numerator 20,000 / denominator 20,000 = 100 % | 3 |
| API-005-S04 | Implement the charge-level resolvers: metric → CHARGE groups by service → CHARGE (billing bucket, D-12) → ATTRIBUTION_SET (resources incl. residual) → RESOURCE → QUERY_SET (hot tier) → SOURCE_BATCH (`charge_source_set`) → FILE_SET (ING manifest) | `apps/api/explain/resolvers/*.py` | Fixture: spend 270 → children sum 270; warehouse 200 → query 140 + idle 60; every page includes a REMAINDER so partial sums = parent | 6 |
| API-005-S05 | Implement the statement-line resolvers: STATEMENT_LINE → ALLOCATION_RULE (rule_version, method, weight n/d) → GROUP → source CHARGE (ALC-005 results) | resolvers | Owner profile, fixture: Finance 12,000 → direct query 8,400 + idle share 3,600 (weight 8,400/14,000 of 6,000) → idle charge 6,000 → WMH buckets | 4 |
| API-005-S06 | Implement permission trimming: children through the broker under the caller's profile; RESTRICTED_REMAINDER = parent − Σ visible with no count/names; UNAVAILABLE(DENOMINATOR_OUTSIDE_SCOPE) when the parent or a weight denominator is not readable; tenant switch `explain.disclose_allocation_denominators` (default off) | code + tests | (a) Viewer without `query.read` expanding warehouse 200 sees query 140 / idle 60, and the 140 expands to one RESTRICTED_REMAINDER of 140 with no count. (b) Finance-only viewer expanding the Finance line 12,000 sees 8,400 + 3,600 with method and basis 8,400, and neither 14,000, 6,000, 5,600 nor the string "Marketing" appears anywhere in the payload | 3 |
| API-005-S07 | Retention and pins: statement-pinned publications explainable indefinitely; unpinned retired → 410 + current-value link; hot-tier-expired QUERY_SET → UNAVAILABLE(RETENTION_EXPIRED) | code + tests | Synthetic 100-day-old query leaf returns UNAVAILABLE with the reason | 2 |
| API-005-S08 | Safety: file IDs, checksums and batch IDs only; no S3 URL/bucket/key prefix in any node; raw access is out of scope (separate privilege, R2) | serializer allowlist + test | Payload scan finds no `s3://`, `amazonaws.com` or bucket names | 1 |
| API-005-S09 | Guards: depth ≤ 8, cycle detection on the node path in the token, 20 expansions/min/user, 50 children/page | code | A crafted cyclic fixture terminates with UNAVAILABLE(CYCLE_DETECTED); the rate limit returns 429 | 2 |
| API-005-S10 | Evidence export: `POST /v1/explain/{ref}/export` bundles the expanded nodes (JSON) through API-102 | route | The bundle's root amount equals the UI root; checksum present | 2 |
| API-005-S11 | Tests: foreign child-node ref, missing archived evidence (purged batch manifest) → UNAVAILABLE(EVIDENCE_PURGED), no fabricated formula for unknown price (root null + PRICE_UNKNOWN) | `tests/spec/API-005/` | All pass | 2 |
| API-005-S12 | Observability (`explain_expansions_total{kind}`, `explain_expand_duration_seconds`) and runbook | docs | p95 expansion ≤ 3 s on staging fixture | 2 |

Task acceptance:
- [ ] At every level the displayed amount equals Σ(children) + remainder at the same publication.
- [ ] Restricted children never reveal counts, names or IDs.
- [ ] No lineage table grows per displayed number. Storage growth = `charge_source_set` only (≤ one row per charge × batch).
- [ ] Evidence that was purged or retention-expired is labelled explicitly and never fabricated.

### API-006 — Public API credentials, quotas and contract release tests
Release: R2 (R1* if the first customer integrates by API — owner question Q-API-1) · Estimate: 32–46 h · Risk: M · Decisions: D-17 · Closes: G-API-11, G-API-15 (API side)
Dependency changes: `−API-005` (unrelated), keep `API-004`, `SEC-008`. Downstream `GOV-003 −API-006`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| API-006-S01 | Create `identity.machine_client` (client_id PK, tenant_id, name, profile_hash, capabilities[], status ACTIVE\|REVOKED\|EXPIRED, created_by, created_at, expires_at ≤ 365 d, predecessor_id, last_used_at) with FORCE RLS | PG migration | RLS test passes; capabilities restricted to the allowlist | 2 |
| API-006-S02 | Configure the Cognito resource server `bridge-api` with capability scopes; implement admin-only client creation (Cognito CreateUserPoolClient, client_credentials only, access token 60 min); show the secret once, never persist or log it | `apps/api/machine_clients/`, Terraform for the resource server | The secret is absent from logs, PG and audit payloads (sentinel scan); an audit event is recorded | 4 |
| API-006-S03 | Bearer middleware: JWKS cache, `iss`, `token_use=access`, `client_id` lookup, scope ⊇ route capability, per-request status check (immediate revocation), tenant = machine_client.tenant_id (mismatching `X-Bridge-Tenant` → 403) | middleware | A revoked client with an unexpired token → 401 within 1 request | 3 |
| API-006-S04 | Rotation: create a successor with the same capabilities, overlap ≤ 7 days, auto-revoke the predecessor at the end; UI and API | code | Both clients work during the overlap; the predecessor fails afterwards | 2 |
| API-006-S05 | Rate limits: Redis token buckets per client (5 rps, burst 10) and per tenant (20 rps); 429 + Retry-After; limits come from the entitlement (D-17) | `apps/api/ratelimit.py` | Tenant A flood (100 rps) does not change tenant B's success rate; buckets survive Redis restart conservatively (fail-closed at 50 %) | 3 |
| API-006-S06 | Versioning and deprecation middleware: `/v1` only additive; `Deprecation`/`Sunset`/`Link rel=deprecation` headers on flagged operations; METRIC_VERSION_RETIRED with migration | middleware + policy doc `docs/api/versioning.md` | Contract test asserts headers on a deprecated fixture route | 2 |
| API-006-S07 | OpenAPI release pipeline: generate from FastAPI, commit, `oasdiff breaking` vs the last release tag, examples required per operation, Schemathesis run against staging | CI job | An injected breaking change (removing a response field) fails CI | 4 |
| API-006-S08 | SDKs: the TypeScript client is already generated for the web (UX-002-S01). Publish a Python client (R2) with token caching until `exp − 60 s`, retries honoring Retry-After, and idempotency keys for POST | `sdk/python/` | SDK integration test obtains ≤ 1 token per hour under a 1 rps loop | 4 |
| API-006-S09 | Settings UI `/settings/api-clients` (list, create with capability picker, one-time secret reveal, rotate, revoke, last used, recent 429s) — the screen is missing from the design catalog (UX.md G-UX-10) | `apps/web/src/pages/settings/api-clients` | Playwright: create → copy once → reload shows no secret; revoke → status REVOKED | 4 |
| API-006-S10 | Cost guard: token issuance per client from Cognito logs/CUR (TO VERIFY LIVE the source), alarm > 200/day/client; optional WAF rate rule on the token endpoint (TO VERIFY LIVE) | CloudWatch alarm / Terraform | An injected 1 rps token loop in staging raises the alarm within 1 h | 2 |
| API-006-S11 | Replay compatibility suite: saved v1 requests (fixtures) replayed on every release; expired client; Retry-After behavior | `tests/api/contracts/replay/` | Suite green on the release candidate | 2 |
| API-006-S12 | Security tests: scope escalation (client with analytics.read calling jobs.write), foreign tenant header, token from another user pool, `alg=none`/HS256 confusion | tests | All rejected | 2 |

Task acceptance:
- [ ] A machine client can never exceed its tenant, profile or capabilities. Revocation takes effect on the next request.
- [ ] Breaking OpenAPI changes are blocked in CI. Deprecated metric versions return migration guidance.
- [ ] Rate limiting one tenant does not affect another.
- [ ] Token-issuance cost is monitored per client.

## 5. New tasks required

### API-102 — Exports: CSV (sync/async) and evidence bundles; PNG/PDF via render worker
Release: R1 (CSV, evidence bundles) / R2 (PNG, PDF) · Estimate: R1 24–34 h, R2 8–12 h · Risk: M · Decisions: D-18 · Closes: G-API-09
Dependency changes: new; depends on `API-003`, `API-004`, `INF-003` (S3/KMS); PNG/PDF steps depend on `RPT-002`. Dependents: UX-104, UX-004 export action, API-005-S10. Plugs in parallel with API-005.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| API-102-S01 | Create `analytics.export_job` (extends the analysis_job kinds) and the S3 layout `exports/<tenant_id>/<job_id>/part-*.csv.gz` with KMS, 7-day lifecycle and Object Lock off | PG migration, Terraform | Bucket policy denies any principal except the export writer/reader roles | 2 |
| API-102-S02 | Implement sync/async decision (est_rows ≤ 10,000 and ≤ 5 MB sync), hard limits (1,000,000 rows / 250 MB gz) → 422 EXPORT_TOO_LARGE with narrowing hints | `apps/api/exports/plan.py` | 10,001-row estimate → async; 2M → 422 | 2 |
| API-102-S03 | Implement the type-driven CSV writer: decimal columns raw from strings (regex-validated), text columns escaped per G-API-09 incl. full-width triggers, RFC 4180 quoting, UTF-8 without BOM by default (BOM option for Excel), header row from i18n labels + stable column ids | `packages/exporters/csv.py` | Fuzz: 100k random strings → no exported text cell starts with an unescaped trigger; `-1234.500000000000` stays exact | 3 |
| API-102-S04 | Streaming async writer in analysis-worker: `COPY INTO @stage` or chunked cursor fetch → multipart S3 upload; manifest.json (request, publication_id, metric versions, coverage, row count, SHA-256 per part) | worker extension | 1M-row export completes with worker RSS < 300 MB; manifest checksums verify | 5 |
| API-102-S05 | Download endpoint: re-authorize (subject, epochs, scope hash) → 302 to a 30 s presigned URL; audit event with row count and checksum, no data | `GET /v1/exports/{id}/download` | Revoked user → 403; presigned URL expired after 30 s | 2 |
| API-102-S06 | Sync CSV path for small results (same writer, streamed response, `Content-Disposition` with an ASCII-safe filename) | route | Explorer CSV equals the table rows and totals for the same publication | 2 |
| API-102-S07 | Evidence bundle export (Explain) and saved-view "export definition" (JSON of the semantic request, no data) | routes | Bundle root equals the displayed amount | 2 |
| API-102-S08 | Tests: formula injection corpus (OWASP CSV injection list + full-width), multi-currency export keeps a currency column, restricted profile export contains only authorized rows, export of a retired publication → 410 | `tests/spec/API-102/` | All pass | 3 |
| API-102-S09 | Observability + quotas: `exports_total{mode,outcome}`, bytes, per-tenant daily export cap (default 50 exports/day) | dashboards, entitlements | Cap enforced with 429 | 2 |
| API-102-S10 (R2) | PNG/PDF: submit a render job to RPT-002 with the stored result snapshot + widget spec; deliver through the same download endpoint | integration | PDF numbers equal the CSV of the same job | 5 |
| API-102-S11 (R2) | Visual/regression tests of rendered exports (fixture charts, negative values, long labels) | tests | Baseline diffs reviewed | 4 |

Task acceptance:
- [ ] CSV money is exact and unformatted, and text cells cannot trigger spreadsheet formulas.
- [ ] Exports over the limits are refused before any Snowflake work. Async exports never pass through API memory.
- [ ] Every download is re-authorized and audited, and links expire within 30 s.

### API-104 — Records mode, entity detail and scoped dimension values
Release: R1 · Estimate: 30–42 h · Risk: M · Decisions: D-10, D-11 · Closes: G-API-10
Dependency changes: new; depends on `API-002`, `API-003`, `API-101`. Dependents: UX-002 (scope bar options), UX-004 (ledger), UX-005 (execution explorer, query detail), WRK-002…WRK-004, UX-103.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| API-104-S01 | Add `records` datasets to the registry (billing_ledger, query_executions, model_executions, dbt_invocations, pbi_activities, task_graph_runs, dt_refreshes, storage_objects): allowed columns, filters, default sort, tier, capability per column | `packages/semantic_metrics/records/*.yaml` | Lint green; `sql_text` column requires `query.sql.read` + privacy FULL | 3 |
| API-104-S02 | Implement `POST /v1/analytics/records` (IR mode RECORDS, keyset, ≤ 200 rows/page, sync range ≤ 31 d else async) | route + compiler support | 90-day query_executions request → async; 7-day → sync page of 200 with next_cursor | 4 |
| API-104-S03 | Implement `GET /v1/entities/{kind}/{id}` for warehouse, database, compute_pool, pipe, task, dynamic_table, query, dbt_invocation, pbi_activity, task_graph_run: attributes, capability flags (warehouse_type, idle supported, operator evidence window), retention tier | route | Adaptive warehouse entity returns `capabilities.idle=false` | 4 |
| API-104-S04 | Implement query detail specifics: timing breakdown (compile/queue/execution), hash + hash_version, parent/root query links (WRK-004), workload, sanitized SQL per privacy mode, D-14 per-hour compute proration rows | route | Fixture q_demo_042: 0.4 + 0.2 + 11.8 = 12.4 s; METADATA_ONLY tenant → sql_text null + PRIVACY_SUPPRESSED | 3 |
| API-104-S05 | Implement `GET /v1/dimensions/{id}/values` via the broker under row policies: prefix search (≥ 2 chars for HIGH), ≤ 20 values, `has_more` only, pseudonym→display resolution for `user` only with `people.read` (D-10) | route | Finance-only viewer searching "MARK" on group returns nothing and `has_more=false`, byte-identical to a nonexistent prefix | 4 |
| API-104-S06 | Non-enumeration: unknown/foreign/unauthorized ids take the same broker lookup path; identical 404 bodies; latency difference < 20 % (p50 over 200 trials) | tests | Timing test passes | 2 |
| API-104-S07 | Retention-tier behavior: records older than hot_days → 410 RETENTION_EXPIRED on detail; list mode refuses ranges beyond the hot tier with guidance to use family aggregates | code + tests | 100-day-old query id → RETENTION_EXPIRED | 2 |
| API-104-S08 | Rate limits for autocomplete (10/s/user) and records (shares the interactive admission) | config + tests | Burst beyond limits → 429 | 1 |
| API-104-S09 | Security tests: restricted user enumerating warehouse ids by guessing UUIDs, query ids from another account of the same tenant outside scope, SQL text access without capability | `tests/spec/API-104/` | All denied without leakage | 3 |
| API-104-S10 | Billing ledger dataset for the UX ledger page: bucket-grain rows (D-12) with scope_kind, signed amounts, price basis, maturity, recon status; org-scope rows only with an org-financial grant (G-FIN-25) | dataset + tests | A1-limited viewer's ledger totals 268 (FIN-GOLD-01; 26,800 in the UI fixture) and never lists the organization support (5) or rebate (−3) rows | 3 |
| API-104-S11 | OpenAPI examples + docs; observability `records_requests_total{dataset}` | docs | Lint green | 2 |

Task acceptance:
- [ ] Record, entity and autocomplete reads go only through the broker under row policies, with no unscoped PG dictionaries.
- [ ] Guessing IDs produces indistinguishable 404s, and autocomplete reveals no hidden names or counts.
- [ ] Query detail respects privacy mode and retention tier.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| API-001 | R1 | 38 | 54 |
| API-101 (new) | R1 | 24 | 34 |
| API-002 | R1 | 48 | 68 |
| API-003 | R1 | 36 | 50 |
| API-004 | R1 | 32 | 46 |
| API-005 | R1 | 32 | 46 |
| API-102 (new, CSV/evidence) | R1 | 24 | 34 |
| API-104 (new) | R1 | 30 | 42 |
| API-006 | R2 (R1* if customer integrates by API) | 32 | 46 |
| API-102 (PNG/PDF steps) | R2 | 8 | 12 |
| **Total R1** | | **264** | **374** |
| **Total R2** | | **40** | **58** |

The original plan was 6 tasks × 2–6 h = 12–36 h. The realistic figure is roughly 10× higher. Most of the gap is the registry, broker, tokens and Explain designs, which the contract leaves implicit.

## 7. Owner questions (only those not already covered by D-01…D-25)

- **Q-API-1** Does the first customer need programmatic access (API-006 in R1), or is UI plus CSV export enough for R1?
- **Q-API-2** Export limits: are 1,000,000 rows / 250 MB compressed per export and 50 exports/tenant/day acceptable commercial defaults? Should they be plan-dependent (D-17)?
- **Q-API-3** Deprecated metric versions: a 6-month support window, and are saved reports allowed to auto-migrate on EQUIVALENT changes without customer notification?
- **Q-API-4** Async result retention: is 7 days for analysis-job results and exports acceptable, or do customers expect to re-open old analyses? Longer retention increases pinned revisions and storage.
- **Q-API-5** Should the "Explain" evidence export (JSON bundle) be available to all analysts, or only to Auditor/FinOps Admin capabilities?

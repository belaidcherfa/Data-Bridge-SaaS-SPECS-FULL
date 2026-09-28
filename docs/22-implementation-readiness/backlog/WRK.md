# WRK — Implementation-readiness review and production backlog

Canonical contract: [workloads.md](../../10-frontend/workloads.md). Tasks reviewed: WRK-001, WRK-002, WRK-003, WRK-004, WRK-005 (plus the 17 workload screens in [pages/workloads.md](../../21-ui-ux/pages/workloads.md), the source catalog rows for QUERY_HISTORY, QUERY_ATTRIBUTION_HISTORY, SESSIONS, TASK_HISTORY and DYNAMIC_TABLE_REFRESH_HISTORY, and PRD §53–§55, §77, §78). Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

Related reviews: [SEC.md](SEC.md) G-SEC-14/G-SEC-15 (sanitizer ordering; this file extends the allowlist), [API.md](API.md) (registry metrics, records mode, t-digest tier), [UX.md](UX.md) (screen ownership), ING backlog (source projections).

## 1. Verdict

The workload contract has the right epistemics: evidence over guesses, UNKNOWN allowed, cost counted once, no Fabric claims. It is not implementable as written, for four reasons.

1. The metadata the classifier needs (the dbt comment and the Power BI QUERY_TAG) must be extracted **inside the sanitizer at extraction time** (SEC-007, M1). Raw SQL is never persisted, so that extraction is irreversible beyond the 365-day Account Usage window. Yet the allowlist is owned by WRK-001, which is scheduled ~100 tasks later behind API-001.
2. The native linkage that WRK-004 relies on exists only in specific views. Stored-procedure parent/root IDs are in QUERY_ATTRIBUTION_HISTORY and ACCESS_HISTORY, not QUERY_HISTORY, and the source catalog does not extract them. Serverless task cost is per task and time window, not per run.
3. Power BI exposes only mode + ActivityId, and only from the Service with the 1.0 connector. There are no report or dataset identities.
4. D-11 retention removes query-level rows after 90 days. Invocation- and family-level facts must be designed so the 365-day workload views and comparisons still work. The current ING backfill plan also drops the very text that carries dbt identity for days 91–365 (G-WRK-15).

Author first: the allowlist v1 (§3), the evidence schema, and the precedence table. Then decouple WRK-001 from API-001.

## 2. Findings

### G-WRK-01 · Workload metadata extraction is irreversible and must ship with the sanitizer (M1), not with WRK-001 (M5)
Severity: BLOCKER · Type: GAP / CONTRADICTION (dependency order)
Evidence:
- `security.md`: "AST-based SQL parser strips literals, unapproved comments and unsafe query-tag fields before Arrow/S3. Parsing failure stores no SQL."
- SEC-007 MT1: "retain only approved dbt/PBI identifiers from structured comments/tags".
- WRK-001 depends on "DBT-003, SEC-007, API-001" and owns "explicit metadata→session→approved comment" parsing.
- `workloads.md`: "enrich with session client application and approved SQL comments".
- G-SEC-15 proposes an allowlist `app, dbt_version, profile_name, target_name, node_id, invocation_id` plus `bridge_finops`.
Why it matters:
- Whatever the extractor drops is gone. Re-extraction from Account Usage is possible only for the last 365 days, and it costs customer warehouse credits (D-08).
- If ONB-004 (historical backfill) runs with an allowlist that misses `connection_name` (the default key on non-node dbt queries), the Power BI keys (`PowerQuery`, `Host`, `HostContext`, `ActivityId`) or `project_name`/`materialized` (emitted by the widely used query-tags package, below), those classifications are permanently UNKNOWN for the backfilled year.
- The inverse risk: a naive "keep the whole dbt JSON" rule persists `node_meta` (owner emails), `invocation_command` (can contain `--vars` secrets) and `dbt_cloud_run_reason` ("Kicked off from UI by niall@select.dev"). All three are emitted by `get-select/dbt-snowflake-query-tags` — VERIFIED (raw.githubusercontent.com/get-select/dbt-snowflake-query-tags/main/README.md and macros/query_comment.sql, 2026-09-27; the package is now deprecated in favour of `get-select/dbt-query-tags`).
Resolution: new task **WRK-101** delivers a pure Python library `packages/workload_meta` (`extract(query_text, query_tag, policy) → WorkloadMetaV1`), called by SEC-007's sanitizer as its step (1) (G-SEC-15 ordering). The allowlist v1 in §3 is versioned `wlmeta_version`, frozen before ONB-004, and changed only with a documented re-extraction plan bounded to 365 days. Dependencies: WRK-101 ← SEC-001 (data classification); SEC-007 ← WRK-101; WRK-001 ← WRK-101, −API-001.
Affects: WRK-001, WRK-101, SEC-007, ING-003, ONB-004.

### G-WRK-02 · dbt detection facts: the default comment has no invocation or project key, sits at the end of the text, and can be truncated away
Severity: HIGH · Type: VENDOR-FACT
Evidence:
- The dbt-adapters default query comment builds `app='dbt', dbt_version, profile_name, target_name` plus `node_id` when a node exists, else `connection_name`. VERIFIED (raw.githubusercontent.com/dbt-labs/dbt-adapters/main/dbt-adapters/src/dbt/adapters/contracts/connection.py `DEFAULT_QUERY_COMMENT`, 2026-09-27).
- dbt docs: "For Snowflake, the comment appears at the *end* of the query. This prevents the comment from being stripped during processing", and `append` is "useful on databases like Snowflake which remove leading SQL comments". VERIFIED (github.com/dbt-labs/docs.getdbt.com `website/docs/reference/project-configs/query-comment.md`, 2026-09-27).
- dbt-snowflake connects with `application="dbt"`. VERIFIED (dbt-snowflake `connections.py`, 2026-09-27). Whether this surfaces as `SESSIONS.CLIENT_ENVIRONMENT:APPLICATION` is TO VERIFY LIVE.
- `invocation_id` is available to query-comment templates (QueryHeaderContext → ManifestContext → BaseContext.invocation_id). VERIFIED (dbt-core v1.9.0 `context/query_header.py`, `context/base.py`, 2026-09-27).
- `workloads.md`: "structured comments may expose project/model/environment and optionally invocation/materialization".
Why it matters:
- There is **no invocation_id by default**. Exact run counts (`dbtruns: 30 verified invocations`) exist only for customers who customized the comment or use a tags package.
- There is no `project_name` by default. The project must be derived from `node_id` = `<resource_type>.<package>.<name>`, and models from installed packages report the package, not the root project.
- A customer who set `append: false` (or an old dbt version that prepends) gets **no** comment in QUERY_HISTORY at all.
- Very long compiled statements can lose the tail comment through QUERY_TEXT truncation (the storage limit is TO VERIFY LIVE; search snippets mention truncation above ~1 MB).
- `target_name` is an environment hint, not an environment.
Resolution:
- The WRK-101 lexer scans the **last** block comment outside string literals first, then the first one, and caps JSON at 4 KB.
- A truncated text or unterminated comment gives `dbt_meta_status=TRUNCATED`, and classification then falls back to QUERY_TAG and session evidence.
- Project = `project_name` if present, else the `node_id` package segment, flagged `project_basis=NODE_PACKAGE`.
- Environment = a tenant-configurable mapping of `target_name` → PRODUCTION/STAGING/DEV/OTHER, with the raw label kept.
- Non-node queries (`connection_name` present, e.g. `master`, `list_<db>_<schema>`) form a "dbt overhead" bucket.
- The onboarding and empty-state guide offers a snippet that adds `invocation_id` (and optionally `materialized`) to `query-comment` with `append: true`, plus an optional `query_tag` macro. The customer stays free not to adopt it.
- dbt Fusion and dbt Projects on Snowflake (native `EXECUTE DBT PROJECT`, whose child queries may carry a root query ID) are TO VERIFY LIVE in WRK-002-S01, not assumed.
Affects: WRK-101, WRK-001, WRK-002, ONB-001.

### G-WRK-03 · Power BI: only mode + ActivityId are observable, only from the Service, only on connector 1.0
Severity: HIGH · Type: VENDOR-FACT
Evidence:
- Power BI Service queries to Snowflake carry `QUERY_TAG` JSON such as `{"PowerQuery":true,"Host":"PBI_SemanticModel_MWC","HostContext":"PowerBIPremium-DirectQuery","ActivityId":"<guid>"}`, with `HostContext` `PowerBIPremium-Import` for refreshes.
- Tags are sent only from the Service, not Desktop, and only with the V1.0 connector implementation as of April 2025.
- The contents are not customizable, and there is no report or visual information.
- ActivityId was added later and maps to the Workspace Monitoring OperationId.
- VERIFIED via search snippets of blog.crossjoin.co.uk/2025/04/13/current-status-of-snowflake-query-tags-in-power-bi/ and …/2025/10/05/snowflake-query-tags-in-power-bi-and-workspace-monitoring/ (Chris Webb, Microsoft), 2026-09-27. The connector 2.0 status after Oct 2025 is TO VERIFY LIVE.
- Session identification via `PARSE_JSON(CLIENT_ENVIRONMENT):APPLICATION ilike '%Power%BI%'` (or "MashupEngine", gateway) — search snippet of community.snowflake.com, TO VERIFY LIVE exact strings.
- WRK-003 data model: "optional dataset/report identifiers with evidence".
Why it matters:
- Dataset and report identities are **not obtainable** from Snowflake-only evidence.
- Desktop traffic and connector-2.0 traffic have no mode.
- "Activity" means different things: in Import mode, one ActivityId covers a refresh that spans many table queries (the fixture `pbi_0830`: 8 + 24 = 32 queries); in DirectQuery, it covers one DAX query.
- A connector upgrade at the customer can silently turn classified traffic into UNKNOWN, which looks like a cost drop in "Power BI compute".
Resolution:
- Mode = `HostContext` suffix (Import|DirectQuery), else UNKNOWN.
- ActivityId is validated as a UUID and scoped by (tenant, account). The same ActivityId across accounts is never merged.
- Activity metrics are split by mode and never averaged across modes.
- Dataset/report are removed from the R1 data model. The UI states "not available from Snowflake metadata". A Microsoft API integration is out of the baseline (`workloads.md`).
- A capability monitor computes `pbi_tag_coverage = PBI-session queries with tag / PBI-session queries` per day and raises a Data Health warning when it drops > 20 points week-over-week.
Affects: WRK-003, WRK-101, UX (power-bi pages), ING-012.

### G-WRK-04 · Stored-procedure trees exist only in QUERY_ATTRIBUTION_HISTORY/ACCESS_HISTORY, and the source catalog does not extract them
Severity: HIGH · Type: VENDOR-FACT / GAP
Evidence:
- QUERY_HISTORY has no parent query ID. QUERY_ATTRIBUTION_HISTORY and ACCESS_HISTORY expose `parent_query_id` and `root_query_id`, populated from mid-January 2024, and Snowflake documents summing a procedure's cost by `root_query_id`. VERIFIED (search snippets of docs.snowflake.com/en/sql-reference/account-usage/query_attribution_history, …/user-guide/cost-attributing, …/release-notes/bcr-bundles/2023_08/bcr-1265, 2026-09-27).
- `source-catalog.md` QAH projection: "QUERY_ID, START_TIME, END_TIME, WAREHOUSE_ID, CREDITS_ATTRIBUTED_COMPUTE, CREDITS_USED_QUERY_ACCELERATION". The parent/root columns are missing.
- The catalog already notes "very short queries can be absent" from QAH.
- `workloads.md`: "Task/procedure/... workloads use verified execution IDs and parent/root fields where available".
Why it matters:
- Without the two columns in the extraction projection, WRK-004 cannot link any child query to its procedure.
- Even with them, children absent from QAH (very short or non-warehouse queries) cannot be linked. ACCESS_HISTORY covers only object-accessing queries and requires Enterprise edition.
- Adaptive warehouses (QUERY_METERING_HISTORY) may not carry the fields (TO VERIFY LIVE).
- Procedure-level cost is therefore a lower bound with explicit linkage coverage, not a total.
Resolution:
- ING adds `PARENT_QUERY_ID, ROOT_QUERY_ID` to the QAH projection (and to ACCESS_HISTORY if that source is activated). They are capability-probed by CON-005.
- Linkage precedence: QAH root/parent → ACCESS_HISTORY root/parent → none (UNLINKED).
- Procedure cost = Σ distinct child `query_compute_cost` where linked + the CALL query's own cost. `procedure_linkage_coverage` = linked child compute / (linked + unlinked compute in the same session window) is shown. The procedure is never presented as complete.
Affects: WRK-004, ING-001/ING-003 (projection), CON-005.

### G-WRK-05 · Task graphs: native IDs exist, but serverless task cost is not per run
Severity: HIGH · Type: VENDOR-FACT / GAP
Evidence:
- ACCOUNT_USAGE.TASK_HISTORY exposes `ROOT_TASK_ID` and `GRAPH_RUN_GROUP_ID` (the graph-run identifier), and `QUERY_ID` is populated once a task starts running. VERIFIED (search snippets of docs.snowflake.com/en/sql-reference/account-usage/task_history and …/bcr-bundles/2023_06/bcr-1147, 2026-09-27). `ATTEMPT_NUMBER` and `COMPLETED_TASK_PREDECESSORS` are TO VERIFY LIVE.
- `source-catalog.md` SERVERLESS_TASK_HISTORY grain is "Account+task+instance+time dimensional snapshot" with `CREDITS_USED`.
- The UI fixture shows "Task pipeline cost: $700 — Included in serverless total" per pipeline run.
Why it matters:
- A graph run is identified by (account, ROOT_TASK_ID, GRAPH_RUN_GROUP_ID), and warehouse-backed task runs link to their query (and, through QAH `root_query_id`, to a procedure's children).
- Serverless task credits, however, are reported per task per time window, not per run. Per-run serverless cost must be allocated by run-duration overlap within the window, which is an approximation.
- Retries of a graph may share the group ID, so counting runs by `RUN_ID` would double count.
Resolution:
- `fct_task_graph_run(tenant, account, root_task_id, graph_run_group_id, attempt, state, scheduled_time, start, end)` and `fct_task_run(…, task_id, query_id, attempt)`.
- Warehouse task cost = linked query cost (exact).
- Serverless task cost per run = window credits × (run seconds overlapping window / Σ run seconds of that task in window), labelled `APPROXIMATE_OVERLAP`. The residual stays at task level if no run overlaps.
- Run counts use distinct (root_task_id, graph_run_group_id) with the latest attempt state.
- A cycle in the observed predecessor data (impossible natively, possible through data errors) breaks the edge with a warning.
Affects: WRK-004, FIN-013.

### G-WRK-06 · Dynamic tables: refresh history is in Account Usage, but the dependency graph is an Information Schema function
Severity: MEDIUM · Type: VENDOR-FACT
Evidence:
- ACCOUNT_USAGE.DYNAMIC_TABLE_REFRESH_HISTORY includes `QUERY_ID`, `STATE`, `REFRESH_ACTION`, `REFRESH_TRIGGER`, `DATA_TIMESTAMP`, with latency up to 3 hours.
- DYNAMIC_TABLE_GRAPH_HISTORY (dependencies) is an Information Schema table function.
- VERIFIED (search snippets of docs.snowflake.com/en/sql-reference/account-usage/dynamic_table_refresh_history and …/user-guide/dynamic-tables-monitor, 2026-09-27).
- `pages/workloads.md` dynamic-tables: "Refresh cost and freshness objectives together"; fixture `lag` "Observed freshness lag: 4 min against 5 min target".
Why it matters: DT refresh cost is exact through `QUERY_ID` → QAH. The DAG view needs per-database INFORMATION_SCHEMA calls in the customer account, which is the "hot path" family deferred by D-24.
Resolution:
- R1: DT refresh list, cost per refresh (via QUERY_ID), and lag = refresh end − DATA_TIMESTAMP (p95 over refreshes; the target lag comes from the DT metadata if extracted, else UNKNOWN).
- R2: the DAG from DYNAMIC_TABLE_GRAPH_HISTORY under D-24.
- Classification: DT refresh queries are `workload_type=DYNAMIC_TABLE` with VERIFIED evidence via the refresh QUERY_ID join.
Affects: WRK-004, ING (projection), D-24.

### G-WRK-07 · Classifier precedence, confidence and spoofing are undefined; the PRD's Python-classifier stage is the wrong execution model
Severity: HIGH · Type: GAP (challenges PRD §53/§54 `workload_classifier` → `PY_WORKLOAD_CLASSIFICATION`)
Evidence:
- WRK-001 MT1: "explicit metadata→session→approved comment→weak query type precedence with conflict capture". The API is "Pure classify(sanitized_record,session,config)→typed result persisted in Snowflake". No confidence scale, no conflict rule, no revision rule for late-arriving sessions.
- PRD §54 lists `PY_WORKLOAD_CLASSIFICATION` as a Python output table.
Why it matters:
- Any Snowflake user can write `/* {"app":"dbt","node_id":"model.finance.x"} */` or set `QUERY_TAG` to mimic Power BI and move cost into another team's workload.
- The SESSIONS row can arrive hours after the query (latency), so the first classification is UNKNOWN and must be revised.
- A Python row-by-row stage between dbt runs adds a Snowflake → Python → Snowflake round trip over millions of queries per day (D-06 multi-tenant set-based runs).
Resolution:
- (1) Evidence classes (not fake-precise scores):
  - VERIFIED: native linkage — task QUERY_ID, DT refresh QUERY_ID, QAH root/parent, Bridge's own tag.
  - DECLARED_CORROBORATED: structured comment or tag + matching session application.
  - DECLARED: structured comment/tag or a customer rule.
  - OBSERVED: session application only.
  - INFERRED: query_type/user heuristics.
  - UNKNOWN.
- (2) Precedence table (§3): VERIFIED > DECLARED_CORROBORATED > DECLARED > OBSERVED > INFERRED. Two candidates at ≥ DECLARED that disagree on `workload_type` → `conflict=true`, the higher precedence wins, and the candidates array is stored. A comment claiming dbt while the session is Snowsight gives CONFLICT, never DECLARED_CORROBORATED.
- (3) Classification runs **as set-based dbt SQL** over structured evidence (WRK-101 output + joins), with the rules table versioned (D-16 engine for customer rules). The pure Python `classify()` is kept as the reference oracle for differential tests. This keeps the PRD's separation of responsibilities without a per-row Python pass.
- (4) Classification is revisioned (D-05). A late SESSIONS row re-classifies the query in the next run, and the change is visible through publication.
Affects: WRK-001, ALC-001 (workload dimension), DBT-006.

### G-WRK-08 · D-11 retention tiering breaks 365-day workload views unless execution-level facts are retained separately
Severity: HIGH · Type: GAP
Evidence:
- D-11: "Query-level detail hot for 90 days … query-family × day aggregates (parameterized hash) for 400 days".
- The workload pages show invocation/model histories and p95s (`modelp95`, `runduration`) over periods selectable up to 365 days (`product.md` presets).
- WRK-005 compares baseline vs current windows.
- `workloads.md`: "Never promise operator evidence for all one-year-old queries".
Why it matters:
- After 90 days, "dbt project → invocation → model" has no queries to aggregate, and family×day aggregates keyed by parameterized hash do not carry invocation or model identity.
- A comparison whose baseline is older than 90 days cannot compute per-execution unit cost.
- Model p95 over a year would require averaging percentiles.
Resolution:
- Retain **execution-level facts for 400 days**: dbt model executions, dbt invocations, PBI activities, task graph runs, DT refreshes. These are 2–3 orders of magnitude smaller than queries. Each carries cost, query count, wall time, execution sum and status.
- Query family × day keeps t-digest and HLL states (API G-API-04).
- UI tier labels: execution-level exact for 400 days; query-level 90 days.
- Operator evidence is 14 days (G-WRK-09).
- WRK-104 builds these facts and purges.
Affects: WRK-002…WRK-005, WRK-104, API-001, UX-005, ING-001.

### G-WRK-09 · On-demand GET_QUERY_OPERATOR_STATS runs in the customer account, costs customer credits and needs per-warehouse grants
Severity: MEDIUM · Type: VENDOR-FACT / GAP
Evidence:
- `workloads.md`: "GET_QUERY_OPERATOR_STATS covers completed queries from the past 14 days and requires OPERATE or MONITOR on the warehouse". Confirmed: 14 days; OPERATE or MONITOR on the warehouse where the query ran (search snippets of docs.snowflake.com/en/sql-reference/functions/get_query_operator_stats, 2026-09-27).
- WRK-005 MT2: "Fetch supported operator statistics on demand with strict query ID/account authorization and timeout".
- D-07 (account-cycle ECS tasks) and D-08 (dedicated customer warehouse).
Why it matters:
- The function must be executed by Bridge's WIF identity **in the customer account**, resuming `BRIDGE_FINOPS_WH`. At 60 s minimum billing per resume, an XS warehouse costs about 1/60 credit per isolated request.
- It needs MONITOR on **every** customer warehouse. Warehouses are account-level objects, so a future grant does not cover new warehouses (TO VERIFY LIVE); every new warehouse becomes a grant gap.
- Operator attributes include filter and join expressions that can contain literals, so the output must be sanitized.
- A request cannot run inside the scheduled account-cycle task without adding minutes of latency.
Resolution: new task **WRK-103** (R2 per RELEASE_PLAN):
- An on-demand extraction job type in the D-07 worker, launched with the account's task role, with its own admission (≤ 20 requests/user/day, ≤ 200/tenant/day, batching requests within 60 s into one warehouse resume).
- Query age ≤ 14 days is checked before launch; otherwise UNAVAILABLE(RETENTION_EXPIRED).
- The output passes through the SEC-007 sanitizer (expressions → literal-free), is capped at 1 MB, and is stored as an **evidence artifact** in S3 (tenant prefix, KMS, 30-day TTL) plus PG metadata. It is not an analytical table (it is not additive data).
- The install script (CON-003) grants MONITOR per warehouse; the CON-005 probe detects new warehouses without it, and Integration Health shows the remediation GRANT (UX-103).
- The UI shows the estimated customer credits per request.
Affects: WRK-005, WRK-103, CON-003, CON-005, UX-103, SEC-007.

### G-WRK-10 · The comparison oracle presumes a specific decomposition order that the spec does not state
Severity: MEDIUM · Type: AMBIGUITY
Evidence: WRK-005 MT3: "baseline 10 runs × 2 = 20, current 20 × 3 = 60; explain +40 as volume +20 and unit cost +20 under fixed decomposition order".
Why it matters: the same inputs give different splits depending on the order.
- Volume first at baseline unit cost: (20 − 10) × 2 = **20**; unit cost at current volume: 20 × (3 − 2) = **20**.
- Unit cost first at baseline volume: 10 × (3 − 2) = 10; volume at current unit cost: (20 − 10) × 3 = 30.
- Symmetric (Shapley/midpoint): volume = 10 × 2.5 = 25; unit cost = 1 × 15 = 15.
All sum to +40. Without a stated formula, two engineers produce different "drivers".
Resolution:
- Fix the formula as **volume at baseline unit cost, then unit cost at current volume** (matches the oracle): ΔC = (V₁ − V₀)·u₀ + V₁·(u₁ − u₀). Apply it per matched entity (model / activity / graph), then sum.
- New entities (V₀ = 0) go to a `NEW` bucket; disappeared entities go to a `DISAPPEARED` bucket, labelled "not observed in current window", never "deleted".
- Report the residual explicitly: zero by construction per entity; non-zero only from rounding at 12 dp.
- Minimum sample: ≥ 5 executions in each window per entity, else `INSUFFICIENT_BASELINE`.
- Windows must be complete and of equal length, else `comparison_status=PARTIAL`.
Affects: WRK-005.

### G-WRK-11 · Wall-clock and invocation semantics for partial, cross-boundary and approximate groupings are undefined
Severity: MEDIUM · Type: AMBIGUITY
Evidence: `workloads.md`: "Wall-clock invocation duration is max(end)-min(start) for a complete invocation … Optional approximate session/time groups are clearly labelled and excluded from exact run metrics". WRK-002 oracle: "Two concurrent 10 s queries have invocation wall time 10 s, execution sum 20 s".
Why it matters:
- An invocation straddling the period boundary (23:50–00:20 UTC) is counted in both periods or in neither.
- An invocation whose queries are partly missing from QAH or the hot tier has an understated wall time.
- dbt runs each thread on its own connection, so `SESSION_ID` never groups a whole invocation. A naive session grouping undercounts wall time and overcounts runs.
Resolution:
- An invocation belongs to the period containing its **start**. Cost is still apportioned by query `start_time` for financial totals, so money and run counts use documented, different rules.
- `complete=true` only if the status is terminal and no gap in the query stream is flagged. Wall time is exposed for complete invocations only.
- A model execution = contiguous queries with the same `node_id` in one session (OBSERVED).
- Approximate invocation = same (account, user, role, profile_name, target_name), inter-query gap ≤ 10 min, span ≤ 24 h, flagged `APPROXIMATE`. It is excluded from `execution_count` and exact-run KPIs, but its cost is included in project totals.
Affects: WRK-002, WRK-003, WRK-004.

### G-WRK-12 · Workload tasks are over-serialized behind API-001 and UX-005
Severity: MEDIUM · Type: GAP
Evidence: task-index.json: WRK-001 ← API-001 (← FIN-009); WRK-002/003/004 ← UX-005; WRK-005 ← WRK-003 (Power BI, R1* per RELEASE_PLAN) and API-004; ALC-001 ← WRK-001; GOV-002 ← WRK-005.
Why it matters: WRK-001 is on the 73-task critical path (AUDIT X-05), even though the classifier needs sanitized query records and resource history, not the metric registry. The workload pages need the UX-002 data layer and API-104 records, not the warehouse deep-dive page. WRK-005 would wait for Power BI even when Power BI is out of R1.
Resolution:
- WRK-001: −API-001, +WRK-101.
- WRK-002/003/004: −UX-005, +UX-002, +API-104, +WRK-104.
- WRK-005: −WRK-003 (unless R1*), keep API-004; operator evidence moves to WRK-103.
- GOV-002: −WRK-005 (lead finding).
- ALC-001 keeps WRK-001, which is now earlier.
Affects: WRK-001…WRK-005, ALC-001, GOV-002.

### G-WRK-13 · Bridge's own extraction queries must be a first-class workload
Severity: MEDIUM · Type: GAP
Evidence: D-08: "extractor sets QUERY_TAG `bridge_finops:<component>`; product labels Bridge's own queries as 'Bridge overhead' workload". No WRK task mentions it. The ad hoc page says "Make unclassified usage inspectable".
Why it matters: without an explicit rule, Bridge's own Account Usage queries appear as customer ad hoc or UNKNOWN cost. That inflates "unclassified", and customers see the tool's cost disguised as their own activity.
Resolution: the WRK-101 tag parser recognizes the prefix `bridge_finops:` (component ∈ {extract, probe, operator_stats, install}) → `workload_type=BRIDGE_OVERHEAD`, evidence VERIFIED (the tag is set by Bridge; spoofing it only moves the spoofer's own cost into a visible bucket). The Workloads overview (WRK-102) shows it as its own row with the D-08 quota comparison.
Affects: WRK-101, WRK-001, WRK-102, UX-103.

### G-WRK-15 · The ING backfill plan drops QUERY_TEXT beyond 90 days, which permanently loses a year of dbt identity at onboarding
Severity: HIGH · Type: CONTRADICTION (with [ING.md](ING.md) ING-010-S04)
Evidence:
- ING-010-S04: "QUERY_TEXT not projected for windows older than the hot horizon (D-11) … The generated SQL for a day 200 days old lacks QUERY_TEXT".
- ING.md: "Backfilling QUERY_TEXT beyond the 90-day hot window wastes 75 % of the CPU on text that D-11 discards".
- The default dbt comment lives **only** in QUERY_TEXT, at its end (G-WRK-02).
- G-WRK-08 keeps execution-level facts for 400 days.
Why it matters: at onboarding, days 91–365 of dbt activity would carry no `node_id`/`invocation_id` evidence. Once those days leave Account Usage's 365-day window, they can never be recovered. dbt project/model history, WRK-005 baselines and the INS-003 pipeline detectors would all start 90 days back instead of a year back. ING's CPU argument is valid for full AST sanitization, not for metadata extraction.
Resolution:
- For windows older than the hot horizon, the extraction SQL projects only the trailing comment, computed **in the customer warehouse**: `REGEXP_SUBSTR(QUERY_TEXT, '/\\*[^*]*\\*+([^/*][^*]*\\*+)*/\\s*;?\\s*$')` truncated to 4,096 chars as `QUERY_TEXT_TAIL_COMMENT`. Leading comments are removed by Snowflake anyway (G-WRK-02).
- WRK-101 runs its lexer on that fragment only (no AST, microseconds per row) and persists only `WorkloadMetaV1`. No SQL text is stored.
- The customer-credit and bytes impact of the regex over ~275 M cold rows is TO VERIFY LIVE in ING-101, and disclosed in the D-08 estimate.
Affects: ING-010, ING-101, WRK-101, WRK-104, D-08.

### G-WRK-14 · Native App and custom-application identity have no defined evidence sources
Severity: LOW · Type: GAP
Evidence: `pages/workloads.md` native-apps: "Provider fees and execution costs as distinct components"; custom-apps: "Verified application identity before cost attribution". FIN-020 covers the marketplace/app fee separation. Nothing defines what a "verified application identity" is.
Why it matters: without a rule, a custom app is whatever a regex on USER_NAME says, which is a guess presented as a fact.
Resolution (R2, WRK-105):
- Custom app identity = customer-declared rules over QUERY_TAG keys, SERVICE-type users (`USER_TYPE` if projected — TO VERIFY LIVE column availability) or `CLIENT_ENVIRONMENT:APPLICATION`, with evidence class DECLARED/OBSERVED.
- Native App consumer-side execution visibility in QUERY_HISTORY is TO VERIFY LIVE. Until verified, the page shows app fees (FIN-020) and SPCS pool usage by `APPLICATION_ID` (SPCS history, verified fields) and nothing else.
Affects: WRK-105, FIN-020.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by (task/micro-task) |
|---|---|---|
| Allowlist v1 `packages/workload_meta/allowlist_v1.yaml` | **dbt comment/tag keys kept:** `app`, `dbt_version`, `profile_name`, `target_name`, `node_id`, `connection_name`, `invocation_id`, `project_name`, `node_resource_type`, `node_package_name`, `materialized`, `full_refresh`, `which`, `run_started_at`, `is_incremental`, `dbt_cloud_project_id`, `dbt_cloud_job_id`, `dbt_cloud_run_id`, `dbt_cloud_run_reason_category`, `dbt_snowflake_query_tags_version`/`dbt_query_tags_version`. **Dropped always:** `node_meta`, `node_tags` (R2 opt-in), `invocation_command`, `dbt_cloud_run_reason`, `node_original_file_path`, `node_refs`. **Pseudonymized (D-10):** `target_schema`/`node_schema` when matching a personal-schema pattern (`^dbt_[a-z]+`). **Power BI:** `PowerQuery`, `Host`, `HostContext`, `ActivityId` (UUID). **Bridge:** prefix `bridge_finops:<component>`. **Customer keys:** ≤ 10 tenant-declared keys, value regex `^[A-Za-z0-9_.:\-/ ]{1,128}$`, email-pattern values dropped. Value limits: node_id ≤ 512 chars matching `^(model\|test\|seed\|snapshot\|operation\|analysis\|sql_operation\|unit_test\|source)\.[A-Za-z0-9_]+\.[A-Za-z0-9_.\-]+$`; others per G-SEC-15 regex | WRK-101-S01 |
| `WorkloadMetaV1` Arrow schema | `wlmeta_version`, `dbt_meta_status` (ABSENT\|PARSED\|MALFORMED\|TRUNCATED\|DROPPED_POLICY), `dbt_*` fields above, `pbi_mode`, `pbi_activity_id`, `bridge_component`, `customer_tag_values` (map), `tag_format` (JSON\|TEXT\|NONE), `comment_position` (TAIL\|HEAD) | WRK-101-S05 |
| Evidence and classification DDL | `int_query_workload_evidence(tenant_id, account_id, query_id, evidence_source ∈ {NATIVE_TASK, NATIVE_DT, NATIVE_PROC_ROOT, BRIDGE_TAG, DBT_COMMENT, DBT_TAG, PBI_TAG, CUSTOMER_RULE, SESSION_APP, QUERY_TYPE}, evidence_class, workload_type_candidate, application, project_key, environment_key, execution_id, parent_query_id, root_query_id, rule_version, parser_version)`; `fct_query_workload(tenant_id, account_id, query_id, workload_type, workload_key, application, project, environment, execution_id, execution_kind, evidence_class, conflict, candidates VARIANT, classifier_version, revision_id)`; unique (tenant_id, account_id, query_id, revision_id) | WRK-001-S01 |
| Workload taxonomy enum | DBT, POWER_BI, TASK, PROCEDURE, DYNAMIC_TABLE, SNOWPIPE, NATIVE_APP, SPCS, CORTEX, CUSTOM_APP, BI_OTHER, AD_HOC, BRIDGE_OVERHEAD, UNKNOWN; versioned | WRK-001-S01 |
| Precedence table `classifier_rules_v1.yaml` | Ordered rules: (1) BRIDGE_TAG → BRIDGE_OVERHEAD VERIFIED; (2) NATIVE_* → TASK/DT/PROCEDURE VERIFIED; (3) DBT_COMMENT/TAG + SESSION_APP≈dbt → DBT DECLARED_CORROBORATED; (4) DBT_COMMENT/TAG alone → DBT DECLARED; (5) PBI_TAG → POWER_BI DECLARED(_CORROBORATED if session ≈ Power BI); (6) CUSTOMER_RULE → declared type DECLARED; (7) SESSION_APP → mapped type OBSERVED; (8) QUERY_TYPE CALL → PROCEDURE INFERRED, Snowsight/worksheet session → AD_HOC OBSERVED; (9) else UNKNOWN. Conflict rule: ≥ 2 candidates at ≥ DECLARED with different types → conflict=true | WRK-001-S03 |
| Session application map `session_app_map_v1.yaml` | Normalized patterns on `CLIENT_ENVIRONMENT:APPLICATION` / `CLIENT_APPLICATION_ID` → application (dbt, Power BI, Tableau, Looker, Snowsight, SnowSQL, Python connector, JDBC, ODBC…), each flagged TO VERIFY LIVE until observed in tenant zero | WRK-001-S02 |
| Execution graph DDL | `fct_execution(tenant, account, execution_id, kind ∈ {DBT_INVOCATION, DBT_MODEL_EXEC, PBI_ACTIVITY, TASK_GRAPH_RUN, TASK_RUN, PROCEDURE_CALL, DT_REFRESH}, start, end, status, complete, basis ∈ {VERIFIED, APPROXIMATE}, query_count, compute_cost, wall_time_s, exec_sum_s)`; `fct_execution_edge(tenant, account, parent_execution_id, child_execution_id \| child_query_id, edge_source, evidence_class)`; `fct_execution_query_link(tenant, account, execution_id, query_id)` — unique per (execution_id, query_id) so a query's cost is counted once per execution | WRK-004-S01 |
| Required source projections (to ING) | QAH + `PARENT_QUERY_ID`, `ROOT_QUERY_ID`; QUERY_HISTORY + `COMPILATION_TIME`, `QUEUED_OVERLOAD_TIME`, `QUEUED_PROVISIONING_TIME`, `QUERY_TAG` (sanitized by WRK-101); SESSIONS: `SESSION_ID`, `CREATED_ON`, `USER_NAME` (pseudonymized), `CLIENT_APPLICATION_ID`, `CLIENT_APPLICATION_VERSION`, `CLIENT_ENVIRONMENT:APPLICATION` only; TASK_HISTORY: `QUERY_ID`, `NAME`, `DATABASE_NAME`, `SCHEMA_NAME`, `ROOT_TASK_ID`, `GRAPH_RUN_GROUP_ID`, `RUN_ID`, `STATE`, `SCHEDULED_TIME`, `QUERY_START_TIME`, `COMPLETED_TIME`, `ATTEMPT_NUMBER` (TO VERIFY); DYNAMIC_TABLE_REFRESH_HISTORY: `QUALIFIED_NAME`, `QUERY_ID`, `STATE`, `REFRESH_ACTION`, `REFRESH_TRIGGER`, `DATA_TIMESTAMP`, `REFRESH_START_TIME`, `REFRESH_END_TIME` | WRK-101-S09 (handoff to ING backlog) |
| Comparison contract | Formula (G-WRK-10), entity matching keys per workload kind, window rules, min sample, output schema `{entity_key, bucket ∈ COMMON\|NEW\|DISAPPEARED, v0, u0, v1, u1, volume_effect, unit_cost_effect, residual}` | WRK-005-S01 |
| Operator evidence artifact schema | `{tenant, account, query_id, fetched_at, sanitizer_version, operators:[{id, parent_ids, type, stats:{…}, attributes_sanitized}], truncated}` ≤ 1 MB | WRK-103-S01 |
| Retention contract | Query-level 90 d (plan-configurable); execution-level 400 d; family×day with t-digest/HLL 400 d; operator artifacts 30 d, source limit 14 d | WRK-104-S01 |

## 4. Revised production backlog

### WRK-001 — Versioned workload classifier and evidence model
Release: R1 · Estimate: 34–48 h · Risk: H · Decisions: D-05, D-06, D-08, D-10, D-16 · Closes: G-WRK-07, G-WRK-13 (classification)
Dependency changes: `−API-001` (not needed), `+WRK-101` (structured metadata), keep `DBT-003`, `SEC-007`. Moves off the critical path. `ALC-001` keeps depending on WRK-001.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| WRK-001-S01 | Create the taxonomy enum and the evidence/classification DDL (§3) as dbt model contracts with unique keys and tenant columns | `data/dbt/models/intermediate/workload/*.yml`, `data/contracts/workload.json` | `dbt parse` passes; contract tests enforce the unique (tenant, account, query_id, revision) | 3 |
| WRK-001-S02 | Build the evidence producers in dbt SQL: from `WorkloadMetaV1` columns (dbt/PBI/Bridge/customer keys), SESSIONS application map, TASK_HISTORY query_id, DT refresh query_id, QAH root/parent, query_type heuristics, customer predicate rules (D-16 tables) | `int_query_workload_evidence.sql` | Fixture with 12 evidence kinds produces one row per (query, evidence_source) | 6 |
| WRK-001-S03 | Implement precedence and conflict resolution with the versioned rules table; candidates array; `conflict` flag | `fct_query_workload.sql`, `classifier_rules_v1.yaml` seed | Conflicting-tags fixture (dbt comment + PBI tag on one query) → conflict=true, both candidates stored | 4 |
| WRK-001-S04 | Spoof resistance: corroboration rule (comment + session dbt → DECLARED_CORROBORATED; comment + Snowsight session → CONFLICT); customer rules cannot override VERIFIED | SQL + tests | Spoofed comment from a Snowsight session never becomes DECLARED_CORROBORATED | 2 |
| WRK-001-S05 | Identity keys: `workload_key = sha256(tenant, account, workload_type, project_key, environment_key)`; project from `project_name` else `node_id` package; environment via tenant mapping of target_name (raw label kept); keys independent of parser_version | SQL + macro | Parser version bump with identical inputs → identical workload_key | 3 |
| WRK-001-S06 | Late-evidence revision: queries classified UNKNOWN because SESSIONS arrived late are re-evaluated for 48 h (session latency + margin) and republished as a new revision | incremental logic | Fixture: session arrives 3 h late → next run reclassifies and publication shows the new revision | 3 |
| WRK-001-S07 | Python reference `classify()` + differential test against SQL on 5,000 generated rows | `services/intelligence/workload_classifier/reference.py`, test | 0 differences | 4 |
| WRK-001-S08 | Coverage metric inputs for `workload_classification_coverage` and per-evidence-class breakdown (registry binding in API-001) | serving columns | Fixture: 14,000 classified / 14,000 = 100 %; with one UNKNOWN query of 100 → 13,900/14,000 | 2 |
| WRK-001-S09 | Tenant isolation: identical node_id/ActivityId/project names in tenants A and B never share keys; duplicate query_id across accounts stays distinct | tests | Cross-tenant join count = 0 | 2 |
| WRK-001-S10 | Task-oracle tests: conflicting tags; spoofed app text; absent session → UNKNOWN; legacy prepended dbt comment (stripped by Snowflake) → no dbt evidence; Bridge tag → BRIDGE_OVERHEAD; replay under the same versions → identical output hash | `tests/spec/WRK-001/*` | All pass locally (DuckDB/dbt fixtures) and on staging | 4 |
| WRK-001-S11 | Observability and docs: `workload_classification_total{class,type}`, conflict rate alarm (> 2 % of compute), classifier_version in the publication manifest | dashboards, `docs/10-frontend/workloads.md` change request | Metrics visible; doc reviewed | 2 |

Task acceptance:
- [ ] Every query has exactly one current classification with an evidence class. UNKNOWN is explicit and never defaulted to AD_HOC.
- [ ] Conflicting or spoofed evidence is flagged. VERIFIED linkage cannot be overridden by comments or customer rules.
- [ ] Replaying under the same versions is bit-identical. Late sessions produce a new revision, not an in-place edit.
- [ ] No hierarchy crosses a tenant or an account.

### WRK-002 — dbt project, invocation and model intelligence
Release: R1 · Estimate: 40–56 h · Risk: M · Decisions: D-11, D-20 · Closes: G-WRK-02 (downstream), G-WRK-11
Dependency changes: `−UX-005`, `+UX-002`, `+API-104`, `+WRK-104`; keep `WRK-001`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| WRK-002-S01 | Verify live (tenant zero) what dbt Core 1.x, dbt Fusion (if used) and dbt Projects on Snowflake emit: comment position, keys, session application, root query id for `EXECUTE DBT PROJECT`; record findings | `docs/evidence/WRK-002/<commit>/dbt-signals.md` | Each signal marked VERIFIED or ABSENT with a query_id sample | 3 |
| WRK-002-S02 | Build `fct_dbt_model_execution` (session_id + node_id + contiguity; cost = Σ distinct query links; wall; exec sum; status) and `fct_dbt_invocation` (VERIFIED by invocation_id, else APPROXIMATE grouping per G-WRK-11) | `data/dbt/models/marts/dbt_workloads/*` | Fixture inv_0830: 140 + 84 + 56 = 280; wall 13 min; duration sum 17 min | 6 |
| WRK-002-S03 | Node taxonomy (model/test/seed/snapshot/operation) and the "dbt overhead" bucket for `connection_name` queries; project = project_name or node package (flag basis) | SQL | Overhead queries appear under their project's overhead row, not under a model | 2 |
| WRK-002-S04 | Metrics: executions, cost/execution, cost/model, failures (terminal failed status), p95 model duration over model executions (not averaged), query counts | serving view columns + registry bindings | modelp95 computed over executions; the registry test proves non-averaging | 3 |
| WRK-002-S05 | Regression: per model, median cost/execution current vs baseline (complete windows, ≥ 5 executions each) with `INSUFFICIENT_BASELINE` otherwise | SQL | Fixture with 4 baseline runs → INSUFFICIENT_BASELINE | 3 |
| WRK-002-S06 | Unassigned buckets: detected-by-session-only → "unassigned project"; no invocation → "unassigned invocation"; first-class filters | SQL + API filters | Buckets appear in the filter list and sum into project totals | 2 |
| WRK-002-S07 | Common/new/disappeared models across complete periods; wording "not observed" (never "deleted") | SQL | Disappeared model labelled "not observed in current window" | 2 |
| WRK-002-S08 | Records datasets for invocations and model executions (API-104) + dimensions (dbt_project, dbt_environment, dbt_model, dbt_resource_type) | registry YAML | API-104 serves invocation lists with keyset paging | 2 |
| WRK-002-S09 | UI: /explore/workloads/dbt, project, invocation (DAG of models from observed order, concurrency lanes), model pages per screen contracts; exact-run KPIs disabled with reason when APPROXIMATE | `apps/web/src/pages/workloads/dbt/*` | Screens pass UX-008 state matrix; approximate grouping never shows run counts | 9 |
| WRK-002-S10 | Customer enhancement guide: `query-comment` snippet adding `invocation_id` with `append: true`, optional query_tag macro; shown in empty/partial states and ONB docs | `docs/customer/dbt-metadata.md` | Snippet validated on tenant zero: invocation_id appears in QUERY_TEXT tail | 2 |
| WRK-002-S11 | Tests: two concurrent 10 s queries → wall 10 s, exec sum 20 s; missing invocation → no run count; each query cost once across model/invocation/project; same model name in two projects distinct; failed then retried model counted as 2 executions, 1 failure; invocation across the midnight boundary belongs to its start period | `tests/spec/WRK-002/*` | All pass | 4 |
| WRK-002-S12 | a11y/mobile/screenshots for the four pages | evidence | Axe clean | 2 |

Task acceptance:
- [ ] Exact run metrics appear only with verified invocation IDs. Approximate groups are labelled and excluded from run counts.
- [ ] Each query's cost is counted once at every hierarchy level, and the fixture reproduces 280 / 13 min / 17 min.
- [ ] Missing history never produces a "deleted" claim.

### WRK-003 — Power BI activity and mode intelligence
Release: R1* (D-20: only if the first customer uses Power BI on Snowflake) else R2 · Estimate: 24–34 h · Risk: M · Decisions: D-20 · Closes: G-WRK-03
Dependency changes: `−UX-005`, `+UX-002`, `+API-104`, `+WRK-104`; keep `WRK-001`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| WRK-003-S01 | Verify live on tenant zero or the design partner: QUERY_TAG keys from Service DirectQuery and Import refresh, Desktop behavior, connector 1.0 vs 2.0, session application strings | evidence doc | Each signal VERIFIED/ABSENT with samples | 3 |
| WRK-003-S02 | Build `fct_pbi_activity(tenant, account, activity_id, mode, start, end, query_count, compute_cost, wall_s, status)` from tag evidence; mode from HostContext; UNKNOWN when absent | `data/dbt/models/marts/powerbi/*` | Fixture pbi_0830: 8 + 24 = 32 queries; 56 + 168 = 224 USD | 4 |
| WRK-003-S03 | Session-only Power BI traffic (no tag) → POWER_BI/UNKNOWN mode bucket with OBSERVED evidence | SQL | Desktop-style fixture lands in the UNKNOWN-mode bucket | 2 |
| WRK-003-S04 | Mode-separated metrics (never averaged across modes); activity retries with the same ActivityId → one activity, distinct queries counted once | SQL | Retry fixture: 3 queries (2 + 3 + 5) with one duplicate delivery → activity cost 10 | 3 |
| WRK-003-S05 | Tag-coverage capability monitor (`pbi_tag_coverage` daily; Data Health warning on a 20-point weekly drop) | SQL + ING-012 hook | A synthetic drop triggers the warning | 2 |
| WRK-003-S06 | Records dataset + dimensions (pbi_mode, pbi_activity) | registry YAML | API-104 serves activity lists | 2 |
| WRK-003-S07 | UI: /explore/workloads/powerbi and activity detail; explicit "dataset/report not available from Snowflake metadata"; "Snowflake-side cost only, excludes Fabric capacity" label | pages | Screens pass the state matrix; no fabricated dataset name | 6 |
| WRK-003-S08 | Tests: one ActivityId across two accounts stays two activities; missing mode stays UNKNOWN; no dataset/Fabric fields in API payloads | tests | All pass | 3 |

Task acceptance:
- [ ] Activity cost = Σ distinct query costs (2 + 3 + 5 = 10), and retries are not double counted.
- [ ] Unknown mode stays UNKNOWN. No dataset, report or Fabric cost is fabricated.
- [ ] A drop in tag coverage is surfaced as a data-health warning, not a cost change.

### WRK-004 — Tasks, procedures and dynamic-table execution graphs
Release: R1 · Estimate: 40–56 h · Risk: H · Decisions: D-11, D-14, D-24 · Closes: G-WRK-04, G-WRK-05, G-WRK-06
Dependency changes: `−UX-005`, `+UX-002`, `+API-104`, `+WRK-104`; `+ING` projection change (QAH parent/root, TASK_HISTORY, DT refresh — owner ING backlog); keep `WRK-001`, `FIN-013` (serverless task cost only; the graph build does not wait for it). The workloads overview, native apps and custom apps move to WRK-102/WRK-105.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| WRK-004-S01 | Create the execution graph DDL (§3) as dbt contracts | `data/dbt/models/marts/workload_graph/*.yml` | Contracts enforce unique (execution_id, query_id) links | 2 |
| WRK-004-S02 | Task graph runs: build graph runs from TASK_HISTORY (root_task_id, graph_run_group_id, attempt), task runs → query_id links; latest-attempt state; run counts by distinct graph run | SQL | Retry fixture (attempt 1 failed, attempt 2 succeeded) → 1 graph run, SUCCEEDED, 2 task-run rows | 4 |
| WRK-004-S03 | Warehouse task cost = linked query cost (exact); serverless task cost per run = overlap allocation of SERVERLESS_TASK_HISTORY window credits (APPROXIMATE_OVERLAP), residual at task level | SQL | Fixture: window 0.6 credits, runs of 120 s and 60 s → 0.4 / 0.2; task residual 0 | 4 |
| WRK-004-S04 | Procedure trees from QAH root/parent (then ACCESS_HISTORY), CALL query included; linkage coverage per procedure; UNLINKED otherwise | SQL | Nested procedure fixture (P → P2 → 3 queries) sums once at P and once at P2 without double counting in P's total | 4 |
| WRK-004-S05 | Dynamic tables: refresh executions from DT refresh history, cost via QUERY_ID, lag = refresh end − DATA_TIMESTAMP, p95 lag; DAG deferred (R2, D-24) | SQL | Fixture lag values give p95 4 min vs target 5 min | 3 |
| WRK-004-S06 | Parent totals = Σ distinct descendant query links (set semantics); parent wall time separate from child sums; shared child counted once per parent, once in totals | SQL | Shared-child fixture: the child query linked to two parents appears once in the tenant total | 3 |
| WRK-004-S07 | Graph integrity: cycle detection (break the edge, warning), missing root (UNLINKED), query-id collisions across accounts (keys include account) | SQL tests | Cycle fixture yields a warning and an acyclic output | 2 |
| WRK-004-S08 | Bounded graph API: `GET /v1/entities/task_graph_run/{id}/graph?cursor` (≤ 500 nodes/page, lazy expand), evidence class and cost-inclusion flag per edge | route (API-104 extension) | 2,000-node fixture paginates; unauthorized nodes are not returned | 4 |
| WRK-004-S09 | UI: /explore/workloads/pipelines, pipeline-detail (graph + run history), procedures (linkage coverage column), dynamic-tables (cost + freshness) per screen contracts | pages | Screens pass the state matrix; dashed edges for APPROXIMATE/INFERRED | 9 |
| WRK-004-S10 | Tests from the task oracle: nested procedure, task retry, shared child, missing parent, cycle; graph cannot cross tenant/account | `tests/spec/WRK-004/*` | All pass | 4 |
| WRK-004-S11 | Observability: linkage coverage per tenant (alarm when procedure linkage < 50 % after QAH maturity), graph build duration | dashboards | Alarm visible in staging | 2 |

Task acceptance:
- [ ] A parent's cost = its unique child components once. Serverless per-run cost is labelled approximate.
- [ ] Unsupported or missing parent fields yield UNLINKED, never an invented parent.
- [ ] A graph cannot cross a tenant or an account, and it paginates under row policies.

### WRK-005 — Workload comparison (volume vs unit-cost decomposition)
Release: R1 · Estimate: 26–36 h · Risk: M · Decisions: D-11 · Closes: G-WRK-10
Dependency changes: `−WRK-003` (unless R1*), keep `WRK-002`, `WRK-004`, `API-004`. **On-demand operator evidence moves to WRK-103 (R2).** Downstream: `GOV-002 −WRK-005`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| WRK-005-S01 | Write the comparison contract (§3) incl. formula, window rules, min sample, buckets | `docs/10-frontend/workload-comparison.md` | Reviewed by FinOps + data owners | 2 |
| WRK-005-S02 | Implement the `workload_compare` job kind (API-004) over execution-level facts (400-day tier), entity matching per kind | `services/intelligence/workload_compare/*` | The job runs for baselines older than 90 days without query-level rows | 5 |
| WRK-005-S03 | Decomposition per entity: volume = (V₁ − V₀)·u₀; unit cost = V₁·(u₁ − u₀); NEW/DISAPPEARED buckets; residual reported | SQL/Python (Decimal FIN-106 context) | Oracle: 10×2 → 20×3 gives +40 = +20 volume + 20 unit cost, residual 0 | 3 |
| WRK-005-S04 | Window validation: complete, equal length, aligned; PARTIAL label; INSUFFICIENT_BASELINE (< 5 executions) | code | Unequal windows → 422 unless explicitly accepted, then PARTIAL | 2 |
| WRK-005-S05 | Performance regression view (p95 duration and queue per entity) kept separate from cost decomposition; no causal language | output schema | The API has no "cause" field; copy keys say "associated with" | 2 |
| WRK-005-S06 | UI: compare flow from workload detail (A/B pickers, coverage review, contributors table/waterfall, drill to hash/query where the hot tier allows) | `apps/web/src/pages/workloads/compare/*` | State matrix passes; contributors sum to the total delta | 6 |
| WRK-005-S07 | Tests: contributors sum to +40; missing history prevents a deleted-project claim; new model in current only → NEW bucket; mixed currency refused | tests | All pass | 3 |
| WRK-005-S08 | Export and saved comparison (API-102, CTL-007) | integration | Export equals the on-screen contributors | 2 |

Task acceptance:
- [ ] Contributors sum exactly to the total delta under the stated formula.
- [ ] Comparisons work for baselines older than 90 days, using execution-level facts.
- [ ] Missing history never yields "deleted". The copy makes no causal claim.

## 5. New tasks required

### WRK-101 — Workload metadata extraction library (dbt/PBI/Bridge/customer keys) for the sanitizer
Release: R1 (M1, with SEC-007) · Estimate: 22–30 h · Risk: H · Decisions: D-08, D-10, D-11 · Closes: G-WRK-01, G-WRK-02 (parsing), G-WRK-13 (tag), G-WRK-15
Dependency changes: new; depends on `SEC-001` (data classification), `FND-004` (fixtures). **SEC-007 depends on WRK-101.** WRK-001 depends on it. **ING-010 (backfill) depends on WRK-101-S12.** Must be frozen before `ONB-004`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| WRK-101-S01 | Author allowlist v1 (§3) with SEC review, including dropped/pseudonymized keys and value limits | `packages/workload_meta/allowlist_v1.yaml` | SEC and privacy reviewers sign off | 2 |
| WRK-101-S02 | Implement the comment lexer: find block comments outside string literals/identifiers (Snowflake quoting rules, `$$` bodies), prefer the last, then the first; JSON parse ≤ 4 KB | `packages/workload_meta/comment.py` | A `*/` inside a string literal does not end the comment; a comment inside a string is ignored | 3 |
| WRK-101-S03 | Implement the QUERY_TAG parser: JSON object vs text; PBI schema; `bridge_finops:` prefix; customer keys; dbt tag package keys | `packages/workload_meta/tag.py` | PBI Import and DirectQuery samples parse; malformed JSON → tag_format TEXT, nothing kept | 2 |
| WRK-101-S04 | Truncation detection (unterminated comment, or text length at the source limit — TO VERIFY LIVE value) → TRUNCATED | code | A 2 MB synthetic text with the tail cut → TRUNCATED | 1 |
| WRK-101-S05 | Emit `WorkloadMetaV1` (Arrow schema) and integrate as the first step of SEC-007 `sanitize()`; comments are then stripped from the SQL body; the metadata is never part of the sanitized-text cache key (G-SEC-15) | integration PR with SEC-007 | Two queries with the same parameterized hash and different invocation_ids keep their own invocation_ids | 3 |
| WRK-101-S06 | PII controls: drop email-pattern values, pseudonymize personal schema names (D-10 HMAC), drop forbidden keys even when nested | code | Sentinel emails and secrets from the query-tags package example (`dbt_cloud_run_reason`, `node_meta`, `invocation_command`) appear nowhere in the output, logs or quarantine | 3 |
| WRK-101-S07 | Adversarial/fuzz tests: nested/unterminated comments, 1 MB texts, Unicode confusables in keys (`nоde_id` with Cyrillic о), duplicate keys, deeply nested JSON | `tests/spec/WRK-101/*` | Fuzz 100k cases without exceptions; confusable keys are dropped | 3 |
| WRK-101-S08 | Golden corpus: real samples from dbt 1.8/1.9/1.10 (default comment, append true/false), the dbt query-tags packages, Power BI Service samples, Bridge extractor; each with the expected output | `tests/spec/WRK-101/corpus/` | Corpus passes; prepended-comment sample documents that Snowflake stripping yields ABSENT | 3 |
| WRK-101-S09 | Hand off the required source projections (§3) to the ING owner and the capability probes to CON-005 | ING/CON change requests | Accepted into ING-001/CON-005 backlogs | 1 |
| WRK-101-S10 | Versioning and irreversibility runbook: `wlmeta_version` bump procedure, re-extraction bounded to 365 days, customer credit estimate (D-08) | `docs/05-ingestion/workload-meta.md` | Reviewed by ING/SEC | 1 |
| WRK-101-S11 | Metrics: `wlmeta_parse_total{source,status}` with alarms on a MALFORMED rate > 5 % per account/day | instrumentation | Visible in staging | 1 |
| WRK-101-S12 | Cold-window mode (G-WRK-15): specify the `QUERY_TEXT_TAIL_COMMENT` projection for ING-010 and accept a fragment-only input path (no AST, no text persisted) | ING change request + `extract_fragment()` | On a 200-day-old fixture window, dbt node_id/invocation_id are extracted and no SQL text column is present in the Parquet output | 2 |

Task acceptance:
- [ ] Allowlisted keys are extracted before sanitization, and forbidden keys (emails, commands, meta) never persist.
- [ ] Tail comments are found even with string literals containing comment tokens. Truncation is detected.
- [ ] The allowlist is frozen and versioned before the first historical backfill.

### WRK-102 — Workloads overview, ad hoc and Bridge-overhead views
Release: R1 · Estimate: 14–20 h · Risk: L · Decisions: D-08 · Closes: G-UX-01 (workloads/ad-hoc), G-WRK-13 (UI)
Dependency changes: new; depends on `WRK-001`, `UX-002`, `API-104`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| WRK-102-S01 | Screen contracts for /explore/workloads (type breakdown, classification coverage, UNKNOWN, Bridge overhead) and /explore/workloads/ad-hoc | contracts | Reviewed | 2 |
| WRK-102-S02 | Overview page: query compute by workload_type with evidence-class composition, `workload_classification_coverage`, links to type pages | page | Fixture: dbt 8,400 + Power BI 5,600 = 14,000 classified (100 %) | 4 |
| WRK-102-S03 | Ad hoc page: AD_HOC and UNKNOWN by user (pseudonym/name per capability), role, warehouse, client application; sanitized query families only | page | No SQL text without the capability; UNKNOWN never labelled "ad hoc" | 4 |
| WRK-102-S04 | Bridge overhead row with D-08 quota comparison and a link to Integration Health | component | Bridge queries appear only in this row | 2 |
| WRK-102-S05 | Tests + a11y | tests | All pass; axe clean | 3 |

Task acceptance:
- [ ] Every classified and unclassified query-compute dollar appears exactly once in the overview.
- [ ] Bridge's own cost is visible and separate. UNKNOWN is not merged into ad hoc.

### WRK-103 — On-demand operator evidence (GET_QUERY_OPERATOR_STATS)
Release: R2 (per RELEASE_PLAN) · Estimate: 24–34 h · Risk: M · Decisions: D-07, D-08 · Closes: G-WRK-09
Dependency changes: new (split from WRK-005); depends on `API-004`, `ING-003` (account-cycle worker, D-07), `SEC-007`, `CON-005`, `UX-005`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| WRK-103-S01 | Define the evidence artifact schema and S3 layout (tenant prefix, KMS, 30-day TTL) + PG metadata table | schema + migration | Reviewed with SEC | 2 |
| WRK-103-S02 | API: `POST /v1/queries/{account}/{query}/operator-evidence` → job; pre-checks (query age ≤ 14 d from source end time, capability MONITOR present, user capability `query.evidence.read`, quotas) | route | A 15-day-old query → UNAVAILABLE(RETENTION_EXPIRED) without any customer-account call | 3 |
| WRK-103-S03 | On-demand extraction job in the D-07 worker: assume the account's task role, WIF session, `BRIDGE_FINOPS_WH`, statement timeout 60 s, batch requests within 60 s per account | worker job type | Two requests within 60 s cause one warehouse resume (QUERY_HISTORY evidence) | 5 |
| WRK-103-S04 | Sanitize operator attributes (expressions → literal-free via the SEC-007 sanitizer; drop on failure), cap 1 MB, store the artifact | code | Sentinel literal in a filter expression never appears in the artifact | 3 |
| WRK-103-S05 | Permission failure handling: missing MONITOR → UNAVAILABLE(PERMISSION_MISSING) + Integration Health grant gap | code + UX-103 hook | The fixture warehouse without MONITOR produces the grant-gap entry | 2 |
| WRK-103-S06 | Cost disclosure: estimated credits per request shown before submit; monthly usage in Integration Health | UI + API | Estimate shown; usage recorded | 2 |
| WRK-103-S07 | UI: operator evidence panel on query detail (tree of operators with stats; unavailable states) | component | State matrix passes | 5 |
| WRK-103-S08 | Tests: foreign query id → 404; another account of the same tenant outside scope → 404; the fetch failure does not alter the query cost; quota exceeded → 429 | tests | All pass | 3 |

Task acceptance:
- [ ] Operator evidence is fetched only for authorized queries ≤ 14 days old, with disclosed customer cost and quotas.
- [ ] Artifacts contain no literals and expire in 30 days. A failed fetch never changes cost figures.

### WRK-104 — Retention-tier facts: execution-level (400 d) and query-family × day with mergeable states
Release: R1 · Estimate: 22–30 h · Risk: M · Decisions: D-05, D-11 · Closes: G-WRK-08, G-API-04 (data side)
Dependency changes: new; depends on `WRK-001`, `DBT-004` (incremental/revision model), `ING-001` (retention config). Dependents: WRK-002…WRK-005, UX-005, API-101.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| WRK-104-S01 | Write the retention contract (§3) and plan-configurable hot days | doc + config | Reviewed with ING/OPS | 1 |
| WRK-104-S02 | Build `fct_query_family_daily(tenant, account, warehouse, workload_key, query_parameterized_hash, hash_version, day, query_count, failed_count, compute_cost, elapsed_tdigest, execution_tdigest, users_hll, queued_ms_sum, bytes_scanned_sum)` with APPROX_PERCENTILE_ACCUMULATE/HLL_ACCUMULATE | dbt model | Fixture states combine to the same estimate as a direct APPROX_PERCENTILE over all rows | 4 |
| WRK-104-S03 | Build execution-level facts retention (dbt invocations/model executions, PBI activities, task graph runs, DT refreshes) with 400-day retention | dbt models (shared with WRK-002/003/004) | Execution facts survive the query purge | 3 |
| WRK-104-S04 | Null-hash handling (queries without a parameterized hash) → `__NO_HASH__` bucket per workload/day | SQL | No query compute is lost from the family totals | 1 |
| WRK-104-S05 | Purge job for query-level rows older than hot_days (insert-only revisions per D-05: drop partitions, not row deletes) with a tier marker in the publication manifest | ORC asset + SQL | After purge, family totals still equal the pre-purge query totals for the same days | 4 |
| WRK-104-S06 | Measure the t-digest error on the fixture and a 1M-row synthetic set (p50/p95/p99) and record it for the UI label | evidence | Error recorded (target relative error < 2 % at p95; measured, not assumed) | 3 |
| WRK-104-S07 | Serving views for both tiers with registry `exactness` bindings (API-001) | views + YAML | API picks AGGREGATE for ranges beyond hot days | 2 |
| WRK-104-S08 | Tests: conservation across the purge; distinct users across 365 days via HLL; tenant isolation on states | tests | All pass | 3 |

Task acceptance:
- [ ] Query-level purge never changes family or execution-level totals.
- [ ] Percentiles and distinct counts over long ranges come from mergeable states, labelled approximate, with a measured error.

### WRK-105 — Native Applications and custom applications
Release: R2 · Estimate: 22–32 h · Risk: M · Decisions: D-16, D-20 · Closes: G-WRK-14
Dependency changes: new (split from WRK-004); depends on `WRK-001`, `FIN-019`, `FIN-020`, `UX-002`, `API-104`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| WRK-105-S01 | Verify live what consumer-side QUERY_HISTORY shows for Native App execution and which session/user signals identify custom apps (USER_TYPE availability) | evidence doc | Each signal VERIFIED/ABSENT | 3 |
| WRK-105-S02 | Custom-app identity rules (tenant-declared predicates on tag keys, service users, client application) through the D-16 engine; evidence DECLARED/OBSERVED | rules + SQL | A customer rule classifies the fixture app; an undeclared app stays UNKNOWN | 4 |
| WRK-105-S03 | Native App view: app fees (FIN-020) and SPCS pool usage by APPLICATION_ID shown as distinct components; execution cost only if S01 verified | SQL + page | Fees and usage never summed into one unlabeled number | 5 |
| WRK-105-S04 | Custom apps page with verification status and rule provenance | page | State matrix passes | 5 |
| WRK-105-S05 | Tests + a11y | tests | All pass | 4 |

Task acceptance:
- [ ] Application identity is DECLARED or OBSERVED with provenance, never guessed from names.
- [ ] Provider fees and execution usage stay distinct.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| WRK-101 (new) | R1 | 22 | 30 |
| WRK-001 | R1 | 34 | 48 |
| WRK-002 | R1 | 40 | 56 |
| WRK-004 | R1 | 40 | 56 |
| WRK-005 | R1 | 26 | 36 |
| WRK-102 (new) | R1 | 14 | 20 |
| WRK-104 (new) | R1 | 22 | 30 |
| WRK-003 | R1* (D-20) / else R2 | 24 | 34 |
| WRK-103 (new) | R2 | 24 | 34 |
| WRK-105 (new) | R2 | 22 | 32 |
| **Total R1** (excluding R1* WRK-003) | | **198** | **276** |
| **Total R2** (WRK-103 + WRK-105; + WRK-003 if not R1*) | | **46** | **66** |

The original plan was 5 tasks × 2–6 h = 10–30 h.

## 7. Owner questions (only those not already covered by D-01…D-25)

- **Q-WRK-1** Will the first customer accept adding `invocation_id` to their dbt `query-comment` (a one-line project change)? Without it, dbt run counts are approximate only.
- **Q-WRK-2** Power BI: is the first customer's traffic from the Power BI Service with the Snowflake connector implementation 1.0, and do they need Power BI in R1 (WRK-003 R1*)?
- **Q-WRK-3** Is a 90-day query-level drilldown commercially acceptable if execution-level (dbt/PBI/tasks) history is kept 400 days? This extends D-11's owner check.
- **Q-WRK-4** May Bridge run on-demand operator-stats queries on the customer's `BRIDGE_FINOPS_WH` (customer credits) in R2, and at what default monthly cap?
- **Q-WRK-5** Should customer-declared application rules (custom apps, environments from `target_name`) be editable by tenant admins in R1, or seeded by Bridge support during onboarding?

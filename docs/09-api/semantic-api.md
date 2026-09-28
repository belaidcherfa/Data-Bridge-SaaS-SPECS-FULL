# Semantic metric registry and analytical API

Canonical domain contract. Owner: Backend engineer. Implementation state: NOT_STARTED.


## One semantic contract

`packages/semantic_metrics` defines versioned metric IDs, source relation/grain, expression reference, additive behavior, numerator/denominator, supported dimensions/filters, unit, currency policy, required sources, maturity, privacy and allowed scope dimensions. dbt owns expression implementations; API compiles allowlisted query plans and React displays returned values. Neither computes a competing financial formula.

| Metric | Definition / important constraint |
|---|---|
| spend | Sum selected `fct_charge.cost_effective` by currency and publication; CHARGE only. (amended 2026-09-28, G-API-02) Supported dimensions are bucket-grain only (organization, account, scope_kind, service category/type, rating/billing type, currency, is_adjustment, time grain, data_status); a request grouping by a resource dimension is served by `attributed_cost` and says so in `meta.metric_substitution` |
| attributed_cost | (added 2026-09-28, G-API-02) Money of `bridge_charge_attribution` rows via `serving_attribution_daily`, **including one explicit residual row per parent charge** (`__UNATTRIBUTED__`), so the sum by warehouse, database, user, role, workload, dbt model, query family or compute pool equals `spend` of the same buckets; dimensions without an attribution path (for example compute cost by object) return 422 `DIMENSION_INCOMPATIBLE` with supported alternatives |
| allocated_spend | (added 2026-09-28, G-GOV-04) Allocated money for one required `book_id` from the allocation facts; the only money metric for team/group scopes and group-restricted profiles |
| billed_credits | Adjusted billed credit quantities for credit-rated services; non-credit rows excluded with unit coverage |
| warehouse_compute_cost | Warehouse component from authoritative charges or explicit estimate basis |
| query_compute_cost | Query-attributed compute × approved rate; component scope, coverage and price basis visible |
| idle_credits / idle_cost | Valid classic WMH decomposition; unknown when required attribution is null |
| storage_bytes | Latest or time-weighted snapshot as requested, never sum daily gauges as current storage |
| attribution_coverage | Assigned absolute eligible charge amount / total absolute eligible charge amount; zero denominator null. (amended 2026-09-28, G-SEC-13) Returns null with `DENOMINATOR_OUTSIDE_SCOPE` when the caller's profile cannot read the denominator or lacks unallocated visibility |
| budget_variance | Actual net cost − budget; percentage divides by nonzero budget |
| forecast_variance | Forecast total − budget; percent divides by nonzero budget; distinct from actual budget variance |
| forecast_total | Actual-to-date + modeled remaining spend; method/interval/coverage explicit |
| potential_savings | Deduplicated mutually compatible opportunities, with range and confidence |
| realized_savings | Validated normalized savings for non-overlapping action scopes and measurement windows |
| query_elapsed_p95 | Percentile over individual eligible query elapsed times; not average of daily percentiles. (amended 2026-09-28, G-API-04, D-11) Exact within the query-level retention (`hot_days`, 365 days by default); beyond it the aggregate tier merges stored t-digest states (`APPROX_PERCENTILE_ACCUMULATE`/`COMBINE`, and HLL states for distinct counts) from `fct_query_family_daily`, and the response states `meta.retention_tier` and `meta.exactness` ("≈ approximate") |
| query_failure_rate | Failed queries / eligible completed queries under versioned status taxonomy |

A dimension can be unsupported for a metric because attribution is absent; return a validation error or explicit unattributed bucket, never invent a relationship. Maintain compatible metric versions for saved views/reports; deprecations have migration instructions.

## Request and response

```json
{
  "period": {"start": "2026-09-01T00:00:00Z", "end": "2026-10-01T00:00:00Z"},
  "grain": "day",
  "metrics": ["spend"],
  "dimensions": ["account", "service"],
  "filters": [{"dimension": "account", "operator": "in", "values": ["internal-uuid"]}],
  "currency": "USD",
  "limit": 100
}
```

`POST /v1/analytics/query` is the canonical structured endpoint; `GET /v1/cost` is a documented convenience over the same planner. Tenant is derived from authenticated active membership, not accepted as an authorization claim in JSON. (amended 2026-09-28, G-API-13) The active tenant is a **per-request selector** — header `X-Bridge-Tenant: <tenant_uuid>`, mirrored by the route prefix `/t/{tenant_slug}/…` — authorized on every request against durable membership; the session stores no active tenant, every response echoes `meta.tenant_id`, and clients drop responses for another tenant. The selector grants nothing: it chooses among the subject's memberships. Machine clients are bound to one tenant (mismatch → 403). (amended 2026-09-28, G-API-14) `currency` is a filter, never a conversion: a multi-currency scope without `currency` forces currency into the dimensions and returns no single money total; comparisons (`compare.mode`) run at the same publication and return `comparison_status`; `maturity` filters report what they exclude. All literals are bound; identifiers come from a registry. Reject SQL/expression input. Initial synchronous limits: 365-day range, 4 dimensions, 500 returned rows, 15-second query deadline and bounded concurrency; high-cardinality/deep requests route to jobs based on estimated scan/group cardinality. Financial aggregations remain exact.

Responses contain data, next_cursor and meta: tenant scope summary, publication_id, metric_version, source_as_of, materialized_at, data_status, reconciliation_status, coverage, missing_sources, price_basis, currency, warnings and request_id. (amended 2026-09-28) Meta also carries `tenant_id`, the pinned publication sequence (`pub_seq`, [ADR-014](../architecture/adr/ADR-014-analytical-revisions.md)), `metric_substitution`, `retention_tier`, `exactness` and server-computed totals, `__OTHER__` rows and `delta`/`delta_pct` so clients never compute money. Decimal money is a JSON string matching the FIN-106 grammar (plain decimal, up to 12 fraction digits, never "-0"); unavailable is null plus reason. Empty authorized results are 200 with empty rows and confirmed coverage, not 404. Partial business data is 200 with metadata, not HTTP range status 206. ETag binds publication/query/scope; (amended 2026-09-28, G-API-07) it is a weak ETag computed before execution from publication, registry version, request hash, profile hash, currency, privacy mode and schema version, checked after authorization, and analytical responses send `Cache-Control: no-store`.

Cursor binds query hash, stable sort tuple, tenant/profile/permission_epoch, publication and expiry with server signature. (amended 2026-09-28, G-API-07, C-07) Cursors are **sealed (encrypted) tokens** — `bt1.<kid>.<…>`, AES-256-GCM with AAD `purpose|tenant_id|subject_id`, key ring rotated every 30 days, TTL 1 h (`cursor_ttl_seconds`) — because a signed-only cursor leaks sort-key values into access logs; the plaintext binds subject, membership epoch and profile hash, publication, request hash, metric versions, sort and position. Validation: tampered/foreign/unknown key → 400 `CURSOR_INVALID` (identical body); expired → 410 `CURSOR_EXPIRED`; epoch or profile changed → 409 `SCOPE_CHANGED`; request changed → 400 `CURSOR_MISMATCH`; publication purged → 410 `PUBLICATION_RETIRED`. Cursors create no publication pins; they rely on the garbage-collection grace window. Sort includes stable ID tie-breaker. Dataset version stays pinned across pages; an expired/retired snapshot returns explicit restart-required, never silently changes the result set.

## Query broker and async jobs

The API authorizes current user scope, chooses the corresponding constrained Snowflake principal and reads only serving views. (amended 2026-09-28, D-22, D-02, G-API-05) The query broker is a **separate internal service** with its own task role, the only component able to assume tenant serving identities; the API sends it a server-signed, SELECT-only plan over private authenticated transport (SigV4 through VPC Lattice preferred, TO VERIFY LIVE). The broker maps the request to (tenant WIF user, profile role), keys pools by `(env, tenant user, profile role)` — never by epoch — asserts user, role and empty secondary roles after connecting, re-checks authorization every 10 s for running statements and cancels them on revocation, and has INTERACTIVE (15 s timeout) and JOB (up to 1,800 s) classes. Recheck authorization before response delivery. Use bounded per-principal pools; do not switch identities in a generic global pool. Set statement timeout and safe QUERY_TAG; cancel on timeout/client cancellation where supported. Redis uses the CTL scoped key contract.

Heavy work: POST `/v1/analysis-jobs` returns 202 with job ID/status URL. PostgreSQL stores definition/status/owner/scope/version/progress, Snowflake stores results. (amended 2026-09-28, D-33, G-API-12) A long-lived **analysis-worker** service claims jobs from PostgreSQL with fenced leases and submits them to the broker's JOB class, writing results server-side (`INSERT … SELECT` into job-result tables); there is no Dagster run per interactive job, which PRD §140's "Python worker" allows. Exports and report snapshots use the same worker model. Allocation simulations are transforms, so they run as Dagster dbt jobs while an API job record provides status and cancellation. Long-lived jobs create explicit publication pins (ORC-105). Default 2 active heavy jobs per tenant, 1 per user; queue admission is plan-aware. Jobs pin data/config and reauthorize on reads. Retry-After controls polling; cancellation is cooperative and fenced. No million-row JSON in PostgreSQL or Redis.

## Explainability and exports

`GET /v1/explain/{reference}` resolves metric/charge/allocation/rate/rule/source lineage at the pinned version. Show formula reference, exact operands, scope, source state and evidence IDs. (amended 2026-09-28, X-33, G-API-08, C-27) Explain is a lazy, paginated, permission-trimmed tree evaluated at the pinned publication; leaves summarize batch/file sets through the batch-manifest endpoint `GET /v1/data-health/batches/{batch_id}` (ING-012) instead of materializing per-number lineage; a group-restricted reader stops at "allocated by method M under policy vN" with only its own operands. Raw file identifiers/checksums are safe metadata; direct S3 RAW access requires separate explicit privilege and privacy checks. Ordinary users do not get arbitrary storage URLs.

CSV/PDF/PNG export uses the same semantic query and report service; async result count/size bounds and formula-injection protection apply. (amended 2026-09-28, U-10, C-12) API-102 owns the shared CSV writer and export job kinds; every artifact download (exports, reports, statements, evidence bundles, uploaded billing references) goes through the single authorizing download broker of SEC-006, which redirects to a presigned URL valid 30 s. Public API credentials (API-006) are R2. Service-to-service customer API clients use Cognito-supported machine identity mapped to explicit tenant scopes and revocable credentials; no browser token masquerades as long-lived API key. Version/rate-limit and audit all public endpoints.


## Implementation sequence

(amended 2026-09-28) The dependency and gate columns below are the original index. Execution follows the revised graph ([revised-task-graph.json](../22-implementation-readiness/revised-task-graph.json), [revised critical path](../22-implementation-readiness/REVISED_CRITICAL_PATH.md)) and phases P0–P6 of the [release plan](../22-implementation-readiness/RELEASE_PLAN.md); new tasks, revised steps, dependencies and task acceptance are in [backlog/API.md](../22-implementation-readiness/backlog/API.md).

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [API-001](../tasks/API/API-001.md) | Implement metric and dimension registry with compatibility rules | FIN-009, DBT-006 | M5 |
| [API-002](../tasks/API/API-002.md) | Build safe analytical planner and Snowflake query broker | API-001, SEC-005, CTL-006 | M5 |
| [API-003](../tasks/API/API-003.md) | Implement response metadata, stable pagination and cache | API-002 | M5 |
| [API-004](../tasks/API/API-004.md) | Build asynchronous analysis jobs and cancellation | API-003, CTL-004, ORC-006 | M5 |
| [API-005](../tasks/API/API-005.md) | Implement Explain This Number lineage endpoint | API-003, FIN-010 | M5 |
| [API-006](../tasks/API/API-006.md) | Add public API credentials, quotas and contract release tests | API-004, API-005, SEC-008 | M5 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

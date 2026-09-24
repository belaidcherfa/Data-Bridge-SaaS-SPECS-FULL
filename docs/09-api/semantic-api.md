# Semantic metric registry and analytical API

Canonical domain contract. Owner: Backend engineer. Implementation state: NOT_STARTED.


## One semantic contract

`packages/semantic_metrics` defines versioned metric IDs, source relation/grain, expression reference, additive behavior, numerator/denominator, supported dimensions/filters, unit, currency policy, required sources, maturity, privacy and allowed scope dimensions. dbt owns expression implementations; API compiles allowlisted query plans and React displays returned values. Neither computes a competing financial formula.

| Metric | Definition / important constraint |
|---|---|
| spend | Sum selected `fct_charge.cost_effective` by currency and publication; CHARGE only |
| billed_credits | Adjusted billed credit quantities for credit-rated services; non-credit rows excluded with unit coverage |
| warehouse_compute_cost | Warehouse component from authoritative charges or explicit estimate basis |
| query_compute_cost | Query-attributed compute × approved rate; component scope, coverage and price basis visible |
| idle_credits / idle_cost | Valid classic WMH decomposition; unknown when required attribution is null |
| storage_bytes | Latest or time-weighted snapshot as requested, never sum daily gauges as current storage |
| attribution_coverage | Assigned absolute eligible charge amount / total absolute eligible charge amount; zero denominator null |
| budget_variance | Actual net cost − budget; percentage divides by nonzero budget |
| forecast_total | Actual-to-date + modeled remaining spend; method/interval/coverage explicit |
| potential_savings | Deduplicated mutually compatible opportunities, with range and confidence |
| realized_savings | Validated normalized savings for non-overlapping action scopes and measurement windows |
| query_elapsed_p95 | Percentile over individual eligible query elapsed times; not average of daily percentiles |
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

`POST /v1/analytics/query` is the canonical structured endpoint; `GET /v1/cost` is a documented convenience over the same planner. Tenant is derived from authenticated active membership, not accepted as an authorization claim in JSON. All literals are bound; identifiers come from a registry. Reject SQL/expression input. Initial synchronous limits: 365-day range, 4 dimensions, 500 returned rows, 15-second query deadline and bounded concurrency; high-cardinality/deep requests route to jobs based on estimated scan/group cardinality. Financial aggregations remain exact.

Responses contain data, next_cursor and meta: tenant scope summary, publication_id, metric_version, source_as_of, materialized_at, data_status, reconciliation_status, coverage, missing_sources, price_basis, currency, warnings and request_id. Decimal money is a JSON string; unavailable is null plus reason. Empty authorized results are 200 with empty rows and confirmed coverage, not 404. Partial business data is 200 with metadata, not HTTP range status 206. ETag binds publication/query/scope.

Cursor binds query hash, stable sort tuple, tenant/profile/permission_epoch, publication and expiry with server signature. Sort includes stable ID tie-breaker. Dataset version stays pinned across pages; an expired/retired snapshot returns explicit restart-required, never silently changes the result set.

## Query broker and async jobs

The API authorizes current user scope, chooses the corresponding constrained Snowflake principal and reads only serving views. Recheck authorization before response delivery. Use bounded per-principal pools; do not switch identities in a generic global pool. Set statement timeout and safe QUERY_TAG; cancel on timeout/client cancellation where supported. Redis uses the CTL scoped key contract.

Heavy work: POST `/v1/analysis-jobs` returns 202 with job ID/status URL. PostgreSQL stores definition/status/owner/scope/version/progress, Snowflake stores results; an outbox schedules Dagster. Default 2 active heavy jobs per tenant, 1 per user; queue admission is plan-aware. Jobs pin data/config and reauthorize on reads. Retry-After controls polling; cancellation is cooperative and fenced. No million-row JSON in PostgreSQL or Redis.

## Explainability and exports

`GET /v1/explain/{reference}` resolves metric/charge/allocation/rate/rule/source lineage at the pinned version. Show formula reference, exact operands, scope, source state and evidence IDs. Raw file identifiers/checksums are safe metadata; direct S3 RAW access requires separate explicit privilege and privacy checks. Ordinary users do not get arbitrary storage URLs.

CSV/PDF/PNG export uses the same semantic query and report service; async result count/size bounds and formula-injection protection apply. Service-to-service customer API clients use Cognito-supported machine identity mapped to explicit tenant scopes and revocable credentials; no browser token masquerades as long-lived API key. Version/rate-limit and audit all public endpoints.


## Implementation sequence

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

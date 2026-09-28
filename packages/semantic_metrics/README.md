---
contract: semantic-metrics-registry-guide
version: 1
status: DRAFT
owner_task: API-001
decisions: [D-05, D-10, D-11, D-12, D-17, D-18, D-20]
last_changed: 2026-09-28
canonical: docs/09-api/semantic-api.md
---

# Semantic metric registry (v1)

The registry is the **only** source of analytical identifiers. The API compiles a validated request into the typed
QueryPlan IR (`schema/query_plan.schema.json`); the query broker generates SQL from the IR alone. dbt owns the
expression implementations behind the serving relations; neither the API nor React computes a competing financial
formula (semantic-api.md, PRD §69).

## Layout

| Path | Content | Schema |
|---|---|---|
| `metrics/<category>/<id>.yaml` | One file per metric (51 in v1) | `schema/metric.schema.json` |
| `dimensions/<id>.yaml` | One file per dimension (52 in v1) | `schema/dimension.schema.json` |
| `relations/<id>.yaml` | Serving relations the registry may read (20) — the physical secure views must expose exactly these columns | `schema/relation.schema.json` |
| `join_paths/<id>.yaml` | The only joins the compiler may emit | `schema/join_path.schema.json` |
| `records/<id>.yaml` | Record datasets for `POST /v1/analytics/records` (10) | `schema/record_dataset.schema.json` |
| `taxonomies/query_status_v1.yaml` | Query status classes used by query populations | — |
| `screen_key_map.yaml` | All 176 design KPI keys → registry metric or named API | — |
| `fixtures/golden_oracles_v1.yaml` | Compiler-level golden oracles (API-001-S13) | — |
| `schema/query_plan.schema.json` | QueryPlan IR (API-002) | — |

A build step (API-001-S11) compiles these files into `data/contracts/metrics.json`; `registry_version` =
`sha256:` of that artifact and is echoed in every response `meta.registry_version`, in cursors and in publication
manifests (API-101-S09).

## Aggregation rules (fixed in code, never per metric)

| measure.type | Output-grain rule | Top-N "Other" | Beyond `hot_days` |
|---|---|---|---|
| SUM | `SUM(column)` over the population at the output grain | Σ members | same (FULL-tier relations) or `aggregate_binding` column sum |
| RATIO | `SUM(numerator) / NULLIF(SUM(denominator), 0)` at the output grain; operands cast to NUMBER(38,18) and the division is the last step (CONVENTIONS §5). Never summed or averaged | numerator and denominator re-aggregated over the Other members | `aggregate_binding` numerator/denominator sums |
| PERCENTILE | `PERCENTILE_CONT(p) WITHIN GROUP (ORDER BY column)` over individual rows | recomputed over Other members' rows | `APPROX_PERCENTILE_ESTIMATE(APPROX_PERCENTILE_COMBINE(state), p)` — `meta.exactness=APPROX_TDIGEST` |
| COUNT_DISTINCT | `COUNT(DISTINCT column)` | recomputed | `HLL_ESTIMATE(HLL_COMBINE(state))` — `APPROX_HLL` |
| COUNT | `COUNT(*)` over the population | Σ members | aggregate column sum |
| GAUGE / LATEST / TWA | LATEST: value on the last observed time bucket of each group; TWA: `Σ(value × observation_seconds) / Σ observation_seconds`; summed across non-time dimensions | Σ members at the same instant | — |
| DERIVED | Arithmetic over other metric values at the same grain and publication (`SUBTRACT`, `DIVIDE` → null `ZERO_DENOMINATOR` on 0, `DIVIDE_SCALED`) | recomputed from the operands of Other | follows operands |

The registry lint rejects `RATIO | PERCENTILE | COUNT_DISTINCT | DERIVED` with `additivity.across_dimensions ≠ NONE`
(schema `allOf`). Every ratio declares `denominator_scope`: when the caller's profile cannot read the denominator
(SEC Appendix A.4), the value is `null` + `DENOMINATOR_OUTSIDE_SCOPE` and the denominator is not executed.

## Compatibility engine (API-001-S08)

For a request `(metric, dimensions, filters)` the engine answers, per metric:

1. **COMPATIBLE** — every dimension is in `dimensions` (or is a time grain) and has a binding on the metric's relation.
2. **SUBSTITUTED** — the metric declares `substitution` and a requested dimension is in `when_dimensions_any_of`:
   the plan serves `use` (always `attributed_cost@1` in v1), carries the requested metric's population predicates whose
   columns exist in the served relation (e.g. `service_family = WAREHOUSE_COMPUTE`), and returns
   `meta.metric_substitution = {requested, served, unattributed_row_key: "__UNATTRIBUTED__"}`. The UI shows
   `analytics.substitution.attributed_cost.banner` (UX-004-S06).
3. **INCOMPATIBLE** — `422 QUERY_DIMENSION_INCOMPATIBLE` with `errors[].field = dimensions[i]`, the reason from
   `incompatible_dimensions` (or `NOT_AT_GRAIN`) and `supported_alternatives` (the compatible dimensions of the metric).
   Examples: `query_compute_cost × database` (NO_ATTRIBUTION_PATH, alternatives warehouse, workload);
   `storage_bytes × user`; `spend × group` (use `allocated_spend`).
4. **Tier** — when `period.start < now − hot_days` the metric's `aggregate_binding` is used; a dimension in
   `aggregate_binding.unsupported_dimensions` makes the request INCOMPATIBLE with reason `RETENTION_TIER`.
5. **Currency** — a money metric (or a ratio of money) over an authorized scope holding several currencies without a
   `currency` filter gets `currency` forced into the output dimensions (`plan.dimensions[].forced_by = CURRENCY_RULE`);
   a scalar tile request that cannot take a dimension gets `422 QUERY_CURRENCY_MIXED`.
6. **Parameters** — `params` marked `required` must be supplied (`book_id`, `budget_id`, `tag_key`); metrics additive
   `within_param` refuse two parameter values in one request (`422 QUERY_NON_ADDITIVE_BOOKS`).
7. **Required filter or dimension** — execution metrics require `execution_kind` as an EQ filter or a dimension so a
   parent and its children are never counted together.

## Versioning (G-API-15)

- A change to population, formula (measure), unit or null policy is a **semantic change** → `version + 1` in a new file
  revision; label/description keys are not. CI job `registry-diff` fails a semantic change without a bump (API-001-S10).
- A superseded version stays `DEPRECATED` and is served for ≥ 6 months (`deprecation.sunset`), with
  `meta.warnings[METRIC_DEPRECATED]{replaced_by, sunset}`. After sunset the API answers
  `410 QUERY_METRIC_VERSION_RETIRED` with `{replaced_by, migration}`.
- Saved views/reports auto-migrate only for `migration: EQUIVALENT | PARAM_MAP`; `MANUAL` marks them `needs_review` and
  keeps serving the old version until sunset. `migrate_saved_query(query, registry)` is one pure function shared by
  CTL-007, RPT-001, GOV-003 and `POST /v1/analytics/requests/migrate`.

## Authoring checklist (reviewers: FIN + UX owners)

1. The label names the population ("P95 execution time" → `query_execution_p95`, never a generic "P95").
2. `population` predicates reference relation columns only; money metrics carry `unit.currency_policy = SINGLE_CURRENCY_REQUIRED`.
3. Null policy chosen explicitly: `ZERO` only when zero is confirmed on a fully covered population.
4. Ratios: `denominator_scope` and `zero_denominator`; restricted-profile behaviour tested (SEC A.4).
5. `required_sources` and `capability_flags` list every source/capability whose absence must yield a reasoned null.
6. `exactness` per tier; percentiles/distinct counts that cross `hot_days` have an `aggregate_binding` with a state column.
7. Add the design keys served in `screen_keys` and regenerate `screen_key_map.yaml`.
8. Add or extend a golden oracle in `fixtures/golden_oracles_v1.yaml` with the arithmetic in a comment.

## Name aliases in older documents

| Name in older text | Registry id | Source of the rename |
|---|---|---|
| `allocated_cost` (API.md §3.1) | `allocated_spend` | semantic-api.md (G-GOV-04), ALC-102-S01 |
| `unallocated_cost` (API.md §3.1) | `unallocated_spend` | ALC-102-S02 |
| `idle_cost / idle_credits` | `idle_cost`, `idle_credits` | split into two metrics |
| `budget_variance (+ _pct)`, `forecast_variance (+ _pct)` | `…_variance`, `…_variance_pct` | split into two metrics |
| `bytes_scanned / bytes_spilled_remote`, `files_loaded / bytes_loaded` | four metrics | split |
| — | `ai_attributed_cost` | added as the money operand of `ai_cost_per_million_tokens` |

## Catalog (generated)

| Metric | v | Category | Relation | Measure | Additivity | Exactness HOT / AGG | Release |
|---|---|---|---|---|---|---|---|
| [`ai_attributed_cost`](#ai_attributed_cost) | 1 | AI_SPCS | v_attribution_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`ai_cost_per_million_tokens`](#ai_cost_per_million_tokens) | 1 | AI_SPCS | — | DERIVED | NONE/NONE | EXACT / EXACT | R1 |
| [`ai_request_count`](#ai_request_count) | 1 | AI_SPCS | v_attribution_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`ai_tokens`](#ai_tokens) | 1 | AI_SPCS | v_attribution_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`allocated_spend`](#allocated_spend) | 1 | ALLOCATION | v_allocation_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`allocation_coverage`](#allocation_coverage) | 1 | ALLOCATION | v_allocation_coverage_daily | RATIO | NONE/NONE | EXACT / EXACT | R1 |
| [`allocation_share`](#allocation_share) | 1 | ALLOCATION | v_allocation_daily | RATIO | NONE/NONE | EXACT / EXACT | R1 |
| [`attributed_cost`](#attributed_cost) | 1 | FINANCE | v_attribution_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`attribution_coverage`](#attribution_coverage) | 1 | FINANCE | v_attribution_daily | RATIO | NONE/NONE | EXACT / EXACT | R1 |
| [`billed_credits`](#billed_credits) | 1 | FINANCE | v_charge_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`budget_actual_to_date`](#budget_actual_to_date) | 1 | GOVERNANCE | v_budget_daily | SUM | LISTED/SUM | EXACT / EXACT | R1 |
| [`budget_amount`](#budget_amount) | 1 | GOVERNANCE | v_budget_daily | SUM | LISTED/SUM | EXACT / EXACT | R1 |
| [`budget_remaining`](#budget_remaining) | 1 | GOVERNANCE | — | DERIVED | NONE/NONE | EXACT / EXACT | R1 |
| [`budget_variance`](#budget_variance) | 1 | GOVERNANCE | — | DERIVED | NONE/NONE | EXACT / EXACT | R1 |
| [`budget_variance_pct`](#budget_variance_pct) | 1 | GOVERNANCE | — | DERIVED | NONE/NONE | EXACT / EXACT | R1 |
| [`bytes_loaded`](#bytes_loaded) | 1 | PERFORMANCE | v_attribution_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`bytes_scanned`](#bytes_scanned) | 1 | PERFORMANCE | v_query_exec | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`bytes_spilled_remote`](#bytes_spilled_remote) | 1 | PERFORMANCE | v_query_exec | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`dynamic_table_lag_p95`](#dynamic_table_lag_p95) | 1 | WORKLOAD | v_workload_exec | PERCENTILE | NONE/NONE | EXACT / EXACT | R1 |
| [`execution_count`](#execution_count) | 1 | WORKLOAD | v_workload_exec | COUNT_DISTINCT | NONE/NONE | EXACT / EXACT | R1 |
| [`execution_duration_p95`](#execution_duration_p95) | 1 | WORKLOAD | v_workload_exec | PERCENTILE | NONE/NONE | EXACT / EXACT | R1 |
| [`execution_failure_rate`](#execution_failure_rate) | 1 | WORKLOAD | v_workload_exec | RATIO | NONE/NONE | EXACT / EXACT | R1 |
| [`execution_time_sum`](#execution_time_sum) | 1 | WORKLOAD | v_workload_exec | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`execution_wall_time_sum`](#execution_wall_time_sum) | 1 | WORKLOAD | v_workload_exec | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`failed_execution_count`](#failed_execution_count) | 1 | WORKLOAD | v_workload_exec | COUNT_DISTINCT | NONE/NONE | EXACT / EXACT | R1 |
| [`failed_query_count`](#failed_query_count) | 1 | PERFORMANCE | v_query_exec | COUNT | ALL/SUM | EXACT / EXACT | R1 |
| [`files_loaded`](#files_loaded) | 1 | PERFORMANCE | v_attribution_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`forecast_total`](#forecast_total) | 1 | GOVERNANCE | v_forecast | LATEST | NONE/NONE | EXACT / EXACT | R1 |
| [`forecast_variance`](#forecast_variance) | 1 | GOVERNANCE | — | DERIVED | NONE/NONE | EXACT / EXACT | R1 |
| [`forecast_variance_pct`](#forecast_variance_pct) | 1 | GOVERNANCE | — | DERIVED | NONE/NONE | EXACT / EXACT | R1 |
| [`idle_cost`](#idle_cost) | 1 | FINANCE | v_attribution_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`idle_credits`](#idle_credits) | 1 | FINANCE | v_attribution_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`potential_savings`](#potential_savings) | 1 | OPTIMIZATION | v_insight_summary | SUM | ALL/NONE | EXACT / EXACT | R1 |
| [`query_compute_cost`](#query_compute_cost) | 1 | FINANCE | v_attribution_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`query_count`](#query_count) | 1 | PERFORMANCE | v_query_exec | COUNT | ALL/SUM | EXACT / EXACT | R1 |
| [`query_elapsed_p95`](#query_elapsed_p95) | 1 | PERFORMANCE | v_query_exec | PERCENTILE | NONE/NONE | EXACT / APPROX_TDIGEST | R1 |
| [`query_execution_p95`](#query_execution_p95) | 1 | PERFORMANCE | v_query_exec | PERCENTILE | NONE/NONE | EXACT / APPROX_TDIGEST | R1 |
| [`query_failure_rate`](#query_failure_rate) | 1 | PERFORMANCE | v_query_exec | RATIO | NONE/NONE | EXACT / EXACT | R1 |
| [`query_queued_time_sum`](#query_queued_time_sum) | 1 | PERFORMANCE | v_query_exec | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`realized_savings`](#realized_savings) | 1 | OPTIMIZATION | v_insight_summary | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`run_rate_daily`](#run_rate_daily) | 1 | GOVERNANCE | v_budget_daily | RATIO | NONE/NONE | EXACT / EXACT | R1 |
| [`spcs_node_hours`](#spcs_node_hours) | 1 | AI_SPCS | v_attribution_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`spend`](#spend) | 1 | FINANCE | v_charge_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`storage_bytes`](#storage_bytes) | 1 | STORAGE | v_storage_daily | GAUGE | ALL/LATEST | EXACT / EXACT | R1 |
| [`tag_coverage`](#tag_coverage) | 1 | ALLOCATION | v_attribution_daily | RATIO | NONE/NONE | EXACT / EXACT | R1 |
| [`unallocated_spend`](#unallocated_spend) | 1 | ALLOCATION | v_allocation_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`unattributed_cost`](#unattributed_cost) | 1 | FINANCE | v_attribution_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`warehouse_compute_cost`](#warehouse_compute_cost) | 1 | FINANCE | v_charge_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`warehouse_credits`](#warehouse_credits) | 1 | FINANCE | v_attribution_daily | SUM | ALL/SUM | EXACT / EXACT | R1 |
| [`warehouse_utilization`](#warehouse_utilization) | 1 | PERFORMANCE | — | NONE | NONE/NONE | EXACT / EXACT | R1 (UNSUPPORTED) |
| [`workload_classification_coverage`](#workload_classification_coverage) | 1 | WORKLOAD | v_attribution_daily | RATIO | NONE/NONE | EXACT / EXACT | R1 |

### Metric formulas

#### ai_attributed_cost

- Relation: `v_attribution_daily`; measure `SUM` of `amount`; population: service_family EQ AI_SERVICES.
- AI_SERVICES money attributed to family/model/function incl. the residual row; operand of ai_cost_per_million_tokens. Warehouse credits of the calling query stay WAREHOUSE_COMPUTE.

#### ai_cost_per_million_tokens

- Relation: `None`; measure `DERIVED`; population: —.
- Derived: DIVIDE_SCALED(ai_attributed_cost, ai_tokens) × 1000000.
- cost × 1,000,000 / tokens at the same grain; null when tokens are null or zero.

#### ai_request_count

- Relation: `v_attribution_daily`; measure `SUM` of `ai_requests`; population: service_family EQ AI_SERVICES.

#### ai_tokens

- Relation: `v_attribution_daily`; measure `SUM` of `ai_tokens`; population: service_family EQ AI_SERVICES.
- Native token units by family; families that do not emit tokens (e.g. Cortex Search) return null NOT_SUPPORTED, never 0.

#### allocated_spend

- Relation: `v_allocation_daily`; measure `SUM` of `allocated_amount`; population: —.
- Parameters: `book_id` (required).
- Canonical id allocated_spend (semantic-api.md G-GOV-04, ALC-102-S01); API.md §3.1 calls it allocated_cost — the same metric. Book required; two books in one request → 422 QUERY_NON_ADDITIVE_BOOKS. The only money metric for team/group scopes and group-restricted profiles. Allocation version floats to the latest published allocation unless the request pins publication/allocation_publication_id (ALC-102-S04).

#### allocation_coverage

- Relation: `v_allocation_coverage_daily`; measure `RATIO`; population: —.
- Numerator SUM(covered_abs); denominator SUM(eligible_abs); denominator scope `BOOK_WIDE`.
- Parameters: `book_id` (required).
- Coverage-bucket basis (G-ALC-14): Σ covered_abs / Σ eligible_abs, transfers excluded. F-270 default book (no team rules): (4+5+3)/276 = 12/276 = 0.043478260869… Book-wide profiles only (ALC-102-S03/S05).

#### allocation_share

- Relation: `v_allocation_daily`; measure `RATIO`; population: —.
- Numerator SUM(allocated_amount); denominator SUM(allocated_amount); denominator scope `BOOK_WIDE`.
- Parameters: `book_id` (required).
- Group allocated / book total in the same non-group scope. Group-restricted profiles get null DENOMINATOR_OUTSIDE_SCOPE (canonical semantic-api.md rule; ALC-101-S06's '403' wording is superseded for ratios — hand-off K7). Fixture: Finance 12,000 / 20,000 = 0.6.

#### attributed_cost

- Relation: `v_attribution_daily`; measure `SUM` of `amount`; population: —.
- Σ bridge_charge_attribution amount INCLUDING the explicit residual row per parent charge ('__UNATTRIBUTED__'), so Σ by any resource dimension = spend of the same buckets (270 = Σ warehouses + unattributed). Rows where a dimension does not apply (e.g. database on compute rows) group under a null value with label reason NOT_APPLICABLE; money is never dropped.

#### attribution_coverage

- Relation: `v_attribution_daily`; measure `RATIO`; population: —.
- Numerator SUM_ABS(amount); denominator SUM_ABS(amount); denominator scope `INCLUDE_UNALLOCATED`.
- Σ|amount attributed to a non-residual target| / Σ|all eligible attribution amount| on the absolute basis (ledger.md). Profiles without INCLUDE_UNALLOCATED get null DENOMINATOR_OUTSIDE_SCOPE (SEC A.4 (4)).

#### billed_credits

- Relation: `v_charge_daily`; measure `SUM` of `effective_credits`; population: measure_role EQ CHARGE AND effective_credits IS_NOT_NULL .
- Adjusted billed credit quantities for credit-rated families; rows without credits (storage, transfer, fees) are excluded and counted in meta.coverage.excluded_non_credit_rows. Not money: currency does not apply.

#### budget_actual_to_date

- Relation: `v_budget_daily`; measure `SUM` of `actual_amount`; population: is_complete_day EQ True.
- Parameters: `budget_id` (required).
- The same spend (or allocated_spend for team budgets) as the explorer, over complete UTC days of the budget scope.

#### budget_amount

- Relation: `v_budget_daily`; measure `SUM` of `plan_amount_daily`; population: —.
- Parameters: `budget_id` (required).
- Plan amount prorated by the declared calendar policy over the requested period (GOV-001 formula sheet). One budget per request; budgets are never summed.

#### budget_remaining

- Relation: `None`; measure `DERIVED`; population: —.
- Derived: SUBTRACT(budget_amount, budget_actual_to_date).
- Parameters: `budget_id` (required).
- budget − actual; may be negative. Fixture: 28,000 − 15,000 = 13,000.

#### budget_variance

- Relation: `None`; measure `DERIVED`; population: —.
- Derived: SUBTRACT(budget_actual_to_date, budget_amount).
- Parameters: `budget_id` (required).
- actual − budget (canonical budget_variance).

#### budget_variance_pct

- Relation: `None`; measure `DERIVED`; population: —.
- Derived: DIVIDE(budget_variance, budget_amount).
- Parameters: `budget_id` (required).
- Null ZERO_DENOMINATOR when the budget is 0.

#### bytes_loaded

- Relation: `v_attribution_daily`; measure `SUM` of `bytes_loaded`; population: service_family IN ['SNOWPIPE_FILE'].

#### bytes_scanned

- Relation: `v_query_exec`; measure `SUM` of `bytes_scanned`; population: —.

#### bytes_spilled_remote

- Relation: `v_query_exec`; measure `SUM` of `bytes_spilled_remote`; population: —.
- Capability-gated on the spill columns of the QUERY_HISTORY projection (AUDIT X-32, ING-101).

#### dynamic_table_lag_p95

- Relation: `v_workload_exec`; measure `PERCENTILE` of `lag_ms`; population: execution_kind EQ DT_REFRESH.
- p95 of (refresh end − DATA_TIMESTAMP). Fixture: 4 min against a 5 min target.

#### execution_count

- Relation: `v_workload_exec`; measure `COUNT_DISTINCT` of `execution_id`; population: basis EQ VERIFIED.
- COUNT DISTINCT verified execution ids of one execution_kind (invocation, model execution, activity, graph run, refresh). APPROXIMATE groupings are excluded from run counts (G-WRK-11). Execution-level facts are retained 400 days, so the value is exact over the whole range.

#### execution_duration_p95

- Relation: `v_workload_exec`; measure `PERCENTILE` of `wall_time_ms`; population: basis EQ VERIFIED AND complete EQ True.
- PERCENTILE_CONT over per-execution wall time; never averaged across days or modes.

#### execution_failure_rate

- Relation: `v_workload_exec`; measure `RATIO`; population: —.
- Numerator COUNT_DISTINCT(execution_id); denominator COUNT_DISTINCT(execution_id); denominator scope `SAME_AS_NUMERATOR`.

#### execution_time_sum

- Relation: `v_workload_exec`; measure `SUM` of `exec_sum_ms`; population: basis EQ VERIFIED.
- Σ EXECUTION_TIME of leaf queries (two concurrent 10 s queries → 20 s).

#### execution_wall_time_sum

- Relation: `v_workload_exec`; measure `SUM` of `wall_time_ms`; population: basis EQ VERIFIED AND complete EQ True.
- Σ over complete executions of (max(end) − min(start)); concurrent queries are not summed (two concurrent 10 s queries → 10 s). Additive across executions of one kind only (execution_kind required).

#### failed_execution_count

- Relation: `v_workload_exec`; measure `COUNT_DISTINCT` of `execution_id`; population: basis EQ VERIFIED AND has_failed_leaf EQ True.

#### failed_query_count

- Relation: `v_query_exec`; measure `COUNT`; population: status_class EQ FAILED.

#### files_loaded

- Relation: `v_attribution_daily`; measure `SUM` of `files_loaded`; population: service_family IN ['SNOWPIPE_FILE'].

#### forecast_total

- Relation: `v_forecast`; measure `LATEST` of `forecast_total`; population: —.
- Parameters: `budget_id` (required).
- actual-to-date + modeled remaining for the budget period, latest as_of at the pinned publication; method, interval and history in meta.metric_context. Fixture: 15,000 + 15 × 1,000 = 30,000 (run-rate fallback, no calibrated interval).

#### forecast_variance

- Relation: `None`; measure `DERIVED`; population: —.
- Derived: SUBTRACT(forecast_total, budget_amount).
- Parameters: `budget_id` (required).
- forecast − budget over the full budget period; distinct from budget_variance. Fixture: 30,000 − 28,000 = +2,000.

#### forecast_variance_pct

- Relation: `None`; measure `DERIVED`; population: —.
- Derived: DIVIDE(forecast_variance, budget_amount).
- Parameters: `budget_id` (required).
- Fixture: +2,000 / 28,000 = 0.071428571428… (UI shows +7.14 %).

#### idle_cost

- Relation: `v_attribution_daily`; measure `SUM` of `amount`; population: target_kind EQ WAREHOUSE_IDLE AND attribution_method EQ CLASSIC_IDLE.
- Classic idle = WMH compute − Σ attributed query compute per warehouse-hour. Adaptive warehouses have no idle: a group made only of Adaptive warehouses returns null NOT_SUPPORTED, a mixed scope returns the classic idle with warning ADAPTIVE_EXCLUDED.

#### idle_credits

- Relation: `v_attribution_daily`; measure `SUM` of `credits`; population: target_kind EQ WAREHOUSE_IDLE AND attribution_method EQ CLASSIC_IDLE.

#### potential_savings

- Relation: `v_insight_summary`; measure `SUM` of `potential_point`; population: row_kind EQ OPPORTUNITY AND is_current_snapshot EQ True AND is_dedup_representative EQ True.
- Estimate: deduplicated, mutually compatible opportunities at the current snapshot, with Row.intervals low/high. Never added to realized_savings (the API has no combined metric).

#### query_compute_cost

- Relation: `v_attribution_daily`; measure `SUM` of `amount`; population: target_kind EQ QUERY AND attribution_method IN ['QAH', 'QMH'].
- Query-attributed compute (QAH classic, QMH adaptive, prorated per D-14) × the charge's effective rate. Excludes idle and cloud services; a query missing from QAH lands in unattributed_cost, never free (UX-005-S10).

#### query_count

- Relation: `v_query_exec`; measure `COUNT`; population: status_class IN ['SUCCEEDED', 'FAILED', 'CANCELLED'].
- Terminal queries under status taxonomy v1 (taxonomies/query_status_v1.yaml).

#### query_elapsed_p95

- Relation: `v_query_exec`; measure `PERCENTILE` of `total_elapsed_ms`; population: status_class IN ['SUCCEEDED', 'FAILED'].
- PERCENTILE_CONT(0.95) over individual TOTAL_ELAPSED_TIME values (compile + queue + execution), never an average of daily percentiles. Oracle: {100 × 1 s, 5 × 100 s} → position 0.95 × 104 = 98.8 → 1 s (not 50.5 s). Beyond hot_days: APPROX_PERCENTILE_ESTIMATE(APPROX_PERCENTILE_COMBINE(elapsed_tdigest), 0.95) labelled ≈.

#### query_execution_p95

- Relation: `v_query_exec`; measure `PERCENTILE` of `execution_ms`; population: status_class IN ['SUCCEEDED', 'FAILED'].
- EXECUTION_TIME only (label 'P95 execution time'); distinct from query_elapsed_p95 (q_demo_042: elapsed 12.4 s = 0.4 compile + 0.2 queue + 11.8 execution).

#### query_failure_rate

- Relation: `v_query_exec`; measure `RATIO`; population: —.
- Numerator COUNT(*); denominator COUNT(*); denominator scope `SAME_AS_NUMERATOR`.
- failed / (succeeded + failed); cancelled excluded; taxonomy versioned.

#### query_queued_time_sum

- Relation: `v_query_exec`; measure `SUM` of `queued_ms`; population: status_class IN ['SUCCEEDED', 'FAILED', 'CANCELLED'].
- Σ(QUEUED_OVERLOAD_TIME + QUEUED_PROVISIONING_TIME).

#### realized_savings

- Relation: `v_insight_summary`; measure `SUM` of `realized_amount`; population: row_kind EQ REALIZED AND realized_status EQ VERIFIED AND is_counted_realized EQ True.
- Verified normalized savings for non-overlapping action scopes and measurement windows; negative (adverse) values are kept, never clamped. Fixture: expected 24,000 − observed 18,000 = 6,000; adverse 24,000 − 26,000 = −2,000.

#### run_rate_daily

- Relation: `v_budget_daily`; measure `RATIO`; population: —.
- Numerator SUM(actual_amount); denominator COUNT(*); denominator scope `SAME_AS_NUMERATOR`.
- Parameters: `budget_id` (required).
- actual / complete days (money per day). Fixture: 15,000 / 15 = 1,000. Null INSUFFICIENT_DATA below 3 complete days.

#### spcs_node_hours

- Relation: `v_attribution_daily`; measure `SUM` of `spcs_node_hours`; population: service_family EQ SPCS.
- Source availability TO VERIFY LIVE (FIN-019); until verified the capability flag is false and the value is null NOT_SUPPORTED.

#### spend

- Relation: `v_charge_daily`; measure `SUM` of `cost_effective`; population: measure_role EQ CHARGE.
- Substitution: resource dimensions → `attributed_cost@1` with residual row `__UNATTRIBUTED__`.
- Signed net Σ fct_charge.cost_effective at D-12 bucket grain (canonical: semantic-api.md 'spend'). Grouping by any resource/actor/workload dimension is rewritten to attributed_cost@1 and returns meta.metric_substitution; group/tag dimensions are refused (use allocated_spend). Organization-only adjustments are never copied to accounts: at account scope they are absent, and a tile that asks for them gets null NOT_APPLICABLE.

#### storage_bytes

- Relation: `v_storage_daily`; measure `GAUGE` of `average_bytes`; population: —.
- Parameters: `gauge_mode`.
- Gauge, never summed over days. LATEST = value on the last observed day per group; TWA = Σ(bytes×seconds)/Σ(observed seconds). Oracle: 10 TB × 20 d + 12 TB × 10 d over 30 d → TWA 10.666… TB, LATEST 12 TB. Summed across databases/classes. Billed storage money is spend/attributed_cost, never derived from bytes (G-UX-11).

#### tag_coverage

- Relation: `v_attribution_daily`; measure `RATIO`; population: —.
- Numerator SUM_ABS(amount); denominator SUM_ABS(amount); denominator scope `SAME_AS_NUMERATOR`.
- Parameters: `tag_key` (required).
- Σ|cost of resources carrying tag_key on the usage date| / Σ|eligible (non-residual) cost|. Native tags need Enterprise (ACCESS/TAG_REFERENCES); on Standard edition only External Tag Studio assignments count (capability degradation, D-20).

#### unallocated_spend

- Relation: `v_allocation_daily`; measure `SUM` of `allocated_amount`; population: is_unallocated EQ True.
- Parameters: `book_id` (required).
- API.md alias unallocated_cost. '__UNALLOCATED__' leaf of the book; requires an explicit unallocated grant or book-wide scope (ALC-102-S02: Finance-only profile → 403 QUERY_METRIC_FORBIDDEN).

#### unattributed_cost

- Relation: `v_attribution_daily`; measure `SUM` of `amount`; population: is_residual EQ True.
- Residual rows only (UNATTRIBUTED, PRORATION_RESIDUAL, OVER_ATTRIBUTED, HIDDEN_RESOURCE kinds).

#### warehouse_compute_cost

- Relation: `v_charge_daily`; measure `SUM` of `cost_effective`; population: measure_role EQ CHARGE AND service_family EQ WAREHOUSE_COMPUTE.
- Substitution: resource dimensions → `attributed_cost@1` with residual row `__UNATTRIBUTED__`.
- Warehouse component of authoritative charges (or the explicit estimate basis). Substituted by attributed_cost restricted to service_family = WAREHOUSE_COMPUTE (the population predicate is carried) when grouped by warehouse, user, workload, …: 200 = query 140 + idle 60.

#### warehouse_credits

- Relation: `v_attribution_daily`; measure `SUM` of `credits`; population: service_family EQ WAREHOUSE_COMPUTE.
- WAREHOUSE_METERING_HISTORY compute credits (operational, pre-adjustment), split exactly over query/idle/residual attribution rows.

#### warehouse_utilization

- Relation: `None`; measure `NONE`; population: —.
- Declared so the screen binds to a registry id; always null NOT_SUPPORTED in R1. Utilization is never inferred from credits.

#### workload_classification_coverage

- Relation: `v_attribution_daily`; measure `RATIO`; population: —.
- Numerator SUM_ABS(amount); denominator SUM_ABS(amount); denominator scope `SAME_AS_NUMERATOR`.
- Σ|query compute with workload_type ≠ UNKNOWN| / Σ|query compute|. Fixture: 14,000 / 14,000 = 1; with one UNKNOWN query of 100 → 13,900 / 14,000 = 0.992857142857…

## Dimension catalog (generated)

| Dimension | Group | Kind | Cardinality | Entitlement | Privacy | Autocomplete |
|---|---|---|---|---|---|---|
| `account` | BILLING | ENTITY | MEDIUM | account | CUSTOMER_METADATA | prefix ≥ 0 |
| `ai_family` | RESOURCE | ENUM | LOW | — | INTERNAL | — |
| `ai_model` | RESOURCE | ATTRIBUTE | MEDIUM | — | CUSTOMER_METADATA | — |
| `allocation_method` | OWNERSHIP | ENUM | LOW | — | INTERNAL | — |
| `billing_type` | BILLING | ATTRIBUTE | LOW | — | INTERNAL | — |
| `book` | OWNERSHIP | ENTITY | LOW | — | CUSTOMER_METADATA | — |
| `client_application` | ACTOR | ATTRIBUTE | LOW | — | CUSTOMER_METADATA | — |
| `cloud` | BILLING | ENUM | LOW | — | INTERNAL | — |
| `component_kind` | OWNERSHIP | ENUM | LOW | — | INTERNAL | — |
| `compute_pool` | RESOURCE | ENTITY | LOW | — | CUSTOMER_METADATA | prefix ≥ 0 |
| `currency` | BILLING | ATTRIBUTE | LOW | — | INTERNAL | — |
| `data_status` | QUALITY | ENUM | LOW | — | INTERNAL | — |
| `database` | RESOURCE | ENTITY | MEDIUM | — | CUSTOMER_METADATA | prefix ≥ 1 |
| `day` | TIME | TIME | LOW | — | INTERNAL | — |
| `dbt_model` | WORKLOAD | ENTITY | HIGH | — | CUSTOMER_METADATA | prefix ≥ 2 |
| `dbt_project` | WORKLOAD | ENTITY | LOW | — | CUSTOMER_METADATA | prefix ≥ 0 |
| `dbt_resource_type` | WORKLOAD | ENUM | LOW | — | INTERNAL | — |
| `dynamic_table` | RESOURCE | ENTITY | MEDIUM | — | CUSTOMER_METADATA | prefix ≥ 1 |
| `environment` | WORKLOAD | ENUM | LOW | — | INTERNAL | — |
| `evidence_class` | WORKLOAD | ENUM | LOW | — | INTERNAL | — |
| `execution_kind` | WORKLOAD | ENUM | LOW | — | INTERNAL | — |
| `group` | OWNERSHIP | ENTITY | MEDIUM | group | CUSTOMER_METADATA | prefix ≥ 1 |
| `group_ancestor` | OWNERSHIP | ENTITY | MEDIUM | — | CUSTOMER_METADATA | prefix ≥ 1 |
| `group_set` | OWNERSHIP | ENTITY | LOW | group_set | CUSTOMER_METADATA | prefix ≥ 0 |
| `is_adjustment` | BILLING | BOOLEAN | LOW | — | INTERNAL | — |
| `month` | TIME | TIME | LOW | — | INTERNAL | — |
| `organization` | BILLING | ENTITY | LOW | organization | CUSTOMER_METADATA | prefix ≥ 0 |
| `pbi_mode` | WORKLOAD | ENUM | LOW | — | INTERNAL | — |
| `pipe` | RESOURCE | ENTITY | MEDIUM | — | CUSTOMER_METADATA | prefix ≥ 1 |
| `price_basis` | QUALITY | ENUM | LOW | — | INTERNAL | — |
| `query_parameterized_hash` | WORKLOAD | ATTRIBUTE | HIGH | — | INTERNAL | prefix ≥ 4 |
| `query_status` | WORKLOAD | ENUM | LOW | — | INTERNAL | — |
| `rating_type` | BILLING | ATTRIBUTE | LOW | — | INTERNAL | — |
| `region` | BILLING | ATTRIBUTE | LOW | — | CUSTOMER_METADATA | — |
| `role` | ACTOR | ATTRIBUTE | MEDIUM | — | CUSTOMER_METADATA | prefix ≥ 1 |
| `schema` | RESOURCE | ENTITY | HIGH | — | CUSTOMER_METADATA | prefix ≥ 2 |
| `scope_kind` | BILLING | ENUM | LOW | — | INTERNAL | — |
| `service_category` | BILLING | ENUM | LOW | — | INTERNAL | — |
| `service_family` | BILLING | ENUM | LOW | — | INTERNAL | — |
| `service_type` | BILLING | ATTRIBUTE | LOW | — | INTERNAL | — |
| `spcs_service` | RESOURCE | ENTITY | MEDIUM | — | CUSTOMER_METADATA | prefix ≥ 1 |
| `storage_class` | RESOURCE | ENUM | LOW | — | INTERNAL | — |
| `sub_service` | BILLING | ATTRIBUTE | MEDIUM | — | INTERNAL | — |
| `tag` | OWNERSHIP | ATTRIBUTE | HIGH | — | CUSTOMER_METADATA | prefix ≥ 2 |
| `task` | RESOURCE | ENTITY | HIGH | — | CUSTOMER_METADATA | prefix ≥ 2 |
| `user` | ACTOR | ENTITY | HIGH | — | PERSONAL (pseudonym) | prefix ≥ 2 |
| `warehouse` | RESOURCE | ENTITY | MEDIUM | — | CUSTOMER_METADATA | prefix ≥ 1 |
| `warehouse_size` | RESOURCE | ATTRIBUTE | LOW | — | INTERNAL | — |
| `warehouse_type` | RESOURCE | ENUM | LOW | — | INTERNAL | — |
| `week` | TIME | TIME | LOW | — | INTERNAL | — |
| `workload` | WORKLOAD | ENTITY | MEDIUM | — | CUSTOMER_METADATA | prefix ≥ 1 |
| `workload_type` | WORKLOAD | ENUM | LOW | — | INTERNAL | — |

## Relations (generated)

| Relation | Serving view | Tier | Policy | Grain |
|---|---|---|---|---|
| `v_ai_usage` | `bridge.serving.serving_ai_usage` | FULL | RAP_ACCOUNT_SCOPED | tenant_id, ai_usage_row_key |
| `v_allocation_coverage_daily` | `bridge.serving.serving_allocation_coverage_daily` | FULL | RAP_ACCOUNT_SCOPED | tenant_id, book_id, coverage_bucket_key |
| `v_allocation_daily` | `bridge.serving.srv_allocation_restricted` | FULL | RAP_GROUP_SCOPED | tenant_id, allocation_row_key |
| `v_attribution_daily` | `bridge.serving.serving_attribution_daily` | FULL | RAP_ACCOUNT_SCOPED | tenant_id, attribution_row_key |
| `v_budget_daily` | `bridge.serving.serving_budget_daily` | FULL | RAP_GROUP_SCOPED | tenant_id, budget_id, budget_revision_id, usage_date |
| `v_charge_daily` | `bridge.serving.serving_daily_charge` | FULL | RAP_ACCOUNT_SCOPED | tenant_id, charge_row_id |
| `v_charge_source_set` | `bridge.serving.serving_charge_source_set` | FULL | RAP_ACCOUNT_SCOPED | tenant_id, charge_row_id, source_view, batch_id |
| `v_dim_account` | `bridge.serving.serving_dim_account` | FULL | RAP_ACCOUNT_SCOPED | tenant_id, account_id |
| `v_dim_dbt_model` | `bridge.serving.serving_dim_dbt_model` | FULL | RAP_ACCOUNT_SCOPED | tenant_id, dbt_model_key |
| `v_dim_group` | `bridge.serving.serving_dim_group` | FULL | RAP_GROUP_SCOPED | tenant_id, book_id, group_id, valid_from |
| `v_dim_group_closure` | `bridge.serving.serving_dim_group_closure` | FULL | RAP_GROUP_SCOPED | tenant_id, book_id, ancestor_group_id, descendant_group_id, valid_from |
| `v_dim_resource` | `bridge.serving.serving_dim_resource` | FULL | RAP_ACCOUNT_SCOPED | tenant_id, resource_kind, resource_id |
| `v_dim_workload` | `bridge.serving.serving_dim_workload` | FULL | RAP_ACCOUNT_SCOPED | tenant_id, workload_key |
| `v_forecast` | `bridge.serving.serving_forecast` | FULL | RAP_GROUP_SCOPED | tenant_id, forecast_row_key |
| `v_insight_summary` | `bridge.serving.serving_insight_summary` | FULL | RAP_ACCOUNT_SCOPED | tenant_id, insight_row_key |
| `v_query_exec` | `bridge.serving.serving_query_exec` | HOT | RAP_ACCOUNT_SCOPED | tenant_id, account_id, query_id |
| `v_query_family_daily` | `bridge.serving.serving_query_family_daily` | AGGREGATE | RAP_ACCOUNT_SCOPED | tenant_id, family_row_key |
| `v_storage_daily` | `bridge.serving.serving_storage_daily` | FULL | RAP_ACCOUNT_SCOPED | tenant_id, storage_row_key |
| `v_tag_assignment` | `bridge.serving.serving_tag_assignment` | FULL | RAP_ACCOUNT_SCOPED | tenant_id, target_kind, target_id, tag_key, valid_from |
| `v_workload_exec` | `bridge.serving.serving_workload_exec` | FULL | RAP_ACCOUNT_SCOPED | tenant_id, account_id, execution_id |

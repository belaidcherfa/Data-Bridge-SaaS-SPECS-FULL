# dbt Core deterministic transformation framework

Canonical domain contract. Owner: Analytics engineer. Implementation state: NOT_STARTED.


## Layer ownership and grain

`staging` casts/renames/UTC/deduplicates accepted raw; `intermediate` resolves identities/time/workloads; `ledger` produces independent service charge models and attribution bridges; `allocation` consumes approved config versions; `marts` builds analytical domain facts; `serving` builds bounded query-friendly partitions. (amended 2026-09-28, D-05, G-DBT-12, G-FIN-18, G-ALC-01) Staging models are **read-time deduplication views** over accepted RAW (registry `dedup_mode` NATURAL_KEY or WINDOW_SNAPSHOT, reading only through `accepted_source()` with `accepted_seq <= snapshot_seq`), not merged tables. Ledger money comes from two generic models (authoritative billing normalizer and provisional estimator); per-service models are attribution models, with `ledger_<family>` kept as thin views. Allocation reads only `int_alloc_unit`. Workload classification is set-based dbt SQL (D-34, WRK-001) with a Python reference as test oracle; `fct_query_workload` replaces the PRD §54 `PY_WORKLOAD_CLASSIFICATION` output. Metadata lives under `config.meta.bridge`, validated by JSON Schema, because dbt ≥ 1.10 requires custom keys under `meta`. Each model declares grain, unique key, tenant key, event/processing timestamps, authoritative source, dependency list, incremental strategy, coverage policy and privacy classification in YAML metadata.

Every service model is independently testable against shared staging/reference contracts; one service must not depend on another service's ledger output. A union canonical ledger references independent outputs by an explicit include registry, not directory wildcard. Empty capability-disabled branches return a typed empty relation plus coverage metadata; they do not manufacture zero spend.

## Incremental and correction contract

Use exact composite unique keys including tenant/account. For source rows, select latest accepted authoritative revision with deterministic tie-breaker. For complete partition snapshots, replace the selected partition version so rows removed by a correction disappear. (amended 2026-09-28, D-05, D-06, G-DBT-01…04) The write model is [ADR-014](../architecture/adr/ADR-014-analytical-revisions.md), which replaces the former per-tenant/dataset/partition lease and MERGE wording: facts are written by the custom `revisioned` materialization as insert-only revisions `(tenant_id, scope_id, partition_start, revision_id, build_id)` of the partitions listed in `BUILD_WORKSET`, zero-row partitions included; there is no MERGE in R1. dbt's built-in `insert_overwrite` (truncates the whole table) and `microbatch` (deletes a time slice for all tenants) are rejected (VERIFIED). Partition grain is declared per dataset: query-grain facts by (account, **hour**), charges/attribution/allocation/serving by (scope, **day**), monthly marts by (tenant, month). Builds are multi-tenant and set-based; per-tenant failures are isolated at publication. Reprocess source-specific overlap plus anti-entropy windows, not a universal two-day cutoff.

(amended 2026-09-28, G-DBT-03) The only dbt variable is `build_id`; tenant scope, windows, the accepted-input bound (`snapshot_seq`) and per-tenant config versions (`BUILD_CONFIG_PIN`, D-04) are data read through the `in_workset()`, `accepted_source()` and `pinned_config()` macros, replacing typed tenant/account/window run variables. Validate variables, quote identifiers through adapter APIs and bind values where possible; no raw user SQL in Jinja. Full refresh in production is a controlled shadow rebuild followed by comparison and pointer publication, not dropping live serving tables; the `revisioned` materialization refuses `--full-refresh`. (amended 2026-09-28, G-DBT-05, D-26) Each dataset declares `rebuild_horizon_days`: financial sources keep RAW 400 days, query-grain sources 90 days, and a request beyond the horizon returns `REBUILD_HORIZON_EXCEEDED`.

## Financial numerical standards

NUMBER/Decimal preserves source precision; canonical money uses NUMBER(38,12) internally, currency minor-unit rounding only at statement/export boundaries. (amended 2026-09-28, G-FIN-19, G-ALC-06) Cast both operands explicitly before multiplication or division (Snowflake scale rules otherwise round below 12 decimals); exact allocation and statement rounding use the FIN-106 `allocate_exact` and `round_statement_lines` macros ([ADR-015](../architecture/adr/ADR-015-financial-grain-maturity-attribution.md)). A `no_float_columns` test covers RAW, staging and ledger. Source monetary fields with coarser precision stay annotated. Never average percentiles, prices or ratios blindly; define numerator/denominator and population. Null unknown costs remain null with reason; distinguish zero confirmed usage. Signed adjustments are legal. (amended 2026-09-28, G-DBT-10) Sign rules are keyed by `entry_kind` (usage ≥ 0; adjustment, rebate, credit and correction any sign) and conservation is exact, which refines the PRD §52 blanket `cost >= 0` tests. Join assertions must detect fanout before financial sums.

## Tests and CI

Use dbt built-in tests plus custom SQL tests for tenant-safe keys, accepted-batch-only lineage, no service double inclusion, signed-entry validity, conservation and publication consistency. (amended 2026-09-28, G-DBT-07, G-DBT-08) Snowflake does not enforce primary, unique or foreign keys, so uniqueness and relationships are check models writing to `QUALITY.CHECK_RESULT`; a static checker (sqlglot over compiled SQL) requires a tenant_id conjunct on every join between tenant-bearing relations, complemented by a golden fixture where tenants share account locators, warehouse names and query IDs. Golden fixtures are deterministic and separate from real source data. Run modified models in isolated CI schemas, with dependency deferral only to approved compatible manifests — (amended 2026-09-28, G-DBT-09) that is, to a fixture-built CI baseline in `BRIDGE_CI`, never to production; CI authenticates by GitHub OIDC → AWS → Snowflake WIF (D-21), schemas are named `CI_PR<nr>_<sha7>_<layer>` with a 24 h ownership-based janitor, and changes to financial layers always run the full golden end-to-end suite ([DBT backlog](../22-implementation-readiness/backlog/DBT.md)). Keep temporary schemas behind isolated roles and TTL cleanup. `dbt parse`/`compile` are syntax gates; live `dbt build` with fixtures is the SQL correctness gate. [Incremental models](https://docs.getdbt.com/docs/build/incremental-models) and [dbt unit tests](https://docs.getdbt.com/docs/build/unit-tests).

## Identity and dimensional history

Use internal durable resource IDs with source ID/instance/account keys; names are attributes with validity ranges. For snapshot-only metadata, capture SCD2 from first observation and record uncertainty before enrollment. (amended 2026-09-28, G-DBT-11) SCD2 is built as deterministic models over the extracted observation log (half-open validity ranges), not with `dbt snapshot`, which is not replay-safe; this refines the PRD §44 `snapshots/` directory. Effective-dated source/account membership and rule versions must align to the cost event, not today's name/tag. Left joins retain unattributed/unowned rows and coverage explanations.

## Publication and documentation

Each run produces manifest, run_results, test results and redacted lineage metadata tagged with build ID, snapshot sequence, config pins and git SHA. Publish generated model docs privately; do not expose customer SQL/names through public artifacts. (amended 2026-09-28, G-DBT-15) Docs are generated only from the fixture CI baseline, never against production targets. Attach source→raw file→model→ledger lineage to Explain This Number. The ORC publication manifest is the cross-model consistency boundary.


## Implementation sequence

(amended 2026-09-28) The dependency and gate columns below are the original index. Execution follows the revised graph ([revised-task-graph.json](../22-implementation-readiness/revised-task-graph.json), [revised critical path](../22-implementation-readiness/REVISED_CRITICAL_PATH.md)) and phases P0–P6 of the [release plan](../22-implementation-readiness/RELEASE_PLAN.md); new tasks, revised steps, dependencies and task acceptance are in [backlog/DBT.md](../22-implementation-readiness/backlog/DBT.md).

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [DBT-001](../tasks/DBT/DBT-001.md) | Bootstrap dbt Core project, profiles and model contracts | ORC-004, ING-008 | M4 |
| [DBT-002](../tasks/DBT/DBT-002.md) | Implement staging dedup and complete-partition revisions | DBT-001, ING-008 | M4 |
| [DBT-003](../tasks/DBT/DBT-003.md) | Resolve resource history, account membership and workload joins | DBT-002, CTL-001 | M4 |
| [DBT-004](../tasks/DBT/DBT-004.md) | Implement bounded incremental merges and shadow rebuild (amended 2026-09-28: workset-bounded revisioned rebuilds, no MERGE, ADR-014) | DBT-003, ORC-005 | M4 |
| [DBT-005](../tasks/DBT/DBT-005.md) | Build golden financial tests and tenant-safe CI | DBT-004, FND-005, SEC-008 | M4 |
| [DBT-006](../tasks/DBT/DBT-006.md) | Build serving partition revisions and explainable lineage | DBT-005, SEC-005 | M4 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

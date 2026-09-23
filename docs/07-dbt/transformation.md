# dbt Core deterministic transformation framework

Canonical domain contract. Owner: Analytics engineer. Implementation state: NOT_STARTED.


## Layer ownership and grain

`staging` casts/renames/UTC/deduplicates accepted raw; `intermediate` resolves identities/time/workloads; `ledger` produces independent service charge models and attribution bridges; `allocation` consumes approved config versions; `marts` builds analytical domain facts; `serving` builds bounded query-friendly partitions. Each model declares grain, unique key, tenant key, event/processing timestamps, authoritative source, dependency list, incremental strategy, coverage policy and privacy classification in YAML metadata.

Every service model is independently testable against shared staging/reference contracts; one service must not depend on another service's ledger output. A union canonical ledger references independent outputs by an explicit include registry, not directory wildcard. Empty capability-disabled branches return a typed empty relation plus coverage metadata; they do not manufacture zero spend.

## Incremental and correction contract

Use exact composite unique keys including tenant/account. For source rows, select latest accepted authoritative revision with deterministic tie-breaker. For complete partition snapshots, replace the selected partition version so rows removed by a correction disappear. Use a serialized per-tenant/dataset/partition lease for overlapping dbt runs; dedup source before MERGE to avoid multi-match nondeterminism. Reprocess source-specific overlap plus anti-entropy windows, not a universal two-day cutoff.

Model invocations receive typed tenant, account scope, window and config/publication IDs from trusted run context. Validate variables, quote identifiers through adapter APIs and bind values where possible; no raw user SQL in Jinja. Full refresh in production is a controlled shadow rebuild followed by comparison and pointer publication, not dropping live serving tables.

## Financial numerical standards

NUMBER/Decimal preserves source precision; canonical money uses NUMBER(38,12) internally, currency minor-unit rounding only at statement/export boundaries. Source monetary fields with coarser precision stay annotated. Never average percentiles, prices or ratios blindly; define numerator/denominator and population. Null unknown costs remain null with reason; distinguish zero confirmed usage. Signed adjustments are legal. Join assertions must detect fanout before financial sums.

## Tests and CI

Use dbt built-in tests plus custom SQL tests for tenant-safe keys, accepted-batch-only lineage, no service double inclusion, signed-entry validity, conservation and publication consistency. Golden fixtures are deterministic and separate from real source data. Run modified models in isolated CI schemas, with dependency deferral only to approved compatible manifests. Keep temporary schemas behind isolated roles and TTL cleanup. `dbt parse`/`compile` are syntax gates; live `dbt build` with fixtures is the SQL correctness gate. [Incremental models](https://docs.getdbt.com/docs/build/incremental-models) and [dbt unit tests](https://docs.getdbt.com/docs/build/unit-tests).

## Identity and dimensional history

Use internal durable resource IDs with source ID/instance/account keys; names are attributes with validity ranges. For snapshot-only metadata, capture SCD2 from first observation and record uncertainty before enrollment. Effective-dated source/account membership and rule versions must align to the cost event, not today's name/tag. Left joins retain unattributed/unowned rows and coverage explanations.

## Publication and documentation

Each run produces manifest, run_results, test results and redacted lineage metadata tagged with tenant/window/config and git SHA. Publish generated model docs privately; do not expose customer SQL/names through public artifacts. Attach source→raw file→model→ledger lineage to Explain This Number. The ORC publication manifest is the cross-model consistency boundary.


## Implementation sequence

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [DBT-001](../tasks/DBT/DBT-001.md) | Bootstrap dbt Core project, profiles and model contracts | ORC-004, ING-008 | M4 |
| [DBT-002](../tasks/DBT/DBT-002.md) | Implement staging dedup and complete-partition revisions | DBT-001, ING-008 | M4 |
| [DBT-003](../tasks/DBT/DBT-003.md) | Resolve resource history, account membership and workload joins | DBT-002, CTL-001 | M4 |
| [DBT-004](../tasks/DBT/DBT-004.md) | Implement bounded incremental merges and shadow rebuild | DBT-003, ORC-005 | M4 |
| [DBT-005](../tasks/DBT/DBT-005.md) | Build golden financial tests and tenant-safe CI | DBT-004, FND-005, SEC-008 | M4 |
| [DBT-006](../tasks/DBT/DBT-006.md) | Build serving partition revisions and explainable lineage | DBT-005, SEC-005 | M4 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

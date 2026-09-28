# Dagster OSS orchestration and data publication

Canonical domain contract. Owner: Data platform engineer. Implementation state: NOT_STARTED.


## Production topology

Deploy webserver, one active daemon, versioned code locations and isolated ECS run workers. Use separate `dagster_meta` database/user and migrations with backups; never reuse application schemas. UI is private. Use the OSS ECS run launcher/integration after validating its pinned configuration and task-role behavior. [Dagster AWS deployment](https://docs.dagster.io/deployment/oss/deployment-options/aws). (amended 2026-09-28, D-07, G-ORC-03, G-ORC-05) Validation showed that dagster-aws `EcsRunLauncher` sets a per-run task role only through the user-writable `ecs/task_overrides` run tag and that ECS `RunTask` overrides cannot be constrained by IAM (both VERIFIED). The stock launcher therefore runs only Dagster's own runs, with no connection roles and no `iam:PassRole` on them; **customer extraction is started by the dedicated extraction launcher (ING-106), never by Dagster** ([ADR-008 amendment](../architecture/adr/ADR-008-queues-and-orchestration.md)). The daemon runs as one ECS task (`minimumHealthyPercent=0`, `maximumPercent=100`, heartbeat-age alarm); the webserver is `--read-only` by default and reached through the operator SSM tunnel, a writable instance only under break-glass.

Definitions are generic source/data-family assets. Code locations split extraction/ingestion, dbt, intelligence, monitoring/reporting and maintenance by resource boundary, not tenant. Assets invoke pure library interfaces; SQL/business formulas live in dbt/Python packages. `Definitions` import must not query customer accounts or perform network mutations.

## Partitions, runs and fairness

(amended 2026-09-28, D-07, G-ORC-01) There are **no Dagster partitions on tenant, account or connection** (500 accounts × 365 days = 182,500 partitions per asset, above the ~100k guidance) and **no Dagster run per account-cycle**. ORC-003 admission marks `sync.account_cycles` rows ADMITTED in PostgreSQL; the extraction launcher claims them and calls `RunTask`; an ECS task-state event completes the cycle; a Dagster sensor records sync outcomes as asset observations. Extraction and ingestion assets are observations; daily time partitions are allowed only for global maintenance assets (purge, GC, recovery snapshot, cost collection). Large historical interval coverage remains in PostgreSQL, not a million duplicated static DAGs. A single-account run cannot certify a global multi-tenant day. Record partition cardinality and shard deployments by region/workload class before measured limits, keeping one codebase.

Run config accepts validated connection/job IDs; the extraction launcher resolves identity from PostgreSQL and source policy. (amended 2026-09-28, G-ORC-02, C-03, C-05, D-33) Admission budgets follow Little's law (500 hourly cycles × ~4 min ≈ 33 concurrent): steady cycles 60 total / 6 per tenant / 1 per account, each connection's cycle minute `5 + (hash(connection_id) mod 50)`; backfill 12 total / 4 per tenant, admitted only while steady p95 queue age < 5 min; dbt steady lane 1 build at a time plus 1 repair/shadow lane; Python 2. There is **no Dagster report lane**: interactive analysis, export and report jobs run in long-lived workers (D-33). The 15-minute per-source cadence is superseded by one hourly account-cycle (D-08). Treat these as starting configuration for load tests (OPS-008). Reserve steady-state capacity and weighted-fair tenant admission; do not use a global FIFO that lets one backfill monopolize workers. Dagster pool/run limits complement durable PostgreSQL leases. [Concurrency controls](https://docs.dagster.io/guides/operate/managing-concurrency).

Sensor run keys hash job/config/partition revision and semantic purpose; duplicate sensor ticks still hit the durable idempotency gate. (amended 2026-09-28, G-ORC-04) Dagster OSS has no run retention and sensor de-duplication silently depends on retained runs, so the PostgreSQL cycle/build claim is the only idempotency authority and ORC-102 purges runs and events (extraction-related success 14 d, dbt/publication success 30 d, failures 90 d) under a 50 GB metadata budget. Retry only classified transient failures with exponential jitter and a finite budget. Auth/schema/financial failures require remediation, not infinite reruns. Cancellation fences work, stops new uploads/publications and attempts source query cancellation safely.

## Assets and checks

The graph is source/capability → planned extraction → journaled batch → RAW acceptance → staging → ledger/intermediate → Python outputs → marts → quality/reconciliation → publication → cache/version notification → monitors/reports. Never trigger staging from S3 notification alone. (amended 2026-09-28, G-ORC-07, G-ORC-09, U-18, C-17, D-34) A multi-tenant dbt build starts when the oldest unprocessed accepted batch is ≥ 10 min old or ≥ 500 batches wait (ORC-101 processing ledger). Workload classification is a dbt model, not a Python output. Python outputs (forecasts, anomaly and insight candidates) land through the ORC-103 writer only — Arrow → Parquet → `PUT` to an internal stage → `COPY INTO … FILES=` → checksum against a run manifest → revisioned insert; no Snowpipe, no customer journal — and are published in a second phase pinned to the financial publication they read (`input_pub_seq`), so a Python failure never blocks ledger publication. Asset checks attach transport, schema, row identity, transformation and financial evidence. Failed optional sources yield scoped degraded coverage; failed mandatory invariants block publication.

Use dagster-dbt manifest integration with dbt Core execution and preserve model-level lineage/checks; select only affected partitions/models, not a full 365-day platform rebuild. [dbt integration](https://docs.dagster.io/integrations/libraries/dbt). (amended 2026-09-28, D-06) dbt runs are multi-tenant and set-based; the only dbt variable is `build_id`, and the exact partitions are data in `BUILD_WORKSET`. Tenant-scoped check failures gate only that tenant's publication (check results in `QUALITY.CHECK_RESULT`, absence = FAIL); allocation simulations are Dagster dbt jobs (`allocation_sim` selector, concurrency 1 per tenant) with an API job record.

## Publication transaction

Build candidate partition revisions in Snowflake. A publication manifest maps tenant, dataset and each partition to a physical revision, plus schema/metric/config/algorithm/code versions and coverage. Reuse unchanged partitions; do not copy 500M rows on every publication. After all required checks pass, one Snowflake transaction advances the tenant publication pointer. (amended 2026-09-28, D-05, G-ORC-06, G-ORC-10) The publication design is [ADR-014](../architecture/adr/ADR-014-analytical-revisions.md): insert-only revisioned partitions, an SCD2 `PUBLICATION_MAP`, and one DML-only `PUBLISH_BATCH(pub_seq, build_id, fence_token)` compare-and-swap that advances all eligible tenants' pointers set-based under a lane fence (DDL auto-commits and can never take part). Rollback is a forward republication of prior revisions; the pointer never decreases. PostgreSQL holds only the reference/status via idempotent ack. An interrupted ack can be reconciled from Snowflake; it cannot roll back analytical truth accidentally.

API responses, cursors, reports and monitor evaluations pin one publication manifest (`pub_seq`). Old revisions remain while active jobs/statements reference them, then expire under retention. (amended 2026-09-28, G-ORC-13) Long-lived holders create explicit pins; cursors rely on a grace window of max(cursor TTL + 15 min, 7-day rollback window); ORC-105 is the only physical deleter of revisioned rows and purged pins answer RESTART_REQUIRED. Cache invalidation announces a version; consumers reading an older accepted version show its as-of timestamp. No user sees a half-new ledger/half-old allocation snapshot.

## Operational health

Record daemon heartbeat, sensor lag, queued age by class, lease wait, run cancellation, asset check failure, partition backlog and publication age. (amended 2026-09-28) Also record admitted-but-unlaunched cycles, launcher `RunTask` failures, cycle overruns, gated and quarantined tenants per build, read amplification (alarm above 3) and Dagster metadata size. Keep customer health vocabulary separate from Dagster internals. Alert on steady-state starvation and stalled accepted batches, not merely failed process counts.


## Implementation sequence

(amended 2026-09-28) The dependency and gate columns below are the original index. Execution follows the revised graph ([revised-task-graph.json](../22-implementation-readiness/revised-task-graph.json), [revised critical path](../22-implementation-readiness/REVISED_CRITICAL_PATH.md)) and phases P0–P6 of the [release plan](../22-implementation-readiness/RELEASE_PLAN.md); new tasks, revised steps, dependencies and task acceptance are in [backlog/ORC.md](../22-implementation-readiness/backlog/ORC.md).

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [ORC-001](../tasks/ORC/ORC-001.md) | Deploy private OSS control services and metadata database | INF-007, CTL-002 | M3 |
| [ORC-002](../tasks/ORC/ORC-002.md) | Define generic assets and bounded partition catalog | ORC-001, ING-008 | M3 |
| [ORC-003](../tasks/ORC/ORC-003.md) | Implement fair queues, schedules and idempotent sensors | ORC-002, CTL-004 | M3 |
| [ORC-004](../tasks/ORC/ORC-004.md) | Integrate dbt assets and Python result dependencies | ORC-003, ING-009, CON-002 | M3 |
| [ORC-005](../tasks/ORC/ORC-005.md) | Publish coherent datasets and version notifications | ORC-004, CTL-005, CTL-006 | M3 |
| [ORC-006](../tasks/ORC/ORC-006.md) | Exercise backfill, cancellation and selective recovery | ORC-005, ING-011 | M3 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

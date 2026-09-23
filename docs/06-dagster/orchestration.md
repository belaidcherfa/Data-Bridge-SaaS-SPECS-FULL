# Dagster OSS orchestration and data publication

Canonical domain contract. Owner: Data platform engineer. Implementation state: NOT_STARTED.


## Production topology

Deploy webserver, one active daemon, versioned code locations and isolated ECS run workers. Use separate `dagster_meta` database/user and migrations with backups; never reuse application schemas. UI is private. Use the OSS ECS run launcher/integration after validating its pinned configuration and task-role behavior. [Dagster AWS deployment](https://docs.dagster.io/deployment/oss/deployment-options/aws).

Definitions are generic source/data-family assets. Code locations split extraction/ingestion, dbt, intelligence, monitoring/reporting and maintenance by resource boundary, not tenant. Assets invoke pure library interfaces; SQL/business formulas live in dbt/Python packages. `Definitions` import must not query customer accounts or perform network mutations.

## Partitions, runs and fairness

Use source-family assets with daily time partitions and a bounded dynamic connection/source dimension where native partition tracking is useful. Large historical interval coverage remains in PostgreSQL, not a million duplicated static DAGs. Each materialization declares tenant/account/window and accepted batch references; a single-account run cannot certify a global multi-tenant day. Record partition cardinality and shard deployments by region/workload class before measured limits, keeping one codebase.

Run config accepts validated connection/job IDs; launcher resolves identity and source policy. Initial concurrency budgets are deliberately conservative: steady-state extraction 8 total/2 per tenant/1 per account-source; backfill 2 total/1 per tenant; dbt 2; Python 2; reports 2. Treat these as starting configuration for load tests. Reserve steady-state capacity and weighted-fair tenant admission; do not use a global FIFO that lets one backfill monopolize workers. Dagster pool/run limits complement durable PostgreSQL leases. [Concurrency controls](https://docs.dagster.io/guides/operate/managing-concurrency).

Sensor run keys hash job/config/partition revision and semantic purpose; duplicate sensor ticks still hit the durable idempotency gate. Retry only classified transient failures with exponential jitter and a finite budget. Auth/schema/financial failures require remediation, not infinite reruns. Cancellation fences work, stops new uploads/publications and attempts source query cancellation safely.

## Assets and checks

The graph is source/capability → planned extraction → journaled batch → RAW acceptance → staging → ledger/intermediate → Python outputs → marts → quality/reconciliation → publication → cache/version notification → monitors/reports. Never trigger staging from S3 notification alone. Asset checks attach transport, schema, row identity, transformation and financial evidence. Failed optional sources yield scoped degraded coverage; failed mandatory invariants block publication.

Use dagster-dbt manifest integration with dbt Core execution and preserve model-level lineage/checks; select only affected partitions/models, not a full 365-day platform rebuild. [dbt integration](https://docs.dagster.io/integrations/libraries/dbt).

## Publication transaction

Build candidate partition revisions in Snowflake. A publication manifest maps tenant, dataset and each partition to a physical revision, plus schema/metric/config/algorithm/code versions and coverage. Reuse unchanged partitions; do not copy 500M rows on every publication. After all required checks pass, one Snowflake transaction advances the tenant publication pointer. PostgreSQL holds only the reference/status via idempotent ack. An interrupted ack can be reconciled from Snowflake; it cannot roll back analytical truth accidentally.

API responses, cursors, reports and monitor evaluations pin one publication manifest. Old revisions remain while active jobs/statements reference them, then expire under retention. Cache invalidation announces a version; consumers reading an older accepted version show its as-of timestamp. No user sees a half-new ledger/half-old allocation snapshot.

## Operational health

Record daemon heartbeat, sensor lag, queued age by class, lease wait, run cancellation, asset check failure, partition backlog and publication age. Keep customer health vocabulary separate from Dagster internals. Alert on steady-state starvation and stalled accepted batches, not merely failed process counts.


## Implementation sequence

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

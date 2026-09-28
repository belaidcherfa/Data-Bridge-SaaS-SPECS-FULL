# ADR-008 — Generic Dagster assets and durable fair queues

Status: Accepted for implementation. Date: 2026-09-23.

## Context

Per-customer DAG copies and unbounded backfills do not scale. Redis is disposable.

## Decision

Use stable generic asset definitions, runtime tenant/account/source context, bounded partition metadata, separate execution pools and PostgreSQL fenced leases. Dagster run IDs/sensors are orchestrator state; accepted coverage is a separate canonical operational record.

## Alternatives considered

One static asset graph per tenant explodes definitions. Redis locks alone can permit duplicate writers after failover.

## Consequences

Admission controls protect steady-state traffic; run tags are metadata, never authorization. Worker death and daemon restart must recover from durable state.

## Revisit conditions

Measured scheduler/partition cardinality or database event growth exceeds budget; shard by region/workload class, not customer code.

## Validation obligation

Implementation tasks must link redacted live evidence before production. Documentation acceptance is not execution evidence. See [delivery methodology](../../../DELIVERY_METHODOLOGY.md).

## Amendment 2026-09-28

Status: ACCEPTED (owner decision record 2026-09-28). Decisions: D-07, D-33 (with D-06 via [ADR-014](ADR-014-analytical-revisions.md)). Evidence: [decision record](../../22-implementation-readiness/DECISIONS_REQUIRED.md) D-07/D-33; [ORC backlog](../../22-implementation-readiness/backlog/ORC.md) G-ORC-01…05, G-ORC-09; [ING backlog](../../22-implementation-readiness/backlog/ING.md) G-ING-08/09 and ING-106; [INF backlog](../../22-implementation-readiness/backlog/INF.md) G-INF-08; [API backlog](../../22-implementation-readiness/backlog/API.md) G-API-12; [reconciliation](../../22-implementation-readiness/RECONCILIATION.md) C-03, C-04, C-05, U-12, U-18.

What changes:

1. **Extraction unit = account-cycle.** One ECS task per connection per hourly cycle runs all due sources with one customer warehouse resume (cycle minute `5 + (hash(connection_id) mod 50)`), under that connection's task role. The 15-minute per-source cadence is superseded.
2. **Dedicated extraction launcher, no Dagster run per account-cycle.** ORC-003 admission marks rows of `sync.account_cycles` ADMITTED in PostgreSQL (kinds STEADY, BACKFILL_CHUNK, ANTI_ENTROPY, PROBE, ORG). The launcher service (ING-106), not Dagster, claims them, resolves `connection_id → role` from PostgreSQL and calls ECS `RunTask`; an ECS task-state event completes the cycle; a Dagster sensor records outcomes as asset observations. Only the launcher holds `iam:PassRole` on `role/bridge-<env>-conn-*` (with `iam:PassedToService=ecs-tasks.amazonaws.com`). Reason (VERIFIED): dagster-aws `EcsRunLauncher` sets a per-run task role only through the user-writable `ecs/task_overrides` run tag, and ECS `RunTask` overrides cannot be constrained by IAM, so anyone able to launch a Dagster run could choose any customer's role. The stock launcher is used only for Dagster's own runs, which never receive connection roles.
3. **Extractor trust path.** Extractor tasks hold no PostgreSQL or Dagster credentials. They report through the internal `sync-api`, authenticated by a presigned `sts:GetCallerIdentity` request mapped to exactly one connection, which authorizes only that connection's cycle, leases, batch attempts and manifests.
4. **Dagster scope and hygiene.** No Dagster partitions on tenant, account or connection (500 accounts × 365 days would exceed ~100k partitions per asset); extraction/ingestion assets are observations; daily partitions only for global maintenance assets. Dagster OSS has no run retention, so ORC-102 purges runs/events (extraction success 14 d, dbt/publication success 30 d, failures 90 d); the PostgreSQL cycle claim is the only idempotency authority. The daemon runs single-instance (`minimumHealthyPercent=0`, `maximumPercent=100`); the webserver is `--read-only` by default and reached through an operator tunnel.
5. **Transform and Python lanes.** dbt runs are multi-tenant and set-based (D-06, ADR-014). Python outputs (forecasts, anomaly and insight candidates) land through ORC-103 light acceptance (PUT to an internal stage → `COPY INTO … FILES=` → checksum → revisioned insert), never through the customer journal or Snowpipe.
6. **Interactive, export and report jobs (D-33).** Long-lived workers (analysis-worker, render worker) claim PostgreSQL jobs with fenced leases and read only through the query broker ([ADR-005 amendment](ADR-005-analytical-authorization.md)); there is no Dagster `report` lane. Allocation simulations remain Dagster dbt jobs (`allocation_sim` selector, concurrency 1 per tenant) with an API job record for status and cancellation.

Why: ~216,000 Dagster runs and Fargate tasks per day at the benchmark profile, a verified cross-tenant role-override path, and user-facing latency coupled to orchestrator health.

Consequences: steady-lane admission is sized by Little's law (≈33 concurrent cycles at 500 accounts; initial cap 60 total, 6 per tenant, 1 per account); launcher and sync-api are new security-critical services; run tags remain metadata, never authorization.

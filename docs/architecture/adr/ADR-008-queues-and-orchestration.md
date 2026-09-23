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

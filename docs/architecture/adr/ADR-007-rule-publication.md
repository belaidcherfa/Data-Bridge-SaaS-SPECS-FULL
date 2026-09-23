# ADR-007 — Versioned control configuration to analytics

Status: Accepted for implementation. Date: 2026-09-23.

## Context

PostgreSQL owns rule editing while dbt owns deterministic allocation. Direct dual writes are not atomic.

## Decision

Use PostgreSQL transactional outbox to export immutable configuration snapshots to S3/Snowpipe and central Snowflake config tables. Runs pin approved config_version. A serving publication records all source/config/model/algorithm versions and advances only after checks.

## Alternatives considered

Reading live PostgreSQL during each dbt model breaks reproducibility. Embedding formulas in Dagster hides business logic.

## Consequences

Rule publishing is asynchronous with visible pending state. Replaying an old dataset uses the original version. Outbox duplicates are harmless.

## Revisit conditions

If propagation latency misses measured product targets, optimize transport without changing ownership.

## Validation obligation

Implementation tasks must link redacted live evidence before production. Documentation acceptance is not execution evidence. See [delivery methodology](../../../DELIVERY_METHODOLOGY.md).

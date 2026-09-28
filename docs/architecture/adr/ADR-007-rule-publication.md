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

## Amendment 2026-09-28

Status: ACCEPTED (owner decision record 2026-09-28). Decision: D-04. Evidence: [decision record](../../22-implementation-readiness/DECISIONS_REQUIRED.md) D-04; [audit](../../22-implementation-readiness/AUDIT_CROSS_CUTTING.md) X-17; [CTL backlog](../../22-implementation-readiness/backlog/CTL.md) G-CTL-11 and Appendix G; [DBT backlog](../../22-implementation-readiness/backlog/DBT.md) DBT-103.

What changes: the transactional outbox, immutable `config_version` and pinned runs stay; the **transport** changes. Instead of outbox → S3 → Snowpipe → Snowflake, a dedicated `config-publisher` WIF identity writes each immutable version directly into insert-only `CONFIG.*` tables:

- rows first, then one header row in `CONFIG.CONFIG_VERSION` (row count + content SHA-256 + approval, publisher run and fencing token) in the same Snowflake transaction; the header is the commit marker and dbt reads only header-complete versions;
- one publisher per `(tenant, config_kind)` holds a PostgreSQL fenced lease; an existing header with the same hash is a no-op, a different hash raises `CONFIG_VERSION_CONFLICT`;
- an archival copy `config/{env}/{tenant}/{kind}/{version}.json.gz` is written to S3 for recovery;
- builds pin the version per tenant through `BUILD_CONFIG_PIN` ([ADR-014](ADR-014-analytical-revisions.md));
- draft simulations write to `SIMULATION_INPUT`, never to published config tables;
- user-name predicates are compiled to pseudonyms before leaving PostgreSQL ([ADR-009 amendment](ADR-009-privacy-and-retention.md)).

PostgreSQL shows `PENDING_PUBLICATION → PUBLISHED | FAILED`. The same publisher path carries other small control records that analytics must pin, such as approved billing references and close records (FIN-101, FIN-010).

Why: kilobyte-sized versions gained nothing from a second acceptance protocol and Snowpipe latency; idempotency and reproducibility come from immutable keys, not from the transport. This is the "optimize transport without changing ownership" revisit condition above.

Consequences: one more narrowly privileged WIF identity (insert on `CONFIG.*` only); Snowflake does not enforce uniqueness, so duplicate identical rows after an ambiguous commit are removed by staging deduplication with content equality, and conflicting content fails the build.

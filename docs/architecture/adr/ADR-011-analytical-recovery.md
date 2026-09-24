# ADR-011 — Recover retained analytics beyond raw journal lifetime

Status: ACCEPTED design; live qualification NOT_RUN. Owner: SRE/Data platform.

## Context

The journal default90-day lifecycle is shorter than400-day canonical history. Recreating central Snowflake only from surviving raw files would lose older facts and could make closed statements irreproducible.

## Decision

Use the consistent canonical snapshot plus accepted-journal recovery contract in [operations](../../16-observability/operations.md). Snapshot all retained analytical facts/config versions and required statement evidence daily into a separately restricted recovery location. Recreate identity/row policies and reapply deletion tombstones before exposing restored data. Measure RPO/RTO through OPS-007.

## Alternatives

Retain all raw forever: higher cost and privacy burden. Rely only on Snowflake Time Travel: insufficient independent recovery horizon. Cross-region Snowflake replication: valuable optional enhancement, but account edition, residency and cost need separate approval and proof.

## Consequences

Snapshot export/restore costs and permission management are explicit. Old retained facts can be recovered without promising raw replay beyond its retention. Regional disaster guarantees remain limited to the actually qualified recovery topology.

## Revisit conditions

Contracted longer retention, regional recovery SLA, material snapshot cost or a proven replication topology changes the tradeoff.

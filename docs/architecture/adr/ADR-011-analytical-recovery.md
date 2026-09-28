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

## Amendment 2026-09-28

Status: ACCEPTED design (review finding G-OPS-06/G-OPS-07 resolution, consistent with D-05, D-10 and D-26); live qualification NOT_RUN. Evidence: [OPS backlog](../../22-implementation-readiness/backlog/OPS.md) G-OPS-06, G-OPS-07, G-OPS-08, OPS-007, OPS-104, OPS-111; [ORC backlog](../../22-implementation-readiness/backlog/ORC.md) ORC-105; [decision record](../../22-implementation-readiness/DECISIONS_REQUIRED.md) D-05, D-10, D-26; [audit](../../22-implementation-readiness/AUDIT_CROSS_CUTTING.md) §7 (blockers G-OPS-06, G-OPS-07).

What changes: the "daily consistent canonical snapshot" receives a physical design in three tiers.

- **Tier 1 (R1) — Snowflake Backups** on the ledger, serving, config and security databases: daily, 35-day expiry, **no retention lock** (a lock is irreversible and needs Business Critical; see ADR-009). Backups are zero-copy snapshots restorable with `CREATE … FROM BACKUP`, generally available since 2025-12-10, same account and region only (VERIFIED). They protect against bad DML/DROP, not against loss of the account.
- **Tier 2 (R1) — independent copy.** Incremental Parquet export of **new immutable revisions only** (write-once under [ADR-014](ADR-014-analytical-revisions.md), so each revision is exported exactly once) with `ENABLE_UNLOAD_PHYSICAL_TYPE_OPTIMIZATION=FALSE` (keeps decimal precision), into an S3 bucket in a separate AWS recovery account. A daily recovery manifest pins the publication map `AT(TIMESTAMP => T)`, per-revision row counts, `HASH_AGG` checksums and per-currency amount sums, the config versions, `tombstone_hwm` and journal high-water marks. ORC-105 pins the exported publication so garbage collection cannot delete referenced revisions.
- **Tier 3 (R2, owner decision, OPS-111)** — database replication to a second EU account (residency and cost approval required).
- Refuted: "clone into another account" — zero-copy clone is intra-account only.

Tombstones and side effects: the append-only OPS-104 tombstone log (PostgreSQL plus an S3 mirror outside restore scope) is replayed in full before recovered data is served, so restores cannot resurrect erased subjects or deleted tenants ([ADR-009 amendment](ADR-009-privacy-and-retention.md)). After a PostgreSQL restore, provider-accepted deliveries are reconciled against an out-of-band S3 dispatch journal and a global lease epoch is bumped so pre-restore fencing tokens are rejected.

Journal horizon: with D-26, FINANCIAL sources keep 400 days of journal and RAW, so the "90-day journal" gap applies only to QUERY_GRAIN sources.

Recovery recreates the D-02 identity model (tenant users, profile roles, entitlements; [ADR-005 amendment](ADR-005-analytical-authorization.md)) before reopening serving. Targets remain analytical RPO ≤ 24 h and RTO ≤ 8 h, measured by OPS-007, which moves from M9 to phase P3 (M5) so the first drill happens before the query-grain journal horizon expires.

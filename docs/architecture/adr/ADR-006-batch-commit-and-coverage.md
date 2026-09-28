# ADR-006 — Manifest acceptance and contiguous coverage

Status: Accepted for implementation. Date: 2026-09-23.

## Context

Files/events can duplicate, reorder or partially arrive; Snowpipe file history is not permanent business deduplication.

## Decision

Immutable objects plus final manifest define an attempt. A batch becomes accepted only after all listed files, checksums/schema and load receipts match. Track journaled, RAW-accepted and serving-published interval coverage independently. Commit only contiguous ranges with fenced compare-and-swap. Periodic anti-entropy re-extraction handles changes beyond ordinary overlap.

## Alternatives considered

Advancing MAX(timestamp) loses sparse windows. Renaming archives can generate reloads. S3 notifications are not commit records.

## Consequences

Staging selects accepted batches only. Retry attempts may differ physically but produce identical canonical facts. Partition snapshot selection handles deletes/corrections when the source is a complete bounded snapshot.

## Revisit conditions

New source semantics or an alternative ingestion channel must prove the same acceptance and replay contract.

## Validation obligation

Implementation tasks must link redacted live evidence before production. Documentation acceptance is not execution evidence. See [delivery methodology](../../../DELIVERY_METHODOLOGY.md).

## Amendment 2026-09-28

Status: ACCEPTED (review blocker/HIGH resolutions, consistent with D-03, D-26 and D-29). Evidence: [ING backlog](../../22-implementation-readiness/backlog/ING.md) G-ING-01…07, G-ING-10 and §3.1–§3.4; [FIN backlog](../../22-implementation-readiness/backlog/FIN.md) G-FIN-02; [INF backlog](../../22-implementation-readiness/backlog/INF.md) G-INF-07; [ORC backlog](../../22-implementation-readiness/backlog/ORC.md) G-ORC-07; [decision record](../../22-implementation-readiness/DECISIONS_REQUIRED.md) D-03, D-29; [audit](../../22-implementation-readiness/AUDIT_CROSS_CUTTING.md) X-20 and §7 (blockers G-ING-01, G-ING-02, G-FIN-02).

What changes:

1. **Completion-time extraction for query sources.** START_TIME windows with a finite overlap lose queries longer than ≈75–120 min (QUERY_HISTORY) and ≈15 h (QUERY_ATTRIBUTION_HISTORY). Both use the `END_TIME_SWEEP` watermark mode: `END_TIME >= :ws AND END_TIME < :we AND START_TIME >= DATEADD(day, -8, :ws)` (the START_TIME bound is only a pruning hint of the 7-day maximum statement timeout plus one day). Each completed query falls into exactly one window whatever its duration; coverage means "all queries completed before T". QUERY_METERING_HISTORY uses hour partitions plus a bounded (8-day) pending-refresh set. An alarm fires when an observed duration exceeds 7 days. This refines the PRD §34 overlap model.
2. **Watermark modes and pass schedules.** The registry declares a watermark mode per source (END_TIME_SWEEP, START_TIME_INTERVAL, HOUR_PARTITION, DATE_PARTITION, SNAPSHOT, PENDING_REFRESH), a FIRST and a SETTLE pass per window, checksum or re-snapshot anti-entropy, and a `retention_class` (D-26). Anti-entropy on event sources is additive only.
3. **Exact decimals in transport.** Every extractor connection sets `arrow_number_to_decimal=True` (the connector otherwise converts scaled NUMBER to float64, VERIFIED); every Arrow batch is cast to the registry-derived schema (`safe=True`), the Parquet schema never comes from the first batch, and a contract test fails on any float field not declared as a FLOAT source.
4. **Parquet load options.** File format `TYPE=PARQUET USE_LOGICAL_TYPE=TRUE USE_VECTORIZED_SCANNER=TRUE`; pipes use `MATCH_BY_COLUMN_NAME=CASE_INSENSITIVE` with `INCLUDE_METADATA` and explicit `ON_ERROR=SKIP_FILE`; Parquet field names are lower-snake from the registry and case-fold collisions are rejected; RAW technical columns are NOT NULL. This refines PRD §30 (`CASE_SENSITIVE`), which would load all-NULL rows against upper-case RAW columns.
5. **Key grammar and conditional writes.** One normative key grammar (landing, manifests, replay, probes) is produced only by the builder and parsed strictly; IAM resource ARNs enumerate literal `source=…/schema_major=…` pairs; path identity = file content identity = manifest identity = PostgreSQL attempt identity. Files are single-part `PutObject` (≤ 256 MiB) with SHA-256 checksum and `If-None-Match: *`; the bucket policy denies unconditional puts on `landing/`, `manifests/` and `replay/`; manifests live under `manifests/`; replay re-PUTs verified bytes. "Signed manifests" are replaced by a PostgreSQL-planned `batch_id` plus lease `fencing_token` carried in the manifest.
6. **Acceptance evidence from RAW.** A file is received when `COUNT(DISTINCT LOADER_FILE_ROW_NUMBER)` in RAW equals the manifest row count, which never expires while RAW is retained; COPY_HISTORY is a diagnostic only; duplicate loads are flagged and deduplicated by `(LOADER_FILENAME, LOADER_FILE_ROW_NUMBER)`. Snowpipe auto-ingest is the steady-state path; orchestrated `COPY INTO … FILES=(…)` is the replay/repair path (D-03). Single-writer acceptance assigns `accepted_seq`, which bounds each build's input snapshot ([ADR-014](ADR-014-analytical-revisions.md)).
7. **Suspect guard for complete-partition snapshots.** A new complete partition with 0 rows or a primary-measure drop > 50 % against the selected revision is accepted as SUSPECT and becomes selectable only after a confirming batch ≥ 6 h later with a fresh AVAILABLE probe; partitions within 7 days of the source retention cutoff are never re-snapshotted.
8. **Steady state first (D-29).** Steady-state cycles start at SYNCING from the enrollment boundary and the historical backfill runs in a fair background lane over `[start, enrollment_boundary)`; coverage merges contiguously, so there is no separate "catch-up T0 → now" phase (refines PRD §40).

Validation obligation: live probes of a query longer than 90 minutes (ING-101), NUMBER(38,9) extremes and TIMESTAMP_LTZ round trips (ING-006), the key-crafting attack (INF-003) and a suspect-empty fixture (ING-008).

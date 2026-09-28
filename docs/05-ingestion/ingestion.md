# Source contracts and durable immutable ingestion

Canonical domain contract. Owner: Data engineer. Implementation state: NOT_STARTED.


## Source registry contract

One adapter per source family, never per customer. Registry entry contains fully qualified source, documented fields/types, required/optional columns, grain/key, timestamp semantics, source-specific latency/retention, privilege mapping, edition/capability, extraction mode, overlap, maturation lag, cadence, chunk bounds, privacy, schema version, documentation URL and live-verification record. Unknown columns are not automatically collected. A required-key removal quarantines only the affected source. (amended 2026-09-28, G-ING-01, G-ING-13, D-26) The registry (JSON Schema in [ING backlog](../22-implementation-readiness/backlog/ING.md) §3) also declares a `watermark_mode` (END_TIME_SWEEP, START_TIME_INTERVAL, HOUR_PARTITION, DATE_PARTITION, SNAPSHOT, PENDING_REFRESH), a FIRST and a SETTLE pass delay per window, the anti-entropy method (checksum or re-snapshot), the suspect guard, the backfill chunk and a `retention_class` (FINANCIAL or QUERY_GRAIN); schema fingerprints are tracked per (account, source) because behavior-change bundles differ by account.

The [source catalog](source-catalog.md) defines baseline sources and explicit activation gates. Documentation is not proof of availability in a customer account. Source adapters implement `probe`, `plan_windows`, `build_query`, `iter_batches`, `normalize_transport`, `validate_schema`; financial transformations are forbidden here.

Use UTC, explicit projections and bound values. Account Usage scans have half-open predicates on the registry's actual watermark column. (amended 2026-09-28, G-ING-01) QUERY_HISTORY and QUERY_ATTRIBUTION_HISTORY are extracted by **completion time** (`END_TIME >= :ws AND END_TIME < :we AND START_TIME >= DATEADD(day,-8,:ws)`), because START_TIME windows with a finite overlap lose queries longer than ≈75–120 min (QUERY_HISTORY) or ≈15 h (QUERY_ATTRIBUTION_HISTORY); coverage means "all queries completed before T" ([ADR-006 amendment](../architecture/adr/ADR-006-batch-commit-and-coverage.md)). For mutable daily billing, retrieve complete scoped day partitions and select the newest accepted partition snapshot; row-only MERGE cannot remove corrected/deleted rows. For query histories use tenant/account/query keys, with deterministic latest accepted source copy. Adaptive query metering is query × metering hour, not query-only.

## Transport and Arrow

Use connector batch APIs such as `fetch_arrow_batches`, not fetchall/pandas for history. (amended 2026-09-28, G-ING-02, G-FIN-02) Every extractor connection sets `arrow_number_to_decimal=True` — by default the Python connector converts scaled NUMBER to float64 (VERIFIED in connector source) — and uses `force_microsecond_precision=True` for timestamp scales ≤ 6; every batch is cast to the registry-derived Arrow schema (`safe=True`), an empty result still yields that schema, and a contract test fails on any float field the registry does not declare as a FLOAT source. The connector and Arrow buffers still consume memory: bound query windows, prefetch, row size and worker concurrency; bisect windows after controlled size/time limits. Initial worker goal: peak RSS below 70% of assigned memory under a 10-million-row synthetic stream. A single oversized record must be quarantined or safely omitted under a documented source policy, not OOM the account queue. [Python connector batch APIs](https://docs.snowflake.com/en/developer-guide/python-connector/python-connector-api).

Transport map: Snowflake NUMBER→Arrow decimal128 with original precision/scale; monetary calculations never float; BOOLEAN→bool; DATE→date32; strings→UTF-8; LTZ/TZ→UTC timestamp at preserved source precision; NTZ uses explicit source semantics, never a guessed local timezone. Nested source fields use individually approved structured/JSON columns, not an all-purpose record payload. Schema fingerprint includes case, order-independent field identity, type and nullability.

Parquet uses ZSTD, target approximately 128 MiB compressed, flexible 100–250 MB operational band for large batches, hard cap 256 MiB so every file is a single-part upload (amended 2026-09-28, G-ING-05); close at window end even if small. Field names are lower-snake from the registry and case-fold collisions are rejected (G-ING-03). Write bounded row groups and inspect actual compressed bytes between groups. This is a target, not a hard guarantee for one large row group. [Snowflake loading guidance](https://docs.snowflake.com/en/user-guide/data-load-considerations-prepare).

## Immutable objects and manifest commit

Prefer source-first physical prefixes so one source pipe serves many tenants:
`landing/source=<registry_id>/schema_major=<n>/tenant_id=<uuid>/organization_id=<uuid>/account_id=<uuid-or-org>/extraction_date=<UTC>/batch_id=<uuid>/part-000.parquet`.

This deliberately refines the PRD's illustrative prefix order without changing physical tenant isolation. Every object is immutable; attempt retries use new batch IDs unless checking an identical existing checksum. (amended 2026-09-28, G-ING-04, G-ING-05, G-INF-07) Keys follow the normative grammar of [ING backlog](../22-implementation-readiness/backlog/ING.md) §3.2, produced only by the builder and parsed strictly (exactly one `tenant_id=` segment at a fixed depth); IAM resource ARNs enumerate literal `source=…/schema_major=…` pairs so a wildcard cannot absorb another tenant's prefix. Objects are written with single-part `PutObject`, `ChecksumAlgorithm=SHA256` and `If-None-Match: *`; on 412 an equal stored checksum is idempotent success and a different one is `KEY_CONFLICT`; the bucket policy denies unconditional puts on `landing/`, `manifests/` and `replay/` and denies deletes to connector roles. ETag is not a universal checksum; store SHA-256 and size per file. Publish manifest last, under the separate `manifests/` prefix that no pipe watches, after upload completion and read/metadata validation. No rename to archive: lifecycle tier and batch state represent archival. Quarantine is a state plus protected diagnostic reference; it must not accidentally create duplicate load events.

Manifest required fields:

```json
{
  "manifest_version": 1,
  "batch_id": "attempt-uuid",
  "logical_window_id": "stable-contract-window-hash",
  "tenant_id": "uuid",
  "organization_id": "uuid",
  "account_id": "uuid-or-null-for-org-scope",
  "source": "QUERY_HISTORY",
  "window_start": "2026-09-01T00:00:00Z",
  "window_end": "2026-09-02T00:00:00Z",
  "source_schema_version": 1,
  "transport_schema_version": 1,
  "schema_fingerprint": "sha256",
  "privacy_policy_version": 1,
  "extracted_at": "UTC timestamp",
  "extractor_version": "image-digest",
  "query_ids": ["source-query-id"],
  "row_count": 200,
  "files": [{"key": "immutable-key", "rows": 200, "bytes": 12000, "sha256": "digest"}],
  "empty_window": false,
  "complete_partition": true
}
```

The example values are synthetic. An empty successful window has zero files/rows and an accepted manifest; an inaccessible source has no successful empty manifest. (amended 2026-09-28, G-ING-04, G-ING-09) Manifest v1 additionally carries `connection_id`, `connection_revision`, `connection_epoch`, `lease_id`, `fencing_token`, `attempt_no`, `watermark_mode`, `pass_kind` (FIRST/SETTLE/ANTI_ENTROPY/BACKFILL/REPLAY), `generation`, covered partitions, observed watermarks and per-file `sha256_hex`, `s3_version_id` and Parquet fingerprint (`additionalProperties: false`). "Signing" is replaced by a PostgreSQL-planned `batch_id` issued with the lease `fencing_token`: acceptance rejects unplanned batch IDs and stale tokens, and requires path identity = file content identity (single-valued tenant/organization/account per file) = manifest identity = attempt identity. Do not trust tenant_id solely because a file contains it.

## Snowpipe and acceptance

Use storage integration with external ID and KMS permissions, source/schema-specific external stages and pipes. S3 events fan out through supported SNS/SQS arrangements; Bridge receipt consumers use their own queue, not Snowflake's managed queue. [Snowpipe S3 setup](https://docs.snowflake.com/en/user-guide/data-load-snowpipe-auto-s3). Duplicate/out-of-order events are expected. [S3 event semantics](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html).

Typed RAW columns include identity, source batch/window/extracted_at, schema version, row hash and source fields. Add loader metadata columns up front. Use `MATCH_BY_COLUMN_NAME=CASE_INSENSITIVE` with `INCLUDE_METADATA` mapping file name, row number and start-scan time; do not combine MATCH_BY_COLUMN_NAME with a SELECT load transform. (amended 2026-09-28, G-ING-03) This refines PRD §30 (`CASE_SENSITIVE`), which would load all-NULL rows against upper-case RAW columns. File format `BRIDGE_PARQUET_V1` sets `USE_LOGICAL_TYPE=TRUE` (otherwise Parquet timestamps load as far-future values) and `USE_VECTORIZED_SCANNER=TRUE`; pipes set `ON_ERROR=SKIP_FILE` explicitly; RAW technical columns are NOT NULL so a mismatched file is skipped instead of loading NULL rows. Disable unreviewed automatic schema evolution. Failed/partially loaded files cannot make a batch accepted. (amended 2026-09-28, D-03) Snowpipe auto-ingest is the steady-state path; orchestrated `COPY INTO … FILES=(…)` over a WIF session is the replay/repair path. Snowpipe bills a flat 0.0037 credits per GB with no per-file charge since 2025-12-08 (VERIFIED), so small files are a bookkeeping concern, never a reason for cross-tenant coalescing. [COPY contract](https://docs.snowflake.com/en/sql-reference/sql/copy-into-table).

File arrival may precede manifest. Accepted-batch registry is materialized in Snowflake only after every declared file has matching load receipt, row count, schema and identity checks; staging joins that registry. Product transformations never scan unaccepted RAW indiscriminately. (amended 2026-09-28, G-ING-06) The receipt is derived from RAW itself — `COUNT(DISTINCT LOADER_FILE_ROW_NUMBER)` per file equals the manifest row count — so it never expires while RAW is retained; ACCOUNT_USAGE.COPY_HISTORY (up to 2 h, sometimes 2 days of latency) is not on the acceptance path and INFORMATION_SCHEMA.COPY_HISTORY is used only for diagnostics of files missing after 15 min; `COUNT(*) > COUNT(DISTINCT row number)` flags a duplicate load, deduplicated by `(LOADER_FILENAME, LOADER_FILE_ROW_NUMBER)`. The acceptance decision table A1–A9 is normative ([ING backlog](../22-implementation-readiness/backlog/ING.md) §3.3). Single-writer acceptance assigns `accepted_seq`, which bounds each build's input ([ADR-014](../architecture/adr/ADR-014-analytical-revisions.md)). Load time is ingestion metadata, not event order.

## State and checkpoints

PLANNED → LEASED → EXTRACTING → JOURNALED → RAW_ACCEPTED → TRANSFORMED → PUBLISHED. Side states RETRYABLE_FAILED, QUARANTINED, CANCELLED. Track interval sets for journaled, raw accepted and serving published; checkpoint is the maximum contiguous covered boundary from the requested start. A hole blocks advancement past it, even when later data is loaded. PostgreSQL owns operational interval state; Snowflake acceptance/publication metadata is reconciled through idempotent outbox/ack steps, not an imaginary distributed transaction.

Overlap handles routine lateness; anti-entropy rescans older mutable partitions and billing open months. (amended 2026-09-28, G-ING-01, G-ING-07) Overlap re-reads are replaced by the registry pass schedule (FIRST and SETTLE per window) plus anti-entropy; anti-entropy on event sources (QUERY_HISTORY, QUERY_ATTRIBUTION_HISTORY) is additive only; a complete-partition snapshot with 0 rows or a primary-measure drop > 50 % is accepted as SUSPECT and selected only after a confirming batch ≥ 6 h later with a fresh AVAILABLE probe; partitions within 7 days of the source retention cutoff are never re-snapshotted. Registry defaults are operational starting points, not guaranteed source SLAs.

(amended 2026-09-28, D-07, G-ING-08, G-ING-09) Extraction executes as one **account-cycle** per connection per hour (ING-106): one WIF session and one customer warehouse resume run all due windows in priority order (billing, metering, serverless, transfer, storage, then QUERY_ATTRIBUTION_HISTORY and QUERY_HISTORY), classify failures per source, re-check the fence and connection epoch between sources and before each manifest, respect a 45-min (steady) or 2-h (backfill chunk) deadline and suspend `BRIDGE_FINOPS_WH` at the end. The extractor holds no PostgreSQL or Dagster credentials; it reports through the internal `sync-api` authenticated by its AWS role (presigned `sts:GetCallerIdentity`). Queries run with `ABORT_DETACHED_QUERY=TRUE`, bounded statement timeouts and a persisted query ID for cancellation.

One-year backfill clamps each source to actual retention and feature availability, records unsupported intervals, prioritizes finance before high-volume queries, and reserves steady-state capacity. (amended 2026-09-28, D-29, G-ING-10) Steady-state cycles start as soon as capabilities are validated; the historical backfill covers `[requested start, enrollment boundary)` in a fair background lane (within each source, the days closest to the retention cutoff first, then newest to oldest), coverage merges contiguously, and there is **no separate catch-up phase** — this refines PRD §40 while keeping its intent (no gap between history and now). (amended 2026-09-28, D-11) Query-level detail, including sanitized text, is extracted for the full 365-day window; `hot_days` is plan-configurable and a shorter setting projects only the trailing workload comment for older windows. Snapshot-only objects have history only after first capture. (amended 2026-09-28, D-24) The INFORMATION_SCHEMA hot path is deferred to R2 (ING-112); R1 shows "source current through" and "published at" timestamps.

Replay validates retained manifests, selects original privacy/config/schema versions and recreates RAW under a new replay generation when necessary; new object keys explicitly reference originals so finite Snowpipe load history is irrelevant to business deduplication; replay re-PUTs verified bytes rather than CopyObject. Publish a new serving version only after checks. No customer re-query is needed within retained journal coverage; expired/deep-archive coverage is disclosed with restoration time/cost or a separately authorized re-extraction. (amended 2026-09-28, D-26) Journal and RAW retention follow the registry `retention_class`: FINANCIAL sources (billing, metering, storage, serverless, transfer, snapshots) 400 days, QUERY_GRAIN sources 90 days; query facts older than 90 days are rebuilt by re-extraction within Account Usage's 365 days ([ADR-009 amendment](../architecture/adr/ADR-009-privacy-and-retention.md)).


## Implementation sequence

(amended 2026-09-28) The dependency and gate columns below are the original index. Execution follows the revised graph ([revised-task-graph.json](../22-implementation-readiness/revised-task-graph.json), [revised critical path](../22-implementation-readiness/REVISED_CRITICAL_PATH.md)) and phases P0–P6 of the [release plan](../22-implementation-readiness/RELEASE_PLAN.md); new tasks, revised steps, dependencies and task acceptance are in [backlog/ING.md](../22-implementation-readiness/backlog/ING.md).

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [ING-001](../tasks/ING/ING-001.md) | Create executable source contracts and registry validation | CON-005, FND-004 | M3 |
| [ING-002](../tasks/ING/ING-002.md) | Implement UTC window planning, overlap and source horizons | ING-001, CTL-004 | M3 |
| [ING-003](../tasks/ING/ING-003.md) | Build bounded Arrow extraction with WIF cancellation | ING-002, CON-002, SEC-007 | M3 |
| [ING-004](../tasks/ING/ING-004.md) | Implement typed Parquet schema and size rotation | ING-003 | M3 |
| [ING-005](../tasks/ING/ING-005.md) | Commit S3 batches and validated manifests | ING-004, INF-003 | M3 |
| [ING-006](../tasks/ING/ING-006.md) | Provision typed RAW tables, stages and Snowpipe | ING-005, INF-008 | M3 |
| [ING-007](../tasks/ING/ING-007.md) | Build file receipts and complete-batch acceptance | ING-006, CTL-004 | M3 |
| [ING-008](../tasks/ING/ING-008.md) | Advance fenced checkpoints and deterministic source revisions | ING-007, ING-002 | M3 |
| [ING-009](../tasks/ING/ING-009.md) | Handle schema drift and source BCR changes | ING-008 | M3 |
| [ING-010](../tasks/ING/ING-010.md) | Plan historical backfills and catch-up with fair admission (amended 2026-09-28: steady-first backfill, no catch-up phase, D-29) | ING-009, CON-006 | M3 |
| [ING-011](../tasks/ING/ING-011.md) | Implement journal replay and anti-entropy repair | ING-010 | M3 |
| [ING-012](../tasks/ING/ING-012.md) | Add bounded hot history and truthful Data Health UX (amended 2026-09-28: hot history moved to R2 ING-112, D-24) | ING-011, UX-001 | M3 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

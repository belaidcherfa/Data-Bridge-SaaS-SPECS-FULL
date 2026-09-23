# Source contracts and durable immutable ingestion

Canonical domain contract. Owner: Data engineer. Implementation state: NOT_STARTED.


## Source registry contract

One adapter per source family, never per customer. Registry entry contains fully qualified source, documented fields/types, required/optional columns, grain/key, timestamp semantics, source-specific latency/retention, privilege mapping, edition/capability, extraction mode, overlap, maturation lag, cadence, chunk bounds, privacy, schema version, documentation URL and live-verification record. Unknown columns are not automatically collected. A required-key removal quarantines only the affected source.

The [source catalog](source-catalog.md) defines baseline sources and explicit activation gates. Documentation is not proof of availability in a customer account. Source adapters implement `probe`, `plan_windows`, `build_query`, `iter_batches`, `normalize_transport`, `validate_schema`; financial transformations are forbidden here.

Use UTC, explicit projections and bound values. Account Usage scans have half-open predicates on the registry's actual watermark column. For mutable daily billing, retrieve complete scoped day partitions and select the newest accepted partition snapshot; row-only MERGE cannot remove corrected/deleted rows. For query histories use tenant/account/query keys, with deterministic latest accepted source copy. Adaptive query metering is query × metering hour, not query-only.

## Transport and Arrow

Use connector batch APIs such as `fetch_arrow_batches`, not fetchall/pandas for history. The connector and Arrow buffers still consume memory: bound query windows, prefetch, row size and worker concurrency; bisect windows after controlled size/time limits. Initial worker goal: peak RSS below 70% of assigned memory under a 10-million-row synthetic stream. A single oversized record must be quarantined or safely omitted under a documented source policy, not OOM the account queue. [Python connector batch APIs](https://docs.snowflake.com/en/developer-guide/python-connector/python-connector-api).

Transport map: Snowflake NUMBER→Arrow decimal128 with original precision/scale; monetary calculations never float; BOOLEAN→bool; DATE→date32; strings→UTF-8; LTZ/TZ→UTC timestamp at preserved source precision; NTZ uses explicit source semantics, never a guessed local timezone. Nested source fields use individually approved structured/JSON columns, not an all-purpose record payload. Schema fingerprint includes case, order-independent field identity, type and nullability.

Parquet uses ZSTD, target approximately 128 MiB compressed, flexible 100–250 MB operational band for large batches; close at window end even if small. Write bounded row groups and inspect actual compressed bytes between groups. This is a target, not a hard guarantee for one large row group. [Snowflake loading guidance](https://docs.snowflake.com/en/user-guide/data-load-considerations-prepare).

## Immutable objects and manifest commit

Prefer source-first physical prefixes so one source pipe serves many tenants:
`landing/source=<registry_id>/schema_major=<n>/tenant_id=<uuid>/organization_id=<uuid>/account_id=<uuid-or-org>/extraction_date=<UTC>/batch_id=<uuid>/part-000.parquet`.

This deliberately refines the PRD's illustrative prefix order without changing physical tenant isolation. Every object is immutable; attempt retries use new batch IDs unless checking an identical existing checksum. Multipart upload aborts cleanly; do not overwrite accepted keys. ETag is not a universal checksum; store SHA-256 and size per file. Publish manifest last after upload completion and read/metadata validation. No rename to archive: lifecycle tier and batch state represent archival. Quarantine is a state plus protected diagnostic reference; it must not accidentally create duplicate load events.

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

The example values are synthetic. An empty successful window has zero files/rows and an accepted manifest; an inaccessible source has no successful empty manifest. Sign/authorize manifest publication using the registered task identity and verify row tenant/account values agree with the authorized prefix. Do not trust tenant_id solely because a file contains it.

## Snowpipe and acceptance

Use storage integration with external ID and KMS permissions, source/schema-specific external stages and pipes. S3 events fan out through supported SNS/SQS arrangements; Bridge receipt consumers use their own queue, not Snowflake's managed queue. [Snowpipe S3 setup](https://docs.snowflake.com/en/user-guide/data-load-snowpipe-auto-s3). Duplicate/out-of-order events are expected. [S3 event semantics](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html).

Typed RAW columns include identity, source batch/window/extracted_at, schema version, row hash and source fields. Add loader metadata columns up front. Use `MATCH_BY_COLUMN_NAME=CASE_INSENSITIVE` with `INCLUDE_METADATA` mapping file name, row number and start-scan time; do not combine MATCH_BY_COLUMN_NAME with a SELECT load transform. Disable unreviewed automatic schema evolution. Failed/partially loaded files cannot make a batch accepted. [COPY contract](https://docs.snowflake.com/en/sql-reference/sql/copy-into-table).

File arrival may precede manifest. Accepted-batch registry is materialized in Snowflake only after every declared file has matching load receipt, row count, schema and identity checks; staging joins that registry. Product transformations never scan unaccepted RAW indiscriminately. Persist load receipts before Snowflake's history windows expire. Load time is ingestion metadata, not event order.

## State and checkpoints

PLANNED → LEASED → EXTRACTING → JOURNALED → RAW_ACCEPTED → TRANSFORMED → PUBLISHED. Side states RETRYABLE_FAILED, QUARANTINED, CANCELLED. Track interval sets for journaled, raw accepted and serving published; checkpoint is the maximum contiguous covered boundary from the requested start. A hole blocks advancement past it, even when later data is loaded. PostgreSQL owns operational interval state; Snowflake acceptance/publication metadata is reconciled through idempotent outbox/ack steps, not an imaginary distributed transaction.

Overlap handles routine lateness; anti-entropy rescans older mutable partitions and billing open months. Registry defaults are operational starting points, not guaranteed source SLAs. One-year backfill clamps each source to actual retention and feature availability, records unsupported intervals, prioritizes finance before high-volume queries, and reserves steady-state capacity. Snapshot-only objects have history only after first capture.

Replay validates retained manifests, selects original privacy/config/schema versions and recreates RAW under a new replay generation when necessary; new object keys explicitly reference originals so finite Snowpipe load history is irrelevant to business deduplication. Publish a new serving version only after checks. No customer re-query is needed within retained journal coverage; expired/deep-archive coverage is disclosed with restoration time/cost or a separately authorized re-extraction.


## Implementation sequence

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
| [ING-010](../tasks/ING/ING-010.md) | Plan historical backfills and catch-up with fair admission | ING-009, CON-006 | M3 |
| [ING-011](../tasks/ING/ING-011.md) | Implement journal replay and anti-entropy repair | ING-010 | M3 |
| [ING-012](../tasks/ING/ING-012.md) | Add bounded hot history and truthful Data Health UX | ING-011 | M3 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

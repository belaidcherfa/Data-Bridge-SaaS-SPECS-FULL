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

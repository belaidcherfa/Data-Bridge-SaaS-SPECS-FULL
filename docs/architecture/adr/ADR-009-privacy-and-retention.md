# ADR-009 — Sanitize before durable transport

Status: Accepted for implementation. Date: 2026-09-23.

## Context

SQL comments, tags and errors may contain secrets or personal data. Replay retention can conflict with erasure.

## Decision

Default SANITIZED; parse SQL and remove literals/comments except allowlisted structured workload metadata. On sanitizer failure drop SQL and flag METADATA_ONLY. FULL requires explicit tenant authorization and stricter access/retention. Apply one privacy policy to Parquet, logs, reports, quarantine and replay.

## Alternatives considered

Redacting only UI leaves central raw data exposed. Regex alone is insufficient for SQL sanitization.

## Consequences

Keep object/query identifiers only where permitted; treat usernames and tags as sensitive. Default S3 replay 90 days, RAW 90 days, canonical 400 days, reports 30 days, audit 365 days; contract/legal policy may supersede. No irreversible Object Lock compliance mode by default; evaluate deletion obligations first.

## Revisit conditions

Customer retention/residency/legal requirements change; assess prospective policy and deletion of historical retained copies.

## Validation obligation

Implementation tasks must link redacted live evidence before production. Documentation acceptance is not execution evidence. See [delivery methodology](../../../DELIVERY_METHODOLOGY.md).

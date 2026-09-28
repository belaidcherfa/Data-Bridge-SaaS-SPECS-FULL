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

## Amendment 2026-09-28

Status: ACCEPTED (owner decision record 2026-09-28; legal review of D-10 sufficiency remains required). Decisions: D-10, D-11, D-26 and the report RECORD retention class. Evidence: [decision record](../../22-implementation-readiness/DECISIONS_REQUIRED.md) D-10/D-11/D-26; [SEC backlog](../../22-implementation-readiness/backlog/SEC.md) G-SEC-14…17 and Appendix G; [OPS backlog](../../22-implementation-readiness/backlog/OPS.md) G-OPS-07, G-OPS-09, G-OPS-10 (OPS-104 tombstone log, OPS-005 retention matrix); [ING backlog](../../22-implementation-readiness/backlog/ING.md) G-ING-13; [DBT backlog](../../22-implementation-readiness/backlog/DBT.md) G-DBT-05; [RPT backlog](../../22-implementation-readiness/backlog/RPT.md) G-RPT-05; [audit](../../22-implementation-readiness/AUDIT_CROSS_CUTTING.md) X-15, X-16, X-31; [reconciliation](../../22-implementation-readiness/RECONCILIATION.md) C-01, C-02, C-19, C-20.

What changes (the retention defaults in "Consequences" above are superseded where they conflict):

1. **Pseudonymization in the immutable journal (D-10).** `USER_NAME` and e-mail-like tag values are replaced at extraction by per-tenant HMAC-SHA256 pseudonyms (`u1_…`, `e1_…`, `t1_…`; 256-bit key per tenant, KMS envelope encryption with encryption context `tenant_id`). The identity dictionary (pseudonym → display name) lives only in PostgreSQL `privacy.identity_dictionary` under tenant RLS; it is never exported to S3 or Snowflake. The API resolves names after Snowflake returns rows, only for profiles holding `identity.resolve`. The "Bridge overhead" flag is computed from plaintext identity before pseudonymization. User-dimension rules accept only `eq`/`in` in R1 and are compiled to pseudonyms at config publication.
2. **Erasure and restore (D-10).** Subject erasure = delete the dictionary row + append a SUBJECT tombstone to the single OPS-104 tombstone log (PostgreSQL `privacy.tombstones` mirrored to a versioned S3 bucket in the security/log-archive account, outside restore scope) + bump the tenant `authz_epoch`. Every restore replays all tombstones before traffic resumes. Tenant offboarding schedules deletion of the tenant's KMS key (7–30-day waiting period, default 30). Disclosed residuals: Aurora PITR ≤ 35 days, Snowflake Time Travel plus 7-day Fail-safe, Redis TTL, already delivered artifacts; anyone holding the tenant key can test a candidate name (linkability). Privacy requests use `/v1/privacy/requests` (SUBJECT_ACCESS, SUBJECT_ERASURE, TENANT_DELETION; OPS-005).
3. **Query-level retention (D-11, owner choice).** Query-level detail is kept **365 days** (`hot_days` default 365, plan-configurable, bounded by Account Usage retention); every backfilled day carries sanitized query text within that window. Query-family × day aggregates (`fct_query_family_daily`, with mergeable t-digest/HLL sketch states, attributed credits, spill and workload identity) and execution-level facts (dbt invocations/model runs, Power BI activities, task-graph runs, dynamic-table refreshes) are kept 400 days. Consequences: ≈ 4× query-grain storage and dbt volume compared with 90 days, more sanitizer CPU and customer warehouse time during backfill.
4. **Journal and RAW retention by source class (D-26).** Registry `retention_class` FINANCIAL (billing, metering, storage, serverless, transfer and snapshot sources) keeps S3 journal and RAW **400 days** (Glacier Instant Retrieval after 30 days); QUERY_GRAIN (QUERY_HISTORY, QUERY_ATTRIBUTION_HISTORY, QUERY_METERING_HISTORY, access and session sources) keeps **90 days**. Query facts older than 90 days are rebuilt by re-extraction, which Account Usage allows up to 365 days, not by journal replay. Clocks: S3 object creation, RAW acceptance/`LOADER_START_SCAN_TIME`, canonical event date. Revisioned fact tables keep Time Travel 1 day ([ADR-014](ADR-014-analytical-revisions.md)); transient staging has no Fail-safe.
5. **Report artifacts: two retention classes.** EPHEMERAL (convenience reports, 30 days) and RECORD (issued chargeback statements, closed-period statements and artifacts explicitly filed by a FinOps Admin): default max(400 days, contract), configurable up to 7 years, S3 Object Lock in GOVERNANCE mode (reversible only through break-glass, consistent with "no irreversible compliance mode by default"). Statement templates carry no user-level personal data, so erasure never edits RECORD artifacts, and statement lines in Snowflake are retained at least as long as the RECORD artifact.
6. **Sanitizer hardening.** The metadata allowlist runs first (WRK-101 library), then the SQL body is sanitized with all comments stripped; the sanitized-text cache is keyed without comment metadata. The `sqlglot` logger is forced to CRITICAL with a filter dropping `sqlglot.*` records, because the library logs raw SQL on unsupported syntax (VERIFIED); any `Command`/unknown node is a parse failure. Whether an optional lexical tier replaces "drop SQL" on AST failure is decided in SEC-007-S02.

Why: tombstones alone cannot remove personal data from immutable Parquet, Time Travel or backups (X-15); a 90-day financial journal gives no rebuild value beyond 90 days (G-ING-13, G-DBT-05); chargeback evidence cannot expire after 30 days (X-31).

Consequences: dictionary availability becomes part of every name-bearing response path; the retention matrix in OPS-005 is the executable form of this ADR; audit retention (365 days, Object Lock GOVERNANCE) is unchanged. Validation: restore drills must prove that an erased subject and a deleted tenant are not resurrected.

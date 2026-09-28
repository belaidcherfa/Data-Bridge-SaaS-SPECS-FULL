# Architecture decision register

Accepted design decisions; runtime validation remains governed by the task and release gates. Change a decision only with new evidence and explicit consequences.

- [ADR-001 — Storage responsibilities and physical tenancy](ADR-001-storage-and-tenancy.md)
- [ADR-002 — Additive charges and non-additive attribution](ADR-002-financial-grains.md)
- [ADR-003 — Separate maturity, reconciliation and close](ADR-003-maturity-and-close.md)
- [ADR-004 — Account-specific WIF and isolated run identities](ADR-004-wif-identities.md)
- [ADR-005 — Snowflake identity-bound serving authorization](ADR-005-analytical-authorization.md)
- [ADR-006 — Manifest acceptance and contiguous coverage](ADR-006-batch-commit-and-coverage.md)
- [ADR-007 — Versioned control configuration to analytics](ADR-007-rule-publication.md)
- [ADR-008 — Generic Dagster assets and durable fair queues](ADR-008-queues-and-orchestration.md)
- [ADR-009 — Sanitize before durable transport](ADR-009-privacy-and-retention.md)
- [ADR-010 — Pinned open-source stack and evidence-driven launch](ADR-010-versions-and-release.md)
- [ADR-011 — Recover retained analytics beyond raw journal lifetime](ADR-011-analytical-recovery.md)
- [ADR-012 — Manual B2B billing for first paying customer](ADR-012-first-customer-commercial.md)

- [ADR-013 — Independent UI design prototype](ADR-013-ui-design-prototype.md)
- [ADR-014 — Analytical revisions and publication](ADR-014-analytical-revisions.md)
- [ADR-015 — Financial grain, maturity and attribution](ADR-015-financial-grain-maturity-attribution.md)
- [ADR-016 — Customer coverage, residency and reachability](ADR-016-customer-coverage-residency-reachability.md)

## Amendments of 2026-09-28

The product owner recorded decisions D-01…D-38 on 2026-09-28 ([decision record](../../22-implementation-readiness/DECISIONS_REQUIRED.md)). They are carried by an "Amendment 2026-09-28" section appended to the affected ADRs (original text kept above it; the amendment governs where they conflict) and by the three new ADRs above:

| ADR | Amended by | Summary |
|---|---|---|
| ADR-002 | D-12 | Billing-bucket identity, family-bucket supersession, attribution-only money below the bucket, `int_alloc_unit` |
| ADR-003 | D-13, D-27 | Numeric per-source FINAL horizons, `MONTH_STABLE`, maker-checker close, PROVISIONAL monitors by default |
| ADR-005 | D-02, D-22 | Tenant WIF user + per-profile role, `CURRENT_ROLE()`-only policies, secondary roles disabled, pools not keyed by epoch, separate broker service |
| ADR-006 | review blockers G-ING-01/02, D-03, D-29 | Completion-time extraction for query sources, exact decimals, Parquet logical types, key grammar and conditional writes, suspect guard, steady state first |
| ADR-007 | D-04 | Direct insert-only config publisher + S3 archive |
| ADR-008 | D-07, D-33 | Dedicated extraction launcher, account-cycle tasks, no Dagster run per cycle, long-lived analysis/render workers |
| ADR-009 | D-10, D-11, D-26 | Pseudonymized journal, PostgreSQL identity dictionary, tombstone log, per-tenant keys; 365-day query detail; 400-day financial journal; RECORD retention class |
| ADR-010 | D-21 | WIF everywhere with dbt-snowflake ≥ 1.12; transient bootstrap credential only |
| ADR-011 | G-OPS-06/07 | Snowflake Backups + incremental export of immutable revisions to a recovery account; tombstone replay |
| ADR-012 | D-17, D-30, D-36, D-37 | Platform fee + spend band (USD), PILOT instead of TRIAL, manual invoice or Stripe link, French entity |

Every ADR records context, decision, alternatives, consequences and revisit conditions. User requirements and authoritative PRD boundaries take precedence over convenience.

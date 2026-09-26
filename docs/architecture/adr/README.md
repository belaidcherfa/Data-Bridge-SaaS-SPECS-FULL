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

Every ADR records context, decision, alternatives, consequences and revisit conditions. User requirements and authoritative PRD boundaries take precedence over convenience.

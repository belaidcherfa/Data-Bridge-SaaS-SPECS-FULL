# Production readiness and release qualification

Canonical domain contract. Owner: Delivery manager / DevOps / Security. Implementation state: NOT_STARTED.


## Promotion and rollback contract

Build once, promote immutable image digests and pinned schema/dbt/config manifests through development, staging and production. GitHub Actions uses OIDC with repository/ref/environment conditions; customer data never enters CI. Required promotion checks include contract compatibility, migration rehearsal, numerical fixtures, tenant isolation, IaC plan review, image/SBOM/signature validation and evidence freshness. Production configuration is explicit, not copied from developer machines.

Use expand → deploy compatible readers/writers → migrate/backfill → verify → contract for PostgreSQL and analytical schema changes. Old and new worker generations cannot concurrently advance the same fenced lease. dbt writes candidate revisions, runs gates, then swaps the publication pointer. Reverting code must not silently roll back accepted customer mutations or closed finance. Rollback options are previous application digest, previous compatible publication, paused ingestion, or a forward data repair. Destructive migrations require a separately reviewed recovery plan and data evidence.

Production launch is gated by [readiness checklist](CHECKLIST.md). A release candidate is an immutable version plus exact artifact digests, infrastructure plan, dependency lockfiles, task/evidence matrix, accepted capability limitations, rollback owner and customer communication plan. Missing required security or numerical evidence blocks promotion. Vendor outages and unavailable optional capabilities are documented; they cannot be converted into a false PASS.

Customer-facing availability begins only after production synthetic login, organization isolation, WIF, ingestion,270-USD fixture reconciliation, report access and alarm tests succeed. These are controlled synthetic fixtures, not assertions about real customer cost. Legal/commercial readiness includes terms, privacy/retention agreement, subprocessors, support contacts, billing currency/tax handling and security questionnaire evidence reviewed by the responsible human owners. Documentation does not constitute legal advice or signed agreements.


## Implementation sequence

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [REL-001](../tasks/REL/REL-001.md) | Qualify complete CI/CD promotion and schema compatibility | INF-007, OPS-011 | M10 |
| [REL-002](../tasks/REL/REL-002.md) | Rehearse production deployment and rollback | REL-001, OPS-010 | M10 |
| [REL-003](../tasks/REL/REL-003.md) | Assemble operational, commercial and support readiness pack | REL-002, OPS-009 | M10 |
| [REL-004](../tasks/REL/REL-004.md) | Approve immutable release candidate and production gate | REL-003 | M10 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

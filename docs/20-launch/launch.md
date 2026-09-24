# Commercial activation, first release and post-launch validation

Canonical domain contract. Owner: Product / Delivery / Customer success. Implementation state: NOT_STARTED.


## Paying customer and release boundaries

A production tenant, trial entitlement, signed order and settled payment are separate states. First-customer commercial default is an approved manually invoiced B2B contract; automated subscription collection is not required by this PRD. Store plan/entitlement/subscription status and invoice/payment references in PostgreSQL, with audit and idempotency; never store card data. A future payment provider integration needs verified signed webhooks and its own task/ADR. Do not fabricate a paid state to pass a launch milestone.

State model: TRIAL → ACTIVE_PENDING_PAYMENT → ACTIVE_PAID; PAST_DUE/SUSPENDED/CANCELLED with effective date and approved grace policy. Payment evidence is recorded by an authorized finance operator, with independent review for corrections. Retry of the same external invoice/payment reference cannot activate twice. Plan quotas are enforced at admission, not by deleting historical facts. Customer analytics may remain readable under a documented grace/export policy; data retention is independent from billing status.

First release includes a stable version, changelog, artifact/evidence manifest, rollback runbook, support rota, first customer acceptance and payment evidence reference. Public docs contain templates and redacted evidence only. Rollout starts with synthetic smoke checks and the approved first customer; monitor before expanding. The release record states known capability limits and source maturity honestly.

Post-launch checks: hourly during the first working day; daily for days2–7; weekly through day30. Owners review auth errors, source/accepted coverage, ingestion lag, duplicate counts, financial deltas, alert/report delivery, support issues, cost per tenant and realized customer value. Day30 review compares observed SLOs/costs against targets, validates first complete monthly billing period if available, tests support response and chooses fixes before scale. A future date's review remains scheduled/open until evidence exists.


## Implementation sequence

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [LCH-001](../tasks/LCH/LCH-001.md) | Define plans, entitlements and manual billing workflow | REL-003, CTL-007 | M10 |
| [LCH-002](../tasks/LCH/LCH-002.md) | Verify first customer acceptance and payment evidence | ONB-005, LCH-001 | M12 |
| [LCH-003](../tasks/LCH/LCH-003.md) | Publish first production release and perform monitored rollout | LCH-002, REL-004 | M12 |
| [LCH-004](../tasks/LCH/LCH-004.md) | Execute first-week and day30 validation with improvement backlog | LCH-003 | M12 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

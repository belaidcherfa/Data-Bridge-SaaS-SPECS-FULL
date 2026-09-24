# Customer onboarding and first-value acceptance

Canonical domain contract. Owner: Customer success / Snowflake / FinOps. Implementation state: NOT_STARTED.


## Onboarding state and first value

Onboarding is a resumable control-plane workflow: Bridge organization → Snowflake organization WIF → account discovery/selection → per-account WIF → capability verification → requested/available history plan → extraction/S3/Snowpipe/dbt progress → reconciliation → ownership → allocation simulation → budget → monitors → actionable insight review. Reports and user invitations complete the first-value pack. A connection alone never marks onboarding complete.

Each step stores configuration version, actor, prerequisite evidence, started/completed times and blocked reason. No analytical totals are duplicated into PostgreSQL; status references the accepted Snowflake publication. Browser closure, worker restart or repeated submission resumes the same operation. The customer sees required versus optional grants, actual source-retained history, requested365-day target, snapshot-only limits and excluded/unpriced spend before consent to start. A standalone-account connection is supported with organization coverage explicitly limited.

Historical completion means contiguous coverage of every selected required source's available authorized range, with missing and unsupported ranges disclosed and accepted. A successful extraction counter is not proof of transformed or reconciled data. Progress separates source extraction, journal, Snowpipe, transformation and financial validation; use counts/dates, not invented percentages. Estimate completion only when throughput evidence exists.

## Customer acceptance record

Use [first-value checklist](FIRST_VALUE.md). Record tenant/org/account locators safely, selected scopes, retained history boundaries, capability exceptions, reconciliation period/currency/basis, allocation method, accountable owners, first budget/monitor/report, reviewed insight and support contacts. Customer approval of a disclosed limitation does not change an unavailable metric into a measured result or a failed reconciliation into RECONCILED.

Installation is executed by the customer's authorized Snowflake administrator with reviewed least-privilege scripts. Bridge never requests ACCOUNTADMIN as its ongoing runtime role. Offboarding pauses schedules, disables identities, exports approved records, applies retention/deletion policy and verifies access revocation. Reconnection uses the same tenant/account identity mapping and versioned capabilities; do not create duplicate historical charges.


## Implementation sequence

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [ONB-001](../tasks/ONB/ONB-001.md) | Build resumable onboarding checklist and guided progress | CON-006, ING-012, UX-002 | M5 |
| [ONB-002](../tasks/ONB/ONB-002.md) | Prepare customer and support documentation with rehearsal | ONB-001, OPS-010 | M9 |
| [ONB-003](../tasks/ONB/ONB-003.md) | Prepare authorized first-customer environment and identities | REL-004, ONB-002, LCH-001 | M11 |
| [ONB-004](../tasks/ONB/ONB-004.md) | Complete historical synchronization and customer reconciliation | ONB-003, ING-010, FIN-010 | M11 |
| [ONB-005](../tasks/ONB/ONB-005.md) | Complete first-value workshop and customer acceptance | ONB-004, ALC-008, GOV-008, INS-007, RPT-005 | M11 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

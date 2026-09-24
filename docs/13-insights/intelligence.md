# Evidence-backed insights, actions and verified savings

Canonical domain contract. Owner: Data science / FinOps / Frontend. Implementation state: NOT_STARTED.


## Intelligence contract and ownership

Python owns robust statistics, classification and optimization heuristics; dbt owns deterministic feature tables and aggregates. Dagster schedules versioned engine runs and materializes outputs through the same journal/acceptance contracts. PostgreSQL stores assignment/status/actions; analytical evidence, predictions and savings observations stay in Snowflake. No recommendation changes a customer Snowflake object. Future automation/Copilot requires a separate approved scope, permission model and ADR.

Every insight has tenant/scope/resource, type and rule version, first/last seen, baseline/current windows, metric/input publication, evidence IDs, sample count, estimated monetary impact with currency/horizon, confidence method, severity, effort, owner and recommended action. Stable detection fingerprint prevents repeat insights on replay; a new observation appends history. Required lifecycle: Detected → Reviewed → Assigned → Planned → Implemented → Verifying → Validated, with Dismissed, Accepted Risk and Not Applicable carrying reason/actor/expiry where relevant. State transitions are version checked and audited. Validation requires evidence, not merely a click.

The deep dive presents what happened, why it is suspected, when, financial impact, evidence, history, contributors, affected resources and a reversible recommended action. Label correlation and estimated impact honestly. Resource overlaps are grouped into mutually exclusive opportunity sets: rightsizing and suspension of the same idle credits cannot both inflate the opportunity total. Suppress a numerical estimate when required utilization or rates are unavailable.

## Eligibility and guardrails

Default recurring-pattern detector: at least 14 complete comparable daily observations; seasonal detector requires 28. These are initial product thresholds, configurable and versioned after backtesting, not statistical guarantees. No-usage claims require complete access evidence for the entire declared window; absence of permission or history is not proof an object is unused. Never recommend dropping a table automatically. Fail-safe retention is governed by Snowflake behavior; do not promise instant reclamation. Adaptive and standard warehouses have different supported metrics.

[Operator statistics](https://docs.snowflake.com/en/sql-reference/functions/get_query_operator_stats) are available for completed queries in the documented 14-day window and require OPERATE or MONITOR on the warehouse. Prefer read-oriented MONITOR where sufficient; verify the exact customer grant. Sanitize retrieved attributes and retain bounded evidence only. Operator percentages describe execution-time components, not credit allocation weights.

## Savings measurement

Freeze baseline version, intervention date, population, volume normalizer, rate basis, exclusion policy, horizon and overlap group before verification. Expected cost = baseline cost per normalized unit × observed post-change units, adjusted only by documented approved covariates. Realized savings = expected cost − observed comparable cost, with confidence/coverage and signed negative outcomes retained. Do not sum different currencies or overlapping actions. Financial close and causal confidence are different axes. A reconciled bill does not prove an action caused the change.

Golden fixture: baseline 100 executions costing200 USD gives2/execution. Post-change 120 executions cost180. Counterfactual240; normalized saving60, not20 from an unadjusted period difference. A second overlapping action cannot claim another60. Estimated opportunity80 remains separate from verified60. With only80% post-period coverage, status stays Verifying and the verified total excludes the incomplete result. A cost increase to260 produces−20, not zero.


## Implementation sequence

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [INS-001](../tasks/INS/INS-001.md) | Build insight registry and evidence publication | WRK-005, API-005, ORC-005 | M8 |
| [INS-002](../tasks/INS/INS-002.md) | Implement warehouse optimization detectors | INS-001, FIN-004, UX-005 | M8 |
| [INS-003](../tasks/INS/INS-003.md) | Implement query and pipeline optimization detectors | INS-001, WRK-002, WRK-004 | M8 |
| [INS-004](../tasks/INS/INS-004.md) | Implement storage and ingestion optimization detectors | INS-001, FIN-006, FIN-011, FIN-012 | M8 |
| [INS-005](../tasks/INS/INS-005.md) | Implement Cortex and container optimization detectors | INS-001, FIN-018, FIN-019, UX-007 | M8 |
| [INS-006](../tasks/INS/INS-006.md) | Implement action workflow and immutable baseline capture | INS-002, INS-003, INS-004, INS-005, CTL-004 | M8 |
| [INS-007](../tasks/INS/INS-007.md) | Measure normalized savings and finish optimization acceptance | INS-006, FIN-009 | M8 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

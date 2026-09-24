# External tags, allocation, usage groups, showback and chargeback

Canonical domain contract. Owner: FinOps / Backend / Frontend. Implementation state: NOT_STARTED.


## External semantic ownership

Tag Studio is an external classification layer; it does not modify customer Snowflake tags in release one. Supported dimensions include business_unit, team, owner, cost_center, product, project, environment, application, customer, domain, workload, SLA and criticality, plus typed tenant-defined dimensions. Native tags are evidence inputs, not automatically privileged truth. Record value, source, confidence, valid_from/to, ruleset version and override provenance.

Rules use a typed bounded expression AST over approved resource/query/session/workload metadata. No arbitrary SQL/Python/eval. Explicit priority wins; overlapping equal-priority assignments of different values are conflicts that block publication unless an explicit resolution is approved. Manual overrides are scoped, effective-dated and audited. Unmatched objects remain unclassified. Reclassification must not retroactively mutate closed statements.

Lifecycle: DRAFT → SIMULATING → REVIEWABLE → APPROVED → PUBLISHING → PUBLISHED; failures return to a recoverable state. Preview includes affected resources/charges, coverage before/after, conflicts, monetary movement, sample evidence and permission impact. A rule that changes access-relevant group membership requires authorization review before publication. PostgreSQL owns definitions/approvals; Snowflake owns applied tag/allocation facts and simulation results via immutable config versions.

## Usage group sets

A set is an independent classification book, e.g. Teams, Products, Cost Centers or Environments. One charge may appear once in each set; totals from different sets must never be summed. Within a set, assignments are mutually exclusive or explicitly weighted and conserved. Hierarchies are acyclic with effective dates; moving a child preserves old published hierarchy versions. Unknown/unassigned is an explicit leaf, not an omitted row.

## Allocation contract

Input = selected charge publication + tag/group/rule versions + effective period. Output grain = charge_id × allocation_book/group_set × target × rule_version. Fields include signed source/allocated amount, currency, weight, method, status, evidence, rounding adjustment and lineage. Methods: direct, fixed percentage, proportional, query-cost, measured usage, weighted, shared pool, residual and approved manual transfer.

Each charge is processed once per book. Rules declare exclusive scope, precedence and eligible cost components. Fixed weights must sum to one. Proportional denominator zero or missing data leaves UNALLOCATED unless an explicit fallback rule is part of the approved preview. Shared pools cannot reference themselves or form cycles. Idle policy is explicit: warehouse owner, proportional eligible consumers or platform cost center. Estimated query allocation is labelled as an allocation method, not direct observed billed cost.

Conservation per charge/book/currency:
`direct + rule_allocated + shared + unallocated = source_charge`.

Use exact decimals; allocate at internal precision. Statement rounding uses largest remainder on absolute amounts and a stable target ID tie-breaker, then reapplies sign. 1.00 split three ways becomes 0.34/0.33/0.33; -1.00 becomes -0.34/-0.33/-0.33. Manual internal transfers have equal/opposite entries and preserve total; they never alter the original Snowflake charge.

## Golden allocation fixture

Parent warehouse200 consists of query140 and idle60. Query ownership: Finance84, Marketing56. Under proportional-consumer idle, Finance receives36 idle and Marketing24, totaling120/80. Under platform-idle policy: Finance84, Marketing56, Platform60. Both total200; alternative policies are separate versions, not additive results. A second Products book also totals200, not combined400. A zero-usage shared pool stays unallocated200 unless an approved fallback is present.

## Showback and chargeback

Showback is an authorized business portal over allocations: current spend, budget/forecast, change, top workloads, new spend, risks and opportunities. It does not transfer money. Chargeback selects one book, period, currency, pricing and allocation version, requires reconciliation/approval, and creates immutable statement lines and explanation links. It is an internal cost statement, not automatically a legally compliant sales invoice. Corrections follow FIN close/restatement rules. Showback may show provisional current periods; issued chargeback must state required final/reconciled coverage or an explicitly approved exception.

## Quality and UX

Quality view reports direct/rule/shared/unallocated shares on the FIN absolute-amount coverage basis, conflicts and unowned resources. Every count/amount opens the corresponding remediation filter. Group-limited users see only authorized allocations and an allowed share of shared costs; neither hidden groups nor hidden grand totals leak through percentages. Simulation screens show data and rule versions and require rerun when either changes before approval.


## Implementation sequence

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [ALC-001](../tasks/ALC/ALC-001.md) | Create dimension registry and external tag fact model | FIN-009, WRK-001, CTL-005 | M6 |
| [ALC-002](../tasks/ALC/ALC-002.md) | Implement bounded rule evaluation and deterministic conflicts | ALC-001 | M6 |
| [ALC-003](../tasks/ALC/ALC-003.md) | Build simulation, review and ruleset publication | ALC-002, API-004 | M6 |
| [ALC-004](../tasks/ALC/ALC-004.md) | Implement usage group sets and effective hierarchies | ALC-003, CTL-003 | M6 |
| [ALC-005](../tasks/ALC/ALC-005.md) | Implement allocation methods and conservation | ALC-004, FIN-010 | M6 |
| [ALC-006](../tasks/ALC/ALC-006.md) | Build allocation studio and quality remediation | ALC-005, UX-004 | M6 |
| [ALC-007](../tasks/ALC/ALC-007.md) | Build scoped showback portal | ALC-006, UX-003 | M6 |
| [ALC-008](../tasks/ALC/ALC-008.md) | Implement chargeback statements, rounding and adjustments | ALC-007, FIN-010, API-005 | M6 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

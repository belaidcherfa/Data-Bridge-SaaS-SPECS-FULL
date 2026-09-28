# Canonical FinOps ledger, pricing and reconciliation

Canonical domain contract. Owner: FinOps / Analytics engineer. Implementation state: NOT_STARTED.


## Canonical facts and inclusion rules

There is one financial truth in central Snowflake, represented at distinct grains. (amended 2026-09-28) Grain, supersession, maturity, attribution, default allocation and rule evaluation are consolidated in [ADR-015](../architecture/adr/ADR-015-financial-grain-maturity-attribution.md); the normative column list, decision tables, per-service authority, maturity policy, control catalog, close workflow and money contract are §3.1–§3.6 of the [FIN backlog](../22-implementation-readiness/backlog/FIN.md).

| Relation | Grain / responsibility | Additive in spend? |
|---|---|---|
| `fct_service_usage` | Tenant/account/service/resource/time/native unit; authoritative operational measurement | Only when explicitly rated into an estimated charge version |
| `fct_charge` | One normalized billable bucket/entry/version with signed money and currency. (amended 2026-09-28, D-12) Identity = fine billing bucket; estimates exist only at family-bucket grain; versions are D-05 `revision_id` values, not identity | Yes, selected active version exactly once |
| `bridge_charge_attribution` | Charge→resource/workload/query/group decomposition with attribution method/evidence | No second charge; sums back to parent per attribution set |
| `fct_query_compute` | Classic query or Adaptive query-hour compute/QAS measurements | Query-specific metric; not added to warehouse parent spend |
| `fct_billing_reference` | Original organization billing snapshot/statement lines and revisions; (amended 2026-09-28, G-FIN-09) customer-supplied usage statements, invoices, reseller invoices, marketplace invoices and manual totals from the maker-checker intake FIN-101, published through the D-04 config publisher | Comparison/reference, never added to charges |
| `fct_reconciliation` | Scope/period/currency/control/reference-version outcome and differences | No |

Every independent service model reads the shared accepted staging/reference contracts it needs and emits the same charge schema; no service ledger depends on another service ledger. (amended 2026-09-28, G-FIN-18) Money comes from exactly two generic models — the authoritative billing normalizer (FIN-002) and the provisional estimator at family-bucket grain (FIN-102, one `select_rate` macro) — and per-service models (Snowpipe, tasks, clustering, search, MV, QAS, Cortex, SPCS, marketplace, …) are attribution models built only from staging; `ledger_<family>` names survive as thin filtered views over `fct_charge` (refines PRD §47/§49). Registry declares `measure_role=CHARGE|ATTRIBUTION|REFERENCE`, mutually exclusive authority windows and service inclusion. The canonical union explicitly includes CHARGE only. Named `ledger_query_compute` and `ledger_warehouse_idle` remain independent attribution models, satisfying the PRD without double counting.

## Financial schema

Mandatory: tenant_id, organization_id, scope_kind, account_id nullable only for organization scope, stable resource ID/name version, ledger_entry_id, source_key, source_revision, usage_start/end UTC, service_category/service/sub_service, resource_type, native_unit, quantity, credits, effective_credits, cost_native, cost_effective, currency, price_basis, rate_version, entry_kind, measure_role, data_status, reconciliation_status, allocation_status, source_view/batch/file, model_version, publication_id. (amended 2026-09-28, D-05, D-12, G-DBT-04, G-FIN-04) `publication_id` and `source_revision` are no longer row columns: rows carry `revision_id` and `build_id`, and publication membership is resolved through the publication map ([ADR-014](../architecture/adr/ADR-014-analytical-revisions.md)). `fct_charge` adds `bucket_key`, `family_bucket_key`, `contract_number`, `usage_type_raw`, `balance_source`, `funding_class` (CONTRACT, FREE, REBATE, ON_DEMAND, UNKNOWN), `accounting_period`, `account_connected`, `crosswalk_version`, `period_stability`, `maturity_policy_version`, `null_reason`, `estimate_source`, `complete_through` and `flags` (BILLING_MISSING, DIMS_DERIVED, RATE_CARRIED_FORWARD, UNRESOLVED_ACCOUNT). Spend is the sum of all funding classes, with the funding breakdown shown.

`credits` is source gross credit quantity where applicable; `effective_credits` is adjusted billed credit quantity when explicitly supported. Non-credit services use quantity/native_unit and leave credits null. `cost_native` preserves a source monetary amount when present. `cost_effective` is the selected contract-effective amount in the **same** currency; a separate display_cost/display_currency/fx_version expresses conversion. Do not manufacture a list price. `price_basis` is BILLED_SOURCE, CONTRACT_RATE_ESTIMATE, CUSTOMER_APPROVED_RATE or UNKNOWN. All money/quantity computation is exact decimal; missing price yields null+reason, not zero.

## Authority and reconciliation independence

When authoritative currency billing exists, normalize those buckets as final top-line charges and attach independent operational measurements/attribution. Before currency billing, estimates are explicitly provisional and replaced by the corresponding authoritative bucket version, not appended. (amended 2026-09-28, D-12, G-FIN-01) "Replaced" means **family-bucket supersession**: an accepted authoritative row deactivates the estimate for its (tenant, organization, scope, account, usage_date, service_family, currency) bucket; a mature (+72 h) daily billing snapshot deactivates all estimates for that account-day; metered credits without billing after maturity keep the estimate active, flagged `BILLING_MISSING`, and fail control C2. Example F-SUP-01: estimate 200.00 then billed capacity 160.00 + overage 50.00 → 210.00, never 410.00. Money below the bucket exists only in attribution bridges produced by the exact allocator `allocate_exact` with explicit `UNATTRIBUTED` and `PRORATION_RESIDUAL` rows; the displayed effective rate is never multiplied back. Service totals sourced from billing pass a transport/schema control, **not an independent financial reconciliation merely because they equal their own input**.

Required independent controls: operational units→account metering; detailed service quantities→service totals; account billing→organization billing scope; normalized charge ledger→customer-approved statement/invoice reference; attribution/allocation→parent charge conservation. Keep controls separate and expose which ones passed. A missing independent invoice reference cannot pass the named INVOICE reconciliation control. (amended 2026-09-28, G-FIN-09, G-FIN-10) The control catalog C1–C9 (unit→metering, metering→billing, rated metering→billed, detail→total, ledger→invoice/statement, attribution conservation, allocation conservation, estimate accuracy, closed-period drift) is normative in [FIN backlog](../22-implementation-readiness/backlog/FIN.md) §3.4: `delta = ledger − reference`; PENDING when an input is immature or absent; MATCHED within tolerance; WARNING only when every excess carries an approved classified explanation (never a tolerance escape); FAILED otherwise; controls run per currency. For capacity contracts the comparable document is the monthly **usage statement**, not the prepaid-capacity invoice; references are entered through the maker-checker intake FIN-101 (usage statement CSV where the format is stable, invoices, reseller and marketplace invoices, manual totals; PDFs are evidence only). Use the canonical reconciliation result enum; do not introduce a competing status enum. Reconciliation delta is never erased by a synthetic balancing charge. A known billed amount lacking detailed ownership remains explicit unattributed spend; it is not a reconciliation plug.

## Service authority map

| Family | Measurement / monetary authority | Critical exclusion |
|---|---|---|
| Classic warehouses | WMH compute, QAH attribution; billing effective amount | Query attribution+idle are subdivisions, not additional charges |
| Adaptive warehouses | WMH totals; QUERY_METERING_HISTORY query×hour | No classic idle formula when attributed WMH field is null; no double QAH/QMH union |
| Cloud services | METERING_DAILY_HISTORY signed adjustment and billed credits, matched billing | Do not bill raw query cloud credits as final or implement a universal per-query 10% deduction. (amended 2026-09-28, G-FIN-15, D-15) The adjustment exists only at (account, UTC day) and excludes serverless compute; billed cloud services are allocated proportionally to gross cloud-services credits |
| Storage | Billing-oriented organization storage/currency records; operational STORAGE_USAGE/TSM for explanation; (amended 2026-09-28, G-FIN-16) DATABASE_STORAGE_USAGE_HISTORY (365 days) supplies per-database weights | Byte snapshots and clone logical sizes are not extra bills; verify storage unit and month convention; DSUH does not reconcile to the bill, so an explicit unattributed residual remains |
| Snowpipe / streaming | Dedicated detail and METERING_HISTORY service authority, billing | File Snowpipe and streaming components are distinct; overlapping detail/summary not additive. (amended 2026-09-28, G-FIN-17) Snowpipe bills 0.0037 credits/GB with no per-file charge since 2025-12-08; money never comes from files or bytes |
| Serverless tasks, alerts, clustering, search, MV, QAS | Independent matching service detail/metering + billing | Warehouse tasks/dynamic tables are workload attribution, not serverless charges |
| Transfer / replication | Bytes by direction/type and billed native units; replication compute separately | Do not multiply transfer bytes by credit price or duplicate replication transfer |
| Cortex / AI | Current service-specific usage and billed buckets with effective authority rules; (amended 2026-09-28, G-FIN-06) money from the AI_SERVICES billing family only; attribution chain CORTEX_AISQL_USAGE_HISTORY (≤ 2026-01-04) → CORTEX_AI_FUNCTIONS_USAGE_HISTORY (≥ 2026-01-05) | Retired functions view cannot power new usage; agent totals and child tools may overlap |
| SPCS / native apps | Compute-pool metering and billing; app fees separately scoped; (amended 2026-09-28, G-FIN-05) marketplace consumer purchases from `SNOWFLAKE.DATA_SHARING_USAGE.MARKETPLACE_PAID_USAGE_DAILY` when not already in currency billing | App purchase fee differs from its warehouse/SPCS usage; provider revenues (`MONETIZED_USAGE_DAILY`) are not consumer costs and are blocked from CHARGE |
| Other billed services | All observed billing types including fees, rebates, support, private connectivity, backups, archive, Openflow, telemetry and future types | Unknown type remains visible UNMAPPED; no dropped spend to make coverage look complete |

## Prices, currencies and adjustments

Rate joins include effective date, organization/contract, account/region/edition, service/rating/billing type, currency and adjustment semantics. Assert one applicable rate or explain ambiguity; never fan out. (amended 2026-09-28, G-FIN-20) Zero matches yield `RATE_MISSING`, more than one distinct rate `RATE_AMBIGUOUS`; a rate may be carried forward at most 3 days (`RATE_CARRIED_FORWARD`). Approved customer rate tables support reseller/limited-access cases and remain estimates unless matched to an actual statement; (amended 2026-09-28, G-FIN-13, D-20) they are versioned and maker-checker (FIN-105) because reseller partner views carry the reseller's price, not the customer's. The historical 2.91 USD/credit value is permitted only in clearly labelled demo fixtures, never as a production default; the guard is provenance-based (`rate_source=DEMO_FIXTURE` rejected outside demo tenants), not value-based.

Never sum EUR and USD into one money KPI. Display separate totals unless a customer-approved, versioned FX dataset is configured; preserve native amounts and rate date/source. Refunds/support credits/rebates are signed entries. Internal allocation transfers net to zero and do not mutate the original charge. Taxes, contract prepayments and invoices may have a different scope from consumption: create an explicit reconciliation bridge with classified differences rather than claiming every invoice line is resource usage.

## Canonical numerical fixtures

Fixture `FIN-GOLD-01`, one USD account/day with synthetic rate 2 USD/credit:

- Warehouse compute 100 credits = 200. Query-attributed compute 70 = 140; idle 30 = 60. Parent spend remains 200.
- Cloud gross 15 credits plus adjustment -10 gives billed 5 credits = 10. Total billed credits for these two components: 105.
- Storage 12; serverless 18; Cortex 6; SPCS 8; transfer 4; app purchase 10; organization support 5; rebate -3.
- **Canonical organization spend = 270 USD.** Account-scoped amount excludes organization support/rebate unless source scope explicitly assigns them; organization drilldown includes them in a separate bucket.
- Serverless detail fixture: file Snowpipe 5 + tasks 7 + clustering 2 + search 2 + materialized views 2 = 18. Summary metering is a reference, not another 18.
- Adaptive fixture Q1 has hourly compute 0.25 and 0.75 credits → 1.00 total; dedup by query only is an error.
- Billing correction storage 12→11 makes total 269; replay returns 269. Separate EUR 20 remains EUR 20, never total 289 with USD.

Use absolute currency tolerance one minor unit per independently compared bucket (e.g. USD 0.01) unless source rounding evidence justifies a versioned rule. Also expose exact signed/absolute/relative delta; zero denominator makes percentage null. Credit tolerances follow declared source precision. Do not use a broad percentage tolerance to hide a material amount.

## State and close

PROVISIONAL = estimate or incomplete maturity; FINAL = source-mature under current policy; RECONCILED = named required controls passed for a specific version. `PENDING/MATCHED/WARNING/FAILED` describes each reconciliation; `OPEN/CLOSED/RESTATED` describes period close. A closed statement is immutable and references evidence. Corrections create a new version and explicitly restate or carry forward; they never silently replace a delivered PDF. (amended 2026-09-28, D-13, G-FIN-08, G-FIN-11, G-FIN-12, G-FIN-26) FINAL uses the numeric per-source horizons of [ADR-015](../architecture/adr/ADR-015-financial-grain-maturity-attribution.md) (currency billing +72 h; metering +24 h; query attribution hour end + statement-timeout horizon + 24 h, 72 h by default) and requires contiguous coverage; `MONTH_STABLE` (period_stability STABLE at month end + 5 days) is a separate state that gates close. Close is maker-checker (`finance.period.close.request` then `…approve` by another user), pins an enumerated freeze set and stores statement artifacts in the RECORD retention class; D-05 garbage collection and D-11 purges skip pinned revisions. Closed-period drift (control C9) opens a correction case resolved by restatement (statement v2) or carry-forward (`PRIOR_PERIOD_ADJUSTMENT` in the accounting period of the decision, usage date unchanged), both maker-checker (FIN-107; worked example F-REST-01 in [FIN backlog](../22-implementation-readiness/backlog/FIN.md) §3.5). All financial periods, closes, statements and controls are UTC. Snowflake trial accounts are excluded from reconciliation claims and close (D-35).

Coverage has separate source/account/time, financial-reference and attribution measures. For signed amounts, attribution coverage uses sum(abs(eligible charge amounts)) as denominator and the same absolute basis in assigned/unassigned numerators; show net financial totals separately. Percentiles and efficiency ratios always declare their population.


## Implementation sequence

(amended 2026-09-28) The dependency and gate columns below are the original index. Execution follows the revised graph ([revised-task-graph.json](../22-implementation-readiness/revised-task-graph.json), [revised critical path](../22-implementation-readiness/REVISED_CRITICAL_PATH.md)) and phases P0–P6 of the [release plan](../22-implementation-readiness/RELEASE_PLAN.md); new tasks, revised steps, dependencies and task acceptance are in [backlog/FIN.md](../22-implementation-readiness/backlog/FIN.md).

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [FIN-001](../tasks/FIN/FIN-001.md) | Define charge schema, service authority and exact decimal fixtures | DBT-005, ING-001 | M4 |
| [FIN-002](../tasks/FIN/FIN-002.md) | Normalize billing, rate sheets and approved pricing | FIN-001, DBT-002 | M4 |
| [FIN-003](../tasks/FIN/FIN-003.md) | Implement classic warehouse compute, query attribution and idle | FIN-002, DBT-003 | M4 |
| [FIN-004](../tasks/FIN/FIN-004.md) | Implement Adaptive query-hour compute and maturity | FIN-003 | M4 |
| [FIN-005](../tasks/FIN/FIN-005.md) | Implement adjusted cloud services and signed billing entries | FIN-002 | M4 |
| [FIN-006](../tasks/FIN/FIN-006.md) | Implement storage classes, snapshots and billed reconciliation | FIN-002, DBT-003 | M4 |
| [FIN-007](../tasks/FIN/FIN-007.md) | Validate independent serverless service inclusion and totals | FIN-011, FIN-012, FIN-013, FIN-014, FIN-015, FIN-016, FIN-017 | M4 |
| [FIN-008](../tasks/FIN/FIN-008.md) | Implement directional transfer and replication charges | FIN-002, FIN-006 | M4 |
| [FIN-009](../tasks/FIN/FIN-009.md) | Build reconciliation controls and financial health UX | FIN-004, FIN-005, FIN-006, FIN-007, FIN-008, FIN-018, FIN-019, FIN-020, FIN-021 | M4 |
| [FIN-010](../tasks/FIN/FIN-010.md) | Implement period close, corrections and financial evidence retention | FIN-009, SEC-006 | M4 |
| [FIN-011](../tasks/FIN/FIN-011.md) | Implement file snowpipe and hidden pipe attribution | FIN-002, DBT-005 | M4 |
| [FIN-012](../tasks/FIN/FIN-012.md) | Implement snowpipe streaming channel and client components | FIN-002, DBT-005 | M4 |
| [FIN-013](../tasks/FIN/FIN-013.md) | Implement serverless tasks and alerts | FIN-002, DBT-005 | M4 |
| [FIN-014](../tasks/FIN/FIN-014.md) | Implement automatic clustering | FIN-002, DBT-005 | M4 |
| [FIN-015](../tasks/FIN/FIN-015.md) | Implement search optimization | FIN-002, DBT-005 | M4 |
| [FIN-016](../tasks/FIN/FIN-016.md) | Implement materialized view maintenance | FIN-002, DBT-005 | M4 |
| [FIN-017](../tasks/FIN/FIN-017.md) | Implement query acceleration | FIN-002, DBT-005 | M4 |
| [FIN-018](../tasks/FIN/FIN-018.md) | Implement current Cortex services and non-overlapping AI attribution | FIN-002, DBT-005 | M4 |
| [FIN-019](../tasks/FIN/FIN-019.md) | Implement SPCS compute-pool and application attribution | FIN-002, DBT-005 | M4 |
| [FIN-020](../tasks/FIN/FIN-020.md) | Implement marketplace purchase and native-app cost separation | FIN-002, FIN-019 | M4 |
| [FIN-021](../tasks/FIN/FIN-021.md) | Cover new billable services, organization fees and unmapped spend | FIN-002 | M4 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

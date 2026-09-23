# Canonical FinOps ledger, pricing and reconciliation

Canonical domain contract. Owner: FinOps / Analytics engineer. Implementation state: NOT_STARTED.


## Canonical facts and inclusion rules

There is one financial truth in central Snowflake, represented at distinct grains:

| Relation | Grain / responsibility | Additive in spend? |
|---|---|---|
| `fct_service_usage` | Tenant/account/service/resource/time/native unit; authoritative operational measurement | Only when explicitly rated into an estimated charge version |
| `fct_charge` | One normalized billable bucket/entry/version with signed money and currency | Yes, selected active version exactly once |
| `bridge_charge_attribution` | Charge→resource/workload/query/group decomposition with attribution method/evidence | No second charge; sums back to parent per attribution set |
| `fct_query_compute` | Classic query or Adaptive query-hour compute/QAS measurements | Query-specific metric; not added to warehouse parent spend |
| `fct_billing_reference` | Original organization billing snapshot/statement lines and revisions | Comparison/reference, never added to charges |
| `fct_reconciliation` | Scope/period/currency/control/reference-version outcome and differences | No |

Every independent service model reads the shared accepted staging/reference contracts it needs and emits the same charge schema; no service ledger depends on another service ledger. Registry declares `measure_role=CHARGE|ATTRIBUTION|REFERENCE`, mutually exclusive authority windows and service inclusion. The canonical union explicitly includes CHARGE only. Named `ledger_query_compute` and `ledger_warehouse_idle` remain independent attribution models, satisfying the PRD without double counting.

## Financial schema

Mandatory: tenant_id, organization_id, scope_kind, account_id nullable only for organization scope, stable resource ID/name version, ledger_entry_id, source_key, source_revision, usage_start/end UTC, service_category/service/sub_service, resource_type, native_unit, quantity, credits, effective_credits, cost_native, cost_effective, currency, price_basis, rate_version, entry_kind, measure_role, data_status, reconciliation_status, allocation_status, source_view/batch/file, model_version, publication_id.

`credits` is source gross credit quantity where applicable; `effective_credits` is adjusted billed credit quantity when explicitly supported. Non-credit services use quantity/native_unit and leave credits null. `cost_native` preserves a source monetary amount when present. `cost_effective` is the selected contract-effective amount in the **same** currency; a separate display_cost/display_currency/fx_version expresses conversion. Do not manufacture a list price. `price_basis` is BILLED_SOURCE, CONTRACT_RATE_ESTIMATE, CUSTOMER_APPROVED_RATE or UNKNOWN. All money/quantity computation is exact decimal; missing price yields null+reason, not zero.

## Authority and reconciliation independence

When authoritative currency billing exists, normalize those buckets as final top-line charges and attach independent operational measurements/attribution. Before currency billing, estimates are explicitly provisional and replaced by the corresponding authoritative bucket version, not appended. Service totals sourced from billing pass a transport/schema control, **not an independent financial reconciliation merely because they equal their own input**.

Required independent controls: operational units→account metering; detailed service quantities→service totals; account billing→organization billing scope; normalized charge ledger→customer-approved statement/invoice reference; attribution/allocation→parent charge conservation. Keep controls separate and expose which ones passed. A missing independent invoice reference cannot receive INVOICE_RECONCILED status. Reconciliation delta is never erased by a synthetic balancing charge. A known billed amount lacking detailed ownership remains explicit unattributed spend; it is not a reconciliation plug.

## Service authority map

| Family | Measurement / monetary authority | Critical exclusion |
|---|---|---|
| Classic warehouses | WMH compute, QAH attribution; billing effective amount | Query attribution+idle are subdivisions, not additional charges |
| Adaptive warehouses | WMH totals; QUERY_METERING_HISTORY query×hour | No classic idle formula when attributed WMH field is null; no double QAH/QMH union |
| Cloud services | METERING_DAILY_HISTORY signed adjustment and billed credits, matched billing | Do not bill raw query cloud credits as final or implement a universal per-query 10% deduction |
| Storage | Billing-oriented organization storage/currency records; operational STORAGE_USAGE/TSM for explanation | Byte snapshots and clone logical sizes are not extra bills; verify storage unit and month convention |
| Snowpipe / streaming | Dedicated detail and METERING_HISTORY service authority, billing | File Snowpipe and streaming components are distinct; overlapping detail/summary not additive |
| Serverless tasks, alerts, clustering, search, MV, QAS | Independent matching service detail/metering + billing | Warehouse tasks/dynamic tables are workload attribution, not serverless charges |
| Transfer / replication | Bytes by direction/type and billed native units; replication compute separately | Do not multiply transfer bytes by credit price or duplicate replication transfer |
| Cortex / AI | Current service-specific usage and billed buckets with effective authority rules | Retired functions view cannot power new usage; agent totals and child tools may overlap |
| SPCS / native apps | Compute-pool metering and billing; app fees separately scoped | App purchase fee differs from its warehouse/SPCS usage; provider revenues are not consumer costs |
| Other billed services | All observed billing types including fees, rebates, support, private connectivity, backups, archive, Openflow, telemetry and future types | Unknown type remains visible UNMAPPED; no dropped spend to make coverage look complete |

## Prices, currencies and adjustments

Rate joins include effective date, organization/contract, account/region/edition, service/rating/billing type, currency and adjustment semantics. Assert one applicable rate or explain ambiguity; never fan out. Approved customer rate tables support reseller/limited-access cases and remain estimates unless matched to an actual statement. The historical 2.91 USD/credit value is permitted only in clearly labelled demo fixtures, never as a production default.

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

PROVISIONAL = estimate or incomplete maturity; FINAL = source-mature under current policy; RECONCILED = named required controls passed for a specific version. `PENDING/MATCHED/WARNING/FAILED` describes each reconciliation; `OPEN/CLOSED/RESTATED` describes period close. A closed statement is immutable and references evidence. Corrections create a new version and explicitly restate or carry forward; they never silently replace a delivered PDF.

Coverage has separate source/account/time, financial-reference and attribution measures. For signed amounts, attribution coverage uses sum(abs(eligible charge amounts)) as denominator and the same absolute basis in assigned/unassigned numerators; show net financial totals separately. Percentiles and efficiency ratios always declare their population.


## Implementation sequence

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

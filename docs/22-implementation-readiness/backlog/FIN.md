# FIN — Implementation-readiness review and production backlog

Canonical contract: [ledger.md](../../08-finops-ledger/ledger.md). Related: [ADR-002](../../architecture/adr/ADR-002-financial-grains.md), [ADR-003](../../architecture/adr/ADR-003-maturity-and-close.md), [source catalog](../../05-ingestion/source-catalog.md), [validation strategy](../../15-testing/validation-strategy.md), [allocation](../../11-allocation/allocation.md), [RB-06](../../16-observability/RUNBOOKS.md). Tasks reviewed: FIN-001 … FIN-021 (21). Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

## 1. Verdict

Not implementable as specified, although the *principles* are right (one additive charge truth, attribution separate, signed adjustments, unknown ≠ zero, three status axes). Money is under-defined at the exact points where it is computed. The authors must fix six things before any FIN SQL is written:

1. **Grain and supersession (D-12).** Row-for-row 1:1 replacement of estimates is impossible (G-FIN-01). Replace it with *family-bucket supersession*.
2. **Money below the bucket.** Define one exact allocation algorithm for money at hour, resource and query level (G-FIN-03).
3. **Float leak.** The Snowflake Python connector converts every scaled NUMBER to float64 in Arrow by default. That puts floats into the immutable journal (G-FIN-02, VERIFIED in connector source).
4. **Vendor billing semantics.** Balance source, marketplace, Cortex and adjustment semantics differ from the catalog. Several are TO VERIFY LIVE, and no task owns that verification (G-FIN-04…07, new FIN-108).
5. **Reconciliation and close.** Controls, the invoice-reference intake and the close/restatement workflow have no precise definitions or screens (G-FIN-09…12).
6. **Maturity numbers (D-13).** QAH attribution maturity must be tied to the statement timeout, not to hour end + 24 h (G-FIN-08).

Per-service tasks FIN-011…020 become small **attribution** models. The money for those services comes from one billing normalizer plus one estimator, which cuts risk and reconciliation surface (G-FIN-18). Realistic effort: **R1 ≈ 669–981 h**, **R1\* (D-20-conditional) ≈ 139–208 h** and **R2 ≈ 24–36 h**. For comparison, "2–6 h per task" gives 42–126 h for the 21 original tasks.

## 2. Findings

### G-FIN-01 · 1:1 replacement of estimates by billing buckets is impossible as D-12 is written
Severity: BLOCKER · Type: CONTRADICTION (challenges D-12 as worded in DECISIONS_REQUIRED.md and ledger.md "replaced by the corresponding authoritative bucket version")
Evidence: `DECISIONS_REQUIRED.md` D-12 — "Estimates are aggregated to exactly this key … so the authoritative bucket replaces them 1:1". The key contains `rating_type, billing_type, balance_source, is_adjustment` and `source_revision`. An estimate made from `METERING_DAILY_HISTORY × rate` cannot know in advance three things: whether the day will be billed from capacity or as overage, whether an `IS_ADJUSTMENT` row will appear, or which rating/billing type rows the billing system will emit. Example: an estimate of 100 credits × 2.00 = 200.00 is followed by two authoritative rows, capacity 80 cr = 160.00 and overage 20 cr × 2.50 = 50.00. No estimate key equals either authoritative key, so key-based replacement either leaves the estimate active (total 410.00) or needs a fuzzy match. `source_revision` in an identity key also breaks D-05, because a revision is a version of a bucket, not a new bucket.
Why it matters: this produces double counting (410 vs 210) or orphaned estimates on every day the billing split differs from the estimate's assumed dimensions. Overage days and adjustment days are exactly the days finance cares about.
Resolution: keep the D-12 *grain* for `fct_charge` (fine bucket key, §3.1). Change the replacement rule to **family-bucket supersession**:
- Every fine bucket rolls up to `family_bucket = (tenant, organization, scope_kind, account|∅, usage_date UTC, service_family, currency)`.
- Estimates are produced only at family-bucket grain.
- Before the UICD org/day snapshot is mature (+72 h), an accepted authoritative row for a family bucket deactivates the estimate for **that family bucket**. After maturity, the snapshot deactivates **all** estimates for that (account, day).
- If the account had metered credits > 0 but has no billing rows after maturity, the estimate stays active with `BILLING_MISSING` and control C2 = FAILED. Spend is never dropped.
- `source_revision` leaves the identity key and becomes `revision_id` under D-05.
Decision table: §3.1. Fixtures: F-SUP-01…03 (FIN-001).
Affects: FIN-001, FIN-002, FIN-102, all service tasks.

### G-FIN-02 · The Python connector silently turns scaled NUMBER into float64 in Arrow
Severity: BLOCKER · Type: VENDOR-FACT
Evidence: VERIFIED (github.com/snowflakedb/snowflake-connector-python `src/snowflake/connector/nanoarrow_cpp/ArrowIterator/CArrowTableIterator.cpp`, 2026-09-27): "All Snowflake fixed number with scale > 0 (expect decimal) will be converted to Arrow float64/double column" unless the connection parameter `arrow_number_to_decimal` (default `False`, `connection.py`) is set. The extractor uses `fetch_arrow_batches` (PRD §19–21, RESEARCH R23). Credits are NUMBER(38,9) and USAGE_IN_CURRENCY is decimal. In Python, `12345678.123456789` round-trips as `12345678.12345679`, and summing ten `0.1` floats gives `0.9999999999999999`.
Why it matters: floats would be written into the **immutable** Parquet journal. That violates `transformation.md` ("NUMBER/Decimal preserves source precision"), cannot be repaired by replay without re-extraction, and makes every exact-equality oracle flaky.
Resolution:
- Set `arrow_number_to_decimal=True` on every extractor connection.
- The Parquet schema uses `decimal128(38, s)` with the source scale.
- Add a contract test that fails on any `double`/`float` Arrow or Parquet field in a financial source.
- Add a dbt test `no_float_columns` over the RAW/STAGING/LEDGER information_schema.
Owner is ING-003/ING-004. FIN-001 S10 adds the ledger-side gate.
Affects: ING-003, ING-004, FIN-001, FIN-002.

### G-FIN-03 · No algorithm for money below the billing bucket; "effective rate × credits" leaves silent residuals
Severity: HIGH · Type: GAP
Evidence: `ledger.md` — "`bridge_charge_attribution` … sums back to parent per attribution set", but no method is given. `AUDIT X-18` proposes "applying the bucket's effective rate to operational quantities with an explicit rounding residual". Snowflake division scale rule: result scale = max(s1, min(s1+6, 12)), rounded (VERIFIED via search snippet of docs.snowflake.com/en/sql-reference/operators-arithmetic, 2026-09-27). So `USAGE_IN_CURRENCY (scale 2) / USAGE` returns a rate rounded to **8 dp**. Computed example: 24 hourly credit rows, bucket 1,234.57, gives Σ(credits × rate₈) = 1,234.570000233570, a residual of −2.3357e-7 with no owner.
Why it matters: Explorer hourly/resource totals disagree with the bucket, and conservation tests either fail randomly or get a tolerance that hides real defects.
Resolution: one exact allocator, `allocate_exact` (FIN-103, §3.6):
- Child money = parent_money × wᵢ / Σw, computed at scale 12. Floor each value to 1e-12, then distribute the leftover 1e-12 quanta by largest remainder, ties broken by stable child key. Σ children = parent **exactly**.
- If Σ detail quantity < bucket quantity, emit an explicit `UNATTRIBUTED` row worth parent × (Q−Σq)/Q.
- If Σ detail > Q, emit an `OVER_ATTRIBUTED` quality flag and normalise to Σq.
- The "daily effective rate" is shown only as a display attribute (money/usage) and is never multiplied back.
Affects: FIN-003…FIN-020, FIN-103, ALC-005.

### G-FIN-04 · USAGE_IN_CURRENCY_DAILY semantics are under-modelled (balance source, USAGE_TYPE, legacy nulls, month revisions)
Severity: HIGH · Type: VENDOR-FACT
Evidence:
- `source-catalog.md` projects BALANCE_SOURCE but not **USAGE_TYPE**, and does not say which balance sources count as spend.
- Search snippets of docs.snowflake.com (`billing-reconcile`, `remaining_balance_daily`, 2026-09-27) show balance sources capacity, rollover, free usage and overage, plus a "rebate" source. Overage = "usage that was paid at on-demand pricing … exhausted its capacity, rollover, and free credits", and "total consumption does not include usage whose balance_source is overage" when reconciling remaining balance. VERIFIED (snippet).
- "Until month close, data for a given day … can change to account for end-of-month adjustments/credits, contract amendments, or account transfers", latency up to 72 h. VERIFIED (snippet).
- Exact enum strings, the on-demand-account value, and whether older rows carry null RATING_TYPE/BILLING_TYPE/SERVICE_TYPE: TO VERIFY LIVE.
Why it matters:
- Treating free-usage or rebate-funded rows as $0 understates consumption value.
- Treating them as cash overstates cash cost.
- Excluding overage breaks the spend total.
- Dropping USAGE_TYPE loses the only discriminator on legacy rows.
Resolution:
- Project USAGE_TYPE.
- Carry `balance_source` raw in the fine key and add `funding_class ∈ {CONTRACT (capacity, rollover), FREE, REBATE, ON_DEMAND (overage/on-demand), UNKNOWN}`.
- **Spend = Σ all funding classes** (consumption value at billed rates), with a funding breakdown shown.
- "Capacity drawdown" = CONTRACT + FREE + REBATE (overage excluded).
- A cash-effective view is R2 (owner question Q2).
- Legacy null dimensions fall back to the USAGE_TYPE crosswalk (`dims_derived=true`).
- Month revisions follow D-13 month stability (§3.3).
- All enum values are confirmed by the tenant-zero verification task FIN-108 before crosswalk v1 is frozen.
Affects: FIN-002, FIN-021, FIN-108.

### G-FIN-05 · Marketplace: the consumer source is not in ORGANIZATION_USAGE, and double counting depends on the payment method
Severity: HIGH · Type: VENDOR-FACT
Evidence:
- `source-catalog.md` lists "[OU.MARKETPLACE_PAID_USAGE_DAILY]". Search snippets (docs.snowflake.com/en/collaboration/views/marketplace-paid-usage-daily-ds, consumer-listings-paying, marketplace-capacity-drawdown, 2026-09-27) say the consumer view lives in the **DATA_SHARING_USAGE** schema, with latency up to 48 h and 365-day retention. VERIFIED (snippet).
- Paid listings are paid "by credit card, bank transfer, and Marketplace Capacity Drawdown (MCD)", and invoices for monetized listings go to the billing email. VERIFIED (snippet).
- `MONETIZED_USAGE_DAILY` in ORGANIZATION_USAGE is the **provider** view.
- Whether MCD-funded purchases also appear in USAGE_IN_CURRENCY_DAILY is TO VERIFY LIVE.
Why it matters: an MCD purchase present in both UICD and MARKETPLACE_PAID_USAGE_DAILY is counted twice. A card-paid listing is absent from UICD, so using UICD alone misses it. Loading the provider view as cost books revenue as expense (the FIN-020 oracle "provider revenue 100 contributes 0").
Resolution: authority rule per (org, month).
- If UICD contains marketplace rows (crosswalk family `MARKETPLACE`), those are the CHARGE and MPUD is ATTRIBUTION (listing detail).
- Otherwise MPUD rows are the CHARGE with `price_basis=BILLED_SOURCE`, `billing_channel=SEPARATE_INVOICE`, excluded from the UICD-based C2/C3 and compared in C5 against a MARKETPLACE_INVOICE reference.
- `MONETIZED_USAGE_DAILY` and disbursement views are blocked from `measure_role=CHARGE` by a registry validator.
- Correct the schema location in the source contract (ING-001).
Affects: FIN-020, FIN-009, ING-001.

### G-FIN-06 · Cortex authority chain is out of date
Severity: HIGH · Type: VENDOR-FACT
Evidence:
- `source-catalog.md` — "prefer documented CORTEX_AISQL_USAGE_HISTORY".
- Search snippets (docs.snowflake.com/en/sql-reference/account-usage/cortex_ai_functions_usage_history, 2026-09-27): `CORTEX_AI_FUNCTIONS_USAGE_HISTORY` is the current canonical view. It includes all functions (including document functions), aggregates into one-hour windows and starts 2026-01-05, while CORTEX_AISQL_USAGE_HISTORY "is being superseded". VERIFIED (snippet).
- A Cortex AI Gateway preview was released 2026-09-15 (snippet).
Why it matters: an implementation that follows the catalog picks a view that is being deprecated, and it may double count the 2026-01-05 overlap with the AISQL view.
Resolution:
- Under D-12, Cortex **money** comes only from UICD/MDH `AI_SERVICES` family buckets. Every Cortex view is ATTRIBUTION.
- The attribution authority chain is effective-dated: `CORTEX_FUNCTIONS_USAGE_HISTORY` (retired; history only) → `CORTEX_AISQL_USAGE_HISTORY` (until 2026-01-04) → `CORTEX_AI_FUNCTIONS_USAGE_HISTORY` (≥ 2026-01-05).
- Agent, Search, Analyst and other feature views attach as separate attribution sets with parent/child exclusion.
- The AI Gateway is UNMAPPED until verified.
Affects: FIN-018, ING-001.

### G-FIN-07 · Adaptive warehouses are GA, not preview
Severity: MEDIUM · Type: VENDOR-FACT (contradicts AUDIT X-28 "may be preview")
Evidence: snowflake.com/en/blog/adaptive-compute-generally-available (search snippet, 2026-09-27): "Adaptive Compute reached general availability on AWS on June 16, 2026 … select Azure and Google Cloud regions on July 28, 2026". It is billed per query. `CREDITS_ATTRIBUTED_COMPUTE_QUERIES` is NULL for Adaptive warehouses, and QMH latency is about 1 h. VERIFIED (snippet).
Why it matters: Adaptive usage by the first customer is now likely, not exotic. Without FIN-004, Adaptive spend still appears in the bucket but has 0 % query attribution and "idle unknown".
Resolution:
- Keep FIN-004 as **R1\*** (D-20), but take it off the critical path: FIN-009 must not depend on it.
- CON-005 capability probe must detect Adaptive warehouses and flag D-20 automatically ("customer uses Adaptive → FIN-004 required before go-live").
- Money coverage stays R1 through the bucket.
Affects: FIN-004, FIN-009, CON-005, INS-002, UX-005.

### G-FIN-08 · D-13 horizons are missing, and "QAH FINAL at +24 h" is wrong for long queries
Severity: HIGH · Type: GAP (challenges D-13 for QAH)
Evidence:
- ADR-003 — "FINAL means source-mature under a documented policy". No numbers exist anywhere (AUDIT X-19).
- A QAH row appears only after the query **ends** plus latency (8 h in the catalog; one snippet says 6 h, TO VERIFY LIVE, no design impact).
- STATEMENT_TIMEOUT_IN_SECONDS defaults to 172,800 s = 2 days (search snippets, 2026-09-27; VERIFIED snippet).
- So the attribution of hour *h* can still change until h + 48 h + latency.
Why it matters: idle for hour *h* is labelled FINAL at h + 24 h and then silently changes when a 40-hour query lands. Monitors with `minimum_data_status: FINAL` fire on false idle.
Resolution: numeric per-source policy table (§3.3) with two separate horizons.
- **Charge maturity:** bucket money FINAL at usage_date end + 72 h for UICD.
- **Attribution maturity:** warehouse-hour split FINAL at hour_end + T + 24 h, where T = min(account max statement timeout, 48 h), so 72 h by default.
- Month **stability** (`period_stability=STABLE`) at month_end + N days (N = 5 default). FIN-108 re-derives N from the last observed revision date over ≥ 3 closed months (+2 days margin).
Affects: FIN-104, FIN-003, FIN-004, FIN-010, GOV-004.

### G-FIN-09 · No task covers invoice or usage-statement intake, and for capacity contracts the invoice is the wrong reference
Severity: HIGH · Type: GAP (AUDIT X-47)
Evidence:
- FIN-009 lists only "import approved statement with provenance". No task, screen (SCREEN_INDEX has none), storage path, parser or approval flow exists.
- `ledger.md` — "A missing independent invoice reference cannot pass the named INVOICE reconciliation control".
- Capacity customers are invoiced for **prepaid capacity**, not monthly consumption. The comparable document is the monthly **usage statement**. Its content changed under BCR-1584 ("monthly usage statements now contain usage for the current month only", search snippet of docs.snowflake.com/en/release-notes/bcr-bundles/un-bundled/bcr-1584, 2026-09-27, VERIFIED snippet).
Why it matters: control C5 can never pass, so no period can be RECONCILED with INVOICE required. If someone compares against a capacity invoice, a spurious FAILED results.
Resolution: new task **FIN-101**.
- Reference types: SNOWFLAKE_USAGE_STATEMENT (CSV parser in R1 if the live export format is stable, TO VERIFY), SNOWFLAKE_INVOICE (on-demand), RESELLER_INVOICE, MARKETPLACE_INVOICE and MANUAL_TOTALS.
- PDF files are evidence attachments only; R1 has no OCR.
- Lines are classified (CONSUMPTION, TAX, CAPACITY_PURCHASE, SUPPORT, CREDIT_NOTE, ADJUSTMENT, MARKETPLACE, OTHER).
- Maker-checker approval.
- Storage is in S3 with Object Lock and KMS; the version is published to `fct_billing_reference` via D-04.
Affects: FIN-009, FIN-010, new FIN-101.

### G-FIN-10 · Reconciliation controls are named but not defined, and the WARNING outcome and delta sign are unspecified
Severity: HIGH · Type: AMBIGUITY
Evidence:
- `ledger.md` lists five controls in one sentence. PRD §72 enumerates `PENDING/MATCHED/WARNING/FAILED` without semantics.
- The delta sign "ledger minus billing reference" appears only in the UI page `reconciliation.md` ("Ledger minus billing reference").
- FIN-010 uses "difference −1" for 269 vs 270 (new − old) without stating a convention.
Why it matters: engineers will invent incompatible controls. WARNING will be used as a tolerance escape hatch, and dashboards will flip signs.
Resolution: control catalog C1–C9 in §3.4, each with exact inputs, grain, tolerance and outcome mapping.
- PENDING = an input is immature or absent.
- MATCHED = |Δ| ≤ tolerance on every compared bucket.
- WARNING = excess exists but every excess bucket has an approved classified explanation with evidence, or the control is informational.
- FAILED = any unexplained excess on mature inputs.
- Declared signs: `delta = ledger − reference` and `correction_delta = new − closed`.
Affects: FIN-009, FIN-010, FIN-107, UX.

### G-FIN-11 · Close has no maker-checker, no enumerated freeze set, no immutability mechanism and no retention pins
Severity: HIGH · Type: GAP
Evidence:
- `security.md` role matrix: "FinOps Admin — Prices, tags, allocation, budgets, close/restate chargeback" (one role, no second approver).
- FIN-010 — "Close record pins charge/publication/reference/rules/rates/check versions" (no list, no storage mechanism).
- D-05 garbage-collects revisions, and D-11 purges query-level detail after 90 days. Neither excludes pinned periods.
Why it matters: one person can close and restate a financial period. Explain This Number on a 6-month-old closed statement breaks once pinned revisions or query rows are purged. A "closed" PDF in a mutable bucket is not immutable.
Resolution:
- Split capabilities: `finance.period.close.request`, `finance.period.close.approve`, `finance.period.restate.request` and `finance.period.restate.approve`. Maker ≠ checker is enforced server-side (tenant policy default ON; owner Q3).
- The freeze set is listed in §3.5.
- Statement artifacts go to S3 with Object Lock (compliance mode; retention = owner Q7) and their sha256 is stored in the close record.
- Pinned publication revisions are exempt from D-05 GC. D-11 purge keeps query-family aggregates for pinned periods, and query-level drilldown older than the hot window shows "detail expired by retention policy".
Affects: FIN-010, FIN-107, SEC-005, DBT-004, OPS.

### G-FIN-12 · Restatement vs carry-forward is undefined, including the usage period vs accounting period split
Severity: HIGH · Type: GAP
Evidence: ADR-003 — "Later corrections create a restatement or next-period adjustment". There is no rule for which one, who decides, or how a carry-forward appears in the next period's totals.
Why it matters: when an October correction to August arrives, one of three things happens: August silently changes (violating immutability), October consumption is contaminated, or the correction disappears.
Resolution: FIN-107 implements the worked example in §3.5.
- Correction detection is control C9.
- The materiality rule is a tenant policy (default: restatement **proposed** when |Δ| ≥ max(100 units, 0.5 % of period total), owner Q4).
- Carry-forward creates `entry_kind=PRIOR_PERIOD_ADJUSTMENT` in the **accounting period** of the decision, while its `usage_date` stays in the original period.
- Consumption KPIs are by usage_date. Statements are by accounting period.
Affects: FIN-010, FIN-107, ALC-008.

### G-FIN-13 · Resellers get Snowflake's price to the reseller, not the customer's price
Severity: HIGH · Type: VENDOR-FACT / RISK
Evidence: search snippets of docs.snowflake.com/en/sql-reference/billing (2026-09-27): PARTNER_USAGE_IN_CURRENCY_DAILY and PARTNER_RATE_SHEET_DAILY live in `SNOWFLAKE.BILLING`, and "only resellers and distributors can access the views in the BILLING schema". VERIFIED (snippet). `connectivity.md` — "support an explicitly imported customer billing statement/approved contract rate".
Why it matters: a reseller customer has no authoritative currency source at all. Even the reseller's PARTNER views carry the reseller's cost, not the customer's contract price. A FinOps product that shows "billed" values for such tenants misstates their spend.
Resolution: for tenants with `billing_access=NONE`, money = credits × **customer-approved rate table** (FIN-105, versioned, maker-checker), with `price_basis=CUSTOMER_APPROVED_RATE` and data_status at most FINAL (never "billed"). C5 compares against a RESELLER_INVOICE reference (FIN-101). FIN-105 is **R1**, because customers who refuse org-level access are common even without a reseller.
Affects: FIN-002, FIN-105, FIN-101, ONB.

### G-FIN-14 · Temporal proration (D-14) needs an exact algorithm and an explicit residual
Severity: MEDIUM · Type: GAP
Evidence:
- FIN-003 failure list: "long query crosses days" (one phrase).
- QAH gives one row per query (START_TIME/END_TIME/credits).
- Short queries ≤ ~100 ms are not in QAH, and QAH excludes idle (search snippet of docs.snowflake.com/en/sql-reference/account-usage/query_attribution_history, 2026-09-27; VERIFIED snippet).
Why it matters: without proration, a query from 23:30 to 01:30 with 2.0 credits puts all 2.0 on day 1. Day 1's query sum then exceeds WMH attributed credits and idle goes negative.
Resolution (FIN-003 S03–S06):
- q credits in hour h = credits × |[start,end) ∩ [h,h+1)| / (end − start). A zero-duration query goes to its start hour.
- Worked example: 0.5 (d1 23:00), 1.0 (d2 00:00), 0.5 (d2 01:00), so day 1 = 0.5 and day 2 = 1.5.
- idle_h = WMH.compute − WMH.attributed (from WMH only).
- `PRORATION_RESIDUAL_h = WMH.attributed − Σ prorated QAH` is a signed, explicit attribution row. Absent short queries end up there.
Affects: FIN-003, WRK.

### G-FIN-15 · The cloud-services adjustment has no grain rule, and per-query deduction is wrong
Severity: MEDIUM · Type: AMBIGUITY
Evidence: `ledger.md` — "Do not … implement a universal per-query 10% deduction" (no reason, no alternative). Search snippets of docs.snowflake.com/en/user-guide/cost-understanding-compute (2026-09-27): the adjustment "is calculated daily (in the UTC time zone) by multiplying daily warehouse usage by 10%" and "Serverless compute does not factor into the 10% adjustment". VERIFIED (snippet).
Counter-example:
| Query | Compute credits | Cloud-services credits |
|---|---:|---:|
| A | 1 | 0.5 |
| B | 99 | 0.5 |
- Account adjustment = −min(1.0, 10) = −1.0, so billed cloud services = **0**.
- A per-query 10 % rule bills A max(0, 0.5 − 0.1) = 0.4 and B 0, for a total of 0.4 ≠ 0.
Why it matters: phantom cloud-services cost is charged back to small-query teams.
Resolution:
- Billed cloud services are known only at (account, UTC day).
- D-15 default: billed cloud-services money is allocated proportionally to **gross** cloud-services credits across warehouse-hours, serverless service types and queries, via `allocate_exact`.
- Control `CS_ADJUSTMENT_RULE` (informational) checks adj = −min(gross CS, 0.1 × warehouse compute) to detect vendor rule changes.
- Test F-CS-02 encodes the A/B case.
Affects: FIN-005, ALC-005.

### G-FIN-16 · Storage: the historical per-database source is ignored, and daily vs monthly billing is unspecified
Severity: MEDIUM · Type: GAP
Evidence:
- `source-catalog.md` presents TABLE_STORAGE_METRICS (snapshot from enrollment) as the explanation source. DATABASE_STORAGE_USAGE_HISTORY appears only as a "billing storage" candidate.
- Search snippets of docs.snowflake.com (database_storage_usage_history, 2026-09-27): DSUH gives average daily bytes per database for the **last 365 days**, but "isn't designed to reconcile with your Snowflake bill". VERIFIED (snippet).
- Storage is billed monthly at a flat rate per TB on the daily average.
- Hybrid-table **requests** have not been billed since 2026-03-01 (release note snippet, VERIFIED snippet).
Why it matters: database-level storage attribution could be backfilled for 12 months at onboarding, but it is currently declared "unknown pre-enrollment". A bytes × rate estimate without a declared TB unit (10¹² vs 2⁴⁰) and day-count convention can drift from the bill by up to 10 %.
Resolution:
- Storage money = UICD storage family buckets (daily rows; whether storage is accrued daily or posted month-end is TO VERIFY LIVE in FIN-108).
- Estimate = avg_bytes_d / TB_unit × rate_per_TB_month / days_in_month(d), with `tb_unit` a versioned rate-contract attribute (TO VERIFY).
- D-15 weights = DSUH database bytes (backfilled 365 d) + stage bytes, with an explicit UNATTRIBUTED residual.
- TSM is used only for table-level explanation from enrollment.
- Hybrid-table request charges map through FIN-021 and have a hard cutoff at 2026-03-01.
Affects: FIN-006, ING-001.

### G-FIN-17 · Snowpipe pricing changed; per-file economics are obsolete
Severity: MEDIUM · Type: VENDOR-FACT
Evidence:
- Search snippets of docs.snowflake.com/en/release-notes/2025/other/2025-12-08-snowpipe-simplified-pricing (2026-09-27): a fixed 0.0037 credits per GB replaced per-core plus per-1,000-files charges. It applied from 2025-08-01 for Business Critical/VPS and from 2025-12-08 for all accounts. VERIFIED (snippet).
- Snowpipe Streaming high-performance is 0.0037 credits per uncompressed GB, while Classic bills compute plus client (snippet).
Why it matters: the FIN-012 "two components" fixture fits Classic only. Any per-file estimate formula is wrong after the cutover. A 365-day backfill spans both pricing models.
Resolution:
- FIN-011/012 never compute money from files or bytes; money comes from the bucket and credits come from the detail views.
- Add an effective-dated `pricing_model` attribute (FILE_LEGACY, PER_GB) for explanation and insights.
- FIN-012 detects Classic vs high-performance per pipe/channel (TO VERIFY source fields).
- Cross-domain: `intelligence.md` PI02 already avoids per-file pricing.
Affects: FIN-011, FIN-012, INS-004.

### G-FIN-18 · Ten per-service "charge" models duplicate money (challenges PRD §47/§49 wording)
Severity: MEDIUM · Type: OVER-ENGINEERING
Evidence: PRD §47 — "Each Snowflake billable service gets a self-contained ledger model". FIN-011…017 each "emit canonical charge schema" with their own pricing. `ledger.md` — "Every independent service model … emits the same charge schema".
Why it matters:
- Ten pricing joins mean ten places where rate ambiguity, overage and adjustments must be handled identically. Any divergence produces a reconciliation difference that looks like a billing gap.
- Once UICD exists, the per-service charge is exactly the UICD family bucket anyway.
Resolution:
- **Money** comes from exactly two generic models: `fct_charge` authoritative (FIN-002 normalizer) and `fct_charge` provisional (FIN-102 estimator, MDH/MH × rate).
- Per-service models become **attribution models** (`bridge_<family>`), each built only from staging (PRD §49 independence preserved; a failure affects explanation, never money).
- `ledger_<family>` names survive as thin filtered views over `fct_charge` for PRD traceability.
- Estimates are always rated with the same `select_rate` macro.
Affects: FIN-007, FIN-011…FIN-020, FIN-102.

### G-FIN-19 · Numeric plumbing: Python Decimal context, JSON money format and mixed-sign statement rounding are unspecified
Severity: MEDIUM · Type: GAP
Evidence:
- `transformation.md` — "NUMBER(38,12) internally, currency minor-unit rounding only at statement/export boundaries".
- `semantic-api.md` — "Decimal money is a JSON string" (no format).
- The allocation contract's largest remainder is defined for one signed parent only.
- Python's default `decimal` context has prec = 28. Computed: `Decimal('12345678901234567890.123456789012') * Decimal('1.000000000001')` gives `12345678901246913569.02469136`, silently rounded, versus exact `…024691356902123456789012`.
- NUMBER(38,12) holds |x| < 10²⁶, so there is no realistic overflow. Snowflake multiplication scale = min(s1+s2, max(s1, s2, 12)) (VERIFIED snippet, arithmetic operators page).
Why it matters: silent rounding in Python-side analytics (forecasts, savings), `-0.00` rendered in statements, and statements whose rounded lines do not add to the rounded total.
Resolution (FIN-106):
- Money library with `Context(prec=76, rounding=ROUND_HALF_UP, traps=[InvalidOperation, DivisionByZero, Overflow])`. `quantize(Decimal('1e-12'))` is the only rounding inside the kernel, and `Inexact` is trapped in conservation code.
- JSON money = plain decimal string, no exponent, ≥ minor-unit digits, no "-0". UI arithmetic uses a decimal library, never JS `number`.
- Statement rounding = the signed largest-remainder algorithm in §3.6, with ROUND_HALF_UP for the total (consistent with Snowflake ROUND, half away from zero).
- ISO 4217 minor units come from a versioned seed.
Affects: FIN-106, FIN-010, ALC-008, API, RPT.

### G-FIN-20 · Rate selection lacks keys, carry-forward, an overage switch and a correct demo guard
Severity: MEDIUM · Type: GAP
Evidence: FIN-002 — "unique effective-rate selection" with no key list. RESEARCH R10 — "demo 2.91 is not production default".
Why it matters:
- A date+service join fans out when region, service level or contract differ.
- Today's rate is not yet published (RATE_SHEET latency 24 h), so the current-day estimate becomes null.
- After capacity is exhausted, estimates keep the capacity rate and understate cost.
- A value-based "2.91" guard would reject a genuine customer rate.
Resolution (FIN-002 S07–S10):
- Full key match: date, org, contract, account locator, region, service_level, service_type, rating_type, billing_type, is_adjustment, currency.
- 0 matches → `RATE_MISSING`; >1 distinct rate → `RATE_AMBIGUOUS`. Never fan out; a dbt row-count test runs before and after the join.
- Carry-forward ≤ 3 days, flagged `RATE_CARRIED_FORWARD`.
- R2: switch to the overage rate when REMAINING_BALANCE_DAILY shows capacity exhausted (in R1 the C8 estimate-accuracy control makes the error visible).
- The demo guard is **provenance-based** (`rate_source=DEMO_FIXTURE` rejected outside demo tenants), not value-based.
Affects: FIN-002, FIN-102, FIN-105.

### G-FIN-21 · Pricing, close and reference-intake screens are missing from the UI spec, and a route disagrees
Severity: MEDIUM · Type: GAP
Evidence:
- FIN-002 entry point `/settings/pricing`, FIN-010 `/govern/reconciliation/period` and FIN-009 `/govern/reconciliation`.
- `SCREEN_INDEX.md` has only `/reconciliation` and `/reconciliation-detail`. `settings.md` has no pricing section (grep "pricing": 0 hits).
Why it matters: the frontend has nothing to build against, and the routes conflict.
Resolution:
- UX authors three screen specs (contract-first, §3): `/settings-pricing`, `/reconciliation-close` and `/reconciliation-references`.
- FIN-009 adopts `/reconciliation`.
- Built in FIN-105 S08, FIN-010 S12 and FIN-101 S09.
Affects: FIN-002, FIN-009, FIN-010, FIN-101, FIN-105, UX.

### G-FIN-22 · Fixture ambiguities (arithmetic passes, specification is ambiguous)
Severity: LOW · Type: AMBIGUITY
Evidence: every fixture recomputed in §3.7: 27 PASS, 0 FAIL. Three ambiguities remain:
- FIN-021 says "total adds 11 to prior amount", but F-270 already contains support 5 and rebate −3. Adding 11 to 270 gives 281, which double counts.
- `FIXTURES_AND_SCOPE.md` "AI parent 10 includes child 4 and residual 6" collides numerically with F-270 Cortex = 6.
- FIN-011 file Snowpipe 5.00 and FIN-012 streaming 5.00 share a value although only the former is inside F-270.
Why it matters: implementers "fix" a correct model to match a misread oracle.
Resolution:
- The FIN-021 oracle becomes: account baseline 268.00 + support 5.00 − rebate 3.00 + novel 9.00 = **279.00** (equivalently F-270 + 9).
- Rename the AI fixture F-AI-10 (not part of F-270).
- The streaming fixture is F-STREAM-05 with combined total F-270 + 5 = 275.00.
Affects: FIN-012, FIN-018, FIN-021.

### G-FIN-23 · Dependency edges are over-serialized and some are reversed
Severity: MEDIUM · Type: RISK
Evidence:
- FIN-001 depends on DBT-005 and ING-001, but DBT-005 "Wire signed-adjustment, idle and allocation fixture families into CI" consumes FIN-001's fixtures.
- FIN-009 waits for R1\* tasks FIN-004/018/019/020.
- FIN-004 waits for FIN-003.
- FIN-008 waits for FIN-006.
- FIN-020 waits for FIN-019.
- Downstream: API-001 waits for FIN-009, ALC-001 for FIN-009, ALC-005 for FIN-010, and INS-002/UX-005 for FIN-004.
Why it matters: the FIN chain adds about 8 serial tasks to the critical path and makes Adaptive/Cortex/SPCS/Marketplace mandatory for launch.
Resolution: see per-task "Dependency changes" and the summary in §6 (reverse FIN-001→DBT-005; capability plug-ins for R1\*). Downstream:
- API-001 → FIN-001 (+FIN-102) instead of FIN-009.
- ALC-001 → FIN-001 + FIN-103.
- ALC-005 → FIN-009 (not FIN-010).
- INS-002/UX-005 → FIN-003 (FIN-004 optional).
Affects: all FIN tasks, API-001, ALC-001, ALC-005, INS-002, UX-005.

### G-FIN-24 · Vendor billing semantics have no live-verification owner
Severity: HIGH · Type: GAP
Evidence: at least 14 items in this file are TO VERIFY LIVE, including the BALANCE_SOURCE strings, the cloud-services representation in UICD, whether UICD includes SPCS/AI/storage/transfer/marketplace, the storage accrual convention, the TB unit, and the month revision lag. OPEN_VALIDATIONS and RESEARCH_REGISTER assign none of them to a task. `RELEASE_PLAN.md` §4 proposes a "tenant zero" but no FIN task uses it.
Why it matters: crosswalk v1 would be guessed, and the first customer becomes the test bed for money.
Resolution: new **FIN-108** runs on tenant zero (Bridge's own Snowflake organization) before FIN-002 SQL is frozen.
- Capture distinct `(service_type, usage_type, rating_type, billing_type, balance_source, is_adjustment)` tuples.
- Match one full month of UICD against the Snowsight usage statement.
- Measure per-source latency and month-close revision lag.
- Freeze crosswalk v1 and maturity policy v1 from the evidence.
Affects: FIN-001, FIN-002, FIN-104, FIN-108.

### G-FIN-25 · Organization-scope rows can leak through account-limited totals
Severity: MEDIUM · Type: RISK
Evidence:
- `ledger.md` — "Never expose another account through org-level residuals".
- F-270: account 268 vs org 270.
- UICD also returns **unconnected** accounts of the organization.
Why it matters: an A1-limited reader who sees "org total 270" learns about A2 and org fees through subtraction. A "coverage 268/270" percentage leaks the same information.
Resolution:
- ORGANIZATION-scope rows and rows of unconnected accounts are visible only to principals with an explicit organization-financial grant. The row access policy checks `scope_kind`.
- Coverage percentages for account-limited principals use only authorized numerators and denominators.
- Negative test in FIN-009 S13 and FIN-021 S08.
Affects: FIN-009, FIN-021, SEC-005, API.

### G-FIN-26 · Financial periods are UTC; local-time views cannot reconcile
Severity: LOW · Type: AMBIGUITY
Evidence: the cloud-services adjustment is computed "daily (in the UTC time zone)" (VERIFIED snippet). The UI supports tenant time zones (`FOUNDATIONS.md`).
Why it matters: a Paris-time "August" total differs from the invoice month, and users then raise false reconciliation tickets.
Resolution:
- Every financial period, close, statement and control is UTC and labelled "UTC".
- Local-time aggregation is allowed only for hourly operational views, labelled "not comparable to billing".
- Budgets default to the UTC month (GOV owner).
Affects: FIN-009, FIN-010, GOV.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by (task/micro-task) |
|---|---|---|
| `data/contracts/ledger/fct_charge.schema.json` + dbt contract `fct_charge.yml` | Columns/types/enums/nullability of §3.1, including the fine bucket key and the family bucket key; no FLOAT anywhere | FIN-001-S01/S02 |
| `data/contracts/ledger/supersession.md` | Decision table §3.1 (8 cases) with fixture IDs | FIN-001-S03 |
| `data/contracts/ledger/bridge_charge_attribution.schema.json` | Grain, residual kinds, exact-conservation invariant, attribution_status | FIN-001-S04 |
| `data/contracts/service-authority.json` | §3.2 per family: charge authority, estimator, attribution sets with effective_from/to, exclusions, R1/R1\*/R2 | FIN-001-S05 |
| `data/dbt/seeds/ref_service_crosswalk.csv` (versioned) | UICD `(service_type, usage_type, rating_type, billing_type, is_adjustment)` and MDH `service_type` mapped to `service_family, entry_kind, native_unit`; unknown → UNMAPPED | FIN-001-S06 (v0), FIN-108 (v1 from live evidence) |
| `data/dbt/seeds/ref_source_maturity_policy.csv` (versioned) | §3.3 numbers per source: charge horizon, attribution horizon, month stability N, anti-entropy window | FIN-104-S01 |
| `data/contracts/reconciliation/controls.yaml` | §3.4 C1–C9: inputs, grain, tolerance rule, required flag, outcome mapping, classification enum | FIN-009-S01 |
| `data/contracts/finance/period_state_machine.md` + PG DDL `finance.*` | §3.5 states, transitions, guards, freeze set, capabilities | FIN-010-S01, FIN-107-S01 |
| `packages/bridge_money` API + `data/contracts/money.schema.json` | §3.6: Decimal context, `allocate_exact`, `round_statement_lines`, JSON money string grammar, ISO-4217 minor units seed | FIN-106-S01…S04 |
| OpenAPI: `/v1/pricing/*`, `/v1/billing-references/*`, `/v1/reconciliation/*`, `/v1/periods/*`, `/v1/statements/*` | Paths, idempotency keys, If-Match versions, error codes `RATE_AMBIGUOUS`, `MAKER_CHECKER_VIOLATION`, `STALE_PREVIEW`, `REFERENCE_DUPLICATE`, `PERIOD_NOT_STABLE`, `CONTROL_BLOCKING` | FIN-105-S05, FIN-101-S06, FIN-009-S12, FIN-010-S11 |
| UX screen specs `/settings-pricing`, `/reconciliation-close`, `/reconciliation-references` | Same structure as existing `docs/21-ui-ux/pages/*.md` (states, KPIs, a11y) | UX owner, before FIN-105-S08 / FIN-010-S12 / FIN-101-S09 |
| Fixture pack `data/fixtures/finance/` | F-270 (FIN-GOLD-01), F-SUP-01…03, F-COR-01, F-CS-02, F-D14-01, F-ADP-01, F-STREAM-05, F-AI-10, F-MKT-01, F-RATE-01…03, F-REST-01; each with independently computed `expected_*.csv` | FIN-001, per-task fixture steps |
| Capability catalog additions (SEC) | `finance.pricing.import`, `finance.pricing.approve`, `finance.reference.enter`, `finance.reference.approve`, `finance.reconciliation.explain`, `finance.reconciliation.approve_explanation`, `finance.period.close.request/approve`, `finance.period.restate.request/approve`, `finance.org_scope.read` | FIN-010-S02 with SEC-005 |

### 3.1 Canonical charge grain and supersession (resolves D-12, amended)

**Fine bucket key** (identity of an active `fct_charge` row; unique among active rows of one publication):
`bucket_key = sha256(tenant_id ␟ organization_id ␟ coalesce(contract_number,'∅') ␟ scope_kind ␟ coalesce(account_id,'∅') ␟ usage_date ␟ service_type_raw ␟ coalesce(usage_type_raw,'∅') ␟ coalesce(rating_type,'∅') ␟ coalesce(billing_type,'∅') ␟ coalesce(balance_source,'∅') ␟ is_adjustment ␟ currency ␟ basis_class)`, where ␟ = U+001F, all enums upper-cased and trimmed, and `basis_class ∈ {AUTH, EST}`.

**Family bucket key** (unit of supersession and of estimate production):
`family_bucket_key = sha256(tenant_id ␟ organization_id ␟ scope_kind ␟ coalesce(account_id,'∅') ␟ usage_date ␟ service_family ␟ currency)`.

`revision_id` is **not** part of either key. It is the D-05 revision of the partition that produced the row.

Minimum DDL (`ledger.fct_charge`, insert-only revisioned partitions per D-05, clustered by `(tenant_id, usage_date)`):

| Column | Type | Rule |
|---|---|---|
| charge_row_id | VARCHAR(64) | sha256(bucket_key ␟ revision_id) |
| bucket_key, family_bucket_key | VARCHAR(64) | As above |
| tenant_id, organization_id | VARCHAR(36) | NOT NULL |
| contract_number | VARCHAR | Nullable; raw |
| scope_kind | VARCHAR(12) | ACCOUNT or ORGANIZATION |
| account_id | VARCHAR(36) | NULL iff scope_kind = ORGANIZATION |
| account_connected | BOOLEAN | FALSE for org accounts discovered but not onboarded |
| usage_date | DATE | UTC billing day |
| accounting_period | CHAR(7) | 'YYYY-MM'; equals month(usage_date) except PRIOR_PERIOD_ADJUSTMENT |
| service_type_raw, usage_type_raw, rating_type, billing_type, balance_source | VARCHAR | Raw source values; estimates carry MDH service_type and NULLs elsewhere |
| is_adjustment | BOOLEAN | NOT NULL |
| service_family | VARCHAR | From crosswalk; UNMAPPED_BILLABLE_SERVICE if unknown |
| crosswalk_version | VARCHAR | NOT NULL |
| funding_class | VARCHAR | CONTRACT, FREE, REBATE, ON_DEMAND, UNKNOWN |
| entry_kind | VARCHAR | CONSUMPTION, ADJUSTMENT, FEE, CREDIT, PRIOR_PERIOD_ADJUSTMENT, UNMAPPED |
| measure_role | VARCHAR | Always CHARGE in this table |
| price_basis | VARCHAR | BILLED_SOURCE, CONTRACT_RATE_ESTIMATE, CUSTOMER_APPROVED_RATE, UNKNOWN |
| native_unit | VARCHAR | CREDIT, TB_MONTH, TB, CURRENCY, UNIT |
| quantity, credits, effective_credits | NUMBER(38,12) | credits NULL for non-credit families |
| cost_native, cost_effective | NUMBER(38,12) | cost_effective NULL iff null_reason NOT NULL |
| currency | CHAR(3) | ISO 4217; NOT NULL |
| null_reason | VARCHAR | RATE_MISSING, RATE_AMBIGUOUS, BILLING_UNAVAILABLE, … |
| rate_id, rate_version | VARCHAR | For estimates |
| estimate_source | VARCHAR | UICD, MDH, MH, APPROVED_RATE; NULL for AUTH |
| complete_through | TIMESTAMP_NTZ | UTC; partial-day estimates |
| data_status | VARCHAR | PROVISIONAL, FINAL, RECONCILED |
| period_stability | VARCHAR | OPEN, STABLE |
| maturity_policy_version | VARCHAR | NOT NULL |
| flags | ARRAY | BILLING_MISSING, DIMS_DERIVED, RATE_CARRIED_FORWARD, UNRESOLVED_ACCOUNT |
| source_view, source_batch_id, revision_id, model_version | VARCHAR | Provenance; NOT NULL |
| supersedes / superseded_by | VARCHAR | Audit link written in `fct_charge_supersession` |

**Supersession decision table** (evaluated per family bucket, at publication time):

| # | Authoritative UICD snapshot for (org, usage_date) | Account rows in snapshot | Family rows for this family bucket | Active rows | Flags / control |
|---|---|---|---|---|---|
| 1 | None accepted | — | — | Estimate (PROVISIONAL) | — |
| 2 | Accepted, not mature (< date_end+72h) | Present | Present | Authoritative rows of that family | Estimate inactive; C8 records Δ |
| 3 | Accepted, not mature | Present | Absent | Estimate of that family | Wait (family may arrive later) |
| 4 | Accepted, not mature | Absent | — | Estimate | — |
| 5 | Mature | Present | Present | Authoritative | — |
| 6 | Mature | Present or absent | Absent, and MDH credits for family = 0 | Nothing | Confirmed zero |
| 7 | Mature | Present or absent | Absent, and MDH credits > 0 | Estimate (PROVISIONAL) | BILLING_MISSING; C2 FAILED |
| 8 | OU unavailable (reseller / no grant) | — | — | Estimate priced with CUSTOMER_APPROVED_RATE or money NULL | price_basis never BILLED_SOURCE |

Worked fixture F-SUP-01 (USD, account A1, 2026-08-17, family WAREHOUSE_COMPUTE):
- Estimate: MDH 100.000000000 cr × 2.00 = 200.00 (PROVISIONAL).
- UICD arrives with two rows: capacity 80 cr = 160.00 and overage 20 cr at 2.50 = 50.00.
- Active result = 210.00 in two fine buckets; the estimate is superseded (case 2 → 5).
- C8 estimate accuracy Δ = 200.00 − 210.00 = −10.00 (−4.761904…%).
- **Never 410.00.**

Hour-level money (FIN-103):
- Warehouse-hour money m_h = allocate_exact(210.00, WMH compute credits per hour). With Σ credits = 100, the displayed blended rate is 2.10/credit.
- Σ m_h = 210.000000000000 exactly.

### 3.2 Per-service authority and grain (contract-first; financial coverage of every row is R1)

"UICD" = OU.USAGE_IN_CURRENCY_DAILY, "MDH" = AU.METERING_DAILY_HISTORY, "MH" = AU.METERING_HISTORY. Money for every family = UICD family buckets. If UICD is unavailable, money = the estimate at family-bucket grain (G-FIN-01), otherwise NULL + reason. Service-type strings below are expected values, TO VERIFY LIVE in FIN-108.

| Family (service_family) | Money authority (CHARGE) | Provisional estimate (same family bucket) | Attribution source → grain (ATTRIBUTION) | Overlap trap / exclusion | Charge FINAL | Detail release · task |
|---|---|---|---|---|---|---|
| WAREHOUSE_COMPUTE (classic Gen1/Gen2) | UICD WAREHOUSE_METERING compute rows | MDH WAREHOUSE_METERING CREDITS_USED_COMPUTE × rate; intraday MH hourly | WMH → warehouse×hour; QAH prorated (D-14) → query×hour; idle = WMH.compute − WMH.attributed | Query + idle are subdivisions; QAH short queries → PRORATION_RESIDUAL | +72 h (UICD) | R1 · FIN-003 |
| WAREHOUSE_COMPUTE (Adaptive) | Same family bucket | Same | WMH → warehouse×hour; QMH → query×metering_hour | No idle (attributed column NULL, VERIFIED snippet); never union QAH+QMH | +72 h | R1\* · FIN-004 |
| CLOUD_SERVICES | UICD cloud-services rows including IS_ADJUSTMENT rows (representation TO VERIFY) | MDH Σ(CS gross + CREDITS_ADJUSTMENT_CLOUD_SERVICES) per account/day × rate | D-15: ∝ gross CS by warehouse-hour (WMH), serverless service type (MDH), query (QUERY_HISTORY) | Adjustment only at account/UTC day; serverless compute excluded from the 10 % base (VERIFIED snippet); no per-query 10 % | +72 h | R1 · FIN-005 |
| STORAGE (database, stage, fail-safe, hybrid, archive tiers) | UICD storage rows (daily accrual vs month-end TO VERIFY) | OU.STORAGE_DAILY_HISTORY avg bytes / tb_unit × rate per TB-month / days_in_month | DSUH → database×day (365 d backfill); STAGE_STORAGE_USAGE_HISTORY → stage; TSM → table×snapshot (from enrollment) | DSUH does not reconcile (VERIFIED snippet) → UNATTRIBUTED residual; clone logical bytes never summed | +72 h | R1 · FIN-006 |
| SNOWPIPE_FILE | UICD PIPE rows | MDH PIPE × rate | PIPE_USAGE_HISTORY → pipe×interval; NULL PIPE_ID → HIDDEN_PIPE | MH summary is reference only; pricing model changed to 0.0037 cr/GB (VERIFIED snippet) | +72 h | R1 · FIN-011 |
| SNOWPIPE_STREAMING | UICD SNOWPIPE_STREAMING rows | MDH SNOWPIPE_STREAMING × rate | Classic: CLIENT/CHANNEL history → client/channel×interval; HP: per-GB (source TO VERIFY) | Never reuse file-Snowpipe unit economics; migration component distinct | +72 h | R1\* · FIN-012 |
| SERVERLESS_TASK / SERVERLESS_ALERT | UICD SERVERLESS_TASK (alerts service type TO VERIFY) | MDH × rate | SERVERLESS_TASK_HISTORY (CREDITS_USED VARCHAR → exact decimal) → task×instance×interval; SERVERLESS_ALERT_HISTORY | Warehouse-executed tasks/dynamic tables are warehouse workload (WRK), never serverless | +72 h | R1 · FIN-013 |
| AUTO_CLUSTERING | UICD AUTO_CLUSTERING | MDH × rate | AUTOMATIC_CLUSTERING_HISTORY → table×interval | Summary MH not additive | +72 h | R1 · FIN-014 |
| SEARCH_OPTIMIZATION | UICD SEARCH_OPTIMIZATION | MDH × rate | SEARCH_OPTIMIZATION_HISTORY → table×interval | Benefit ≠ saving | +72 h | R1 · FIN-015 |
| MATERIALIZED_VIEW | UICD MATERIALIZED_VIEW | MDH × rate | MATERIALIZED_VIEW_REFRESH_HISTORY → view×interval | Reads of the view are warehouse workload | +72 h | R1 · FIN-016 |
| QUERY_ACCELERATION | UICD QUERY_ACCELERATION | MDH × rate | QUERY_ACCELERATION_HISTORY → warehouse×interval; QAH.CREDITS_USED_QUERY_ACCELERATION → query | QAH QAS column is decomposition, not a second bill | +72 h | R1\* · FIN-017 |
| AI_SERVICES (Cortex) | UICD AI_SERVICES (sub-types TO VERIFY) | MDH AI_SERVICES × rate | Effective-dated: CORTEX_AISQL_USAGE_HISTORY (≤ 2026-01-04) → CORTEX_AI_FUNCTIONS_USAGE_HISTORY (≥ 2026-01-05, hourly); Search/Analyst/Agent views as separate sets | Retired functions view: history only; agent parent includes child tools; warehouse credits of the calling query stay WAREHOUSE_COMPUTE | +72 h | R1\* · FIN-018 |
| SPCS (compute pools; block storage/transfer as separate rating types TO VERIFY) | UICD SNOWPARK_CONTAINER_SERVICES | MDH × rate | SNOWPARK_CONTAINER_SERVICES_HISTORY → pool×hour, app_id | Two services on one pool: one charge; utilization never inferred from credits | +72 h | R1\* · FIN-019 |
| DATA_TRANSFER | UICD data-transfer rows (currency per TB) | DATA_TRANSFER_HISTORY bytes / tb_unit × directional rate | DATA_TRANSFER_HISTORY → direction×type×day | Bytes × credit price forbidden; replication transfer is a link | +72 h | R1 · FIN-008 |
| REPLICATION (compute) | UICD REPLICATION | MDH × rate | REPLICATION_GROUP_USAGE_HISTORY (current) / DATABASE_REPLICATION_USAGE_HISTORY (legacy), effective-dated | No old/new union; transfer counted in DATA_TRANSFER only | +72 h | R1\* · FIN-008 |
| MARKETPLACE | UICD marketplace rows if present; else DATA_SHARING_USAGE.MARKETPLACE_PAID_USAGE_DAILY (separate invoice) | None (billed source only) | MPUD listing detail; APPLICATION_DAILY_USAGE_HISTORY app consumption links (non-additive) | MONETIZED_USAGE_DAILY = provider revenue, blocked from CHARGE; MCD double count | +72 h (UICD) / +72 h (MPUD 48 h latency) | R1\* · FIN-020 |
| ORGANIZATION_FEES (support, VPS, private connectivity, …) | UICD rows with ACCOUNT NULL → scope ORGANIZATION | None | None; D-15 platform bucket | Never assigned to an invented account | +72 h | R1 · FIN-021 |
| ADJUSTMENTS / CREDITS | UICD IS_ADJUSTMENT = TRUE (signed) | None | Follow family of service_type when present; else unallocated | Balance source REBATE is funding, not a negative charge | +72 h | R1 · FIN-005/021 |
| HYBRID_TABLE_REQUESTS (historic) | UICD rows ≤ 2026-02-28 | MDH × rate ≤ 2026-02-28 | None | Not billed from 2026-03-01 (VERIFIED snippet) | +72 h | R1 · FIN-021 |
| UNMAPPED_BILLABLE_SERVICE | Any UICD tuple absent from crosswalk | MDH unknown service_type × rate if rated, else NULL + reason | None | Counted once; mapping work item created | +72 h | R1 · FIN-021 |
| BRIDGE_OVERHEAD (D-08) | Inside WAREHOUSE_COMPUTE of BRIDGE_FINOPS_WH | — | QUERY_TAG prefix `bridge_finops:` → workload | Not a separate charge | — | R1 · FIN-003 |

### 3.3 Maturity policy v0 (D-13, numbers; `ref_source_maturity_policy`)

Horizons are measured from the end of the source interval (hour or UTC day). "Documented latency" values come from the source catalog unless marked otherwise.

| Source | Documented latency | Data FINAL (charge or measurement) | Attribution FINAL | Anti-entropy / revision window |
|---|---|---|---|---|
| UICD | 72 h (VERIFIED snippet) | date_end + 72 h | — | Open month + previous month re-extracted daily until STABLE; then weekly for 90 d |
| Month stability (UICD) | "can change until month close" (VERIFIED snippet) | `period_stability=STABLE` at month_end + N d, N = 5 (FIN-108 re-derives N = max observed revision lag + 2 d) | — | Later changes → C9 CLOSED_PERIOD_DRIFT |
| RATE_SHEET_DAILY | 24 h | date_end + 48 h | — | Open month |
| MDH | 3 h | date_end + 24 h | — | 7-day overlap + 30-day weekly |
| MH / WMH | 3 h compute, 6 h CS | hour_end + 24 h | — | 24 h overlap + 30-day weekly |
| QAH | 8 h (one snippet: 6 h; TO VERIFY) | — | hour_end + T + 24 h, T = min(max STATEMENT_TIMEOUT, 48 h) → default 72 h | QAH re-extracted by END_TIME sweep (ING backlog) |
| QMH (Adaptive) | ≈ 1 h (VERIFIED snippet) | — | hour_end + 24 h if no running query overlaps the hour, else query end + 24 h | 24 h overlap |
| OU.STORAGE_DAILY_HISTORY | TO VERIFY | date_end + 72 h | — | 7 d |
| DSUH / STAGE_STORAGE_USAGE_HISTORY / STORAGE_USAGE | ≈ 2–3 h (TO VERIFY) | date_end + 24 h (weights only) | date_end + 24 h | 7 d |
| Serverless detail views (pipe, task, clustering, SO, MV, QAS) | TO VERIFY (≈ 45 min–3 h) | — | interval_end + 24 h | 24 h overlap + 30-day weekly |
| SPCS history | 3 h | — | hour_end + 24 h | 24 h |
| Cortex views | TO VERIFY | — | interval_end + 48 h | 7 d |
| MARKETPLACE_PAID_USAGE_DAILY | 48 h (VERIFIED snippet) | date_end + 72 h | — | Open month |
| DATA_TRANSFER_HISTORY / replication views | TO VERIFY | date_end + 48 h | date_end + 48 h | 7 d |

Status rules:
- A row is FINAL when the current UTC time ≥ its horizon **and** coverage for its source window is contiguous (ADR-006).
- RECONCILED is set per (period, publication) by FIN-009 S10.
- A later revision of any row in a RECONCILED period moves that period back to FINAL until controls are re-run. Closed statements are unaffected.

### 3.4 Reconciliation control catalog (`controls.yaml`)

Common rules:
- `delta = ledger_side − reference_side` (signed), `delta_abs = |delta|`, and `delta_rel = delta / |reference|`, which is NULL when reference = 0.
- Each control runs per currency and never across currencies.
- Outcome mapping:
  - **PENDING** — a required input is absent or not FINAL.
  - **MATCHED** — every compared bucket has |Δ| ≤ tolerance.
  - **WARNING** — excess buckets exist but each carries an *approved* classified explanation with evidence, or the control is informational.
  - **FAILED** — any unexplained excess on mature inputs.
- No control ever writes to `fct_charge` (no balancing plug).

| ID | Control | Ledger side → reference side | Grain | Tolerance | Required for RECONCILED | Notes |
|---|---|---|---|---|---|---|
| C1 | UNIT_TO_METERING | Σ WMH/MH credits → MDH credits per service_type | account × UTC day × service_type | ≤ 1e-6 credit per bucket (v0; FIN-108 derives from source scale) | Yes | Transport independence: hourly vs daily views |
| C2 | METERING_TO_BILLING | MDH CREDITS_BILLED per family → Σ UICD USAGE (credit families) | account × day × family | ≤ 1e-6 credit | Yes (if OU available) | Detects BILLING_MISSING, crosswalk errors |
| C3 | RATED_METERING_TO_BILLED | MDH billed credits × selected RATE_SHEET rate → Σ UICD USAGE_IN_CURRENCY | account × day × family × currency | One minor unit per bucket | Yes (if OU available) | Auto-classifies OVERAGE_PRICING, ADJUSTMENT, RATE_MISMATCH, RATE_MISSING |
| C4 | SERVICE_DETAIL_TO_TOTAL | Σ detail view credits → MDH service_type credits | account × day × family | ≤ 1e-6 credit; detail < total → attribution coverage only | No (WARNING at most) | detail > total beyond tolerance → FAILED (double-count risk) |
| C5 | LEDGER_TO_INVOICE | Σ active fct_charge in reference scope → Σ approved reference lines classified CONSUMPTION/SUPPORT/ADJUSTMENT/CREDIT_NOTE/MARKETPLACE | org × contract × accounting period × currency (and per line class when reference is itemised) | One minor unit per compared line and on the total | Per tenant policy (default: required for close, not for RECONCILED) | Missing reference → PENDING; TAX and CAPACITY_PURCHASE lines are out of scope, listed separately |
| C6 | ATTRIBUTION_CONSERVATION | Σ bridge rows (incl. residual kinds) → parent charge money | charge_row_id × attribution_set | Exactly 0 | Yes; FAILED blocks publication | Enforced as dbt test and control |
| C7 | ALLOCATION_CONSERVATION | direct + rule + shared + unallocated → source charge | charge × book × currency | Exactly 0 | Yes once ALC enabled | Owned by ALC-005; displayed here |
| C8 | ESTIMATE_ACCURACY | Superseded estimate → authoritative | family bucket | Informational | No | Always WARNING or MATCHED; trend feeds FIN-102 tuning |
| C9 | CLOSED_PERIOD_DRIFT | Current active ledger for a CLOSED period → pinned close publication | org × period × currency × family | One minor unit | No (creates correction case, FIN-107) | Runs nightly |

Worked outcomes:
- F-270 vs invoice 271: C5 Δ = 270.00 − 271.00 = **−1.00**, status FAILED.
- The analyst classifies −1.00 as TIMING with evidence and a checker approves: status WARNING (never MATCHED).
- No invoice uploaded: C5 PENDING. The period can still be RECONCILED if the tenant policy does not require C5, and the UI lists C5 as PENDING.

### 3.5 Period close, statements and corrections

States of `finance.financial_period(tenant, org, period YYYY-MM, currency)`:

| From | To | Guard | Capability |
|---|---|---|---|
| OPEN | CLOSE_PREVIEWED | period_stability = STABLE; required controls not FAILED/PENDING or covered by approved exception; coverage ≥ policy | finance.period.close.request |
| CLOSE_PREVIEWED | CLOSED (v1) | Approver ≠ requester; pins unchanged since preview (else STALE_PREVIEW); fresh durable authz check | finance.period.close.approve |
| CLOSE_PREVIEWED | OPEN | Reject or preview expiry (24 h) | request or approve |
| CLOSED (vn) | RESTATEMENT_PROPOSED | Correction case exists (C9) or manual reason | finance.period.restate.request |
| RESTATEMENT_PROPOSED | CLOSED (vn+1, flagged RESTATED) | Approver ≠ proposer; new pins; difference lines computed | finance.period.restate.approve |
| RESTATEMENT_PROPOSED | CLOSED (vn) + CARRY_FORWARD decision | Approver ≠ proposer; creates PRIOR_PERIOD_ADJUSTMENT in current OPEN period | finance.period.restate.approve |

**Freeze set** pinned in the close record:
- `publication_id` for fct_charge, bridge_charge_attribution, allocation facts and reference facts.
- `revision_id` set hash.
- crosswalk_version, maturity_policy_version and rate_version set (hash of rate_ids used).
- fx_version (NULL in R1).
- Tag, rule and allocation config versions.
- Control run IDs with statuses, and approved explanation IDs.
- Billing reference versions.
- Statement artifact sha256 (JSON, CSV and PDF).
- Requester, approver and UTC timestamps.

Storage:
- PG `finance.period_close` (authoritative control state).
- Insert-only mirror `ledger.fct_period_close` via the D-04 config publisher.
- Artifacts in the tenant evidence prefix on S3 with Object Lock compliance mode.
- D-05 GC and D-11 purge must skip pinned revisions and family aggregates.

**Worked example F-REST-01** (restatement vs carry-forward):
1. **2026-09-08:** August 2026 is STABLE since 2026-09-06 (month end 2026-09-01T00:00Z + 5 d). C1–C4 and C6 are MATCHED and C5 is MATCHED against the usage statement 270.00. Close v1 is approved by a second user. Statement v1 = 270.00 USD (support 5.00 and rebate −3.00 in the organization section).
2. **2026-10-14:** a UICD revision for 2026-08-17 storage arrives, 12.00 → 11.00. The ingest publishes revision r2. The active ledger for August now totals 269.00. The August statement v1 still reads 270.00; nothing mutates.
3. **2026-10-15 (nightly C9):** Δ = 269.00 − 270.00 = −1.00 for family STORAGE creates correction case CC-1 (materiality under the default policy: |−1.00| < max(100, 1.35), so the proposal default is CARRY_FORWARD).
4. **Option A, RESTATE:** proposer and approver create statement v2 = 269.00 linked to v1, with the difference line "Storage −1.00". August shows "CLOSED v2 (restated)". Chargeback statements for August get linked v2 adjustments (ALC-008).
5. **Option B, CARRY_FORWARD:** a `PRIOR_PERIOD_ADJUSTMENT` of −1.00 is created with usage_date 2026-08-17 and accounting_period 2026-10. October consumption KPIs (by usage_date) stay unchanged. The October **statement** shows "Prior-period adjustments: −1.00". August remains CLOSED v1 = 270.00 with the annotation "later correction −1.00 carried to 2026-10 (CC-1)".
6. **Explorer "August" in both options:** it shows the current truth (269.00) with a banner "differs from closed statement v1 by −1.00". Statement and chargeback pages show the issued versions.

### 3.6 Money and rounding contract (`packages/bridge_money`, dbt macros)

- **Internal scale:** NUMBER(38,12) (|x| < 10²⁶; no realistic overflow). In SQL, cast both operands explicitly before multiply or divide, because of the Snowflake scale rules (VERIFIED snippet). Rates are never obtained by dividing and then multiplying back.
- **Python:** `bridge_money.CTX = Context(prec=76, rounding=ROUND_HALF_UP, traps=[InvalidOperation, DivisionByZero, Overflow])`. `q12(x) = x.quantize(Decimal('1e-12'))`. No `float` accepted: type guard raises `TypeError`.
- **`allocate_exact(parent, weights{key: w≥0}, quantum=1e-12)`:**
  - If Σw = 0, return {UNATTRIBUTED: parent}.
  - Otherwise exactᵢ = parent × wᵢ / Σw, and flooredᵢ = floor toward zero at the quantum.
  - k = (parent − Σ floored)/quantum (a signed integer with |k| < n). Give ±1 quantum to the |k| keys with the largest |remainder|, ties broken by ascending key.
  - Postcondition: Σ = parent exactly.
- **Coverage residual:** when detail quantity Q_d < bucket quantity Q, first split parent into attributed = allocate_exact over {DETAIL: Q_d, UNATTRIBUTED: Q − Q_d}, then allocate DETAIL over the children.
- **`round_statement_lines(lines, currency)`:**
  - u = minor unit (ISO 4217 seed: USD/EUR 0.01, JPY 1, KWD 0.001).
  - T = ROUND_HALF_UP(Σ exact, u), and tᵢ = truncate toward zero(exactᵢ, u).
  - k = (T − Σ tᵢ)/u. If k > 0, add +u to the k lines with the largest positive remainders. If k < 0, add −u to |k| lines with the most negative remainders. Ties go to the stable line ID.
  - Examples:
    - {1.00 split into thirds} → 0.34/0.33/0.33.
    - {+0.006, +0.006, −0.004} → T = 0.01 → 0.01/0.00/0.00.
    - {+0.004, −0.006, −0.006} → T = −0.01 → 0.00/−0.01/0.00 (tie by ID).
    - "-0.00" is normalized to "0.00".
- **JSON money** = string matching `^-?(0|[1-9][0-9]{0,25})(\.[0-9]{1,12})?$`, never "-0…", and always with `currency`. Unavailable = `null` + `null_reason`. The UI never sums money with JS `number`: it uses decimal.js or big.js, or the server-provided totals.

### 3.7 Fixture recomputation (all arithmetic redone by the reviewer)

| Fixture (source) | Recomputation | Result |
|---|---|---|
| F-270 total (validation-strategy, ledger.md) | 200+10+12+18+6+8+4+10+5−3 = 270.00 | PASS |
| Account scope 268 | 270 − (5 − 3) = 268.00 | PASS |
| Wrong answers 470 / 488 (FIN-001) | 270+140+60 = 470 (query+idle added); 470+18 = 488 (summary serverless added) | PASS (explained) |
| Billed credits 105 (ledger.md) | 100 + (15 − 10) = 105 | PASS |
| Cloud services 10.00 | (15 − 10) × 2 = 10.00; adj −10 = −min(15, 0.1×100) consistent with vendor rule | PASS |
| Serverless 18 | 5+7+2+2+2 = 18; Explorer ×100: 700+500+200+200+200 = 1,800 | PASS |
| Correction 269; EUR not 289 | 270 − 12 + 11 = 269; 269 + 20 = 289 must never appear | PASS |
| Invoice delta | 270 − 271 = −1 (ledger − reference) | PASS |
| Adaptive Q1 | 0.25+0.75 = 1.00; 0.30+0.75 = 1.05; 1.30 = 0.25+0.30+0.75 (append); 1.80 = 0.30+0.75+0.75 (duplicated hour) | PASS (1.80 derivation now stated) |
| QAS 3 = 2 + 1 | 2.00 detail + 1.00 unattributed | PASS |
| AI parent 10 / child 4 | 10 stays 10; residual 6 (F-AI-10, separate from F-270) | PASS (rename) |
| Allocation book A | Query 140 → 84/56 (60/40); idle 60 → 36/24; totals 120/80 = 200 | PASS |
| Allocation book B | 84 + 56 + 60 = 200 | PASS |
| Rounding thirds | 0.33×3 = 0.99, +0.01 to the first ID → 0.34/0.33/0.33; mirrored for −1.00 | PASS |
| Budget | Actual 15×10 = 150; remaining 280−150 = 130; forecast 150 + 15×10 = 300; variance 20; 20/280 = 7.142857…% | PASS |
| Anomaly z | 60/(1.4826×10) = 4.0469445568… ≈ 4.04694456 | PASS |
| Workload comparison | 60 − 20 = 40 = (20−10)×2 + 20×(3−2) | PASS |
| Savings | 2/unit × 120 = 240; 240−180 = 60; 240−260 = −20 | PASS |
| Margin | (1000−300)/1000 = 70 % | PASS |
| UI fixture ×100 | 20,000+1,000+1,200+1,800+600+800+400+1,000+500−300 = 27,000; account 26,800 | PASS |
| UI storage correction | 27,000 − 1,200 + 1,100 = 26,900 | PASS |
| UI forecast | 15,000 + 15×1,000 = 30,000; +2,000/28,000 = 7.142857…% | PASS |
| UI chargeback | Finance 8,400 + 3,600 = 12,000; Marketing 5,600 + 2,400 = 8,000; issued 20,000 | PASS |
| PRD §86 chargeback | 48,320+2,014+4,811+1,520+822+201 = 57,688 | PASS |
| PRD §88 quality | 73.1+18.2+6.5+2.2 = 100.0; coverage 100 − 2.2 = 97.8 | PASS |
| FIN-020 | 10 + 8 = 18 (26 = 8 counted twice) | PASS |
| FIN-021 | 5 − 3 + 9 = 11; org total with novel service = 268 + 11 = 279 (not 281) | PASS (oracle reworded, G-FIN-22) |

## 4. Revised production backlog

Conventions:
- dbt models live under `data/dbt/models/ledger/…`, staging under `data/dbt/models/staging/…`, contracts under `data/contracts/…`, fixtures under `data/fixtures/finance/…`, and task validation under `tests/spec/FIN-0xx/`.
- The API lives in `apps/api/finance/…` and the web app in `apps/web/src/features/finance/…`.
- "Oracle" values are computed independently (by hand or spreadsheet), never by the code under test.
- Every step that reads UICD or crosswalk strings depends on FIN-108 evidence before the task is marked DONE.

### FIN-001 — Define charge schema, service authority and exact decimal fixtures
Release: R1 · Estimate: 40–60 h · Risk: H · Decisions: D-05, D-12 (amended), D-13, D-15 · Closes: G-FIN-01, G-FIN-18, G-FIN-22 (partly), G-FIN-02 (ledger gate)
Dependency changes: `−DBT-005` (reversed: DBT-005 consumes the FIN-GOLD fixtures authored here), `−ING-001` (contract-level only; ING-001 consumes the maturity fields from FIN-104), `+FND-004` (fixture harness). FIN-001 can start in phase P0.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-001-S01 | Author the `fct_charge` JSON Schema and dbt contract with every column of §3.1, types NUMBER(38,12)/VARCHAR/DATE/BOOLEAN, enum lists and conditional nullability (`account_id` NULL iff ORGANIZATION; `cost_effective` NULL iff `null_reason` set) | `data/contracts/ledger/fct_charge.schema.json`, `data/dbt/models/ledger/_contracts/fct_charge.yml` | 12 valid and 12 invalid example rows validate as expected in `tests/spec/FIN-001/test_schema.py` | 3 |
| FIN-001-S02 | Specify fine and family bucket keys: field order, U+001F separator, '∅' null token, upper-case trim, sha256 hex. Implement Python reference `bridge_ledger_keys.bucket_key()` and dbt macro `ledger_bucket_key()` | `packages/bridge_ledger_keys/`, `data/dbt/macros/ledger_keys.sql` | Python and SQL produce identical keys for 1,000 generated rows, including NULL/unicode/whitespace cases | 3 |
| FIN-001-S03 | Write the supersession decision table (8 cases, §3.1) with a fixture ID per case | `data/contracts/ledger/supersession.md` | Reviewer sign-off; every case maps to one F-SUP fixture row | 2 |
| FIN-001-S04 | Author the `bridge_charge_attribution` contract: grain (charge_row_id, attribution_set, target_kind, target_id, hour_start NULLable, query_id NULLable), residual kinds UNATTRIBUTED/IDLE/PRORATION_RESIDUAL/OVER_ATTRIBUTED/HIDDEN_RESOURCE, `attribution_status`, exact conservation | `data/contracts/ledger/bridge_charge_attribution.schema.json` | Schema rejects a row without residual kind or target | 3 |
| FIN-001-S05 | Author the service authority registry from §3.2 (one entry per family: charge source, estimator, attribution sets with effective_from/to, exclusions, release). JSON Schema forbids two CHARGE authorities with overlapping windows per family, and forbids `MONETIZED_USAGE_DAILY` with role CHARGE | `data/contracts/service-authority.json`, `…/service-authority.schema.json` | Validator rejects 4 crafted invalid registries (overlap, unknown role, provider view as CHARGE, missing exclusion) | 4 |
| FIN-001-S06 | Seed crosswalk v0: UICD tuples and MDH service types → service_family/entry_kind/native_unit, with every row marked `evidence=TO_VERIFY_LIVE`; unknown tuple → UNMAPPED_BILLABLE_SERVICE | `data/dbt/seeds/ref_service_crosswalk.csv` + `_seeds.yml` | dbt seed loads; uniqueness test on source tuple passes; FIN-108 replaces it with v1 | 3 |
| FIN-001-S07 | Build F-270 inputs (UICD rows, MDH, WMH, QAH, storage, serverless detail, org rows, EUR 20.00 bucket) and expected outputs computed by hand | `data/fixtures/finance/fin_gold_01/{inputs,expected}/*.csv` | Expected org USD 270.00, account 268.00, EUR 20.00; the spreadsheet computation file is committed | 4 |
| FIN-001-S08 | Build supersession fixtures F-SUP-01 (200.00 estimate → 160.00 + 50.00), F-SUP-02 (family arrives late: case 3 → 2), F-SUP-03 (A2 missing after maturity → BILLING_MISSING) | `data/fixtures/finance/f_sup_0{1,2,3}/` | Expected actives: 210.00 (never 410.00); case-3 estimate retained; A2 estimate retained with flag | 3 |
| FIN-001-S09 | Build F-COR-01 (storage 12 → 11 revision, duplicate replay) and currency fixture (USD and EUR in one org) | `data/fixtures/finance/f_cor_01/` | Expected 269.00 after the revision and 269.00 after replay; no 289 anywhere | 2 |
| FIN-001-S10 | Implement generic dbt tests `unique_active_bucket_key`, `no_mixed_basis_in_family_bucket`, `measure_role_is_charge`, `account_iff_account_scope`, `money_null_has_reason`, `single_currency_aggregate`, `no_float_columns` (information_schema over RAW/STAGING/LEDGER) | `data/dbt/tests/generic/ledger_*.sql` | Each test fails on its purpose-built bad fixture and passes on F-270 | 4 |
| FIN-001-S11 | Add negative model fixtures: query row inserted into fct_charge (→ 470), summary serverless added (→ 488), duplicated authority window, missing `source_batch_id` | `tests/spec/FIN-001/negative/` | 4/4 fail with the named test ID in CI output | 3 |
| FIN-001-S12 | Tenant isolation fixture: tenants A and B with identical account locators, dates and service types | `tests/spec/FIN-001/isolation/` | Bucket keys differ; a deliberate join without tenant_id trips DBT-005's fan-out gate | 2 |
| FIN-001-S13 | Write the sign and entry_kind conventions appendix (delta = ledger − reference; correction = new − closed; PRIOR_PERIOD_ADJUSTMENT semantics; funding_class) | `data/contracts/ledger/conventions.md` | Linked from ledger.md change proposal; reviewer sign-off | 2 |
| FIN-001-S14 | Run and record `make validate-task TASK=FIN-001 ENV=local` | `docs/evidence/FIN-001/<commit>/` | Expected and observed table for F-270, F-SUP, F-COR all PASS | 2 |
Task acceptance:
- [ ] No FLOAT/DOUBLE column exists in any ledger/staging contract (`no_float_columns` green).
- [ ] F-270 gives org 270.00, account 268.00 and EUR 20.00. The wrong answers 470 and 488 are each produced only by a named failing negative fixture.
- [ ] F-SUP-01 has exactly two active authoritative buckets totalling 210.00 and zero active estimates for that family bucket.
- [ ] Bucket-key parity holds between Python and SQL on 1,000 rows.
- [ ] The authority registry rejects overlapping CHARGE windows and provider-revenue sources.

### FIN-002 — Normalize billing, rate sheets and approved pricing
Release: R1 · Estimate: 45–65 h · Risk: H · Decisions: D-05, D-12, D-13 · Closes: G-FIN-04, G-FIN-13 (engine side), G-FIN-20
Dependency changes: `+ING-001` (UICD/RATE_SHEET source contracts), `+FIN-108` (crosswalk v1 before DONE; the SQL can start on v0), `+DBT-003` (account membership at usage_date). The approved-rate UI/API moves to new FIN-105.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-002-S01 | Finalize the UICD projection (add USAGE_TYPE) and the RATE_SHEET_DAILY projection. Staging models cast explicitly to NUMBER(38,12) and upper-case enums | `data/dbt/models/staging/ou/stg_ou__usage_in_currency_daily.sql`, `stg_ou__rate_sheet_daily.sql` | Contract test: column types match; a float input fixture is quarantined | 3 |
| FIN-002-S02 | Apply complete-snapshot semantics per (org, usage_date) with the DBT-002 macro. The latest accepted snapshot replaces the previous one, and rows missing from it disappear from the active set | `int_billing__uicd_snapshot_active.sql` | Fixture: a row deleted in snapshot r2 is absent from the active set; r1 stays queryable by revision | 3 |
| FIN-002-S03 | Aggregate truly identical dimensional rows within a snapshot (sum measures, keep `source_row_count`) | same model | Two legitimate identical rows of 5.00 give one bucket of 10.00 with count 2 (not 5.00) | 2 |
| FIN-002-S04 | Map to authoritative `fct_charge` candidates. Scope is ORGANIZATION when ACCOUNT_LOCATOR is NULL. Resolve account_id via membership at usage_date (DBT-003). An unconnected account gets `account_connected=false`; an unknown locator gets the UNRESOLVED_ACCOUNT flag and is never dropped | `int_charge__authoritative.sql` | F-270 org rows NULL account; unknown locator row present with flag | 4 |
| FIN-002-S05 | Handle legacy rows whose RATING_TYPE/BILLING_TYPE/SERVICE_TYPE are NULL: derive via USAGE_TYPE crosswalk and set `DIMS_DERIVED` | same | Fixture with NULL new columns maps to the expected family | 2 |
| FIN-002-S06 | Derive `funding_class` from balance_source. Spend metric = all classes; capacity-drawdown metric excludes ON_DEMAND | `int_charge__authoritative.sql`, metric definitions for API-001 | F-SUP-01: spend 210.00, drawdown 160.00 | 3 |
| FIN-002-S07 | Build `fct_rate` (rate_id, rate_source RATE_SHEET, CUSTOMER_APPROVED or DEMO_FIXTURE, full key of G-FIN-20, effective_rate NUMBER(38,12), rate_version) | `data/dbt/models/ledger/pricing/fct_rate.sql` | Unique test on (rate_source, full key, effective_date) | 3 |
| FIN-002-S08 | Implement the `select_rate()` macro: exact key match; 0 → NULL + RATE_MISSING; >1 distinct → NULL + RATE_AMBIGUOUS; carry-forward ≤ 3 days with flag. Add a pre/post join row-count equality test | `data/dbt/macros/select_rate.sql`, `tests/rate_join_no_fanout.sql` | Two candidate rates give NULL money plus reason, not double cost; row counts are equal | 4 |
| FIN-002-S09 | Apply rate precedence RATE_SHEET > CUSTOMER_APPROVED (FIN-105). When both exist and differ, emit `RATE_SOURCE_DISAGREEMENT` into C3 classification | macro + `int_rate__selected.sql` | Fixture with 2.00 vs 2.05 selects 2.00 and records the disagreement | 2 |
| FIN-002-S10 | Add the provenance-based demo guard: `rate_source=DEMO_FIXTURE` is rejected unless tenant.kind = DEMO (dbt test + runtime assertion). CI grep flags a literal `2.91` outside `data/fixtures/demo/` | `tests/demo_rate_guard.sql`, `.github/workflows/lint-finance.yml` | Prod-profile run with a DEMO rate fails; a real rate sheet row of 2.91 passes | 2 |
| FIN-002-S11 | Fixture F-RATE-01 (mid-month change: 1–15 Aug 2.00, 16–31 Aug 2.20, 10 cr/day) | `data/fixtures/finance/f_rate_01/` | Total = 15×20.00 + 16×22.00 = 652.00 | 2 |
| FIN-002-S12 | Fixture F-RATE-02 (OU denied): no authoritative rows; estimates via approved rate or NULL money; coverage reason BILLING_UNAVAILABLE | `data/fixtures/finance/f_rate_02/` | Credits visible, money NULL with reason; price_basis never BILLED_SOURCE | 2 |
| FIN-002-S13 | Revision preservation: UICD revision for 2026-08-17 (storage 12 → 11) creates a new partition revision; the old one stays selectable by publication | F-COR-01 wiring | Active = 269.00; pinned old publication = 270.00 | 2 |
| FIN-002-S14 | Tenant isolation: tenant B's rate or org with an identical name is never used for tenant A | `tests/spec/FIN-002/isolation/` | Join count across tenants = 0 | 2 |
| FIN-002-S15 | Observability: counters `fin_billing_snapshot_rows_total{source}`, `fin_rate_missing_buckets`, `fin_rate_ambiguous_buckets` (tenant only in structured logs); alarm when RATE_AMBIGUOUS > 0 on any FINAL day | `infra/observability/fin_alarms.tf` or equivalent | Alarm fires in staging on the injected ambiguous fixture | 2 |
| FIN-002-S16 | Add a runbook RB-06 subsection "rate missing / ambiguous / disagreement", then record evidence | `docs/runbooks/financial-mismatch.md`, `docs/evidence/FIN-002/` | Runbook dry-run on staging fixture recorded | 2 |
Task acceptance:
- [ ] 100 credits at synthetic 2.00 give 200.00 when a single rate matches. Two candidate rates give NULL + RATE_AMBIGUOUS, never 400.00.
- [ ] Balance-source split 80 capacity + 20 overage gives spend 210.00 and capacity drawdown 160.00.
- [ ] Organization rows stay ORGANIZATION scope, and no invented account appears.
- [ ] A billing revision is preserved: active 269.00, while the pinned publication still returns 270.00.
- [ ] A DEMO_FIXTURE rate cannot price a non-demo tenant.

### FIN-003 — Implement classic warehouse compute, query attribution and idle
Release: R1 · Estimate: 50–75 h · Risk: H · Decisions: D-11, D-12, D-13, D-14 · Closes: G-FIN-03, G-FIN-08 (attribution), G-FIN-14
Dependency changes: `+FIN-102` (estimates and supersession), `+FIN-103` (allocate_exact / bridge framework), `+FIN-104` (attribution horizons); keep DBT-003.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-003-S01 | Build WMH hourly staging (account, warehouse_id, start_time UTC, compute, cs, attributed) with revision replacement, and QAH staging keyed (tenant, account, query_id) latest revision | `stg_au__warehouse_metering_history.sql`, `stg_au__query_attribution_history.sql` | Revised hour 1.0 → 1.2 replaces rather than appends; duplicate batch is idempotent | 3 |
| FIN-003-S02 | Allocate each WAREHOUSE_COMPUTE family-bucket money to warehouse-hours by WMH compute credits with `allocate_exact`. Σ WMH ≠ bucket quantity → UNATTRIBUTED or OVER_ATTRIBUTED | `bridge_warehouse_hour.sql` | Σ hour money = bucket money exactly (C6); bucket 210.00 over 100 cr → blended 2.10 | 4 |
| FIN-003-S03 | Implement D-14 proration: explode each QAH query over the hours intersecting [start,end), weight = overlap/duration, zero duration → start hour, using a bounded hour spine (max span = statement-timeout cap + 1 h) | `int_query__hourly_prorated.sql`, macro `hour_spine()` | F-D14-01: Q 23:30–01:30, 2.0 cr → 0.5 / 1.0 / 0.5; day totals 0.5 and 1.5 | 4 |
| FIN-003-S04 | Performance: benchmark proration on 1 M QAH rows/day on the central warehouse; cluster keys (tenant_id, usage_date) | `tests/perf/FIN-003/` result | Runtime and credits recorded; the target (≤ 5 min on M) is TO VERIFY and reported, not assumed | 3 |
| FIN-003-S05 | Decompose per warehouse-hour: IDLE = WMH.compute − WMH.attributed (WMH only); QUERY = prorated QAH; PRORATION_RESIDUAL = WMH.attributed − Σ prorated (signed) | `bridge_warehouse_query_idle.sql` | F-270: query 70 cr, idle 30 cr, total 100 cr | 4 |
| FIN-003-S06 | Turn credits into money per hour: shares of m_h via `allocate_exact` over {queries…, IDLE, PRORATION_RESIDUAL} | same | F-270 money: query 140.00 + idle 60.00 = 200.00 exactly | 3 |
| FIN-003-S07 | Negative idle: WMH.attributed > compute → quality flag IDLE_NEGATIVE (C-quality FAILED), idle row = 0, OVER_ATTRIBUTED row carries the negative raw difference explicitly | same + `tests/idle_negative.sql` | Fixture compute 10 / attributed 10.5 gives flag + explicit −0.5 cr raw difference | 2 |
| FIN-003-S08 | Missing attribution (WMH.attributed NULL or QAH window immature) → idle NULL with reason ATTRIBUTION_UNAVAILABLE; the whole m_h goes to UNATTRIBUTED | same | Oracle: missing attribution gives idle unknown, not 100 | 2 |
| FIN-003-S09 | Short queries absent from QAH (≤ ~100 ms, VERIFIED snippet) end up in PRORATION_RESIDUAL; document in the model docs | same | Fixture WMH attributed 70, QAH Σ 69.5 → residual 0.5 cr | 2 |
| FIN-003-S10 | Set attribution maturity from FIN-104: hour split FINAL at hour_end + T + 24 h (default 72 h); a late QAH row rebuilds the affected hours as a new revision | `attribution_status` column | Late 40 h query fixture changes hour split at +44 h; status PROVISIONAL until +72 h | 3 |
| FIN-003-S11 | Resize and multi-cluster: no model reads WAREHOUSE_SIZE for money (lint test); resized-within-hour fixture | `tests/no_size_based_money.sql` | Lint fails if WAREHOUSE_SIZE appears in ledger/bridge SQL | 2 |
| FIN-003-S12 | D-11 tiering: query-level bridge rows hot 90 d; aggregate `bridge_query_family_daily` (parameterized hash × warehouse × day) kept 400 d; pinned closed periods retain family aggregates | `bridge_query_family_daily.sql`, purge job spec | Purging query rows leaves family and day totals unchanged (checksum) | 3 |
| FIN-003-S13 | Label queries with QUERY_TAG prefix `bridge_finops:` as workload BRIDGE_OVERHEAD (D-08) | same | Fixture shows Bridge overhead as a separate workload, still inside warehouse 200 | 1 |
| FIN-003-S14 | Tenant isolation: identical query_id and warehouse_id in tenants A and B | `tests/spec/FIN-003/isolation/` | Zero cross-tenant rows; composite key enforced | 2 |
| FIN-003-S15 | Observability: `fin_wh_idle_negative_hours`, `fin_wh_unattributed_ratio`; alert if unattributed > 20 % on FINAL days for 3 consecutive days per tenant | alarms | Injected fixture triggers alert in staging | 2 |
| FIN-003-S16 | Evidence: F-270 warehouse, F-D14-01, negative-idle and missing-attribution fixtures | `docs/evidence/FIN-003/` | All PASS; staging run on tenant-zero data recorded | 2 |
Task acceptance:
- [ ] 100 compute / 70 attributed gives 30 idle with parent 200.00 unchanged; query 140.00 + idle 60.00 = 200.00 exactly.
- [ ] A cross-midnight query is prorated (0.5 / 1.5 by day) and no day shows negative idle due to allocation.
- [ ] The proration residual is an explicit signed row; there is no fabricated scaling of query costs.
- [ ] Attribution is not FINAL before hour_end + 72 h (default policy).
- [ ] Query-level purge after 90 d preserves family and day totals.

### FIN-004 — Implement Adaptive query-hour compute and maturity
Release: R1\* (D-20; Adaptive GA since 2026-06-16) · Estimate: 24–36 h · Risk: M · Decisions: D-12, D-13, D-20 · Closes: G-FIN-07
Dependency changes: `−FIN-003` (independent attribution model; shares only WMH staging), `+FIN-103`, `+FIN-104`. FIN-009 no longer depends on FIN-004; it plugs in via capability.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-004-S01 | Detect Adaptive capability per warehouse (warehouse type from the inventory source, TO VERIFY field; fallback: WMH attributed NULL and QMH rows present) with an effective-dated `warehouse_capability` | `int_warehouse__capability_history.sql` | Fixture warehouse converted at 12:00 shows CLASSIC before and ADAPTIVE after | 3 |
| FIN-004-S02 | Stage QMH keyed (tenant, account, query_id, query_metering_hour); predicate on QUERY_METERING_HOUR; keep NULL start/end/name rows | `stg_au__query_metering_history.sql` | Running-query row with NULL end retained | 2 |
| FIN-004-S03 | Replace revisions by key | same | F-ADP-01: 0.25 → 0.30 revision gives 1.05, not 1.30 (append) or 1.80 (duplicated hour) | 2 |
| FIN-004-S04 | Reuse the warehouse-hour money split (FIN-003-S02 macro) for Adaptive warehouses | `bridge_warehouse_hour.sql` (shared macro) | Σ = bucket money | 2 |
| FIN-004-S05 | Query attribution: allocate m_h over QMH compute credits; residual = WMH.compute − Σ QMH (signed) → UNATTRIBUTED or OVER_ATTRIBUTED; emit no IDLE row (`idle_status=NOT_APPLICABLE`) | `bridge_adaptive_query_hour.sql` | Idle shows "not applicable" (not 0, not unknown) | 3 |
| FIN-004-S06 | Expose QMH CREDITS_USED_CLOUD_SERVICES as gross CS weight for FIN-005 | same | CS weights available per query-hour | 1 |
| FIN-004-S07 | Running queries: current-hour rows mutable; attribution PROVISIONAL until query end + 24 h | `attribution_status` | Fixture running 3 h: status flips only after end + 24 h | 2 |
| FIN-004-S08 | Exclude QAH rows for Adaptive warehouses if present (TO VERIFY) so QAH and QMH are never unioned | test `no_qah_qmh_union.sql` | Fixture with both sources counts each query-hour once | 2 |
| FIN-004-S09 | Conversion boundary: before the capability change use FIN-003, after it FIN-004; the boundary hour is split by capability timestamp | shared macro | Boundary-hour fixture conserves money exactly | 3 |
| FIN-004-S10 | Isolation and observability: `fin_adaptive_unattributed_ratio`; foreign-tenant query-id collision test | tests + metric | Zero cross-tenant rows | 2 |
| FIN-004-S11 | Evidence (staging uses a tenant-zero Adaptive warehouse when available; otherwise NOT_RUN with reason) | `docs/evidence/FIN-004/` | Recorded | 2 |
Task acceptance:
- [ ] 0.25 + 0.75 = 1.00; after the revision 1.05 (never 1.30 or 1.80).
- [ ] Classic idle is reported NOT_APPLICABLE for Adaptive warehouses.
- [ ] Money for Adaptive warehouses equals the bucket exactly, with the residual explicit.
- [ ] A capability flip mid-day is handled without double counting.

### FIN-005 — Implement adjusted cloud services and signed billing entries
Release: R1 · Estimate: 28–40 h · Risk: M · Decisions: D-12, D-15 · Closes: G-FIN-15
Dependency changes: `+FIN-102`, `+FIN-103`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-005-S01 | Stage MDH (account, usage_date, service_type): compute, CS gross, CREDITS_ADJUSTMENT_CLOUD_SERVICES (signed), CREDITS_BILLED. Row check: billed = compute + CS + adjustment (tolerance 1e-9) | `stg_au__metering_daily_history.sql`, `tests/mdh_row_identity.sql` | F-270: 100 + 15 − 10 = 105 billed | 3 |
| FIN-005-S02 | Build account-day CS: gross_total = Σ CS over service types; adj_total = Σ adjustments; billed_cs = gross + adj. Informational control CS_ADJUSTMENT_RULE: adj = −min(gross_total, 0.1 × warehouse compute) | `int_cloud_services__account_day.sql` | F-270: −min(15, 10) = −10 PASS; rule-violation fixture gives WARNING | 3 |
| FIN-005-S03 | CS family estimate (billed_cs credits × rate) via FIN-102 | estimator config | 5 cr × 2.00 = 10.00 PROVISIONAL | 2 |
| FIN-005-S04 | Authoritative CS: sum all UICD rows of the CS family including IS_ADJUSTMENT rows (both representations supported: net row, or gross + negative adjustment row) | crosswalk + `int_charge__authoritative` | Both fixture representations give 10.00 | 2 |
| FIN-005-S05 | D-15 attribution: allocate billed CS money ∝ gross CS weights across warehouse-hours (WMH CS), serverless service types (MDH CS), and queries (QUERY_HISTORY CS) for drilldown; Σ weights = 0 → UNATTRIBUTED | `bridge_cloud_services.sql` | Σ bridge = 10.00 exactly | 4 |
| FIN-005-S06 | Counter-example F-CS-02: A (1 cr compute, 0.5 CS) and B (99, 0.5) → billed 0.00; no query receives CS money | fixture + test | Both allocations 0.00; a per-query 10 % rule would yield 0.40 → test asserts absence | 2 |
| FIN-005-S07 | Signed adjustment entries (credits, rebates, IS_ADJUSTMENT) keep their sign; assert that no `cost ≥ 0` test is attached to ADJUSTMENT or CREDIT entry kinds | `tests/signed_entries_allowed.sql` | Rebate −3.00 decreases total and passes | 2 |
| FIN-005-S08 | Org-scope support +5.00 and rebate −3.00 visible only with `finance.org_scope.read` (row policy fixture with A-reader) | `tests/spec/FIN-005/org_scope/` | A-reader totals exclude them; no derived org total visible | 2 |
| FIN-005-S09 | Adjustment arriving for a CLOSED period emits `closed_period_drift` input for C9 (FIN-107) | event row in `fct_reconciliation_input` | Fixture adjustment on closed August creates C9 candidate | 2 |
| FIN-005-S10 | Observability and evidence | `docs/evidence/FIN-005/` | Recorded | 2 |
Task acceptance:
- [ ] Cloud 15 + adjustment (−10) = billed 5; at 2.00 this is 10.00 and it appears once.
- [ ] The account-day adjustment is never distributed as a per-query 10 % rule (F-CS-02 = 0.00).
- [ ] Negative rebate −3.00 passes signed-entry validation and reduces the org total.
- [ ] Both UICD cloud-services representations yield the same net money.

### FIN-006 — Implement storage classes, snapshots and billed reconciliation
Release: R1 · Estimate: 36–54 h · Risk: M · Decisions: D-12, D-15 · Closes: G-FIN-16
Dependency changes: `+FIN-102`, `+FIN-103`; keep DBT-003.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-006-S01 | Record, from FIN-108 evidence, whether UICD storage is daily accrual or month-end posting, and the TB unit of the storage rate; encode both in crosswalk and rate metadata (`tb_unit`) | `ref_service_crosswalk`, `fct_rate.tb_unit` | Evidence link present; no default assumed silently | 2 |
| FIN-006-S02 | Stage OU.STORAGE_DAILY_HISTORY, AU.STORAGE_USAGE, DATABASE_STORAGE_USAGE_HISTORY and STAGE_STORAGE_USAGE_HISTORY with bytes as NUMBER(38,0) and explicit storage-class columns | `stg_ou__storage_daily_history.sql`, `stg_au__database_storage_usage_history.sql`, … | Types asserted | 3 |
| FIN-006-S03 | Estimate: money_d = avg_bytes_d / tb_unit × rate_TB_month / days_in_month(d) per storage class | estimator config | Fixture 3 TB avg, 23.00/TB-month, 31-day month → 2.225806451612…/day; 31 days sum to 69.00 exactly after `allocate_exact` of the monthly figure | 3 |
| FIN-006-S04 | Storage classes: database, stage, fail-safe, hybrid, archive tiers as `storage_class`; unknown class → UNMAPPED | same | Unknown class fixture visible, counted once | 3 |
| FIN-006-S05 | D-15 attribution: storage money → databases by DSUH bytes (database + fail-safe + hybrid) and stages by stage bytes; residual → UNATTRIBUTED; backfill DSUH 365 d at onboarding | `bridge_storage_database.sql` | Σ bridge = bucket money exactly; the residual is explicit | 4 |
| FIN-006-S06 | Table-level explanation from TSM daily snapshot (from enrollment): table share within database by active + TT + fail-safe + retained_for_clone bytes; pre-enrollment = UNKNOWN | `bridge_storage_table.sql` | Pre-enrollment query returns NULL + reason `SNAPSHOT_BEFORE_ENROLLMENT` | 4 |
| FIN-006-S07 | Clones: retained_for_clone bytes to the owning table per TSM; never sum clone logical size | fixture clone family | Three-clone fixture: physical bytes counted once | 3 |
| FIN-006-S08 | Dropped or recreated tables keep a stable ID; dropped keeps its bytes until purge | same | Recreated name = new table ID | 2 |
| FIN-006-S09 | Hybrid-table requests: historical charges through FIN-021; no estimate after 2026-03-01 | crosswalk rows | 2026-03-02 fixture has no hybrid request estimate | 1 |
| FIN-006-S10 | Correction F-COR-01 (12 → 11 → 269.00) and C9 drift input for closed periods | fixture | 269.00 active; C9 candidate created when August is closed | 2 |
| FIN-006-S11 | Isolation, observability (`fin_storage_unattributed_ratio`), evidence | tests + `docs/evidence/FIN-006/` | Recorded | 3 |
Task acceptance:
- [ ] Billed storage 12.00 appears once; database attribution sums to it with an explicit unattributed remainder.
- [ ] Pre-enrollment table history is UNKNOWN, while database-level history is available for 365 d.
- [ ] The revised total becomes 269.00, and a closed August is not mutated.
- [ ] Clone bytes are never double counted.

### FIN-007 — Validate independent serverless service inclusion and totals
Release: R1 · Estimate: 13–18 h · Risk: L · Decisions: D-12 · Closes: G-FIN-18 (conformance)
Dependency changes: `−FIN-012`, `−FIN-017` (R1\*, validated when enabled via capability flag); keep FIN-011/013/014/015/016; `+FIN-103`. (FIN-007 is missing from RELEASE_PLAN R1 lists; tagged R1 here.)
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-007-S01 | Graph test: each `bridge_<serverless family>` model's upstream set (`dbt ls --select +model`) contains staging/seeds only, never another ledger or bridge model | `tests/spec/FIN-007/test_independence.py` | Fails when a fixture model references `bridge_pipe` | 2 |
| FIN-007-S02 | Union fixture from UICD family buckets: pipe 5 + task 7 + clustering 2 + search 2 + MV 2 = 18.00; loading MH summary rows adds 0 | `data/fixtures/finance/fin_gold_01/serverless/` | Total 18.00 before and after loading summary | 2 |
| FIN-007-S03 | Implement C4 per family (detail credits vs MDH credits): detail < total → attribution coverage only; detail > total + tolerance → FAILED | `data/dbt/models/reconciliation/ctl_c4_service_detail.sql` | Fixture detail 13/18 → coverage 72.2 %; fixture 19/18 → FAILED | 3 |
| FIN-007-S04 | Capability denial: PIPE_USAGE_HISTORY denied → money unchanged, attribution coverage reduced, reason CAPABILITY_DENIED | fixture | 18.00 stays; pipe share UNATTRIBUTED | 2 |
| FIN-007-S05 | Unknown serverless service_type → UNMAPPED via FIN-021, counted once | fixture | +x once | 1 |
| FIN-007-S06 | Plug-in test for QAS and streaming when enabled: enabling adds attribution only, no money | fixture | Totals unchanged by enabling | 1 |
| FIN-007-S07 | Observability: metric `fin_serverless_attribution_coverage{family}` (no tenant label) and daily coverage log per tenant; alert when a family drops > 30 points day over day | alarm definition | Injected denial fixture triggers the alert in staging | 1 |
| FIN-007-S08 | Evidence | `docs/evidence/FIN-007/` | Recorded | 1 |
Task acceptance:
- [ ] Serverless total 18.00 is unchanged by loading summary/reference rows.
- [ ] Denying an optional detail source leaves money unchanged and lowers attribution coverage.
- [ ] No attribution model depends on another ledger or bridge model.

### FIN-008 — Implement directional transfer and replication charges
Release: R1 (transfer S01–S05, S08–S09) · R1\* (replication S06–S07, D-20) · Estimate: 24–36 h (transfer 16–24 h, replication 8–12 h) · Risk: M · Decisions: D-12, D-15 · Closes: —
Dependency changes: `−FIN-006` (no storage dependency), `+FIN-102`, `+FIN-103`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-008-S01 | Stage DATA_TRANSFER_HISTORY: BYTES_TRANSFERRED (VARIANT/NUMBER) → NUMBER(38,0) via TRY_TO_NUMBER, quarantining non-numeric values; direction = (source cloud/region → target cloud/region); TRANSFER_TYPE raw | `stg_au__data_transfer_history.sql` | "12e3" and "abc" fixtures: the first is parsed per contract rule, the second quarantined | 3 |
| FIN-008-S02 | Estimate: bytes / tb_unit × directional rate (rate key includes source and target region; TO VERIFY in FIN-108); missing rate → NULL + RATE_MISSING | estimator config | Two directions at 90.00 and 20.00 per TB give distinct amounts; a missing direction gives NULL | 3 |
| FIN-008-S03 | Authoritative DATA_TRANSFER family buckets from UICD (currency, not credits) | crosswalk | F-270 transfer 4.00 once | 1 |
| FIN-008-S04 | Attribution: bucket money → (transfer_type, direction) by bytes; REPLICATION-type transfer tagged `caused_by=REPLICATION` (link only) | `bridge_data_transfer.sql` | Σ = 4.00 exactly | 3 |
| FIN-008-S05 | Lint test: no model multiplies bytes by a credit rate (`native_unit=TB` requires a rate with unit TB) | `tests/no_bytes_times_credit_rate.sql` | Crafted bad model fails | 2 |
| FIN-008-S06 | (R1\*) Replication compute: REPLICATION family bucket; attribution from REPLICATION_GROUP_USAGE_HISTORY (current) and DATABASE_REPLICATION_USAGE_HISTORY (legacy), effective-dated authority (no union) | `bridge_replication.sql` | Overlap-day fixture counts once | 4 |
| FIN-008-S07 | (R1\*) Link replication groups to their transfer attribution rows; totals count transfer only in DATA_TRANSFER | same | Replication 6.00 + transfer 4.00 = 10.00, never 14.00 | 2 |
| FIN-008-S08 | NULL target metadata → UNATTRIBUTED transfer row | fixture | Explicit residual | 1 |
| FIN-008-S09 | Isolation, observability, evidence | `docs/evidence/FIN-008/` | Recorded | 2 |
Task acceptance:
- [ ] The transfer fixture is 4.00 USD once; bytes are never multiplied by a credit price.
- [ ] Replication compute and replication-caused transfer are distinguishable and never added twice.
- [ ] A missing directional rate leaves money NULL with a reason, while bytes remain visible.

### FIN-009 — Build reconciliation controls and financial health UX
Release: R1 · Estimate: 70–100 h · Risk: H · Decisions: D-02, D-12, D-13, D-22 · Closes: G-FIN-10, G-FIN-21 (route), G-FIN-25, G-FIN-26
Dependency changes: `−FIN-004`, `−FIN-018`, `−FIN-019`, `−FIN-020` (R1\* plug in by capability; they are not required edges); `+FIN-003`, `+FIN-101` (C5 references), `+FIN-104`, `+FIN-106`; keep FIN-005/006/007/008/021. Downstream: `API-001` and `ALC-001` should depend on FIN-001/FIN-102/FIN-103 instead of FIN-009.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-009-S01 | Author the control catalog (§3.4, C1–C9) with inputs, grain, tolerance expression, required flag, outcome mapping and classification enum (TIMING, TAX_SCOPE, CAPACITY_PURCHASE, RATE_MISMATCH, OVERAGE_PRICING, ADJUSTMENT, UNMAPPED_SERVICE, MISSING_SOURCE, MARKETPLACE_SEPARATE_INVOICE, OTHER) | `data/contracts/reconciliation/controls.yaml` + schema | Schema validation green; reviewer sign-off by FinOps | 3 |
| FIN-009-S02 | DDL `fct_reconciliation` (run_id, tenant, scope, period, currency, control_id, ledger_publication_id, reference_version, bucket_key/grain key, ledger_value, reference_value, delta, delta_abs, delta_rel, tolerance, status, classification, explanation_id) and `fct_reconciliation_run` | `data/dbt/models/reconciliation/_contracts.yml` | Contract tests; delta = ledger − reference asserted in a test | 3 |
| FIN-009-S03 | Implement C1 UNIT_TO_METERING (WMH/MH → MDH per account/day/service_type) | `ctl_c1_unit_to_metering.sql` | Injected 0.5 cr gap → FAILED; exact → MATCHED | 4 |
| FIN-009-S04 | Implement C2 METERING_TO_BILLING (MDH billed credits → UICD usage per family) | `ctl_c2_metering_to_billing.sql` | F-SUP-03 → FAILED with BILLING_MISSING; F-270 → MATCHED | 4 |
| FIN-009-S05 | Implement C3 RATED_METERING_TO_BILLED with auto-classification (OVERAGE_PRICING when balance_source overage explains Δ; ADJUSTMENT when IS_ADJUSTMENT rows explain Δ) | `ctl_c3_rated_to_billed.sql` | F-SUP-01: Δ = 200.00 − 210.00 = −10.00 auto-classified OVERAGE_PRICING → WARNING | 4 |
| FIN-009-S06 | Wire C4 from FIN-007 and C6 attribution conservation (exact) as a publication-blocking gate | `ctl_c4_*.sql`, `ctl_c6_attribution_conservation.sql` | A 1e-12 imbalance → FAILED and publication blocked | 2 |
| FIN-009-S07 | Implement C5 LEDGER_TO_INVOICE against approved FIN-101 references by line class; TAX and CAPACITY_PURCHASE listed out of scope; missing reference → PENDING | `ctl_c5_ledger_to_invoice.sql` | 270 vs 271 → −1.00 FAILED; no reference → PENDING; itemised reference with tax 54.00 → tax excluded, MATCHED on 270.00 | 5 |
| FIN-009-S08 | Implement C8 ESTIMATE_ACCURACY and C9 CLOSED_PERIOD_DRIFT (C9 creates correction cases for FIN-107) | `ctl_c8_*.sql`, `ctl_c9_*.sql` | F-REST-01 on 2026-10-15 creates CC-1 with Δ −1.00 | 3 |
| FIN-009-S09 | Read C7 allocation conservation from ALC outputs when enabled, else NOT_APPLICABLE with reason | `ctl_c7_*.sql` | Disabled ALC → NOT_APPLICABLE, not MATCHED | 1 |
| FIN-009-S10 | Period roll-up: RECONCILED per (period, publication) when all required controls are MATCHED or approved-WARNING; a newer revision reverts to FINAL | `fct_period_reconciliation_status.sql` | Revision after reconciliation → FINAL; closed statement unaffected | 3 |
| FIN-009-S11 | Explanation workflow in PG `finance.reconciliation_explanation` (classification, amount, evidence_file_id, author, approver ≠ author, status); explanations never write fct_charge (DB privileges: API role has no Snowflake ledger write) | `apps/api/finance/reconciliation/explanations.py`, migration | Author self-approval → 409 MAKER_CHECKER_VIOLATION; approved explanation turns FAILED into WARNING, never MATCHED | 4 |
| FIN-009-S12 | API endpoints: GET `/v1/reconciliation/periods/{period}` (scope, currency), GET `/v1/reconciliation/runs/{run_id}/controls`, POST `/v1/reconciliation/runs` (Idempotency-Key, async job), POST `/v1/reconciliation/differences/{id}/explanations` (If-Match), POST `…/explanations/{id}/approve`; money as JSON strings | `apps/api/finance/reconciliation/routes.py`, OpenAPI | Contract tests against OpenAPI; duplicate POST with the same key returns the same run_id | 5 |
| FIN-009-S13 | Authorization attacks: A1-limited reader requests org-scope C5 → 404 non-enumerating; foreign run_id → 404; stale permission epoch → 403; replayed signed cursor → 400; coverage % for A1-reader uses only authorized numerator and denominator | `tests/spec/FIN-009/security/` | All assertions pass; no foreign totals in any body | 3 |
| FIN-009-S14 | UX `/reconciliation` (FIN-009's `/govern/reconciliation` retired): per-control status table (no global green badge), per-currency tabs, delta labelled "Ledger − reference", period stability and maturity chips | `apps/web/src/features/finance/reconciliation/` | Playwright: F-270 vs 271 shows −1.00 FAILED; missing invoice shows PENDING | 6 |
| FIN-009-S15 | UX `/reconciliation-detail`: drilldown control → family → account → bucket → source batch and reference line; explanation form with evidence upload (FIN-101 storage) | same | Keyboard-only path completes; evidence link opens via the download broker | 6 |
| FIN-009-S16 | UX states: empty (no billing access / no reference), partial (C4 coverage), error (safe code + request ID), denied; 390 px and 200 % zoom | Playwright specs | All state snapshots and axe checks pass | 4 |
| FIN-009-S17 | Observability: `fin_recon_status_total{control,status}` (no tenant label); alarm on FAILED in a CLOSE_PREVIEWED or CLOSED period → RB-06 | alarms | Injected FAILED pages on-call in staging | 2 |
| FIN-009-S18 | Performance: 12 months × 20 accounts control run ≤ 2 min on the central warehouse (target TO VERIFY; record actual) | `tests/perf/FIN-009/` | Recorded runtime/credits | 2 |
| FIN-009-S19 | Evidence: 270 vs 271, replay stays 270, missing invoice PENDING, USD and EUR controls independent | `docs/evidence/FIN-009/` | All PASS | 2 |
Task acceptance:
- [ ] 270 vs 271 stays visible as −1.00 FAILED until an approved classified explanation makes it WARNING (never MATCHED).
- [ ] A duplicate or replayed run stays 270.00; a missing invoice is PENDING, not RECONCILED.
- [ ] Per-currency controls are independent; no USD+EUR aggregate exists.
- [ ] No control or explanation can write a balancing row to fct_charge.
- [ ] An account-limited principal cannot infer org-scope amounts from totals or percentages.

### FIN-010 — Implement period close, statements and financial evidence retention
Release: R1 · Estimate: 50–70 h · Risk: H · Decisions: D-05, D-11, D-04, D-25 · Closes: G-FIN-11, G-FIN-21 (close screen)
Dependency changes: keep FIN-009, SEC-006; `+FIN-106` (statement rounding), `+FIN-101` (reference pins), `+INF evidence bucket with S3 Object Lock` (INF backlog). Corrections and restatement move to new FIN-107. Downstream: `ALC-005` should depend on FIN-009, not FIN-010; ALC-008 keeps FIN-010.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-010-S01 | Write the period state machine (§3.5) and PG DDL `finance.financial_period`, `finance.period_close_request`, `finance.period_close` (pins JSONB + hashes), unique (tenant, org, period, currency, version), FORCE RLS | `data/contracts/finance/period_state_machine.md`, `apps/api/migrations/…_financial_period.sql` | Illegal transition (OPEN → CLOSED) rejected by a DB check or service guard test | 3 |
| FIN-010-S02 | Add capabilities `finance.period.close.request/approve` and `finance.period.restate.request/approve` to the SEC-005 catalog; maker ≠ checker enforced server-side (tenant policy `close_requires_second_approver`, default true) | SEC capability seed + policy | Same-user approve → 409 MAKER_CHECKER_VIOLATION | 3 |
| FIN-010-S03 | Precondition evaluator: STABLE (month_end + N d), required controls, coverage ≥ policy, no open correction case; returns an ordered remedy list | `apps/api/finance/close/preconditions.py` | Aug 2026 before 2026-09-06 → PERIOD_NOT_STABLE; C5 FAILED → CONTROL_BLOCKING with control ID | 4 |
| FIN-010-S04 | Preview: compute the freeze set (§3.5) and statement lines; store the preview (24 h expiry) | `apps/api/finance/close/preview.py` | Preview hash is deterministic for the same inputs | 4 |
| FIN-010-S05 | Statement generation: lines by family, account (org section separate) and currency using exact amounts + `round_statement_lines`; JSON, CSV and PDF (RPT renderer) with sha256 | `services/reporting/statements/financial_period.py` | F-270 statement: lines add to 270.00; org section 2.00; CSV formula-neutralized | 5 |
| FIN-010-S06 | Approve → CLOSED: one PG transaction writes the close record, then the idempotent D-04 insert into `ledger.fct_period_close`, then the S3 Object Lock upload; retry-safe ordering (upload key = close_id; PG state CLOSING_ARTIFACTS until all three confirm) | `apps/api/finance/close/approve.py` | Crash injected after PG commit resumes to CLOSED without a duplicate; duplicate approve returns the same record | 4 |
| FIN-010-S07 | Retention pins: pinned revisions are exempt from D-05 GC; D-11 purge keeps query-family aggregates of pinned periods | DBT-004 GC macro change + test | GC run leaves pinned revision; drilldown shows "detail expired" beyond the hot window | 3 |
| FIN-010-S08 | Race: a late billing revision between preview and approve → approve fails STALE_PREVIEW (pin hash mismatch) | test | Deterministic failure and re-preview works | 3 |
| FIN-010-S09 | Permission revocation during close: approver loses capability after opening the dialog → fresh durable check (SEC-006) rejects | test | 403 and audit event | 2 |
| FIN-010-S10 | Concurrency: two approvals in parallel → one CLOSED record (unique constraint); the loser gets the same close_id | test | Exactly one record | 2 |
| FIN-010-S11 | API: POST `/v1/periods/{period_id}/close-requests`, POST `/v1/close-requests/{id}/approve` and `/reject`, GET `/v1/periods/{period_id}`, GET `/v1/statements/{statement_id}` (download via broker); Idempotency-Key, If-Match | routes + OpenAPI | Contract tests pass | 4 |
| FIN-010-S12 | UX `/reconciliation-close` (new screen spec): precondition checklist with remedies, preview (lines, pins, controls), approve dialog showing requester and approver, closed version view with sha256 | `apps/web/src/features/finance/close/` | Playwright happy path and all states; 390 px | 6 |
| FIN-010-S13 | Security negative tests: Analyst close → 403; foreign period_id → 404; requester = approver → 409; stale If-Match → 412; statement download after revocation → 403 | `tests/spec/FIN-010/security/` | All pass | 2 |
| FIN-010-S14 | Audit events (request, approve, reject, pins, hashes) to the SEC audit stream; metric `fin_period_close_total{outcome}` | audit schema entries | Audit rows present for every transition | 2 |
| FIN-010-S15 | Runbook `financial-close.md` (blocked close, stale preview, artifact upload failure), then evidence | `docs/runbooks/financial-close.md`, `docs/evidence/FIN-010/` | Closed 270.00 statement re-downloads byte-identical (sha256) | 2 |
Task acceptance:
- [ ] The closed 270.00 statement remains 270.00 byte-identical after later corrections.
- [ ] Close requires two distinct authorized users (unless tenant policy explicitly disables it, which is audited).
- [ ] A duplicate close returns the same record; concurrent closes produce one record.
- [ ] Every pinned version listed in the freeze set is retrievable 13 months later (GC test).
- [ ] An unauthorized or revoked user cannot close or download.

### FIN-011 — Implement file Snowpipe and hidden pipe attribution
Release: R1 · Estimate: 12–18 h · Risk: L · Decisions: D-12 · Closes: G-FIN-17 (file)
Dependency changes: `+FIN-103`; keep FIN-002, DBT-005.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-011-S01 | Finalize the PIPE_USAGE_HISTORY contract: FLOAT/VARIANT BYTES_INSERTED and FILES_INSERTED → NUMBER(38,0) with quarantine on non-integral values; CREDITS_USED → NUMBER(38,12) | `stg_au__pipe_usage_history.sql` | 1.5 files → quarantine; "7" → 7 | 2 |
| FIN-011-S02 | Attribution: PIPE family money → pipes by CREDITS_USED; NULL PIPE_ID → HIDDEN_PIPE target (label Iceberg auto-refresh only when the source identifies it) | `bridge_pipe.sql` | F-270 pipe 5.00 = 3.00 + 1.50 + hidden 0.50 | 3 |
| FIN-011-S03 | Add an effective-dated `pricing_model` attribute (FILE_LEGACY before 2025-12-08, or 2025-08-01 for BC/VPS; PER_GB after); money never computed from files or bytes | seed `ref_pricing_model_history.csv` | Pre/post cutover fixture labels correct | 2 |
| FIN-011-S04 | Rename/recreate: stable PIPE_ID; recreated = new ID | fixture | Two IDs, same name | 1 |
| FIN-011-S05 | Duplicate batch replay and late correction of an interval | fixture | 5.00 stays 5.00; correction replaces | 1 |
| FIN-011-S06 | C4: Σ detail vs MDH PIPE credits | uses FIN-007 | 5.00 vs 5.00 MATCHED | 1 |
| FIN-011-S07 | Tenant isolation: identical PIPE_ID and PIPE_NAME in tenants A and B; A-reader limited to A1 cannot see A2 pipes | `tests/spec/FIN-011/isolation/` | Zero cross-tenant or cross-account rows | 1 |
| FIN-011-S08 | Observability (`fin_hidden_pipe_share`) and evidence | metric + `docs/evidence/FIN-011/` | Recorded | 1 |
Task acceptance:
- [ ] 5.00 USD attributed with an explicit hidden-pipe row; loading the summary does not increase the total.
- [ ] No money derives from file counts or bytes.
- [ ] Every row preserves source lineage (batch, revision).

### FIN-012 — Implement Snowpipe Streaming channel and client components
Release: R1\* (D-20) · Estimate: 17–26 h · Risk: M · Decisions: D-12 · Closes: G-FIN-17 (streaming), G-FIN-22 (fixture)
Dependency changes: `+FIN-103`; not a dependency of FIN-009.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-012-S01 | Detect architecture per pipe/channel (Classic vs high-performance) from verified source fields (TO VERIFY in FIN-108; document the probe) | `int_streaming__architecture.sql` | Mixed-architecture fixture classified | 3 |
| FIN-012-S02 | Classic: attribution of SNOWPIPE_STREAMING family money to client and channel components from SNOWPIPE_STREAMING_CLIENT_HISTORY / CHANNEL_HISTORY | `bridge_streaming.sql` | F-STREAM-05: compute 2.00 + client 3.00 = 5.00 | 4 |
| FIN-012-S03 | High-performance: attribution by ingested uncompressed GB per table/pipe (0.0037 cr/GB documented; source field TO VERIFY); money from the bucket only | same | HP fixture conserves bucket money | 3 |
| FIN-012-S04 | File-migration component (Classic) is not double counted against file Snowpipe | fixture | Totals once | 2 |
| FIN-012-S05 | Default pipe, renamed client, missing detail → UNATTRIBUTED | fixture | Explicit residual | 2 |
| FIN-012-S06 | Combined fixture F-270 + F-STREAM-05 = 275.00 | fixture | 275.00 | 1 |
| FIN-012-S07 | C4 detail vs MDH SNOWPIPE_STREAMING and tenant isolation (identical client names in A and B) | control + tests | MATCHED; zero cross-tenant rows | 1 |
| FIN-012-S08 | Evidence (staging on tenant zero if streaming exists, else NOT_RUN with reason) | `docs/evidence/FIN-012/` | Recorded | 1 |
Task acceptance:
- [ ] 2.00 + 3.00 = 5.00 for two proven distinct Classic components; HP pipes are attributed by GB.
- [ ] Summary/reference ingestion does not increase the charge; F-270 + stream = 275.00.

### FIN-013 — Implement serverless tasks and alerts
Release: R1 · Estimate: 14–22 h · Risk: L · Decisions: D-12 · Closes: —
Dependency changes: `+FIN-103`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-013-S01 | Stage SERVERLESS_TASK_HISTORY: CREDITS_USED VARCHAR → TRY_TO_DECIMAL(38,12); a failed parse quarantines the row (never NULL silently) | `stg_au__serverless_task_history.sql` | "1.2.3" quarantined; "0.000000001" exact | 2 |
| FIN-013-S02 | Attribution: SERVERLESS_TASK family money → task × instance × interval | `bridge_serverless_task.sql` | F-270 task 7.00 = 4.00 + 3.00 | 3 |
| FIN-013-S03 | Serverless alerts: verify source/service type (TO VERIFY); separate family SERVERLESS_ALERT | `bridge_serverless_alert.sql` | Alert fixture separate from tasks | 3 |
| FIN-013-S04 | Warehouse-executed tasks are never in serverless (their queries stay in FIN-003; WRK-004 links) | test | Warehouse task fixture absent from serverless bridge | 1 |
| FIN-013-S05 | Rerun instance, missing INSTANCE_ID, task recreated (new ID) | fixtures | Correct grain keys | 2 |
| FIN-013-S06 | C4 detail vs MDH SERVERLESS_TASK (and the alerts service type) | control | MATCHED on fixture; 6.50/7.00 → coverage 92.9 % | 1 |
| FIN-013-S07 | Tenant isolation: identical TASK_ID in tenants A and B; A1-reader cannot see A2 tasks | `tests/spec/FIN-013/isolation/` | Zero leakage | 1 |
| FIN-013-S08 | Observability (`fin_task_quarantined_rows`) and evidence | metric + `docs/evidence/FIN-013/` | Recorded | 1 |
Task acceptance:
- [ ] 7.00 USD task fixture; a malformed decimal is quarantined, not zero.
- [ ] Warehouse tasks never appear as serverless charges.

### FIN-014 — Implement automatic clustering
Release: R1 · Estimate: 10–14 h · Risk: L · Decisions: D-12 · Closes: —
Dependency changes: `+FIN-103`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-014-S01 | Stage AUTOMATIC_CLUSTERING_HISTORY with optional VERSION only after the probe | `stg_au__automatic_clustering_history.sql` | Missing VERSION column tolerated | 2 |
| FIN-014-S02 | Attribution: AUTO_CLUSTERING money → table ID × interval | `bridge_auto_clustering.sql` | F-270 2.00 conserved | 2 |
| FIN-014-S03 | Table rename keeps its ID; shared table name across schemas is not merged | fixture | Distinct IDs | 1 |
| FIN-014-S04 | Duplicate/late correction replay | fixture | Stable 2.00 | 1 |
| FIN-014-S05 | C4 detail vs MDH | control | MATCHED | 1 |
| FIN-014-S06 | Tenant isolation: identical TABLE_ID in tenants A and B | `tests/spec/FIN-014/isolation/` | Zero cross-tenant rows | 1 |
| FIN-014-S07 | Observability: coverage metric per family; alert on C4 FAILED | alarm | Fires on the 19/18 fixture | 1 |
| FIN-014-S08 | Evidence | `docs/evidence/FIN-014/` | Recorded | 1 |
Task acceptance:
- [ ] 2.00 conserved; the summary does not add; stable table identity through rename.

### FIN-015 — Implement search optimization
Release: R1 · Estimate: 10–14 h · Risk: L · Decisions: D-12 · Closes: —
Dependency changes: `+FIN-103`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-015-S01 | Stage SEARCH_OPTIMIZATION_HISTORY (table, interval, credits) | `stg_au__search_optimization_history.sql` | Types asserted | 2 |
| FIN-015-S02 | Attribution: SEARCH_OPTIMIZATION money → table × interval; hidden/unknown table → UNATTRIBUTED | `bridge_search_optimization.sql` | 2.00 conserved | 2 |
| FIN-015-S03 | Keep maintenance cost separate from benefit evidence: no "saving" column in FIN models (INS owns benefit) | lint | Crafted column rejected | 1 |
| FIN-015-S04 | Stale table metadata / dropped table handling | fixture | Stable ID | 1 |
| FIN-015-S05 | C4, replay | control + fixture | MATCHED; stable | 1 |
| FIN-015-S06 | Tenant isolation: identical table IDs in tenants A and B | `tests/spec/FIN-015/isolation/` | Zero cross-tenant rows | 1 |
| FIN-015-S07 | Observability: coverage metric; alert on C4 FAILED | alarm | Fires on fixture | 1 |
| FIN-015-S08 | Evidence | `docs/evidence/FIN-015/` | Recorded | 1 |
Task acceptance:
- [ ] 2.00 conserved; estimated benefit never presented as realized saving.

### FIN-016 — Implement materialized view maintenance
Release: R1 · Estimate: 10–14 h · Risk: L · Decisions: D-12 · Closes: —
Dependency changes: `+FIN-103`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-016-S01 | Stage MATERIALIZED_VIEW_REFRESH_HISTORY | `stg_au__materialized_view_refresh_history.sql` | Types asserted | 2 |
| FIN-016-S02 | Attribution: MATERIALIZED_VIEW money → view ID × interval; unavailable view ID → UNATTRIBUTED | `bridge_materialized_view.sql` | 2.00 conserved | 2 |
| FIN-016-S03 | Queries reading the view stay warehouse workload (no join from FIN-003 into this bridge) | graph test | Independence holds | 1 |
| FIN-016-S04 | Drop/recreate and maintenance failure rows | fixture | New ID on recreate; failure rows keep credits | 1 |
| FIN-016-S05 | C4, replay | control | MATCHED | 1 |
| FIN-016-S06 | Tenant isolation: identical view IDs in tenants A and B | `tests/spec/FIN-016/isolation/` | Zero cross-tenant rows | 1 |
| FIN-016-S07 | Observability: coverage metric; alert on C4 FAILED | alarm | Fires on fixture | 1 |
| FIN-016-S08 | Evidence | `docs/evidence/FIN-016/` | Recorded | 1 |
Task acceptance:
- [ ] 2.00 conserved; view reads are never charged as MV maintenance.

### FIN-017 — Implement query acceleration
Release: R1\* (D-20) · Estimate: 12–18 h · Risk: L · Decisions: D-12, D-14 · Closes: —
Dependency changes: `+FIN-103`, `+FIN-003` (QAH proration shared macro); not a dependency of FIN-009.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-017-S01 | Stage QUERY_ACCELERATION_HISTORY (warehouse × interval credits) | `stg_au__query_acceleration_history.sql` | Types asserted | 2 |
| FIN-017-S02 | Attribution level 1: QUERY_ACCELERATION money → warehouse × interval | `bridge_qas_warehouse.sql` | 3.00 conserved | 2 |
| FIN-017-S03 | Attribution level 2: QAH.CREDITS_USED_QUERY_ACCELERATION → queries (prorated per D-14); remainder UNATTRIBUTED | `bridge_qas_query.sql` | 3.00 = 2.00 query + 1.00 unattributed | 3 |
| FIN-017-S04 | Guard: QAH QAS credits never added to WAREHOUSE_COMPUTE or to the QAS charge | test | Total stays 3.00 | 1 |
| FIN-017-S05 | Optional source denied → money unchanged, coverage 0 % | fixture | 3.00 stays | 1 |
| FIN-017-S06 | Cross-day query: QAS credits prorated across UTC days with the FIN-003 macro | fixture | 23:30–01:30 query splits 0.25/0.75 of its QAS credits by day | 1 |
| FIN-017-S07 | C4 detail vs MDH QUERY_ACCELERATION; tenant isolation on query_id | control + tests | MATCHED; zero cross-tenant rows | 1 |
| FIN-017-S08 | Evidence | `docs/evidence/FIN-017/` | Recorded | 1 |
Task acceptance:
- [ ] 3.00 service total with 2.00 query detail and 1.00 unattributed; QAS is not billed twice.

### FIN-018 — Implement current Cortex services and non-overlapping AI attribution
Release: R1\* (D-20) · Estimate: 36–54 h · Risk: H · Decisions: D-12, D-20 · Closes: G-FIN-06, G-FIN-22 (AI fixture)
Dependency changes: `+FIN-103`, `+FIN-108` (live source inventory); not a dependency of FIN-009.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-018-S01 | Inventory the Cortex/AI sources present in the account (AI_FUNCTIONS, AISQL, retired FUNCTIONS, SEARCH_SERVING, ANALYST, AGENT, document processing, Intelligence, AI Gateway preview) with first/last row dates; record in the capability probe | `data/contracts/cortex-authority.json`, CON-005 probe extension | Probe output lists each source with AVAILABLE/EMPTY/DENIED | 3 |
| FIN-018-S02 | Effective-dated authority chain for function usage: CORTEX_FUNCTIONS_USAGE_HISTORY (history only) → CORTEX_AISQL_USAGE_HISTORY (≤ 2026-01-04) → CORTEX_AI_FUNCTIONS_USAGE_HISTORY (≥ 2026-01-05) | registry entries + `int_cortex__function_usage.sql` | Overlap-day fixture counts once | 4 |
| FIN-018-S03 | Stage CORTEX_AI_FUNCTIONS_USAGE_HISTORY (hourly aggregates; function, model, tokens, credits; custom-function attribution fields as verified) | `stg_au__cortex_ai_functions_usage_history.sql` | Types asserted; tokens NUMBER(38,0) | 3 |
| FIN-018-S04 | Stage Search serving, Analyst and Agent usage as separate attribution sets | `stg_au__cortex_*.sql` | Contract tests | 4 |
| FIN-018-S05 | Attribution: AI_SERVICES family money → (feature, function/model, hour) by credits; residual UNATTRIBUTED | `bridge_ai_services.sql` | F-270 Cortex 6.00 conserved | 4 |
| FIN-018-S06 | Parent/child exclusion: agent totals include tool calls; child detail is linked under the parent edge and never added | same | F-AI-10: parent 10.00 + child detail 4.00 → 10.00 (residual 6.00) | 4 |
| FIN-018-S07 | Warehouse credits of the SQL query calling AI functions stay WAREHOUSE_COMPUTE (test on query_id) | test | No warehouse credits in AI metric | 2 |
| FIN-018-S08 | Source staleness: a view that stops updating while credits appear in MDH AI_SERVICES → coverage gap + health warning (not healthy ingestion) | health rule | Stale fixture shows gap, money unchanged | 2 |
| FIN-018-S09 | Unknown new AI feature (e.g. AI Gateway) → UNATTRIBUTED within AI_SERVICES, and UNMAPPED if in a new service_type | fixture | Counted once | 2 |
| FIN-018-S10 | Non-token functions (e.g. per-page document processing) keep native units; no token×price formula | test | Units preserved | 2 |
| FIN-018-S11 | Isolation, observability, evidence | tests + evidence | Recorded | 3 |
Task acceptance:
- [ ] Parent 10 + child detail 4 remains 10; AISQL/AI_FUNCTIONS overlap counts once.
- [ ] Missing or stale sources show a visible coverage gap while money is unchanged.
- [ ] No warehouse credits appear in the AI metric.

### FIN-019 — Implement SPCS compute-pool and application attribution
Release: R1\* (D-20) · Estimate: 22–32 h · Risk: M · Decisions: D-12 · Closes: —
Dependency changes: `+FIN-103`; not a dependency of FIN-009 or FIN-020.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-019-S01 | Stage SNOWPARK_CONTAINER_SERVICES_HISTORY (pool ID/name, IS_EXCLUSIVE, APPLICATION_ID/NAME, hourly CREDITS_USED) | `stg_au__spcs_history.sql` | Types asserted | 2 |
| FIN-019-S02 | Verify in FIN-108 whether SPCS block storage and data transfer are separate rating types; map in crosswalk | crosswalk rows | Evidence linked | 2 |
| FIN-019-S03 | Attribution level 1: SPCS money → pool × hour | `bridge_spcs_pool.sql` | Pool 8.00 once | 3 |
| FIN-019-S04 | Attribution level 2: pool-hour → services/apps when service-level telemetry capability exists; else the pool is the leaf | `bridge_spcs_service.sql` | Two services 5.00 + 3.00 = 8.00; no telemetry → pool only | 4 |
| FIN-019-S05 | Exclusive app pool maps wholly to the app; deleted app IDs retained | fixture | App deleted: history kept | 2 |
| FIN-019-S06 | Utilization and idle are never inferred from credits (lint: no `idle` column without the telemetry source) | test | Crafted column rejected | 1 |
| FIN-019-S07 | Pool renamed/deleted, missing hourly row → UNATTRIBUTED | fixtures | Explicit residual | 2 |
| FIN-019-S08 | C4, isolation, evidence | tests + evidence | Recorded | 3 |
Task acceptance:
- [ ] Pool 8.00 is charged once despite two services; app association does not create another 8.00.
- [ ] Idle/utilization show "unavailable" without telemetry.

### FIN-020 — Implement marketplace purchase and native-app cost separation
Release: R1\* (D-20) · Estimate: 20–30 h · Risk: M · Decisions: D-12 · Closes: G-FIN-05
Dependency changes: `−FIN-019` (optional link only), `+FIN-103`, `+FIN-108` (MCD/UICD evidence), `+ING-001` (correct schema DATA_SHARING_USAGE).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-020-S01 | Correct the source contract: consumer MARKETPLACE_PAID_USAGE_DAILY in SNOWFLAKE.DATA_SHARING_USAGE (48 h latency, 365 d); provider MONETIZED_USAGE_DAILY and disbursement views blocked as CHARGE | ING-001 contract PR + registry validator | Validator rejects a provider view as CHARGE | 2 |
| FIN-020-S02 | Authority rule per (org, month): UICD marketplace rows present → CHARGE = UICD and MPUD = attribution; else MPUD = CHARGE with `billing_channel=SEPARATE_INVOICE` | `int_charge__marketplace.sql` | F-MKT-01 MCD month: fee 10.00 once (not 20.00); card month: 10.00 from MPUD | 4 |
| FIN-020-S03 | Separate-invoice charges are excluded from C2/C3 and compared in C5 against a MARKETPLACE_INVOICE reference | control config | Separate-invoice month shows C5 with a marketplace reference line | 2 |
| FIN-020-S04 | APPLICATION_DAILY_USAGE_HISTORY → non-additive links from app to warehouse/serverless/SPCS charge IDs | `bridge_native_app_consumption.sql` | Fee 10 + pool 8 = 18, not 26 | 4 |
| FIN-020-S05 | Listing ID change and currency mismatch (listing priced in a different currency → separate currency bucket) | fixtures | No FX; separate totals | 2 |
| FIN-020-S06 | No marketplace access → limited fee coverage message; money = UICD rows only | fixture | Coverage reason shown | 2 |
| FIN-020-S07 | Tenant isolation: identical LISTING_GLOBAL_NAME in tenants A and B; org-scope marketplace rows hidden from A1-reader | `tests/spec/FIN-020/isolation/` | Zero leakage | 2 |
| FIN-020-S08 | Evidence (tenant zero or design partner; else NOT_RUN with reason) | `docs/evidence/FIN-020/` | Recorded | 1 |
Task acceptance:
- [ ] Fee 10 + pool 8 = 18, not 26; provider revenue 100 contributes 0.
- [ ] A capacity-drawdown purchase is never counted in both UICD and MPUD.

### FIN-021 — Cover new billable services, organization fees and unmapped spend
Release: R1 · Estimate: 24–36 h · Risk: M · Decisions: D-01, D-12, D-15 · Closes: G-FIN-22 (oracle), G-FIN-25 (org scope)
Dependency changes: `+FIN-108` (observed tuple inventory); keep FIN-002.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-021-S01 | Discovery model: distinct observed UICD tuples and MDH service types per tenant/day vs crosswalk version → `mapping_work_item` rows (NEW_TUPLE, UNIT_CHANGED, DISAPPEARED) | `int_crosswalk__discovery.sql` | Novel tuple creates one work item, idempotent on rerun | 3 |
| FIN-021-S02 | Generic normalizer: an unmapped tuple becomes UNMAPPED_BILLABLE_SERVICE with raw tuple and signed amount; never dropped or zeroed | `int_charge__authoritative` branch | Novel 9.00 visible once | 2 |
| FIN-021-S03 | Organization fees (ACCOUNT NULL): scope ORGANIZATION; D-15 default target PLATFORM_SHARED in the seeded book | seed for ALC default book | Support 5.00 org scope | 2 |
| FIN-021-S04 | Known families without a detail adapter (Openflow, telemetry, data quality/classification, private connectivity, archive/backups, Snowflake Postgres, historic hybrid requests): crosswalk rows with `detail_adapter=NONE` | crosswalk | Each maps to a named family with attribution coverage 0 % | 3 |
| FIN-021-S05 | Unit change detection: the same service_type changes native_unit → work item + WARNING; money kept | fixture | Warning raised | 2 |
| FIN-021-S06 | Duplicate mapping protection: the crosswalk source tuple is unique per version | test | Duplicate fails CI | 1 |
| FIN-021-S07 | Oracle fixture: account baseline 268.00 + support 5.00 − rebate 3.00 + novel 9.00 = 279.00; attribution warning stays open | fixture | 279.00 (never 281.00) | 2 |
| FIN-021-S08 | Org-scope visibility: A1-reader sees neither the org fee rows nor unconnected-account rows, nor any total or percentage derived from them | security test | 404/filtered; no derivable totals | 3 |
| FIN-021-S09 | Mapping-work UX hook: Data Health lists unmapped tuples with amount and first-seen date (surface via ING-012 page) | API field `unmapped_services[]` | Visible in Data Health | 2 |
| FIN-021-S10 | Observability: `fin_unmapped_amount` per currency (tenant in logs), alarm when unmapped > 0 for 7 days | alarm | Fires on fixture | 1 |
| FIN-021-S11 | Evidence | `docs/evidence/FIN-021/` | Recorded | 2 |
Task acceptance:
- [ ] 5 − 3 + 9 = 11, and the org total with the novel service is 279.00.
- [ ] A missing account stays organization-scoped; an unknown service is counted once and never shown as reconciled resource detail.
- [ ] Account-limited users cannot derive org-scope amounts.

## 5. New tasks required

### FIN-101 — Billing reference intake: usage statements, invoices and manual totals
Release: R1 · Estimate: 45–65 h · Risk: H · Decisions: D-04, D-10, D-25 · Closes: G-FIN-09, G-FIN-21 (reference screen)
Why: control C5 (LEDGER_TO_INVOICE) is required to close and is impossible without an approved, versioned, independent reference (AUDIT X-47).
Plugs in: after FIN-001 (reference schema) and CTL/SEC foundations; before FIN-009-S07 and FIN-010. Dependencies: `FIN-001`, `CTL-005`, `SEC-005`, `SEC-006`, INF evidence bucket (KMS + Object Lock), `RPT` download broker.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-101-S01 | Define the reference model: `finance.billing_reference` (id, tenant, org, contract_number, reference_type SNOWFLAKE_USAGE_STATEMENT, SNOWFLAKE_INVOICE, RESELLER_INVOICE, MARKETPLACE_INVOICE or MANUAL_TOTALS, document_number, period YYYY-MM, currency, status, version, supersedes_id, file sha256) and `finance.billing_reference_line` (line_class CONSUMPTION, TAX, CAPACITY_PURCHASE, SUPPORT, CREDIT_NOTE, ADJUSTMENT, MARKETPLACE or OTHER; service_family NULLable; account_locator NULLable; amount as decimal string → NUMERIC(38,12)) | migration + `data/contracts/finance/billing_reference.schema.json` | Schema rejects float amounts, unknown line_class and currency not in ISO 4217 | 3 |
| FIN-101-S02 | Build the upload path: POST init → presigned PUT to `s3://<evidence>/tenants/{tenant_id}/finance/references/{reference_id}/v{n}/original.{pdf,csv}` (SSE-KMS tenant key, Object Lock governance until approved, then compliance); 20 MiB limit; content-type sniffing (PDF magic `%PDF`, CSV UTF-8) | `apps/api/finance/references/upload.py`, IAM prefix policy | Foreign-tenant prefix PUT denied by IAM (test); a 21 MiB file is rejected | 4 |
| FIN-101-S03 | Malware scanning before the reference can be submitted (GuardDuty Malware Protection for S3 or ClamAV task; availability in region TO VERIFY); PDFs are never rendered server-side in R1 | scan hook + status `SCAN_PENDING/CLEAN/INFECTED` | EICAR test file → INFECTED and blocked | 3 |
| FIN-101-S04 | CSV parser for the Snowflake monthly usage statement (column mapping versioned; format TO VERIFY LIVE in FIN-108), with preview: parsed lines, totals, unmapped columns; parse errors carry line numbers | `apps/api/finance/references/parsers/snowflake_usage_statement.py` | Tenant-zero statement parses; total equals the statement PDF total; malformed row → line-level error | 5 |
| FIN-101-S05 | Manual line entry (for PDFs, reseller invoices and totals-only): per-line classification, decimal-string validation, sign rules (CREDIT_NOTE negative), document total check (Σ lines = declared total, exact) | API + validators | Σ mismatch 0.01 → 422 `REFERENCE_TOTAL_MISMATCH` | 3 |
| FIN-101-S06 | Lifecycle: DRAFT → SUBMITTED → APPROVED (approver ≠ submitter, capability `finance.reference.approve`) → ACTIVE; REJECTED; SUPERSEDED by version n+1. Duplicate guard on (tenant, org, reference_type, document_number, period) and on file sha256 | `apps/api/finance/references/lifecycle.py` | Same document twice → 409 `REFERENCE_DUPLICATE`; self-approval → 409 | 4 |
| FIN-101-S07 | Publish approved versions immutably to Snowflake `fct_billing_reference` / `fct_billing_reference_line` via the D-04 config publisher (insert-only keyed by reference_id+version) | publisher job + dbt source | Re-publish is idempotent; a superseded version stays queryable | 3 |
| FIN-101-S08 | API: POST `/v1/billing-references` (init), PUT `…/{id}/lines`, POST `…/{id}/submit`, POST `…/{id}/approve`, POST `…/{id}/reject`, GET list/detail, GET `…/{id}/file` (download broker, short-lived URL); Idempotency-Key + If-Match | routes + OpenAPI | Contract tests; stale If-Match → 412 | 4 |
| FIN-101-S09 | UX `/reconciliation-references` (new screen spec): list by period/org/currency, upload and preview, line editor, submit/approve with actors, version history, link to C5 | `apps/web/src/features/finance/references/` | Playwright happy path, all states, 390 px, keyboard-only | 7 |
| FIN-101-S10 | Security tests: foreign reference_id → 404; A1-reader cannot list org references (org-scope capability required); presigned URL for tenant B file from tenant A session → 403; CSV formula neutralization on export (`=HYPERLINK(` becomes a text cell) | `tests/spec/FIN-101/security/` | All pass | 3 |
| FIN-101-S11 | Retention and privacy: references are kept for the financial retention period (owner Q7); personal data (names in PDFs) is covered by the D-10 erasure exception register; deletion requires the legal-hold check | policy doc + retention job config | Deletion attempt under hold → refused and audited | 2 |
| FIN-101-S12 | Audit events for every lifecycle transition; metric `fin_reference_status_total{status}` | audit entries | Present for every transition in the test run | 1 |
| FIN-101-S13 | Evidence: tenant-zero usage statement imported, approved and matched by C5 | `docs/evidence/FIN-101/` | C5 MATCHED within one minor unit, or a classified difference recorded | 2 |
Task acceptance:
- [ ] An approved usage statement for a period makes C5 computable; a missing reference leaves C5 PENDING.
- [ ] No reference is used before a second authorized user approves it; duplicates are rejected.
- [ ] Files are tenant-prefixed, encrypted, scanned and immutable after approval.
- [ ] TAX and CAPACITY_PURCHASE lines are excluded from the consumption comparison and shown separately.

### FIN-102 — Provisional estimator and family-bucket supersession engine (D-12 core)
Release: R1 · Estimate: 36–52 h · Risk: H · Decisions: D-12 (amended), D-13, D-24 · Closes: G-FIN-01, G-FIN-18, G-FIN-20 (estimate side)
Why: a single estimator replaces ten per-service pricing implementations and makes supersession deterministic.
Plugs in: after FIN-001, FIN-002, FIN-104; before FIN-003…FIN-021 and API-001 (metric registry can bind to `fct_charge` early). Dependencies: `FIN-001`, `FIN-002`, `FIN-104`, `DBT-004`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-102-S01 | Estimator source precedence per (account, day): MDH complete day (after MDH FINAL horizon) > MH hourly partial (`complete_through` = last complete hour) | `int_estimate__credits_family_day.sql` | Today partial fixture: complete_through 13:00Z from MH; yesterday from MDH | 4 |
| FIN-102-S02 | Map MDH/MH service types to service_family via the crosswalk; unknown → UNMAPPED | same | Unknown type visible | 2 |
| FIN-102-S03 | Rate the credit families with `select_rate()` (RATE_SHEET or CUSTOMER_APPROVED); non-credit families (storage, transfer) are priced by the FIN-006/FIN-008 estimator configs | `int_estimate__priced.sql` | F-SUP-01 estimate 200.00; missing rate → NULL + reason | 4 |
| FIN-102-S04 | Emit estimate rows at family-bucket grain into `fct_charge` candidates (basis_class EST, price_basis CONTRACT_RATE_ESTIMATE or CUSTOMER_APPROVED_RATE, data_status PROVISIONAL) | `int_charge__estimate.sql` | Contract tests green | 3 |
| FIN-102-S05 | Supersession resolver implementing the 8-case table (§3.1) using UICD snapshot maturity from FIN-104 | `int_charge__active.sql` | F-SUP-01/02/03 produce the expected actives exactly | 5 |
| FIN-102-S06 | Write the supersession audit table `fct_charge_supersession` (estimate charge_row_id, superseding family bucket, snapshot revision, timestamp) | model | Every inactive estimate has exactly one audit row | 2 |
| FIN-102-S07 | Publication: `fct_charge` = active rows only; ledger family views `ledger_<family>` as thin filters for PRD traceability | `fct_charge.sql`, `ledger_*.sql` | No row appears in two family views; Σ families = Σ fct_charge | 3 |
| FIN-102-S08 | Late billing for an already-superseded family and estimate re-activation when a UICD snapshot revision removes rows (case 5 → 7) | fixtures | Estimate reappears with BILLING_MISSING | 3 |
| FIN-102-S09 | Incremental/full-rebuild parity for the resolver (DBT-004) on 60 days of fixture data | parity test | Identical checksums | 3 |
| FIN-102-S10 | "Current through" metadata for D-24: per tenant/account `money_complete_through`, `billing_complete_through` exposed to the semantic API | `fct_ledger_freshness.sql` | API meta fields populated | 2 |
| FIN-102-S11 | Isolation: estimator never uses another tenant's rate or snapshot | test | Zero cross-tenant joins | 2 |
| FIN-102-S12 | Observability: `fin_estimate_share_of_spend` (open month), `fin_billing_missing_buckets`; alarm on BILLING_MISSING > 0 after maturity | alarms | Fires on F-SUP-03 | 2 |
| FIN-102-S13 | Evidence | `docs/evidence/FIN-102/` | Recorded | 1 |
Task acceptance:
- [ ] Estimate 200.00 followed by authoritative 160.00 + 50.00 gives 210.00, never 410.00, with an audit row.
- [ ] A late family is not dropped before maturity; missing billing after maturity keeps the estimate and FAILs C2.
- [ ] Incremental and full rebuild produce identical active sets.

### FIN-103 — Exact attribution framework (allocate_exact, residual kinds, bridge conventions)
Release: R1 · Estimate: 26–40 h · Risk: M · Decisions: D-12, D-14, D-15 · Closes: G-FIN-03
Why: every attribution model needs the same exact conservation; implementing it once removes a class of reconciliation defects.
Plugs in: after FIN-001 and FIN-106; before all service tasks and ALC-005. Dependencies: `FIN-001`, `FIN-106`, `DBT-005`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-103-S01 | Implement the dbt macro `allocate_exact(parent_money_col, weight_col, partition_by, order_key)`: floor toward zero at 1e-12, signed largest remainder, ties by order_key | `data/dbt/macros/allocate_exact.sql` | 1.00 over 3 equal weights → 0.333333333334/0.333333333333/0.333333333333 | 4 |
| FIN-103-S02 | Python reference implementation in `bridge_money` and a property test: 10,000 random parents (positive, negative, zero) and weights; Σ = parent exactly; SQL vs Python parity | `packages/bridge_money/allocate.py`, `tests/property/test_allocate.py` | 0 mismatches | 4 |
| FIN-103-S03 | Coverage split macro `split_coverage(parent, detail_qty, bucket_qty)` → DETAIL and UNATTRIBUTED; detail > bucket → OVER_ATTRIBUTED flag with normalization | macro | Detail 70/100 → 70 % / 30 %; 110/100 → flag + 100 % | 3 |
| FIN-103-S04 | Zero-weight and NULL-weight rules: Σw = 0 → whole parent UNATTRIBUTED; NULL weight rows excluded and counted in `null_weight_rows` | macro + tests | Fixture outcomes as stated | 2 |
| FIN-103-S05 | Bridge schema conventions: every bridge model has charge_row_id, attribution_set, residual kind, attribution_status, source lineage; generic test `bridge_conserves_parent` (exact) | `data/dbt/tests/generic/bridge_conserves_parent.sql` | Deliberate 1e-12 leak fails | 3 |
| FIN-103-S06 | Hierarchical attribution helper (parent → level-1 → level-2) preserving conservation at each level (used by FIN-003 hour→query and FIN-019 pool→service) | macro | Two-level fixture conserves at both levels | 3 |
| FIN-103-S07 | Display effective rate: `display_rate = money / quantity` for UI only, with a lint rule that forbids multiplying `display_rate` back in models | lint test | Crafted misuse fails CI | 2 |
| FIN-103-S08 | Performance: allocate 50 M bridge rows per month on the central warehouse; record runtime/credits (target TO VERIFY) | `tests/perf/FIN-103/` | Recorded | 3 |
| FIN-103-S09 | Documentation of residual kinds and their UX labels (Unattributed, Idle, Proration residual, Over-attributed, Hidden resource) for API/UX | `data/contracts/ledger/residual_kinds.md` | Linked by API-001 registry | 1 |
| FIN-103-S10 | Evidence | `docs/evidence/FIN-103/` | Property tests green | 1 |
Task acceptance:
- [ ] Σ children = parent exactly (0 difference) on property tests and on all fixture bridges.
- [ ] Residual kinds are always explicit rows, never absorbed into a child.
- [ ] Python and SQL implementations agree bit-for-bit.

### FIN-104 — Maturity policy registry and status evaluator (D-13)
Release: R1 · Estimate: 24–36 h · Risk: M · Decisions: D-13 · Closes: G-FIN-08
Why: FINAL/STABLE need numbers and a single evaluator used by ledger, monitors (GOV-004) and close.
Plugs in: after FIN-001 and ING-001; before FIN-002/102/003/009/010 and GOV-004. Dependencies: `FIN-001`, `ING-001`, `ING-009` (contiguous coverage).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-104-S01 | Seed `ref_source_maturity_policy` v0 from §3.3 (source, data_horizon, attribution_horizon, stability_days N, anti-entropy window, evidence link) | `data/dbt/seeds/ref_source_maturity_policy.csv` | Seed loads; each enabled source has a row (test) | 2 |
| FIN-104-S02 | Per-tenant overrides (versioned; only stricter or evidence-backed looser values), stored in PG and published via D-04 | migration + publisher | Override older than evidence rejected | 3 |
| FIN-104-S03 | Evaluator macro `data_status_for(source, interval_end, now, coverage_ok)` → PROVISIONAL or FINAL; `period_stability_for(month, now)` → OPEN or STABLE | `data/dbt/macros/maturity.sql` | Aug 2026: OPEN at 2026-09-05T23:59Z, STABLE at 2026-09-06T00:00Z | 3 |
| FIN-104-S04 | Attribution horizon with T = min(account max STATEMENT_TIMEOUT (from capability probe; default 48 h), 48 h) | macro + probe field | Account with 1 h timeout → horizon 25 h; default → 72 h | 3 |
| FIN-104-S05 | Contiguous-coverage guard: FINAL only if the source window is covered without gaps (ADR-006) | macro joins coverage table | Gap fixture stays PROVISIONAL after the horizon | 2 |
| FIN-104-S06 | Measured lateness telemetry: per source, observed (row arrival − interval end) p50/p95/max and last-revision lag per month | `fct_source_lateness.sql` | Populated from tenant-zero data | 3 |
| FIN-104-S07 | Policy-revision workflow: a proposed v1 from measured lateness (max observed + margin) requires FinOps approval; it never weakens close evidence | runbook + PR template | v1 proposal generated from FIN-108 data | 2 |
| FIN-104-S08 | Expose `data_status`, `period_stability`, `maturity_policy_version` in semantic API meta and in exports | API-001 registry fields | Response meta fields present | 2 |
| FIN-104-S09 | Tests: late row after FINAL creates a new revision and the status stays FINAL (a revision, not a regression); monitors reading FINAL see revision IDs | tests | Pass | 2 |
| FIN-104-S10 | Evidence | `docs/evidence/FIN-104/` | Recorded | 1 |
Task acceptance:
- [ ] Every enabled source has numeric horizons; FINAL is time-bound and coverage-bound.
- [ ] Month stability flips at month_end + N days (default 5) and is recorded per period.
- [ ] Attribution horizons reflect the statement-timeout cap.

### FIN-105 — Customer-approved rate tables (reseller / no-billing-access tenants)
Release: R1 · Estimate: 30–44 h · Risk: M · Decisions: D-04, D-20 · Closes: G-FIN-13, G-FIN-21 (pricing screen)
Why: tenants without OU billing access (resellers, refused org grants) otherwise have no money at all.
Plugs in: after FIN-002; before FIN-102 is DONE for such tenants; before ONB-004. Dependencies: `FIN-002`, `CTL-005`, `SEC-005`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-105-S01 | Model PG `finance.rate_table` (id, tenant, org, name, currency, source_document_ref, status, version, effective_from/to) and `finance.rate_table_line` (service_family or service_type, rating_type NULLable, region NULLable, unit CREDIT/TB_MONTH/TB, rate decimal string, tb_unit) | migration + schema | Float rate rejected; overlapping effective periods for the same key rejected | 3 |
| FIN-105-S02 | CSV import with preview (row errors with line numbers) and manual entry | `apps/api/finance/pricing/import.py` | Malformed "2,91" (comma decimal) → error unless locale is declared | 3 |
| FIN-105-S03 | Lifecycle DRAFT → SUBMITTED → APPROVED (approver ≠ submitter; `finance.pricing.approve`) → ACTIVE, with SUPERSEDED; approval requires an evidence file (contract excerpt) via FIN-101 storage | lifecycle module | Self-approval → 409 | 3 |
| FIN-105-S04 | Publish approved versions to `fct_rate` with rate_source CUSTOMER_APPROVED via the D-04 publisher | publisher | Idempotent | 2 |
| FIN-105-S05 | API: POST `/v1/pricing/rate-tables`, PUT `…/{id}/lines`, POST `…/{id}/simulate`, POST `…/{id}/submit`, `…/approve`, GET list/detail | routes + OpenAPI | Contract tests pass | 4 |
| FIN-105-S06 | Simulation: apply the draft to the last 30 days of credits and show deltas vs the current basis (and vs RATE_SHEET when available), written to the D-04 `simulation_input` schema, never to published tables | `simulation_input` model | Simulation leaves published fct_charge unchanged (checksum) | 4 |
| FIN-105-S07 | Guard: approved rates never produce price_basis BILLED_SOURCE; UI labels "Estimated with approved contract rate" | tests | Label present; basis asserted | 1 |
| FIN-105-S08 | UX `/settings-pricing` (new screen spec): active basis per org (billing source, approved table or none), import, simulate, approve and supersede; empty state explains credits-only mode | `apps/web/src/features/finance/pricing/` | Playwright states; 390 px | 6 |
| FIN-105-S09 | Security: Analyst import → 403; foreign rate_table id → 404; stale If-Match → 412; demo provenance cannot be selected in production tenants | tests | All pass | 2 |
| FIN-105-S10 | Audit and metric `fin_rate_table_changes_total`; runbook "customer rate table dispute" | audit + runbook | Present | 1 |
| FIN-105-S11 | Evidence: reseller fixture priced, simulated and approved | `docs/evidence/FIN-105/` | Recorded | 1 |
Task acceptance:
- [ ] A no-OU tenant gets money from an approved table, labelled as an estimate, with maker-checker approval and evidence.
- [ ] Simulation never mutates published facts.
- [ ] Overlapping or ambiguous rate lines are rejected before approval.

### FIN-106 — Money library, JSON money contract and statement rounding
Release: R1 · Estimate: 16–24 h · Risk: M · Decisions: D-18 (formatting) · Closes: G-FIN-19
Why: one shared definition of exact arithmetic across Python, SQL, API and UI.
Plugs in: phase P0 (no dependency except FND-002 monorepo); consumed by FIN-103, FIN-010, API-001, RPT, ALC-008.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-106-S01 | `bridge_money` context: prec 76, ROUND_HALF_UP, traps; `Money(amount: Decimal, currency: str)` value type rejecting float | `packages/bridge_money/core.py` | `Money(0.1, 'USD')` raises TypeError; prec test uses the 20-integer-digit example | 2 |
| FIN-106-S02 | ISO 4217 minor-unit seed (versioned) and `minor_unit(currency)` | `data/dbt/seeds/ref_currency_minor_unit.csv`, Python loader | USD 2, JPY 0, KWD 3 | 1 |
| FIN-106-S03 | `round_statement_lines` (signed largest remainder, §3.6) in Python and as a dbt macro, with a property test | `rounding.py`, `macros/round_statement_lines.sql` | Thirds; {+0.006, +0.006, −0.004} → 0.01/0/0; {+0.004, −0.006, −0.006} → 0/−0.01/0; Σ lines = rounded total on 10,000 random sets | 4 |
| FIN-106-S04 | JSON money grammar (§3.6) in the OpenAPI component `Money`, with a serializer that normalizes −0 and removes exponent notation | `data/contracts/money.schema.json`, API serializer | `Decimal('1E+2')` → "100", `Decimal('-0.00')` → "0.00" | 2 |
| FIN-106-S05 | Web: `@bridge/money` wrapper over decimal.js (parse, add, format with Intl per locale, never JS number); ESLint rule banning `parseFloat`/`Number()` on money fields | `packages/web-money/` | Unit tests; lint fails on a crafted misuse | 3 |
| FIN-106-S06 | SQL cast policy doc and dbt lint: multiply/divide in ledger models must wrap operands in explicit `::NUMBER(38,12)` | `docs` + sqlfluff custom rule | Crafted uncast division fails lint | 2 |
| FIN-106-S07 | Cross-language parity test (Python vs SQL vs TS) on 1,000 formatting and rounding cases | `tests/parity/money/` | 0 mismatches | 2 |
| FIN-106-S08 | Evidence | `docs/evidence/FIN-106/` | Recorded | 1 |
Task acceptance:
- [ ] No float reaches money code (type guard + lint).
- [ ] Statement lines always add to the rounded total, including mixed-sign sets.
- [ ] JSON money never contains exponent notation or "-0".

### FIN-107 — Corrections, restatement and prior-period adjustments
Release: R1 · Estimate: 36–52 h · Risk: H · Decisions: D-05, D-25 · Closes: G-FIN-12
Why: ADR-003 promises restatement or carry-forward without a rule; FIN-010 alone would be oversized.
Plugs in: after FIN-010 and FIN-009-S08 (C9); before ALC-008 (chargeback corrections) and ONB-004. Dependencies: `FIN-009`, `FIN-010`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-107-S01 | Model PG `finance.correction_case` (id, period, family, delta = new − closed, detected_at, materiality, proposal RESTATE/CARRY_FORWARD, status, decision actors) from C9 outputs; idempotent per (period, publication pair, family) | migration | Rerun of C9 does not duplicate CC-1 | 3 |
| FIN-107-S02 | Materiality policy (tenant, versioned): restate proposed when \|Δ\| ≥ max(abs_threshold, pct × period total); defaults 100 units / 0.5 % (owner Q4) | policy table + evaluator | F-REST-01 (−1.00) → CARRY_FORWARD proposal | 2 |
| FIN-107-S03 | RESTATE path: new close version vn+1 with new pins, statement v2 and difference lines (new − closed per family and account); v1 stays downloadable and immutable | extends FIN-010 close service | Statement v2 = 269.00 with "Storage −1.00"; v1 = 270.00 byte-identical | 5 |
| FIN-107-S04 | CARRY_FORWARD path: insert a `PRIOR_PERIOD_ADJUSTMENT` charge (usage_date original, accounting_period = current open period, entry_kind PRIOR_PERIOD_ADJUSTMENT) through an insert-only adjustment partition; the original period annotation is linked | `ledger.fct_charge_adjustment` partition + model | October statement shows −1.00 prior-period line; October consumption KPI unchanged | 5 |
| FIN-107-S05 | Guard against double effect: once CC-1 is carried forward, the restated-period view (Explorer "current truth") shows 269.00 while statements show v1 270.00 + Oct −1.00; no period shows 268.00 | test | Σ over statements (Aug v1 + Oct adj) = Σ current truth | 3 |
| FIN-107-S06 | Maker-checker on decisions (`finance.period.restate.request/approve`); approver ≠ proposer | lifecycle | Self-approval → 409 | 2 |
| FIN-107-S07 | Allocation/chargeback propagation hook: emit event `period_restated` / `prior_period_adjustment_created` for ALC-008 | outbox events | Event schema validated | 2 |
| FIN-107-S08 | API: GET `/v1/periods/{id}/corrections`, POST `/v1/corrections/{id}/propose`, POST `…/approve`, GET `/v1/statements/{id}/versions` | routes + OpenAPI | Contract tests | 4 |
| FIN-107-S09 | UX on `/reconciliation-close`: correction banner, comparison v1 vs current, decision dialog | web feature | Playwright | 5 |
| FIN-107-S10 | Race: second correction for the same period while a proposal is pending → merged into the case (delta recomputed), proposal invalidated if pins changed | test | Deterministic | 2 |
| FIN-107-S11 | Runbook RB-06 addendum "closed-period correction"; audit events | runbook + audit | Dry-run recorded | 1 |
| FIN-107-S12 | Evidence: F-REST-01 both paths | `docs/evidence/FIN-107/` | PASS | 2 |
Task acceptance:
- [ ] A correction never mutates a closed statement; restate creates v2 linked to v1 with explicit difference lines.
- [ ] Carry-forward appears only in the accounting period of the decision; usage-date consumption is unchanged.
- [ ] Statements across periods always sum to current truth once corrections are resolved.

### FIN-108 — Tenant-zero live verification of Snowflake billing semantics
Release: R1 (phase P2, before FIN-002 DONE) · Estimate: 28–44 h · Risk: H · Decisions: D-12, D-13, D-20 · Closes: G-FIN-24 (and the TO VERIFY LIVE items of G-FIN-04/05/06/16/17)
Why: crosswalk v1, maturity v1 and several authority rules depend on vendor behavior that is only partially documented.
Plugs in: after CON-005 and ING-007 connect Bridge's own Snowflake organization (RELEASE_PLAN §4 "tenant zero"); feeds FIN-001 (crosswalk v1), FIN-002, FIN-104, FIN-006, FIN-012, FIN-018, FIN-020. Dependencies: `CON-005`, `ING-007`, `FIN-002-S01…S03`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-108-S01 | Capture the distinct UICD tuples (service_type, usage_type, rating_type, billing_type, balance_source, is_adjustment, currency) with first/last date and row counts over all retained history | `docs/evidence/FIN-108/uicd_tuples.csv` (redacted) | File committed; crosswalk v1 PR opened | 3 |
| FIN-108-S02 | Capture distinct MDH/MH service types and map them to UICD tuples; list unmatched ones on either side | evidence file | Every MDH type mapped or explicitly UNMAPPED | 3 |
| FIN-108-S03 | Record the cloud-services representation in UICD (net vs gross + adjustment rows) and which MDH service types carry CREDITS_ADJUSTMENT_CLOUD_SERVICES | evidence note | FIN-005-S04 representation chosen from evidence | 2 |
| FIN-108-S04 | Storage: daily accrual vs month-end, tb_unit, storage-class values; compare one month of STORAGE_DAILY_HISTORY bytes × rate to UICD storage | evidence note | FIN-006-S01 inputs frozen | 3 |
| FIN-108-S05 | Obtain one real monthly usage statement (Snowsight) for a closed month; reconcile Σ UICD to it per service and currency; record rounding behavior (line vs total) | evidence + FIN-101 parser sample | Statement total vs Σ UICD Δ recorded (target ≤ one minor unit per line) | 4 |
| FIN-108-S06 | Measure latency per enabled source and month-close revision lag (last change date of each closed month, ≥ 3 months where history allows) | `fct_source_lateness` extract | Maturity policy v1 proposal (FIN-104-S07) | 3 |
| FIN-108-S07 | Verify availability and the schema of MARKETPLACE_PAID_USAGE_DAILY (DATA_SHARING_USAGE), Cortex views (AI_FUNCTIONS vs AISQL overlap), SERVERLESS_ALERT_HISTORY, streaming architecture fields, SPCS rating types | capability report | Each marked AVAILABLE, EMPTY or DENIED with evidence | 3 |
| FIN-108-S08 | Verify connector decimal handling end-to-end: `arrow_number_to_decimal=True` → Parquet decimal128 → RAW NUMBER; negative test without the flag shows float64 | evidence | No float column in RAW (G-FIN-02 closed) | 2 |
| FIN-108-S09 | Publish crosswalk v1 and maturity v1 with evidence links; mark all resolved TO VERIFY LIVE items in this backlog's contracts | seeds + PR | Reviewed by FinOps owner | 2 |
| FIN-108-S10 | Repeatability: script the capture queries (read-only, bounded predicates) for reuse on the design partner and each new tenant during onboarding (feeds ONB) | `services/extractor/probes/billing_semantics.py` | Runs on a second account without edits | 3 |
Task acceptance:
- [ ] Crosswalk v1 covers 100 % of observed tuples on tenant zero, and unknown tuples route to UNMAPPED.
- [ ] One closed month reconciles Σ UICD to the official usage statement with every difference classified.
- [ ] Maturity policy v1 numbers are derived from measured lateness and revision lag.
- [ ] No float column exists anywhere in the RAW financial sources.

### FIN-109 — Customer-approved FX dataset and display conversion
Release: R2 (R1 only if owner Q5 says chargeback must be in a currency other than billing) · Estimate: 24–36 h · Risk: M · Decisions: D-18 · Closes: FX part of ledger.md
Why: ledger.md allows display conversion only with a customer-approved, versioned FX dataset; nothing implements it.
Plugs in: after FIN-002 and FIN-106; consumed by API display and RPT/ALC statements when enabled. Dependencies: `FIN-002`, `FIN-106`, `FIN-105` (approval pattern reuse).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FIN-109-S01 | FX dataset model (source ECB reference / customer treasury / manual; pair; rate_date; rate NUMBER(38,12); convention (monthly average, month-end or daily); version; approval) | migration + schema | Overlapping versions rejected | 3 |
| FIN-109-S02 | Import (CSV) with maker-checker and evidence; publish via D-04 | API + publisher | Self-approval → 409 | 4 |
| FIN-109-S03 | Conversion model: display_cost = cost_effective × fx(pair, convention date) → `display_currency`, `fx_version`; native amounts untouched | `int_charge__display_fx.sql` | EUR 20.00 at 1.08 → USD 21.60 displayed with version; native EUR 20.00 kept | 3 |
| FIN-109-S04 | Aggregation rule: mixed-currency totals only in display currency with the FX version shown; never in native KPIs | API guard | Native USD+EUR sum request → 422 | 2 |
| FIN-109-S05 | Missing rate for a date → display NULL + reason (no carry beyond policy) | test | Visible reason | 2 |
| FIN-109-S06 | Close pins fx_version when a statement is issued in display currency | FIN-010 extension | Pin present | 2 |
| FIN-109-S07 | UX: currency switcher shows basis and version; exports include native and display amounts | web + RPT | Playwright | 5 |
| FIN-109-S08 | Isolation, audit, evidence | tests + evidence | Recorded | 3 |
Task acceptance:
- [ ] Native amounts are never altered; display amounts carry fx_version and convention.
- [ ] No native-currency KPI ever mixes currencies.

### Dependency corrections (summary for the task index)

| Edge change | Reason |
|---|---|
| Reverse `FIN-001 → DBT-005` (was DBT-005 → FIN-001); drop `ING-001 → FIN-001`; add `FND-004 → FIN-001` | Contracts and fixtures are inputs to the CI golden tests; start in P0 |
| `FIN-108` after `CON-005`, `ING-007`; `FIN-108 → FIN-002 (DONE)`, `→ FIN-104`, `→ FIN-006`, `→ FIN-018`, `→ FIN-020`, `→ FIN-021` | Vendor semantics verified before money SQL is frozen |
| `FIN-001 → FIN-104 → FIN-102`; `FIN-002 → FIN-102`; `FIN-106 → FIN-103`; `FIN-102, FIN-103 → FIN-003…FIN-021` | Estimator, supersession and exact attribution are shared cores |
| Drop `FIN-003 → FIN-004`, `FIN-006 → FIN-008`, `FIN-019 → FIN-020` | Independent attribution models (PRD §49) |
| `FIN-009` depends on 003, 005, 006, 007, 008, 021, 101, 104, 106; **not** on 004, 018, 019, 020 (capability plug-ins) | Removes R1\* features from the launch critical path |
| `FIN-007` depends on 011, 013–016 (not 012, 017) | Same |
| `FIN-101 → FIN-009 → FIN-010 → FIN-107 → ALC-008, ONB-004` | Invoice intake and corrections precede close and chargeback |
| Downstream: `API-001` → FIN-001 + FIN-102 (not FIN-009); `ALC-001` → FIN-001 + FIN-103 (not FIN-009); `ALC-005` → FIN-009 (not FIN-010); `INS-002`, `UX-005` → FIN-003 (FIN-004 optional) | Allows lanes D/E to start on contracts |

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| FIN-001 Charge schema, authority, fixtures | R1 | 40 | 60 |
| FIN-002 Billing, rates normalization | R1 | 45 | 65 |
| FIN-003 Classic warehouse, query, idle | R1 | 50 | 75 |
| FIN-004 Adaptive query-hour | R1\* | 24 | 36 |
| FIN-005 Cloud services, signed entries | R1 | 28 | 40 |
| FIN-006 Storage | R1 | 36 | 54 |
| FIN-007 Serverless conformance | R1 | 13 | 18 |
| FIN-008 Transfer (S01–S05, S08–S09) | R1 | 16 | 24 |
| FIN-008 Replication (S06–S07) | R1\* | 8 | 12 |
| FIN-009 Reconciliation controls + UX | R1 | 70 | 100 |
| FIN-010 Period close, statements | R1 | 50 | 70 |
| FIN-011 File Snowpipe | R1 | 12 | 18 |
| FIN-012 Snowpipe Streaming | R1\* | 17 | 26 |
| FIN-013 Serverless tasks, alerts | R1 | 14 | 22 |
| FIN-014 Automatic clustering | R1 | 10 | 14 |
| FIN-015 Search optimization | R1 | 10 | 14 |
| FIN-016 Materialized views | R1 | 10 | 14 |
| FIN-017 Query acceleration | R1\* | 12 | 18 |
| FIN-018 Cortex / AI services | R1\* | 36 | 54 |
| FIN-019 SPCS | R1\* | 22 | 32 |
| FIN-020 Marketplace, native apps | R1\* | 20 | 30 |
| FIN-021 New/unmapped services, org fees | R1 | 24 | 36 |
| FIN-101 Billing reference intake (new) | R1 | 45 | 65 |
| FIN-102 Estimator + supersession (new) | R1 | 36 | 52 |
| FIN-103 Exact attribution framework (new) | R1 | 26 | 40 |
| FIN-104 Maturity policy + evaluator (new) | R1 | 24 | 36 |
| FIN-105 Customer-approved rate tables (new) | R1 | 30 | 44 |
| FIN-106 Money library + rounding (new) | R1 | 16 | 24 |
| FIN-107 Corrections, restatement (new) | R1 | 36 | 52 |
| FIN-108 Tenant-zero billing verification (new) | R1 | 28 | 44 |
| FIN-109 FX display conversion (new) | R2 | 24 | 36 |
| **Total R1** | | **669** | **981** |
| **Total R1\* (in R1 only if D-20 requires; otherwise R2)** | | **139** | **208** |
| **Total R2** | | **24** | **36** |

Hours are one senior engineer-hour including tests, review fixes and evidence (D-19). They exclude UX screen-spec authoring by the UX owner (three screens, see §3) and the ING-side fix for G-FIN-02.

## 7. Owner questions (only those not already covered by D-01…D-25)

1. **Spend definition.** Should headline "spend" be consumption value at billed rates across all funding classes (capacity, rollover, free, rebate-funded and overage), with a funding breakdown (recommended)? Or should the product also ship a cash-effective view that excludes free and rebate-funded usage in R1? (G-FIN-04)
2. **INVOICE control policy.** Is an approved usage statement or invoice (control C5) required to reach RECONCILED, or only to close a period? Recommended: required for close, optional for RECONCILED, configurable per tenant. (G-FIN-09, §3.4)
3. **Maker-checker for close, restatement, rates and references.** May a tenant with a single FinOps admin disable the second-approver rule (audited)? Recommended: allowed only with explicit tenant-owner acknowledgement. (G-FIN-11)
4. **Materiality defaults for closed-period corrections.** Restatement is proposed when |Δ| ≥ max(100 currency units, 0.5 % of period total); otherwise carry-forward. Accept, or set other values? (G-FIN-12)
5. **Statement currency.** If Snowflake bills in USD but the first customer's internal chargeback must be in EUR, FX (FIN-109) moves into R1. Which currency do the customer's statements use? (FIN-109)
6. **Statement and evidence retention.** How many years of Object Lock retention apply to closed statements and billing references (e.g. 7 or 10 years, per the customer's accounting law)? This drives S3 cost and deletion/erasure exceptions. (G-FIN-11, FIN-101-S11)
7. **Tenant-zero billing access.** Will Bridge grant its own Snowflake organization-account billing roles, and supply real monthly usage statements for ≥ 3 closed months, to the staging environment for FIN-108? Without this, crosswalk v1 is validated first on the paying customer. (G-FIN-24)
8. **Month stability window.** Is the default N = 5 days after month end acceptable for closing, knowing FIN-108 may raise it after measuring actual revision lag? (G-FIN-08)

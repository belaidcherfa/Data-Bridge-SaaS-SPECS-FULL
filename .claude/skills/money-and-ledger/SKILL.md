---
name: money-and-ledger
description: Rules and test recipes for any code that computes, stores, allocates, forecasts, prices or displays money or credits — exact decimals, currency, unknown vs zero, maturity, supersession, proration, allocation conservation, rounding at boundaries. Use for FIN, ALC, INS, RPT, commercial and any money-bearing API or screen.
---

# Money and ledger correctness

Read ADR-003 (+ amendment), ADR-014 (revisions), ADR-015 (grain, maturity, attribution), decisions D-12…D-16, and `contracts/CONVENTIONS.md` §5–6 before touching money.

## Representation
- Python: `decimal.Decimal` only, created from strings or ints, via `packages/bridge_money` (`Money`, `Quantity`, context precision 38). `float` in a money path is a blocking finding; add `ruff` rule and a test that scans the module for `float(`.
- Snowflake: `NUMBER(38,12)` amounts, `NUMBER(38,18)` intermediates for division; multiply before dividing; `arrow_number_to_decimal=True` on every connector; Parquet decimal128.
- JSON: `{"amount": "<decimal string>", "currency": "USD"}`; TypeScript never does arithmetic on amounts (format only).
- Currency: every amount carries currency; different currencies are never added; FX conversion only through the rate table with `price_basis` recorded (D-17 USD commercial, customer data in its own currency).

## Semantics
- **Unknown ≠ zero**: missing price, denied view, out-of-retention → `null` + reason (unknown-reason enum). Aggregates over partially unknown inputs return the known subtotal + `coverage` + warning, never silently treat unknown as 0.
- **Maturity** (D-13): `PROVISIONAL` → `FINAL` after the per-source horizon (+24 h metering, +72 h QUERY_ATTRIBUTION_HISTORY and daily billing), `RECONCILED` after the invoice/organization-usage match; period state `OPEN → MONTH_STABLE` (month end + 5 days) `→ CLOSED → RESTATED`. Never overwrite a published figure: publish a new revision (ADR-014) and let the publication map switch.
- **Supersession** (D-12): an estimate family bucket is superseded atomically by the authoritative family for the same (account, date, service family); no double counting across estimate and actual.
- **Temporal attribution** (D-14): long queries are prorated by execution overlap with metering hours over half-open UTC intervals; the unexplained part of each metering hour is an explicit hourly residual, never spread silently; prorated parts sum exactly to the whole (remainder assigned deterministically).
- **Allocation** (D-15/D-16): default book always exists; every credit is allocated to exactly one leaf or to `UNALLOCATED` — conservation `Σ allocated + unallocated = source total` per (tenant, account, day, currency) to 12 decimals.
- **Rounding**: internal values unrounded; round to currency minor units only at statement/export boundaries with sign-normalized largest remainder so rounded parts sum to the rounded total.

## Mandatory tests
1. Golden fixture from `data/fixtures/finance/` with expected values computed independently (spreadsheet/hand calculation committed as CSV), never produced by the code under test.
2. Conservation invariants as property tests (Hypothesis with `decimals(allow_nan=False, allow_infinity=False, places=12)`): allocation sums, proration sums, supersession no-double-count, rounding sums.
3. Signed amounts (credits, refunds, adjustments), zero, very large (10^25), 12-decimal precision, empty periods, DST-irrelevance (UTC), month boundaries, leap day.
4. Unknown propagation: a null input yields null + reason at every aggregation level.
5. Restatement: a late revision changes the figure only through a new publication; previous publication still readable by ID.
6. Snapshot of the SQL/dbt result on the fixture equals the Python reference implementation (dual implementation check) where the packet requires it.

FinOps reviewer (`finops-reviewer`) must approve any PR in FIN/ALC/INS/RPT or touching `packages/bridge_money`.

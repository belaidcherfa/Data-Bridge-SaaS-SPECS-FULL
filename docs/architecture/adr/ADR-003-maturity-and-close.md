# ADR-003 — Separate maturity, reconciliation and close

Status: Accepted for implementation. Date: 2026-09-23.

## Context

Account Usage and currency billing have different lateness and may be revised. FINAL cannot promise an immutable invoice.

## Decision

Expose data_status PROVISIONAL/FINAL/RECONCILED with source/reference versions; store reconciliation_status and financial_period_state separately. FINAL means source-mature under a documented policy. Close creates an immutable statement. Later corrections create a restatement or next-period adjustment.

## Alternatives considered

A single boolean final is ambiguous. Marking old data reconciled without a reference is false assurance.

## Consequences

UI, exports and alerts carry coverage and status. Each reopening produces a new version and audit trail. No silent mutation of issued chargeback.

## Revisit conditions

Revisit maturity windows using measured lateness; never weaken invoice close evidence.

## Validation obligation

Implementation tasks must link redacted live evidence before production. Documentation acceptance is not execution evidence. See [delivery methodology](../../../DELIVERY_METHODOLOGY.md).

## Amendment 2026-09-28

Status: ACCEPTED (owner decision record 2026-09-28). Decision: D-13 (with D-27 for monitors). Evidence: [decision record](../../22-implementation-readiness/DECISIONS_REQUIRED.md) D-13/D-27; [FIN backlog](../../22-implementation-readiness/backlog/FIN.md) G-FIN-08, G-FIN-10…12 and §3.3–§3.5 (FIN-104, FIN-107, FIN-108); [audit](../../22-implementation-readiness/AUDIT_CROSS_CUTTING.md) X-19; consolidated in [ADR-015](ADR-015-financial-grain-maturity-attribution.md).

What changes:

1. **Numeric horizons.** "FINAL means source-mature under a documented policy" now has numbers: a versioned per-source policy `ref_source_maturity_policy` (FIN-104) stored with the source registry. Defaults (measured from the end of the source hour or UTC day): WAREHOUSE_METERING_HISTORY and METERING_HISTORY +24 h; METERING_DAILY_HISTORY +24 h; RATE_SHEET_DAILY +48 h; USAGE_IN_CURRENCY_DAILY +72 h. Charge maturity and attribution maturity are separate: query attribution (QUERY_ATTRIBUTION_HISTORY) is FINAL at hour end + T + 24 h, where T = min(account maximum statement timeout, 48 h) — **72 h by default**, because a query can run for the statement timeout before it appears. A row is FINAL only when its horizon has elapsed **and** its source coverage is contiguous (ADR-006).
2. **MONTH_STABLE is a separate state.** Daily FINAL and month stability differ: a day can be FINAL at +72 h while the month still changes. `period_stability = STABLE` is reached at month end + N days (N = 5 by default, configurable; FIN-108 re-derives N from observed revision lag + 2 days). STABLE gates close: `OPEN → CLOSE_PREVIEWED` requires it.
3. **Close and corrections.** Close is maker-checker (`finance.period.close.request` / `…close.approve`, approver ≠ requester, fresh authorization check), pins an enumerated freeze set (publication, revision set, crosswalk, maturity policy, rates, config, control runs, references, artifact hashes) and stores statement artifacts in the RECORD retention class ([ADR-009 amendment](ADR-009-privacy-and-retention.md)). A later change to a closed period raises control C9 (CLOSED_PERIOD_DRIFT) and a correction case resolved by restatement (new statement version) or carry-forward (`PRIOR_PERIOD_ADJUSTMENT` in the accounting period of the decision, usage date unchanged), both maker-checker (FIN-107).
4. **Revisions after reconciliation.** A later revision of any row in a RECONCILED period moves that period back to FINAL until controls are re-run; closed statements are unaffected.
5. **Alerts (D-27).** Monitors evaluate PROVISIONAL data by default and state the maturity in every alert; `minimum_data_status: FINAL` is an explicit opt-in, because FINAL delays alerts by 2–5 days under these horizons.

Revisit condition (unchanged in spirit): measured lateness from tenant zero and canaries revises the defaults through a new policy version, never by weakening close evidence.

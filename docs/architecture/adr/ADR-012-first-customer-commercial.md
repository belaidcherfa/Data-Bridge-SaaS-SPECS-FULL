# ADR-012 — Manual B2B billing for first paying customer

Status: ACCEPTED design; customer/commercial approval pending. Owner: Product/Finance.

## Context

The required outcome is a first paying production customer. The PRD does not prescribe a payment provider or authorize card processing.

## Decision

Use approved manual B2B invoicing with auditable plan/entitlement and verified payment references, as defined in [launch](../../20-launch/launch.md). Customer analytical facts remain in Snowflake; PostgreSQL holds commercial control state. Genuine settlement evidence is required for ACTIVE_PAID and M12.

## Alternatives

Integrate a subscription processor immediately: adds provider, tax, webhook and operational scope before first value. Treat signed order or trial as payment: misleading and rejected.

## Consequences

Finance performs a controlled verification step and corrections are reviewed. No card data is stored. Product admission enforces plan quotas independently from retained financial truth.

## Revisit conditions

Self-service volume, recurring collection needs or commercial policy justify a provider integration with its own security and idempotency specification.

## Amendment 2026-09-28

Status: ACCEPTED (owner decision record 2026-09-28; accountant confirmation required before the first invoice). Decisions: D-17, D-30, D-36 (with D-37 support model). Evidence: [decision record](../../22-implementation-readiness/DECISIONS_REQUIRED.md) D-17/D-30/D-36/D-37; [LCH backlog](../../22-implementation-readiness/backlog/LCH.md) G-LCH-01, G-LCH-03, G-LCH-04, G-LCH-05, G-LCH-10 (LCH-101…LCH-105); [reconciliation](../../22-implementation-readiness/RECONCILIATION.md) U-08, C-08.

What changes:

1. **Plan model (D-17).** Price = platform fee + band of managed Snowflake spend, priced in USD. Bands are defined per spend currency in the plan catalog (no FX dependency). New task LCH-105 meters each tenant's managed spend from MONTH_STABLE ledger totals ([ADR-015](ADR-015-financial-grain-maturity-attribution.md)) and assigns the band. Entitlements remain plan-agnostic quotas enforced at admission by LCH-101 (connected accounts, users, history days, query-detail days, report schedules, API clients, concurrent heavy jobs and backfills).
2. **No free trial: PILOT replaces TRIAL.** The subscription state `TRIAL` becomes `PILOT`, a contracted (possibly discounted) pilot, never an unpaid self-service trial. The canonical machine owned by LCH-001 is `PILOT → ACTIVE_PENDING_PAYMENT → ACTIVE_PAID`, with `PAST_DUE`, `SUSPENDED` and `CANCELLED`; genuine verified settlement is still required for `ACTIVE_PAID` and the paid-customer gate, and the activating payment event needs a second finance operator. Snowflake trial accounts are demonstration-only connections ([ADR-016](ADR-016-customer-coverage-residency-reachability.md), D-35), unrelated to the subscription state.
3. **Invoicing channel (D-30).** Not automated for now: manual invoices from an accounting tool, or a Stripe payment link. The product never generates invoices; Bridge stores invoice references (number, date, amounts, VAT treatment, e-invoicing transmission identifier and status) and verified payment evidence (including payment-link or charge references) only, and never card data. Automated collection later requires its own ADR.
4. **French invoicing entity (D-36).** French VAT rules (EU B2B reverse charge where applicable) and the French e-invoicing reform apply to whichever tool issues invoices: since 2026-09-01 French companies must be able to receive electronic invoices, and issuance through an approved platform applies from 2026-09-01 for large companies and ETIs and from 2027-09-01 for SMEs and micro-enterprises (VERIFIED from public sources; obligations to be confirmed by an accountant, LCH-103). Accounting-record retention is multi-year and independent of product data retention.
5. **Go-live order.** Production go-live and monitored rollout (LCH-003) precede first-customer onboarding (ONB-003); verified payment (LCH-002) remains the commercial gate afterwards (G-LCH-01).
6. **Support stance (D-37).** EU business hours (Mon–Fri 09:00–18:00 CET), SEV1 best effort outside those hours, no contractual 24×7 commitment; published in the support policy (LCH-104).

Why: owner decisions; the original "trial" wording would allow an unpaid state to pass for a customer, and in-product invoice generation would be non-compliant under the French reform.

Consequences: plan catalog needs spend bands per currency; LCH-105 depends on MONTH_STABLE ledger totals; [launch](../../20-launch/launch.md) is amended accordingly.

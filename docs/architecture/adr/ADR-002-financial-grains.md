# ADR-002 — Additive charges and non-additive attribution

Status: Accepted for implementation. Date: 2026-09-23.

## Context

The PRD names warehouse, query, idle and dynamic-table ledgers, but summing all of them would double count.

## Decision

Maintain additive charge entries and separate attribution links. Every amount declares entry_kind, billable inclusion, currency, provenance and revision. Queries/idle decompose warehouse compute; dynamic tables on warehouses are workloads. Signed adjustments are valid. Never impose universal cost>=0 on adjustment rows.

## Alternatives considered

A flat union of every metric inflates spend. Deriving every bill solely from queries misses idle, services, storage, fees and adjustments.

## Consequences

Service models stay independent but share a ledger schema. Reconciliation compares equivalent scope, units, currency, period and billing version. Unknown services remain visible.

## Revisit conditions

New billing service types or source semantics require a new registry version and golden fixture, not another hidden total.

## Validation obligation

Implementation tasks must link redacted live evidence before production. Documentation acceptance is not execution evidence. See [delivery methodology](../../../DELIVERY_METHODOLOGY.md).

## Amendment 2026-09-28

Status: ACCEPTED (owner decision record 2026-09-28; D-12 delegated to engineering). Decision: D-12 (with D-14 and D-15, see [ADR-015](ADR-015-financial-grain-maturity-attribution.md)). Evidence: [decision record](../../22-implementation-readiness/DECISIONS_REQUIRED.md) D-12; [FIN backlog](../../22-implementation-readiness/backlog/FIN.md) G-FIN-01, G-FIN-03, G-FIN-18 and §3.1–§3.2; [ALC backlog](../../22-implementation-readiness/backlog/ALC.md) G-ALC-01; [API backlog](../../22-implementation-readiness/backlog/API.md) G-API-02; [audit](../../22-implementation-readiness/AUDIT_CROSS_CUTTING.md) X-18 and §7 (blockers G-FIN-01, G-ALC-01, G-API-02).

What changes:

1. **Charge identity = billing bucket.** An active `fct_charge` row is identified by its fine bucket key (tenant, organization, contract, scope_kind, account — null only for organization scope —, usage_date UTC, service_type, usage_type, rating_type, billing_type, balance_source, is_adjustment, currency, basis AUTH/EST; FIN §3.1). Versions are `revision_id` values under [ADR-014](ADR-014-analytical-revisions.md), never part of the identity; rows no longer carry `publication_id`.
2. **Family-bucket supersession replaces 1:1 replacement.** Estimates exist only at family-bucket grain (tenant, organization, scope_kind, account, usage_date, service_family, currency). An accepted authoritative row deactivates the estimate for its family bucket; a mature daily billing snapshot (+72 h) deactivates all estimates for that account-day; metered usage with no billing after maturity stays visible as a PROVISIONAL estimate flagged `BILLING_MISSING` and fails control C2. Example: estimate 200 followed by billed capacity 160 + overage 50 gives 210, never 410.
3. **Money below the bucket lives only in attribution bridges**, produced by one exact allocator (`allocate_exact`, FIN-103, 12-decimal quanta, largest remainder, stable key) with explicit residual rows (`UNATTRIBUTED`, `PRORATION_RESIDUAL`) so every attribution set sums exactly to its parent charge. The daily effective rate is a display attribute and is never multiplied back.
4. **Two money models only.** Money comes from the authoritative billing normalizer (FIN-002) and the provisional estimator (FIN-102). Per-service models (Snowpipe, tasks, clustering, Cortex, SPCS, …) become attribution models; `ledger_<family>` names survive as thin filtered views for PRD traceability (refines PRD §47/§49 "self-contained ledger model per service").
5. **Allocation input grain.** `int_alloc_unit` splits each charge into QUERY, IDLE, HOUR_RESIDUAL, RESOURCE or WHOLE units that sum exactly to the charge and is the only allocation input (G-ALC-01).
6. **Resource-dimension spend.** Grouping money by warehouse, user, role, workload or query family uses the `attributed_cost` metric over attribution rows that include one explicit residual row per parent charge, so any grouping conserves `spend` (G-API-02).

Consequences: estimate accuracy is a reported control (C8), not a hidden replacement; unknown billing tuples stay `UNMAPPED_BILLABLE_SERVICE`; reconciliation and allocation read the same active rows.

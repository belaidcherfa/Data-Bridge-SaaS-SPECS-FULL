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

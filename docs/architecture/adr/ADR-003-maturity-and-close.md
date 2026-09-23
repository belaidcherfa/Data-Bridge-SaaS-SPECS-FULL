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

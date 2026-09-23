# ADR-005 — Snowflake identity-bound serving authorization

Status: Accepted for implementation. Date: 2026-09-23.

## Context

Tenant_id filters or client-writable session variables alone cannot enforce database isolation.

## Decision

Create central WIF reader principals per tenant and distinct normalized permission profile, with one constrained role and a policy mapping from CURRENT_USER() to tenant/account/resource entitlements. An isolated query broker resolves server-authenticated profiles to identities; callers cannot provide principals. Row policies protect serving tables, including aggregates. No RAW or policy-table grants to readers.

## Alternatives considered

A shared superuser plus WHERE clauses is rejected. QUERY_TAG or arbitrary session variables are audit metadata, not trusted identity. One identity per web user creates needless churn; profiles deduplicate equal permissions.

## Consequences

Central Snowflake requires an edition supporting row access policies. Pools are keyed by principal and authorization epoch, secondary roles disabled. Permission revocation tombstones profile access, invalidates pools/caches and is checked again before result delivery. Broad aggregates cannot serve narrower readers; use secure authorized fact aggregates. Launch capacity includes identity quota tests.

## Revisit conditions

At high profile cardinality, evaluate a signed-context trusted broker or dedicated tenant accounts with a new threat model; do not quietly replace RLS with filters.

## Validation obligation

Implementation tasks must link redacted live evidence before production. Documentation acceptance is not execution evidence. See [delivery methodology](../../../DELIVERY_METHODOLOGY.md).

# ADR-001 — Storage responsibilities and physical tenancy

Status: Accepted for implementation. Date: 2026-09-23.

## Context

The PRD requires four stores, organizations, accounts and tenant_id in facts; earlier single-customer database assumptions do not apply to this SaaS.

## Decision

Use shared central Snowflake analytical tables with physical tenant keys and policy-enforced serving. PostgreSQL stores control records only. Separate environment accounts/databases. Preserve organization-level rows with account_id null and scope_kind=ORGANIZATION; account-scoped rows require account_id. Use effective-dated org/account membership and retain source identifiers.

## Alternatives considered

Database-per-tenant adds operational cost and cannot remove the PRD tenant key. PostgreSQL analytical mirrors duplicate truth. A customer organization name is not an authentication boundary.

## Consequences

All joins, uniqueness, manifests and caches include tenant identity. Organization fees require explicit scoped handling. Bulk administrators are isolated from product readers.

## Revisit conditions

Revisit physical Snowflake isolation for residency, contractual dedicated tenancy or demonstrated noisy-neighbor limits; retain canonical tenant keys.

## Validation obligation

Implementation tasks must link redacted live evidence before production. Documentation acceptance is not execution evidence. See [delivery methodology](../../../DELIVERY_METHODOLOGY.md).

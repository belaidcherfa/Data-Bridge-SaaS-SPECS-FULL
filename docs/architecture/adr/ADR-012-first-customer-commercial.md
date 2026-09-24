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

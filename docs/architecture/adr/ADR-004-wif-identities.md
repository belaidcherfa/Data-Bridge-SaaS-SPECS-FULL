# ADR-004 — Account-specific WIF and isolated run identities

Status: Accepted for implementation. Date: 2026-09-23.

## Context

Long-lived Snowflake secrets are prohibited; a shared extraction identity would magnify cross-customer compromise.

## Decision

Provision an AWS role and Snowflake SERVICE reader per connected account; use Fargate task roles for extraction. Central services use separate WIF identities. Prefer documented JWT AWS WIF only when connector/adapter support is live-proved; otherwise explicitly use supported AWS attestation mode, still WIF. Never fall back to RSA/PAT.

## Alternatives considered

A global account reader or user-supplied role ARN weakens isolation. Customer-specific pipeline code is unnecessary.

## Consequences

An allowlisted launcher resolves connection_id to role/task definition. iam:PassRole is restricted. Bootstrap authenticates interactively and is audited. Verify quotas before tenant admission.

## Revisit conditions

Identity counts approach quotas, or connector support changes; benchmark a broker design before consolidation.

## Validation obligation

Implementation tasks must link redacted live evidence before production. Documentation acceptance is not execution evidence. See [delivery methodology](../../../DELIVERY_METHODOLOGY.md).

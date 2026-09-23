# ADR-010 — Pinned open-source stack and evidence-driven launch

Status: Accepted for implementation. Date: 2026-09-23.

## Context

Vendor versions change and current dbt documentation may default to a different execution engine. The mission requires dbt Core and Dagster OSS.

## Decision

Choose a tested Python/dbt-core/dbt-snowflake/connector/Dagster/PyArrow matrix during bootstrap and commit exact locks and image digests. Do not silently switch to Fusion/dbt v2 or a cloud plan. Run live WIF/dbt/Dagster compatibility gates before M2/M4. GitHub Actions OIDC to AWS is the CI default for this repository.

## Alternatives considered

Unpinned latest and assumed transitive connector support are unsafe. Tool compilation alone cannot certify source grants or financial truth.

## Consequences

Provisioning, payments, customer consent and legal approval remain explicit future implementation gates. The current repository contains specifications only.

## Revisit conditions

New supported releases pass compatibility/security fixtures; update through one version ADR amendment.

## Validation obligation

Implementation tasks must link redacted live evidence before production. Documentation acceptance is not execution evidence. See [delivery methodology](../../../DELIVERY_METHODOLOGY.md).

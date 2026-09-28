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

## Amendment 2026-09-28

Status: ACCEPTED (owner decision record 2026-09-28). Decision: D-21 (with D-19 and D-32 for execution). Evidence: [decision record](../../22-implementation-readiness/DECISIONS_REQUIRED.md) D-21; [audit](../../22-implementation-readiness/AUDIT_CROSS_CUTTING.md) X-23; [FND backlog](../../22-implementation-readiness/backlog/FND.md); [CON backlog](../../22-implementation-readiness/backlog/CON.md) CON-002; [INF backlog](../../22-implementation-readiness/backlog/INF.md) G-INF-01; [research register](../../00-project/RESEARCH_REGISTER.md).

What changes:

1. **WIF everywhere, including dbt Core.** Pin `dbt-snowflake >= 1.12.0`: dbt-labs/dbt-adapters PR #1316 (Snowflake Workload Identity Federation) merged 2026-05-20 with milestone v1.12.0 (VERIFIED). No RSA key-pair or PAT fallback for any central or customer-facing service. dbt-snowflake has no impersonation parameter, so each dbt task role is itself the WIF identity; dbt CI uses GitHub OIDC → AWS → a Snowflake WIF CI user that owns only `BRIDGE_CI`. The live proof remains CON-002; a pre-agreed non-WIF fallback is no longer needed.
2. **Bootstrap credential exception.** The only non-WIF credential allowed is a transient human bootstrap credential required at Snowflake account creation (for example, `CREATE ORGANIZATION ACCOUNT` requires `ADMIN_PASSWORD` or `ADMIN_RSA_PUBLIC_KEY`, VERIFIED). It is used interactively by a named administrator, never stored in CI, Terraform state or runtime configuration, audited, and disabled or rotated as soon as federated administrators and WIF service identities exist.
3. **Pinned behaviour-bearing settings.** The lock records `snowflake-connector-python` with `arrow_number_to_decimal=True` on every extractor connection (the default converts scaled NUMBER to float64, VERIFIED), an exact `sqlglot` pin (sanitizer behaviour, see [ADR-009 amendment](ADR-009-privacy-and-retention.md)), and dagster-aws/dagster-dbt versions. Upgrades re-run the corresponding corpora and live gates.
4. **Where live gates run.** Live WIF, grant, policy and load gates run against the non-production Snowflake test estate (INF-101: two test organizations, several accounts, workload generators, canaries, tenant zero) within the approved budget (D-32: estate ≤ 150 credits/month inside a 500 credits/month non-production ceiling; one-off benchmarks ≤ 600 credits). Coding agents implement tasks under 1–2 human reviewers (D-19); live gates with real credentials are executed or witnessed by a human.

Consequences: open validation V01 narrows to live compatibility proof; the "choose AWS attestation mode when JWT is unsupported" rule of ADR-004 still applies and remains WIF.

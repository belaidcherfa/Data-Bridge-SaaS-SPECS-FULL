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

## Amendment 2026-09-28

Status: ACCEPTED (owner decision record 2026-09-28). Decisions: D-02, D-22. Evidence: [decision record](../../22-implementation-readiness/DECISIONS_REQUIRED.md) D-02/D-22; [SEC backlog](../../22-implementation-readiness/backlog/SEC.md) G-SEC-01, G-SEC-13, G-SEC-20, G-SEC-21, G-SEC-22 and Appendix A (normative DDL and policy bodies); [API backlog](../../22-implementation-readiness/backlog/API.md) G-API-05; [INF backlog](../../22-implementation-readiness/backlog/INF.md) INF-103, G-INF-16; [audit](../../22-implementation-readiness/AUDIT_CROSS_CUTTING.md) X-10, X-24; [reconciliation](../../22-implementation-readiness/RECONCILIATION.md) U-02, C-09, C-11, C-28.

What changes (the original text above is superseded where it conflicts):

1. **Identity model.** One Snowflake `TYPE=SERVICE` user and one identity-only AWS IAM role per **tenant** (`bridge-<env>-srv-<uuid32>`, no IAM path, no permission policies, deny-all permissions boundary, trust limited to the query broker task role). One Snowflake **role per normalized permission profile** (`BRIDGE_<ENV>_T_<TENANT_SHORT>_P_<first 16 hex of profile_hash>`). Profiles are content-addressed and immutable: a scope change maps the member to another profile, it never edits one. This replaces "WIF reader principals per tenant and distinct normalized permission profile". The tenant boundary stays identity-enforced; intra-tenant scope is role-enforced.
2. **Row access policies test `CURRENT_ROLE()` only.** `CURRENT_USER()` resolves the tenant through `SECURITY.TENANT_PRINCIPAL`; `CURRENT_ROLE()` resolves entitlements in `SECURITY.PROFILE_ENTITLEMENT`. `IS_ROLE_IN_SESSION()` is never used for entitlement or for any service exemption, because with secondary roles it would widen a restricted profile to the union of every profile of the tenant. Policies: `RAP_ACCOUNT_SCOPED` (account-grain facts, only clauses with an unrestricted group dimension), `RAP_GROUP_SCOPED` (group-grain facts, sentinel groups `__SHARED__`/`__UNALLOCATED__` need explicit flags, no "all groups" rows), `RAP_TENANT_ONLY`, and masking policy `MP_SQL_TEXT_FULL`. Ratios whose denominator is outside the caller's profile return `null` with `DENOMINATOR_OUTSIDE_SCOPE`.
3. **Secondary roles disabled.** Tenant users are created with `DEFAULT_SECONDARY_ROLES = ()` plus a session policy with `ALLOWED_SECONDARY_ROLES = ()`, because new users default to `('ALL')` since behavior-change bundle 2024_08 (VERIFIED). The broker asserts `CURRENT_USER()`, `CURRENT_ROLE()` and an empty `CURRENT_SECONDARY_ROLES()` after connecting and discards the connection otherwise.
4. **Pools are not keyed by epoch.** Pool key = `(env, tenant_user, profile_role)`. The membership `permission_epoch` and the tenant `authz_epoch` bind cursors, jobs, cache keys and download links instead. Revocation is enforced by the per-request durable check, the broker's re-check of running statements every 10 s with cancellation, and entitlement deactivation on profile retirement. This replaces "Pools are keyed by principal and authorization epoch".
5. **Provisioning and blast radius.** Snowflake objects are provisioned by SEC-105 with split identities: `TENANT_ONBOARDER` (creates tenant users, writes `TENANT_PRINCIPAL`) and `PROFILE_PROVISIONER` (creates profile roles, writes entitlements; cannot create users, so it cannot cross tenants). The AWS role is created by the single runtime IAM provisioner INF-103. Admission is refused at 80 % of the IAM role quota and alarmed at 70 % (default quota 1,000 roles per account; adjustable maximum 10,000 since 2026-05, VERIFIED), shared with per-connection extractor roles (ADR-004).
6. **Query broker placement (D-22).** The broker is a separate internal service with its own task role, the only component allowed to assume tenant serving identities. It is reached by the API over private, authenticated transport (SigV4 through VPC Lattice preferred, TO VERIFY LIVE; no private CA in R1) with a server-signed query plan; the planner emits `SELECT` only. It reaches the tenant user through the Python connector's `workload_identity_impersonation_path` (VERIFIED). Monitor, budget, forecast, report and analysis workers submit signed plans to the broker's JOB class and never hold serving credentials (C-09, D-33). dbt-snowflake has no impersonation parameter, so each dbt task role is itself the central transform WIF identity.
7. **Policy attachment.** Policies attach to the insert-only revision tables of [ADR-014](ADR-014-analytical-revisions.md); readers hold `SELECT` only on secure views, there are no future grants on base tables, and a migration/CI gate fails if `POLICY_REFERENCES` does not cover every base table a serving view reads.

Why: per-profile users need an IAM role and a Snowflake user created at runtime for every scope change, consume the IAM quota and multiply pools, while adding no protection over per-profile roles because the broker must be able to assume every profile anyway (X-10). The `CURRENT_ROLE()`-only rule and disabled secondary roles close a verified widening path (G-SEC-01).

Consequences: separation between profiles of the same tenant rests on the broker (residual risk RR-01), which is no weaker than the original decision. Admission caps 200 active profiles per tenant; Snowflake role-count limits, the memoizable-function policy variant and the Lattice transport are TO VERIFY LIVE (SEC-005, API-002). The signed-context trusted broker remains the documented revisit option.

Validation obligation: SEC-005/SEC-105 live evidence must include a restricted-profile session that attempts secondary roles and alternate roles, a mutation test replacing `CURRENT_ROLE()` by `IS_ROLE_IN_SESSION()` that must fail the suite, IAM/Snowflake/PostgreSQL drift reconciliation, and revocation under dropped invalidation events.

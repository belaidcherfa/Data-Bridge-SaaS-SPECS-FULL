# Identity, authorization, isolation and privacy

Canonical domain contract. Owner: Security. Implementation state: NOT_STARTED.


## Threat boundaries and identities

Protect against unauthenticated attackers, authenticated foreign tenants, restricted same-tenant users, compromised connectors, malicious SQL/tag text and compromised notification destinations. Separate user, control, connector, data and future action planes. Central operator roles are privileged, private, time-bound and audited; they are not product roles. A tenant owner cannot access another tenant by changing request IDs, prefixes or connector configuration.

Cognito handles web authentication; Snowflake WIF handles machine authentication. Use authorization-code flow with PKCE. FastAPI acts as a server-side session BFF (amended 2026-09-28, G-SEC-06: not "stateless") with an opaque `__Host-` Secure/HttpOnly/SameSite cookie whose SHA-256 keys a PostgreSQL session row holding the KMS-encrypted refresh token; defaults idle 30 min / absolute 12 h, session-ID rotation on login, tenant switch and step-up, single-flight refresh ([SEC backlog](../22-implementation-readiness/backlog/SEC.md) Appendix D); process memory is not session truth. CSRF tokens protect mutations; validate issuer, audience/client, token_use, expiry and allowed signing algorithm. Never store tokens in localStorage or URL parameters. Short-lived access plus membership checks bound revocation. Human administrators require MFA. (amended 2026-09-28, G-SEC-07) Local users all require MFA (TOTP or passkey with user verification); SMS and e-mail OTP are not MFA factors; step-up means `auth_time` ≤ 10 min for the actions of the four-eyes policy. The active tenant is a per-request selector (`X-Bridge-Tenant` header mirrored by the `/t/{tenant_slug}/` route prefix, authorized against durable membership), never session state (G-API-13). Because R1 has no self-service trial (D-17), tenants are created through the operator-provisioned tenant workflow (CTL-102, G-SEC-24), which also triggers the tenant serving principal (SEC-105). SAML/OIDC federation uses stable subject identifiers and explicit IdP-to-tenant bindings; email domain alone never grants membership. Federated MFA is enforced at the external IdP and verified through the agreed tenant policy, not assumed from Cognito local MFA settings. [Cognito SAML](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-saml-idp.html).

## Role and scope matrix

| Role | Allowed mutations | Read scope |
|---|---|---|
| Organization Owner | Ownership transfer, subscription, all tenant administration | Granted tenant organizations/accounts |
| Organization Admin | Members, teams, settings and integration administration; no ownership transfer | Explicit grant scope |
| FinOps Admin | Prices, tags, allocation, budgets, close/restate chargeback | Explicit financial scope |
| Snowflake Admin | Connections, source configuration, sync/replay requests | Granted technical/financial modules |
| Team Admin | Own team membership within delegation bounds, team budgets/reports | Granted team/account intersection |
| Analyst | Own saved views/reports and assigned actions; no publish/close | Granted analytical scope |
| Viewer | Personal presentation preferences only | Granted analytical scope |
| Auditor | No business mutation | Granted financial/audit evidence, SQL only if separately authorized |

Permissions are explicit capabilities; roles are defaults. A scope is a union of grant clauses, each clause an intersection of organization/account/team/resource restrictions. Never implement account A OR team Finance when the grant means account A AND Finance. (amended 2026-09-28, G-SEC-02) Every clause states every dimension explicitly, as a non-empty ID list or the literal `"*"`; an omitted dimension is rejected (422 `SCOPE_DIMENSION_MISSING`), never read as ANY; empty grants yield no data. One library (SEC-101) compiles PostgreSQL predicates, Snowflake entitlement rows, profile hashes and cache keys from the same canonical form ([SEC backlog](../22-implementation-readiness/backlog/SEC.md) Appendix B). (amended 2026-09-28, G-SEC-03, G-ALC-04) Grants reference usage groups `(group_set_id, group_id, include_descendants)`, not people teams, and follow the published hierarchy; broadening through a reclassification is controlled at publication by an access-impact review and an epoch bump rather than by pinning versions in grants.

(amended 2026-09-28, G-SEC-04, G-SEC-05) The capability catalog (≈ 55 capabilities with kind visibility/mutation, scope binding, grantability, four-eyes and step-up flags) and the role defaults are normative in [SEC backlog](../22-implementation-readiness/backlog/SEC.md) Appendix C; R1 has no custom roles and UI labels use the eight role names above. Separation of duties is generic maker-checker (SEC-102): an approval binds object, revision, content hash and action; approver ≠ requester and ≠ last editor; any revision change voids it. It applies at least to period close and restatement (`finance.period.close.request/approve`, `finance.period.restate.request/approve`), statement issue, price overrides, rule publication, FULL SQL access, SSO enforcement, ownership transfer and support access.

## PostgreSQL RLS

Tenant-owned tables have `tenant_id UUID NOT NULL`; composite unique keys and foreign keys include tenant_id. (amended 2026-09-28, G-SEC-10) Referential-integrity checks (unique, primary and foreign keys) always bypass row security (VERIFIED), so a single-column foreign key or a global unique index on tenant data is a covert channel: use composite keys everywhere and never reveal constraint details in errors. Runtime users are neither owners nor BYPASSRLS/superusers; the role model (owner NOLOGIN, migrator, api, worker, dispatcher, audit exporter, broker, read-only operator), policy templates per table class, the `SECURITY DEFINER` session resolver and the catalog lint are defined in the SEC backlog Appendix E and built by CTL-101. Enable and FORCE RLS on every applicable table. Global identity subjects are separate from tenant memberships and exposed only through scoped joins. Migration owner is not an API credential.

Illustrative policy and transaction pattern (implement with parameter binding):

```sql
BEGIN;
SELECT set_config('app.tenant_id', :authorized_tenant_uuid, true);
-- RLS USING and WITH CHECK both enforce tenant_id =
-- NULLIF(current_setting('app.tenant_id', true), '')::uuid
-- Execute only the authorized operation, then COMMIT/ROLLBACK.
```

Missing tenant context yields no rows/no writes; malformed context is a safe error. Transaction-local context must clear on pool reuse. This policy protects tenant isolation; account/team scope also requires validated repository predicates and grants. [PostgreSQL policy behavior](https://www.postgresql.org/docs/current/ddl-rowsecurity.html).

## Snowflake serving RLS

Implement ADR-005 as amended on 2026-09-28 (D-02; [ADR-005](../architecture/adr/ADR-005-analytical-authorization.md), [SEC backlog](../22-implementation-readiness/backlog/SEC.md) Appendix A): one WIF service user and one identity-only IAM role per **tenant**, one Snowflake role per immutable, content-addressed normalized permission profile. Row access policies resolve the tenant from `CURRENT_USER()` through `SECURITY.TENANT_PRINCIPAL` and entitlements from **`CURRENT_ROLE()` only** through `SECURITY.PROFILE_ENTITLEMENT`; never `IS_ROLE_IN_SESSION()`, which secondary roles would widen. Tenant users are created with `DEFAULT_SECONDARY_ROLES = ()` plus a session policy blocking secondary roles, because new users default to `('ALL')` since bundle 2024_08 (VERIFIED). Profile roles have no policy-table write/ownership, RAW read or alternate privileged roles. Apply row access policy to every readable serving boundary, including new versions and exports. Aggregate only authorized grain: a team-restricted identity must never query an account-only total that includes hidden teams. Shared and unallocated costs require explicit scope grants.

A private query broker alone resolves the authorized (tenant user, profile role); request bodies cannot choose it. (amended 2026-09-28, D-02, D-22) The broker is a separate internal service with its own task role, the only component able to assume tenant serving identities, reached over private authenticated transport (SigV4 through VPC Lattice preferred, TO VERIFY LIVE) with a server-signed SELECT-only plan. Pool key = (environment, tenant user, profile role); the permission epoch is not in the pool key but binds cursors, jobs, cache keys and download links. Scope changes map the member to another profile (fail closed until it is active) before broadening; account-grain facts are readable only by profiles with an unrestricted group dimension, and ratios whose denominator is outside the profile return null with `DENOMINATOR_OUTSIDE_SCOPE`. Validate central Enterprise-or-higher policy capability before provisioning; customer Standard can still connect with supported sources. [Snowflake row policy use](https://docs.snowflake.com/en/user-guide/security-row-using).

## Revocation and caches

Every mutation increments permission_epoch transactionally and emits an outbox event. (amended 2026-09-28, G-SEC-12) Two counters exist: `memberships.permission_epoch` (any grant or membership change) and `tenants.authz_epoch` (data-visibility events only: profile retirement, privacy-mode change, access-relevant group-set publication). On every sensitive request/job submission/download, read current membership/epoch from durable control state in one indexed call (`identity.resolve_session()`); cached authorization cannot override a revocation; events only accelerate. The broker re-reads authorization every 10 s for running statements and cancels them; cursors, jobs and links bind (subject, membership epoch, profile hash); downloads go through one authorizing broker that redirects to a presigned URL valid 30 s ([SEC backlog](../22-implementation-readiness/backlog/SEC.md) Appendix F). Before returning an asynchronous result, recheck scope. Invalidate principal pools and browser caches on tenant switch/logout. Target revocation within 30 seconds, measured under dropped invalidation events; financial close/export checks use a fresh durable check.

## Privacy and audit

Default SANITIZED; AST-based SQL parser strips literals, unapproved comments and unsafe query-tag fields before Arrow/S3. Parsing failure stores no SQL. (amended 2026-09-28, G-SEC-14, G-SEC-15, G-WRK-01) Order: the WRK-101 workload-metadata library first extracts allowlisted keys from leading/trailing comments and QUERY_TAG, then the SQL body is sanitized with all comments stripped; the sanitized-text cache is keyed by (tenant, account, parameterized-hash version and value, sanitizer version) and never carries comment metadata. The `sqlglot` logger is forced to CRITICAL with a filter dropping `sqlglot.*` records, because the library logs raw SQL on unsupported syntax (VERIFIED); any `Command` or unknown node is a parse failure and the output is re-tokenized to prove it has no literals or comments. An optional lexical tier is decided in SEC-007-S02. (amended 2026-09-28, D-10) User names and e-mail-like tag values are replaced at extraction by per-tenant HMAC pseudonyms; the identity dictionary lives only in PostgreSQL and is resolved by the API for profiles holding `identity.resolve`; erasure deletes the dictionary entry and writes a tombstone to the OPS-104 log ([ADR-009 amendment](../architecture/adr/ADR-009-privacy-and-retention.md), SEC-103). FULL is opt-in and a separate read permission; METADATA_ONLY still supports source-provided query hashes. Do not recompute source hashes from sanitized text and claim equivalence. Restrict user names, object names, tags, report narratives and error payloads too.

Audit events are append-only logical records with tenant, actor/service, action, object/version, redacted before/after, UTC timestamp, request ID and outcome. (amended 2026-09-28, G-SEC-17) Events also carry IP and user agent (PRD §118); denied or failed mutations are audited in a separate short transaction after rollback; the exporter selects unexported rows through an export ledger (not a time watermark), chains digests per tenant, signs batches with a KMS asymmetric key and writes to a log-archive account bucket under Object Lock GOVERNANCE for 365 days. Support access (SEC-104) is a time-bound, tenant-approved read-only synthetic membership: default 4 h, maximum 8 h, scopes `health_read` and `analytics_read` in R1. Outbox exports signed/hash-linked batches to a separately permissioned S3 audit store; hash chains detect tampering but do not make a compromised signer infallible. Audit retention and erasure exceptions require approved policy; no compliance certification is implied.


## Implementation sequence

(amended 2026-09-28) The dependency and gate columns below are the original index. Execution follows the revised graph ([revised-task-graph.json](../22-implementation-readiness/revised-task-graph.json), [revised critical path](../22-implementation-readiness/REVISED_CRITICAL_PATH.md)) and phases P0–P6 of the [release plan](../22-implementation-readiness/RELEASE_PLAN.md); new tasks, revised steps, dependencies and task acceptance are in [backlog/SEC.md](../22-implementation-readiness/backlog/SEC.md).

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [SEC-001](../tasks/SEC/SEC-001.md) | Model threats and classify sensitive data | INF-002, FND-004 | M1 |
| [SEC-002](../tasks/SEC/SEC-002.md) | Implement Cognito login, sessions and local MFA | SEC-001, INF-006, UX-001 | M1 |
| [SEC-003](../tasks/SEC/SEC-003.md) | Add tenant-bound SAML and OIDC SSO | SEC-002, UX-001 | M1 |
| [SEC-004](../tasks/SEC/SEC-004.md) | Implement scoped RBAC and tenant RLS foundation | SEC-002, INF-004 | M1 |
| [SEC-005](../tasks/SEC/SEC-005.md) | Provision identity-bound Snowflake serving policies | SEC-004, INF-005, INF-008 | M1 |
| [SEC-006](../tasks/SEC/SEC-006.md) | Enforce revocation across sessions, jobs and cache | SEC-004, SEC-005 | M1 |
| [SEC-007](../tasks/SEC/SEC-007.md) | Sanitize SQL, tags and errors before persistence | SEC-001, FND-004 | M1 |
| [SEC-008](../tasks/SEC/SEC-008.md) | Create audit trail and early isolation attack suite | SEC-006, SEC-007 | M1 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

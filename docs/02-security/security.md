# Identity, authorization, isolation and privacy

Canonical domain contract. Owner: Security. Implementation state: NOT_STARTED.


## Threat boundaries and identities

Protect against unauthenticated attackers, authenticated foreign tenants, restricted same-tenant users, compromised connectors, malicious SQL/tag text and compromised notification destinations. Separate user, control, connector, data and future action planes. Central operator roles are privileged, private, time-bound and audited; they are not product roles. A tenant owner cannot access another tenant by changing request IDs, prefixes or connector configuration.

Cognito handles web authentication; Snowflake WIF handles machine authentication. Use authorization-code flow with PKCE. FastAPI can act as a stateless BFF with an opaque Secure/HttpOnly/SameSite cookie and encrypted refresh-token record in PostgreSQL; process memory is not session truth. CSRF tokens protect mutations; validate issuer, audience/client, token_use, expiry and allowed signing algorithm. Never store tokens in localStorage or URL parameters. Short-lived access plus membership checks bound revocation. Human administrators require MFA. SAML/OIDC federation uses stable subject identifiers and explicit IdP-to-tenant bindings; email domain alone never grants membership. Federated MFA is enforced at the external IdP and verified through the agreed tenant policy, not assumed from Cognito local MFA settings. [Cognito SAML](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-saml-idp.html).

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

Permissions are explicit capabilities; roles are defaults. A scope is a union of grant clauses, each clause an intersection of organization/account/team/resource restrictions. Never implement account A OR team Finance when the grant means account A AND Finance. Deny unspecified dimensions; empty grants yield no data. Group set IDs and versions are part of scope to prevent reclassification broadening access.

## PostgreSQL RLS

Tenant-owned tables have `tenant_id UUID NOT NULL`; composite unique keys and foreign keys include tenant_id. Runtime users are neither owners nor BYPASSRLS/superusers. Enable and FORCE RLS on every applicable table. Global identity subjects are separate from tenant memberships and exposed only through scoped joins. Migration owner is not an API credential.

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

Implement ADR-005: each distinct tenant permission profile maps to a constrained WIF reader identity. Policy uses authenticated `CURRENT_USER()` and a security-owned entitlement table; profile identities have no policy-table write/ownership, RAW read or alternate privileged roles. Disable secondary roles. Apply row access policy to every readable serving boundary, including new versions and exports. Aggregate only authorized grain: a team-restricted identity must never query an account-only total that includes hidden teams. Shared and unallocated costs require explicit scope grants.

A private query broker alone resolves authorized profile→IAM/Snowflake principal; request bodies cannot choose it. Pool key includes environment, tenant, profile, permission_epoch and principal. Scope changes revoke the old profile mapping before broadening/reissuing. Validate central Enterprise-or-higher policy capability before provisioning; customer Standard can still connect with supported sources. [Snowflake row policy use](https://docs.snowflake.com/en/user-guide/security-row-using).

## Revocation and caches

Every mutation increments permission_epoch transactionally and emits an outbox event. On every sensitive request/job submission/download, read current membership/epoch from durable control state; cached authorization cannot override a revocation. Before returning an asynchronous result, recheck scope. Invalidate principal pools and browser caches on tenant switch/logout. Target revocation within 30 seconds, measured under dropped invalidation events; financial close/export checks use a fresh durable check.

## Privacy and audit

Default SANITIZED; AST-based SQL parser strips literals, unapproved comments and unsafe query-tag fields before Arrow/S3. Parsing failure stores no SQL. FULL is opt-in and a separate read permission; METADATA_ONLY still supports source-provided query hashes. Do not recompute source hashes from sanitized text and claim equivalence. Restrict user names, object names, tags, report narratives and error payloads too.

Audit events are append-only logical records with tenant, actor/service, action, object/version, redacted before/after, UTC timestamp, request ID and outcome. Outbox exports signed/hash-linked batches to a separately permissioned S3 audit store; hash chains detect tampering but do not make a compromised signer infallible. Audit retention and erasure exceptions require approved policy; no compliance certification is implied.


## Implementation sequence

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [SEC-001](../tasks/SEC/SEC-001.md) | Model threats and classify sensitive data | INF-002, FND-004 | M1 |
| [SEC-002](../tasks/SEC/SEC-002.md) | Implement Cognito login, sessions and local MFA | SEC-001, INF-006 | M1 |
| [SEC-003](../tasks/SEC/SEC-003.md) | Add tenant-bound SAML and OIDC SSO | SEC-002 | M1 |
| [SEC-004](../tasks/SEC/SEC-004.md) | Implement scoped RBAC and tenant RLS foundation | SEC-002, INF-004 | M1 |
| [SEC-005](../tasks/SEC/SEC-005.md) | Provision identity-bound Snowflake serving policies | SEC-004, INF-005 | M1 |
| [SEC-006](../tasks/SEC/SEC-006.md) | Enforce revocation across sessions, jobs and cache | SEC-004, SEC-005 | M1 |
| [SEC-007](../tasks/SEC/SEC-007.md) | Sanitize SQL, tags and errors before persistence | SEC-001, FND-004 | M1 |
| [SEC-008](../tasks/SEC/SEC-008.md) | Create audit trail and early isolation attack suite | SEC-006, SEC-007 | M1 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

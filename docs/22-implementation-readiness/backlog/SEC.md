# SEC — Implementation-readiness review and production backlog

Canonical contract: [security.md](../../02-security/security.md). Tasks reviewed: [SEC-001](../../tasks/SEC/SEC-001.md), [SEC-002](../../tasks/SEC/SEC-002.md), [SEC-003](../../tasks/SEC/SEC-003.md), [SEC-004](../../tasks/SEC/SEC-004.md), [SEC-005](../../tasks/SEC/SEC-005.md), [SEC-006](../../tasks/SEC/SEC-006.md), [SEC-007](../../tasks/SEC/SEC-007.md), [SEC-008](../../tasks/SEC/SEC-008.md). Also read: ADR-001, ADR-004, ADR-005, ADR-007, ADR-008, ADR-009, ADR-012, [validation-strategy.md](../../15-testing/validation-strategy.md) (adversarial isolation matrix), [RUNBOOKS.md](../../16-observability/RUNBOOKS.md) RB-09/RB-12, PRD §56–§66, §113–§118, §135–§137, [sign-in.md](../../21-ui-ux/pages/sign-in.md), [settings.md](../../21-ui-ux/pages/settings.md), [semantic-api.md](../../09-api/semantic-api.md), [allocation.md](../../11-allocation/allocation.md), [launch.md](../../20-launch/launch.md). Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

Companion file: [CTL.md](CTL.md) owns the control-plane kernel (outbox, idempotency, migrations, pools, Redis). Several SEC resolutions depend on the new task **CTL-101** defined there.

## 1. Verdict

The security contract states the right invariants (fail-closed RLS, identity-bound Snowflake policies, epoch revocation, sanitize-before-transport) but none of them is implementable as written: there is no scope grammar, no capability matrix, no entitlement DDL or row-policy body, no session model, no revocation mechanism beyond "read durable state", and no pseudonymization design. SEC-004/SEC-005/SEC-006 each hide 2–4 weeks of design-plus-build behind three generic micro-steps. The biggest risks are (1) the Snowflake serving model (D-02) — a wrong choice between `CURRENT_ROLE()` and `IS_ROLE_IN_SESSION()` combined with Snowflake's post-2024_08 default of `DEFAULT_SECONDARY_ROLES=('ALL')` silently turns a restricted profile into the union of every profile in the tenant; (2) hidden totals leaking through account-grain aggregates and percentages; (3) a hidden dependency cycle (SEC-006/SEC-008 need the outbox built by CTL-004, which transitively depends on SEC-008); (4) sqlglot logging raw SQL on unsupported syntax. Author first: the ADR-005 amendment in Appendix A, the scope grammar (Appendix B), the capability/SoD matrix (Appendix C) and the session model (Appendix D). With those, the domain is implementable in ≈520–810 senior hours for R1 (not 8 × 2–6 h); since D-20 (2026-09-28) R1 also includes SEC-003 SAML/OIDC SSO, and D-11's 365-day sanitized text adds SEC-007-S17 (§6: 567–881 h).

## 2. Findings

### G-SEC-01 · ADR-005 has no implementable serving-authorization design; the D-02 recommendation needs two corrections
Severity: BLOCKER · Type: GAP / CONTRADICTION
Evidence: `SEC-005.md` — "SECURITY.principal_entitlement(principal,tenant,profile,account,group_set,group,epoch,active)" is the entire schema; no policy body, provisioning flow, revocation or GC. `DECISIONS_REQUIRED.md` D-02 — "row access policies check CURRENT_USER() → tenant and CURRENT_ROLE()/IS_ROLE_IN_SESSION() → profile entitlements; pools keyed (tenant user, profile role, epoch)". Vendor facts: new users get `DEFAULT_SECONDARY_ROLES=('ALL')` unless explicitly set to `()` — VERIFIED (search snippet of docs.snowflake.com/en/release-notes/bcr-bundles/2024_08/bcr-1692, 2026-09-28); `CURRENT_ROLE()` ignores secondary roles whereas `IS_ROLE_IN_SESSION()` considers them — VERIFIED (search snippet of docs.snowflake.com/en/user-guide/security-row-using, 2026-09-28).
Why it matters: every profile role of a tenant is granted to the same tenant WIF user. If the policy used `IS_ROLE_IN_SESSION(role)` and secondary roles were active (the default for newly created users), a session of the restricted "Finance on A1" profile would satisfy the entitlement rows of every other profile of that tenant → a restricted reader sees the whole tenant. Separately, putting `permission_epoch` in the pool key either (tenant epoch) drops every pool of the tenant on any unrelated permission edit (login storm; WIF login is a network round trip per connection) or (membership epoch) prevents pool sharing between members with the same profile.
Resolution: adopt Appendix A as the ADR-005 amendment: (a) policies use **`CURRENT_ROLE()` only**, never `IS_ROLE_IN_SESSION()`; (b) every tenant user is created with `DEFAULT_SECONDARY_ROLES = ()` and a session policy with `ALLOWED_SECONDARY_ROLES = ()` (blocks secondary roles, enforced immediately for existing sessions — VERIFIED search snippet docs.snowflake.com/en/user-guide/session-policies-using, 2026-09-28); (c) profiles are **content-addressed and immutable** (role name derived from the profile hash), so pools are keyed `(env, tenant_user, profile_role)` with no epoch, and revocation is enforced by the broker's per-request durable check (Appendix F) plus entitlement deactivation on GC; (d) `TENANT_PRINCIPAL` (user→tenant binding) is written by a different identity than `PROFILE_ENTITLEMENT`, so a compromised profile provisioner cannot cross tenants.
Affects: SEC-005, SEC-006, SEC-105, API-002, OPS-004, OPS-007 (recovery must recreate principals/profiles).

### G-SEC-02 · Scope grammar is prose only; "deny unspecified dimensions" contradicts the example grants
Severity: BLOCKER · Type: AMBIGUITY
Evidence: `security.md` — "A scope is a union of grant clauses, each clause an intersection of organization/account/team/resource restrictions … Deny unspecified dimensions; empty grants yield no data." PRD §114 example "scope = Finance + PROD account" names two dimensions and leaves organization unspecified.
Why it matters: read literally, a clause that omits organization denies everything; read loosely, omission means ANY and a forgotten dimension silently broadens access. PostgreSQL predicates, Snowflake entitlement rows, cache keys and profile hashes will each be implemented with a different interpretation.
Resolution: Appendix B grammar: every clause states every dimension explicitly as a non-empty ID list or the literal `"*"`; omission is a 422 `SCOPE_DIMENSION_MISSING`, never ANY. Account restriction implies its organization (accounts are tenant-unique UUIDs; an account transferred between organizations keeps matching). Canonical form = sorted set of maximal atoms (Appendix B.3), hash = SHA-256 of RFC 8785 JSON. One library (`packages/authz_scope`, SEC-101) compiles PG predicates and Snowflake entitlement rows from the same canonical form.
Affects: SEC-004, SEC-005, SEC-101, CTL-003, CTL-006, CTL-007, API-002, ALC-004, GOV-001.

### G-SEC-03 · "Team" means two different things (people team vs usage group)
Severity: HIGH · Type: AMBIGUITY
Evidence: `control-plane.md` lists `identity.teams, team_members` **and** `governance.usage_group_sets`; `security.md` role matrix — Team Admin "Own team membership … team budgets/reports", read scope "Granted team/account intersection"; `allocation.md` — "Group-limited users see only authorized allocations".
Why it matters: if a grant references an identity team, the Snowflake policy has nothing to match (serving rows carry `group_id`, not people teams); if it references a usage group, "Team Admin manages own team membership" has no link to what data the team sees. Implementers will join the two by name ("Finance"), which is exactly the name-based identity the specs forbid.
Resolution: identity team = set of people (membership administration, notification audiences); usage group = cost-ownership target inside a group set. Grants reference **usage groups only** `(group_set_id, group_id)`. `identity.teams.linked_group_set_id/linked_group_id` (nullable, one link per team) lets a Team Admin's default invitation scope be pre-filled from the link, but the grant stored is always explicit. Team Admin delegation bound = the Team Admin's own `member.manage` grant scope (Appendix C.3).
Affects: SEC-004, SEC-101, CTL-001, CTL-003, ALC-004.

### G-SEC-04 · No capability matrix; UI role vocabulary contradicts the 8 PRD roles; custom capabilities multiply profiles
Severity: BLOCKER · Type: GAP / CONTRADICTION
Evidence: `security.md` — "Permissions are explicit capabilities; roles are defaults" (no capability list). `settings.md` settings-roles — rows "FinOps admin / Group viewer / Platform admin" and "Role editor: Choose named capabilities, allowed scopes…"; PRD §114 lists Organization Owner … Auditor.
Why it matters: every route handler will invent its own permission string; "Platform admin" and "Group viewer" are not roles; per-member capability editing interacts with Snowflake profiles (data-visibility capabilities such as full SQL text change the profile hash).
Resolution: Appendix C: ≈55 named capabilities (45 matrix rows) × 8 roles, grantable extras, delegation rule, and which capabilities are **data-visibility** capabilities (included in the profile hash) versus **mutation** capabilities (checked in PG only). R1 has no custom roles: a grant = (one of 8 roles, optional extra grantable capabilities from an allowlist, scope clauses). UI labels must use the PRD role names (fix in UX backlog).
Affects: SEC-004, SEC-102, CTL-003, every route in API/ALC/GOV/RPT/FIN.

### G-SEC-05 · Separation of duties / maker-checker is required by UI and runbooks but specified nowhere
Severity: HIGH · Type: GAP
Evidence: `settings.md` — FinOps admin "Financial close: Approval required"; "Sensitive changes: Step-up authentication, approval and audited effective policy"; `ALC-003` — "approval references hash and reviewer"; `FIN-010` — "authorized approver"; `launch.md` — "Payment evidence is recorded by an authorized finance operator, with independent review for corrections"; RB-06 "restatement requiring finance approval". None states approver ≠ author, what is bound, or what invalidates an approval.
Why it matters: without a rule, a single FinOps Admin can author a price override, approve it, publish it and close the period — the exact control a SOC 2-ready product (D-25) and any customer finance team will test first.
Resolution: generic `governance.approvals` (Appendix C.4): approval binds `(object_type, object_id, revision, content_sha256, action)`; approver ≠ requester and ≠ last editor of the approved revision; approver must hold the checker capability over the object's full scope at approval **and** execution time; any revision change voids it; 7-day expiry; step-up auth (≤10 min since `auth_time`) for both. Default policy per action in Appendix C.4 (close, restatement, statement issue, price override, rule publication, FULL SQL, SSO enforcement, ownership transfer, support access). Single-admin tenants: `SELF_APPROVAL_WITH_STEPUP` allowed only where the table says so and is flagged in audit and on the statement.
Affects: SEC-102, FIN-002, FIN-010, ALC-003, SEC-003, SEC-007, SEC-104, CTL-007.

### G-SEC-06 · The BFF session model is unspecified (and "stateless BFF" contradicts "durable session record")
Severity: HIGH · Type: GAP / CONTRADICTION (LOW)
Evidence: `security.md` — "FastAPI can act as a stateless BFF with an opaque … cookie and encrypted refresh-token record in PostgreSQL"; `SEC-002` — "auth.session stores encrypted refresh handle, expiry and revoke time"; UI `settings-security` — "Session minutes" field. No idle/absolute timeout, rotation, refresh concurrency, logout-everywhere, tenant switch, cookie attributes or CSRF token type.
Why it matters: refresh-token rotation (Cognito, Essentials+) combined with parallel browser requests produces spurious logouts unless refresh is single-flighted; missing idle/absolute limits fail any enterprise security questionnaire; "stateless" invites a JWT-in-cookie design that cannot be revoked in ≤30 s.
Resolution: Appendix D (server-side session row keyed by SHA-256 of a 256-bit opaque `__Host-` cookie, KMS-envelope-encrypted Cognito refresh token, idle 30 min / absolute 12 h defaults, sid rotation on login/tenant switch/step-up, single-flight refresh with Cognito `RetryGracePeriodSeconds=30`, synchronizer CSRF token = HMAC(session), logout-everywhere). Refresh token rotation and passkeys require the Cognito **Essentials** tier (VERIFIED search snippet aws.amazon.com/about-aws/whats-new/2025/04/amazon-cognito-refresh-token-rotation/, 2026-09-28). Wording fix: "server-side session BFF", not "stateless".
Affects: SEC-002, SEC-006, UX-002, INF-006.

### G-SEC-07 · MFA methods and step-up are undefined; passkeys only count as MFA under a specific Cognito setting
Severity: HIGH · Type: GAP / VENDOR-FACT
Evidence: `security.md` — "Human administrators require MFA"; `sign-in.md` /mfa — "A step-up check before sensitive access"; `settings.md` — "Step-up authentication". Vendor: Cognito passkeys are a first factor (Essentials+); they satisfy MFA only when `WebAuthnConfiguration.FactorConfiguration = MULTI_FACTOR_WITH_USER_VERIFICATION`, and users must also keep another MFA method; MFA factors are SMS, TOTP, email OTP — VERIFIED (search snippets of docs.aws.amazon.com Cognito API `WebAuthnMfaSettingsType` and "Authentication flows", 2026-09-28). Cognito MFA does not apply to users signing in through a SAML/OIDC IdP (`security.md` already says federated MFA is enforced upstream).
Why it matters: "require MFA for admins" with SMS enabled is SIM-swap-weak and costs per message; passkey-only users locked out when the passkey is lost; federated admins' MFA is unknown unless asserted.
Resolution: R1 local users: MFA **required for all users** (not only admins — roles change after enrolment), factors TOTP + passkey (`MULTI_FACTOR_WITH_USER_VERIFICATION`); SMS and email-OTP MFA disabled (email OTP allowed only for recovery per Cognito flow). Federated: tenant SSO config records `mfa_assertion = REQUIRED_AMR|TRUSTED_IDP_POLICY`; with REQUIRED_AMR the callback must carry an MFA-indicating `amr`/`AuthnContextClassRef` mapped attribute, else deny. Step-up = `auth_time` ≤ 10 min for actions in Appendix C.4; re-authentication via Cognito `prompt=login` / SAML `ForceAuthn` — **TO VERIFY LIVE** (if unsupported, step-up = full logout + login).
Affects: SEC-002, SEC-003, SEC-102.

### G-SEC-08 · Cognito tier, quotas and multi-tenant IdP limits are not planned
Severity: HIGH · Type: RISK / VENDOR-FACT
Evidence: PRD §113 lists Entra/Okta/SAML/OIDC; nothing on user-pool topology. Vendor: Essentials $0.015/MAU (10k free), Plus $0.02/MAU, SAML/OIDC federated MAU $0.015 above 50 free, M2M billed per successful token request (≈$0.00225; per-app-client dimension removed Nov 2025) — VERIFIED via search snippets (aws.amazon.com/cognito/pricing and secondary sources, 2026-09-28; re-check at contract time). Identity providers per user pool: secondary sources disagree (10 vs 300) — **TO VERIFY LIVE** in Service Quotas.
Why it matters: one IdP per SSO tenant in a single pool hits the IdP quota at tenant N (N unknown); federated MAUs are billed separately; Plus-tier threat protection may be wanted for credential-stuffing defence on email/password.
Resolution: one user pool per environment, Essentials tier (R1), one IdP object per SSO tenant named `t-<tenant_short>`; admission check refuses SSO configuration when `idp_count ≥ quota − 10%`; if the verified quota < 300, plan R2 pool sharding keyed by tenant (pool id stored on `identity.identity_providers`). Plus tier = owner cost decision (Owner question Q6). Cost model entry in OPS.
Affects: SEC-002, SEC-003, OPS-009.

### G-SEC-09 · Federation linking and home-realm discovery can link the wrong person or enumerate tenants
Severity: HIGH · Type: GAP
Evidence: `SEC-003` — "Test changed email, reused email across IdPs"; `sign-in.md` — "Workspace domain → Continue with SSO". No rule for NameID format, Cognito user identity per (provider, NameID), `email_verified` trust, JIT, or what the domain prompt reveals.
Why it matters: Cognito creates a distinct user per `(ProviderName, userId)`; a transient NameID (or email-format NameID that changes on rename) yields a new subject and either an orphaned membership or an unsafe email-based auto-link. A domain prompt answering "no such workspace" vs redirecting leaks which companies are customers.
Resolution: `identity.subject_identities(provider_id, provider_subject)` unique; SAML requires persistent NameID or a configured immutable attribute (Entra `objectidentifier`, Okta `user.id`); OIDC uses `sub` (Google: `sub`, and because Google's issuer is shared by every Google customer the binding also requires the `hd` claim to equal a verified tenant domain — SEC-003-S17). Linking a federated identity to an existing subject happens only through (a) a pending invitation accepted while authenticated by the tenant's bound IdP, or (b) an authenticated owner-approved "link identity" action; never by email equality. JIT (opt-in per tenant, R1) creates membership with role Viewer and **empty scope** (sees nothing until granted). Discovery endpoint `POST /v1/auth/discover {email}` always returns 200 with either an IdP redirect or the generic Cognito login, same latency envelope; verified domains are discovery hints only and require DNS TXT verification before activation.
Affects: SEC-003, CTL-003.

### G-SEC-10 · PostgreSQL RLS mechanics for global tables, workers, dispatcher, audit and definer paths are missing
Severity: BLOCKER · Type: GAP
Evidence: `security.md` — "Global identity subjects are separate from tenant memberships and exposed only through scoped joins"; `SEC-004` failure "background task forgets context"; `control-plane.md` — dispatcher "claims with FOR UPDATE SKIP LOCKED" across all tenants. Vendor: "Referential integrity checks, such as unique or primary key constraints and foreign key references, always bypass row security" — VERIFIED (search snippet of postgresql.org/docs/current/ddl-rowsecurity.html, 2026-09-28).
Why it matters: the session lookup (before a tenant is known), "list my tenants", cross-tenant claim queries of workers/dispatcher and the audit exporter all need rows outside one tenant context; without a designed pattern engineers disable FORCE RLS or connect as the owner. Single-column FKs or global unique indexes on tenant data are covert channels (a 409/23503 reveals that a foreign ID exists).
Resolution: Appendix E standard: role model (owner NOLOGIN / migrator / api / worker / dispatcher / audit_exporter / broker / ops_ro, all `NOBYPASSRLS`), policy templates per table class (tenant, subject-scoped global, queue, append-only), `SECURITY DEFINER` session resolver, role-targeted `USING (true)` policies only on allowlisted queue tables, composite FKs everywhere, catalog lint in CI, and the missing-context test for every table. Mechanism lives in CTL-101; identity policies in SEC-004.
Affects: SEC-004, CTL-101, CTL-004, SEC-008, all PG-backed domains.

### G-SEC-11 · Hidden dependency cycle: revocation and audit need the outbox, which is built after them
Severity: HIGH · Type: CONTRADICTION (dependency graph)
Evidence: `SEC-006` MT1 "Increment epoch and emit outbox in the same membership transaction"; `SEC-008` "Audit emit within transaction/outbox"; `task-index.json`: CTL-004 (outbox) ← CTL-003 ← SEC-008 ← SEC-006. The graph has no SEC-006 → CTL-004 edge, so the cycle is invisible but real.
Why it matters: SEC-006/SEC-008 will either create a private outbox table (two outboxes) or be blocked until CTL-004 exists, which cannot start until SEC-008 is done.
Resolution: new **CTL-101 Control DB kernel** (see CTL.md) creates `platform.outbox`, `platform.idempotency_requests`, `audit.events`, the unit-of-work and `emit_event()`/`emit_audit()` before SEC-004. CTL-004 keeps only the dispatcher/leases. Edges: SEC-004 +CTL-101; SEC-006 +CTL-101; CTL-003 −SEC-008 +CTL-101.
Affects: SEC-004, SEC-006, SEC-008, CTL-003, CTL-004.

### G-SEC-12 · "Revocation within 30 s under dropped invalidation events" has no mechanism or cost model
Severity: HIGH · Type: GAP
Evidence: `security.md` — "read current membership/epoch from durable control state … Target revocation within 30 seconds, measured under dropped invalidation events"; `SEC-006` — "Drop invalidation events deliberately"; no statement of which epoch (tenant vs membership), how in-flight Snowflake queries, cursors, async results, report links and presigned URLs are cut off.
Why it matters: an event-driven design fails the dropped-event test by construction; a cached-epoch design with TTL adds staleness; presigned S3 URLs cannot be revoked at all once issued.
Resolution: Appendix F: one indexed PG read per request (`identity.resolve_session()` returns session+membership+profile+epochs; ≈1 round trip, <1 ms server time; at 200 req/s ≈200 trivial qps), so API revocation is immediate at commit and events are only accelerators; the broker re-reads authz state every 10 s for running statements and cancels; cursors/jobs/links bind `(subject, membership_epoch, profile_hash)`; downloads go through an authorizing endpoint that redirects to a presigned URL valid **30 s**; emailed links never carry presigned URLs. Two counters: `memberships.permission_epoch` (per member) and `tenants.authz_epoch` (bumped only by data-visibility changes: profile retirement, privacy-mode change, access-relevant group-set publication).
Affects: SEC-006, CTL-006, API-003, API-004, RPT-005, UX-002.

### G-SEC-13 · Hidden-team totals and shared/unallocated costs leak through aggregates, ratios, "Other" buckets and autocomplete
Severity: HIGH · Type: GAP
Evidence: `security.md` — "a team-restricted identity must never query an account-only total that includes hidden teams. Shared and unallocated costs require explicit scope grants"; `allocation.md` — "neither hidden groups nor hidden grand totals leak through percentages". No row semantics for aggregate rows, no rule for ratio denominators, no rule for dimension dictionaries.
Why it matters: a "Finance = 30 % of account A1" chip reveals A1's total; an "Other" bucket computed from the account total reveals hidden groups' sum; an autocomplete listing group names reveals the org chart; `attribution_coverage` needs unallocated amounts.
Resolution: Appendix A.4 row semantics: account-grain facts use policy `RAP_ACCOUNT_SCOPED` that matches only clauses with unrestricted group dimension; group-grain facts use `RAP_GROUP_SCOPED`; sentinels `__SHARED__`/`__UNALLOCATED__` require clause flags; there are no "ALL groups" rows in group-grain tables. Semantic registry declares `denominator_scope` per ratio metric: if the denominator relation is not readable under the caller's profile, the metric returns `null` + reason `DENOMINATOR_OUTSIDE_SCOPE` (never a share of an unreadable total); "Other" = visible total − shown rows. Dimension dictionaries (accounts, groups, users, warehouses) are served from policy-protected serving tables, never from unscoped PG lists.
Affects: SEC-005, API-001, API-002, ALC-006, ALC-007, UX-004.

### G-SEC-14 · sqlglot logs raw SQL on unsupported syntax and is lenient by design
Severity: HIGH · Type: VENDOR-FACT / RISK
Evidence: sqlglot 30.20.0 (2026-09-27), Snowflake is an "Official" dialect, "The parser is intentionally lenient" — VERIFIED (pypi.org/project/sqlglot, 2026-09-28). `Parser._warn_unsupported()` calls `logger.warning(f"'{sql}' contains unsupported syntax. Falling back to parsing as a 'Command'.")` with `sql` = first `error_message_context` characters of the statement — VERIFIED (raw.githubusercontent.com/tobymao/sqlglot/main/sqlglot/parser.py, 2026-09-28). `SEC-007` — "strip sensitive text from exception chains and logs".
Why it matters: `CREATE USER x PASSWORD='…'`, `COPY INTO … CREDENTIALS=(AWS_SECRET_KEY='…')` and Snowflake Scripting are exactly the statements that fall back to `Command`; the library itself then writes the secret-bearing prefix to the application log, bypassing any sanitizer. `ParseError` messages also embed SQL context. "Parse succeeded" does not mean every literal was a `Literal` node.
Resolution: sanitizer runs with the `sqlglot` logger forced to `CRITICAL` and a logging filter that drops records from `sqlglot.*`; exceptions are caught and converted to an error class without message; any tree containing `exp.Command`, `exp.RawString` outside allowlisted positions, or unknown node types is treated as parse failure; output is validated by re-tokenizing the generated SQL and asserting it contains zero string/number/raw-string literal tokens and zero comments. Parser failure → lexical tier (G-SEC-15) or METADATA_ONLY. Pin sqlglot exactly; sanitizer_version bumps on upgrade and re-runs the corpus.
Affects: SEC-007, ING-003, WRK-001.

### G-SEC-15 · Comment/tag allowlist ordering and the proposed sanitized-text cache can misattribute dbt runs
Severity: MEDIUM · Type: GAP / VENDOR-FACT
Evidence: ADR-009 — "remove literals/comments except allowlisted structured workload metadata"; Snowflake removes leading comments from query text, hence dbt's `query-comment: append: true` — VERIFIED (search snippets docs.getdbt.com/reference/project-configs/query-comment and dbt-core PR #2199, 2026-09-28).
Why it matters: an allowlist that only inspects a leading comment misses every dbt run; caching sanitized text by `(account, QUERY_PARAMETERIZED_HASH)` is a good CPU optimization (1M queries/day × ~3 ms ≈ 50 CPU-min/day/account without cache) but queries differing only in comments share a parameterized hash — if the cached value included comment metadata, one run's `invocation_id`/`node_id` would be attached to another run.
Resolution: pipeline order: (1) extract trailing and leading block comments and QUERY_TAG, parse JSON (≤4 KB), keep only allowlisted keys (dbt: `app, dbt_version, profile_name, target_name, node_id, invocation_id`; Bridge: `bridge_finops`) with value regex `^[A-Za-z0-9_.:\-/]{1,256}$`; (2) sanitize the SQL body with **all** comments stripped; (3) cache only step 2 output keyed `(tenant_id, account_id, QUERY_PARAMETERIZED_HASH_VERSION, QUERY_PARAMETERIZED_HASH, sanitizer_version)` in the per-account-cycle process (LRU 100k entries). Optional lexical tier (challenges ADR-009 "on sanitizer failure drop SQL"): if AST parse fails but sqlglot tokenization succeeds with no unterminated token, replace every literal/comment token with `?` and mark `sanitizer_mode=LEXICAL`; tenant setting can disable it. Decision recorded in SEC-007-S02. With D-11's 365 days of sanitized text (owner decision 2026-09-28), the cache is also persisted between backfill chunks of one account (SEC-007-S17), because a per-process LRU never sees the hash repetition across days.
Affects: SEC-007, WRK-002 (dbt), ING-003.

### G-SEC-16 · Pseudonymization (D-10) needs a concrete design; the lead's "separately journaled dictionary" would recreate the problem
Severity: HIGH · Type: GAP / challenge to D-10 wording
Evidence: `DECISIONS_REQUIRED.md` D-10 — "maintain a per-tenant identity dictionary … as a small, separately journaled, deletable dataset"; `source-catalog.md` QUERY_HISTORY projects `USER_NAME, ROLE_NAME`; D-16 rule operators "eq, in, prefix, suffix, contains".
Why it matters: journaling the dictionary to the immutable S3 journal puts plaintext names back into immutable storage. Allocation/tag rules on the user dimension with prefix/contains operators cannot be evaluated over HMAC pseudonyms in dbt.
Resolution: Appendix G.2: HMAC-SHA256 with a per-tenant 256-bit key (KMS-envelope-encrypted, decrypt allowed only with encryption context `tenant_id`), pseudonym `u1_<base32(HMAC(key, "sf_user|"+account_id+"|"+upper(USER_NAME)))[:26]>`; the dictionary lives in **PostgreSQL** (`privacy.identity_dictionary`, tenant RLS, mutable, never exported to S3/Snowflake); the API resolves pseudonyms → display names after the Snowflake query for callers with `identity.resolve`; name search maps name→pseudonym in PG first. User-dimension rules allow only `eq/in` on names, compiled to pseudonyms at config publication; prefix/contains on user names are expanded against the dictionary at publication and re-published when the dictionary gains a matching user (R1: `eq/in` only; expansion R2). Erasure = delete dictionary row + insert tombstone `(tenant_id, pseudonym)` that suppresses re-population; residual = Aurora PITR window (35 days) — to be disclosed.
Affects: SEC-103 (new), SEC-007, ING-003, CTL-005, ALC-002, OPS-005.

### G-SEC-17 · Audit design gaps: denied mutations roll back their own audit, PRD fields missing, export ordering loses late commits
Severity: HIGH · Type: GAP / CONTRADICTION
Evidence: `SEC-008` oracle — "a denied mutation still creates a safe audit event"; `security.md` audit fields omit IP and user agent required by PRD §118 ("IP, user_agent"); `security.md` — "Outbox exports signed/hash-linked batches"; ADR-009 — "No irreversible Object Lock compliance mode by default".
Why it matters: if the audit row is written in the mutation's transaction, a denial (raised before commit) rolls it back; an exporter that walks `created_at` misses rows committed late with an earlier timestamp, breaking the chain or silently dropping evidence; IP/user-agent are personal data that interact with erasure.
Resolution: Appendix H: allowed outcomes are audited in the business transaction; denials/failures are audited in a separate short transaction after rollback; exporter selects "not yet exported" via an export ledger (not by time watermark) with a 2-minute settle delay; per-tenant hash chain; batches signed with a KMS asymmetric key (`ECC_NIST_P256`, `kms:Sign` only for the exporter role); S3 audit bucket in a separate log-archive account, Object Lock **GOVERNANCE** 365 days, bypass only via break-glass role with MFA + alarm; IP stored full in PG (365 d), exported as `/24` (IPv4) or `/48` (IPv6) plus KMS-encrypted full value under a per-tenant data key (tenant offboarding = key deletion).
Affects: SEC-008, CTL-101, OPS-005.

### G-SEC-18 · Support/operator access is required but has no model
Severity: MEDIUM · Type: GAP
Evidence: `operations.md` — "Support access is time-bound, reason-coded, approved by customer policy and audited; no shared admin passwords or unaudited impersonation"; `settings.md` privacy — "Support access duration minutes"; RUNBOOKS — "read-only `bridge-admin` CLI".
Why it matters: without a designed path, support staff will receive standing database or Snowflake access (cross-tenant by construction), which contradicts ADR-001's operator isolation and RB-09.
Resolution: SEC-104: `identity.support_access_grants(tenant_id, id, requested_by_operator, reason_code, case_ref, scope_json, capabilities[], approved_by_member, starts_at, expires_at ≤ 8 h, revoked_at)`; operator authenticates via the internal IdP (not Cognito customer pool) with hardware MFA; access materializes as a **read-only synthetic membership** with a support-specific profile (sanitized SQL, pseudonymous identities) and a visible banner + audit on every request; no impersonation of a real member; no write capabilities in R1.
Affects: SEC-104 (new), OPS-010, SEC-008.

### G-SEC-19 · Sign-in UX spec shows tenant scope, KPIs and CSV export before authentication
Severity: MEDIUM · Type: CONTRADICTION
Evidence: `sign-in.md` desktop composition — "Acme Group [v] | PRODUCTION / organization scope … [Explain] [Save view] [Export CSV]" and a DataTable with CSV on `/sign-in`; `security.md` — "Avoid disclosure before authorization".
Why it matters: a templated page shell rendered pre-auth will call scope/navigation APIs and display a tenant name — an enumeration and fixation surface; engineers following the ASCII will build it.
Resolution: `/sign-in` and `/mfa` use a separate unauthenticated layout with no scope bar, no API calls except `POST /v1/auth/discover` and `GET /v1/auth/login`; no table/CSV; generic copy. Handed to the UX backlog as a correction; SEC-002-S14 asserts via Playwright that no `/v1/*` data endpoint is called before session establishment.
Affects: SEC-002, UX-001.

### G-SEC-20 · Row access policies cannot be tag-propagated; new serving tables can be readable before the policy is attached
Severity: MEDIUM · Type: RISK
Evidence: `security.md` — "Apply row access policy to every readable serving boundary, including new versions and exports"; SEC-005 failure "New serving table lacks policy". Row access policies are attached per table/view (no tag-based row policy analogous to tag-based masking — TO VERIFY LIVE).
Why it matters: `FUTURE GRANTS` on the serving schema make a freshly created table readable before a dbt post-hook attaches the policy.
Resolution: readers hold `SELECT` only on **secure views** in `SERVING_API`; no future grants on `SERVING` base tables; views are created by migration/dbt in a role without reader grants and granted explicitly after a gate query shows `POLICY_REFERENCES` covers every base table the view reads; CI job `security/policy_coverage.sql` fails if any table in `SERVING` lacks the expected policy or any `SERVING_API` object is not secure. With D-05 (insert-only revisioned partitions) base tables are long-lived, so the gate runs on migration, not per dbt run.
Affects: SEC-005, DBT-006.

### G-SEC-21 · Privileged Snowflake/AWS provisioners and their blast radius are unassigned
Severity: HIGH · Type: GAP
Evidence: `SEC-005` — "Provision synthetic A/B/restricted-profile WIF users and reader roles"; ADR-004 — "iam:PassRole is restricted"; nobody holds `CREATE ROLE`, `CREATE USER`, `iam:CreateRole` at runtime.
Why it matters: the easiest implementation gives one "security admin" service `ACCOUNTADMIN`-like rights plus `iam:*`, whose compromise is a full cross-tenant breach.
Resolution: Appendix A.6 identity table: `TENANT_ONBOARDER` (CREATE USER, writes `TENANT_PRINCIPAL`; runs only in the operator-approved tenant provisioning workflow), `PROFILE_PROVISIONER` (CREATE ROLE, owns profile roles, writes `PROFILE_ENTITLEMENT`; cannot create users or write `TENANT_PRINCIPAL` → cannot cross tenants), `SECURITY_POLICY_OWNER` (NOLOGIN role owning policies, used by the reviewed CI deploy identity only), AWS `tenant-serving-provisioner` with `iam:CreateRole` constrained to path `/bridge/tenant-serving/` and a mandatory permissions boundary granting nothing (the WIF role needs no AWS permissions). Nightly reconciliation compares IAM roles ↔ Snowflake users/WORKLOAD_IDENTITY ↔ `TENANT_PRINCIPAL` ↔ PG and pages on drift. The query broker remains the single component able to assume every tenant role (inherent; D-22) — CloudTrail alarm on AssumeRole to >N distinct tenant roles per minute.
Affects: SEC-005, SEC-105, INF-005, INF-008, OPS-004.

### G-SEC-22 · IAM role quota is shared with per-account connector roles
Severity: MEDIUM · Type: VENDOR-FACT / RISK
Evidence: ADR-004 — "Provision an AWS role … per connected account"; D-02 adds one role per tenant. IAM roles per account: default 1,000, adjustable; maxima raised in 2026-05 — default VERIFIED (search snippet of docs.aws.amazon.com/IAM/latest/UserGuide/reference_iam-quotas.html, 2026-09-28), new maximum TO VERIFY LIVE.
Why it matters: benchmark profile (100 tenants × 5 accounts) = 500 connector roles + 100 tenant-serving roles + platform roles ≈ 650 of 1,000 before growth.
Resolution: quota gate in tenant/connection admission (`iam_roles_used ≥ 80 %` → block + page); request the increase at P1; record in OPS cost/quota model.
Affects: SEC-105, CON-001, OPS-008.

### G-SEC-23 · Error payload scrubbing ignores framework echo paths
Severity: MEDIUM · Type: GAP
Evidence: `control-plane.md` — "Response errors use code, message, request_id, retryable, field errors; no database text"; `SEC-007` — "strip sensitive text from exception chains and logs".
Why it matters: FastAPI/Pydantic v2 validation errors include the rejected `input` value in `detail[].input` by default (a secret pasted into a destination URL field is echoed and logged); Snowflake error messages quote literals ("Numeric value 'x' is not recognized"); asyncpg exceptions include constraint/key values (`Key (tenant_id, email)=(…)`).
Resolution: global exception handlers that emit only `{code, message(catalog), request_id, retryable, field_errors:[{field, code}]}`; Pydantic errors mapped without `input`/`ctx`; Snowflake errors stored as `(error_code, sql_state, error_class)` only (message kept only in FULL privacy mode); asyncpg `IntegrityError` mapped by constraint name; log processors drop `exc_info` text for classes in `packages/query_privacy/sensitive_exceptions.py`. Sentinel test in SEC-007-S12.
Affects: SEC-007, CTL-003, API-*.

### G-SEC-24 · Tenant creation path and first-owner bootstrap are undefined
Severity: MEDIUM · Type: GAP
Evidence: `SEC-002` UX — "New user sees create organization or accept invite"; `SEC-004` — "bootstrap first owner through an atomic tenant-creation transaction"; ADR-012 manual B2B billing; no statement of who may create a tenant.
Why it matters: open self-service tenant creation in R1 creates trial abuse (every tenant costs a Snowflake user, an IAM role and Cognito MAUs) and a public tenant-creation endpoint that provisions privileged resources.
Resolution (recommended, Owner question Q1): R1 tenants are **operator-provisioned** (CTL-102): internal console creates tenant (PROVISIONING) + first-owner invitation, triggers SEC-105 tenant principal provisioning, ACTIVE when principal ready. The "create organization" empty state becomes "Ask your administrator or contact sales".
Affects: CTL-102, SEC-002, SEC-105.

### G-SEC-25 · Dependencies are inverted or over-serialized; task sizes are unrealistic
Severity: MEDIUM · Type: RISK
Evidence: `task-index.json`: SEC-004 ← SEC-002 although SEC-002's data model ("identity.subject … auth.session") needs SEC-004's identity migration; SEC-002 ← INF-006; SEC-008 bundles audit write-path (needed by everyone early) with the export store and attack suite (needed late).
Resolution: see "Dependency changes" per task in §4. Net effect: SEC-004 can start once CTL-101 exists (no Cognito needed); SEC-002 local work starts in parallel; INF-006 only gates SEC-002's staging live step.
Affects: all SEC tasks.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by (task/micro-task) |
|---|---|---|
| ADR-005 amendment (D-02) | Appendix A verbatim: identities, Snowflake DDL for `SECURITY.TENANT_PRINCIPAL/PROFILE/PROFILE_ENTITLEMENT`, three policy bodies, masking policy for full SQL text, lifecycle, limits, pool rules, provisioner privileges, attack list | SEC-005-S01 |
| Scope grammar spec + JSON Schema | `schemas/authz/scope-clause.v1.json`, `profile-canonical.v1.json`; normalization algorithm; hash; subsumption; PG/Snowflake compilation; 40-case golden table (Appendix B.5) | SEC-101-S01/S02 |
| Capability catalog + role matrix | `packages/authz/capabilities.yaml`: ≈55 capabilities (Appendix C.2) with `kind` (mutation/visibility), `scope_bound`, `grantable`, `four_eyes_policy`, `step_up`; 8-role defaults (Appendix C) | SEC-004-S02 |
| Approval (maker-checker) state machine | States REQUESTED→APPROVED/REJECTED/EXPIRED/VOIDED→EXECUTED; guards; bound fields; per-action policy table | SEC-102-S01 |
| Session & auth OpenAPI | `GET /v1/auth/login`, `GET /v1/auth/callback`, `POST /v1/auth/discover`, `GET /v1/auth/session`, `POST /v1/auth/refresh` (internal), `POST /v1/auth/logout`, `POST /v1/auth/sessions/revoke-all`, `POST /v1/auth/switch-tenant`, `POST /v1/auth/step-up`, `GET /v1/me/sessions`, `DELETE /v1/me/sessions/{id}`; cookie attributes; CSRF header; error codes | SEC-002-S01 |
| Identity DDL | `identity.tenants, subjects, subject_identities, memberships, grants, grant_clauses, permission_profiles, sessions, identity_providers, idp_domains, support_access_grants`; columns/keys in Appendix D.2 and E | SEC-004-S01, SEC-002-S02, SEC-003-S01 |
| RLS standard | Role list, policy templates per table class, definer functions, catalog lint query, forbidden patterns (Appendix E) | CTL-101 / SEC-004-S03 |
| Revocation contract | Epoch semantics, `identity.resolve_session()` signature, broker recheck period, cursor/job/link binding fields, presigned TTL, measurement harness (Appendix F) | SEC-006-S01 |
| Privacy policy file | `data/contracts/privacy-policy.json`: modes, per-field treatment (SQL, tag, user, role, object names, error text), allowlisted comment/tag keys + regex, size limits, sanitizer/lexical tiers, pseudonym scheme version | SEC-007-S01, SEC-103-S01 |
| Attack catalog | `tests/security/attacks/catalog.yaml` ATK-01…ATK-36 with entry point, fixture, expected status/body, owning task (Appendix I) | SEC-001-S05, SEC-008-S07 |
| Audit event taxonomy | `schemas/audit/event.v1.json` + catalog of ~70 action names, redaction rules per field, outcome enum, export manifest schema | SEC-008-S01 |
| Data inventory | Data class × store × retention × residency × access × sanitization × erasure path (incl. pseudonyms and IP) | SEC-001-S03 |

## 4. Revised production backlog

Conventions used below: `AuthContext` = (subject_id, tenant_id, membership_id, permission_epoch, profile_hash, session_id); all PG access goes through `tenant_transaction()` from CTL-101; attack IDs `ATK-nn` refer to Appendix I; appendix references (A–I) are normative designs at the end of this file.

### SEC-001 — Model threats and classify sensitive data
Release: R1 · Estimate: 24–40 h · Risk: M · Decisions: D-02, D-10, D-22, D-25 · Closes: G-SEC-21 (inventory part), G-SEC-24 (decision capture)
Dependency changes: `−INF-002` (threat modelling uses the INF-002 network *design*, not a deployed VPC); none added.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SEC-001-S01 | Draw data-flow diagrams for user, control, connector, data, action and **operator** planes; enumerate every entry point (HTTP route prefixes, SQS queues, S3 notifications, Snowpipe, outbox handlers, Dagster sensors, internal broker endpoint, `bridge-admin` CLI, Cognito callbacks) | `docs/security/threat-model.md` §1–2 | Each entry point has an ID `EP-nn`; reviewer finds no route prefix in the planned OpenAPI outline without an EP | 4 |
| SEC-001-S02 | Apply STRIDE per EP for 8 attacker classes (unauthenticated, foreign tenant, restricted same-tenant user, compromised connector task, malicious SQL/tag text, compromised notification destination, malicious operator, compromised CI) including confused-deputy paths (broker, provisioner, config publisher) | `threat-model.md` §3 table EP × threat × control × ATK-id | Every cell has a control or an explicit accepted risk ID | 5 |
| SEC-001-S03 | Build the data inventory: class (credentials, SQL text, user identifiers, object names, tags, financial facts, audit identifiers incl. IP/user agent, report narratives) × store (S3 journal, RAW, canonical, serving, PG, Redis, logs, reports, backups) × retention × residency (D-23 EU) × access × sanitization × erasure path | `docs/security/data-inventory.md` | Every PRD §57/§117/§118 data element and every D-10 pseudonym appears once with an erasure path or documented exemption | 4 |
| SEC-001-S04 | Inventory privileged identities: AWS task/execution roles, tenant-serving roles, provisioners, Snowflake roles/users (Appendix A.6), PG roles (Appendix E), Cognito admin APIs, Redis ACL users; record blast radius and who may assume each | `docs/security/privileged-identities.md` | Each identity lists "can read tenants: none/one/all"; exactly one component (query broker) is "all" for serving data, flagged as residual risk RR-01 | 3 |
| SEC-001-S05 | Write attack catalog v1 (ATK-01…ATK-36, Appendix I) with entry point, fixture persona, request, expected status/body, owning task | `tests/security/attacks/catalog.yaml` | YAML validates against `catalog.schema.json`; each ATK has an owner task ID that exists in task-index | 4 |
| SEC-001-S06 | Record residual risks: RR-01 broker compromise, RR-02 presigned URL ≤30 s after revoke, RR-03 PITR residual of erased names (35 d), RR-04 timing side channels, RR-05 Snowflake result-cache semantics under policies (until SEC-005-S11 proves), each with owner and revisit gate | `docs/security/residual-risks.md` | Each RR has owner, trigger to revisit and linked test | 2 |
| SEC-001-S07 | Trace every G-SEC finding and threat control to a task/micro-task; add CI check that each ATK in the catalog has a test module path (stub allowed until owning task starts) | `docs/security/traceability.md`, `tests/security/test_catalog_coverage.py` | CI fails when an ATK lacks a module path | 2 |
| SEC-001-S08 | Run a review with backend, data and UX leads; capture decisions: lexical sanitizer tier (G-SEC-15), four-eyes defaults (Appendix C.4), tenant creation mode (Q1), MFA factors (G-SEC-07) | `docs/security/decisions-2026-xx.md` | Each decision has an owner sign-off line or is listed in §7 owner questions | 2 |

Task acceptance:
- [ ] Every EP has at least one ATK or accepted-risk entry; no orphan ATK.
- [ ] Data inventory shows no plaintext Snowflake user name in any immutable store (S3 journal, RAW, canonical) once D-10 is applied.
- [ ] Privileged identity inventory proves no runtime component except the broker can obtain cross-tenant serving access.
- [ ] Residual risks RR-01…RR-05 have owners and revisit gates.

### SEC-002 — Implement Cognito login, BFF sessions and local MFA
Release: R1 · Estimate: 64–96 h · Risk: H · Decisions: D-19, D-25 · Closes: G-SEC-06, G-SEC-07 (local part), G-SEC-08 (tier), G-SEC-19
Dependency changes: `+SEC-004` (identity tables and `resolve_session()` definer function live there); `−INF-006` as a start dependency — INF-006 gates only step S17 (staging live evidence); `+CTL-101` (unit of work, audit emit).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SEC-002-S01 | Author OpenAPI for auth endpoints (Appendix D.3) with error codes `AUTH_STATE_INVALID, AUTH_TOKEN_INVALID, AUTH_SESSION_EXPIRED, AUTH_IDP_UNAVAILABLE, AUTH_CSRF_INVALID, AUTH_STEP_UP_REQUIRED, AUTH_MFA_REQUIRED` and cookie specification | `packages/api_contracts/openapi/auth.yaml` | Spectral lint passes; every endpoint lists response codes and cookie effects | 3 |
| SEC-002-S02 | Migrate `identity.sessions` and `identity.auth_transactions` (Appendix D.2); create `identity.resolve_session(sid_hash bytea)` SECURITY DEFINER with fixed `search_path` | `migrations/versions/0003_sessions.py` | `bridge_api` has no SELECT on `identity.sessions`; function returns one row for a valid hash and zero for revoked/expired | 3 |
| SEC-002-S03 | Terraform Cognito: user pool per env, feature plan **Essentials**, MFA `ON` with TOTP + WebAuthn `MULTI_FACTOR_WITH_USER_VERIFICATION`, SMS MFA off, password min length 12, confidential app client (secret in Secrets Manager), code grant + PKCE only, exact callback/logout URLs per env, access/ID token 10 min, refresh 24 h with rotation `RetryGracePeriodSeconds=30`, deletion protection | `infra/terraform/modules/cognito/` | `terraform plan` shows no implicit/`localhost` callbacks in staging/prod; AWS CLI `describe-user-pool` shows MFA ON and WebAuthn factor config | 5 |
| SEC-002-S04 | Implement `GET /v1/auth/login`: validate `return_to` (relative path, regex `^/(?!/)[A-Za-z0-9/_\-?=&%.~]*$`, max 512), create 256-bit `state`, nonce, PKCE S256 verifier; persist hashed in `auth_transactions` (10 min TTL); set `__Host-bridge_auth` binding cookie (SameSite=Lax); 302 to Cognito authorize (with `identity_provider` when discovery resolved one) | `apps/api/auth/login.py` | `//evil.com`, `/\evil.com`, `https:evil`, `%2F%2Fevil` all rejected → `return_to=/` | 4 |
| SEC-002-S05 | Implement callback: consume state atomically (`UPDATE … SET consumed_at=now() WHERE state_hash=$1 AND consumed_at IS NULL AND expires_at>now()`), exchange code with verifier, validate ID token (iss = pool issuer, aud = client id, `token_use=id`, RS256 only, kid in JWKS, exp/iat ±60 s, nonce) and access token (`token_use=access`, `client_id`); JWKS cache 1 h, unknown-kid refresh ≤1/min, stale-JWKS tolerance 24 h | `apps/api/auth/callback.py`, `packages/auth/jwt.py` | Second use of the same state → `AUTH_STATE_INVALID`; unit tests for each claim failure | 5 |
| SEC-002-S06 | Resolve subject: native `(issuer, sub)`; federated via `identities` claim → `subject_identities(provider_id, provider_subject)`; create subject without membership if new; update `email_norm` only from verified sources | `apps/api/auth/subjects.py` | New subject has zero memberships and lands on "pending invitation" view | 3 |
| SEC-002-S07 | Create session: sid = 32 random bytes; store SHA-256; refresh token AES-256-GCM-encrypted with KMS data key (cached ≤5 min/process, AAD = session_id); set `__Host-bridge_sid` (Secure, HttpOnly, SameSite=Lax, Path=/); always new sid at login (fixation defence); record `auth_time`, `amr`, `idp_id` | `apps/api/auth/sessions.py` | Pre-set attacker cookie is ignored and replaced; DB row never contains plaintext refresh token (grep of pg_dump in test) | 4 |
| SEC-002-S08 | Session middleware: call `resolve_session()` once per request; enforce idle (default 30 min, tenant 15–120) and absolute (default 12 h, tenant 1–24 h); throttle `last_seen_at` writes to ≥60 s; build `AuthContext` | `apps/api/auth/middleware.py` | Fixed-clock tests: 29:59 idle passes, 30:01 fails; 12 h absolute fails regardless of activity | 4 |
| SEC-002-S09 | CSRF: `GET /v1/auth/session` returns `csrf_token = b64url(HMAC-SHA256(csrf_key[kid], session_id))`; all non-GET require `X-CSRF-Token` + `Origin` in env allowlist; key rotation keeps previous kid 24 h | `apps/api/auth/csrf.py` | POST without header/with token of another session/with foreign Origin → 403 `AUTH_CSRF_INVALID` | 3 |
| SEC-002-S10 | Server-side refresh: when stored access expiry < now+60 s and last refresh ≥15 min ago, lock session row `FOR UPDATE SKIP LOCKED`, call Cognito refresh, store rotated refresh token; `NotAuthorizedException` → revoke session (`IDP_REVOKED`); other requests proceed without waiting | `apps/api/auth/refresh.py` | 20 parallel requests at refresh boundary produce exactly 1 Cognito refresh call and 0 logouts | 4 |
| SEC-002-S11 | Logout, logout-everywhere and session list: revoke row, Cognito `RevokeToken`, redirect to Cognito `/logout`; `POST /v1/auth/sessions/revoke-all` also calls `AdminUserGlobalSignOut` for native users; `GET /v1/me/sessions`, `DELETE /v1/me/sessions/{id}` (own only, foreign id → 404) | `apps/api/auth/logout.py` | After logout, replaying the old cookie → 401; Cognito refresh with the stored token fails | 4 |
| SEC-002-S12 | Tenant switch `POST /v1/auth/switch-tenant`: require ACTIVE membership, tenant SSO/MFA policy satisfied by session (`idp_id`, `amr`), rotate sid, send `Clear-Site-Data: "cache"`; non-member → 404 | `apps/api/auth/switch.py` | Switch A→B issues new cookie; old sid revoked; B with SSO enforced and password session → `AUTH_STEP_UP_REQUIRED` with IdP redirect | 3 |
| SEC-002-S13 | MFA enrolment and recovery via Cognito managed login (TOTP, passkey); lost-MFA recovery = owner/admin-approved reset (`support`-free) with audit and 24 h cool-down; WAF rate rule 20 req/5 min/IP on `/v1/auth/*` | `apps/api/auth/mfa.py`, `infra/terraform/modules/waf/auth_rules.tf` | New user cannot reach any tenant data before MFA enrolment; recovery emits `auth.mfa.reset` audit | 4 |
| SEC-002-S14 | Frontend: unauthenticated layout for `/sign-in` and `/mfa` without scope bar/API calls (G-SEC-19); session bootstrap; CSRF header injection; `history.replaceState` after callback; Playwright asserts no JWT-like string (`eyJ[A-Za-z0-9_-]{10,}`) in localStorage/sessionStorage/IndexedDB/URL history and no `/v1/` data call before session | `apps/web/auth/`, `apps/web/e2e/auth.spec.ts` | Playwright suite green at 390 px and desktop | 5 |
| SEC-002-S15 | Negative suite: expired, wrong iss, wrong aud, ID-as-access, `alg:none`, HS256-with-public-key, unknown kid, nonce replay, state replay, duplicate callback, ±5 min skew, 4 open-redirect variants, CSRF variants, session fixation (ATK-18…ATK-22) | `tests/security/auth/` | All cases return the specified code and create no session row | 5 |
| SEC-002-S16 | Observability: `auth_login_total{outcome}`, `auth_refresh_total{outcome}`, `auth_sessions_active`, `auth_csrf_reject_total`, `auth_jwks_age_seconds`; alarms: login failure ratio >30 % for 10 min, JWKS age >1 h; logs carry subject_id, never email/token | `apps/api/auth/metrics.py`, `infra/alarms/auth.tf` | Alarm test fires in staging via injected failures | 2 |
| SEC-002-S17 | Staging live evidence (needs INF-006): real Cognito, TOTP and passkey (Chromium virtual authenticator), two-tab logout, refresh rotation under parallel load | `docs/evidence/SEC-002/<commit>/` | Evidence record fields per validation strategy; PASS on all | 4 |
| SEC-002-S18 | Runbook: Cognito outage (existing sessions continue to idle/absolute limits; new logins `AUTH_IDP_UNAVAILABLE`), JWKS rotation, emergency global logout (`UPDATE identity.sessions SET revoked_at=now()` + Cognito global sign-out for natives) | `docs/runbooks/auth.md` | Drill in staging revokes all sessions in <60 s | 2 |

Task acceptance:
- [ ] Valid login yields one session row and a `__Host-bridge_sid` cookie (Secure, HttpOnly, SameSite=Lax); no token reaches browser JavaScript.
- [ ] All S15 negative cases fail with the specified code; duplicate callback creates no second session.
- [ ] Logout in tab B → tab A's next request is 401; Cognito refresh with the stored token fails.
- [ ] Idle 30 min and absolute 12 h limits hold under fixed-clock tests; tenant overrides are bounded (15–120 min, 1–24 h).
- [ ] Parallel requests at refresh time produce exactly one Cognito refresh and no spurious logout.
- [ ] Pre-auth pages make no `/v1/` data calls and show no tenant name.

### SEC-003 — Add tenant-bound SAML and OIDC SSO
Release: R1 (D-20, 2026-09-28: SSO for every customer; tested IdPs Entra ID, Okta and Google) · Estimate: 60–90 h · Risk: H · Decisions: D-20 · Closes: G-SEC-07 (federated), G-SEC-08, G-SEC-09
Dependency changes: `+SEC-102` (enforcement requires approval/step-up), `+CTL-003` (invitation linking).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SEC-003-S01 | Migrate `identity.identity_providers` (tenant_id, id, protocol, cognito_provider_name `t-<short>-<n>`, entity_id/issuer **globally unique** (Google OIDC: unique per (issuer, client_id, verified `hd`), S17), metadata_sha256, subject_attribute, attribute_mapping, mfa_assertion `REQUIRED_AMR\|TRUSTED_IDP_POLICY`, jit_enabled, state `DRAFT\|TESTED\|ENFORCED\|DISABLED`, tested_at/by, enforced_at, revision) and `identity.idp_domains` (domain, verification_token_hash, verified_at, last_checked_at) | `migrations/versions/00xx_idp.py` | Unique index rejects the same entity_id for a second tenant | 3 |
| SEC-003-S02 | Implement IdP draft create/update: SAML metadata ≤256 KB parsed with `defusedxml`, signing cert present, RSA ≥2048, not expired; OIDC discovery fetched through the SSRF-safe egress client (https, public IPs only, 5 s timeout, no redirects to private ranges); call Cognito `CreateIdentityProvider`; same entity_id in another tenant → 409 `IDP_ALREADY_BOUND` without tenant name | `apps/api/identity_providers/` | XXE payload and `http://169.254.169.254` discovery URL both rejected | 5 |
| SEC-003-S03 | Enforce stable subject: SAML requires persistent NameID or a configured immutable attribute (Entra objectidentifier, Okta user.id); OIDC uses `sub` (Entra, Okta, Google); store in `subject_identities` | `apps/api/identity_providers/mapping.py` | Email change at IdP maps to the same subject in the test | 3 |
| SEC-003-S04 | Build test mode: `POST /v1/settings/sso/{id}/test` starts an auth transaction flagged `test`, result shows redacted asserted attributes, creates no tenant session; success sets TESTED bound to metadata_sha256; any metadata change resets to DRAFT | `apps/api/identity_providers/test_flow.py` | Enforce attempt on DRAFT → 409 `SSO_NOT_TESTED` | 5 |
| SEC-003-S05 | Implement domain verification via DNS TXT `_bridge-verify.<domain>`; re-check every 30 days; verified domains are discovery hints only | `apps/api/identity_providers/domains.py` | Unverified domain never triggers IdP redirect | 3 |
| SEC-003-S06 | Implement `POST /v1/auth/discover {email}`: constant response shape, jittered latency envelope, rate-limited; returns IdP redirect for verified domain else generic login | `apps/api/auth/discover.py` | Response bodies for customer and non-customer domains differ only in redirect target class; timing p50 within ±10 % | 3 |
| SEC-003-S07 | Bind federated sessions: provider P → exactly one tenant; session `idp_id=P`; tenant selection outside P's tenant → `AUTH_IDP_TENANT_MISMATCH` | `apps/api/auth/federation_binding.py` | ATK-23 (IdP of A used for B) denied | 4 |
| SEC-003-S08 | Invitation linking and JIT: SSO-enforced tenant accepts invitations only from sessions with its IdP; JIT (opt-in) creates membership Viewer + empty scope + admin notification | `apps/api/identity_providers/jit.py` | JIT user sees zero rows everywhere until granted (API + Snowflake profile = none) | 4 |
| SEC-003-S09 | Enforce MFA assertion: with `REQUIRED_AMR`, require the mapped MFA attribute (allowlisted `amr` values or SAML AuthnContextClassRef) else deny `AUTH_MFA_NOT_ASSERTED` | `apps/api/identity_providers/mfa_assertion.py` | Assertion without MFA attribute denied in live test | 3 |
| SEC-003-S10 | Enforcement lifecycle: TESTED + approval (Appendix C.4 `sso.enforce`) + ≥1 designated break-glass owner (max 2, passkey MFA required); when ENFORCED, password sessions cannot select the tenant except break-glass owners, whose use pages Security | `apps/api/identity_providers/enforce.py` | ATK-22 (password login bypass) denied; break-glass login emits `sso.breakglass.used` + alarm | 5 |
| SEC-003-S11 | Certificate rotation: accept two signing certs; expiry alarms at 30/7/1 days; cert-only rotation for the same entity_id requires a new test run | `apps/api/identity_providers/certs.py` | Expired-cert fixture blocks login with `AUTH_IDP_CERT_EXPIRED` and alarm | 3 |
| SEC-003-S12 | Disable/recovery: disabling requires owner step-up; runbook for IdP outage using break-glass owner | `docs/runbooks/sso.md` | Drill restores owner access within 15 min without support involvement | 3 |
| SEC-003-S13 | Attack tests: changed email (same subject), same email via second IdP (new subject, no link), cross-tenant IdP reuse, enforced-SSO bypass, replayed SAML response, altered assertion (Cognito rejects) | `tests/security/sso/` | All PASS in staging with the three tested IdPs (Entra ID, Okta, Google) | 5 |
| SEC-003-S14 | UI `/settings/sso`: DRAFT/TESTED/ENFORCED/DISABLED visually distinct, test result view, approval banner | `apps/web/settings/sso/` | Playwright covers each state and keyboard path | 5 |
| SEC-003-S15 | Observability: `sso_login_total{outcome}`, `idp_cert_days_to_expiry`, `idp_quota_used_ratio` (alarm ≥0.9 of verified Cognito IdP quota, G-SEC-08) | `infra/alarms/sso.tf` | Alarms fire in staging with injected values | 2 |
| SEC-003-S16 | Live evidence with an Entra ID test tenant (SAML), an Okta developer org (OIDC) and a Google Workspace test domain (OIDC; SAML too if S17 verifies an immutable attribute); record Cognito IdP-per-pool quota from Service Quotas | `docs/evidence/SEC-003/<commit>/` | Evidence per IdP (login, subject stability, cross-tenant denial) and the quota value (VERIFIED LIVE) | 5 |
| SEC-003-S17 | Google as a tested IdP: Google Workspace via OIDC — issuer `https://accounts.google.com` is shared by all Google customers, so the tenant binding is (issuer, client_id, `hd` claim equal to a DNS-verified tenant domain, S05); subject = `sub`; `email`/`email_verified` never used for linking; Google Workspace SAML custom app only if an immutable attribute can be mapped instead of the primary-email NameID (TO VERIFY LIVE), else OIDC only | `apps/api/identity_providers/google.py` | A valid Google token from another Workspace domain or a consumer account → `AUTH_IDP_TENANT_MISMATCH`; the same Google `sub` after a primary-email rename maps to the same subject | 3 |

Task acceptance:
- [ ] Changing the IdP email does not create a subject or privilege; the same email via another IdP is not linked.
- [ ] A failed or stale test cannot enforce SSO; enforcement requires approval and a break-glass owner.
- [ ] A tenant's IdP cannot authenticate into another tenant; entity_id reuse across tenants is refused without disclosure.
- [ ] Missing MFA assertion is denied when the tenant policy requires it.
- [ ] Cognito IdP quota is recorded and alarmed.
- [ ] Entra ID, Okta and Google each pass login, subject-stability and cross-tenant denial tests with live evidence.

### SEC-004 — Implement scoped RBAC and tenant RLS foundation
Release: R1 · Estimate: 52–80 h · Risk: H · Decisions: D-02 · Closes: G-SEC-02 (PG side), G-SEC-03, G-SEC-04, G-SEC-10, G-SEC-11, G-SEC-25
Dependency changes: `−SEC-002` (RBAC/RLS does not need Cognito; SEC-002 now depends on SEC-004); `+CTL-101` (migration runner, role model, `tenant_transaction`, emit API); `+SEC-101` (scope library).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SEC-004-S01 | Migrate identity schema: `tenants` (id, slug unique, status, authz_epoch, security_policy jsonb, revision), `subjects` (id, issuer, cognito_sub, email_norm, email_verified, status; unique(issuer,cognito_sub)), `subject_identities`, `memberships` (tenant_id, id, subject_id, kind `MEMBER\|SUPPORT`, status `INVITED\|ACTIVE\|SUSPENDED\|REMOVED`, permission_epoch, profile_id, revision; unique(tenant_id,subject_id)), `grants` (tenant_id, id, membership_id, role, extra_capabilities text[], scope jsonb validated by SEC-101 schema, created_by, revision), `permission_profiles` (tenant_id, id, profile_hash, canonical jsonb, role_name, status, created_at, retired_at; unique(tenant_id, profile_hash)), `teams` (+ linked_group_set_id, linked_group_id), `team_members` — all composite keys/FKs | `migrations/versions/0002_identity.py` | Catalog lint (CTL-101) passes; every FK includes tenant_id | 4 |
| SEC-004-S02 | Encode capability catalog and role defaults (Appendix C) as `capabilities.yaml`; generate `Capability` enum; FastAPI dependency `require(cap, scope_of=…)`; CI job lists routes without a declared capability | `packages/authz/capabilities.yaml`, `packages/authz/generated.py`, `tools/ci/check_route_caps.py` | CI fails on a route lacking `require()`; matrix doc and YAML generated from one source | 4 |
| SEC-004-S03 | Apply RLS policies to identity tables per Appendix E (tenant template; subject-scoped policies for `tenants`, `subjects`, `memberships` "list my tenants"), FORCE RLS | migration + `tests/security/rls/test_identity_rls.py` | With only `app.subject_id` set, subject lists own memberships across tenants and nothing else | 4 |
| SEC-004-S04 | Implement `authorize(ctx, capability) -> ScopePredicate`: union of clauses of grants whose role/extra caps include the capability, normalized by SEC-101; in-process cache keyed `(membership_id, permission_epoch)` | `packages/authz/authorize.py` | Epoch bump invalidates cache (test); p99 <1 ms warm | 4 |
| SEC-004-S05 | Integrate repository predicates: `scoped_select(model, cap)` adds SEC-101 compiled predicate for single-scope objects; multi-scope objects (`scope_atoms` child table) require object scope ⊆ viewer scope (`NOT EXISTS uncovered atom`) | `packages/control_db/scoping.py` | Budget over A1+A2 invisible to A1-only viewer; visible to A1+A2 viewer | 4 |
| SEC-004-S06 | Non-enumerating lookups: not-found, foreign tenant and out-of-read-scope all → 404 `NOT_FOUND` with identical body; 403 `FORBIDDEN` only when object readable but mutation capability missing | `packages/control_db/lookup.py` | ATK-01 returns byte-identical 404 bodies for foreign vs nonexistent UUID | 3 |
| SEC-004-S07 | Tenant creation transaction used by CTL-102: tenant row, owner membership (INVITED), OrganizationOwner grant scope `*`, audit, outbox `tenant.created` | `packages/authz/tenant_bootstrap.py` | Crash injected before commit leaves no partial tenant | 3 |
| SEC-004-S08 | Delegation rules (Appendix C.3): granted capabilities ⊆ actor's delegable set, granted scope ⊆ actor's `member.manage` scope, owner-only capabilities, Team Admin role ceiling Analyst; last-owner protection locking all ACTIVE owner memberships `FOR UPDATE` | `packages/authz/delegation.py` | ATK-25 → 403 `DELEGATION_EXCEEDED`; ATK-26 concurrent removal of 2 owners: exactly one succeeds | 5 |
| SEC-004-S09 | Epoch/outbox hooks: every grant/membership mutation increments `permission_epoch` (`UPDATE … RETURNING`) and emits `authz.membership.changed` + profile recompute request in the same transaction | `packages/authz/events.py` | Rollback leaves epoch and outbox unchanged | 3 |
| SEC-004-S10 | Pool-reuse attack (ATK-30): pool size 1; tx(A) read → tx(B) read → tx(no context) read; plus attempt of session-level `set_config(…, false)` detected by the prior-value check (Appendix E.5) | `tests/security/rls/test_pool_reuse.py` | Rows: A only / B only / 0; stray session context triggers `SECURITY_CONTEXT_LEAK` log and connection invalidation | 3 |
| SEC-004-S11 | Foreign write/FK tests: insert tenant B row under A → SQLSTATE 42501; FK to B parent under A → 23503 with identical message whether parent exists or not (composite FK) | `tests/security/rls/test_foreign_writes.py` | Messages byte-identical across the two cases | 3 |
| SEC-004-S12 | PG half of the scope matrix (Appendix B.5 cases 1–20): Finance∧A1 vs Finance∧A2, union clauses, org-level objects, shared/unallocated flags | `tests/security/rls/test_scope_matrix.py` | All 20 cases match the golden expectations | 3 |
| SEC-004-S13 | Escalation tests: Team Admin grants FinOps Admin (403), Admin grants beyond own scope (403), ownership transfer without step-up (401 `AUTH_STEP_UP_REQUIRED`), self-grant of `audit.export` by Analyst (403) | `tests/security/authz/test_escalation.py` | All denied and audited | 3 |
| SEC-004-S14 | Extend CTL-101 catalog lint to identity schema and add to CI | `tools/ci/rls_lint.sql` | Lint fails on a test table created without FORCE RLS | 1 |
| SEC-004-S15 | Observability: `authz_decision_total{capability,outcome}` (no tenant label); structured denial log; security alarm >20 cross-tenant 404s per subject per 5 min | `packages/authz/metrics.py` | Synthetic probe triggers alarm in staging | 2 |
| SEC-004-S16 | Evidence: local + staging Aurora runs of S10–S13 | `docs/evidence/SEC-004/<commit>/` | PASS recorded with Aurora engine version | 2 |

Task acceptance:
- [ ] A→B pool reuse exposes only B; absent context yields zero rows for every tenant table; foreign writes and FKs fail without an existence oracle.
- [ ] Finance∧A1 never becomes Finance∨A1 (golden cases 1–20).
- [ ] Every route declares a capability; delegation and last-owner rules hold under concurrency.
- [ ] Runtime roles are non-owners and `NOBYPASSRLS` (catalog query in evidence).

### SEC-005 — Provision identity-bound Snowflake serving policies (ADR-005 amended)
Release: R1 · Estimate: 60–92 h · Risk: H · Decisions: D-02, D-05, D-21, D-22 · Closes: G-SEC-01, G-SEC-13, G-SEC-20, G-SEC-21 (Snowflake part)
Dependency changes: `+SEC-101` (entitlement expansion); keep SEC-004, INF-008, INF-005 (broker task role, D-22). Automated provisioning moved to new SEC-105.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SEC-005-S01 | Publish the ADR-005 amendment (Appendix A) and get Security + Data platform approval | `docs/architecture/adr/ADR-005a-tenant-user-profile-roles.md` | Accepted status with reviewers; ADR-005 marked "amended by" | 3 |
| SEC-005-S02 | Create `SECURITY` schema objects (Appendix A.2) owned by `SECURITY_POLICY_OWNER`; grant INSERT/UPDATE on `TENANT_PRINCIPAL` only to `TENANT_ONBOARDER`, on `PROFILE`/`PROFILE_ENTITLEMENT` only to `PROFILE_PROVISIONER`; readers get nothing | `infra/snowflake/security/010_security_schema.sql` | `SHOW GRANTS ON TABLE` output matches the manifest exactly | 4 |
| SEC-005-S03 | Create `RAP_ACCOUNT_SCOPED`, `RAP_GROUP_SCOPED`, `RAP_TENANT_ONLY` and masking policy `MP_SQL_TEXT_FULL` (Appendix A.3) through the INF-008 DDL runner | `infra/snowflake/security/020_policies.sql` | Policies exist; bodies reference `CURRENT_ROLE()` and never `IS_ROLE_IN_SESSION` (grep gate) | 4 |
| SEC-005-S04 | Create session policy `SP_NO_SECONDARY_ROLES` (`ALLOWED_SECONDARY_ROLES = ()`) and the tenant-user template (`TYPE=SERVICE`, `WORKLOAD_IDENTITY=(TYPE=AWS ARN=…)`, `DEFAULT_SECONDARY_ROLES=()`, network policy allowing only broker egress) | `infra/snowflake/security/030_user_template.sql` | `USE SECONDARY ROLES ALL` in a tenant-user session fails with the session-policy error (ATK-12) | 3 |
| SEC-005-S05 | Build access structure: secure views in `SERVING_API`; database role `SERVING_READER` (SELECT on those views only); account role `BRIDGE_SERVING_BASE` holding it; profile roles inherit only BASE; no future grants on `SERVING` | `infra/snowflake/security/040_serving_access.sql` | Profile role cannot select `SERVING`, `RAW`, `CONFIG`, `SECURITY` tables directly | 4 |
| SEC-005-S06 | Add policy-coverage CI gate: every `SERVING` base table has the expected policy per `serving_policy_map.yaml`; every `SERVING_API` object is secure | `infra/snowflake/security/checks/policy_coverage.sql`, CI job | Gate fails on a fixture table without policy | 3 |
| SEC-005-S07 | Script fixture principals with SEC-101 expansion: tenant A user (profiles A-ALL, A-A1, A-FIN∧A1, A-FIN∧A1+UNALLOC), tenant B user (B-ALL) | `tests/security/snowflake/fixtures/principals.py` | Entitlement rows equal SEC-101 expansion output (checksum) | 4 |
| SEC-005-S08 | Load F-270-derived serving fixtures: account-grain charges (incl. org-level fee 5 and rebate −3 with account NULL), group-grain allocations (Finance 120, Marketing 80 of warehouse 200; `__SHARED__`, `__UNALLOCATED__` rows) | `tests/security/snowflake/fixtures/serving.sql` | Fixture totals: account grain 270.00; group grain 200.00 | 3 |
| SEC-005-S09 | Positive oracle per profile: A-ALL sum 270.00; A-A1 sees A1 rows only and no org-level rows; A-FIN∧A1 sees 120.00 in group table and 0 rows in account table; B-ALL sees only B | `tests/security/snowflake/test_positive.py` | Exact decimal equality | 3 |
| SEC-005-S10 | Cross-tenant attacks (ATK-11, ATK-13): `SELECT *` without WHERE as B; `USE ROLE <A profile>` from B user (not granted); query `RAW`/`SECURITY`; pooled connection of A reused for B request (broker test) | `tests/security/snowflake/test_cross_tenant.py` | Zero A rows in every case | 4 |
| SEC-005-S11 | Intra-tenant/aggregate attacks (ATK-15, ATK-16, ATK-14): A-FIN∧A1 reads account-grain table (0 rows), filters Marketing (0), reads `__SHARED__` without flag (0), computes share with account denominator (denominator NULL); run identical SQL under A-ALL then A-FIN∧A1 and compare to each oracle (result-cache under policy — TO VERIFY LIVE) | `tests/security/snowflake/test_intra_tenant.py` | A-FIN∧A1 always returns its own oracle; result-cache behaviour recorded as VERIFIED LIVE | 4 |
| SEC-005-S12 | Document and test the broker-trust boundary: the tenant user holds all its profile roles, so `USE ROLE <broader same-tenant profile>` succeeds by design; prove the broker planner never emits `USE`/`ALTER SESSION`/`GRANT`/`CALL` (AST allowlist) and that ACCOUNTADMIN sees zero serving rows (not in `TENANT_PRINCIPAL`) | `tests/security/snowflake/test_broker_boundary.py` | Planner fuzz (10k requests) emits only SELECT; ACCOUNTADMIN count = 0 | 2 |
| SEC-005-S13 | Benchmark policy cost: 200 profiles × up to 2,000 atoms; p95 of representative serving queries on 10M-row fixture with/without policy; compare EXISTS body vs memoizable-function variant (argument and cache semantics TO VERIFY LIVE); choose variant | `docs/evidence/SEC-005/policy-benchmark.md` | Chosen variant adds ≤25 % p95 or a documented exception | 6 |
| SEC-005-S14 | Implement broker connection core (library for API-002's broker service): pools keyed `(env, tenant_user, profile_role)`, max 4 per pool, idle TTL 300 s, global cap per replica, connect with role parameter, post-connect assertion `CURRENT_USER/CURRENT_ROLE/CURRENT_SECONDARY_ROLES`, statement timeout 15 s interactive / 300 s jobs, static `QUERY_TAG=bridge_finops:serving`, SQL guard | `packages/query_broker_core/pools.py` | Mismatched identity on connect → connection discarded + `SECURITY_IDENTITY_MISMATCH` alarm | 5 |
| SEC-005-S15 | Limit tests: create 2,000 profile roles + entitlements in staging; measure CREATE ROLE/GRANT latency, `SHOW GRANTS`, policy evaluation; record Snowflake role-count behaviour (TO VERIFY LIVE) | `docs/evidence/SEC-005/limits.md` | Numbers recorded; admission cap set (default 200 active profiles/tenant) | 3 |
| SEC-005-S16 | Observability & runbook: `broker_pool_connections`, `broker_connect_seconds`, `security_policy_coverage_ok` (CI/nightly), runbook entries "serving table lacks policy", "stale entitlement", "principal drift" | `docs/runbooks/snowflake-serving-authz.md` | Runbook drill executed once in staging | 2 |
| SEC-005-S17 | Staging live evidence pack with two tenant users and four profiles | `docs/evidence/SEC-005/<commit>/` | All tests PASS against live Snowflake (mocks not accepted) | 3 |

Task acceptance:
- [ ] Direct SQL without any WHERE clause under B returns zero A rows; secondary roles cannot be activated.
- [ ] A team-restricted profile gets zero rows from account-grain tables and NULL for account-denominator ratios; shared/unallocated rows require explicit flags.
- [ ] Every `SERVING` table carries its mapped policy; readers can only use secure `SERVING_API` views.
- [ ] Policy overhead measured and within the recorded budget; role-count limits recorded.
- [ ] ADR-005 amendment accepted.

### SEC-006 — Enforce revocation across sessions, jobs, caches and downloads
Release: R1 · Estimate: 41–64 h · Risk: H · Decisions: D-02, D-22 · Closes: G-SEC-12
Dependency changes: `+SEC-002` (sessions), `+CTL-101` (outbox emit), `+SEC-105` (profile activation/retirement); keep SEC-004, SEC-005.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SEC-006-S01 | Write the revocation contract (Appendix F): epochs, `resolve_session()` output, recheck cadence, binding fields, presigned TTL, measurement method | `docs/security/revocation.md` | Reviewed; referenced by API-003/004, RPT-005, UX-002 | 2 |
| SEC-006-S02 | Extend `identity.resolve_session()` to return session + membership + profile + both epochs in one indexed query; add covering indexes | migration + `tests/perf/test_resolve_session.py` | p99 <2 ms server time at 500 req/s on staging Aurora | 3 |
| SEC-006-S03 | Implement epoch mutations: `memberships.permission_epoch` on any grant/membership/status change; `tenants.authz_epoch` only on data-visibility events (profile retirement, privacy-mode change, access-relevant group-set publication); both via `UPDATE … SET x=x+1 RETURNING` | `packages/authz/epochs.py` | Property test: epochs strictly increase under 50 concurrent edits | 2 |
| SEC-006-S04 | Implement narrowing vs broadening: new profile subsumes old → keep old until new ACTIVE; otherwise set `profile_id=NULL` immediately (analytics → 503 `ACCESS_UPDATING`, `Retry-After: 10`) | `packages/authz/profile_switch.py` | Narrowing test: next analytical request after commit is denied even though SEC-105 has not run | 4 |
| SEC-006-S05 | Broker recheck: re-read authz before each statement and every 10 s while running; on mismatch cancel the statement (`SYSTEM$CANCEL_QUERY` / connector cancel), discard fetched rows, return 403 `AUTHZ_REVOKED` | `packages/query_broker_core/recheck.py` | 60-s synthetic query cancelled ≤15 s after revoke commit | 4 |
| SEC-006-S06 | Moved to API-003-S05 per RECONCILIATION U-21, C-07 (sealed AES-256-GCM cursor tokens, TTL 1 h from config key `cursor_ttl_seconds`, every page re-checks membership epoch and profile hash, stale → 409 `SCOPE_CHANGED`; cursors create no pins) — consume its library here; binding rules (S01) and revocation tests ATK-04/ATK-05 (S12) stay in SEC-006 | — | ATK-04 (stale epoch) 409 `SCOPE_CHANGED`; ATK-05 (other user's cursor) 400 `CURSOR_INVALID` (asserted in S12) | 0 |
| SEC-006-S07 | Async jobs: store submit subject, membership, epoch, profile_hash, canonical scope; result read requires current profile ⊇ job profile (SEC-101 `subsumes`); reaper cancels running jobs of removed/narrowed members within 30 s | `apps/api/jobs/authz.py` | ATK-08: job finishing after revoke is not delivered (403 `RESULT_SCOPE_REVOKED`) | 4 |
| SEC-006-S08 | Single artifact download broker for every artifact kind (reports, exports, evidence bundles, statements, uploaded billing references; RPT-005 plugs in its report authorization resolver; RECONCILIATION U-10, C-12): `GET /v1/artifacts/{id}/download` rechecks artifact scope ⊆ current scope, then 302 to presigned URL TTL 30 s (signer credentials ≥ 15 min remaining) with `response-content-disposition=attachment`; emailed links point to the app route only | `apps/api/artifacts/download.py` | ATK-09: link issued before revoke fails after revoke; presigned URL expires at 30 s | 3 |
| SEC-006-S09 | Bind cache keys (CTL-006) to profile_hash + tenant authz_epoch; test stale-epoch key unreachable | `tests/cache/test_epoch_binding.py` | Pre-seeded stale key never returned | 2 |
| SEC-006-S10 | Browser contract: responses carry `X-Bridge-Tenant` and `X-Bridge-Authz` (opaque epoch digest); client drops mismatching responses, purges query cache on 403 `AUTHZ_REVOKED`/tenant switch, polls `GET /v1/auth/session` every 60 s while visible | `apps/web/lib/authzGuard.ts` | Playwright: revoke during pending request → no rows rendered | 3 |
| SEC-006-S11 | Membership removal clears `active_tenant_id` on that tenant's sessions; next request → 403 `TENANT_ACCESS_REVOKED` with tenant picker | `packages/authz/membership_removal.py` | Removed member cannot load any tenant route | 2 |
| SEC-006-S12 | Fault-injection harness: disable outbox dispatcher (all invalidation events dropped) and Redis; measure t(revoke commit → denial) for API read, cursor page, running query, async result, download, presigned URL | `tests/security/revocation/test_dropped_events.py` | All ≤30 s; API read and cursor ≤1 request; presigned ≤30 s by TTL | 5 |
| SEC-006-S13 | Concurrency tests: concurrent grant edits (If-Match loser 412), epoch monotonic, job completion after removal not delivered | `tests/security/revocation/test_concurrency.py` | PASS | 3 |
| SEC-006-S14 | Observability: `authz_revocation_latency_seconds` (harness and production event timestamps), `authz_cursor_stale_total`, `broker_cancel_on_revoke_total`; alarm when `authz.*` outbox age >60 s | `infra/alarms/authz.tf` | Alarm fires with dispatcher paused in staging | 2 |
| SEC-006-S15 | Concretize RB-09 kill switch: tenant `SUSPENDED`, `TENANT_PRINCIPAL.STATUS='DISABLED'`, `ALTER USER … SET DISABLED=TRUE`, revoke sessions, bump authz_epoch; timed drill | `docs/runbooks/RB-09-tenant-kill-switch.md` | Drill completes ≤5 min with zero serving rows afterwards | 2 |
| SEC-006-S16 | Evidence pack | `docs/evidence/SEC-006/<commit>/` | Measured latencies recorded | 2 |

Task acceptance:
- [ ] With every invalidation event dropped, no revoked result is delivered and all measured paths deny within 30 s (API reads immediately).
- [ ] Narrowing a scope never leaves the member on the broader profile, even before provisioning completes.
- [ ] Foreign or stale cursors are rejected; jobs and downloads reauthorize at delivery.
- [ ] RB-09 kill switch drill measured.

### SEC-007 — Sanitize SQL, tags and errors before persistence
Release: R1 · Estimate: 50–78 h · Risk: H · Decisions: D-10, D-11 · Closes: G-SEC-14, G-SEC-15, G-SEC-23
Dependency changes: `+WRK-101` (workload-metadata library = step (1) of `sanitize()`; requested by WRK, confirmed by RECONCILIATION U-04); SEC-001, FND-004 kept. Step S11 (FULL-mode enablement) additionally needs SEC-102; until SEC-102 lands FULL cannot be enabled (default SANITIZED), so no hard edge is added on the ingestion path. Consumers: `ING-003 +SEC-103` edge added via SEC-103.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SEC-007-S01 | Define `privacy-policy.json` v1 (Appendix G.1): modes, per-field treatment, allowlisted comment/tag keys with regex, size limits, tiers, pseudonym scheme reference | `data/contracts/privacy-policy.json`, `.schema.json` | Schema validation in CI | 3 |
| SEC-007-S02 | Record the lexical-tier decision (challenges ADR-009 "drop on failure"; default ON, tenant can disable) and METADATA_ONLY semantics (source hashes preserved, SQL null) | `docs/security/decisions/sanitizer-tiers.md` | Signed off by Security owner | 1 |
| SEC-007-S03 | Build a ≥3,000-statement corpus: Snowflake SQL reference examples (DDL, DML, COPY, PUT/GET, Scripting, procedures), dbt-generated SQL with appended comments, BI patterns, adversarial cases; label expected tier | `tests/security/sanitization/corpus/` | Corpus manifest with SHA-256 and labels | 6 |
| SEC-007-S04 | Implement AST tier: pinned sqlglot, `read="snowflake"`; replace string/number/hex/national/raw-string literals with `?`; strip comments; regenerate | `packages/query_privacy/ast_sanitizer.py` | Unit tests over 200 labelled statements | 4 |
| SEC-007-S05 | Add safety guards: `sqlglot` logger set to CRITICAL + filter dropping `sqlglot.*` records; convert exceptions to class names; reject trees containing `exp.Command` or unknown nodes; input ≤100k chars; run in a process pool with 2 s timeout; re-tokenize output and assert zero literal/comment tokens | `packages/query_privacy/guards.py` | Sentinel in a `COPY … CREDENTIALS` statement never reaches captured logs (incl. sqlglot WARNING) | 4 |
| SEC-007-S06 | Implement lexical tier: sqlglot tokenizer; any unterminated token → fail; replace literal/comment tokens with `?`; mark `sanitizer_mode=LEXICAL` | `packages/query_privacy/lexical.py` | Truncated 100k-char statement with open quote → METADATA_ONLY | 3 |
| SEC-007-S07 | Moved to WRK-101 per RECONCILIATION U-04 (workload-metadata library and allowlist v1; SEC reviews it and `privacy-policy.json` references it) — call it as step (1) of `sanitize()` here | — | — | 0 |
| SEC-007-S08 | Implement the single sanitized-body cache (ING-107 uses it in the extractor; RECONCILIATION U-04) keyed `(tenant, account, QUERY_PARAMETERIZED_HASH_VERSION, QUERY_PARAMETERIZED_HASH, sanitizer_version)` LRU 100k per account-cycle process; metadata never cached | `packages/query_privacy/cache.py` | Two queries differing only in comments get their own invocation_id | 2 |
| SEC-007-S09 | Error scrubbing (G-SEC-23): FastAPI/Pydantic handler without `input/ctx`; Snowflake errors → `(error_code, sql_state, error_class)`; asyncpg IntegrityError → constraint name; structlog processor removing messages of sensitive exception classes | `packages/query_privacy/errors.py`, `apps/api/errors.py` | Secret in a rejected request field never appears in response or logs | 4 |
| SEC-007-S10 | Apply identifier policy: SANITIZED keeps object identifiers; `USER_NAME`/emails routed to SEC-103 pseudonymizer; object tag values hashed unless allowlisted | `packages/query_privacy/fields.py` | Arrow output of fixture contains no plaintext user name | 2 |
| SEC-007-S11 | FULL mode: tenant setting requires approval (Appendix C.4) and capability `sql_text.read_full`; store in `QUERY_TEXT_FULL` masked by `MP_SQL_TEXT_FULL`; 30-day retention; METADATA_ONLY drops both | `packages/query_privacy/full_mode.py` | Viewer without capability reads NULL; FULL enable without approval → 409 `APPROVAL_REQUIRED` | 3 |
| SEC-007-S12 | Sentinel sweep: 20 placements (quoted, `$$`, JSON literal, `--` and `/* */` comments, QUERY_TAG, COPY credentials, CREATE USER password, 16-digit number, quoted identifier (documented retained), error message, RTL override U+202E, NUL byte, homoglyphs, multi-statement, `EXECUTE IMMEDIATE`); scan Parquet bytes, logs, quarantine, evidence, exception reprs | `tests/security/sanitization/test_sentinels.py` | Zero sentinel occurrences except the documented identifier case | 4 |
| SEC-007-S13 | Measure corpus coverage and cost: AST ≥90 %, AST+LEXICAL ≥99 % of corpus statements (re-measure on tenant-zero data — TO VERIFY), p50/p99 latency, cache hit ratio | `docs/evidence/SEC-007/coverage.md` | Numbers recorded per statement class | 3 |
| SEC-007-S14 | Property tests (hypothesis): inject random literals into corpus statements; output never contains the injected literal | `tests/security/sanitization/test_property.py` | 10k examples pass | 3 |
| SEC-007-S15 | Observability: `sanitizer_outcome_total{tier,outcome}`, `sanitizer_duration_seconds`, per-account METADATA_ONLY ratio alarm >5 %/24 h; runbook | `docs/runbooks/sanitizer.md` | Alarm test fires | 2 |
| SEC-007-S16 | Evidence pack | `docs/evidence/SEC-007/<commit>/` | PASS recorded with sqlglot version | 2 |
| SEC-007-S17 | Backfill throughput for 365 days of sanitized text (D-11 owner decision 2026-09-28): persist the S08 cache (keyed by parameterized hash, version and sanitizer_version) between BACKFILL_CHUNK tasks of one account as an encrypted snapshot (per-tenant KMS key, tenant journal prefix, step-(2) sanitized bodies only — never comment/tag metadata), loaded at chunk start, deleted when the backfill plan completes or `sanitizer_version` changes; publish rows/s per vCPU and CPU-hours per 100 M statements at the measured hit ratio for ING-107-S05, ING-010 and CON-101 | `packages/query_privacy/cache_snapshot.py` | 365-day synthetic corpus with realistic hash repetition: CPU-hours with the snapshot recorded against the uncached figure (target ≤ 50 %); sentinel scan of the snapshot finds no comment/tag metadata and no literal | 3 |

Task acceptance:
- [ ] Sentinel secrets appear nowhere in Parquet, logs (including third-party library loggers), quarantine or evidence.
- [ ] Parse failure produces no SQL text; source hashes remain unchanged.
- [ ] dbt appended comment metadata survives; cached bodies (in memory or persisted between backfill chunks) never carry per-run metadata.
- [ ] Error responses and logs never echo submitted values or database text.

### SEC-008 — Audit trail, export and early isolation attack suite
Release: R1 · Estimate: 56–86 h · Risk: M · Decisions: D-10, D-25 · Closes: G-SEC-17, G-SEC-13 (tests), G-SEC-25
Dependency changes: `+CTL-101` (audit table and emit API move there), `+INF-003` (audit bucket/KMS); downstream `CTL-003 −SEC-008` (no longer needed).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SEC-008-S01 | Author audit taxonomy and `event.v1.json` (Appendix H.1): action names, object types, outcome enum `ALLOWED\|DENIED\|FAILED`, redaction rules per field, PRD §118 IP/user-agent | `schemas/audit/event.v1.json`, `docs/security/audit-taxonomy.md` | Every capability in Appendix C maps to ≥1 action | 4 |
| SEC-008-S02 | Extend `audit.events` (CTL-101) with monthly partitions, indexes `(tenant_id, occurred_at DESC)`, `(tenant_id, actor_subject_id, occurred_at)`, `(tenant_id, object_type, object_id)` | migration | EXPLAIN of audit list uses index; no seq scan at 5M rows | 3 |
| SEC-008-S03 | Instrument emit: allowed outcomes inside the business transaction; denied/failed in a separate short transaction after rollback; read-denials rate-limited 1/min per (subject, route) | `packages/audit/emit.py` | Denied mutation still produces exactly one audit row (oracle) | 4 |
| SEC-008-S04 | Build redacted diff generator: per-object field allowlist; destination URLs → host only; secrets/tokens/SQL never | `packages/audit/diff.py` | Snapshot tests for 10 object types | 3 |
| SEC-008-S05 | Enforce append-only: runtime roles INSERT-only; trigger raising on UPDATE/DELETE for all roles except partition-drop by `bridge_retention` | migration | UPDATE as owner fails in test | 2 |
| SEC-008-S06 | Exporter: export ledger `audit.event_exports(event_id, batch_id)`, 2-min settle delay, per-tenant chain, JSONL.gz batches + manifest `{tenant, batch_seq, first/last event, count, sha256, prev_digest}` signed with KMS `ECC_NIST_P256`; S3 in log-archive account, Object Lock GOVERNANCE 365 d | `services/audit_export/` | Late-committed event with older timestamp lands in the next batch; chain intact | 5 |
| SEC-008-S07 | Verifier `bridge-admin audit verify --tenant --from --to`: recompute hashes, signatures, batch_seq gaps; tamper tests (edit, delete, reorder) on a disposable copy | `tools/bridge_admin/audit_verify.py` | Each tamper type detected with the specific error | 3 |
| SEC-008-S08 | Audit API: `GET /v1/audit/events` (`audit.read`, keyset pagination, filters actor/action/object/outcome/time), `POST /v1/audit/exports` (`audit.export`, async, bounded) | `apps/api/routes/audit.py` | Auditor with A1 scope sees only events whose object scope ⊆ A1 or tenant-level events allowed by policy | 4 |
| SEC-008-S09 | Platform security event stream: cross-tenant 404 bursts, repeated AUTHZ denials, break-glass/support access use → CloudWatch alarms + pager | `services/security_events/`, `infra/alarms/security.tf` | Synthetic probe pages in staging | 3 |
| SEC-008-S10 | Attack harness: pytest plugin over `catalog.yaml`; fixtures tenant A (A1, A2), B (B1); personas A-admin, A-reader-A1, A-team-reader(Finance), B-admin; colliding names/query IDs from FND-004 | `tests/security/attacks/plugin.py` | Harness runs locally and in staging | 5 |
| SEC-008-S11 | Implement ATK cases available at M1 (ATK-01…10, 18…26, 29…33) | `tests/security/attacks/test_*.py` | All PASS | 8 |
| SEC-008-S12 | CI integration: route coverage report (every route in OpenAPI must appear in ≥1 ATK or an explicit exemption); nightly staging run blocks promotion on failure | `.github/workflows/security-isolation.yml` | New unregistered route fails CI | 3 |
| SEC-008-S13 | Timing check (ATK-31): foreign-UUID 404 vs nonexistent-UUID 404 latency p50 within ±10 % over 1,000 samples | `tests/security/attacks/test_timing.py` | Recorded; failure opens a finding, not a flaky retry | 2 |
| SEC-008-S14 | Retention: drop PG audit partitions >365 d only after export verified; S3 lifecycle expiry after lock | `services/audit_export/retention.py` | Dry-run manifest lists partitions and verified batches | 2 |
| SEC-008-S15 | Runbook (audit write failure → fail closed for privileged mutations; export backlog; verify failure) and evidence | `docs/runbooks/audit.md`, `docs/evidence/SEC-008/<commit>/` | Drill executed | 3 |

Task acceptance:
- [ ] A denied mutation creates exactly one safe audit event; allowed mutations are audited atomically with the change.
- [ ] Tampering (edit/delete/reorder) of an exported batch is detected; late commits are not lost.
- [ ] Foreign IDs never disclose names/counts/totals across all implemented ATK cases.
- [ ] Unregistered routes fail CI; the suite runs nightly in staging.

## 5. New tasks required

### SEC-101 — Scope grammar and normalized permission profile library
Release: R1 · Estimate: 24–38 h · Risk: M · Decisions: D-02 · Closes: G-SEC-02, G-SEC-03
Why: one pure library must own scope semantics for PG predicates, Snowflake entitlements, cache keys, cursors and delegation; otherwise each consumer re-implements the AND/OR semantics. Plugs in: after FND-004; before SEC-004, SEC-005, CTL-006.
Dependency changes: `+FND-004`.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SEC-101-S01 | Write JSON Schemas `scope-clause.v1` and `profile-canonical.v1` (Appendix B.1–B.2); every dimension required, `"*"` or non-empty UUID list | `schemas/authz/*.json` | Schema rejects a clause missing `group` with `SCOPE_DIMENSION_MISSING` | 2 |
| SEC-101-S02 | Implement normalization to maximal atoms, RFC 8785 canonical JSON and `profile_hash = sha256` with prefix `pf1:` (Appendix B.3) | `packages/authz_scope/normalize.py` | Clause reorder/duplicate/merge variants yield identical hash | 4 |
| SEC-101-S03 | Implement `subsumes(a, b)`, `intersect(a, b)` and `uncovered_atoms(object, viewer)` | `packages/authz_scope/algebra.py` | Unit tests incl. flags and account-implies-org rule | 3 |
| SEC-101-S04 | Implement PG predicate compiler with bound arrays (Appendix B.4) | `packages/authz_scope/compile_pg.py` | No string interpolation of IDs (bandit/semgrep rule) | 4 |
| SEC-101-S05 | Implement Snowflake entitlement-row expansion (Appendix A.2 columns) | `packages/authz_scope/compile_snowflake.py` | Row count = atom count; deterministic order | 2 |
| SEC-101-S06 | Encode the 40-case golden table (Appendix B.5) as fixtures | `tests/authz_scope/golden.yaml` | All cases pass | 3 |
| SEC-101-S07 | Property tests: normalize idempotent; PG compilation ≡ reference evaluator on random rows; expansion ≡ evaluator | `tests/authz_scope/test_property.py` | 5k hypothesis examples pass | 4 |
| SEC-101-S08 | Limits/errors: >2,000 atoms → `SCOPE_TOO_COMPLEX`; unknown/foreign IDs via `ScopeCatalog` interface → `SCOPE_REFERENCE_INVALID` (non-enumerating) | `packages/authz_scope/validate.py` | Foreign account UUID rejected with same message as nonexistent | 2 |
| SEC-101-S09 | Document grammar versioning (v1 → v2 adds resource dimension, SEC-106) | `docs/security/scope-grammar.md` | Reviewed | 1 |

Task acceptance:
- [ ] One canonical hash per semantic scope; equivalent inputs hash identically.
- [ ] PG and Snowflake compilations agree with the reference evaluator on every golden and random case.
- [ ] Missing dimensions never default to ANY.

### SEC-102 — Maker-checker approvals and step-up authentication
Release: R1 · Estimate: 36–56 h · Risk: M · Decisions: D-25 · Closes: G-SEC-05, G-SEC-07 (step-up)
Why: close, restatement, price overrides, rule publication, FULL SQL, SSO enforcement and support access need a shared, tested SoD mechanism. Plugs in after SEC-004 and SEC-002; consumed by FIN-002, FIN-010, ALC-003, SEC-003, SEC-007, SEC-104, CTL-007.
Dependency changes: `+SEC-004`, `+SEC-002`, `+CTL-101`.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SEC-102-S01 | Migrate `governance.approvals` (Appendix C.4) and state machine REQUESTED→APPROVED/REJECTED/EXPIRED/VOIDED→EXECUTED | migration, `docs/security/approvals.md` | Illegal transitions rejected by CHECK + service | 3 |
| SEC-102-S02 | Add per-action policy (`four_eyes`, `self_approval_allowed`, `step_up_max_age_s`) to `capabilities.yaml`; tenant overrides only within allowed values | `packages/authz/capabilities.yaml` | Tenant cannot set close to NONE | 2 |
| SEC-102-S03 | API: `POST /v1/approvals`, `POST /v1/approvals/{id}/approve`, `/reject` (If-Match), `GET /v1/approvals?state=`; content hash computed server-side from the object snapshot | `apps/api/routes/approvals.py` | Client-supplied hash ignored | 4 |
| SEC-102-S04 | Guard `require_approval(action, obj)` for execution endpoints: APPROVED, unexpired, same revision+hash, approver still holds checker capability over object scope | `packages/authz/approvals.py` | Edit after approval → execution 409 `APPROVAL_INVALID` | 3 |
| SEC-102-S05 | Step-up: `require_step_up(max_age)` using session `auth_time`; `POST /v1/auth/step-up` re-auth (Cognito `prompt=login` / SAML ForceAuthn — TO VERIFY LIVE; fallback full re-login) | `apps/api/auth/step_up.py` | auth_time 11 min old → 401 `AUTH_STEP_UP_REQUIRED` | 4 |
| SEC-102-S06 | SoD invariants: approver ≠ requester and ≠ last editor (`updated_by` of approved revision) | `packages/authz/sod.py` | Same-person approval → 403 `SOD_VIOLATION` | 2 |
| SEC-102-S07 | Self-approval mode: allowed only where policy permits and no other eligible approver exists at request time; recorded `self_approved=true`, surfaced on statements/audit | `packages/authz/self_approval.py` | Adding a second eligible approver disables self-approval for new requests | 3 |
| SEC-102-S08 | Emit `approval.requested/decided` events for in-app inbox (notifications via GOV later) | `packages/authz/approval_events.py` | Events in outbox with IDs only | 2 |
| SEC-102-S09 | UI approvals inbox and object banners (pending, voided on edit, self-approved) | `apps/web/approvals/` | Playwright covers states | 5 |
| SEC-102-S10 | Tests: void on edit, expiry at 7 d, approver capability revoked between approve and execute, approve-vs-edit race (If-Match) | `tests/security/approvals/` | All PASS | 4 |
| SEC-102-S11 | Metrics `approval_total{action,outcome}`; audit actions | `packages/authz/metrics.py` | Visible in staging dashboard | 1 |
| SEC-102-S12 | Evidence | `docs/evidence/SEC-102/<commit>/` | PASS | 2 |

Task acceptance:
- [ ] No action in Appendix C.4 marked four-eyes can be executed by one person unless self-approval is permitted and flagged.
- [ ] Any change to the approved object voids the approval.
- [ ] Step-up is enforced for listed actions with a 10-minute `auth_time` window.

### SEC-103 — Pseudonymization and deletable identity dictionary (D-10)
Release: R1 · Estimate: 35–56 h · Risk: H · Decisions: D-10, D-16 · Closes: G-SEC-16
Why: user identifiers must be pseudonymized before the immutable journal from the first extraction; retrofitting after data exists requires re-extraction. Plugs in: before ING-003 (`ING-003 +SEC-103`), CTL-005 (`+SEC-103`), OPS-005.
Dependency changes: `+INF-003` (KMS), `+CTL-101`, `+SEC-001`.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SEC-103-S01 | Write design (Appendix G.2) incl. legal-review note on residual windows | `docs/security/pseudonymization.md` | Legal/owner acknowledgement recorded | 2 |
| SEC-103-S02 | Tenant key lifecycle: 32-byte key at tenant creation, KMS `Encrypt` with encryption context `{tenant_id}`; `privacy.tenant_keys(tenant_id, key_version, ciphertext, created_at, destroyed_at)`; KMS key policy requires matching context and principal tag | migration, `infra/terraform/modules/kms/pseudonym.tf` | Task role of tenant A cannot decrypt B's key (AccessDenied) | 4 |
| SEC-103-S03 | Pseudonymizer: `u1_` + base32(HMAC-SHA256(key, "sf_user\|"+account_id+"\|"+upper(NFKC(name))))[:26]; `e1_` for emails in tags | `packages/query_privacy/pseudonym.py` | Case variants map to same value; tenants differ | 3 |
| SEC-103-S04 | Extraction contract only: pseudonym scheme, key-access interface and dictionary-delta format (deltas to the control API, never S3) for USER_NAME (QUERY_HISTORY, LOGIN_HISTORY if projected); in-extractor key handling (decrypt once per task) and pseudonymization are ING-107-S03 (RECONCILIATION U-04) | `packages/extraction/privacy_hook.py` contract + test double | ING-107-S03 pipeline test over the test double: Parquet fixture contains zero plaintext names | 2 |
| SEC-103-S05 | Internal endpoint `POST /internal/v1/identity-dictionary:batchUpsert` (SigV4/mTLS, account-cycle identity bound to tenant) with tombstone suppression read from the OPS-104 tombstone registry (RECONCILIATION U-11, C-19) | `apps/api/internal/identity_dictionary.py` | Tombstoned pseudonym is not re-populated | 3 |
| SEC-103-S06 | Post-query resolver in API for callers with `identity.resolve` (≤500 pseudonyms, one PG query); response `{pseudonym, display_name\|null, resolution: RESOLVED\|HIDDEN\|ERASED}` | `packages/semantic/identity_resolver.py` | Viewer without capability sees HIDDEN | 3 |
| SEC-103-S07 | Name search: PG lookup → pseudonym list (cap 1,000) → Snowflake `IN`; above cap → 422 `FILTER_TOO_BROAD` | `packages/semantic/user_filter.py` | Search for erased user returns nothing | 3 |
| SEC-103-S08 | Config-publication helper: user-dimension `eq/in` values → pseudonyms; reject prefix/contains on user names in R1 (`OPERATOR_NOT_SUPPORTED_FOR_PSEUDONYMIZED_DIMENSION`) | `packages/governance/pseudonymize_rules.py` | ALC rule with user `contains` rejected with that code | 2 |
| SEC-103-S09 | Erasure primitive `erase_subject(tenant, pseudonym, request_id)`, called as a stage handler by OPS-005's `POST /v1/privacy/requests` workflow (SUBJECT_ERASURE, approval via SEC-102): delete dictionary rows, write a SUBJECT tombstone to OPS-104, bump tenant authz_epoch (cache), audit, residual report (PITR 35 d, Redis TTL); the request API and workflow are OPS-005's (RECONCILIATION U-11, C-20) | `packages/privacy/erase_subject.py` | After erasure no API response contains the name | 1 |
| SEC-103-S10 | Tenant offboarding: delete key ciphertext rows; document backup expiry | `packages/privacy/offboarding.py` | Pseudonyms no longer computable post-deletion (test) | 2 |
| SEC-103-S11 | Tests: replay reproduces identical pseudonyms; erased user stays hidden after re-extraction; email sentinel in QUERY_TAG never plaintext | `tests/security/privacy/test_pseudonym.py` | PASS | 4 |
| SEC-103-S12 | UX contract note for "top users" (pseudonym chip + resolution state) handed to UX backlog | `docs/security/pseudonym-ux.md` | Reviewed by UX | 1 |
| SEC-103-S13 | Observability: `identity_dictionary_size`, `identity_resolution_total{result}`; runbook for key access failures | `docs/runbooks/pseudonymization.md` | Drill: KMS deny → extraction fails closed (no plaintext fallback) | 2 |
| SEC-103-S14 | Evidence | `docs/evidence/SEC-103/<commit>/` | PASS | 2 |

Task acceptance:
- [ ] No plaintext Snowflake user name or tag email exists in S3 journal, RAW or canonical fixtures.
- [ ] Erasure removes resolvability everywhere the product displays names; residual windows are reported.
- [ ] KMS denial makes extraction fail closed rather than store plaintext.

### SEC-104 — Time-bound, customer-approved support access
Release: R1 · Estimate: 25–42 h · Risk: M · Decisions: D-25 · Closes: G-SEC-18
Why: launch support needs a sanctioned, audited path; otherwise standing cross-tenant access appears. Plugs in after SEC-102, SEC-006 and SEC-105; consumed by OPS-010 and OPS-004 (attack surface). SEC-104 owns support-access grants end to end; OPS-106-S06…S09 fold into it (RECONCILIATION U-05, C-15).
Dependency changes: `+SEC-102`, `+SEC-006`, `+SEC-105`, `+CTL-102` (internal console operator authentication).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SEC-104-S01 | Migrate `identity.support_access_grants` (tenant_id, id, operator_subject, reason_code, case_ref, scope jsonb ∈ {`health_read`, `analytics_read`} in R1 — `config_write` is not a support scope, capabilities[], approved_by, starts_at, expires_at default starts_at+4 h and ≤ starts_at+8 h, revoked_at, status) (RECONCILIATION C-15) | migration | CHECK rejects >8 h and scope `config_write` | 2 |
| SEC-104-S02 | Reuse CTL-102 operator authentication (IAM Identity Center OIDC, hardware-key MFA); add operator role `support_agent` and bind each support session to a case reference | `apps/internal_console/support/` | Customer Cognito user cannot reach console; operator without `support_agent` cannot request | 4 |
| SEC-104-S03 | Request/approve flow: operator requests; tenant member with `support.grant` approves scope/duration (step-up); tenant approval policy incl. the optional `health_read` auto-approve (absorbed from OPS-106-S07; RECONCILIATION U-05) | `apps/api/routes/support_access.py` | Operator cannot approve own request; `health_read` auto-approved only when the tenant policy enables it | 4 |
| SEC-104-S04 | Materialize as synthetic membership `kind=SUPPORT`, read-only capability set, profile with sanitized SQL + pseudonymous identities; banner header `X-Bridge-Support-Session` | `packages/authz/support_membership.py` | Write endpoints → 403; FULL SQL masked | 4 |
| SEC-104-S05 | Expiry reaper and revoke (≤30 s, SEC-006 mechanisms) | `services/workers/support_expiry.py` | Access denied within 30 s of expiry | 2 |
| SEC-104-S06 | Audit every support request (`support.access.used`) and show in tenant audit log | `packages/audit/support.py` | Tenant auditor sees each access | 2 |
| SEC-104-S07 | Tests: expired, other-tenant, self-grant, write attempts | `tests/security/support/` | All denied | 3 |
| SEC-104-S08 | Runbook and evidence | `docs/runbooks/support-access.md` | Drill executed | 2 |

Task acceptance:
- [ ] No operator reads tenant data without an unexpired, customer-approved grant.
- [ ] Support sessions are read-only, sanitized, pseudonymous, bannered and audited.

### SEC-105 — Tenant serving principal and profile-role provisioner
Release: R1 · Estimate: 40–63 h · Risk: H · Decisions: D-02, D-21, D-22 · Closes: G-SEC-01 (lifecycle), G-SEC-21, G-SEC-22
Why: SEC-005 proves the policy model with scripted fixtures; production needs an idempotent, least-privileged provisioner with GC and drift detection. Plugs in after SEC-005 and CTL-004; required by SEC-006, CTL-102, OPS-004, OPS-007.
Dependency changes: `+SEC-005`, `+CTL-004`, `+INF-005`, `+SEC-101`, `+INF-103` (the tenant serving IAM role is created by the single runtime IAM provisioner; RECONCILIATION U-02). SEC-105 keeps everything Snowflake-side.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SEC-105-S01 | Service skeleton consuming `tenant.principal.requested` and `authz.profile.provision_requested` from FIFO SQS (MessageGroupId = tenant_id) | `services/authz_provisioner/` | Duplicate message → single effect | 3 |
| SEC-105-S02 | Moved to INF-103 per RECONCILIATION U-02, C-11 — request the tenant serving role `bridge-<env>-srv-<uuid32>` (no IAM path, srv boundary, broker-only trust) through INF-103's provisioner and consume its ARN here | — | — | 0 |
| SEC-105-S03 | Snowflake onboarding as `TENANT_ONBOARDER`: `CREATE USER IF NOT EXISTS … TYPE=SERVICE WORKLOAD_IDENTITY=(TYPE=AWS ARN=…) DEFAULT_SECONDARY_ROLES=()`, attach session policy, insert `TENANT_PRINCIPAL`; retry WIF test login up to 5 min for IAM propagation | `services/authz_provisioner/snowflake_onboard.py` | New tenant principal can log in via broker test path | 5 |
| SEC-105-S04 | Profile provisioning as `PROFILE_PROVISIONER`: `CREATE ROLE IF NOT EXISTS`, `GRANT ROLE BRIDGE_SERVING_BASE`, MERGE entitlement rows keyed `(role_name, atom_hash)`, `GRANT ROLE … TO USER <tenant user>`, verify entitlement count via a broker test query | `services/authz_provisioner/profiles.py` | Re-run is a no-op (grant diff empty) | 5 |
| SEC-105-S05 | PG transitions: profile PROVISIONING→ACTIVE, pending memberships attached, epochs bumped, latency recorded | `services/authz_provisioner/pg_state.py` | p95 commit→ACTIVE ≤60 s (S12) | 3 |
| SEC-105-S06 | GC: unreferenced >15 min → RETIRING (entitlements ACTIVE=FALSE, revoke from user); >24 h → DROP ROLE; never touch referenced profiles | `services/authz_provisioner/gc.py` | Referenced profile untouched after 25 h | 3 |
| SEC-105-S07 | Tenant disable/offboard as a stage handler of OPS-005's deletion orchestrator (U-11): principal DISABLED, `ALTER USER … SET DISABLED=TRUE`, drop roles; request IAM role deletion from INF-103 after 7 d (INF-103-S08 revocation order; RECONCILIATION U-02) | `services/authz_provisioner/offboard.py` | Offboarded tenant user cannot log in | 2 |
| SEC-105-S08 | Admission quota: ≤200 active profiles/tenant (entitlement); the IAM role quota guard (alarm 70 %, block 80 %, metric `iam_roles_used_ratio`) is INF-103-S07's (RECONCILIATION C-11) | `services/authz_provisioner/quotas.py` | Quota breach returns `QUOTA_EXCEEDED` | 1 |
| SEC-105-S09 | Nightly Snowflake/PG drift reconciliation: `SHOW USERS`/workload identity ARN (must equal INF-103's registered `bridge-<env>-srv-<uuid32>` ARN) ↔ `TENANT_PRINCIPAL` ↔ PG; profile roles' grants must equal {BRIDGE_SERVING_BASE}; each user holds only own-tenant profile roles; IAM-side reconcile/quarantine is INF-103-S09 (RECONCILIATION U-02) | `services/authz_provisioner/drift.py` | Injected extra grant pages within one run | 3 |
| SEC-105-S10 | Failure handling: partial provisioning retried idempotently; poison → DEAD + alarm; memberships stay pending (fail closed) | `services/authz_provisioner/errors.py` | Crash after CREATE ROLE before GRANT recovers on retry | 3 |
| SEC-105-S11 | Privilege tests: provisioner cannot write `TENANT_PRINCIPAL`, cannot CREATE USER, reads zero serving rows; onboarder cannot CREATE ROLE | `tests/security/provisioner/` | All denied live | 4 |
| SEC-105-S12 | Benchmark 50 concurrent profile creations; record p50/p95 | `docs/evidence/SEC-105/latency.md` | p95 ≤60 s or documented | 2 |
| SEC-105-S13 | Observability/runbook: `authz_profile_provision_seconds`, `authz_drift_findings`, DEAD events | `docs/runbooks/authz-provisioner.md` | Drill executed | 2 |
| SEC-105-S14 | Evidence | `docs/evidence/SEC-105/<commit>/` | PASS | 2 |

Task acceptance:
- [ ] Provisioning is idempotent and fails closed; no member is ever attached to a broader profile while waiting.
- [ ] A compromised profile provisioner cannot cross tenants (proven by S11).
- [ ] Drift between IAM, Snowflake and PG is detected nightly.

### SEC-106 — Resource-level scopes, SCIM and pseudonym key rotation
Release: R2 · Estimate: 40–64 h · Risk: M · Decisions: D-16 · Closes: R2 remainder of G-SEC-02, G-SEC-16
Why: resource-level grants (single warehouse), enterprise user provisioning and key rotation are real enterprise asks but not first-customer blockers. Plugs in after SEC-101/SEC-105/SEC-103.
Dependency changes: `+SEC-101`, `+SEC-105`, `+SEC-103`.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SEC-106-S01 | Grammar v2 with `resource` dimension (type+id) and `RAP_RESOURCE_SCOPED` | `schemas/authz/scope-clause.v2.json`, policy DDL | v1 profiles hash unchanged | 6 |
| SEC-106-S02 | Expansion caps and performance re-benchmark | evidence | Within SEC-005 budget | 3 |
| SEC-106-S03 | SCIM 2.0 `/scim/v2/Users`, `/Groups` with per-tenant bearer token (hashed), mapping groups → grants templates | `apps/api/scim/` | Okta SCIM test suite passes | 10 |
| SEC-106-S04 | Pseudonym key rotation: dual-key period, mapping table old→new, re-publication of rules | `packages/query_privacy/rotation.py` | Joins across rotation boundary preserved | 6 |
| SEC-106-S05 | Prefix/contains user-name rules via dictionary expansion + republish on dictionary change | `packages/governance/user_rule_expansion.py` | New matching user appears after republish | 5 |
| SEC-106-S06 | Regex operator security review (ReDoS limits) with ALC | review note | Bounded evaluation proven | 3 |
| SEC-106-S07 | Tests across all | `tests/security/r2/` | PASS | 5 |
| SEC-106-S08 | Evidence | `docs/evidence/SEC-106/<commit>/` | PASS | 2 |

Task acceptance:
- [ ] Resource-scoped profile sees only the granted resources' rows; v1 behaviour unchanged.
- [ ] SCIM deprovisioning revokes access within 30 s.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| SEC-001 | R1 | 24 | 40 |
| SEC-002 | R1 | 64 | 96 |
| SEC-003 | R1 (D-20) | 60 | 90 |
| SEC-004 | R1 | 52 | 80 |
| SEC-005 | R1 | 60 | 92 |
| SEC-006 | R1 | 41 | 64 |
| SEC-007 | R1 | 50 | 78 |
| SEC-008 | R1 | 56 | 86 |
| SEC-101 | R1 | 24 | 38 |
| SEC-102 | R1 | 36 | 56 |
| SEC-103 | R1 | 35 | 56 |
| SEC-104 | R1 | 25 | 42 |
| SEC-105 | R1 | 40 | 63 |
| SEC-106 | R2 | 40 | 64 |
| **Total R1** | | **567** | **881** |
| R1\* (none after D-20, 2026-09-28) | — | 0 | 0 |
| **Total R2** | | **40** | **64** |

## 7. Owner questions

1. **Q1 Tenant creation in R1**: operator-provisioned only (recommended; CTL-102) or self-service sign-up? Self-service needs abuse controls, email verification gating and quota defaults before launch.
2. **Q2 Four-eyes defaults for small customers**: confirm Appendix C.4 defaults — period close, restatement, statement issue and FULL SQL are `REQUIRED` (no self-approval); rule publication and price overrides allow flagged self-approval when the tenant has a single eligible approver.
3. **Q3 MFA factors**: TOTP + passkeys only, SMS and email-OTP MFA disabled (email OTP only for recovery) — acceptable to the first customer?
4. **Q4 Session defaults**: idle 30 min / absolute 12 h, tenant-configurable within 15–120 min / 1–24 h?
5. **Q5 SSO JIT**: allow opt-in JIT (Viewer, empty scope) in R1, or invitation-only until SCIM (R2)?
6. **Q6 Cognito Plus tier** ($0.02/MAU, threat protection) vs Essentials ($0.015/MAU) for R1?
7. **Q7 Audit vs erasure**: approve the legal basis to retain actor identity/IP in audit for 365 days despite user erasure requests (Appendix H.4), with pseudonymized S3 export.
8. **Q8 Support access**: per-case customer approval only (recommended), or a contractual standing consent for Tier-2 support during onboarding?
9. **Q9 "Integration administration"** (PRD role matrix, Organization Admin): does it include Snowflake connection management, or only notification destinations/API clients (recommended: the latter; connections stay with Snowflake Admin/Owner)?

---

## Appendix A — ADR-005 amendment: tenant WIF user + per-profile Snowflake roles (D-02)

### A.1 Model
- **Tenant boundary = identity.** One AWS IAM role `arn:aws:iam::<platform>:role/bridge-<env>-srv-<uuid32>` (no IAM path, created by INF-103; RECONCILIATION C-11, U-02) and one Snowflake `TYPE=SERVICE` user `BRIDGE_<ENV>_T_<TENANT_SHORT>` per tenant, bound by `WORKLOAD_IDENTITY=(TYPE=AWS ARN=…)` (syntax VERIFIED via search snippet of docs.snowflake.com/en/user-guide/workload-identity-federation, 2026-09-28). `TENANT_SHORT` = first 12 chars of base32(tenant UUID). The IAM role has **no permission policies** (only identity) and a permissions boundary denying everything; its trust policy allows only the query broker task role.
- **Intra-tenant scope = role.** One Snowflake role per normalized permission profile: `BRIDGE_<ENV>_T_<TENANT_SHORT>_P_<first 16 hex of profile_hash>`. Profile content is immutable: a scope change maps the member to a different profile; it never edits a profile.
- **Who chooses.** Only the query broker (D-22) maps `AuthContext → (tenant user, profile role)` from PG state. The tenant user is granted all of its tenant's profile roles, so Snowflake alone does not stop a *broker-controlled* session from switching to a broader same-tenant profile; Snowflake does stop any session from reading another tenant, and no other component can open a tenant-user session at all. This is equivalent to ADR-005 as written (where the broker could assume every per-profile principal) and is recorded as residual risk RR-01.
- **Kill switch.** `SECURITY.TENANT_PRINCIPAL.STATUS='DISABLED'` hides all rows immediately (the policy joins it); `ALTER USER … SET DISABLED=TRUE` blocks logins.

### A.2 Snowflake DDL (`SECURITY` schema, same database as serving tables)
```sql
CREATE TABLE SECURITY.TENANT_PRINCIPAL (
  TENANT_ID        VARCHAR(36)   NOT NULL,
  SNOWFLAKE_USER   VARCHAR(255)  NOT NULL,
  AWS_ROLE_ARN     VARCHAR(2048) NOT NULL,
  STATUS           VARCHAR(16)   NOT NULL,            -- ACTIVE | DISABLED
  CREATED_AT       TIMESTAMP_TZ  NOT NULL,
  DISABLED_AT      TIMESTAMP_TZ,
  CONSTRAINT PK_TENANT_PRINCIPAL PRIMARY KEY (SNOWFLAKE_USER)   -- informational; uniqueness checked by drift job
);
CREATE TABLE SECURITY.PROFILE (
  TENANT_ID        VARCHAR(36)  NOT NULL,
  PROFILE_HASH     VARCHAR(64)  NOT NULL,
  ROLE_NAME        VARCHAR(255) NOT NULL,
  GRAMMAR_VERSION  SMALLINT     NOT NULL,
  SQL_TEXT_ACCESS  VARCHAR(16)  NOT NULL,             -- NONE | SANITIZED | FULL
  CANONICAL_JSON   VARIANT      NOT NULL,
  STATUS           VARCHAR(16)  NOT NULL,             -- PROVISIONING | ACTIVE | RETIRING | RETIRED
  CREATED_AT       TIMESTAMP_TZ NOT NULL,
  RETIRED_AT       TIMESTAMP_TZ
);
CREATE TABLE SECURITY.PROFILE_ENTITLEMENT (
  ROLE_NAME           VARCHAR(255) NOT NULL,
  TENANT_ID           VARCHAR(36)  NOT NULL,
  ATOM_HASH           VARCHAR(64)  NOT NULL,          -- sha256 of canonical atom; MERGE key with ROLE_NAME
  ORGANIZATION_ID     VARCHAR(36),                    -- NULL = any (always NULL when ACCOUNT_ID set)
  ACCOUNT_ID          VARCHAR(36),                    -- NULL = any
  GROUP_SET_ID        VARCHAR(36),                    -- NULL = unrestricted group dimension
  GROUP_ID            VARCHAR(36),                    -- NULL = any group within GROUP_SET_ID
  INCLUDE_SHARED      BOOLEAN NOT NULL,
  INCLUDE_UNALLOCATED BOOLEAN NOT NULL,
  ACTIVE              BOOLEAN NOT NULL,
  CREATED_AT          TIMESTAMP_TZ NOT NULL
) CLUSTER BY (ROLE_NAME);
```
Rows are never updated except `ACTIVE`. Snowflake does not enforce PK/UNIQUE; the provisioner MERGEs on `(ROLE_NAME, ATOM_HASH)` and the drift job asserts no duplicates.

### A.3 Policy bodies
Serving rows carry string UUIDs. Sentinel group IDs: `__SHARED__`, `__UNALLOCATED__`.
```sql
-- Account-grain facts (charges, metering, query facts, storage, account/org dimension dictionaries)
CREATE OR REPLACE ROW ACCESS POLICY SECURITY.RAP_ACCOUNT_SCOPED
AS (P_TENANT_ID VARCHAR, P_ORG_ID VARCHAR, P_ACCOUNT_ID VARCHAR) RETURNS BOOLEAN ->
  EXISTS (
    SELECT 1
    FROM SECURITY.TENANT_PRINCIPAL tp
    JOIN SECURITY.PROFILE_ENTITLEMENT e ON e.TENANT_ID = tp.TENANT_ID
    WHERE tp.SNOWFLAKE_USER = CURRENT_USER() AND tp.STATUS = 'ACTIVE'
      AND e.ROLE_NAME = CURRENT_ROLE() AND e.ACTIVE
      AND e.TENANT_ID = P_TENANT_ID
      AND e.GROUP_SET_ID IS NULL                       -- only clauses with unrestricted group dimension
      AND (e.ORGANIZATION_ID IS NULL OR e.ORGANIZATION_ID = P_ORG_ID)
      AND (e.ACCOUNT_ID IS NULL OR e.ACCOUNT_ID = P_ACCOUNT_ID)   -- org-level rows (account NULL) need ACCOUNT_ID IS NULL
  );

-- Group-grain facts (allocations, showback, group budgets actuals); no "all groups" rows allowed here
CREATE OR REPLACE ROW ACCESS POLICY SECURITY.RAP_GROUP_SCOPED
AS (P_TENANT_ID VARCHAR, P_ORG_ID VARCHAR, P_ACCOUNT_ID VARCHAR, P_GROUP_SET_ID VARCHAR, P_GROUP_ID VARCHAR)
RETURNS BOOLEAN ->
  EXISTS (
    SELECT 1
    FROM SECURITY.TENANT_PRINCIPAL tp
    JOIN SECURITY.PROFILE_ENTITLEMENT e ON e.TENANT_ID = tp.TENANT_ID
    WHERE tp.SNOWFLAKE_USER = CURRENT_USER() AND tp.STATUS = 'ACTIVE'
      AND e.ROLE_NAME = CURRENT_ROLE() AND e.ACTIVE
      AND e.TENANT_ID = P_TENANT_ID
      AND (e.ORGANIZATION_ID IS NULL OR e.ORGANIZATION_ID = P_ORG_ID)
      AND (e.ACCOUNT_ID IS NULL OR e.ACCOUNT_ID = P_ACCOUNT_ID)
      AND (e.GROUP_SET_ID IS NULL OR e.GROUP_SET_ID = P_GROUP_SET_ID)
      AND (e.GROUP_ID IS NULL OR e.GROUP_ID = P_GROUP_ID)
      AND (P_GROUP_ID <> '__SHARED__'      OR e.INCLUDE_SHARED)
      AND (P_GROUP_ID <> '__UNALLOCATED__' OR e.INCLUDE_UNALLOCATED)
  );

-- Tenant-level metadata (publication status visible to every member of the tenant)
CREATE OR REPLACE ROW ACCESS POLICY SECURITY.RAP_TENANT_ONLY AS (P_TENANT_ID VARCHAR) RETURNS BOOLEAN ->
  EXISTS (SELECT 1 FROM SECURITY.TENANT_PRINCIPAL tp
          JOIN SECURITY.PROFILE p ON p.TENANT_ID = tp.TENANT_ID
          WHERE tp.SNOWFLAKE_USER = CURRENT_USER() AND tp.STATUS = 'ACTIVE'
            AND p.ROLE_NAME = CURRENT_ROLE() AND p.STATUS IN ('ACTIVE','RETIRING')
            AND tp.TENANT_ID = P_TENANT_ID);

-- Full SQL text column (FULL privacy mode only)
CREATE OR REPLACE MASKING POLICY SECURITY.MP_SQL_TEXT_FULL AS (V VARCHAR) RETURNS VARCHAR ->
  CASE WHEN EXISTS (SELECT 1 FROM SECURITY.PROFILE p
                    WHERE p.ROLE_NAME = CURRENT_ROLE() AND p.SQL_TEXT_ACCESS = 'FULL' AND p.STATUS = 'ACTIVE')
       THEN V ELSE NULL END;
```
Normalization guarantees `INCLUDE_SHARED = INCLUDE_UNALLOCATED = TRUE` whenever the group dimension is unrestricted. Memoizable-function variant (Snowflake-recommended for mapping lookups — VERIFIED search snippet docs.snowflake.com/en/user-guide/security-row-using, 2026-09-28): `SECURITY.ENTITLED_KEYS(ROLE VARCHAR)` returning `ARRAY` of `'T|O|A|GS|G|flags'` strings, called as `ENTITLED_KEYS(CURRENT_ROLE())` with ≤12 `ARRAY_CONTAINS` probes; the role is passed as an explicit argument so cached results can never be shared across roles. Argument support and cache scope are **TO VERIFY LIVE**; SEC-005-S13 selects the variant by benchmark.

### A.4 Row semantics that prevent hidden-total leakage
1. Account-grain tables have **no group columns**; only clauses with unrestricted group dimension see them. A team-restricted profile gets zero rows, so it cannot compute "Finance share of A1".
2. Group-grain tables contain one row per real group plus sentinels; there is no "ALL" row. Parent-group rollups (hierarchies) are materialized per ancestor group ID, and a grant on a parent group expands at normalization to the parent **and** all descendants valid in the published hierarchy version (expansion recomputed at hierarchy publication → new profile hashes; access-relevant hierarchy publication requires `access.review` approval, Appendix C.4).
3. Ratios: the semantic registry declares `denominator_relation`; if the caller's profile cannot read it, the API returns `null` with reason `DENOMINATOR_OUTSIDE_SCOPE`. "Other" buckets and "top N + rest" are computed from the visible total.
4. `attribution_coverage` requires `INCLUDE_UNALLOCATED`; otherwise `null` + reason.
5. Dimension dictionaries (account list, group list, warehouse names, user pseudonyms) are serving tables under the same policies; PG never serves unscoped option lists.

### A.5 Lifecycle when a member's scope changes
1. API transaction (SEC-004/SEC-006): update grants → SEC-101 computes new canonical profile → upsert `identity.permission_profiles(tenant_id, profile_hash)`; if new, status PROVISIONING. If the new profile subsumes the old, keep `profile_id` until ACTIVE; else set `profile_id=NULL` (fail closed). Bump `permission_epoch`; outbox `authz.profile.provision_requested` + `authz.membership.changed`.
2. SEC-105 (FIFO per tenant): CREATE ROLE → GRANT BASE → MERGE entitlements (ACTIVE) → GRANT ROLE TO USER → verify via broker test query → PG: profile ACTIVE, attach pending memberships. Target p95 ≤60 s (DDL statements need no warehouse; the MERGE uses the XSMALL security warehouse).
3. Old profile: if unreferenced for 15 min → RETIRING (entitlements ACTIVE=FALSE, REVOKE ROLE FROM USER); after 24 h → DROP ROLE. Retirement is garbage collection, not the security control: the broker never uses a profile not currently mapped to the requesting membership.
4. Tenant-level visibility events (privacy mode change, access-relevant group-set publication, profile retirement) bump `tenants.authz_epoch` (cache/cursor invalidation).

### A.6 Privileged identities and blast radius
| Identity | Privileges | Cannot | Blast radius if compromised |
|---|---|---|---|
| `TENANT_ONBOARDER` (WIF service user; runs only in the operator-approved provisioning workflow) | CREATE USER; owns tenant users; INSERT/UPDATE `TENANT_PRINCIPAL` | CREATE ROLE; write entitlements; read serving | Could bind a new user to a tenant — mitigated by ARN name check `^arn:aws:iam::<platform>:role/bridge-<env>-srv-[0-9a-f]{32}$` (C-11) in the drift job and in the provisioner, and by IAM trust restricted to the broker |
| `PROFILE_PROVISIONER` | CREATE ROLE; owns profile roles and `BRIDGE_SERVING_BASE` (to grant it); INSERT/UPDATE `PROFILE`, `PROFILE_ENTITLEMENT` | CREATE USER; write `TENANT_PRINCIPAL`; MANAGE GRANTS; read serving (not in `TENANT_PRINCIPAL`) | Intra-tenant broadening only: entitlement rows only take effect for users bound to the same tenant in `TENANT_PRINCIPAL` |
| `SECURITY_POLICY_OWNER` (NOLOGIN role) | Owns SECURITY schema, policies, session policy | — | Used only by the reviewed CI deploy identity `SECURITY_DEPLOYER`; policy changes require PR approval by Security |
| AWS runtime identity provisioner (INF-103; RECONCILIATION U-02) | `iam:CreateRole/TagRole/DeleteRole` on `role/bridge-<env>-srv-*` (and `-conn-*`) with the mandatory matching boundary | Attach policies; PassRole | Can create identity-only roles that only the broker may assume |
| Query broker task role | `sts:AssumeRole` on `role/bridge-<env>-srv-*` | Anything else in AWS; PG writes | **All tenants' serving data (RR-01)**; mitigations: minimal code, mTLS ingress from API only, CloudTrail alarm when >20 distinct tenant roles assumed per minute per task, planner emits SELECT only |

Whether several Snowflake users may share one AWS ARN is TO VERIFY LIVE and not required by this design. Snowflake role-count limits: no documented hard cap found (search, 2026-09-28) — **TO VERIFY LIVE** in SEC-005-S15; admission cap 200 active profiles/tenant, platform alarm at 5,000 roles.

### A.7 Pools
Pool key `(env, tenant_user, profile_role)`; profile content is immutable, so no epoch in the key (G-SEC-01). Max 4 connections/pool, idle TTL 300 s, global cap per broker replica (e.g. 200), LRU eviction. Connect with explicit `role=`; after connect assert `CURRENT_USER()`, `CURRENT_ROLE()`, `CURRENT_SECONDARY_ROLES()` equal expected/empty, else discard and alarm. No per-checkout identity query (Snowflake round trip); instead the planner cannot emit `USE`, `ALTER SESSION`, `GRANT`, `CALL`, `EXECUTE`. Session parameters fixed at connect: `STATEMENT_TIMEOUT_IN_SECONDS` 15 (interactive) / 300 (jobs), `QUERY_TAG='bridge_finops:serving'`; per-request correlation goes into a leading SQL comment `/* rid=<uuid> */` containing no user data.

## Appendix B — Scope grammar v1

### B.1 Clause
```json
{
  "org": "*" | ["<org uuid>", ...],
  "account": "*" | ["<account uuid>", ...],
  "group": "*" | {"group_set": "<uuid>", "groups": "*" | ["<group uuid>", ...]},
  "include_shared": false,
  "include_unallocated": false
}
```
All keys required. Empty arrays invalid (`SCOPE_EMPTY_DIMENSION`); a grant with zero clauses is valid and grants nothing. `include_*` must be `true` when `group="*"`.

### B.2 Canonical profile document
```json
{"v":1,"tenant":"<uuid>","sql_text":"SANITIZED","atoms":[
  {"o":"*","a":"<A1>","gs":"<GS>","g":"<FIN>","sh":false,"un":false}
]}
```
Only visibility-relevant inputs: the `analytics.read` scope and data-visibility capabilities (`sql_text.read_full` → `sql_text`). Mutation capabilities never affect the profile. Identity resolution (D-10) happens in the API and is not part of the Snowflake profile.

### B.3 Normalization
1. Validate every referenced ID belongs to the tenant (organizations, accounts, group sets, groups of that set).
2. Expand each clause to atoms: accounts × groups; if account ≠ `*` then `o="*"`; group `"*"` → `gs="*", g="*", sh=true, un=true`; `groups="*"` → `g="*"` with the clause's flags.
3. Hierarchy expansion: a parent group expands to itself + descendants in the currently published hierarchy of that set.
4. Remove atoms subsumed by another (b subsumes a iff for each of o, a, gs, g: b is `*` or equal, and b.sh ≥ a.sh, b.un ≥ a.un).
5. Sort atoms by (o, a, gs, g, sh, un) with `*` first; dedupe; cap 2,000 (`SCOPE_TOO_COMPLEX`).
6. Serialize with RFC 8785 JCS; `profile_hash = "pf1:" + hex(sha256(bytes))`; `atom_hash = sha256(JCS(atom))`.

### B.4 PostgreSQL compilation (objects with scope columns `organization_id, account_id, group_set_id, group_id`)
```sql
EXISTS (
  SELECT 1 FROM unnest($1::uuid[], $2::uuid[], $3::uuid[], $4::uuid[], $5::bool[], $6::bool[])
         AS a(o, acct, gs, g, sh, un)                 -- NULL element = '*'
  WHERE (a.acct IS NULL OR a.acct = obj.account_id)
    AND (a.acct IS NOT NULL OR a.o IS NULL OR a.o = obj.organization_id)
    AND (obj.group_set_id IS NULL AND a.gs IS NULL
         OR obj.group_set_id IS NOT NULL AND (a.gs IS NULL OR a.gs = obj.group_set_id)
            AND (a.g IS NULL OR a.g = obj.group_id))
)
```
Objects scoped at account/org level (group_set_id NULL) require an atom with unrestricted groups — the same rule as `RAP_ACCOUNT_SCOPED`. Multi-scope objects use `scope_atoms` and require all atoms covered.

### B.5 Golden matrix (excerpt of 40 cases; full table in `tests/authz_scope/golden.yaml`)
| # | Viewer scope | Row/object | Expected |
|---|---|---|---|
| 1 | {A1 ∧ Finance} | allocation row A1/Finance | visible |
| 2 | {A1 ∧ Finance} | allocation row A2/Finance | hidden (no OR) |
| 3 | {A1 ∧ Finance} | allocation row A1/Marketing | hidden |
| 4 | {A1 ∧ Finance} | account-grain charge A1 | hidden |
| 5 | {A1 ∧ *} | account-grain charge A1 | visible |
| 6 | {A1 ∧ *} | org-level fee (account NULL) | hidden |
| 7 | {org O ∧ *} | org-level fee of O | visible |
| 8 | {A1 ∧ Finance} ∪ {A2 ∧ Marketing} | A1/Marketing | hidden |
| 9 | {A1 ∧ Finance, sh=false} | A1/`__SHARED__` | hidden |
| 10 | {A1 ∧ Finance, sh=true} | A1/`__SHARED__` | visible |
| 11 | {* ∧ Finance(parent)} with child Payroll | A2/Payroll | visible |
| 12 | {A1 ∧ *} ∪ {A1 ∧ Finance} | normalized atoms | one atom {A1,*} |
| 13 | account A1 transferred O1→O2 | {O1 ∧ *} viewer, A1 row dated after transfer | hidden; {A1 ∧ *} viewer: visible |
| 14 | grant with zero clauses | anything | hidden |
| 15 | clause missing `group` key | — | 422 `SCOPE_DIMENSION_MISSING` |
| 16 | budget over {A1, A2} | viewer {A1 ∧ *} | hidden (object not covered) |

## Appendix C — Capabilities, roles, delegation and separation of duties

### C.1 Legend
✓ default · S = scope-bounded default (within the grant's scope) · O = own objects only · G = grantable extra (not default) · M/C = maker/checker in a four-eyes action · ✗ = never (not grantable to this role). Kind: V = data-visibility (in profile hash), M = mutation (PG check), R = read of control objects (PG check).

### C.2 Matrix (OO Owner, OA Org Admin, FA FinOps Admin, SA Snowflake Admin, TA Team Admin, AN Analyst, VW Viewer, AU Auditor)
| Capability | Kind | OO | OA | FA | SA | TA | AN | VW | AU |
|---|---|---|---|---|---|---|---|---|---|
| analytics.read | V | ✓ | S | S | S | S | S | S | S |
| sql_text.read_sanitized | V | ✓ | G | S | S | S | S | G | G |
| sql_text.read_full (tenant FULL mode only) | V | G | G | G | G | ✗ | G | ✗ | G |
| identity.resolve (plaintext user names) | R | ✓ | ✓ | S | S | G | G | ✗ | G |
| export.data (visible scope, sync limits) | R | ✓ | ✓ | S | S | S | S | G | S |
| export.bulk (async/large) | R | ✓ | G | S | G | ✗ | G | ✗ | G |
| saved_view.manage_own | M | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| saved_view.share / dashboard.manage_shared | M | ✓ | ✓ | S | S | S | S | ✗ | ✗ |
| analysis_job.run | M | ✓ | G | S | S | S | S | ✗ | ✗ |
| tenant.ownership.transfer (step-up, M/C with target owner) | M | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| tenant.settings.manage | M | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| security.policy.manage (MFA, session timeouts) | M | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| sso.manage (draft/test) | M | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| sso.enforce / sso.disable | M | M/C | M | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| member.invite / member.manage | M | ✓ | ✓ | ✗ | ✗ | S (ceiling Analyst) | ✗ | ✗ | ✗ |
| team.manage (people teams) | M | ✓ | ✓ | ✗ | ✗ | O | ✗ | ✗ | ✗ |
| api_client.manage | M | ✓ | ✓ | ✗ | G | ✗ | ✗ | ✗ | ✗ |
| support.grant | M | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| subscription.read | R | ✓ | ✓ | G | ✗ | ✗ | ✗ | ✗ | ✓ |
| subscription.manage (plan change request) | M | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| audit.read | R | ✓ | ✓ | G | G | ✗ | ✗ | ✗ | S |
| audit.export | R | ✓ | G | ✗ | ✗ | ✗ | ✗ | ✗ | S |
| access.review (approve access-relevant group/hierarchy publications) | M | C | C | ✗ | ✗ | ✗ | ✗ | ✗ | G |
| connection.read | R | ✓ | ✓ | S | S | ✗ | ✗ | ✗ | S |
| connection.manage (create/rotate/disable/delete, install scripts) | M | ✓ | ✗ | ✗ | S | ✗ | ✗ | ✗ | ✗ |
| source.configure | M | ✓ | ✗ | ✗ | S | ✗ | ✗ | ✗ | ✗ |
| sync.replay / backfill.request | M | ✓ | ✗ | ✗ | S | ✗ | ✗ | ✗ | ✗ |
| privacy.mode.manage (SANITIZED ↔ METADATA_ONLY) | M | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| privacy.mode.full.enable | M | M/C | M/C | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| privacy.erasure.request | M | M/C | M/C | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| price.manage (rate sheets, approved rates) | M | M/C | ✗ | M/C (S) | ✗ | ✗ | ✗ | ✗ | ✗ |
| tag_rule.edit / allocation_rule.edit / group_set.edit (draft, simulate) | M | ✓ | ✗ | S | ✗ | ✗ | G | ✗ | ✗ |
| rule.approve | M | C | ✗ | C (S) | ✗ | ✗ | ✗ | ✗ | ✗ |
| rule.publish (after approval) | M | ✓ | ✗ | S | ✗ | ✗ | ✗ | ✗ | ✗ |
| budget.manage | M | ✓ | ✗ | S | ✗ | S | G | ✗ | ✗ |
| monitor.manage | M | ✓ | ✗ | S | S | S | G | ✗ | ✗ |
| notification.destination.manage | M | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| report.manage (definitions/schedules to members) | M | ✓ | ✗ | S | S | S | O | ✗ | ✗ |
| report.recipients.external | M | ✓ | ✓ | G | ✗ | ✗ | ✗ | ✗ | ✗ |
| reconciliation.reference.upload (invoice evidence) | M | ✓ | ✗ | S | ✗ | ✗ | ✗ | ✗ | ✗ |
| period.close.request / restatement.request | M | M | ✗ | M (S) | ✗ | ✗ | ✗ | ✗ | ✗ |
| period.close.approve / restatement.approve | M | C | ✗ | C (S) | ✗ | ✗ | ✗ | ✗ | ✗ |
| statement.issue (chargeback) | M | ✓ | ✗ | S | ✗ | ✗ | ✗ | ✗ | ✗ |
| insight.triage / action.manage | M | ✓ | ✗ | S | S | S | O | ✗ | ✗ |
| commercial.payment.record | — | internal finance operator only (not a tenant role), M/C with a second operator | \| | \| | \| \| |

### C.3 Delegation rule
An actor may create/modify a grant only if: (1) actor holds `member.manage` over a scope that subsumes the target grant's scope (SEC-101 `subsumes`); (2) every default and extra capability of the target role ⊆ actor's own capability set, excluding owner-only capabilities (`tenant.ownership.transfer`, `subscription.manage`, `sso.enforce` checker); (3) Team Admin may assign only Viewer/Analyst; (4) nobody edits their own grants; (5) removing/demoting the last ACTIVE Owner is refused (`LAST_OWNER`), serialized by `SELECT … FOR UPDATE` on all Owner memberships of the tenant.

### C.4 Four-eyes and step-up policy (defaults)
| Action | Four-eyes | Self-approval if single eligible approver | Step-up (≤10 min) | Approval binds |
|---|---|---|---|---|
| period.close, restatement | REQUIRED | No | Yes (both) | period_id, revision, sha256(close manifest: charge/publication/reference/rule/rate/check versions) |
| statement.issue | REQUIRED (approval of close covers it if same manifest) | No | Yes | statement_id, manifest hash |
| price.manage (new approved rate/override) | REQUIRED | Yes, flagged | Yes | rate_table_id, revision, content hash |
| rule.publish (tag/allocation/group set) | REQUIRED | Yes, flagged | No | ruleset_id, revision, simulation_id, content hash |
| access-relevant group/hierarchy publication | REQUIRED with `access.review` | No | Yes | group_set version hash |
| privacy.mode.full.enable, privacy.erasure.request | REQUIRED | No | Yes | tenant setting revision |
| sso.enforce / sso.disable | REQUIRED | Owner may self-approve with step-up | Yes | idp_id, metadata hash |
| tenant.ownership.transfer | Target owner must accept | n/a | Yes | membership ids |
| support.grant | Customer approval is the check | n/a | Yes | grant row |
| member grants of Owner/OA/FA roles | No (audited) | n/a | Yes | — |

`governance.approvals`: `tenant_id, id, action, object_type, object_id, object_revision, content_sha256, requested_by, requested_at, reason, state, decided_by, decided_at, decision_reason, self_approved bool, expires_at (requested_at + 7 d), executed_at, revision`; unique `(tenant_id, action, object_id, object_revision) WHERE state IN ('REQUESTED','APPROVED')`.

## Appendix D — Session and BFF design

### D.1 Flow
Browser → `GET /v1/auth/login` → Cognito managed login (or discovered IdP) → `GET /v1/auth/callback` → session row + `__Host-bridge_sid` → SPA calls `GET /v1/auth/session` (returns subject, memberships list, active tenant, capabilities summary, `csrf_token`, `authz_digest`) → all API calls with cookie + `X-CSRF-Token` on mutations. CloudFront behaviour `/api/*` → ALB uses managed `CachingDisabled` and forwards all cookies and `Origin`; the SPA and API share one host so `__Host-` cookies work (INF-006 must not split API onto another domain).

### D.2 Tables
`identity.sessions`: `id uuid PK, sid_hash bytea UNIQUE, subject_id, active_tenant_id NULL, idp_id NULL, amr text[], auth_time timestamptz, created_at, last_seen_at, idle_timeout_s int, absolute_expires_at, refresh_ciphertext bytea, refresh_key_ref text, refresh_expires_at, access_expires_at, last_refresh_at, user_agent_hash bytea, ip_prefix inet, revoked_at, revoke_reason text`. Subject-scoped; no tenant RLS; accessed only via definer functions. `identity.auth_transactions`: `state_hash PK, nonce_hash, pkce_verifier_ciphertext, return_to, idp_hint, purpose ('login'|'test'|'step_up'), created_at, expires_at, consumed_at`.

### D.3 Endpoints
`GET /v1/auth/login`, `GET /v1/auth/callback`, `POST /v1/auth/discover`, `GET /v1/auth/session`, `POST /v1/auth/logout`, `POST /v1/auth/sessions/revoke-all`, `POST /v1/auth/switch-tenant`, `POST /v1/auth/step-up`, `GET /v1/me/sessions`, `DELETE /v1/me/sessions/{id}`. Refresh is internal (no public `POST /v1/auth/refresh` needed; challenges SEC-002's interface list — the browser never refreshes tokens).

### D.4 Rules
Cookie `__Host-bridge_sid`, Secure, HttpOnly, SameSite=Lax (Strict breaks first navigation from email links), Path=/. New sid on login, tenant switch and step-up. Idle default 30 min; absolute 12 h; tenant policy bounded. CSRF = synchronizer token derived by HMAC from the session (no extra state; not a plain double-submit cookie, which is weaker against subdomain cookie injection). Users in several tenants: one subject, many memberships; one active tenant per session; switching purges browser caches (`Clear-Site-Data: "cache"` is best-effort; the SPA also clears its query cache and aborts in-flight requests).

## Appendix E — PostgreSQL RLS implementation standard (mechanism in CTL-101)

E.1 Roles: `bridge_owner` NOLOGIN (owns everything); `bridge_migrator` LOGIN member of owner (migration task only); `bridge_api`, `bridge_worker`, `bridge_dispatcher`, `bridge_broker`, `bridge_audit_exporter`, `bridge_retention`, `bridge_ops_ro` LOGIN, all `NOSUPERUSER NOBYPASSRLS NOCREATEROLE`, none owns objects; `rds_iam` auth. Explicit per-table grants in migrations (no blanket default privileges) so `audit.events` is INSERT-only.

E.2 Context: `SELECT set_config('app.tenant_id', $1, true), set_config('app.subject_id', $2, true)` as the first statement of every transaction; `app.current_tenant()` = `NULLIF(current_setting('app.tenant_id', true), '')::uuid` (STABLE SQL function, inlined). Malformed value raises → 500 `AUTHZ_CONTEXT_INVALID`.

E.3 Policy templates: (a) tenant tables `USING/WITH CHECK (tenant_id = app.current_tenant())` TO `bridge_api, bridge_worker`; (b) subject-scoped global tables (`subjects`, `tenants`, `memberships`) add `OR subject_id = app.current_subject()` for list-my-tenants; (c) queue tables (`platform.outbox`, `sync.*_jobs`, `report.report_jobs`) add role-targeted `FOR SELECT, UPDATE TO bridge_dispatcher|bridge_worker USING (true)` — allowlisted in lint; (d) `audit.events` INSERT policy tenant-checked, SELECT for `bridge_api` tenant-checked, SELECT `TO bridge_audit_exporter USING (true)`; (e) sessions/auth transactions: no grants; definer functions only.

E.4 Keys: every tenant table `UNIQUE (tenant_id, id)`; FKs `(tenant_id, parent_id) REFERENCES parent (tenant_id, id)`; no global unique index on tenant data except where designed (e.g. `identity_providers.entity_id`, answered with a non-enumerating 409).

E.5 Leak guard: the context statement also returns `current_setting('app.tenant_id', true)` *before* setting; non-empty prior value means a session-level set leaked → log `SECURITY_CONTEXT_LEAK`, invalidate the connection. Engines with `isolation_level="AUTOCOMMIT"` are banned by lint (with autocommit, `set_config(…, true)` lasts one statement, so reads return zero rows — fail closed, proven by test).

E.6 Lint (CI + nightly prod read-only): every table in tenant schemas with a `tenant_id` column has `relrowsecurity AND relforcerowsecurity` and ≥1 policy; no runtime role owns a table or has `rolbypassrls`; `USING (true)` only on allowlisted tables; every FK on tenant tables includes `tenant_id`.

E.7 Mandatory tests per table (generated): with seeded A and B rows, (1) no context → `SELECT count(*)` = 0, `INSERT` → 42501; (2) context A → B rows invisible; `UPDATE … WHERE id=<B>` affects 0 rows; (3) FK to B parent → 23503.

## Appendix F — Revocation mechanism
- Per request: `identity.resolve_session(sid_hash)` returns session validity, active membership status, `permission_epoch`, `profile_id/hash/status`, tenant status and `authz_epoch` in one indexed round trip (<1 ms server time; ~200 qps at 200 req/s — negligible for Aurora). Nothing authorization-related is cached across requests except the per-epoch normalized scope (keyed by epoch, so it cannot be stale).
- Events (`authz.*` outbox) only accelerate: close broker pools, cancel running statements, notify browsers. Losing them does not extend access.
- Running Snowflake statements: broker rechecks every 10 s → cancel (bound ≤10 s + cancel latency).
- Cursors, async jobs, report artifacts bind `(subject_id, membership_id, permission_epoch, profile_hash)`; delivery requires current profile ⊇ bound profile (or equal epoch for cursors).
- Presigned S3 URLs: issued only by an authorizing endpoint, TTL 30 s (residual RR-02).
- Browser: responses tagged with tenant and authz digest; mismatch → discard; 403 `AUTHZ_REVOKED` → purge caches.
- Measurement: SEC-006-S12 with the outbox dispatcher disabled and Redis down.

## Appendix G — Privacy

### G.1 Field treatment (SANITIZED default)
| Field | Treatment |
|---|---|
| QUERY_TEXT | AST tier → lexical tier → NULL (METADATA_ONLY for that row); comments stripped; cached by parameterized hash |
| Comment/QUERY_TAG metadata | allowlisted keys/regex; other values → HMAC `t1_` pseudonyms; ≤4 KB input |
| USER_NAME, emails in tags | HMAC pseudonyms (G.2) |
| ROLE_NAME, object names | retained (SANITIZED); dropped in METADATA_ONLY except IDs |
| Error messages from Snowflake | `(error_code, sql_state, class)`; message only in FULL |
| QUERY_HASH / QUERY_PARAMETERIZED_HASH | preserved unchanged in all modes |

### G.2 Pseudonymization (D-10 refined)
Per-tenant key (KMS envelope, encryption context `tenant_id`); `u1_`/`e1_`/`t1_` prefixes denote scheme version. Dictionary `privacy.identity_dictionary(tenant_id, pseudonym, kind, display_name, email_norm NULL, first_seen, last_seen, source_account_id)` in PostgreSQL only; erasure tombstones `(tenant_id, pseudonym, erased_at, request_id)` are kind SUBJECT in the OPS-104 tombstone registry with its S3 mirror outside restore scope, never a PostgreSQL-only table (RECONCILIATION U-11, C-19). Resolution in the API after Snowflake returns rows. Erasure = delete dictionary row + tombstone + tenant authz_epoch bump; residuals: Aurora PITR (35 days), Redis TTL (≤30 min), already-delivered reports/exports (documented). Limitation: anyone holding the tenant key can recompute a candidate name's pseudonym (linkability) — "crypto-shredding-lite"; tenant offboarding deletes the key.

## Appendix H — Audit
H.1 Event fields: `event_id, tenant_id NULL (platform events), occurred_at (UTC, µs), actor_type (MEMBER|SUPPORT|SERVICE|OPERATOR|ANONYMOUS), actor_subject_id, actor_service, action, object_type, object_id, object_version, outcome (ALLOWED|DENIED|FAILED), reason_code, request_id, session_id_hash, ip, user_agent (≤256), before_redacted jsonb, after_redacted jsonb, approval_id`. Action names `<domain>.<object>.<verb>`, e.g. `auth.login.succeeded`, `auth.session.revoked`, `member.grant.updated`, `authz.profile.activated`, `connection.credentials.rotated`, `sync.replay.requested`, `rule.ruleset.published`, `price.rate.approved`, `period.close.executed`, `statement.issued`, `export.bulk.downloaded`, `privacy.mode.changed`, `support.access.used`, `api_client.secret.rotated`, `operator.recovery.executed`, `authz.request.denied`.
H.2 Export: per-tenant chain `digest_n = sha256(prev_digest || sha256(batch_bytes) || manifest_fields)`; manifest signed with KMS asymmetric key; bucket in log-archive account, Object Lock GOVERNANCE (not COMPLIANCE, per ADR-009), bypass only by break-glass role with MFA + alarm.
H.3 Access: `audit.read` scope-bounded (tenant-level events visible to OO/OA/AU; object events visible if object scope ⊆ reader scope); support and operator actions always visible to the tenant.
H.4 Retention/erasure: PG 365 days; S3 365 days (lock) then lifecycle delete; user erasure does not rewrite audit (legal basis: Q7); exported IP truncated + full value encrypted under per-tenant data key; tenant offboarding deletes that key.

## Appendix I — Attack catalog (ATK-01…ATK-36)
| ID | Attack | Expected | Owner |
|---|---|---|---|
| ATK-01 | Foreign tenant UUID in path (`GET /v1/budgets/{B-id}` as A) | 404 identical to nonexistent | SEC-004/SEC-008 |
| ATK-02 | Foreign account/group ID in analytics filter body | 422 `SCOPE_REFERENCE_INVALID` (non-enumerating) or empty authorized result | API-002 |
| ATK-03 | Drop tenant/scope filter (planner bug simulation) | Snowflake policy returns only own rows | SEC-005 |
| ATK-04 | Replay cursor after permission change | 409 `SCOPE_CHANGED` (RECONCILIATION C-07) | SEC-006 |
| ATK-05 | Use another user's cursor | 400 `CURSOR_INVALID` | SEC-006 |
| ATK-06 | Send `X-Tenant-Id`/JSON tenant of B | ignored; A context only | SEC-004 |
| ATK-07 | Cache poisoning via crafted filter hash collision | digest mismatch → miss | CTL-006 |
| ATK-08 | Read async job result after revoke | 403 `RESULT_SCOPE_REVOKED` | SEC-006 |
| ATK-09 | Download report link after revoke | 403 | SEC-006/RPT-005 |
| ATK-10 | Cross-prefix S3 read/write with tenant A task role | AccessDenied | INF-003/CON-001 |
| ATK-11 | Direct SQL `SELECT *` without WHERE as tenant B user | zero A rows | SEC-005 |
| ATK-12 | `USE SECONDARY ROLES ALL` | session-policy error | SEC-005 |
| ATK-13 | `USE ROLE` of another tenant's profile | not granted | SEC-005 |
| ATK-14 | Same SQL under two profiles (result cache) | each profile's own oracle | SEC-005 |
| ATK-15 | Team profile reads account-grain total | zero rows | SEC-005 |
| ATK-16 | Team profile requests share-of-account metric | null + `DENOMINATOR_OUTSIDE_SCOPE` | API-001/SEC-005 |
| ATK-17 | Autocomplete/dimension options for hidden groups/accounts | not listed | API-002 |
| ATK-18 | CSRF: cross-site POST without token | 403 `AUTH_CSRF_INVALID` | SEC-002 |
| ATK-19 | Session fixation with pre-set cookie | replaced at login | SEC-002 |
| ATK-20 | Open redirect variants in `return_to` | normalized to `/` | SEC-002 |
| ATK-21 | JWT confusion (alg none, HS256, ID-as-access, wrong aud) | rejected | SEC-002 |
| ATK-22 | Password login into SSO-enforced tenant | denied (except break-glass, alarmed) | SEC-003 |
| ATK-23 | IdP bound to A used to enter B | `AUTH_IDP_TENANT_MISMATCH` | SEC-003 |
| ATK-24 | Invitation token replay/forwarding to other email | 403/410, single use | CTL-003 |
| ATK-25 | Grant beyond delegation | 403 `DELEGATION_EXCEEDED` | SEC-004 |
| ATK-26 | Concurrent removal of the last two owners | one succeeds | SEC-004 |
| ATK-27 | CSV formula injection in exported names | cells prefixed/escaped | RPT/API |
| ATK-28 | Webhook destination to private IP/metadata | rejected | GOV-006 |
| ATK-29 | SQL injection via filters/sort/set_config values | bound/allowlisted | API-002/SEC-004 |
| ATK-30 | Pooled PG connection context bleed | zero foreign rows | SEC-004 |
| ATK-31 | Timing oracle foreign vs nonexistent 404 | p50 within ±10 % | SEC-008 |
| ATK-32 | Audit record tamper (edit/delete/reorder) | verifier fails | SEC-008 |
| ATK-33 | Sentinel secret in SQL/tag/error | absent from all stores/logs | SEC-007 |
| ATK-34 | Support grant self-approval / after expiry | denied | SEC-104 |
| ATK-35 | Approval reuse after object edit | 409 `APPROVAL_INVALID` | SEC-102 |
| ATK-36 | Provisioner writes `TENANT_PRINCIPAL` | permission error | SEC-105 |

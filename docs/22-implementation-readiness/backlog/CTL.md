# CTL — Implementation-readiness review and production backlog

Canonical contract: [control-plane.md](../../03-control-plane/control-plane.md). Tasks reviewed: [CTL-001](../../tasks/CTL/CTL-001.md), [CTL-002](../../tasks/CTL/CTL-002.md), [CTL-003](../../tasks/CTL/CTL-003.md), [CTL-004](../../tasks/CTL/CTL-004.md), [CTL-005](../../tasks/CTL/CTL-005.md), [CTL-006](../../tasks/CTL/CTL-006.md), [CTL-007](../../tasks/CTL/CTL-007.md). Also read: ADR-001, ADR-007, ADR-008, ADR-012, PRD §56–§66, [orchestration.md](../../06-dagster/orchestration.md) (concurrency budgets), [launch.md](../../20-launch/launch.md), [RUNBOOKS.md](../../16-observability/RUNBOOKS.md) RB-10/RB-12/RB-14, [RESEARCH_REGISTER.md](../../00-project/RESEARCH_REGISTER.md) R32/R33/R36, related task files ING-007, ORC-003, GOV-007, LCH-001, INF-004. Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

Companion file: [SEC.md](SEC.md) (RLS standard Appendix E, scope grammar Appendix B, revocation Appendix F, capability matrix Appendix C). This file defines the new **CTL-101 Control DB kernel** that SEC-004, SEC-006 and SEC-008 depend on.

## 1. Verdict

The control-plane contract names the right mechanisms (composite tenant keys, FORCE RLS, transactional outbox, fenced leases, idempotency keys, optimistic concurrency, versioned cache keys) but specifies none of them physically: there is no DDL for any of the ten schemas, no outbox claim algorithm or ordering rule, no idempotency semantics under concurrency, no connection arithmetic, no migration protocol for mixed worker generations, and no Redis value/degradation contract with numbers. The graph also hides a cycle (revocation/audit need the outbox, which is built after them). None of this is exotic, but each item is a classic source of duplicate side effects, cross-tenant bugs or failover outages if improvised per task. Author first: CTL-101 (kernel DDL + unit of work + outbox/idempotency/audit tables), the outbox/lease algorithms (Appendix A), the connection budget manifest (Appendix B) and the expand/contract protocol (Appendix C). Realistic effort ≈350–540 senior hours for R1.

## 2. Findings

### G-CTL-01 · No physical schema exists for any control table
Severity: BLOCKER · Type: GAP
Evidence: `control-plane.md` — "| identity | subjects, tenants, memberships, teams, team_members, role_grants, sessions |" (table names only, ten schemas); CTL-001 data model — "UUID internal IDs; organization membership history valid_from/to; account locator+region/source identity retained".
Why it matters: every downstream domain (CON, ING, GOV, RPT, ALC, LCH) writes to these tables; without agreed columns, keys and state enums, parallel lanes (RELEASE_PLAN §3) produce incompatible migrations and duplicated status vocabularies.
Resolution: each owning task produces reviewed DDL as its first step; CTL owns `platform.*`, `connection.organizations/accounts/*history`, `report.saved_views/shares/dashboards`, `commercial.*`; SEC owns `identity.*` (SEC.md Appendix E, D); all follow the CTL-101 template (tenant_id first, `UNIQUE(tenant_id,id)`, composite FKs, `revision bigint`, `created_at/updated_at/updated_by`, text + CHECK instead of PG enums, RLS + grants in the same migration). ERD published at `docs/data/control-erd.md`.
Affects: CTL-001, CTL-003, CTL-007, CTL-101 and consumers.

### G-CTL-02 · Hidden dependency cycle through the outbox
Severity: HIGH · Type: CONTRADICTION (dependency graph)
Evidence: SEC-006 MT1 "emit outbox in the same membership transaction"; SEC-008 "Audit emit within transaction/outbox"; graph CTL-004 ← CTL-003 ← SEC-008 ← SEC-006 (see SEC.md G-SEC-11).
Why it matters: either two outbox implementations appear or security tasks block on CTL-004, which cannot start.
Resolution: new **CTL-101** creates `platform.outbox`, `platform.idempotency_requests`, `audit.events`, `emit_event()`, `emit_audit()`, the migration runner and `tenant_transaction()` right after INF-004. CTL-004 keeps the dispatcher and leases. Edges: CTL-003 `−SEC-008 +CTL-101`; CTL-004 `−CTL-003 +CTL-101`; SEC-004 `+CTL-101`.
Affects: CTL-003, CTL-004, SEC-004, SEC-006, SEC-008.

### G-CTL-03 · Outbox dispatcher semantics are undefined (ordering, poison, transport, retention)
Severity: HIGH · Type: GAP
Evidence: `control-plane.md` — "Outbox dispatcher claims with FOR UPDATE SKIP LOCKED, fenced lease and attempt schedule; side effect identity is event_id"; CTL-004 MT2 "poison classification and dead-letter workflow".
Why it matters: plain `SKIP LOCKED` batches let two dispatchers publish events of the same aggregate out of order (config version 7 applied before 6; revoke processed before grant); a poison event either blocks the whole table (if ordered globally) or silently loses ordering; "event_id as side-effect identity" is meaningless for SQS standard queues without consumer deduplication.
Resolution: Appendix A.1–A.2: per-aggregate ordering via `aggregate_seq` and a head-of-line `NOT EXISTS` predicate (only for `ordering='AGGREGATE'` event types); DEAD predecessor blocks only its own aggregate and pages; lease token from a sequence, DB-time expiry; ordered flows published to SQS **FIFO** (`MessageGroupId`=aggregate, `MessageDeduplicationId`=event_id), unordered to standard queues with consumer-side `platform.consumed_events(consumer, event_id)` dedup; backoff `min(5 s·2^n, 1 h) ±20 %`, max 12 attempts; DONE rows deleted after 7 days.
Affects: CTL-004, GOV-007, ING-002, ING-007, ORC-003, SEC-105, CTL-005.

### G-CTL-04 · Idempotency and optimistic concurrency semantics are incomplete; 409 for stale If-Match contradicts HTTP
Severity: HIGH · Type: AMBIGUITY / CONTRADICTION (LOW)
Evidence: `control-plane.md` — "unique (tenant_id, route, key) stores request hash and result reference. Same key/different body returns 409. PATCH requires revision/If-Match; stale revision returns 409."
Why it matters: (a) keying without the subject lets user X's key collide with user Y's in the same tenant (a 409 that reveals another user's request); (b) storing the record outside the business transaction produces "key recorded, mutation lost" or the reverse after a crash; (c) concurrent duplicates race without a defined winner; (d) RFC 9110 defines a failed `If-Match` as **412 Precondition Failed** and a missing required precondition as **428**; generated clients and CDNs expect that.
Resolution: Appendix A.3/A.5: key `(tenant_id, principal_id, route_key, idem_key)` (principal = subject or API client), written in the same transaction as the mutation, concurrent duplicate blocks on the PK and then replays the stored 2xx response with `Idempotent-Replayed: true`; different body hash → 409 `IDEMPOTENCY_KEY_REUSED`; TTL 24 h; required (400) on resource-creating POSTs and job submissions. Challenges `control-plane.md`: `If-Match` mismatch → 412 `STALE_REVISION`, missing → 428 `PRECONDITION_REQUIRED` (if the owner keeps 409, document it in the error catalog — never both).
Affects: CTL-101, CTL-003, CTL-007, API-004, all mutating routes.

### G-CTL-05 · Connection budget is a principle, not a calculation; the multipliers that break it are missing
Severity: HIGH · Type: GAP / VENDOR-FACT
Evidence: `control-plane.md` — "Define per-component maximum connections × maximum replicas, reserve >=30% … verify against actual Aurora limits"; INF-004 "per-component pool budget <=70% tested connection limit". Aurora PostgreSQL default `max_connections = LEAST({DBInstanceClassMemory/9531392}, 5000)` — VERIFIED (search snippet of AWS re:Post knowledge-center "aurora-postgresql-max-connections", 2026-09-28); ≈1,716 on db.r6g.large per a secondary source — confirm live with `SHOW max_connections`.
Why it matters: the usual overruns come from factors the contract omits — processes per container (uvicorn/gunicorn workers each own a pool), `max_overflow`, Dagster run workers (each run process opens its own metadata DB connections), per-account extraction tasks (D-07) and the old + new task sets running together during a rolling deploy (up to 2× replicas).
Resolution: Appendix B manifest `infra/db/pool-budget.yaml` with the formula `Σ replicas_max × deploy_surge × processes × (pool_size + max_overflow)` per cluster ≤ 0.70 × measured `max_connections`, CI check against Terraform autoscaling maxima, and the initial R1 allocation (≈308 steady / ≈530 during surge vs 1,201 usable on r6g.large). Dagster shares the cluster in R1 with its own user and budget; move it to a separate cluster if its measured write IOPS exceed 30 % of cluster capacity.
Affects: CTL-002, INF-004, ORC-001, ING-003.

### G-CTL-06 · Expand/contract with multiple worker generations has no enforcement; Alembic defaults break online DDL
Severity: HIGH · Type: GAP
Evidence: `control-plane.md` — "destructive changes wait until all old workers are drained"; CTL-002 MT1 "advisory deployment lock and resumable batches"; failure "old image with new schema".
Why it matters: nobody can currently tell whether an old worker generation is still running (Fargate tasks from a previous deploy, long ECS run tasks, Dagster run workers pinned to an old image); `CREATE INDEX CONCURRENTLY` cannot run inside a transaction block, which is Alembic's default; adding `NOT NULL`/FK on large tables takes long `ACCESS EXCLUSIVE` locks.
Resolution: Appendix C: `platform.component_heartbeats` generation registry (every process reports `schema_rev_min/max` every 30 s); the migration runner refuses a contract step while any heartbeat within 15 min reports `schema_rev_max` below the contract's requirement; applications refuse to start on a schema older than their minimum; concurrent index builds inside `autocommit_block()`; `NOT VALID` + `VALIDATE CONSTRAINT` patterns; `lock_timeout=3s` with retries; outbox `event_version` N and N−1 supported by consumers.
Affects: CTL-002, CTL-101, ORC-001, all migrations.

### G-CTL-07 · Redis key contract leaves `profile` and `permission_epoch` undefined and has no degradation numbers
Severity: HIGH · Type: AMBIGUITY
Evidence: `control-plane.md` — "bridge:v1:{environment}:{tenant}:{profile}:{permission_epoch}:…"; "Use single-flight best-effort locks … bounded concurrency"; RB-12 "Fail open only to authorized database reads under concurrency caps"; PRD §64 lists "session-adjacent state … distributed locks" in Redis; CTL-006 MT1 "separate … timegrain" while the key has no grain field.
Why it matters: if `permission_epoch` is the member's epoch, identical profiles never share cache entries; if `profile` is a mutable profile ID, a changed profile could read old entries. Without numeric caps, a Redis outage becomes a Snowflake stampede (100 identical misses → 100 warehouse queries). Storing sessions or ownership locks in Redis contradicts ADR-008 and SEC's durable session model.
Resolution: Appendix D: `{profile}` = first 16 hex of the immutable `profile_hash` (full hash checked in the value envelope), `{permission_epoch}` = `tenants.authz_epoch` (data-visibility epoch, SEC.md Appendix F), grain/period inside the request digest; envelope with full digest, ≤1 MB; single-flight Redis lock + in-process future map; caps 4 concurrent computes per tenant per broker replica and 32 global, reduced to 2/16 when the cache circuit is open, excess → 503 `ANALYTICS_BUSY` `Retry-After: 2`; no session truth, no ownership locks, no permission cache in Redis.
Affects: CTL-006, API-002, API-003, SEC-006.

### G-CTL-08 · Commercial state vocabulary contradicts launch.md and overlaps LCH-001
Severity: MEDIUM · Type: CONTRADICTION
Evidence: CTL-007 MT2 — "subscription states TRIAL/ACTIVE/PAST_DUE/SUSPENDED/CANCELLED"; `launch.md` — "State model: TRIAL → ACTIVE_PENDING_PAYMENT → ACTIVE_PAID; PAST_DUE/SUSPENDED/CANCELLED"; LCH-001 — "Implement audited manual invoice/payment evidence entry with duplicate reference guards and correction review".
Why it matters: two enums for the same state; ADR-012 requires distinguishing a signed-but-unpaid contract (ACTIVE_PENDING_PAYMENT) from ACTIVE_PAID for M12 evidence; CTL-007 and LCH-001 would both build payment entry.
Resolution: `launch.md` enum is canonical (Appendix F). CTL-007 owns schema, state machine, entitlement lookup and admission hooks (plan-agnostic quotas per D-17); LCH-001 owns plan content, grace/export numbers and the finance-operator workflow using CTL-102's internal console. Payment correction requires a second finance operator (maker-checker).
Affects: CTL-007, LCH-001, CTL-102.

### G-CTL-09 · Invitation flow conflicts with "no tokens in URLs" and lacks binding rules
Severity: MEDIUM · Type: GAP / CONTRADICTION
Evidence: `security.md` — "Never store tokens in localStorage or URL parameters"; CTL-003 — "one-time token, expiry and authenticated subject binding"; failures "invite forwarding; duplicate email".
Why it matters: an invitation token in a query string lands in CloudFront/ALB logs and `Referer` headers; without email binding a forwarded link grants membership to whoever clicks first; if the inviter is demoted before acceptance, the invitation still carries their old delegation.
Resolution: Appendix E: token (256-bit) in the URL **fragment** (`/invite#t=…`, never sent to servers), page posts it after login and strips it with `history.replaceState`; `Referrer-Policy: no-referrer`; acceptance requires verified email equality (NFKC, case-folded; no plus-address folding) or, for SSO-enforced tenants, a session from the tenant IdP; inviter's delegation re-validated at acceptance; same error for unknown/expired/revoked tokens; resend rotates the token.
Affects: CTL-003, SEC-003.

### G-CTL-10 · Snowflake account identity, rename and cross-tenant duplicates are unspecified
Severity: MEDIUM · Type: AMBIGUITY
Evidence: CTL-001 — "account locator+region/source identity retained"; failures "Duplicate discovery; account disappears temporarily; renamed organization; stale transfer event". Snowflake accounts are addressable both by `orgname-account_name` and by locator+region.
Why it matters: using the account *name* as natural key breaks on rename; deleting an account on one missed discovery breaks history; the same Snowflake account connected by two tenants (reseller + end customer) doubles extraction cost and, if detected naively, reveals to tenant B that tenant A is a customer.
Resolution: natural key `(tenant_id, account_locator, region, cloud)` with `source_identity_hash = sha256(locator|region|cloud)`; names in effective-dated history tables; disappearance → `MISSING` after 3 consecutive discovery misses, never delete; org membership `valid_from/valid_to` half-open with a GiST exclusion constraint; stale transfer events (older `observed_at`) ignored. Cross-tenant duplicate check runs only **after** the requester proves control (WIF install verified) and applies the owner's policy (Q1).
Affects: CTL-001, CON-004, CON-005.

### G-CTL-11 · Config publication (ADR-007/D-04) lacks the physical contract
Severity: MEDIUM · Type: GAP
Evidence: CTL-005 — "Outbox event→immutable Parquet/manifest→central config acceptance"; D-04 — direct idempotent INSERT by a `config-publisher` identity; failure "partial export; version arrives out of order".
Why it matters: Snowflake does not enforce UNIQUE constraints, so two publisher attempts can insert duplicate or conflicting rows for the same version; without a commit marker dbt can read a half-inserted version; user-name predicates must be pseudonymized (D-10) before they leave PG.
Resolution: Appendix G: insert-only `CONFIG.*` tables; rows then a header row in one Snowflake transaction (header = commit marker with row_count + content hash); single publisher per `(tenant, kind)` via PG fenced lease; existing header with equal hash → no-op, different hash → `CONFIG_VERSION_CONFLICT` page; dbt reads only header-complete versions; S3 archive copy; drafts go to `SIMULATION_INPUT` only.
Affects: CTL-005, DBT-00x, ALC-003, SEC-103.

### G-CTL-12 · Fencing tokens protect nothing unless every protected write checks them
Severity: MEDIUM · Type: GAP
Evidence: `control-plane.md` — "Worker leases use DB time, fencing token and expiry; Redis never decides ownership"; ING-007 — "accept(batch_id,fencing_token)"; no generic `assert_fence` contract or table.
Why it matters: a paused worker (GC, network partition) resumes after lease expiry and writes a checkpoint or publishes a manifest; unless the write predicate includes the token, the fence is decorative.
Resolution: Appendix A.4 generic `platform.leases` + `platform.assert_fence(kind, key, token)` that takes `FOR SHARE` on the lease row inside the protected transaction (a new acquirer waits until the protected transaction ends) and raises SQLSTATE `BL001 LEASE_LOST`; external artifacts (manifests, config rows) carry the token and acceptance compares it with the attempt's recorded token.
Affects: CTL-004, ING-007, ING-008, ORC-003, CTL-005.

### G-CTL-13 · Tenant lifecycle states and operator provisioning are missing
Severity: MEDIUM · Type: GAP
Evidence: RB-14 offboarding "Pause schedules/extraction; revoke WIF and SaaS access … ordered deletion … retain deletion tombstone"; RB-10 "reapply deletion tombstones"; ADR-012 suspension; `tenants` has no status model anywhere.
Why it matters: suspension, offboarding and restore-without-resurrection all key off a tenant state that no task defines; SEC-105 needs a trigger to create the tenant principal.
Resolution: new CTL-102 with states PROVISIONING → ACTIVE ⇄ SUSPENDED → OFFBOARDING → DELETED (tombstone), internal console with operator identity (IAM Identity Center, hardware MFA), and restore-time tombstone enforcement.
Affects: CTL-102 (new), SEC-104, SEC-105, OPS-005, OPS-006.

### G-CTL-14 · Saved views/dashboards sharing and "no fact mirror" need enforceable rules
Severity: MEDIUM · Type: GAP
Evidence: CTL-007 — "sharing never grants additional data access"; "configuration contains no cost/query fact mirror"; failures "Stale metric ID; deleted owner; … incompatible dashboard schema".
Why it matters: a shared view whose filters mention an account the recipient cannot see must neither leak the account's name nor fail the whole dashboard; free-form JSON specs can smuggle result arrays into PG.
Resolution: specs validated by JSON Schema against the registry version with size caps (16 KB per spec, 30 widgets) and no result-value fields; rendering always under the recipient's profile; out-of-scope filter values produce widget state `PARTIAL_SCOPE` without echoing names; deleted metrics → `UNAVAILABLE_METRIC` with migration hint; removed owner → ownership to tenant admins.
Affects: CTL-007, UX-004, API-001.

### G-CTL-15 · Research register maps RDS Proxy to the wrong task
Severity: LOW · Type: CONTRADICTION
Evidence: `RESEARCH_REGISTER.md` R32 — "[CTL-005]: Start with bounded direct pools; introduce Proxy only after SET LOCAL/RLS and failover tests" (CTL-005 is config publication).
Resolution: treat as CTL-002 scope (pool strategy); R1 uses direct pools; RDS Proxy only after a pinning test with `set_config(…, true)` inside transactions (TO VERIFY LIVE).
Affects: CTL-002.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by (task/micro-task) |
|---|---|---|
| Kernel DDL | `platform.outbox`, `platform.idempotency_requests`, `platform.leases`, `platform.consumed_events`, `platform.component_heartbeats`, `platform.backfill_jobs`, `audit.events` (minimal) exactly as Appendix A/C | CTL-101-S05…S07, CTL-002-S02 |
| "Add a tenant table" template | Migration template with composite keys, RLS ENABLE+FORCE, policies, explicit grants, generated isolation tests | CTL-101-S11 |
| Event catalog | `schemas/events/<event_type>.v<n>.json` (IDs/versions only, ≤64 KB), routing table event_type → transport/queue/ordering | CTL-004-S01 |
| Error catalog | Codes, HTTP status, retryable flag, message template; includes `STALE_REVISION`(412), `PRECONDITION_REQUIRED`(428), `IDEMPOTENCY_KEY_REUSED`(409), `IDEMPOTENCY_KEY_REQUIRED`(400), `NOT_FOUND`(404, non-enumerating), `ANALYTICS_BUSY`(503) | CTL-003-S03 |
| Control OpenAPI | Tenants/members/grants/invitations/teams/organizations/accounts/saved views/dashboards/config publications paths (entitlements: LCH-101, RECONCILIATION U-08) with If-Match/Idempotency-Key semantics | CTL-003-S01, CTL-001-S09, CTL-007-S03 |
| Pool budget manifest | `infra/db/pool-budget.yaml` per component (replicas_max, surge factor, processes, pool_size, max_overflow, role, DB) + CI rule | CTL-002-S08 |
| Expand/contract protocol | Appendix C rules + migration linter configuration | CTL-002-S01 |
| Redis key/value contract | Appendix D key families, envelope schema, TTL classes, caps, ACL users | CTL-006-S01 |
| Config snapshot contract | Snowflake `CONFIG.*` DDL, header/commit-marker rules, S3 archive key format, PG publication states | CTL-005-S01/S02 |
| Tenant and subscription state machines | CTL-102 tenant transitions, guards and effects matrix; subscription machine per `LCH.md` G-LCH-03 (Appendix F superseded) | CTL-102-S01 (tenant), LCH-001-S02 (subscription) (RECONCILIATION C-08) |
| Control ERD | `docs/data/control-erd.md` generated from migrations | CTL-001-S10 |

## 4. Revised production backlog

Ordering note: CTL-101 (new, §5) precedes everything in this section; it is listed in §5 only because the format reserves §4 for existing IDs.

### CTL-001 — Extend tenant, organization, account and team schemas
Release: R1 · Estimate: 30–46 h · Risk: M · Decisions: D-02, D-20 · Closes: G-CTL-01 (connection schema), G-CTL-10
Dependency changes: `+CTL-101` (migration runner, template, `tenant_transaction`); keep SEC-004.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CTL-001-S01 | Specify DDL: `connection.organizations` (tenant_id, id, snowflake_org_name, display_name, status, revision), `connection.organization_name_history`, `connection.accounts` (tenant_id, id, account_locator, region, cloud, account_name_current, edition, status `DISCOVERED\|SELECTED\|CONNECTED\|MISSING\|DISCONNECTED\|DELETED_AT_SOURCE`, source_identity_hash, first_seen_at, last_seen_at, missing_count, revision; unique `(tenant_id, account_locator, region, cloud)`), `connection.account_name_history`, `connection.account_membership_history` (tenant_id, account_id, organization_id, valid_from, valid_to, source, observed_at) | `docs/data/control-erd.md` §connection | Reviewed by CON and FIN owners (org-level rows per ADR-001) | 4 |
| CTL-001-S02 | Write migration with composite keys/FKs, RLS + grants via the CTL-101 template, and a GiST exclusion constraint preventing overlapping membership intervals per account | `migrations/versions/00xx_connection.py` | RLS lint passes; overlapping interval insert fails with 23P01 | 3 |
| CTL-001-S03 | Implement temporal repository: `organization_of(account_id, at)` and `accounts_of(org_id, at)` on half-open intervals `[valid_from, valid_to)` | `packages/control_db/repos/accounts.py` | Boundary instant belongs to the new interval | 3 |
| CTL-001-S04 | Implement discovery upsert by natural key: rename → history row + same UUID; missed discovery increments `missing_count`, status `MISSING` at 3; reappearance resets and keeps UUID; never delete | `packages/control_db/repos/discovery.py` | Rename and disappear/reappear fixtures keep one UUID | 4 |
| CTL-001-S05 | Implement organization transfer: close interval at `t`, open new; ignore events with `observed_at` older than the latest applied | `packages/control_db/repos/transfers.py` | Stale transfer event is a no-op with audit note | 3 |
| CTL-001-S06 | Implement cross-tenant duplicate detection on `source_identity_hash`, evaluated only after the connection's WIF verification succeeds; outcome per owner policy (Q1) with a response that never names the other tenant | `packages/control_db/repos/duplicate_accounts.py` | Unverified connection attempt cannot learn whether another tenant connected the account | 3 |
| CTL-001-S07 | Seed fixtures via FND-004: tenant A with two organizations and colliding account names, tenant B with identical locators/names | `tests/fixtures/control/accounts.yaml` | Loader produces distinct UUIDs across tenants | 2 |
| CTL-001-S08 | Tests: rename preserves UUID; transfer changes future membership only; historical lookup at a past date returns the old org; cross-tenant FK fails (23503); interval overlap rejected | `tests/control/test_accounts.py` | All PASS | 4 |
| CTL-001-S09 | Read APIs `GET /v1/organizations`, `GET /v1/accounts` with SEC-101 scope predicates and keyset pagination; team extension columns `linked_group_set_id/linked_group_id` (SEC.md G-SEC-03) | `apps/api/routes/organizations.py` | A1-scoped member lists only A1 | 3 |
| CTL-001-S10 | Generate ERD from migrations and record evidence | `docs/data/control-erd.md`, `docs/evidence/CTL-001/<commit>/` | ERD matches `pg_catalog` (script diff empty) | 2 |

Task acceptance:
- [ ] Rename keeps the internal UUID; organization transfer changes future membership without rewriting history.
- [ ] Temporary disappearance never deletes an account or its history.
- [ ] Cross-tenant FKs fail and duplicate detection never discloses another tenant.

### CTL-002 — Migration safety, indexes and bounded connection pools
Release: R1 · Estimate: 38–58 h · Risk: M · Decisions: D-07 · Closes: G-CTL-05, G-CTL-06, G-CTL-15
Dependency changes: `+CTL-101` (runner exists there; this task adds generation safety, indexes and budgets); keep CTL-001, INF-004.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CTL-002-S01 | Write the expand/contract protocol (Appendix C) and a migration linter: each revision declares `phase: expand\|backfill\|contract`; contract requires `requires_schema_rev_drained`; non-concurrent `CREATE INDEX` on existing tables, in-place renames/type changes and `ALTER TYPE … ADD VALUE` are rejected | `docs/data/migrations.md`, `tools/ci/migration_lint.py` | Linter fails on a fixture migration renaming a column | 4 |
| CTL-002-S02 | Create `platform.component_heartbeats` (component, instance_id, image_digest, schema_rev_min, schema_rev_max, last_seen_at) updated every 30 s by every process; migration runner guard for contract steps | `migrations/…`, `packages/control_db/heartbeat.py` | Contract refused while an N−1 heartbeat is <15 min old | 3 |
| CTL-002-S03 | Build resumable backfill framework `platform.backfill_jobs(name, last_key, batch_size, rows_done, status, updated_at)`; 5k rows per batch by PK, `SET LOCAL statement_timeout='30s'`, 200 ms pause, run as worker job outside the migration transaction | `packages/control_db/backfill.py` | Kill mid-run and resume without reprocessing committed batches | 4 |
| CTL-002-S04 | Run `CREATE INDEX CONCURRENTLY` inside Alembic `autocommit_block()`; detect and rebuild invalid indexes (`pg_index.indisvalid = false`) | `migrations/helpers/indexes.py` | Interrupted build leaves no invalid index after rerun | 2 |
| CTL-002-S05 | Seed a scale fixture (100 tenants; 1M outbox rows, 5M audit rows, 200k jobs, 50k invitations) and capture plans for 12 named queries: resolve_session, membership lookup, outbox claim, lease acquire, idempotency lookup, invitation by token hash, connection list, job claim, audit page, budget list, report schedule due, saved view list | `tests/performance/control/explain/*.sql` + expected plan assertions | Every query uses an index and examines ≤10× returned rows | 5 |
| CTL-002-S06 | Add only indexes justified by S05, each annotated with its query ID | migration | No unused index in `pg_stat_user_indexes` after the perf run | 2 |
| CTL-002-S07 | Implement pool configuration: env validated against the manifest; SQLAlchemy `pool_size`, `max_overflow` (default 0), `pool_timeout=5s`, `pool_pre_ping=True`, `pool_recycle=1800`, connect timeout 5 s; role GUCs `statement_timeout` (api 5 s, workers 60 s), `idle_in_transaction_session_timeout=15s`, `lock_timeout=2s` | `packages/control_db/engine.py`, role migration | `SHOW` under each role returns the configured values | 3 |
| CTL-002-S08 | Create `infra/db/pool-budget.yaml` (Appendix B) and CI check: Σ replicas_max × surge × processes × (pool_size+max_overflow) ≤ 0.70 × measured `max_connections` per cluster; Terraform autoscaling maxima must equal the manifest | `tools/ci/check_pool_budget.py` | CI fails when a service max replica count is raised without the manifest | 3 |
| CTL-002-S09 | Failover drill: Aurora failover under 200 req/s + workers; full-jitter reconnect (0.2–5 s); verify no tenant-context leak and recovery | `tests/performance/control/failover.md` evidence | Error rate back to baseline <60 s; zero cross-tenant rows | 4 |
| CTL-002-S10 | Startup jitter 0–10 s and DB circuit breaker (503 + `Retry-After`) to prevent reconnect storms | `packages/control_db/resilience.py` | 50 simultaneous task restarts do not exceed the budget | 2 |
| CTL-002-S11 | Mixed-generation test: N−1 image against N (expand) schema in CI; N image refuses to start on N−1 schema | `tests/compat/test_generations.py` | Both behaviours proven | 3 |
| CTL-002-S12 | Observability: `db_pool_in_use{component}`, `db_pool_wait_seconds`, `pg_connections{role}` from `pg_stat_activity`; alarms at 80 % of component budget and 70 % of cluster | `infra/alarms/db.tf` | Alarm fires in staging load test | 2 |
| CTL-002-S13 | Evidence pack incl. measured `max_connections` and drill numbers | `docs/evidence/CTL-002/<commit>/` | Recorded | 2 |

Task acceptance:
- [ ] Rerunning migrations is safe; contract steps cannot run while older generations are alive.
- [ ] No runtime login owns a table; configured pools stay within the manifest including deploy surge.
- [ ] The 12 named queries use their intended indexes at scale.
- [ ] Aurora failover recovers within the measured target without context leakage.

### CTL-003 — Scoped CRUD, invitations and optimistic concurrency
Release: R1 · Estimate: 56–84 h · Risk: H · Decisions: D-18 · Closes: G-CTL-04 (API side), G-CTL-09
Dependency changes: `−SEC-008` (audit write-path now in CTL-101), `+CTL-101`, `+SEC-004` (authorize/delegation); keep CTL-001, SEC-002, UX-001.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CTL-003-S01 | Author OpenAPI: `GET/PATCH /v1/tenants/current`, `GET /v1/members`, `GET/PATCH/DELETE /v1/members/{id}`, `PUT /v1/members/{id}/grants`, `POST/GET /v1/invitations`, `DELETE /v1/invitations/{id}`, `POST /v1/invitations/{id}:resend`, `POST /v1/invitations:accept`, `/v1/teams` CRUD, `/v1/teams/{id}/members` | `packages/api_contracts/openapi/settings.yaml` | Lint passes; every mutation documents If-Match/Idempotency-Key | 4 |
| CTL-003-S02 | Implement keyset pagination: signed cursor `{sort values, id, filter digest, exp 15 min}`, `limit ≤100`, stable `(created_at, id)` order | `packages/control_db/pagination.py` | Insertions between pages cause no duplicates/skips | 3 |
| CTL-003-S03 | Publish the error catalog (§3) and map exceptions to it | `packages/api_contracts/errors.yaml` | Every code used in routes exists in the catalog (CI) | 2 |
| CTL-003-S04 | Migrate `identity.invitations` (tenant_id, id, email_norm, token_hash unique, grants jsonb, invited_by, status `PENDING\|ACCEPTED\|REVOKED\|EXPIRED`, expires_at ≤14 d, accepted_by, accepted_at, resend_count, revision) | migration | RLS lint passes | 2 |
| CTL-003-S05 | Create invitation: delegation check (SEC-004), `users` quota check (CTL-007), Idempotency-Key, outbox `invitation.created` → email containing `/invite#t=<token>` | `apps/api/routes/invitations.py` | Retry with same key → same invitation id | 4 |
| CTL-003-S06 | Accept invitation per Appendix E (email binding, SSO binding, inviter re-validation, single use, uniform errors) | `apps/api/routes/invitations_accept.py` | ATK-24 (forwarded link used by another email) → 403 `INVITE_EMAIL_MISMATCH`; second accept by same subject → 200 same membership | 5 |
| CTL-003-S07 | Resend (rotates token), revoke, expiry job | `services/workers/invitation_expiry.py` | Old token after resend → uniform 410 `INVITE_INVALID` | 2 |
| CTL-003-S08 | `PUT /v1/members/{id}/grants` with If-Match: delegation, last-owner rule, epoch bump, profile recompute request (SEC-006) | `apps/api/routes/members.py` | Stale If-Match → 412; Team Admin granting FinOps Admin → 403 | 4 |
| CTL-003-S09 | Member removal, suspension and self-leave (blocked for last owner) | `apps/api/routes/members.py` | Last owner self-delete → 409 `LAST_OWNER` | 3 |
| CTL-003-S10 | Teams CRUD, team membership (Team Admin: own team only), optional linked usage group | `apps/api/routes/teams.py` | TA editing another team → 404 | 3 |
| CTL-003-S11 | Tests: same-key retry identical response; mismatched body 409; stale revision 412; missing If-Match 428; revoked invite; foreign member id 404; concurrent role edits; two owners removed concurrently | `tests/control/test_settings_api.py` | All PASS | 5 |
| CTL-003-S12 | UI `/settings/members`, `/settings/roles`, invitation dialog with explicit per-dimension scope builder (`*` must be chosen explicitly), pending vs active lists, all UX states; PRD role names only | `apps/web/settings/` | Playwright: keyboard path, 390 px, denied state shows no foreign names | 12 |
| CTL-003-S13 | Audit events for every mutation (allowed and denied) and metrics `settings_mutation_total{route,outcome}` | `apps/api/routes/*` | Audit rows present for each test mutation | 2 |
| CTL-003-S14 | Evidence | `docs/evidence/CTL-003/<commit>/` | PASS | 2 |

Task acceptance:
- [ ] An invitation is accepted once, only by the bound identity; retries return the same result.
- [ ] Team Admin cannot grant wider scope or roles above Analyst; the last owner cannot leave or be removed.
- [ ] Stale revisions return 412 and missing preconditions 428 (or the owner-approved alternative, documented once).
- [ ] Settings UI never shows foreign names/counts in denied states.

### CTL-004 — Outbox dispatcher and fenced job leases
Release: R1 · Estimate: 40–60 h · Risk: H · Decisions: D-04, D-07 · Closes: G-CTL-03, G-CTL-12
Dependency changes: `−CTL-003` (dispatcher does not need settings CRUD), `+CTL-101` (tables); keep CTL-002.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CTL-004-S01 | Define event catalog and routing: event_type → transport (`sqs_fifo`, `sqs_standard`, `internal`), queue, `ordering` (`AGGREGATE\|NONE`), max_attempts | `schemas/events/routing.yaml` | Every emitted event type has a route (CI) | 3 |
| CTL-004-S02 | Implement claim algorithm (Appendix A.2): SKIP LOCKED, per-aggregate head-of-line for ordered types, batch 100, lease 60 s, token from `platform.lease_token_seq` | `services/outbox_dispatcher/claim.py` | Two dispatchers never publish seq n+1 before seq n of the same aggregate (1,000-event test) | 4 |
| CTL-004-S03 | Publishers: FIFO with `MessageGroupId`=aggregate key and `MessageDeduplicationId`=event_id; standard queues with `event_id` attribute; consumer helper `consume_once(consumer, event_id)` over `platform.consumed_events` | `services/outbox_dispatcher/publish.py`, `packages/events/consume.py` | Duplicate publish → one consumer effect | 4 |
| CTL-004-S04 | Complete/fail with fencing; backoff `min(5 s·2^attempts, 3600 s)` ±20 % jitter; classes RETRYABLE/PERMANENT; attempts ≥ max → DEAD | `services/outbox_dispatcher/complete.py` | Stale-token completion affects 0 rows and logs `OUTBOX_STALE_LEASE` | 3 |
| CTL-004-S05 | Lease reaper using DB time; dispatcher heartbeat | `services/outbox_dispatcher/reaper.py` | Expired LEASED rows return to PENDING within 10 s | 2 |
| CTL-004-S06 | Dead-letter workflow: `bridge-admin outbox dead list`, `redrive --event-id --reason` (same event_id, attempts reset, audited), `discard --event-id --reason` (two-operator approval) | `tools/bridge_admin/outbox.py` | Redrive publishes once; discard without second operator refused | 3 |
| CTL-004-S07 | Retention: delete DONE rows older than 7 days in 10k batches; keep DEAD until resolved | `services/outbox_dispatcher/retention.py` | Table size stable in 7-day soak | 2 |
| CTL-004-S08 | Generic leases (Appendix A.4): acquire/renew/release and `platform.assert_fence()` raising `BL001` | `packages/control_db/leases.py`, migration | Old owner's protected write after takeover fails with `LEASE_LOST` | 4 |
| CTL-004-S09 | Crash tests: crash before send, after send before complete, after complete; stale worker after lease expiry; paused worker resumes | `tests/failure/test_outbox_crash.py` | Each case yields exactly one logical effect | 5 |
| CTL-004-S10 | Poison test: unknown `event_version` → DEAD immediately; only its aggregate blocks; other aggregates flow | `tests/failure/test_outbox_poison.py` | Blocked aggregate pages; others p99 <2 s | 2 |
| CTL-004-S11 | Throughput test: 1,000 events/s sustained for 10 min with 2 dispatchers | `tests/performance/outbox.md` | p99 commit→publish <2 s; no lock waits >100 ms | 3 |
| CTL-004-S12 | Observability: `outbox_pending`, `outbox_oldest_pending_age_seconds{event_type}`, `outbox_dead`, `outbox_dispatch_seconds`; alarms: age >60 s for `authz.*`/`config.*`, >300 s others, DEAD >0 | `infra/alarms/outbox.tf` | Alarms fire with dispatcher paused | 2 |
| CTL-004-S13 | Runbook (backlog, DEAD, stale lease) and evidence | `docs/runbooks/outbox.md` | Drill executed | 3 |

Task acceptance:
- [ ] All three crash points produce one logical effect; stale lease holders cannot complete or write.
- [ ] Per-aggregate order holds with concurrent dispatchers; a poison event blocks only its aggregate.
- [ ] Backlog age and DEAD counts are observable and alarmed.

### CTL-005 — Publish immutable analytical configuration snapshots (D-04)
Release: R1 · Estimate: 40–62 h · Risk: M · Decisions: D-04, D-05, D-10, D-16 · Closes: G-CTL-11
Dependency changes: `+INF-008` (CONFIG schema and `config-publisher` WIF identity), `+SEC-103` (pseudonymized user predicates), `+SEC-102` (only approved objects are serialized); keep CTL-004, INF-003 (S3 archive).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CTL-005-S01 | Write the ADR-007 amendment for D-04 (direct insert-only publication + S3 archive; drafts in `SIMULATION_INPUT`) and event contract `config.publication.requested` | `docs/architecture/adr/ADR-007a-direct-config-publication.md` | Accepted | 2 |
| CTL-005-S02 | Create Snowflake DDL (Appendix G): `CONFIG.CONFIG_VERSION` header + kind tables (`TAG_RULE_PREDICATE`, `ALLOCATION_RULE`, `ALLOCATION_WEIGHT`, `GROUP_SET_MEMBERSHIP`, `GROUP_HIERARCHY`, `PRICE_RATE`, `MONITOR_DEFINITION`); `CONFIG_PUBLISHER` has INSERT only; dbt role SELECT | `infra/snowflake/config/010_config.sql` | Publisher UPDATE/DELETE → insufficient privileges | 4 |
| CTL-005-S03 | Migrate PG `governance.config_publications` (tenant_id, id, config_kind, config_version, source_revisions jsonb, content_sha256, approval_id, status `PENDING_PUBLICATION\|PUBLISHED\|FAILED`, attempts, published_at, revision); version allocated per `(tenant, kind)` monotonically | migration | Concurrent requests allocate distinct versions | 3 |
| CTL-005-S04 | Implement deterministic serializer: approved objects only (valid SEC-102 approval), effective dates, user predicates pseudonymized (SEC-103), stable row order, content hash | `services/config_publisher/serialize.py` | Same input → byte-identical output and hash | 4 |
| CTL-005-S05 | Implement publisher: fenced lease per `(tenant, kind)`; one Snowflake transaction inserting rows then header; existing header equal hash → no-op; different hash → FAILED `CONFIG_VERSION_CONFLICT` + page | `services/config_publisher/publish.py` | Kill between rows and header → no header, retry completes once | 5 |
| CTL-005-S06 | Write S3 archive copy `config/{env}/{tenant}/{kind}/{version}.json.gz` (versioned bucket, KMS) with SHA-256 | `services/config_publisher/archive.py` | Archive hash equals content hash | 2 |
| CTL-005-S07 | Acceptance: verify header row_count/hash via SELECT, then PG `PUBLISHED`; `GET /v1/config-publications/{id}` shows `PENDING_PUBLICATION` until then | `apps/api/routes/config_publications.py` | UI shows pending until verified | 2 |
| CTL-005-S08 | Hand DBT the read contract: only header-complete versions; dedup test tolerating identical duplicates and failing conflicting ones | `docs/data/config-read-contract.md` | DBT owner sign-off | 2 |
| CTL-005-S09 | Simulation inputs to `SIMULATION_INPUT` with 7-day TTL task; never `CONFIG` | `services/config_publisher/simulation.py` | Draft rule absent from `CONFIG` (oracle) | 3 |
| CTL-005-S10 | Reconstruction: rebuild version N from S3 archive and from `CONFIG`; compare | `tools/bridge_admin/config_reconstruct.py` | Equal hashes | 2 |
| CTL-005-S11 | Tests: duplicate events → one version; v3 published before v2 (independent immutable versions; latest pointer = max PUBLISHED); payload tenant ≠ event tenant → reject; deleted rule referenced by a closed statement remains reconstructable | `tests/control/test_config_publication.py` | All PASS | 4 |
| CTL-005-S12 | Retention: versions referenced by closed statements never deleted; others per 400-day policy | `services/config_publisher/retention.py` | Referenced version survives purge run | 2 |
| CTL-005-S13 | Observability: `config_publication_latency_seconds` (target p95 ≤60 s), `config_publication_failed_total`; runbook | `docs/runbooks/config-publication.md` | Alarm test fires | 2 |
| CTL-005-S14 | Evidence | `docs/evidence/CTL-005/<commit>/` | PASS | 2 |

Task acceptance:
- [ ] A draft rule never appears in `CONFIG`; duplicate events produce one logical version; conflicting content for the same version pages instead of overwriting.
- [ ] Any published version can be reconstructed byte-for-byte from the archive.
- [ ] No plaintext user name leaves PG in a config version.

### CTL-006 — Scoped Redis keys and safe degradation
Release: R1 · Estimate: 36–54 h · Risk: M · Decisions: D-02, D-22 · Closes: G-CTL-07
Dependency changes: `−CTL-004` (not needed), `+CTL-101`, `+SEC-101` (profile hash); keep SEC-006.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CTL-006-S01 | Write the key/value contract (Appendix D) | `docs/data/redis-contract.md` | Reviewed with API owner | 2 |
| CTL-006-S02 | Implement request canonicalization (sorted set-like filters, preserved order-sensitive clauses, UTC timestamps, normalized decimals, grain/period included) and `get_or_compute(ctx: AuthorizedContext, request, compute, ttl_class)`; no API accepts a raw key | `packages/cache/api.py` | Two equivalent requests → same key; different grain → different key | 4 |
| CTL-006-S03 | Implement value envelope (zstd JSON: full request digest, full profile_hash, publication_id, as_of, coverage, created_at, payload), 1 MB cap (larger results not cached) | `packages/cache/envelope.py` | Forced digest mismatch → treated as miss | 3 |
| CTL-006-S04 | TTL classes with ±10 % jitter: navigation 600 s, recent KPI 120 s, historical 1,800 s, small config 300 s | `packages/cache/ttl.py` | Unit tests | 1 |
| CTL-006-S05 | Single-flight: Redis `SET NX PX 15000` lock + waiters polling 50 ms up to 2 s; in-process future map; per-tenant (4/replica) and global (32/replica) compute semaphores | `packages/cache/singleflight.py` | 100 identical concurrent misses → 1 Snowflake query | 4 |
| CTL-006-S06 | Degradation: circuit opens after 5 consecutive errors or p99 >50 ms over 30 s; bypass cache; caps 2/tenant, 16 global; excess → 503 `ANALYTICS_BUSY`, `Retry-After: 2` | `packages/cache/circuit.py` | Redis down: 100 identical misses → ≤ number of broker replicas queries | 3 |
| CTL-006-S07 | Stale-while-revalidate only within the same key family and ≤300 s stale with visible `stale_as_of`; disabled for close/chargeback/revocation paths | `packages/cache/swr.py` | Close endpoint never served stale (test) | 2 |
| CTL-006-S08 | Redis ACL users per component (`api`, `broker`: `~bridge:v1:*`, `~bridge:lock:*`; `ratelimit`: `~bridge:rl:*`), `-@dangerous -keys -flushall`, TLS + AUTH via Terraform; eviction `allkeys-lru` | `infra/terraform/modules/redis/acl.tf` | `FLUSHALL` as api user → NOPERM | 3 |
| CTL-006-S09 | Rate-limit token buckets (Lua) per tenant/subject/API client; in-process fallback limiter when Redis unavailable | `packages/cache/ratelimit.py` | Limits hold with Redis down (degraded, per-replica) | 3 |
| CTL-006-S10 | Tests: tenant A/B, same-tenant different profile, authz_epoch bump makes old keys unreachable, dataset version swap, Redis flush mid-traffic, digest mismatch | `tests/cache/` | No cross-scope/version hit in 10k randomized requests | 5 |
| CTL-006-S11 | Verify `Cache-Control: no-store` on `/api/*` and CloudFront `CachingDisabled` for `/api/*` (with INF-006) | `tests/edge/test_no_store.py` | Response headers asserted in staging | 1 |
| CTL-006-S12 | Observability: `cache_hit_ratio{ttl_class}`, `cache_singleflight_wait_seconds`, `cache_circuit_open`, `analytics_busy_total`; RB-12 updated with the numeric caps | `docs/runbooks/RB-12-redis-loss.md` | Drill: flush Redis under load; latency only | 2 |
| CTL-006-S13 | Evidence | `docs/evidence/CTL-006/<commit>/` | PASS | 2 |

Task acceptance:
- [ ] No cache hit crosses tenant, profile, authz epoch, dataset version, currency, privacy mode or grain.
- [ ] Redis loss loses no job, lease, session or permission state; Snowflake load stays within caps.
- [ ] 100 identical misses cause 1 query (Redis up) and at most one per broker replica (Redis down).

### CTL-007 — Saved views, dashboards and commercial control records
Release: R1 (custom dashboard builder depth → UX-101/RPT-103, R2; CTL-103 merged into UX-101 per RECONCILIATION U-01) · Estimate: 31–46 h · Risk: M · Decisions: D-17 · Closes: G-CTL-14 (G-CTL-08 → LCH-101/LCH-001 per RECONCILIATION U-08, C-08)
Scope after RECONCILIATION U-08: saved views, shares, R1 dashboards (`report.dashboards`, ≤ 30 widgets, fixed grid, per-widget states) and spec validation. Plans/entitlements/admission are LCH-101's; subscription state machine, invoice references and payment evidence are LCH-001's.
Dependency changes: `+API-001` (registry contract for spec validation; contract only, not live data), `−CTL-005` (not needed); keep CTL-003, UX-001. The requested `+CTL-102` edge is dropped with the commercial scope (RECONCILIATION U-08).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CTL-007-S01 | Migrate `report.saved_views` (tenant_id, id, owner_membership_id NULL, name, description, semantic_spec jsonb, registry_version, visibility `PRIVATE\|SHARED`, revision), `report.shares` (tenant_id, object_type, object_id, grantee_type `MEMBER\|TEAM\|TENANT`, grantee_id), `report.dashboards` (layout jsonb, widgets jsonb ≤30) | migration | RLS lint passes | 3 |
| CTL-007-S02 | Validate specs by JSON Schema against the registry version (metric IDs, dimensions, operators), 16 KB per spec, no result-value fields | `packages/semantic/spec_validation.py` | Spec containing a numeric result array rejected | 3 |
| CTL-007-S03 | CRUD and share APIs with If-Match and Idempotency-Key | `apps/api/routes/saved_views.py`, `dashboards.py` | Foreign shared view id → 404 | 4 |
| CTL-007-S04 | Rendering rule: always recipient's profile; filters outside recipient scope → widget `PARTIAL_SCOPE` without echoing names; deleted metric → `UNAVAILABLE_METRIC` with migration hint; other widgets render | `packages/semantic/render_saved.py` | Recipient with A1 scope viewing an A1+A2 view sees A1 values and a partial-scope notice | 4 |
| CTL-007-S05 | Ownership lifecycle: removed owner → shared objects owned by tenant admins; private views of removed members deleted after 30 days | `services/workers/saved_view_gc.py` | GC run matches fixture expectations | 2 |
| CTL-007-S06 | Metric version migration: compatible auto-upgrade per registry rules; incompatible → flagged | `packages/semantic/spec_migration.py` | Deprecated metric fixture upgraded or flagged | 3 |
| CTL-007-S07 | Moved to LCH-101-S01 (`commercial.plans`, `commercial.tenant_entitlements`) and LCH-001-S04 (`invoice_refs`, `payment_events`) per RECONCILIATION U-08, C-08 — CTL-007 creates no commercial or subscription table | — | — | 0 |
| CTL-007-S08 | Moved to LCH-001-S02 per RECONCILIATION C-08 (canonical subscription state machine, `LCH.md` G-LCH-03) | — | — | 0 |
| CTL-007-S09 | Moved to LCH-101-S03 per RECONCILIATION U-08 (`entitlements.check()` and admission hooks) — consume it here for saved-view/dashboard quotas | — | — | 0 |
| CTL-007-S10 | Moved to LCH-001 (payment evidence, S04/S07) per RECONCILIATION U-08 | — | — | 0 |
| CTL-007-S11 | Tests: shared view recipient-only data; suspended tenant keeps saved views and dashboards (commercial tests — plan change, duplicate payment — are LCH-101/LCH-001's, RECONCILIATION U-08) | `tests/control/test_views_dashboards.py` | All PASS | 2 |
| CTL-007-S12 | UI: save view, share dialog (members/teams/tenant), dashboard grid with per-widget states (the plan/limits page `/settings-billing` moves with the commercial scope to LCH, RECONCILIATION U-08) | `apps/web/dashboards/` | Playwright covers partial-scope and unavailable-metric widgets | 6 |
| CTL-007-S13 | Audit, metrics and evidence | `docs/evidence/CTL-007/<commit>/` | PASS | 3 |

Task acceptance:
- [ ] A shared view renders only recipient-authorized data and never discloses out-of-scope filter values.
- [ ] PG stores specs and layouts only (no analytical result values).
- [ ] Saved-view and dashboard quotas are checked through LCH-101's `entitlements.check()` (subscription states and payment evidence are LCH-001's; RECONCILIATION U-08).

## 5. New tasks required

### CTL-101 — Control DB kernel (migration runner, roles, unit of work, outbox/idempotency/audit tables)
Release: R1 · Estimate: 36–56 h · Risk: H · Decisions: D-25 · Closes: G-CTL-01 (kernel), G-CTL-02, G-CTL-04, SEC.md G-SEC-10/G-SEC-11
Why: every tenant table, SEC-004's first migration, SEC-006's epoch/outbox write and SEC-008's audit emit need the same kernel; without it the graph contains a cycle. Plugs in right after INF-004; precedes SEC-004, CTL-001, CTL-003, CTL-004.
Dependency changes: `+INF-004`, `+FND-003`.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CTL-101-S01 | Set up Alembic with a one-off ECS migration task (`bridge-migrate`), `pg_advisory_lock(7431001)`, `lock_timeout=3s` with 5 retries, `transaction_per_migration=True`; API/worker startup never migrates | `migrations/env.py`, `services/migrate/` | Two concurrent runners: second waits then no-ops | 4 |
| CTL-101-S02 | Bootstrap roles (SEC.md Appendix E.1) with `rds_iam`, `NOBYPASSRLS`; helper `grant_table(table, role, privileges)` used by migrations (no blanket default privileges) | `migrations/versions/0001_roles.py` | Catalog query: no runtime role owns objects or bypasses RLS | 3 |
| CTL-101-S03 | Implement `tenant_transaction(ctx)` / `platform_transaction(role_scope)` for SQLAlchemy 2.x + asyncpg: begin, context set with prior-value leak guard, `SET LOCAL statement_timeout`, commit/rollback; semgrep rules banning `AsyncSession(` outside the module and `isolation_level="AUTOCOMMIT"` | `packages/control_db/tx.py`, `.semgrep/control_db.yml` | Lint fails on a banned pattern; leak guard test passes | 4 |
| CTL-101-S04 | Implement RLS catalog lint and generated per-table isolation tests (SEC.md Appendix E.6/E.7) | `tools/ci/rls_lint.sql`, `tests/security/rls/test_generated.py` | A test table without FORCE RLS fails CI | 4 |
| CTL-101-S05 | Create `platform.outbox` (Appendix A.1) and `emit_event(tx, event)` validating payload against `schemas/events/*.json` (IDs/versions only, ≤64 KB) | migration, `packages/events/emit.py` | Rolled-back transaction leaves no outbox row | 3 |
| CTL-101-S06 | Create `platform.idempotency_requests` (Appendix A.3) and middleware | migration, `apps/api/middleware/idempotency.py` | Concurrent duplicate → one mutation; second response replayed with `Idempotent-Replayed: true` | 4 |
| CTL-101-S07 | Create minimal `audit.events` and `emit_audit()` (allowed in-tx; denied/failed via separate transaction helper) | migration, `packages/audit/emit.py` | Denied mutation still leaves one audit row | 3 |
| CTL-101-S08 | Implement OCC helpers: `revision` mixin, ETag `"r<revision>"`, If-Match required (428), mismatch 412 `STALE_REVISION`, not-found vs stale disambiguation under RLS | `packages/control_db/occ.py` | Stale update returns 412; foreign id 404 | 3 |
| CTL-101-S09 | Implement the error envelope and asyncpg exception mapping by constraint name (no DB text) | `apps/api/errors.py` | Unique violation → catalog code, no key values in body/logs | 2 |
| CTL-101-S10 | Kernel tests: rollback atomicity of outbox/audit/idempotency; missing context zero rows on kernel tables; leak guard | `tests/control/test_kernel.py` | All PASS | 4 |
| CTL-101-S11 | Write "add a tenant table" guide and migration template | `docs/data/adding-a-tenant-table.md`, `migrations/templates/tenant_table.py.mako` | A new table created from the template passes lint and generated tests unchanged | 2 |

Task acceptance:
- [ ] Object change, audit and outbox commit or roll back together.
- [ ] Missing tenant context yields zero rows and failed writes on every kernel table.
- [ ] Concurrent duplicate idempotency keys produce exactly one mutation.

### CTL-102 — Tenant lifecycle and operator provisioning console
Release: R1 · Estimate: 25–39 h · Risk: M · Decisions: D-17, D-25 · Closes: G-CTL-13, SEC.md G-SEC-24
Why: tenant creation, suspension and offboarding have no owner; SEC-105 needs a trigger; LCH-001 needs an internal console for finance operators. CTL-102 owns the single ops plane (ops API, operator authentication for console and CLI, operator role catalog, tenant lifecycle endpoints); OPS-106 owns permission sets and the `bridge-admin` CLI, SEC-104 support grants, LCH-001 only registers finance-operator capabilities (RECONCILIATION U-05). Tombstones are OPS-104's and the deletion orchestrator is OPS-005's (U-11, C-19). Plugs in after SEC-004, SEC-105, CTL-004, INF-006; consumed by SEC-104, LCH-101, LCH-001, OPS-106, ONB-102.
Dependency changes: `+SEC-004`, `+SEC-105`, `+CTL-004`, `+INF-006` (ops API/console on the internal ALB private listener; RECONCILIATION U-05).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CTL-102-S01 | Specify tenant state machine PROVISIONING → ACTIVE ⇄ SUSPENDED → OFFBOARDING → DELETED with guards/effects (logins, reads, jobs, extraction, exports) | `docs/data/tenant-lifecycle.md` | Reviewed with LCH and OPS owners | 2 |
| CTL-102-S02 | Single ops plane (RECONCILIATION U-05): internal ops API service on the INF-006 private ALB listener; operator authentication via IAM Identity Center OIDC (console) and SigV4 from operator roles (`bridge-admin` CLI, OPS-106); operator role catalog `ops_viewer`, `ops_provisioner`, `finance_operator`, `support_agent`, `incident_responder`; hardware MFA | `apps/internal_console/auth/`, `apps/ops_api/` | Customer Cognito sessions rejected; public internet cannot reach console or ops API; unsigned CLI call → 403 | 7 |
| CTL-102-S03 | `POST /internal/v1/tenants` (ops_provisioner, step-up, reason): SEC-004 bootstrap transaction, outbox `tenant.principal.requested`, first-owner invitation | `apps/internal_console/routes/tenants.py` | Idempotent on retry; audit event with operator id | 3 |
| CTL-102-S04 | Activation when SEC-105 reports principal ACTIVE; failures visible in console | `services/workers/tenant_activation.py` | Tenant stays PROVISIONING while principal fails | 2 |
| CTL-102-S05 | Suspension/resume: outbox `tenant.suspended` pauses schedules/extraction/jobs; reads per grace flag; banner | `packages/tenancy/suspension.py` | Suspended tenant cannot start jobs (403 `TENANT_SUSPENDED`) | 3 |
| CTL-102-S06 | Start offboarding for RB-14: transition to OFFBOARDING, start the export window, then hand over to OPS-005's tenant-deletion orchestrator (ordered stages, dry-run manifest, second operator; stage handlers CON-006/CON-001 revoke, SEC-105-S07 disable) which writes the TENANT tombstone to OPS-104 (RECONCILIATION U-11, C-19) | `packages/tenancy/offboarding.py` | OFFBOARDING tenant has an OPS-005 TENANT_DELETION request; no `platform.tenant_tombstones` table exists | 1 |
| CTL-102-S07 | Restore guard: startup/restore validation reads OPS-104's TENANT tombstones (S3 mirror outside restore scope) and refuses to serve tenants present there (RB-10/RB-11; RECONCILIATION U-11) | `packages/tenancy/restore_guard.py` | Restored backup containing a deleted tenant keeps it inaccessible | 2 |
| CTL-102-S08 | Tests for every transition guard and effect | `tests/control/test_tenant_lifecycle.py` | All PASS | 3 |
| CTL-102-S09 | Audit, runbook and evidence | `docs/runbooks/tenant-lifecycle.md` | Drill executed | 2 |

Task acceptance:
- [ ] Tenants are created only by authenticated operators with audit; activation waits for the serving principal.
- [ ] Suspension stops new work without deleting configuration; offboarding starts OPS-005's two-operator deletion workflow, and restores honour OPS-104's tombstones.

### CTL-103 — Custom dashboard builder depth
**Merged into UX-101 per RECONCILIATION U-01.** UX-101 owns the dashboards list, builder UI and widget states; RPT-103 owns the backend (dashboard definition as a report layout kind, widget data API under the viewer's scope, sharing, export to report). The entry stays for traceability (`merged_into: UX-101` in revised-task-graph.json).
Release: R2 · Estimate: 0 h (merged; was 24–40 h) · Risk: L · Decisions: D-01 · Closes: RELEASE_PLAN "custom dashboard builder depth" (via UX-101/RPT-103)
Why: R1 ships saved views and a fixed-grid dashboard; richer building is breadth.
Dependency changes: none — edges retired with the merge (was `+CTL-007`, `+UX-004`).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CTL-103-S01 | Merged into UX-101-S03 (grid editor with keyboard alternatives) per RECONCILIATION U-01 | — | — | 0 |
| CTL-103-S02 | Merged into UX-101-S02 (widget model) and RPT-103-S01 (dashboard definition schema) per U-01 | — | — | 0 |
| CTL-103-S03 | Merged into UX-101-S04 (dashboard-level scope/period, one publication per load) per U-01 | — | — | 0 |
| CTL-103-S04 | Merged into UX-101 (persona templates as optional R2 breadth) per U-01 | — | — | 0 |
| CTL-103-S05 | Merged into UX-101-S05 / RPT-103-S05 (revision, optimistic concurrency) per U-01 | — | — | 0 |
| CTL-103-S06 | Merged into UX-101-S08 (a11y/mobile) per U-01 | — | — | 0 |
| CTL-103-S07 | Merged into UX-101-S08 and RPT-103-S07 (shared dashboard under a narrower viewer) per U-01 | — | — | 0 |
| CTL-103-S08 | Evidence recorded under UX-101 per U-01 | — | — | 0 |

Task acceptance:
- [ ] (Carried by UX-101/RPT-103 acceptance.) Dashboards remain configuration-only and render under the viewer's profile.
- [ ] (Carried by UX-101-S04.) All widgets in one dashboard read one publication.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| CTL-101 | R1 | 36 | 56 |
| CTL-001 | R1 | 30 | 46 |
| CTL-002 | R1 | 38 | 58 |
| CTL-003 | R1 | 56 | 84 |
| CTL-004 | R1 | 40 | 60 |
| CTL-005 | R1 | 40 | 62 |
| CTL-006 | R1 | 36 | 54 |
| CTL-007 | R1 | 31 | 46 |
| CTL-102 | R1 | 25 | 39 |
| CTL-103 (merged into UX-101, RECONCILIATION U-01) | R2 | 0 | 0 |
| **Total R1** | \| **332** | **505** |
| **Total R2** | \| **0** | **0** |

## 7. Owner questions

1. **Q1 Same Snowflake account in two tenants** (e.g. reseller/consultancy tenant and end-customer tenant): allow (two independent extractions and customer-side credit costs), or block after verification?
2. **Q2 Grace policy numbers**: launch.md requires a "documented grace/export policy" but gives no durations. Proposed: PAST_DUE 14 days full access; SUSPENDED read-only + export for 30 days; then locked pending offboarding.
3. **Q3 Tenant-wide sharing**: may Analysts share saved views/dashboards with the whole tenant, or only with members/teams (recommended: members/teams; tenant-wide requires FinOps/Org Admin)?
4. **Q4 Removed members' private views**: delete after 30 days (recommended) or transfer to an admin?

---

## Appendix A — Outbox, idempotency, leases and concurrency

### A.1 Outbox DDL
```sql
CREATE SEQUENCE platform.lease_token_seq;
CREATE TABLE platform.outbox (
  event_id         uuid PRIMARY KEY,
  tenant_id        uuid NULL,                       -- NULL only for platform events (platform_transaction)
  aggregate_type   text   NOT NULL,
  aggregate_id     uuid   NOT NULL,
  aggregate_seq    bigint NOT NULL,                 -- aggregate revision after the mutation
  event_type       text   NOT NULL,
  event_version    smallint NOT NULL,
  ordering         text   NOT NULL CHECK (ordering IN ('AGGREGATE','NONE')),
  payload          jsonb  NOT NULL CHECK (pg_column_size(payload) <= 65536),
  trace_id         text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  available_at     timestamptz NOT NULL DEFAULT now(),
  status           text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','LEASED','DONE','DEAD')),
  attempts         int  NOT NULL DEFAULT 0,
  max_attempts     int  NOT NULL DEFAULT 12,
  lease_owner      text, lease_token bigint, lease_expires_at timestamptz,
  last_error_class text, last_error_at timestamptz, completed_at timestamptz,
  UNIQUE (aggregate_type, aggregate_id, aggregate_seq)
);
CREATE INDEX outbox_ready      ON platform.outbox (available_at) WHERE status = 'PENDING';
CREATE INDEX outbox_open_aggr  ON platform.outbox (aggregate_type, aggregate_id, aggregate_seq) WHERE status IN ('PENDING','LEASED','DEAD');
CREATE INDEX outbox_lease_exp  ON platform.outbox (lease_expires_at) WHERE status = 'LEASED';
CREATE TABLE platform.consumed_events (consumer text NOT NULL, event_id uuid NOT NULL,
  consumed_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY (consumer, event_id));
```
RLS: `bridge_api`/`bridge_worker` INSERT with `WITH CHECK (tenant_id = app.current_tenant())`; `bridge_dispatcher` SELECT/UPDATE `USING (true)` (allowlisted); DELETE only `bridge_retention`.

### A.2 Claim, complete, fail, reap
```sql
-- claim ($1 batch size, $2 owner)
WITH c AS (
  SELECT o.event_id FROM platform.outbox o
  WHERE o.status = 'PENDING' AND o.available_at <= now()
    AND (o.ordering = 'NONE' OR NOT EXISTS (
          SELECT 1 FROM platform.outbox p
          WHERE p.aggregate_type = o.aggregate_type AND p.aggregate_id = o.aggregate_id
            AND p.aggregate_seq < o.aggregate_seq AND p.status IN ('PENDING','LEASED','DEAD')))
  ORDER BY o.available_at
  LIMIT $1
  FOR UPDATE SKIP LOCKED)
UPDATE platform.outbox o
   SET status = 'LEASED', lease_owner = $2, lease_token = nextval('platform.lease_token_seq'),
       lease_expires_at = now() + interval '60 seconds', attempts = o.attempts + 1
  FROM c WHERE o.event_id = c.event_id
RETURNING o.event_id, o.lease_token, o.event_type, o.event_version, o.payload, o.aggregate_id;
-- complete
UPDATE platform.outbox SET status='DONE', completed_at=now(), lease_owner=NULL
 WHERE event_id=$1 AND lease_token=$2 AND status='LEASED';            -- 0 rows = stale, no-op
-- fail ($3 class)
UPDATE platform.outbox
   SET status = CASE WHEN $3='PERMANENT' OR attempts >= max_attempts THEN 'DEAD' ELSE 'PENDING' END,
       available_at = now() + make_interval(secs => least(5 * 2 ^ attempts, 3600) * (0.8 + random()*0.4)),
       last_error_class = $4, last_error_at = now(), lease_owner = NULL
 WHERE event_id=$1 AND lease_token=$2 AND status='LEASED';
-- reap (every 10 s)
UPDATE platform.outbox SET status='PENDING', lease_owner=NULL
 WHERE status='LEASED' AND lease_expires_at < now();
```
A lower-sequence PENDING event locked by another dispatcher is still visible as PENDING to the `NOT EXISTS`, so a successor cannot be claimed concurrently. A DEAD predecessor blocks its aggregate by design (ordering integrity) and pages.

### A.3 Idempotency
```sql
CREATE TABLE platform.idempotency_requests (
  tenant_id       uuid NOT NULL,
  principal_id    uuid NOT NULL,                     -- subject or API client
  route_key       text NOT NULL,                     -- e.g. 'POST /v1/invitations'
  idem_key        text NOT NULL CHECK (idem_key ~ '^[A-Za-z0-9_-]{16,128}$'),
  request_sha256  bytea NOT NULL,                    -- sha256(JCS(body) || path params || relevant query)
  response_status smallint NOT NULL,
  response_body   jsonb NOT NULL CHECK (pg_column_size(response_body) <= 32768),
  resource_type   text, resource_id uuid,
  created_at      timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL,              -- created_at + 24 h
  PRIMARY KEY (tenant_id, principal_id, route_key, idem_key)
);
```
Algorithm: (1) look up key; if present → same hash: replay stored 2xx with `Idempotent-Replayed: true`; different hash: 409 `IDEMPOTENCY_KEY_REUSED`. (2) Otherwise execute the mutation and INSERT the record in the **same transaction** before commit. (3) A concurrent duplicate blocks on the PK until the first commits; on unique violation it rolls back and goes to (1); if the first rolled back, it proceeds. Only 2xx responses are stored. External side effects happen only through the outbox, so replays never duplicate them. Cleanup deletes expired rows hourly.

### A.4 Leases and fencing
```sql
CREATE TABLE platform.leases (
  resource_kind text NOT NULL, resource_key text NOT NULL, tenant_id uuid NULL,
  owner_id text NOT NULL, fencing_token bigint NOT NULL,
  acquired_at timestamptz NOT NULL, renewed_at timestamptz NOT NULL, expires_at timestamptz NOT NULL,
  PRIMARY KEY (resource_kind, resource_key));
-- acquire ($5 ttl seconds); no row returned = held by another owner
INSERT INTO platform.leases AS l VALUES ($1,$2,$3,$4, nextval('platform.lease_token_seq'), now(), now(), now() + make_interval(secs => $5))
ON CONFLICT (resource_kind, resource_key) DO UPDATE
   SET owner_id = EXCLUDED.owner_id, fencing_token = EXCLUDED.fencing_token,
       acquired_at = now(), renewed_at = now(), expires_at = EXCLUDED.expires_at
 WHERE l.expires_at < now()
RETURNING fencing_token;
-- renew (every ttl/3); 0 rows = lease lost → stop work
UPDATE platform.leases SET renewed_at = now(), expires_at = now() + make_interval(secs => $4)
 WHERE resource_kind=$1 AND resource_key=$2 AND fencing_token=$3 AND expires_at > now();
```
`platform.assert_fence(kind, key, token)`: `SELECT 1 FROM platform.leases WHERE … AND fencing_token = token AND expires_at > now() FOR SHARE`; no row → `RAISE EXCEPTION USING ERRCODE='BL001', MESSAGE='LEASE_LOST'`. Called first in every protected transaction (checkpoint advance, batch acceptance, publication pointer). The `FOR SHARE` lock makes a concurrent takeover wait until the protected transaction ends. External artifacts carry the token (manifest field `attempt_fencing_token`); acceptance compares it with the attempt row. Defaults: TTL 60 s, renew every 20 s; DB time only.

### A.5 Optimistic concurrency
Every mutable table has `revision bigint NOT NULL DEFAULT 1`. `ETag: "r<revision>"`. PATCH/PUT/DELETE require `If-Match` (428 `PRECONDITION_REQUIRED` if absent). `UPDATE … SET …, revision = revision + 1 WHERE tenant_id=$t AND id=$id AND revision=$expected RETURNING revision`; 0 rows → re-select under RLS: absent → 404, present → 412 `STALE_REVISION` with current ETag. (Challenges `control-plane.md` "stale revision returns 409"; see G-CTL-04.)

## Appendix B — Connection budget (initial R1 manifest, production)
Formula per cluster: `Σ replicas_max × processes × (pool_size + max_overflow)`; checked twice — steady state ≤0.70 × `max_connections` and deploy surge (ECS `maximumPercent=200` doubles services) ≤0.90 × `max_connections`.

| Component | DB user | replicas max | processes | pool+overflow | Steady | Surge |
|---|---|---:|---:|---:|---:|---:|
| api | bridge_api | 6 | 2 | 8+2 | 120 | 240 |
| query-broker (authz reads) | bridge_broker | 4 | 1 | 6+2 | 32 | 64 |
| outbox-dispatcher | bridge_dispatcher | 2 | 1 | 4+0 | 8 | 16 |
| control workers (planner, receipts, reconciler, reapers) | bridge_worker | 4 | 1 | 6+0 | 24 | 48 |
| authz-provisioner, config-publisher, audit-exporter | bridge_worker / bridge_audit_exporter | 1 each | 1 | 2+0 | 6 | 12 |
| monitor-evaluator | bridge_worker | 3 | 1 | 4+0 | 12 | 24 |
| report-renderer | bridge_worker | 2 | 1 | 3+0 | 6 | 12 |
| extraction account-cycle tasks (D-07; 8 steady + 2 backfill per orchestration.md) | bridge_worker | 10 | 1 | 2+0 | 20 | 20 |
| migration task | bridge_migrator | 1 | 1 | 2+0 | 2 | 2 |
| ops / break-glass reserve | bridge_ops_ro | — | — | — | 10 | 10 |
| **bridge_control subtotal** | \| | \| | **240** | **448** |
| Dagster webserver | dagster | 2 | 1 | 5+0 | 10 | 20 |
| Dagster daemon | dagster | 1 | 1 | 10+0 | 10 | 20 |
| Dagster run workers (16 concurrent runs: 8+2+2+2+2 per orchestration.md; ≈3 conns/run — MEASURE) | dagster | 16 | 1 | 3 | 48 | 48 |
| **dagster_meta subtotal** | \| | \| | **68** | **88** |
| **Cluster total** | \| | \| | **308** | **536** |

On db.r6g.large (`max_connections` ≈1,716, secondary source; formula VERIFIED) the limits are 1,201 steady / 1,544 surge → ample headroom; memory ≈10 MB/backend × 536 ≈5.4 GB of 16 GiB. On db.t4g.medium (4 GiB → at most ≈450 by formula before reserved memory) the steady total leaves no headroom → staging must use smaller replica maxima. All connections target the writer endpoint (authz reads need read-after-write). RDS Proxy is not used in R1 (R32 pinning risk, TO VERIFY LIVE).

## Appendix C — Expand/contract protocol with mixed generations
1. **Release k (expand)**: additive only — new tables, nullable columns, `CREATE INDEX CONCURRENTLY` (autocommit block), `CHECK … NOT VALID`, FK `NOT VALID`; RLS/grants for new tables in the same revision. Code k writes old and new, reads old.
2. **Backfill**: resumable job (`platform.backfill_jobs`), 5k rows/batch, throttled; then `VALIDATE CONSTRAINT`; `SET NOT NULL` after a validated `CHECK (col IS NOT NULL)`.
3. **Release k+1**: reads new, still writes both. Consumers accept outbox `event_version` N and N−1.
4. **Release k+2 (contract)**: runner checks `platform.component_heartbeats` — no live instance (last 15 min) with `schema_rev_max` < required, and no PENDING/LEASED/DEAD outbox events with retired `event_version` — then drops old columns/tables.
5. Applications refuse to start if `alembic_version` < their `schema_rev_min`; they may run on newer expand-only schemas.
6. Forbidden: in-place rename/type change, PG enum types (use text + CHECK), long `ACCESS EXCLUSIVE` locks (`lock_timeout=3s`, retried), migrations at app startup.

## Appendix D — Redis contract
- Analytical cache key: `bridge:v1:{env}:{tenant_id}:{profile_hash16}:{authz_epoch}:{dataset}:{dataset_version}:{metric_version}:{currency}:{privacy_mode}:{request_digest16}` where `profile_hash16` = first 16 hex of the immutable profile hash, `authz_epoch` = `tenants.authz_epoch`, `request_digest` = SHA-256 of the canonical request (grain, period, filters, dimensions, sort, limit). Full `profile_hash` and full digest are stored in the envelope and compared on read.
- Other families: `bridge:lock:{env}:{digest}` (single-flight, PX 15 s), `bridge:rl:{env}:{scope}:{id}:{window}` (rate limits), `bridge:nav:{env}:{tenant}:{profile_hash16}:{authz_epoch}:{nav_version}`.
- Never in Redis: sessions, CSRF secrets, permissions/grants, leases/ownership, job state, outbox state.
- Envelope: zstd(JSON) `{v, digest, profile_hash, publication_id, as_of, coverage, created_at, payload}`; ≤1 MB.
- TTL classes (±10 % jitter): navigation 600 s; recent KPI 120 s; historical KPI 1,800 s; small config 300 s. SWR ≤300 s stale, same key family, visible `stale_as_of`; never for close, chargeback or revocation-sensitive paths.
- Caps: 4 concurrent computes per tenant per broker replica, 32 global per replica; circuit open (5 consecutive errors or p99 >50 ms/30 s) → 2 and 16, excess 503 `ANALYTICS_BUSY` `Retry-After: 2`.
- ACL users per component with key patterns; `allkeys-lru`; TLS + AUTH. ACLs cannot separate tenants inside one component; tenant separation relies on `packages/cache` building keys only from `AuthorizedContext` (tested).

## Appendix E — Invitation flow
1. `POST /v1/invitations` (Idempotency-Key) → delegation + quota checks → token = 32 random bytes (base64url), store SHA-256 → outbox → email link `https://<app>/invite#t=<token>` (`Referrer-Policy: no-referrer` on the page).
2. Invitee signs in (or signs up and verifies email; SSO-enforced tenant → via its IdP). Page reads the fragment, calls `POST /v1/invitations:accept {token}`, then `history.replaceState` removes it.
3. Server: `UPDATE identity.invitations SET status='ACCEPTED', accepted_by=$subject, accepted_at=now() WHERE token_hash=$h AND status='PENDING' AND expires_at > now() RETURNING …` inside a transaction that also (a) checks verified email equality (NFKC + casefold, no plus-address folding) or tenant-IdP session, (b) re-validates the inviter still holds delegation for the granted role/scope, (c) creates membership + grants, bumps epoch, emits `authz.profile.provision_requested`, audits.
4. Errors: unknown/expired/revoked/rotated token → uniform 410 `INVITE_INVALID`; email mismatch → 403 `INVITE_EMAIL_MISMATCH`; inviter lost rights → 409 `INVITE_INVALIDATED`; already member → 409 `ALREADY_MEMBER`; same subject re-accepting → 200 with the existing membership. Rate limit 5 accept attempts/min/subject.

## Appendix F — Subscription and entitlement model (launch.md canonical)
**Superseded by RECONCILIATION U-08/C-08:** plans, entitlements and admission are LCH-101's; the canonical subscription state machine and effect matrix are LCH-001's (`LCH.md` G-LCH-03). Kept for reference only; CTL-007 implements none of it.

States: `TRIAL → ACTIVE_PENDING_PAYMENT → ACTIVE_PAID`; `ACTIVE_PAID → PAST_DUE → ACTIVE_PAID | SUSPENDED`; `SUSPENDED → ACTIVE_PAID`; any → `CANCELLED` (effective date). Transitions only by internal console roles (`finance_operator`), with payment-event evidence for `ACTIVE_PAID`; corrections need a second operator.

| State | New connections/backfills/jobs | Interactive reads | Exports | Scheduled reports |
|---|---|---|---|---|
| TRIAL | within trial quotas | yes | yes | yes |
| ACTIVE_PENDING_PAYMENT / ACTIVE_PAID | within plan quotas | yes | yes | yes |
| PAST_DUE | within quotas (grace, Q2) | yes | yes | yes |
| SUSPENDED | no | per grace flag (read-only) | yes during export window | paused |
| CANCELLED | no | export window only | yes during window | stopped |

Plan-agnostic quotas (D-17): `connected_accounts`, `users`, `history_days`, `report_schedules`, `api_clients`, `heavy_jobs_concurrent`. `commercial.payment_events` unique `(tenant_id, external_ref)`; `commercial.plans` versioned; `entitlement_snapshots` record the effective quotas per revision for admission decisions and audit.

## Appendix G — Config publication (D-04)
Snowflake `CONFIG.CONFIG_VERSION(TENANT_ID, CONFIG_KIND, CONFIG_VERSION, PARENT_VERSION, SCHEMA_VERSION, CONTENT_SHA256, ROW_COUNT, APPROVAL_ID, PUBLISHED_AT, PUBLISHER_RUN_ID, FENCING_TOKEN)`; kind tables carry `(TENANT_ID, CONFIG_KIND, CONFIG_VERSION, ROW_KEY, …)`. Publisher (single per tenant/kind via lease) runs `BEGIN; INSERT rows; INSERT header; COMMIT;` A version is readable only when its header exists and `ROW_COUNT`/hash match (dbt test). Duplicate identical rows (retry after an ambiguous commit) are removed by staging dedup on `(TENANT_ID, CONFIG_KIND, CONFIG_VERSION, ROW_KEY)` with content equality; conflicting content fails the build. PG state: `PENDING_PUBLICATION → PUBLISHED | FAILED`. Archive: `s3://<config-archive>/config/{env}/{tenant}/{kind}/{version}.json.gz`.

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
| Control OpenAPI | Tenants/members/grants/invitations/teams/organizations/accounts/saved views/dashboards/config publications/entitlements paths with If-Match/Idempotency-Key semantics | CTL-003-S01, CTL-001-S09, CTL-007-S03 |
| Pool budget manifest | `infra/db/pool-budget.yaml` per component (replicas_max, surge factor, processes, pool_size, max_overflow, role, DB) + CI rule | CTL-002-S08 |
| Expand/contract protocol | Appendix C rules + migration linter configuration | CTL-002-S01 |
| Redis key/value contract | Appendix D key families, envelope schema, TTL classes, caps, ACL users | CTL-006-S01 |
| Config snapshot contract | Snowflake `CONFIG.*` DDL, header/commit-marker rules, S3 archive key format, PG publication states | CTL-005-S01/S02 |
| Tenant and subscription state machines | Appendix F + CTL-102 transitions, guards and effects matrix | CTL-102-S01, CTL-007-S07 |
| Control ERD | `docs/data/control-erd.md` generated from migrations | CTL-001-S10 |

## 4. Revised production backlog

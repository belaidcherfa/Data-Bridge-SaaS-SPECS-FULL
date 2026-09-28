# PostgreSQL control plane, transactional APIs and Redis

Canonical domain contract. Owner: Backend. Implementation state: NOT_STARTED.


## Canonical control schema

All tenant-owned tables include tenant_id, UUID id, created_at, updated_at, revision bigint and composite unique `(tenant_id,id)`. Parent FKs include tenant_id. Migrations are Alembic, expand→backfill→switch→contract; destructive changes wait until all old workers are drained. Initial identity/RLS tables originate in SEC-004; this domain extends them. (amended 2026-09-28, G-CTL-01, G-CTL-02, G-SEC-11) The **kernel tables** — `platform.outbox`, `platform.idempotency_requests`, `audit.events`, `platform.leases`, `platform.component_heartbeats`, `platform.consumed_events`, the `emit_event()`/`emit_audit()` unit of work, `tenant_transaction()` and the migration runner — are created by CTL-101 right after the database exists and before SEC-004, which removes the hidden outbox cycle; every table follows the CTL-101 template (tenant_id first, `UNIQUE(tenant_id, id)`, composite foreign keys, `revision bigint`, text + CHECK instead of PostgreSQL enums, RLS and grants in the same migration). Reviewed DDL per schema is the first step of each owning task ([CTL backlog](../22-implementation-readiness/backlog/CTL.md)).

| Schema | Tables and durable responsibility |
|---|---|
| identity | subjects, tenants, memberships, teams, team_members, role_grants, sessions |
| connection | organizations, accounts, account_membership_history, connections, capability_observations |
| sync | source_config, planned_windows, batch_attempts, batch_files, coverage_intervals, leases, replay_requests |
| governance | dimension_definitions, tag_rules, allocation_rules, ruleset_versions, usage_group_sets, budgets |
| monitor | definitions, destinations, incident_workflow, notification_outbox, delivery_attempts |
| report | definitions, schedules, report_jobs, artifact_metadata, saved_views, dashboards |
| workflow | analysis_jobs, insight_state, actions, action_transitions |
| commercial | plans and tenant_entitlements (LCH-101), subscriptions with the canonical PILOT → ACTIVE_PENDING_PAYMENT → ACTIVE_PAID machine, invoice_refs and payment_events (LCH-001) — owned by LCH, not CTL (amended 2026-09-28, U-08, C-08, D-17) |
| audit | events and export manifests |
| platform | outbox, idempotency_requests, leases, component_heartbeats, consumed_events, dataset_publication_refs, feature_flags (kernel from CTL-101) |
| privacy | identity_dictionary (SEC-103, D-10), tombstones (OPS-104; mirrored to S3 outside restore scope), deletion_requests/stages and legal_holds (OPS-005) — added 2026-09-28 |

Analytical monitor observations, forecasts, allocations, costs and savings remain in Snowflake. PostgreSQL can hold workflow IDs, status, bounded counts/checksums and links to analytical snapshots, never an analytical fact mirror.

## API and transaction contract

`POST` mutations accept `Idempotency-Key`; (amended 2026-09-28, G-CTL-04) the record is unique on `(tenant_id, principal_id, route_key, idem_key)`, written in the same transaction as the mutation, kept 24 h and required on resource-creating POSTs and job submissions; a concurrent duplicate waits on the key and then replays the stored 2xx response with `Idempotent-Replayed: true`; same key/different body returns 409 `IDEMPOTENCY_KEY_REUSED`. PATCH requires `If-Match` with the revision; a stale revision returns **412** `STALE_REVISION` and a missing precondition **428** `PRECONDITION_REQUIRED` (RFC 9110; replaces the earlier 409). Transaction commits object change, audit and outbox together. Response errors use `code`, `message`, `request_id`, `retryable`, field errors; no database text. Foreign object lookup returns non-enumerating 404. Lists use bounded keyset pagination, never unbounded offsets.

Outbox dispatcher claims with `FOR UPDATE SKIP LOCKED`, fenced lease and attempt schedule; side effect identity is event_id. (amended 2026-09-28, G-CTL-03) Event types marked `ordering=AGGREGATE` are dispatched in per-aggregate order (`aggregate_seq` plus a head-of-line predicate; a dead predecessor blocks only its aggregate and pages) and published to SQS FIFO with `MessageGroupId` = aggregate and `MessageDeduplicationId` = event_id; unordered events use standard queues with consumer-side deduplication in `platform.consumed_events`; backoff `min(5 s·2^n, 1 h) ±20 %`, 12 attempts; DONE rows are deleted after 7 days ([CTL backlog](../22-implementation-readiness/backlog/CTL.md) Appendix A). PostgreSQL is source of configuration truth; (amended 2026-09-28, D-04) immutable versions are written directly by the insert-only `config-publisher` WIF identity into Snowflake `CONFIG.*` (rows plus a header commit marker) with an S3 archival copy, not through S3/Snowpipe ([ADR-007 amendment](../architecture/adr/ADR-007-rule-publication.md)), and the API shows PENDING_PUBLICATION until the header exists. No synchronous PostgreSQL/Snowflake dual-write claims.

## Connection strategy and indexes

Use SQLAlchemy/asyncpg with bounded pools, transaction-local tenant context and timeouts. Define per-component maximum connections × maximum replicas, reserve >=30% for failover/admin, and verify against actual Aurora limits. (amended 2026-09-28, G-CTL-05) The committed pool-budget manifest checks `Σ replicas_max × deploy_surge × processes × (pool_size + max_overflow) ≤ 0.70 × measured max_connections` in CI against Terraform autoscaling maxima, including Dagster run workers and the doubled task sets of rolling deploys. Dagster has separate database/user and independent budget. Use tenant-leading indexes on status/time/account/resource scope; JSONB GIN indexes only after an observed query need. Explain plans must avoid accidental whole-tenant scans for key lookups. Worker leases use DB time, fencing token and expiry; Redis never decides ownership. (amended 2026-09-28, G-CTL-06, G-CTL-12, C-16) Every protected write calls `platform.assert_fence(kind, key, token)` inside its transaction (SQLSTATE `BL001 LEASE_LOST` otherwise); external artifacts (manifests, config rows) carry the token. Contract migrations are refused while any heartbeat in `platform.component_heartbeats` (last 15 min) reports an older maximum schema revision; concurrent index builds run outside transaction blocks; `lock_timeout=3s` with 5 retries.

## Cache contract

`bridge:v1:{environment}:{tenant}:{profile}:{permission_epoch}:{dataset}:{dataset_version}:{metric_version}:{currency}:{privacy_mode}:{canonical_filter_hash}`. (amended 2026-09-28, G-CTL-07, G-API-17, D-02) `{profile}` is the first 16 hex of the immutable profile hash (full hash checked in the value envelope); `{permission_epoch}` is the tenant data-visibility epoch `tenants.authz_epoch`, not the member's epoch; the data version is publication-consistent (the pinned publication of the response, so tiles of one page cannot mix publications); grain and period live in the request digest ([CTL backlog](../22-implementation-readiness/backlog/CTL.md) Appendix D, [API backlog](../22-implementation-readiness/backlog/API.md) G-API-17). Sessions, CSRF secrets, permissions, leases, job and outbox state are never stored in Redis. Caps: 4 concurrent computes per tenant and 32 per broker replica, halved when the cache circuit opens; excess returns 503 `ANALYTICS_BUSY` with `Retry-After: 2`. PRD §64's `finops:{tenant}:home:…` key example is refined by this contract (it has no profile). Canonical filters sort set-like members and preserve order-sensitive clauses; hash collisions are guarded by stored request digest. Navigation TTL 600s; recent KPI 120s; historical KPI 1800s; small configuration 300s. These are initial product defaults, not vendor requirements.

Check authorization before reading cache; never cache permissions as final truth. Use single-flight best-effort locks to reduce duplicate reads; correctness survives Redis loss. Stale-while-revalidate only for same authorized dataset, with visible as-of and a maximum stale age; never for revocation or chargeback close. Dataset publication and scope revision make old keys unreachable. Protect against cache stampedes with bounded concurrency, jitter and Snowflake query budget. Redis ACLs limit service key patterns; TLS required.


## Implementation sequence

(amended 2026-09-28) The dependency and gate columns below are the original index. Execution follows the revised graph ([revised-task-graph.json](../22-implementation-readiness/revised-task-graph.json), [revised critical path](../22-implementation-readiness/REVISED_CRITICAL_PATH.md)) and phases P0–P6 of the [release plan](../22-implementation-readiness/RELEASE_PLAN.md); new tasks, revised steps, dependencies and task acceptance are in [backlog/CTL.md](../22-implementation-readiness/backlog/CTL.md).

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [CTL-001](../tasks/CTL/CTL-001.md) | Extend tenant, organization, account and team schemas | SEC-004 | M1 |
| [CTL-002](../tasks/CTL/CTL-002.md) | Implement migrations, indexes and bounded connection pools | CTL-001, INF-004 | M1 |
| [CTL-003](../tasks/CTL/CTL-003.md) | Create scoped CRUD, invitations and optimistic concurrency | CTL-001, SEC-002, SEC-008, UX-001 | M1 |
| [CTL-004](../tasks/CTL/CTL-004.md) | Implement transactional outbox and fenced job leases | CTL-002, CTL-003 | M1 |
| [CTL-005](../tasks/CTL/CTL-005.md) | Publish immutable analytical configuration snapshots | CTL-004, INF-003 | M1 |
| [CTL-006](../tasks/CTL/CTL-006.md) | Implement scoped Redis keys and safe degradation | CTL-004, SEC-006 | M1 |
| [CTL-007](../tasks/CTL/CTL-007.md) | Add saved views, dashboards and commercial control records (amended 2026-09-28: commercial records moved to LCH-101/LCH-001, U-08; dashboards builder R2 in UX-101/RPT-103, U-01) | CTL-003, CTL-005, UX-001 | M1 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

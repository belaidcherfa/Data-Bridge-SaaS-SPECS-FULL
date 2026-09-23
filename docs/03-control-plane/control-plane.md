# PostgreSQL control plane, transactional APIs and Redis

Canonical domain contract. Owner: Backend. Implementation state: NOT_STARTED.


## Canonical control schema

All tenant-owned tables include tenant_id, UUID id, created_at, updated_at, revision bigint and composite unique `(tenant_id,id)`. Parent FKs include tenant_id. Migrations are Alembic, expand→backfill→switch→contract; destructive changes wait until all old workers are drained. Initial identity/RLS tables originate in SEC-004; this domain extends them.

| Schema | Tables and durable responsibility |
|---|---|
| identity | subjects, tenants, memberships, teams, team_members, role_grants, sessions |
| connection | organizations, accounts, account_membership_history, connections, capability_observations |
| sync | source_config, planned_windows, batch_attempts, batch_files, coverage_intervals, leases, replay_requests |
| governance | dimension_definitions, tag_rules, allocation_rules, ruleset_versions, usage_group_sets, budgets |
| monitor | definitions, destinations, incident_workflow, notification_outbox, delivery_attempts |
| report | definitions, schedules, report_jobs, artifact_metadata, saved_views, dashboards |
| workflow | analysis_jobs, insight_state, actions, action_transitions |
| commercial | subscriptions, entitlements, invoices_metadata, payment_events |
| audit | events and export manifests |
| platform | outbox, idempotency_requests, dataset_publication_refs, feature_flags |

Analytical monitor observations, forecasts, allocations, costs and savings remain in Snowflake. PostgreSQL can hold workflow IDs, status, bounded counts/checksums and links to analytical snapshots, never an analytical fact mirror.

## API and transaction contract

`POST` mutations accept `Idempotency-Key`; unique `(tenant_id, route, key)` stores request hash and result reference. Same key/different body returns 409. PATCH requires revision/If-Match; stale revision returns 409. Transaction commits object change, audit and outbox together. Response errors use `code`, `message`, `request_id`, `retryable`, field errors; no database text. Foreign object lookup returns non-enumerating 404. Lists use bounded keyset pagination, never unbounded offsets.

Outbox dispatcher claims with `FOR UPDATE SKIP LOCKED`, fenced lease and attempt schedule; side effect identity is event_id. PostgreSQL is source of configuration truth; snapshots are immutable versioned exports to S3/Snowpipe, and API shows PENDING_PUBLICATION until central acceptance. No synchronous PostgreSQL/Snowflake dual-write claims.

## Connection strategy and indexes

Use SQLAlchemy/asyncpg with bounded pools, transaction-local tenant context and timeouts. Define per-component maximum connections × maximum replicas, reserve >=30% for failover/admin, and verify against actual Aurora limits. Dagster has separate database/user and independent budget. Use tenant-leading indexes on status/time/account/resource scope; JSONB GIN indexes only after an observed query need. Explain plans must avoid accidental whole-tenant scans for key lookups. Worker leases use DB time, fencing token and expiry; Redis never decides ownership.

## Cache contract

`bridge:v1:{environment}:{tenant}:{profile}:{permission_epoch}:{dataset}:{dataset_version}:{metric_version}:{currency}:{privacy_mode}:{canonical_filter_hash}`. Canonical filters sort set-like members and preserve order-sensitive clauses; hash collisions are guarded by stored request digest. Navigation TTL 600s; recent KPI 120s; historical KPI 1800s; small configuration 300s. These are initial product defaults, not vendor requirements.

Check authorization before reading cache; never cache permissions as final truth. Use single-flight best-effort locks to reduce duplicate reads; correctness survives Redis loss. Stale-while-revalidate only for same authorized dataset, with visible as-of and a maximum stale age; never for revocation or chargeback close. Dataset publication and scope revision make old keys unreachable. Protect against cache stampedes with bounded concurrency, jitter and Snowflake query budget. Redis ACLs limit service key patterns; TLS required.


## Implementation sequence

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [CTL-001](../tasks/CTL/CTL-001.md) | Extend tenant, organization, account and team schemas | SEC-004 | M1 |
| [CTL-002](../tasks/CTL/CTL-002.md) | Implement migrations, indexes and bounded connection pools | CTL-001, INF-004 | M1 |
| [CTL-003](../tasks/CTL/CTL-003.md) | Create scoped CRUD, invitations and optimistic concurrency | CTL-001, SEC-002, SEC-008 | M1 |
| [CTL-004](../tasks/CTL/CTL-004.md) | Implement transactional outbox and fenced job leases | CTL-002, CTL-003 | M1 |
| [CTL-005](../tasks/CTL/CTL-005.md) | Publish immutable analytical configuration snapshots | CTL-004, INF-003 | M1 |
| [CTL-006](../tasks/CTL/CTL-006.md) | Implement scoped Redis keys and safe degradation | CTL-004, SEC-006 | M1 |
| [CTL-007](../tasks/CTL/CTL-007.md) | Add saved views, dashboards and commercial control records | CTL-003, CTL-005 | M1 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

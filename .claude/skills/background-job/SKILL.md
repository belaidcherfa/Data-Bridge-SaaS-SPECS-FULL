---
name: background-job
description: Implement a durable background job, worker, Dagster asset/sensor or outbox consumer for Bridge — PostgreSQL job claiming, leases, idempotency, retries with classified errors, tenant context, fairness, cancellation, observability and tests. Use for API-004 workers, exports/reports (D-33), extraction launcher (D-07), notifications, GC, reconcilers and outbox dispatch.
---

# Background jobs and workers

Read ADR-007 (+ amendment: Dagster only enqueues, the account-cycle launcher runs extraction), D-29 (steady-state first, fair backfill), D-33 (long-lived workers claiming PG jobs), the owning backlog section, and the job's state machine.

## Claiming and leases
- Jobs are rows (`workflow.job` or the domain table) with `status`, `attempt`, `lease_owner`, `lease_expires_at`, `idempotency_key`, `tenant_id`, `priority`, `not_before`.
- Claim with `SELECT … FOR UPDATE SKIP LOCKED` ordered by (priority, fair-share key, created_at) in a short transaction, set the lease, commit, then work. Renew the lease periodically; a lost lease means stop without side effects (fencing token checked on every externally visible write).
- Fairness: per-tenant concurrency caps and round-robin across tenants so one tenant's backfill cannot starve others (D-29).

## Execution
- Set tenant context (`app.tenant_id`, broker identity) from the job row before any read; refuse jobs of suspended/offboarding tenants per their state machine.
- Idempotent effects: deterministic output keys (UUIDv5), upserts on natural keys, outbox events with stable `event_id`, external sends deduplicated by idempotency key (webhooks carry `webhook-id`).
- Errors: classify `TRANSIENT` (retry with exponential backoff + jitter, capped attempts), `PERMANENT` (fail with problem code, no retry), `CUSTOMER_ACTION` (connection/privilege issue → capability status + notification, not a page to on-call). Never retry on an unknown exception more than the cap; dead-letter with context.
- Cancellation: check a cancel flag between steps; partial outputs are discarded or marked unpublished.
- Dagster: sensors/schedules only enqueue or trigger dbt builds with `build_id`; never pass customer roles or credentials through Dagster run config.

## Observability
Metrics: queue depth and age per job type, claim latency, attempts, outcomes by error class, per-tenant fairness; structured logs with job_id/tenant_id; an alert with runbook for stuck leases and DLQ growth (skill `observability-and-runbooks`).

## Tests
Concurrent claimers never process the same job (two workers, one job); lease expiry recovery; retry idempotency (kill after side effect, re-run, single effect); fairness under a 10:1 tenant skew; cancellation; tenant-isolation rows for jobs.

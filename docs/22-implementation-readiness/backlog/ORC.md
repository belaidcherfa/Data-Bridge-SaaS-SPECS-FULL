# ORC — Implementation-readiness review and production backlog

Canonical contract: [orchestration.md](../../06-dagster/orchestration.md). Related: [ADR-006](../../architecture/adr/ADR-006-batch-commit-and-coverage.md), [ADR-007](../../architecture/adr/ADR-007-rule-publication.md), [ADR-008](../../architecture/adr/ADR-008-queues-and-orchestration.md), [ADR-011](../../architecture/adr/ADR-011-analytical-recovery.md), [DBT backlog](DBT.md) (physical revision model DBT-101 is shared). Tasks reviewed: ORC-001, ORC-002, ORC-003, ORC-004, ORC-005, ORC-006. Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

## 1. Verdict

Not implementable as specified. The architecture intent (generic assets, durable PostgreSQL leases, candidate revisions + pointer publication) is right, but the six tasks leave the three hardest mechanisms undefined: (1) the **run model at scale** — the spec's "dynamic connection/source dimension" plus "1 per account-source" implies ~240,000 Dagster runs/Fargate tasks per day at 500 accounts and >100k partitions per asset; (2) the **publication transaction** — no tables, no CAS, no multi-tenant batching, no fencing against zombie builds, no definition of how a pin or `dataset_version` is derived; (3) the **processing ledger** that turns "accepted batches" into a consistent multi-tenant dbt build (D-06). A verified vendor fact adds a security blocker: dagster-aws `EcsRunLauncher` sets a per-run task role only through user-writable run tags. Author DBT-101 (physical revision/publication ADR) and ORC-101 (processing ledger/workset) before ORC-004/005; implement a custom launcher in ORC-001. Realistic effort: ~320–458 h R1 (vs 12–36 h implied by the 2–6 h/task sizing).

## 2. Findings

### G-ORC-01 · Run and partition model does not scale; adopt account-cycle runs and no tenant partitions
Severity: BLOCKER · Type: RISK
Evidence: `docs/06-dagster/orchestration.md` — "Use source-family assets with daily time partitions and a bounded dynamic connection/source dimension" and "steady-state extraction 8 total/2 per tenant/1 per account-source". Computation: one run per (account, source, window) at 500 accounts × 20 sources × 24 windows/day = **240,000 runs/day** (2.8/s average; Fargate launch bucket is 100 burst / 20 per s sustained and 1,000 concurrent tasks by default — VERIFIED via search snippet of docs.aws.amazon.com/AmazonECS/latest/developerguide/throttling.html, 2026-09-27). At ~2 billed min per task (Fargate bills a 1-min minimum; ~45 s image pull/provisioning + ~15 s run-worker bootstrap + short query) with 1 vCPU/2 GB at us-east-1 list $0.04048/vCPU-h + $0.004445/GB-h (EU ~10% higher; TO VERIFY LIVE for eu-west-1): 480,000 task-min × $0.000823 = **~$395/day ≈ $11.9k/month**, ~75% of it start-up overhead. Partitions: 500 accounts × 365 days = **182,500 partitions per asset**, above Dagster's recommended ≤100,000 per asset (VERIFIED via search snippet of docs.dagster.io/guides/build/partitions-and-backfills/partitioning-assets, 2026-09-27). Customer side: 20 separately spaced sessions/hour each bill ≥60 s on resume (VERIFIED via search snippet of docs.snowflake.com/en/user-guide/cost-understanding-compute) + 60 s auto-suspend ≈ 40 XS-min/h ≈ 480 credits/account/month vs ≈ 48 for one hourly cycle.
Why it matters: metadata DB, launch throttling, UI unusability and a 10× cost multiplier on both Bridge and customer bills.
Resolution (D-07, D-08): one Dagster run = one ECS task per **account-cycle** (all due sources, one warehouse resume): 500 × 24 = 12,000 runs/day, ~4 min each → 48,000 task-min ≈ $39.5/day. No Dagster partitions on tenant/account/connection; coverage stays in PostgreSQL (ADR-006). Extraction/ingestion assets are **observations** (never global materializations); daily time partitions are allowed only for global maintenance assets (purge, GC, recovery snapshot, cost collection). Backfills run as `backfill_chunk_job` runs sized to 15–30 min of work. Receipt/acceptance processing runs in the long-lived ingestion service (ING-007), not as Dagster runs every 2 minutes.
Affects: ORC-002, ORC-003, ING-007, ING-010, OPS-008.

### G-ORC-02 · Concurrency budgets contradict the target scale (Little's law)
Severity: HIGH · Type: CONTRADICTION
Evidence: `orchestration.md` — "steady-state extraction 8 total"; PRD §16 — "normal extraction 50"; `operations.md` — "publish fresh accepted data within30min after source availability".
Why it matters: required concurrency = arrival rate × duration = 500 cycles/h × 4/60 h = **33 concurrent** on average. A cap of 8 serves at most 8 × 60/4 = 120 hourly accounts; beyond that queue age grows without bound and the 30-min freshness target fails. If all accounts fire at :00 the peak is 500 simultaneous.
Resolution: stagger each account's cycle minute by `hash(account_id) mod 60` (≤ ceil(500/60) = 9 starts/min); steady lane cap 60 (1.8× headroom), per tenant 6, per account 1; backfill lane 12 total/4 per tenant, admitted only while steady p95 queue age < 5 min; dbt steady lane 1 build at a time, repair/shadow lane 1. Record the formula in `services/orchestrator/admission/capacity.md` and recompute from measured cycle duration in OPS-008.
Affects: ORC-003, OPS-008.

### G-ORC-03 · EcsRunLauncher per-run task role is only settable through user-writable run tags
Severity: BLOCKER · Type: VENDOR-FACT
Evidence: VERIFIED (github.com/dagster-io/dagster `python_modules/libraries/dagster-aws/dagster_aws/ecs/launcher.py`, master, 2026-09-27): `_get_task_overrides` does `overrides = json.loads(run.tags.get("ecs/task_overrides"))` and merges it into RunTask `overrides` (ECS `TaskOverride.taskRoleArn` is a valid field); `ecs/run_task_kwargs` is likewise merged; otherwise `task_role_arn` comes from the launcher or code-location `container_context` (one role per code location). `orchestration.md` only says "after validating its pinned configuration and task-role behavior"; ADR-004 says "An allowlisted launcher resolves connection_id to role/task definition".
Why it matters: the daemon must hold `iam:PassRole` on every customer extraction role; anyone able to launch a run (UI, GraphQL) with a crafted `ecs/task_overrides` tag can run code-location code under another customer's WIF role — a cross-tenant credential exposure.
Resolution: (a) `BridgeEcsRunLauncher` subclass (dagster-aws pinned) that **rejects** runs carrying `ecs/task_overrides`, `ecs/run_task_kwargs`, `ecs/container_overrides` and derives `taskRoleArn` for `account_cycle_job`/`backfill_chunk_job` from PostgreSQL `connection.connections` by the run-config `connection_id`; contract test on the overridden private methods; fallback is a from-scratch launcher (~300 lines). (b) Webserver for engineers runs `--read-only` (VERIFIED flag in `dagster_webserver/cli.py`); a writable break-glass webserver is scaled to 0. (c) The run must claim a PostgreSQL cycle row created by the sensor with its own `run_id` or exit without extraction. (d) In-task STS self-check: assumed-role name must equal the registered role before any Snowflake connection. (e) `iam:PassRole` limited to `bridge-ext-*`/`bridge-run-*` with `iam:PassedToService=ecs-tasks.amazonaws.com`.
Affects: ORC-001, ORC-003, CON-001, SEC-005.

### G-ORC-04 · No run/event retention exists in Dagster OSS; sensor dedupe silently depends on retained runs
Severity: HIGH · Type: VENDOR-FACT
Evidence: VERIFIED (github.com/dagster-io/dagster `_core/instance/config.py`, 2026-09-27): `retention` schema only has `schedule`, `sensor`, `auto_materialize` tick `purge_after_days`; run deletion is `instance.delete_run` (VERIFIED via search snippet of docs.dagster.io/deployment/troubleshooting/database-tuning). Sensor run-key dedupe queries stored runs by `RUN_KEY_TAG` (VERIFIED `_daemon/sensor.py` line ~1310). ADR-008 revisit condition "database event growth exceeds budget" has no budget.
Why it matters: estimated growth with the recommended model: extraction 12,000 runs × ~60 events + dbt 96 builds × ~3,000 events (400 models × materialization + check evaluations + logs) + others ≈ **1.1M event rows/day** (≈ 33M rows ≈ 50 GB at 30 days, unbounded otherwise). Purging runs also removes run-key history, so a replayed run key after purge launches again.
Resolution: ORC-102 purge job (extraction success 14 d, dbt/publication success 30 d, failures 90 d, keep latest success per job), tick retention, compute-log lifecycle 30 d, storage alarm at 70% of a 50 GB budget; PostgreSQL cycle claim (G-ORC-03c) is the only idempotency authority.
Affects: ORC-001, ORC-003, ORC-102.

### G-ORC-05 · "One active daemon" is violated by default ECS rolling deployments; metadata DB shares control-plane blast radius
Severity: HIGH · Type: RISK
Evidence: `orchestration.md` — "one active daemon"; Dagster supports only one daemon at a time (heartbeat conflict warning; VERIFIED via search snippet of discuss.dagster.io "another sensor daemon is still sending heartbeat", 2026-09-27). ECS services default to minimumHealthyPercent 100 / maximumPercent 200, i.e., two tasks during deploy. `control-plane.md` — "Dagster has separate database/user and independent budget" (same Aurora cluster implied).
Why it matters: two daemons double-evaluate sensors and dequeue runs concurrently; Dagster event-log write bursts (G-ORC-04) compete with API transactions on the same Aurora writer.
Resolution: daemon ECS service desiredCount 1, minimumHealthyPercent 0, maximumPercent 100, circuit breaker; heartbeat-age alarm > 120 s; `run_monitoring` enabled (start timeout 300 s). Put `dagster_meta` on a separate Aurora Serverless v2 cluster (0.5–4 ACU, PITR 14 d) — owner cost approval (§7).
Affects: ORC-001.

### G-ORC-06 · Publication transaction is under-specified; DDL cannot participate
Severity: BLOCKER · Type: GAP
Evidence: `orchestration.md` — "one Snowflake transaction advances the tenant publication pointer. PostgreSQL holds only the reference/status via idempotent ack"; ORC-005 data model is one line. Snowflake: "If a DDL statement is executed while a transaction is active, the DDL statement implicitly commits the active transaction" (VERIFIED via search snippet of docs.snowflake.com/en/sql-reference/transactions, 2026-09-27). `semantic-api.md` — "Cursor binds … publication … an expired/retired snapshot returns explicit restart-required". `control-plane.md` cache key uses `{dataset_version}` while API meta returns `publication_id` — relation undefined.
Why it matters: implementers will reach for `CREATE OR REPLACE VIEW`/`ALTER TABLE SWAP` (DDL, auto-commit, not per-tenant), or per-tenant loops (500 tenants × ~5 statements ≈ 15+ min serial per build).
Resolution (DBT-101 DDL; ORC-005 implements): pointer = DML over `PUBLICATION.TENANT_POINTER`, SCD2 `PUBLICATION_MAP(tenant_id, dataset_id, scope_id, partition_start, revision_id, valid_from_seq, valid_to_seq)`, `DATASET_VERSION`, `PUBLICATION`, `CANDIDATE_CHANGE`, `BUILD`, `LANE_FENCE`. A single publisher (PostgreSQL lease) allocates a global monotonic `pub_seq` and calls one Snowflake Scripting procedure `PUBLISH_BATCH(pub_seq, build_id, fence_token)` that, in one DML-only transaction, verifies build status + fence, CAS-updates all eligible tenants' pointers set-based (row count must equal eligible count, else rollback), closes superseded map rows, inserts new ones, bumps `DATASET_VERSION` only for datasets that changed, and marks the publication PUBLISHED. Readers pin `pub_seq` and filter `_pub_from <= :pin AND :pin < _pub_to`. `dataset_version` = the `pub_seq` at which that tenant's dataset map last changed (unchanged datasets keep cache hits). PostgreSQL ack upserts `platform.dataset_publication_refs` monotonically + outbox `publication.advanced`; a reconciler replays missing acks from Snowflake and never writes Snowflake from PostgreSQL. Rollback (RB-07) is a **forward** publication re-pointing to old revisions; the pointer never decreases.
Affects: ORC-005, DBT-101, API-002, CTL-006, GOV-004, RPT-002, FIN-010, OPS-007.

### G-ORC-07 · No processing ledger; a multi-statement dbt build has no consistent input snapshot
Severity: HIGH · Type: GAP
Evidence: `ingestion.md` — "Accepted-batch registry is materialized in Snowflake … staging joins that registry" and state machine "RAW_ACCEPTED → TRANSFORMED → PUBLISHED"; D-06 requires "the set of accepted-but-unprocessed batches (processing ledger table)"; no task owns it.
Why it matters: each dbt statement reads the latest committed data, so batches accepted while a build runs are seen by some models and not others (e.g., `stg_wmh` includes hour 10, `ledger_idle` computed earlier does not) → non-reproducible, internally inconsistent candidates. A cursor over a sequence also loses batches when seq 10 commits after seq 11 (gap).
Resolution: ORC-101 — acceptance (ING-007) is single-writer and assigns `accepted_seq`; each build records `snapshot_seq = max(accepted_seq)` and every staging read filters `accepted_seq <= snapshot_seq`; planner anti-joins the processed set for all seq ≤ snapshot (gap-safe); `BATCH_PROCESSING` tracks PENDING/IN_BUILD/BUILT/PUBLISHED/GATED; `BUILD_WORKSET` lists exact partitions per build; `BUILD_CONFIG_PIN` pins config per tenant (D-04). Build trigger: oldest unprocessed ≥ 10 min or ≥ 500 batches → 30-min freshness = ≤10 wait + ≤15 build + ≤5 publish.
Affects: ORC-101, ORC-004, DBT-002, ING-007, ING-008.

### G-ORC-08 · Per-tenant failure isolation in set-based builds is not designed
Severity: HIGH · Type: GAP
Evidence: ORC-004 MT3 — "Fail one financial check and prove dependent publication/monitor/report assets do not execute while unrelated accepted scopes can proceed"; D-06 — "a failing tenant partition is excluded from that tenant's pointer advance".
Why it matters: in `dbt build`, an `error`-severity test failure skips all downstream models for **all** tenants; a SQL runtime error (overflow, bad cast) in one tenant's rows fails the model globally; `store_failures` tables are replaced per invocation, so concurrent lanes overwrite each other.
Resolution: tenant-scoped invariants are **check models** writing one PASS/FAIL row per (build, tenant, check) into `QUALITY.CHECK_RESULT` (absence = FAIL) and the gate reads that table, not Dagster check state; dbt tests stay `warn` for tenant-scoped rules and `error` only for structural rules. Model runtime errors trigger bisection: re-run the failing subtree in the repair lane with the workset split by tenant halves (≤ ⌈log2 n⌉+1 builds), isolate the poison tenant into `PUBLICATION.TENANT_QUARANTINE`, alert RB-07; tenants gated 3 consecutive builds are quarantined from the steady lane.
Affects: ORC-004, ORC-005, DBT-005.

### G-ORC-09 · Python outputs: "same journal/acceptance contracts" is disproportionate; query-grain classification is on the wrong side
Severity: HIGH · Type: OVER-ENGINEERING (challenges `intelligence.md` and PRD §55 ordering)
Evidence: `intelligence.md` — "materializes outputs through the same journal/acceptance contracts"; PRD §55 chains Python between dbt steps; WRK-001 outputs to `services/intelligence/workload_classifier` "keyed by query+parser version"; `allocation.md` — rules use "approved resource/query/session/workload metadata"; `security.md` — "AST-based SQL parser strips literals, unapproved comments … before Arrow/S3".
Why it matters: S3 journal + Snowpipe + receipt poller + accepted-batch registry for outputs that are reproducible from pinned canonical inputs adds ~3 components per engine; a query-grain Python classifier (up to 1M rows/account/day) feeding allocation would put a Python engine on the financial critical path and block ledger publication on its failure.
Resolution: (1) Deterministic workload classification (explicit tag → session client → approved comment fields → query type) is a dbt model; the extractor already parses SQL for sanitization and emits approved comment fields as structured columns (DBT-003 S06, coordinate with WRK-001/SEC-007). (2) Remaining Python outputs (forecast, anomaly/insight candidates, optimization scoring) are low-volume and use ORC-103 "light acceptance": Arrow→Parquet→`PUT` to a named internal stage keyed by `run_id`→`COPY INTO … FILES=(…)`→row-count/checksum check against a run manifest→revisioned insert. No Snowpipe, no receipt poller. `write_pandas` is rejected (pandas object dtype for decimals); Snowpark deferred (different runtime/package set). (3) Two-phase publication: core financial publication P (dbt only) → Python engines pinned to P → outputs published in P′ > P with `input_pub_seq = P` shown in UI. Python failure never blocks ledger publication.
Affects: ORC-004, ORC-103, WRK-001, GOV (forecast), INS-001.

### G-ORC-10 · Cancellation fencing cannot rely on PostgreSQL leases inside Snowflake
Severity: HIGH · Type: GAP
Evidence: ORC-006 oracle — "canceled task cannot publish with stale fence"; `orchestration.md` — "Cancellation fences work, stops new uploads/publications".
Why it matters: the publish transaction runs in Snowflake and cannot read PostgreSQL; a paused/zombie ECS task resuming after a newer build started would publish stale revisions.
Resolution: after acquiring the PostgreSQL lane lease (token t), the build writes `LANE_FENCE.fence_token = t` (monotonic) and `BUILD(build_id, fence_token=t, status=RUNNING)`; `PUBLISH_BATCH` requires `BUILD.status='VALIDATED'` and `BUILD.fence_token = LANE_FENCE.fence_token` inside the transaction. Cancel path: ECS StopTask with `stopTimeout` 120 s (Fargate maximum — TO VERIFY LIVE) → dagster-dbt terminates dbt → dbt-snowflake issues `select system$cancel_all_queries(<session>)` (VERIFIED `dbt-snowflake/src/dbt/adapters/snowflake/connections.py` `cancel()`, 2026-09-27) → handler sets BUILD CANCELLED; a reaper cancels any query whose `QUERY_TAG.build_id` belongs to a terminal build after 5 min. Extraction: SIGTERM cancels the source query and suppresses manifest publication.
Affects: ORC-005, ORC-006.

### G-ORC-11 · Central Snowflake cost per tenant is unattributable for multi-tenant builds
Severity: MEDIUM · Type: GAP
Evidence: `operations.md` — "Shared cost allocation uses declared drivers and an explicit unallocated bucket"; OPS-009 — "allocate shared costs by declared drivers"; a query tag cannot name one tenant in a set-based build (D-06).
Resolution: ORC-104 — query tag JSON `{app, env, lane, build_id, model, layer}`; per-query credits from central `QUERY_ATTRIBUTION_HISTORY` (TO VERIFY LIVE latency) → credits per (build, model); driver = rows written per tenant per model from `PARTITION_REVISION.row_count` (no extra scan); zero-row models by workset partition share; warehouse idle → `UNALLOCATED_IDLE`. Fixture: model 10 credits, A 700 rows, B 300 → A 7, B 3; idle 2 → unallocated 2; allocated + unallocated = 12 = metered. Snowpipe credits by bytes per file with tenant from the `tenant_id=` path segment; broker queries carry tenant in the tag.
Affects: ORC-104, OPS-009.

### G-ORC-12 · Dependency inversions and over-serialization
Severity: HIGH · Type: CONTRADICTION
Evidence: `TASK_INDEX.md` — "DBT-001 … ORC-004, ING-008"; ORC-004 MT1 — "Load the dbt manifest". ORC-004 ← ING-009 (schema drift); ORC-002 ← ING-008; API-004 ← ORC-006.
Why it matters: ORC-004 cannot load a manifest that DBT-001 has not produced — the edge is inverted, and it pushes the entire dbt/FIN chain behind ORC-001…004 (4 serial tasks, ~130–190 h).
Resolution: DBT-001 −ORC-004 −ING-008 +CON-002 +INF-008 +FND-004; ORC-004 +DBT-001 +DBT-002 +DBT-101 +ORC-101 −ING-009; ORC-002 −ING-008 +ING-001 (contract; evidence step needs ING-005); ORC-003 +ING-002 +CON-001; ORC-005 +DBT-101 +ORC-101 +SEC-005; ORC-006 +ORC-105; API-004 −ORC-006 +ORC-005; INS-001/GOV forecast +ORC-103; OPS-009 +ORC-104; OPS-007 +ORC-105.
Affects: all ORC tasks, DBT-001, API-004, INS-001, OPS-007, OPS-009.

### G-ORC-13 · Revision retention, pins and garbage collection have no owner
Severity: MEDIUM · Type: GAP
Evidence: `orchestration.md` — "Old revisions remain while active jobs/statements reference them, then expire under retention"; ORC-005 failure list — "GC deletes referenced revision"; RB-07 — "repoint to prior compatible accepted revision".
Why it matters: without GC, read amplification grows with every build (superseded revisions are joined and discarded); with naive GC, closed statements and running reports lose evidence; RB-07 needs old revisions to exist.
Resolution: ORC-105 — explicit pins only for long-lived holders (report/analysis job, statement, recovery snapshot, operator hold); API cursors rely on a grace window (≥ cursor TTL + 15 min); superseded revisions retained ≥ 7-day rollback window (owner question); orphan revisions of failed builds GC'd after 24 h; purged pins answer `RESTART_REQUIRED`.
Affects: ORC-105, ORC-005, FIN-010, API-002, OPS-007.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by (task/micro-task) |
|---|---|---|
| `services/orchestrator/dagster.yaml` + `workspace.yaml` | Postgres storage env refs; `concurrency.runs` tag limits (lane steady 60, backfill 12, dbt 2, python 2, report 4, tenant applyLimitPerUniqueValue 6); `run_monitoring`; tick retention; S3 compute logs; `BridgeEcsRunLauncher` | ORC-001-S01, ORC-003-S06 |
| Launcher contract | Rejected tags list; role resolution query; audit event `LAUNCH_REJECTED_FORGED_TAG`; STS self-check error `IDENTITY_MISMATCH` | ORC-001-S05/S07 |
| PostgreSQL `sync.account_cycles`, `sync.lane_budget`, `sync.tenant_weight` | Columns/unique keys per ORC-003-S01; status enum PLANNED/SUBMITTED/RUNNING/SUCCEEDED/PARTIAL/FAILED/CANCELLED/SKIPPED_DUPLICATE | ORC-003-S01 |
| Error-class catalog | TRANSIENT/AUTH/CUSTOMER_QUOTA/SCHEMA/CANCELLED/INTERNAL with retry policy and Snowflake/AWS error-code mapping (codes TO VERIFY LIVE) | ORC-003-S07 |
| `data/contracts/dagster_metadata.json` | JSON Schema of observation/materialization metadata (tenant_id, account_id, source, window, batch_id, accepted_seq, build_id, snapshot_seq) | ORC-002-S10 |
| Processing-ledger DDL | `ACCEPTED_BATCH.accepted_seq`, `BATCH_PROCESSING`, `BUILD_WORKSET`, `BUILD_CONFIG_PIN`, `DATASET_PARTITION_RULE`, `TENANT_QUARANTINE` | ORC-101-S02 |
| Publication DDL + procedure | `TENANT_POINTER`, `PUBLICATION`, `PUBLICATION_MAP`, `DATASET_VERSION`, `CANDIDATE_CHANGE`, `BUILD`, `LANE_FENCE`, `PIN`; `PUBLISH_BATCH`, `REPUBLISH_PRIOR` signatures and return codes PUBLISHED/ALREADY_PUBLISHED/FENCED/CONFLICT/NOT_VALIDATED | DBT-101-S03, ORC-005-S01/S04/S13, ORC-105-S01 |
| `data/contracts/publication.json` | Pin resolution order, pin predicate, ack payload `{tenant_id, pub_seq, publication_id, changed_datasets[], accepted_seq_range, source_as_of, coverage}`, outbox event `publication.advanced` | ORC-005-S06/S09 |
| `data/contracts/py_outputs.json` | Per Python output: keys, tenant_id, algorithm_run_id/version, input_pub_seq, config_version, seed, decimal types | ORC-103-S01 |
| `data/contracts/recovery_plan.json` | tenants, datasets/selector, range, reason, expected checksums, approvals | ORC-006-S01 |
| Query-tag schema | `{app, env, lane, build_id, model, layer}` / broker `{app, env, tenant_id, request_id}` | ORC-104-S01 |

## 4. Revised production backlog

### ORC-001 — Deploy private OSS control services and metadata database
Release: R1 · Estimate: 38–52 h · Risk: M · Decisions: D-07, D-21, D-25 · Closes: G-ORC-03, G-ORC-05
Dependency changes: `−CTL-002 (dagster_meta is a separate cluster; only the pool-budget pattern is reused)`, `+INF-004 (Aurora provisioning module)`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ORC-001-S01 | Write instance config: postgres run/event/schedule storage from env, QueuedRunCoordinator with `concurrency.runs` placeholders, `run_monitoring` (enabled, start_timeout 300 s, poll 120 s), tick retention (skipped 1 d, success 7 d, failure 30 d), S3ComputeLogManager with SSE-KMS prefix `dagster-compute-logs/<env>/`, telemetry off | `services/orchestrator/dagster.yaml`, `workspace.yaml` | `dagster instance info` in local compose prints the configured storages/launcher; config schema test passes | 3 |
| ORC-001-S02 | Provision separate Aurora PostgreSQL Serverless v2 cluster `dagster-meta-<env>` (0.5–4 ACU), DB `dagster_meta`, users `dagster_app`/`dagster_migrator`, PITR 14 d, deletion protection, SG ingress only from Dagster task SG | `infra/terraform/modules/dagster/aurora.tf` | Plan reviewed; psql from API task SG times out (negative test recorded) | 3 |
| ORC-001-S03 | Create ECS services: `dagster-webserver-ro` ×2 with `--read-only` behind internal ALB + OIDC to engineering IdP group; `dagster-webserver-admin` desired 0; `dagster-daemon` desired 1, minHealthy 0/max 100, circuit breaker; code servers `cl-extraction`, `cl-dbt`, `cl-intelligence`, `cl-delivery`, `cl-maintenance` | `infra/terraform/modules/dagster/services.tf` | ALB scheme internal, no public IPs; deployment config shows 0/100 for daemon | 4 |
| ORC-001-S04 | Write IAM: daemon role `ecs:RunTask` conditioned on Dagster run task-definition families, `ecs:StopTask/DescribeTasks` on cluster, `iam:PassRole` on `bridge-ext-*`,`bridge-run-*` with `iam:PassedToService=ecs-tasks.amazonaws.com`; webserver-ro role has none of these | `infra/terraform/modules/dagster/iam.tf` | IAM policy simulator: ro-webserver RunTask = Deny; daemon PassRole on `bridge-api-*` = Deny; recorded | 3 |
| ORC-001-S05 | Implement `BridgeEcsRunLauncher(EcsRunLauncher)`: fail launch if run tags contain `ecs/task_overrides`, `ecs/run_task_kwargs`, `ecs/container_overrides`; for `account_cycle_job`/`backfill_chunk_job` resolve `taskRoleArn` from PostgreSQL `connection.connections` (status ACTIVE, env match) by run-config `connection_id` and inject into overrides; emit audit event | `services/orchestrator/launcher/bridge_ecs_launcher.py` | Unit tests: forged-tag run → `LAUNCH_REJECTED_FORGED_TAG`, no RunTask call; resolved ARN equals binding; unknown connection → launch failure | 4 |
| ORC-001-S06 | Add contract test pinning signatures/behaviour of overridden upstream private methods (`_get_task_overrides`, `_run_task_kwargs`) for the locked dagster-aws version | `tests/spec/ORC-001/test_launcher_contract.py` | Test fails when a method signature is changed in a mutated copy | 1 |
| ORC-001-S07 | Implement in-task identity guard: STS GetCallerIdentity assumed-role name must equal registered role for `connection_id`; mismatch aborts before any Snowflake connection and emits security audit | `services/extractor/snowflake/identity_guard.py` | Staging: launching connection A with role B aborts `IDENTITY_MISMATCH`; synthetic account LOGIN_HISTORY shows 0 logins for B's user in window | 2 |
| ORC-001-S08 | Add metadata migration as a one-off ECS task gated before code/daemon deploys, with pre-migration Aurora snapshot; rollback = restore snapshot to new cluster | `infra/.../migrate_task.tf`, release pipeline step | Staging migration N-1→N and restore rehearsal recorded with durations | 3 |
| ORC-001-S09 | Daemon kill drill: stop daemon during a sensor tick with 20 queued runs | `docs/evidence/ORC-001/<commit>/daemon_kill.md` | Each queued run launched exactly once (run ids unique per run key); heartbeat-age alarm fired > 120 s | 3 |
| ORC-001-S10 | Daemon redeploy overlap drill | evidence query on `daemon_heartbeats` | No two distinct daemon_ids heartbeat within the same 30 s window during deploy | 2 |
| ORC-001-S11 | Code-location outage drill: stop `cl-dbt` | evidence | Extraction runs continue; `dagster_code_location_unavailable` alarm within 3 min | 2 |
| ORC-001-S12 | Emit metrics `dagster.daemon.heartbeat_age_s`, `dagster.runs.queued{lane}`, `dagster.runs.queued_age_p95{lane}`, `dagster.run_launch.failures`, `dagster.meta.db_bytes`, `dagster.meta.event_rows` with alarms | `services/orchestrator/telemetry.py`, alarms TF | Dashboard shows all series in staging; alarm thresholds documented | 3 |
| ORC-001-S13 | Enforce log sanitization: Dagster logger filter redacting SQL literals/credentials; forbid logging SQL text | `services/orchestrator/logging.py` | Fixture op logging `select 'secret-123'` → compute log in S3 contains 0 occurrences of `secret-123` | 2 |
| ORC-001-S14 | Negative access tests: internet request to webserver, GraphQL `launchRun` on ro webserver | `tests/spec/ORC-001/test_private.py` | Internet request fails (no route); mutation returns read-only error | 2 |
| ORC-001-S15 | Write runbook sections: daemon down/duplicate, metadata DB full, code location crash, break-glass admin webserver (approver, audit, scale back to 0) | `docs/runbooks/dagster.md` | Reviewed by SRE; commands tested in staging | 2 |
Task acceptance (task-specific, 3–8 items, NO boilerplate):
- [ ] Read-only webserver rejects run launches; no public route exists.
- [ ] A run with a forged `ecs/task_overrides` tag is never launched; account runs receive exactly their registered role.
- [ ] Identity mismatch aborts before any Snowflake login.
- [ ] Daemon kill and redeploy produce zero overlapping heartbeats and no duplicate run launches.
- [ ] `dagster_meta` is unreachable from API task security groups; migration and restore rehearsed.

### ORC-002 — Define generic jobs/assets and the no-tenant-partition catalog
Release: R1 · Estimate: 24–36 h · Risk: M · Decisions: D-07 · Closes: G-ORC-01
Dependency changes: `−ING-008 (+ING-001 source contract; ORC-002-S12 evidence needs ING-005)`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ORC-002-S01 | Encode partition policy: no `DynamicPartitionsDefinition`/`MultiPartitionsDefinition` anywhere; daily partitions only for maintenance assets | `services/orchestrator/partitions.py`, `tests/spec/ORC-002/test_partition_policy.py` | Test fails when a dynamic partition def is added | 2 |
| ORC-002-S02 | Define asset-key catalog: `journal/<family>`, `raw_accepted/<family>` (observable), `dbt/<layer>/<model>`, `py/<engine>/<output>`, `publication/core`, `publication/intelligence` | `services/orchestrator/asset_keys.py` | Snapshot test of key list | 2 |
| ORC-002-S03 | Implement `account_cycle_job` with single op `run_account_cycle(AccountCycleConfig{connection_id: UUID, cycle_id: UUID})`; op loads plan from PostgreSQL and calls `extractor.run_cycle(plan)`; no I/O at import | `services/orchestrator/jobs/account_cycle.py` | Config with extra fields rejected; import performs no network call | 3 |
| ORC-002-S04 | Emit one `AssetObservation(journal/<family>)` per source with tenant_id, account_id, window, batch_id, rows, status, error_class; source failure does not fail cycle except AUTH | same | Fixture cycle with 1 of 20 sources failing: run SUCCESS, 19 OK + 1 FAILED observation | 3 |
| ORC-002-S05 | Implement `backfill_chunk_job` (connection_id, backfill_plan_id, chunk_ids ≤ N sized for 15–30 min) with lane tag | `jobs/backfill_chunk.py` | Chunk sizing unit test from ING-010 estimates | 2 |
| ORC-002-S06 | Stub `dbt_build_job`, `intelligence_job`, `maintenance_*` jobs (daily-partitioned global maintenance only) | `jobs/*.py` | Definitions load with all jobs | 2 |
| ORC-002-S07 | Offline definitions test with sockets disabled and no credentials | `tests/spec/ORC-002/test_offline_load.py` (pytest-socket) | Load succeeds; any socket use fails the test | 2 |
| ORC-002-S08 | Scale invariance test: 1, 100, 1,000 synthetic connections in PostgreSQL fixture | `tests/spec/ORC-002/test_scale_invariance.py` | Repository snapshot hash identical across the three | 2 |
| ORC-002-S09 | Guard against global certification: extraction/ingestion groups contain only observable specs; dbt materialization metadata must carry `build_id`, `snapshot_seq`, `workset_tenant_count` | test | Adding a materializable unpartitioned extraction asset fails CI | 2 |
| ORC-002-S10 | Write metadata JSON Schema and validator used by all emitters | `data/contracts/dagster_metadata.json` | Emitted events in tests validate | 2 |
| ORC-002-S11 | Add limits file (dynamic partitions 0, jobs ≤ 30, assets ≤ 2,000, RunRequests per tick ≤ 50) and CI check | `services/orchestrator/limits.yaml` | CI fails when a limit is exceeded | 1 |
| ORC-002-S12 | Staging evidence with 2 tenants × 1 account after ING-005: observations reference exact batch ids; B failure leaves A untouched | `docs/evidence/ORC-002/<commit>/` | Batch ids in observations equal manifest ids in S3 | 2 |
Task acceptance:
- [ ] Zero dynamic/multi partitions; repository snapshot invariant for 1/100/1,000 connections.
- [ ] Definitions load with network disabled.
- [ ] Every observation carries tenant/account/window/batch ids; one account never produces a global materialization.

### ORC-003 — Implement fair admission, schedules and idempotent sensors
Release: R1 · Estimate: 38–54 h · Risk: H · Decisions: D-07, D-08 · Closes: G-ORC-01, G-ORC-02, G-ORC-04 (idempotency part)
Dependency changes: `+ING-002 (planned windows are the ready-work source)`, `+CON-001 (connection→role binding)`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ORC-003-S01 | Create `sync.account_cycles` (unique account_id+lane+cycle_start; lease_token; attempt; next_attempt_at; error_class), `sync.lane_budget`, `sync.tenant_weight` with RLS per CTL pattern | `services/control/migrations/*_account_cycles.py` | Migration up/down; duplicate insert returns existing row | 3 |
| ORC-003-S02 | Implement cycle planner: each minute plan accounts with `hash(account_id) mod 60 = minute`, attach due sources from ING-002 planned windows; idempotent insert | `services/orchestrator/admission/planner.py` | 500 synthetic accounts → ≤ 9 cycles planned per minute; rerun inserts 0 | 3 |
| ORC-003-S03 | Implement weighted deficit round-robin admission within lane: respect lane total, per-tenant, per-account=1, steady reserved capacity; `FOR UPDATE SKIP LOCKED`; mark SUBMITTED with run_key | `admission/controller.py` | Deterministic test: A has 1,000 PLANNED, B has 5 → B admitted within first 2 slots; weights 2:1 → 2:1 admission ratio ±1 over 300 slots | 4 |
| ORC-003-S04 | Implement `admission_sensor` (30 s, ≤ 50 RunRequests/tick), run_key = sha256(job, cycle_id, attempt); reconcile dagster_run_id by run-key tag after tick | `sensors/admission.py` | Kill sensor after submission before cursor save → next tick emits same key, one run exists | 4 |
| ORC-003-S05 | Implement in-run claim: first op step `UPDATE … SET status=RUNNING, lease_token=… WHERE id=:cycle AND status='SUBMITTED' AND dagster_run_id=:run_id RETURNING`; no row → exit SKIPPED_DUPLICATE without extraction | `extractor/cycle_claim.py` | UI-launched run with valid config but no SUBMITTED row → 0 Snowflake queries, audit event | 2 |
| ORC-003-S06 | Configure run-level tag limits (lane steady 60, backfill 12, dbt 2, python 2, report 4; tenant applyLimitPerUniqueValue 6) as safety net; document capacity formula | `dagster.yaml`, `admission/capacity.md` | Config loads (keys VERIFIED in Dagster `queued_run_coordinator.py`); formula doc reviewed | 2 |
| ORC-003-S07 | Implement error classifier: TRANSIENT (retry ≤ 5, 30 s·2^n ±20% jitter, cap 15 min), AUTH (0 retries, health AUTH_FAILED, RB-01), CUSTOMER_QUOTA (resource monitor suspended warehouse; wait next cycle; D-08), SCHEMA (quarantine source), CANCELLED, INTERNAL (≤ 2) | `admission/errors.py` + code table | Fixture per class → expected status/next_attempt_at; Snowflake codes marked TO VERIFY LIVE | 3 |
| ORC-003-S08 | Enforce retry budgets and poison handling: same error class 3 consecutive cycles → pause account-source + health event | `admission/poison.py` | Injected 429 retried then succeeds; AUTH denied 0 retries; poison paused after 3 | 2 |
| ORC-003-S09 | Implement stuck-lease reaper: RUNNING cycle with terminal Dagster run or age > 45 min → FAILED(WORKER_LOST); StopTask dangling task by `ecs/task_arn` tag | `admission/reaper.py` | Killed worker → cycle FAILED within 5 min; next cycle proceeds | 3 |
| ORC-003-S10 | Implement backfill back-pressure: admit backfill only if steady p95 queue age < 5 min over last 10 min; ≤ 4 per tenant, ≤ 12 total | `admission/backfill.py` | Simulated steady congestion pauses backfill admission | 3 |
| ORC-003-S11 | Noisy-neighbor test: A requests 365 days × 20 sources (ING-010 chunking), B 5 accounts hourly | `tests/spec/ORC-003/test_fairness.py` + staging run | B cycle queue age p95 ≤ 5 min; Dagster queued runs never exceed 2× lane limits | 4 |
| ORC-003-S12 | Duplicate wakeup test: 100 evaluations for the same cycle | test | One SUBMITTED row, one run, one accepted batch per source window | 2 |
| ORC-003-S13 | Emit `admission.queue_age_seconds{lane}` p50/p95, `admission.running{lane}`, `admission.denied{reason}`, `cycle.outcome{status,error_class}`; tenant only in logs; alarms steady p95 > 10 min for 15 min (page), stalled cycles > 30 min | telemetry + alarms | Alarms fire in staging drill | 2 |
| ORC-003-S14 | Write runbook entries: noisy tenant (RB-15 weight/limit commands), poison account, sensor stuck | `docs/runbooks/dagster.md` | Commands dry-run in staging | 2 |
Task acceptance:
- [ ] 500 accounts produce ≤ 9 cycle starts per minute.
- [ ] Under a 365-day flood from A, B's steady p95 queue age ≤ 5 min.
- [ ] Sensor crash after submission yields exactly one run and one cycle.
- [ ] AUTH failures are not retried; TRANSIENT retries are bounded with jitter.
- [ ] A manually launched run without a sensor-issued claim performs no extraction.

### ORC-004 — Integrate dbt assets and Python result dependencies
Release: R1 · Estimate: 34–48 h · Risk: H · Decisions: D-06 · Closes: G-ORC-08, G-ORC-09
Dependency changes: `+DBT-001 (manifest), +DBT-002 (real staging lineage), +DBT-101, +ORC-101`, `−ING-009 (drift handling is not needed to wire assets)`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ORC-004-S01 | Build manifest at image build (`dbt deps && dbt parse`), label image with `bridge.dbt_manifest_sha256`; no runtime parse | `services/orchestrator/Dockerfile.dbt` | Image label present; code location loads a 400-model fixture manifest in < 20 s | 3 |
| ORC-004-S02 | Implement `BridgeDbtTranslator`: keys `dbt/<layer>/<model>`, group=layer, owners from `config.meta.bridge.owner`, code_version=model checksum; source `raw.*`→`raw_accepted/<family>`, `py.*`→`py/<engine>/<output>` (`get_asset_key_for_source` VERIFIED in dagster-dbt `asset_utils.py`) | `services/orchestrator/assets/dbt.py` | Snapshot of asset-graph edges shows py→dbt mart edges | 3 |
| ORC-004-S03 | Compose `dbt_build_job`: `plan_build` (ORC-101) → `dbt build --select <derived> --vars '{"build_id": "<uuid>"}'` → `evaluate_gates` → `publish` (ORC-005); selection = models whose `dataset_id` intersects workset + descendants | `jobs/dbt_build.py` | Fixture workset touching 1 dataset selects only it and descendants | 4 |
| ORC-004-S04 | Enforce var allowlist: only `build_id` (UUID) reaches dbt; macro asserts at compile | `resources/dbt_cli.py`, `data/dbt/macros/build_context.sql` | `build_id="x' or 1=1 --"` rejected before invocation and at compile | 2 |
| ORC-004-S05 | Map dbt tests to Dagster checks for visibility only; gate reads `QUALITY.CHECK_RESULT` | translator settings + doc | Tenant-scoped failing check shows WARN in Dagster and FAIL row for that tenant | 2 |
| ORC-004-S06 | Implement model-error bisection in repair lane (split workset by tenant halves, ≤ ⌈log2 n⌉+1 builds, max 8); quarantine poison tenant; alert RB-07 | `publication/bisect.py` | Tenant C with overflow value: A and B publish; C quarantined within ≤ 3 extra builds for n=3 | 4 |
| ORC-004-S07 | Implement Python asset pattern: `@asset(key=py/<engine>/<output>, deps=[dbt marts])` → pure `engine.run(EngineContext(input_pub_seq, algorithm_version, config pins)) -> pyarrow.Table` → ORC-103 writer | `assets/intelligence.py` | No SQL string in asset module except via library; lint check | 3 |
| ORC-004-S08 | Implement two-phase trigger: `intelligence_sensor` on `publication.advanced` outbox events runs engines pinned to that pub_seq; outputs enter next build workset | `sensors/intelligence.py` | Forecast rows carry `input_pub_seq=P` and appear in P′ > P; killing the engine does not delay the next ledger publication | 3 |
| ORC-004-S09 | Test config change mid-build (insert new accepted config version after `plan_build`) | `tests/spec/ORC-004/test_config_pin.py` | Build output references old version; next build uses new | 2 |
| ORC-004-S10 | Detect stale manifest/image mismatch at run start (label vs release manifest git SHA) | `jobs/dbt_build.py` | Mismatch aborts with `STALE_MANIFEST` before any SQL | 2 |
| ORC-004-S11 | Failure-scope test: inject 270→540 double count for tenant A | test + staging evidence | B publishes; A not; monitors/reports triggered for B only | 3 |
| ORC-004-S12 | Add no-formula guard over `services/orchestrator/**` (AST scan for arithmetic on money/credit fields and SQL aggregates outside planner allowlist) | `tools/lint/no_formula_in_dagster.py` | Seeded violation fails CI | 2 |
| ORC-004-S13 | Emit `dbt.build.duration_s`, `dbt.build.models_error`, `dbt.build.workset_partitions`, `dbt.build.tenants_gated{reason}`, `python.engine.duration_s{engine}`; alarms on quarantine and 2 consecutive failed builds | telemetry | Visible in staging dashboard | 2 |
Task acceptance:
- [ ] Asset graph shows raw→staging→ledger→serving and Python outputs as dbt sources.
- [ ] Only `build_id` reaches dbt; injection attempts rejected.
- [ ] A poison tenant is isolated by bisection while others publish.
- [ ] Python outputs carry `input_pub_seq` and never block ledger publication.
- [ ] Config changes during a build do not alter that build's output.

### ORC-005 — Publish coherent datasets and version notifications
Release: R1 · Estimate: 44–62 h · Risk: H · Decisions: D-05, D-06 · Closes: G-ORC-06, G-ORC-10
Dependency changes: `+DBT-101 (DDL), +ORC-101 (build/workset), +SEC-005 (RAP-protected reader identities for concurrent-reader test)`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ORC-005-S01 | Apply publication DDL from DBT-101 (TENANT_POINTER, PUBLICATION, PUBLICATION_MAP clustered by tenant_id+dataset_id, DATASET_VERSION, CANDIDATE_CHANGE, BUILD, LANE_FENCE); publisher role DML-only | `data/snowflake/migrations/publication/V001__publication.sql` | Apply twice = no-op; reader roles have no grant (negative test) | 3 |
| ORC-005-S02 | Build candidate changes: for each workset partition compare built revision checksum to published revision checksum; equal → reuse (no change row); zero-row partitions included | `publication/candidate.py` + SQL | Correction 30→10 rows yields one change row; identical rebuild yields 0 change rows and no publication | 4 |
| ORC-005-S03 | Implement per-tenant gate: all required checks have PASS rows (absence = FAIL), every workset partition has a PARTITION_REVISION row, code-version homogeneity for shadow datasets, candidate `snapshot_seq` ≥ published `snapshot_seq` else STALE | `publication/gate.py` | Unit matrix of 8 gate cases → expected ELIGIBLE/REJECTED reason | 4 |
| ORC-005-S04 | Write `PUBLICATION.PUBLISH_BATCH(pub_seq, build_id, fence_token)` (Snowflake Scripting, EXECUTE AS OWNER, DML only): verify BUILD VALIDATED + fence; set-based CAS on TENANT_POINTER; SQLROWCOUNT must equal eligible count else ROLLBACK/CONFLICT; close/insert map rows; bump DATASET_VERSION for changed datasets; mark PUBLISHED | `data/snowflake/procedures/publish_batch.sql` | Fixture with 3 eligible tenants advances exactly 3 pointers; forced CAS mismatch rolls back all (transaction scope TO VERIFY LIVE) | 4 |
| ORC-005-S05 | Make publish idempotent under single publisher lease `publisher:<env>` with pub_seq from PostgreSQL sequence | `publication/publisher.py` | Second call same pub_seq returns ALREADY_PUBLISHED; map unchanged | 2 |
| ORC-005-S06 | Implement PostgreSQL ack in one transaction: monotonic upsert `platform.dataset_publication_refs`, published coverage update from BATCH_PROCESSING, outbox `publication.advanced` | `publication/ack.py` | Duplicate ack is a no-op; older pub_seq never overwrites newer | 3 |
| ORC-005-S07 | Implement ack reconciler sensor (60 s): Snowflake PUBLISHED minus PostgreSQL refs → replay ack; PostgreSQL ahead → SEV2 alert only | `sensors/publication_reconciler.py` | Crash after COMMIT before ack reconciled ≤ 2 min | 3 |
| ORC-005-S08 | Wire cache versioning: keys use `dataset_version` from refs (CTL-006); optional pre-warm consumer | `publication/cache_announce.py` | Unchanged dataset keeps key across P1→P2; changed dataset gets new key | 2 |
| ORC-005-S09 | Publish reader pinning contract and SQL snippet generator for API/report/monitor consumers | `data/contracts/publication.json`, `publication/pin_predicate.py` | Contract tests used by API-002 pass | 2 |
| ORC-005-S10 | Concurrent-reader test: 4 readers querying SERVING views pinned and current while 50 publications advance ledger+allocation | `tests/spec/ORC-005/test_no_mixed_versions.py` | Every read equals exactly one publication's golden totals (never ledger of Pn with allocation of Pn−1) | 4 |
| ORC-005-S11 | Crash matrix: before procedure, inside before COMMIT (forced timeout), after COMMIT before ack, after ack before dispatch | test + staging evidence | (a)(b) pointer unchanged; (c)(d) advanced, ack reconciled, exactly one outbox event | 4 |
| ORC-005-S12 | Fence tests: zombie build with old token; CANCELLED build | test | Both return FENCED/NOT_VALIDATED; no map change | 2 |
| ORC-005-S13 | Implement `REPUBLISH_PRIOR(tenant, target_pub_seq, datasets, reason, actor)` as forward publication; audit in PostgreSQL (RB-07) | procedure + `bridge-admin publication republish-prior --dry-run` | Bad P5 → P6 equals P4 content; pointer 5→6, never back to 4 | 3 |
| ORC-005-S14 | Emit `publication.age_seconds` (max over tenants with pending accepted batches), `publication.tenants_published`, `publication.tenants_gated{reason}`, `publication.ack_lag_s`; alarm pending accepted batch older than 60 min | telemetry | Alarm fires in staging drill | 2 |
| ORC-005-S15 | Write RB-07 commands and ack reconciliation procedure | `docs/runbooks/dagster.md` | Dry-run output reviewed | 2 |
Task acceptance:
- [ ] Across 50 publications no reader observes mixed versions.
- [ ] After-commit crash is reconciled from Snowflake; PostgreSQL is never ahead.
- [ ] Identical candidate does not create a publication; a zero-row correction removes old rows.
- [ ] Zombie or cancelled builds cannot publish.
- [ ] Rollback is a forward publication; `pub_seq` per tenant is strictly increasing.

### ORC-006 — Exercise backfill, cancellation and selective recovery
Release: R1 · Estimate: 32–46 h · Risk: H · Decisions: D-05, D-06 · Closes: G-ORC-10, G-ORC-13
Dependency changes: `+ORC-105 (retained revisions/pins)`. Admin recovery **UI** moves to R2; R1 uses `bridge-admin`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ORC-006-S01 | Define recovery plan schema and PostgreSQL `ops.recovery_plans`; CLI `bridge-admin recovery plan/approve/execute --dry-run` | `data/contracts/recovery_plan.json`, `services/admin/recovery.py` | Plan without approval cannot execute | 3 |
| ORC-006-S02 | Compute downstream closure from partition rules into workset (reason REPAIR, lane repair); dry-run shows partitions, estimated rows, current checksums | `planner/recovery.py` | Fixture: stg change for A × 3 days → exact closure list | 3 |
| ORC-006-S03 | Cancel extraction mid-cycle: SIGTERM handler cancels source query, stops uploads, no manifest | `extractor/cancel.py` | Synthetic account query status CANCELLED; no manifest for the batch id | 3 |
| ORC-006-S04 | Cancel dbt mid-build: BUILD→CANCELLED; reaper cancels queries tagged with terminal build after 5 min | `publication/reaper.py` | 0 running tagged queries after 6 min; publish refused | 4 |
| ORC-006-S05 | Zombie drill: SIGSTOP a dbt task, start newer build, SIGCONT old | evidence | Old build returns FENCED | 2 |
| ORC-006-S06 | Staged-bug drill: bug in `int_x` for tenant A (3 days) → RB-07 republish prior → fix → recovery plan for A | evidence | PUBLICATION_MAP diff for B empty; A final per-partition HASH_AGG equals clean-run checksums | 4 |
| ORC-006-S07 | Historical + steady concurrency: 90-day backfill for A while B steady; kill backfill worker; resume | evidence | Accepted windows re-extracted = 0; B SLO held | 3 |
| ORC-006-S08 | Metadata DB outage (10 min writer loss) | evidence | No duplicate accepted batch; publication resumes; observed behaviour documented | 3 |
| ORC-006-S09 | Worker loss mid-build (kill task) | evidence | Run marked failed by run monitoring; BUILD ABANDONED; next build re-plans unpublished partitions | 2 |
| ORC-006-S10 | Journal-missing drill: delete one retained file of an accepted batch in staging, request replay | evidence | Only that coverage blocked; recovery refuses partial partition publication | 2 |
| ORC-006-S11 | Write operator decision tree with thresholds (cancel vs finish, lane pause, SEV2 if publication age > 2 h for > 10% tenants) | `docs/runbooks/dagster.md` | SRE review sign-off | 2 |
| ORC-006-S12 | Assemble evidence pack (timings, checksums, map diffs) | `docs/evidence/ORC-006/<commit>/` | FND-005 schema validates | 2 |
Task acceptance:
- [ ] Cancelled extraction leaves no manifest and cancels the customer query.
- [ ] Cancelled or zombie builds cannot publish; no tagged query survives 6 minutes.
- [ ] Recovery changes only requested tenants' map rows; checksums equal a clean run.
- [ ] Metadata DB outage creates no duplicate accepted batch.

## 5. New tasks required

### ORC-101 — Processing ledger, build snapshot and workset planner
Release: R1 · Estimate: 34–48 h · Risk: H · Decisions: D-04, D-06 · Closes: G-ORC-07
Why/where: D-06 names a processing ledger no task owns. Plugs after ING-007 + DBT-101; blocks DBT-002, ORC-004, ORC-005.
Dependency changes: `+ING-007, +DBT-101, +CTL-005`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ORC-101-S01 | Specify ING-007 amendment: single-writer acceptance assigns `accepted_seq` (Snowflake sequence) in the same INSERT | interface note in `data/contracts/publication.json` | ING owner sign-off | 2 |
| ORC-101-S02 | Create `BATCH_PROCESSING`, `BUILD_WORKSET` (reason NEW_DATA/CONFIG/REPAIR/SHADOW/RETRY/ANTI_ENTROPY), `BUILD_CONFIG_PIN`, `DATASET_PARTITION_RULE` (identity/hour_to_day/day_to_month/account_to_org/tenant_all_open), `TENANT_QUARANTINE` | `data/snowflake/migrations/publication/V002__processing.sql` | Apply twice no-op | 3 |
| ORC-101-S03 | Build source→dataset impact map with registry overlap | `planner/impact.py` | QAH window 10:00–11:00 → `fct_query_compute` hour 10 (+overlap hours); WMH window → day partition | 3 |
| ORC-101-S04 | Implement planner: snapshot S = max(accepted_seq); pending = accepted ≤ S not BUILT in lane ∪ GATED retries ∪ config changes ∪ repair requests; topological closure via partition rules; insert workset; BUILD row with snapshot_seq and fence | `planner/workset.py` | Deterministic workset for fixture history (checksum stable across 10 runs) | 4 |
| ORC-101-S05 | Pin config per tenant (latest ACCEPTED ≤ plan time) and expand config-change partitions to open periods only (closed periods need reason RESTATEMENT) | `planner/config_pins.py` | Rule change for A → only A's open-month allocation partitions | 3 |
| ORC-101-S06 | Split oversized worksets by tenant hash (steady ≤ 50,000 partitions, repair ≤ 200,000), never splitting a tenant | `planner/split.py` | 500-tenant 365-day config change → N builds, each tenant in exactly one | 3 |
| ORC-101-S07 | Maintain batch status BUILT/PUBLISHED(pub_seq)/GATED; 3 consecutive GATED → quarantine | `planner/status.py` | State transitions unit-tested | 3 |
| ORC-101-S08 | Gap-safety test: seq 11 commits before 10 | test | Seq 10 picked by next plan; no batch lost | 2 |
| ORC-101-S09 | Snapshot determinism test: batch accepted mid-build | test | Not in current build output; included in next | 2 |
| ORC-101-S10 | Integrate anti-entropy (ING-011) as ANTI_ENTROPY partitions only when checksums differ | `planner/anti_entropy.py` | Equal checksum adds 0 partitions | 2 |
| ORC-101-S11 | Update PostgreSQL batch state machine to TRANSFORMED/PUBLISHED and published coverage from ack | `publication/ack.py` extension | Batch reaches PUBLISHED with pub_seq | 3 |
| ORC-101-S12 | Emit `workset.partitions{lane,reason}`, `accepted_unprocessed.count`, `accepted_unprocessed.oldest_age_s` (alarm > 30 min), `tenants_gated_consecutive` | telemetry | Visible in staging | 2 |
| ORC-101-S13 | Implement build trigger sensor (oldest unprocessed ≥ 10 min or ≥ 500 batches or config/repair pending; one steady build at a time) | `sensors/dbt_build.py` | Freshness drill: batch accepted → published ≤ 30 min p95 | 2 |
Task acceptance:
- [ ] No batch lost under out-of-order commits; builds read a fixed snapshot.
- [ ] Config changes rebuild only affected tenants' open-period partitions.
- [ ] A tenant is never split across builds of one lane.
- [ ] Accepted→published p95 ≤ 30 min in staging.

### ORC-102 — Dagster metadata retention and capacity guardrails
Release: R1 · Estimate: 16–24 h · Risk: M · Decisions: D-07 · Closes: G-ORC-04
Why/where: no retention exists for runs/events; plugs after ORC-001, before M3 exit.
Dependency changes: `+ORC-001`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ORC-102-S01 | Measure events per run type in staging and write capacity model | `services/orchestrator/maintenance/capacity.md` | Measured events/run recorded for account_cycle, dbt_build, python | 2 |
| ORC-102-S02 | Implement purge job via `instance.delete_run` in batches of 500 (extraction success > 14 d, dbt/publication success > 30 d, failures > 90 d, keep latest success per job, skip runs tagged with open incident id) | `maintenance/purge_runs.py` | Fixture DB: exact expected run set remains | 3 |
| ORC-102-S03 | Configure tick retention and compute-log S3 lifecycle (30 d) | `dagster.yaml`, TF lifecycle | Config applied | 1 |
| ORC-102-S04 | Prove idempotency survives purge: purged run key re-requested | test | Dagster launches run; claim guard exits SKIPPED_DUPLICATE; no extraction | 2 |
| ORC-102-S05 | Add autovacuum tuning for event_logs, bloat query, storage alarm at 70% of 50 GB | TF parameter group + alarm | Alarm test fires | 2 |
| ORC-102-S06 | Load test: 30 days at 1.1M events/day (or 3 days + extrapolation) | evidence | UI run list p95 < 3 s; purge < 30 min | 4 |
| ORC-102-S07 | Wire limits CI guard (shared with ORC-002-S11) | CI | Exceeding limits fails | 1 |
| ORC-102-S08 | Runbook: metadata growth and purge failure | `docs/runbooks/dagster.md` | Reviewed | 1 |
Task acceptance:
- [ ] Run/event volume stays under the 50 GB budget with purge running.
- [ ] Purging run history cannot cause a duplicate extraction.

### ORC-103 — Python output landing and lineage contract
Release: R1 (moves to R2 with forecasts/insights if D-01/D-20 defer them) · Estimate: 22–32 h · Risk: M · Decisions: D-05 · Closes: G-ORC-09
Why/where: no task defines how Python results land; plugs after DBT-101, before GOV forecast tasks and INS-001.
Dependency changes: `+DBT-101, +CON-002`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ORC-103-S01 | Write output contract (keys, tenant_id, algorithm_run_id/version, input_pub_seq, config_version, seed, as_of partition, decimal128(38,12) money) | `data/contracts/py_outputs.json` | Schema review by GOV/INS owners | 2 |
| ORC-103-S02 | Create transient `PY.<OUTPUT>_LANDING` and revisioned `PY_REV.<OUTPUT>_R` tables | migration | Apply twice no-op | 2 |
| ORC-103-S03 | Implement writer: validate Arrow table → Parquet ZSTD → `PUT` to `@PY.RESULTS_STAGE/<output>/<run_id>/` → `COPY INTO … FILES=(…) MATCH_BY_COLUMN_NAME=CASE_INSENSITIVE` → assert rows_loaded = manifest rows → revisioned insert → PARTITION_REVISION rows; rerun same run_id clears its landing/unpublished rows first | `packages/py_results/writer.py` | Rerun produces one copy; row mismatch aborts | 4 |
| ORC-103-S04 | Create `PY.RUN_MANIFEST` (run_id, engine, output, tenant_ids, input_pub_seq, algorithm_version, rows, sha256, status) | migration + writer | Manifest row per run | 2 |
| ORC-103-S05 | Decimal safety tests (float money rejected; 0.1+0.2 exact) | tests | Pass | 2 |
| ORC-103-S06 | Tenant guard: any row with tenant_id outside run tenant set rejects the run | writer | Forged tenant row → run REJECTED, 0 rows landed | 2 |
| ORC-103-S07 | Declare dbt sources `py.*` with asset-key mapping and staging models selecting revisions via map/workset | `data/dbt/models/staging/py/*` | Lineage edge visible; mart reads only published revision | 3 |
| ORC-103-S08 | Replay determinism for forecast fixture (same input_pub_seq/version/seed) | test | Identical checksum across 2 runs | 3 |
| ORC-103-S09 | Volume guard (> 5M rows/run flagged) and prohibition of query-grain outputs | writer | Oversized output flagged | 1 |
| ORC-103-S10 | Clean stage files after registration (`REMOVE`) and truncate landing per run | writer | Stage empty after success | 1 |
Task acceptance:
- [ ] Python outputs are exactly-once per run_id, tenant-guarded and decimal-exact.
- [ ] Outputs are consumed by dbt only through published revisions, with lineage to the engine run.

### ORC-104 — Central compute metering capture per build and tenant
Release: R1 (capture; allocation reporting in OPS-009) · Estimate: 16–24 h · Risk: M · Decisions: D-06 · Closes: G-ORC-11
Why/where: set-based builds make per-tenant COGS impossible to reconstruct later unless drivers are captured from launch. Plugs after DBT-101/ORC-101; feeds OPS-009.
Dependency changes: `+ORC-101, +DBT-101`; OPS-009 `+ORC-104`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ORC-104-S01 | Set query-tag JSON for dbt (`{app, env, lane, build_id, model, layer}`, ≤ 2000 chars), broker (`tenant_id, request_id`), Python writer (`run_id`) | `data/dbt/macros/query_tag.sql`, broker/writer config | QUERY_HISTORY shows parsed tags in staging | 2 |
| ORC-104-S02 | Derive `OPS_INTERNAL.BUILD_MODEL_TENANT_ROWS` from PARTITION_REVISION row counts | dbt model in internal project | Totals equal sum of revision row counts | 2 |
| ORC-104-S03 | Collect per-query credits (central QUERY_ATTRIBUTION_HISTORY, latency TO VERIFY LIVE) joined to tags → credits per (build, model); WAREHOUSE_METERING_HISTORY for idle residual | `maintenance/cost_collect.py` | One staging day collected | 4 |
| ORC-104-S04 | Allocate credits by rows written per tenant; zero-row models by workset share; idle → UNALLOCATED_IDLE | internal model | Fixture 10 credits, 700/300 rows → 7/3; idle 2 unallocated; total 12 | 3 |
| ORC-104-S05 | Allocate Snowpipe credits by bytes per file using `tenant_id=` path segment | internal model | Fixture two tenants' files → byte-proportional split | 2 |
| ORC-104-S06 | Attribute broker queries directly by tag tenant | internal model | Sum by tenant = tagged credits | 1 |
| ORC-104-S07 | Restrict `OPS_INTERNAL` to ops role | grants | Customer reader select fails | 1 |
| ORC-104-S08 | Staging reconciliation evidence | evidence | Allocated + unallocated = metered for the day | 1 |
Task acceptance:
- [ ] Every central credit of a day is either attributed to a tenant or explicitly unallocated.
- [ ] No customer role can read internal cost data.

### ORC-105 — Revision retention, pins and garbage collection
Release: R1 · Estimate: 22–32 h · Risk: M · Decisions: D-05, D-11 · Closes: G-ORC-13
Why/where: retention of superseded revisions is referenced but unowned; plugs after ORC-005; required by ORC-006, FIN-010, OPS-007, API-002.
Dependency changes: `+ORC-005`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ORC-105-S01 | Create `PUBLICATION.PIN` (holder_kind REPORT_JOB/ANALYSIS_JOB/STATEMENT/RECOVERY_SNAPSHOT/OPERATOR_HOLD, pub_seq, dataset_ids, period range, expires_at) | migration | Apply twice no-op | 2 |
| ORC-105-S02 | Implement pin create/extend/release idempotent by holder id | `publication/pins.py` | Duplicate create returns same pin | 2 |
| ORC-105-S03 | Write GC eligibility SQL: superseded older than max(cursor TTL + 15 min, 7 d rollback window), not covered by any pin (pin.pub_seq within validity and period overlaps), not current; orphans of terminal builds older than 24 h | `publication/gc_eligible.sql` | Property test over 1,000 random histories never selects a current or pinned revision | 3 |
| ORC-105-S04 | Implement daily GC (maintenance lane) deleting eligible revisions per table in ≤ 10M-row statements; mark PURGED | `maintenance/gc_revisions.py` | Staging run deletes expected counts | 3 |
| ORC-105-S05 | Implement `pin_status(tenant, pub_seq)` → OK/RESTART_REQUIRED for API | `publication/pins.py` | Purged pin answers RESTART_REQUIRED | 2 |
| ORC-105-S06 | Tests: statement pin survives 30 newer publications; released report pin GC'd after grace; orphan revision GC'd | tests | All pass | 4 |
| ORC-105-S07 | Set revision tables Time Travel 1 day; monitor time-travel/fail-safe bytes (cost TO VERIFY LIVE) | migration + metric | Metric visible | 2 |
| ORC-105-S08 | Monitor read amplification (live revisions / published revisions per table), alarm > 3 | metric | Alarm drill | 2 |
| ORC-105-S09 | Pin current pub_seq per tenant during daily recovery snapshot export (OPS-007 interface) | `publication/pins.py` | Export references only map revisions | 1 |
| ORC-105-S10 | Runbook: GC pause switch, operator hold pin | `docs/runbooks/dagster.md` | Reviewed | 1 |
Task acceptance:
- [ ] GC never deletes a current or pinned revision (property-tested).
- [ ] RB-07 rollback is possible for 7 days; purged pins return RESTART_REQUIRED.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| ORC-001 | R1 | 38 | 52 |
| ORC-002 | R1 | 24 | 36 |
| ORC-003 | R1 | 38 | 54 |
| ORC-004 | R1 | 34 | 48 |
| ORC-005 | R1 | 44 | 62 |
| ORC-006 | R1 | 32 | 46 |
| ORC-101 | R1 | 34 | 48 |
| ORC-102 | R1 | 16 | 24 |
| ORC-103 | R1 | 22 | 32 |
| ORC-104 | R1 | 16 | 24 |
| ORC-105 | R1 | 22 | 32 |
| **Total R1** | | **320** | **458** |
| **Total R2** (admin recovery UI; regional sharding per D-23 — not decomposed here) | | **0** | **0** |

## 7. Owner questions (only those not already covered by D-01…D-25)

1. Approve a separate Aurora Serverless v2 cluster for `dagster_meta` (~USD 50–150/month) instead of sharing the control-plane writer?
2. Rollback window for superseded analytical revisions (default 7 days): acceptable storage cost versus RB-07 capability?
3. Who may use the writable break-glass Dagster webserver, with what approval and audit (all engineers get read-only)?
4. Accept that forecasts/anomaly/insight outputs lag the core financial publication by one publication (displayed with their input publication), so Python failures never block cost data?
5. Central build budget: acceptable Snowflake credits/day for steady builds (drives 15-minute vs 30-minute build cadence while meeting the 30-minute freshness target)?

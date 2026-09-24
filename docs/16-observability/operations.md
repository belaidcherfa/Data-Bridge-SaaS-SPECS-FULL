# Operational quality, security qualification and recovery

Canonical domain contract. Owner: SRE / Security / QA. Implementation state: NOT_STARTED.


## Observability and service objectives

Instrument request → job → source query → batch → accepted RAW → dbt publication → serving response with correlation IDs. OpenTelemetry emits sanitized traces/logs to the approved AWS observability stack; Dagster run/event metadata supplements operational telemetry. Do not log literal SQL or credentials. Bound tenant/resource cardinality; detailed tenant diagnosis belongs in access-controlled logs and analytical operational facts. Dashboard owners, alert thresholds, silence policy and runbooks are release artifacts.

Initial internal targets, measured before offering contractual SLAs: API availability99.9% monthly; warm interactive p95≤2s, cold p95≤10s, hard query deadline15s; auth/control error rate<1%; publish fresh accepted data within30min after source availability for ordinary partitions; backlog age and source lag are reported separately. Backfills and reports use independent queues and quotas. Financial completeness and source permission gaps are not hidden inside API uptime. Synthetic canaries use two synthetic tenants and never mutate customer workloads.

Quality levels: transport checksum/count/schema, transformation uniqueness/relationships/coverage, financial conservation/authority/reconciliation, and semantic/API parity. A failed required quality check blocks that partition's publication and preserves the previous accepted revision. Partial availability remains explicit. Every alert names the owner, impact, first failing durable state and safe recovery action.

## Backup and recovery design

Aurora PostgreSQL: encrypted automated backups/PITR with35-day retention and deletion protection; daily protected snapshots under approved retention; restore into a new cluster, validate RLS/migrations/outbox fences, then controlled endpoint cutover. Target RPO≤5min and RTO≤4h for a same-region control-plane incident, demonstrated by a timed drill. [Aurora PITR](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-pitr.html). A restore rolls back business workflow too: reconcile delivered notification/report IDs before resuming dispatch to avoid replaying old side effects. Redis is rebuilt; losing it must not lose accepted jobs, leases or permissions.

S3 journal retention90 days alone cannot recover400 days of facts. Therefore create a daily consistent canonical analytical recovery snapshot covering all retained ledger/history/config versions and required closed-statement evidence, with publication manifest/checksums. Store encrypted private snapshots for35 days in a separate restricted recovery location. Preserve longer evidence according to contracted policy. A snapshot plus subsequent accepted journal restores the current state; raw history older than90 days is not promised as raw replay. Test an old partition outside raw retention. Snowflake Time Travel is useful short-term protection, not the sole disaster-recovery strategy. Confirm edition/retention and actual central account recovery options before launch. Optional Snowflake replication or approved S3 cross-region backup is a separate residency/cost decision, with measured replication lag; do not claim zero-loss regional failover by default. [S3 replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html).

Analytical target RPO≤24h for daily snapshot-only old-history changes, and no loss of acknowledged S3 batches within the surviving journal; RTO≤8h for the benchmark footprint. Measure actual values. Recovery in a new Snowflake account must recreate WIF users, storage integration trust, row policies, manifests and current permission profiles. Traffic remains blocked until isolation, totals and watermarks are verified. Reapply deletion tombstones and revoke obsolete identities before serving recovered data.

## Scale and internal economics

Benchmark profile:100 tenants, each5 accounts, up to1M queries/account/day,365 days requested history; plus a burst from one tenant at10× steady rate. Start below this load, document actual capacity and refuse unsupported quotas. Partition pruning, aggregate marts, fair queues, streaming extraction, file sizing and bounded concurrency must be tested with skew. No need to load182.5B synthetic rows just to claim the target: publish both representative executed volume and extrapolation assumptions, then test the bottleneck with an approved live benchmark budget.

Measure AWS CUR/cost allocation, ECS runtime, network/NAT, S3 operations/storage, central Snowflake compute/storage/Snowpipe, observability, messaging and support allocation. Internal operational cost facts live in a separate Snowflake namespace inaccessible to customers. PostgreSQL stores plans/entitlements/commercial references only. Shared cost allocation uses declared drivers and an explicit unallocated bucket. Gross margin=(recognized revenue−allocated COGS)/recognized revenue; zero revenue → null margin. Fixture: revenue1000, compute100, AWS120, support80 givesCOGS300 and margin70%. Revenue recognition/accounting treatment requires finance approval before external reporting; estimates are labelled.

## Security qualification and support

Threat tests cover BOLA/IDOR, SQL injection, cross-tenant cache/cursor/job/report leakage, Cognito/JWT confusion, CSRF/session fixation, webhook SSRF, scope revocation, S3 prefix/IAM escape, Snowflake CURRENT_USER policy bypass, administrative identity separation and supply-chain vulnerabilities. No unresolved critical/high exploit with tenant disclosure may launch. Audit store access, retention/deletion and support access are tested. Support access is time-bound, reason-coded, approved by customer policy and audited; no shared admin passwords or unaudited impersonation.

Use [operational runbooks](RUNBOOKS.md) for diagnosis and recovery. Exercises record start, detection, owner, containment, restoration, expected/observed totals, customer impact and corrective task. Incident severity is based on actual exposure/availability, with a named incident commander and communication owner. This documentation does not send notifications or grant support access.


## Implementation sequence

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [OPS-001](../tasks/OPS/OPS-001.md) | Instrument shared telemetry and operational dashboards | INF-005, CTL-004 | M3 |
| [OPS-002](../tasks/OPS/OPS-002.md) | Implement publication quality gates and financial canaries | DBT-006, FIN-009, OPS-001 | M4 |
| [OPS-003](../tasks/OPS/OPS-003.md) | Qualify SLOs, synthetic probes and alert routing | OPS-001, GOV-007, RPT-005 | M9 |
| [OPS-004](../tasks/OPS/OPS-004.md) | Run adversarial tenant isolation and security qualification | SEC-006, SEC-008, API-006, RPT-005, GOV-007 | M9 |
| [OPS-005](../tasks/OPS/OPS-005.md) | Implement retention, deletion and audit verification | SEC-007, SEC-008, RPT-005, CTL-007 | M9 |
| [OPS-006](../tasks/OPS/OPS-006.md) | Rehearse control-plane backup and recovery | INF-004, INF-003, INF-006, CTL-004, OPS-005 | M9 |
| [OPS-007](../tasks/OPS/OPS-007.md) | Implement analytical snapshots and replay recovery drill | ING-011, FIN-010, OPS-005 | M9 |
| [OPS-008](../tasks/OPS/OPS-008.md) | Benchmark concurrency, noisy-neighbor protection and capacity | API-004, ORC-006, OPS-002, RPT-005 | M9 |
| [OPS-009](../tasks/OPS/OPS-009.md) | Measure Bridge unit economics and internal cost allocation | OPS-008, FIN-002 | M9 |
| [OPS-010](../tasks/OPS/OPS-010.md) | Publish support runbooks and run incident exercises | OPS-003, OPS-004, OPS-006, OPS-007 | M9 |
| [OPS-011](../tasks/OPS/OPS-011.md) | Complete cross-product QA and release evidence matrix | OPS-004, OPS-008, OPS-010, INS-007, RPT-005, GOV-008, ALC-008, UX-008 | M9 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

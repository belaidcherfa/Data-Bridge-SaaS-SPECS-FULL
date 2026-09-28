# OPS — Implementation-readiness review and production backlog

Canonical contract: [operations.md](../../16-observability/operations.md), [RUNBOOKS.md](../../16-observability/RUNBOOKS.md), [ADR-009](../../architecture/adr/ADR-009-privacy-and-retention.md), [ADR-011](../../architecture/adr/ADR-011-analytical-recovery.md). Tasks reviewed: OPS-001, OPS-002, OPS-003, OPS-004, OPS-005, OPS-006, OPS-007, OPS-008, OPS-009, OPS-010, OPS-011. Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

## 1. Verdict

Not implementable as specified. The operations contract states good intentions (correlation IDs, 99.9 %, RPO/RTO, daily canonical snapshot, retention periods, 70 % margin fixture) but defines almost none of the mechanisms: SLIs have no numerator/denominator/measurement source, "warm/cold" and "source availability" are undefined, the analytical snapshot has no physical design, deletion tombstones live inside the very stores a restore rolls back, retention has no per-store enforcement, and support access / operator tooling / on-call / pentest / SOC 2 evidence have no owning task. The biggest schedule risk is timing: 9 of 11 OPS tasks sit at M9, after all product work, although logging schema, trace propagation, alert routing, on-call, backup drills, tombstones and cost tags must exist from M1–M3 or they are retrofitted into ~120 tasks. Author first: telemetry contract (OPS-001), SLO catalogue (OPS-003), tombstone registry (OPS-104), recovery design (OPS-007-S01..S04) and the re-milestoned graph in §4.0.

## 2. Findings

### G-OPS-01 · Operational foundations scheduled after all product work
Severity: BLOCKER · Type: RISK
Evidence: `docs/00-project/task-index.json` — OPS-003..OPS-011 all `"milestone": "M9"`; `DEPENDENCY_GRAPH.md` — "OPS-001 telemetry starts M3"; `OPS-006` deps include `OPS-005` (M9) although the Aurora cluster exists from INF-004 (M1).
Why it matters: every service built in M1–M8 (≈120 tasks) would emit ad-hoc logs without the correlation/redaction schema, no alert would page anyone while live synthetic Snowflake data flows from M2, the first restore drill would happen after 8 milestones of schema growth, and cost tags (PRD §139) would be missing from months of central Snowflake history needed for OPS-009. Retrofitting is rework, and the M9 "qualification" becomes first implementation.
Resolution: adopt the re-milestoned graph in §4.0: OPS-001 → M1 (telemetry contract + library), OPS-102 alert routing/on-call → M1, OPS-104 tombstone registry → M1, OPS-108 SOC 2 evidence baseline → M1 (continuous), OPS-103 synthetic Snowflake canary org → M2, OPS-006 first PITR drill → M2, OPS-106 operator CLI/support access → M3, OPS-109 cost-attribution tags → M3, OPS-105 capacity probes → M3/M5, OPS-003 SLOs → M5, OPS-007 analytical recovery → M5, OPS-005 deletion workflow → M7. M9 keeps only final qualification (OPS-004, OPS-107, OPS-008, OPS-009, OPS-010, OPS-011). This challenges `DEPENDENCY_GRAPH.md` ("OPS-001 telemetry starts M3").
Affects: OPS-001, OPS-003, OPS-005, OPS-006, OPS-007, OPS-009, all new OPS-1xx.

### G-OPS-02 · SLIs undefined; freshness target contradicts the extraction cadence
Severity: HIGH · Type: AMBIGUITY / CONTRADICTION
Evidence: `operations.md` — "warm interactive p95≤2s, cold p95≤10s … publish fresh accepted data within30min after source availability"; "warm/cold" appears nowhere else (grep); PRD §63 — "sub-second experience after cache and low-seconds cold response"; D-08 — "default steady-state cadence batched hourly per account"; `source-catalog.md` QUERY_HISTORY — "15m cadence … documented latency up to 45m".
Why it matters: (a) "source availability" is not observable — ACCOUNT_USAGE does not expose when a row became visible, so the 30-min SLI cannot be computed for customer accounts; (b) with hourly cadence (D-08) a row that becomes available at hh:01 is first read at hh+1:00, so "≤30 min after source availability" is violated by construction for most rows; (c) under D-06, publication waits for the next multi-tenant dbt run — a 30-min dbt cadence alone consumes the whole budget; (d) "warm" could mean Redis hit, Snowflake result-cache hit or running warehouse, giving three incompatible dashboards.
Resolution: adopt the SLO catalogue in OPS-003 (normative): FRESH-1 measures Bridge processing latency `publication_committed_at − manifest.committed_at` (p95 ≤ 30 min; requires dbt trigger ≤ 15 min or sensor-on-accepted-batch); FRESH-E2E is a reported decomposition (source latency / cadence wait / extraction / Snowpipe / dbt / publish, PRD §43), not an SLO, measured exactly only on canary accounts (OPS-103) where the probe query's execution time is known. Warm = Bridge result-cache hit (`x-bridge-cache: hit`); cold = cache miss executed by the broker, including warehouse resume. Record the D-08 hourly vs 15-min conflict to the ING owner: steady-state cadence per source must be ≤ 60 min and the customer-facing "current through" must show it.
Affects: OPS-003, OPS-101, OPS-103; cross-domain ING-010, ORC-003, API-003.

### G-OPS-03 · 99.9 % analytical availability cannot exceed the Snowflake SLA it depends on
Severity: HIGH · Type: RISK / VENDOR-FACT
Evidence: `operations.md` — "API availability99.9% monthly"; Snowflake publishes a 99.9 % monthly uptime SLA for Enterprise edition and above — VERIFIED (snowflake.com/en/blog/leveling-up-sla-commitment, search snippet 2026-09-27). Every analytical API call is served from the central Snowflake serving views (D-22 broker).
Why it matters: serial composition ALB × ECS × broker × Snowflake ≈ 0.9999 × 0.9995 × 0.999 ≈ 99.84 % expected ceiling for analytical endpoints; a 99.9 % internal target will be missed by design and burn alerts will page for vendor incidents Bridge cannot fix.
Resolution: split: SLO-AVAIL-CTRL (auth, settings, onboarding, health, non-Snowflake endpoints) 99.9 %; SLO-AVAIL-ANALYTICS 99.5 % in R1 (28-day rolling), raised only after 3 months of measured data. Vendor-caused minutes still count (customers experience them) but incidents are classified `cause=dependency:snowflake` so the error-budget policy (OPS-003) does not freeze releases for them. Contractual SLA remains an owner decision (none in R1, see LCH-104).
Affects: OPS-003, LCH-104.

### G-OPS-04 · Request-based burn alerts are meaningless at first-customer traffic
Severity: HIGH · Type: GAP
Evidence: `OPS-003` — "Add multi-window burn alerts"; `launch.md` — "Rollout starts with synthetic smoke checks and the approved first customer".
Why it matters: one tenant with a handful of users generates perhaps 200–2,000 API requests per day; a single failed request in a 5-minute window is a 100 % error rate → 14.4× burn page at 3 a.m. for one timeout, while a 2-hour silent outage outside business hours produces zero requests and zero alerts.
Resolution: availability SLI = union of (a) real-request events and (b) synthetic probe events (1-min API probe + 5-min login probe = 43,200 + 8,640 events per 30 days). Burn-rate alerts evaluate only when the window has ≥ 50 valid events, otherwise fall back to the probe-only SLI; probe absence for 5 min is itself an alarm (`TreatMissingData=breaching`). This also closes the OPS-003 oracle "Missing probe data alerts rather than becoming100% uptime".
Affects: OPS-003, OPS-103.

### G-OPS-05 · Synthetic canaries need a continuously active Snowflake estate that nobody owns or budgets
Severity: HIGH · Type: GAP
Evidence: `operations.md` — "Synthetic canaries use two synthetic tenants and never mutate customer workloads"; `validation-strategy.md` — "Dedicated synthetic accounts"; no task creates or funds them. ACCOUNT_USAGE latencies: QUERY_HISTORY ≤ 45 min, WAREHOUSE_METERING_HISTORY ≤ 3 h compute / 6 h cloud services, QUERY_ATTRIBUTION_HISTORY "up to 8h" (`source-catalog.md`).
Why it matters: without generated workload the canary tenant's ledger is empty and every financial canary passes vacuously; with un-capped workload it silently costs credits. Because of source latency, a canary check for hour H can only be evaluated at H+2 h (queries), H+7 h (metering) and H+10 h (attribution) — a naive "check last hour" canary always fails.
Resolution: new task OPS-103: a Bridge-owned synthetic Snowflake organization with two accounts (SYN_A Enterprise, SYN_B Standard; different regions), an hourly deterministic workload task (20 tagged queries + 1 intentionally failing query on an XSMALL warehouse, AUTO_SUSPEND=60), resource monitors that suspend at the monthly quota, and lagged oracles (count at H+2 h; metering row at H+7 h; Σ query-attributed + idle = metered compute for the warehouse-hour at H+10 h). Staging and production extract the same accounts through separate service users scheduled at the same minute so both share one warehouse resume. Cost estimate (ASSUMPTION, TO VERIFY LIVE): generator ≈ 100 s billed/h ≈ 0.028 credits/h ≈ 20 credits/month/account; Bridge extraction ≈ 150 s/h ≈ 30 credits/month/account → ≈ 100 credits/month for two accounts ≈ USD 400/month at USD 3.9–4.0/credit.
Affects: OPS-003, OPS-011, new OPS-103; cross-domain CON-002/CON-005 (reuse the same accounts for live WIF tests).

### G-OPS-06 · "Daily consistent canonical snapshot" has no physical design; cross-account clone is impossible
Severity: BLOCKER · Type: GAP / VENDOR-FACT
Evidence: `ADR-011` — "Snapshot all retained analytical facts/config versions … daily into a separately restricted recovery location"; `OPS-007` — one line "Export consistent canonical recovery snapshots".
Why it matters: an implementer must choose between full daily unloads (400 days re-exported every day), Time Travel (same account, ≤ 90 days), cloning (same account only), replication (edition/cost/residency) or Snowflake Backups; each has different RPO/RTO, cost and erasure behaviour. A naive full daily unload of 400 days multiplies compute and storage by the retention length.
Resolution: three tiers, specified in OPS-007:
- Tier 1 (fast logical recovery, R1): Snowflake Backups on the LEDGER/SERVING/CONFIG/SECURITY databases, daily, 35-day expiry, **no retention lock** (lock is irreversible and needs Business Critical — ADR-009 forbids irreversible locks). Backups are zero-copy WORM snapshots restorable with `CREATE … FROM BACKUP`, GA 2025-12-10, same account/region only; cross-account requires replication — VERIFIED (docs.snowflake.com/en/user-guide/backups and release note 2025-12-10, search snippets 2026-09-27). Protects against bad DML/DROP, not account loss.
- Tier 2 (independent copy, R1): incremental Parquet export of **new immutable revisions only** (D-05 makes revisions write-once, so each revision is exported exactly once) via `COPY INTO @recovery_stage … PARTITION BY (…) FILE_FORMAT=(TYPE=PARQUET) HEADER=TRUE` with session `ENABLE_UNLOAD_PHYSICAL_TYPE_OPTIMIZATION=FALSE` so decimal precision is stable (default narrows precision — VERIFIED, docs.snowflake.com/en/sql-reference/sql/copy-into-location snippet 2026-09-27), into an S3 bucket in a separate AWS recovery account; a daily manifest pins the publication map read `AT(TIMESTAMP => T)` plus per-revision row counts, `HASH_AGG` and per-currency amount sums. R1 volume estimate 50–150 GB → < USD 5/month storage, 3–8 credits/month export compute.
- Tier 3 (regional, R2, owner decision): database replication to a second EU account (available on all editions; failover groups need Business Critical — VERIFIED, docs.snowflake.com/en/user-guide/account-replication-intro snippet 2026-09-27).
- Refuted: "clone into another account" — zero-copy clone is intra-account; the only cross-account copies are replication or unload/load.
Affects: OPS-007, new OPS-111 (R2).

### G-OPS-07 · Deletion tombstones are stored inside the stores a restore rolls back
Severity: BLOCKER · Type: GAP
Evidence: `RUNBOOKS.md` RB-10 — "reapply deletion tombstones"; RB-11 — "reapply deletions"; `OPS-005` — "record tombstone outside recoverable customer dataset" but no location/format; OPS-006 data model — "deletion epoch".
Why it matters: tenant T is deleted on day D; an incident on D+3 requires Aurora PITR to D−1 and analytical restore from the D−1 snapshot. Both the PG tombstone row and the Snowflake deletion are rolled back, so the restore resurrects T with its identities and schedules — an unlawful re-processing event and a disclosure risk if T's former users still exist.
Resolution: new task OPS-104 (M1): append-only tombstone log with monotonic `seq`, written transactionally to PG `privacy.tombstones` **and** (via outbox) to a versioned S3 bucket in the security/log-archive account (`tombstones/seq=<20-digit>.json`, no personal data: tenant UUID, account UUID, subject HMAC, dataset/range, effective_at). Every recovery manifest records `tombstone_hwm`; every restore procedure replays **all** tombstones from the S3 log (idempotent) before enabling traffic. Tenant-level offboarding additionally schedules deletion of the tenant's KMS key for the D-10 identity dictionary (waiting period 7–30 days, default 30 — VERIFIED, docs.aws.amazon.com/kms/latest/APIReference/API_ScheduleKeyDeletion.html snippet 2026-09-28) so that ciphertext in PG/Snowflake backups becomes unreadable independent of restore discipline.
Affects: OPS-005, OPS-006, OPS-007, new OPS-104; cross-domain D-10 owner (SEC).

### G-OPS-08 · Side-effect reconciliation after Aurora restore has no external truth to reconcile against
Severity: HIGH · Type: GAP
Evidence: `operations.md` — "reconcile delivered notification/report IDs before resuming dispatch"; `CTL-004` — outbox state lives in PG; RB-10 — "reconcile external side effects".
Why it matters: after PITR to T−Δ, outbox rows sent during Δ are back in PENDING; PG alone cannot tell which were delivered, so either duplicates are sent (Slack/Teams/email/webhook) or real alerts are silently dropped. Likewise job leases restored to an older generation let pre-incident workers commit with tokens the restored DB believes valid; ingestion checkpoints rewind and trigger re-extraction (customer credits, D-08).
Resolution: (1) dispatcher appends every provider-accepted delivery `{event_id, attempt_id, provider_message_id, accepted_at}` to an out-of-band dispatch journal (S3, append-only, 400 days) — OPS-006 reconciles `outbox WHERE status IN ('PENDING','IN_FLIGHT')` against it and marks matches `DELIVERED_RECONCILED`; (2) a global `control.lease_epoch` is incremented as the first post-restore write and every lease claim/commit compares epoch — tokens minted before restore are rejected; (3) coverage/watermarks are re-derived from Snowflake acceptance receipts and S3 manifests (anti-entropy, ING-011) before schedulers resume; (4) user mutations lost in Δ are listed from the S3 audit export (SEC-008 — outside PG) and communicated.
Affects: OPS-006; cross-domain CTL-004, GOV-007, ING-008.

### G-OPS-09 · Retention is a list of numbers without per-store enforcement; several defaults silently keep data forever
Severity: HIGH · Type: GAP / VENDOR-FACT
Evidence: `ADR-009` — "S3 replay 90 days, RAW 90 days, canonical 400 days, reports 30 days, audit 365 days"; PRD §128 — "Separate policies … Dagster history"; ingestion prefix `landing/source=…/schema_major=…/tenant_id=…` (`ingestion.md`).
Why it matters: (a) CloudWatch log groups default to "Never expire" — VERIFIED (docs.aws.amazon.com/AmazonCloudWatchLogs/latest/APIReference/API_PutRetentionPolicy.html snippet 2026-09-28); (b) deleting an object in a versioned bucket creates a delete marker and keeps the data; (c) the source-first prefix puts `tenant_id` at the third level, so no single prefix or lifecycle filter selects one tenant — tenant deletion needs enumeration; (d) Snowflake keeps deleted rows for the Time Travel period plus a non-configurable 7-day Fail-safe on permanent tables; transient tables have no Fail-safe and ≤ 1 day Time Travel — VERIFIED (docs.snowflake.com/en/user-guide/data-failsafe, data-time-travel snippets 2026-09-27); (e) D-05 insert-only revisions grow without bound unless superseded revisions are garbage-collected; (f) Snowflake Backups are immutable, so tenant rows persist in them until expiry.
Resolution: the per-store retention matrix in OPS-005 (normative), with a Terraform policy test rejecting any log group without `retention_in_days`, lifecycle rules with `NoncurrentVersionExpiration` and `AbortIncompleteMultipartUpload`, S3 Inventory + Batch Operations for version-complete tenant deletion, TRANSIENT staging/intermediate tables, `DATA_RETENTION_TIME_IN_DAYS=1` on RAW, 7 on canonical, a revision GC job (collectible when not in any publication map, not pinned by a closed statement, not referenced by an active job/cursor, older than 7 days), and a published residual-copy statement ("active systems ≤ 30 days; backups ≤ 35 days; Snowflake Fail-safe ≤ 7 days after Time Travel, not accessible to Bridge").
Affects: OPS-005, OPS-104; cross-domain INF-003 (lifecycle), DBT-006 (revision GC hook).

### G-OPS-10 · No DSAR, subject erasure or legal-hold flow; controller/processor roles unstated
Severity: HIGH · Type: GAP
Evidence: grep for "DSAR", "erasure", "legal hold", "GDPR" in `docs/**` (excluding tasks) → no hits; `OPS-005` — "approved holds", "indefinite hold" listed only as failure.
Why it matters: customer Snowflake metadata contains personal data (USER_NAME, emails in tags, query text). Under GDPR the customer is controller and Bridge processor (Art. 28(3)(e) assistance duty); Bridge is controller for its own account/billing contacts. Controllers must answer within one month (Art. 12(3)). Without a defined flow, an erasure request either cannot be honoured (immutable journal) or is honoured by ad-hoc deletes that break ledger immutability.
Resolution: OPS-005 implements three request types — `SUBJECT_ACCESS` (export dictionary entries + pseudonym-linked activity for one subject), `SUBJECT_ERASURE` (D-10: delete dictionary entry → pseudonym becomes unresolvable, display "Erased user ‹hash4›"; tombstone kind SUBJECT), `TENANT_DELETION` (ordered purge) — each with intake only from an authenticated tenant Owner/Admin (requests arriving directly from a data subject are forwarded to the controller within 2 business days, not executed), preview, legal-hold check, 30-day due date, stage tracking and a deletion certificate. Legal holds: `privacy.legal_holds` with scope, reason, approver and `review_by ≤ 90 days`; an expired review raises a ticket, never silently releases or extends. Role statement goes to the DPA (LCH-102); legal wording TO VERIFY with counsel.
Affects: OPS-005, LCH-102.

### G-OPS-11 · 100 tenants × 5 accounts × 1M queries/day is not a first-release capacity target
Severity: MEDIUM · Type: OVER-ENGINEERING / RISK
Evidence: `operations.md` — "Benchmark profile:100 tenants, each5 accounts, up to1M queries/account/day,365 days"; computation 100 × 5 × 1,000,000 × 365 = 182.5 B query rows (the spec itself says "No need to load182.5B synthetic rows").
Why it matters: qualifying at that profile before R1 costs benchmark credits and weeks while the first customer needs ~5 accounts; conversely, a "we extrapolate" statement with no staged target leaves admission quotas unset (OPS-008 oracle requires "release capacity reduced" if unproven).
Resolution: staged capacity targets in OPS-008: C1 (R1 launch gate, executed) = 10 tenants × 5 accounts, median 300 k queries/account/day, p90 1 M, one skew account at 3 M/day, two tenants backfilling 365 days concurrently while eight are steady; 30 concurrent interactive users; 50 report runs/day. C2 (R2, executed) = 50 × 5 with 10 % of accounts at 1 M/day. C3 (PRD profile) = extrapolation plus one live bottleneck test. Admission quotas are set from C1 measurements and enforced by LCH-101 entitlements (refuse tenant #11 until C2 evidence). Early probes (OPS-105, M3/M5) feed D-06/D-07 before architecture is frozen.
Affects: OPS-008, new OPS-105, LCH-101.

### G-OPS-12 · Per-tenant cost attribution is impossible as tagged in PRD §139 once dbt runs are multi-tenant
Severity: HIGH · Type: CONTRADICTION / GAP
Evidence: PRD §139 — "bridge_tenant=… so Bridge Data can understand the cost of processing each customer"; D-06 — "Multi-tenant set-based runs"; `OPS-009` — "allocate shared costs by declared drivers".
Why it matters: a MERGE/INSERT that processes 40 tenants' batches carries one QUERY_TAG; per-tenant tagging would force per-tenant dbt invocations (rejected by D-06). Without a declared driver, the gross-margin dashboard is arbitrary, and customer-side extraction credits (D-08) risk being mixed into Bridge COGS.
Resolution: attribution drivers (normative for OPS-009/OPS-109): serving compute = direct, from central `QUERY_ATTRIBUTION_HISTORY` by the tenant's WIF service user (D-02 makes this exact) + serving idle pro rata; transform compute = per-run credits from `QUERY_ATTRIBUTION_HISTORY` joined on QUERY_TAG `{"c":"dbt","run":<id>}`, split by `ops.processing_ledger.input_rows` per tenant (fallback `input_bytes`); Snowpipe = per-pipe credits split by manifest bytes per tenant — exact because Snowpipe is billed at 0.0037 credits/GB since 2025-12-08 — VERIFIED (docs.snowflake.com release note 2025-12-08 snippet 2026-09-27); storage = table bytes split by tenant row share (labelled estimate); AWS = CUR by `component` tag, ECS tasks by task-seconds per tenant, NAT by extracted bytes, shared services by declared drivers with explicit unallocated residual. Customer-side credits (D-08) are a disclosed customer cost shown as "Bridge overhead" in the product, never in `tenant_platform_cost`. PRD §139's `bridge_tenant` tag applies only to single-tenant queries (serving, extraction); challenge recorded.
Affects: OPS-009, new OPS-109.

### G-OPS-13 · Baseline platform cost and price floor unknown — gross-margin target cannot be checked
Severity: HIGH · Type: GAP
Evidence: `operations.md` — "Gross margin=(recognized revenue−allocated COGS)/recognized revenue"; D-17 — "OWNER INPUT"; fixture revenue 1000, COGS 100+120+80 = 300 → margin 700/1000 = 70 % (arithmetic checked, correct).
Why it matters: at R1 scale the fixed platform cost dominates; if the owner prices below the floor, every added tenant still loses money until N grows.
Resolution: OPS-009 carries the R1 cost model below (all unit prices ASSUMPTION, eu-west-1 list prices, TO VERIFY LIVE with AWS Pricing Calculator and the Snowflake order form; London Enterprise credit USD 4.00 per search snippet 2026-09-27). Monthly: production AWS ≈ USD 1.2–1.5 k (NAT 2 AZ ≈ 85, interface endpoints 8×2 AZ ≈ 130, Fargate ≈ 270, Aurora 2 instances ≈ 140–430, Redis ≈ 55, CloudWatch logs/metrics/Synthetics/X-Ray ≈ 295, security services ≈ 70, other ≈ 110); staging ≈ 0.65–0.8 k; dev ≈ 0.25–0.4 k. Central Snowflake production ≈ 280–400 credits (transform XS every 15 min ≈ 243 credits; every 30 min ≈ 122; serving XS ≈ 130; ops ≈ 30; Snowpipe < 1) ≈ USD 1.1–1.6 k; staging+dev ≈ 0.4–0.6 k; canary accounts ≈ 0.4 k. Fixed production COGS F ≈ USD 3.1 k/month; variable per 5-account tenant v ≈ USD 80–200 (mid 140). Price floor P ≥ (F/N + v)/(1 − GM): at GM 75 % → N=1: USD 12,960; N=3: 4,693; N=10: 1,800; N=30: 973 per tenant-month (support staff excluded; 0.25 FTE at ≈ USD 2.2 k/month raises N=10 to 2,680). This is an input to D-17, not a pricing decision. Biggest lever: dbt cadence (15 → 30 min halves transform credits but needs the FRESH-1 target at 45 min).
Affects: OPS-009, LCH-001; D-17.

### G-OPS-14 · Security qualification lacks an external test, a disclosure channel and SOC 2 evidence generation
Severity: HIGH · Type: GAP
Evidence: grep "penetration", "pentest", "bug bounty", "SOC" in `docs/**` → only `21-ui-ux/VALIDATION.md` ("A denied UI scenario is not a security penetration test"); D-25 — "Build SOC 2-ready controls (audit, access reviews, change evidence) in R1".
Why it matters: enterprise FinOps buyers send security questionnaires asking for a third-party pentest letter and SOC 2 status; a Type II report needs an observation window of several months of evidence that must be generated from the day controls start — evidence cannot be back-filled at M9.
Resolution: new OPS-107 (M9, booked at M6): grey-box external pentest of web/API/auth/tenant isolation/report links/webhooks plus AWS and central Snowflake configuration review, 8–12 tester-days (cost ASSUMPTION EUR 12–25 k, owner budget), fixes retested before REL-004; `/.well-known/security.txt` (RFC 9116) and a vulnerability disclosure policy in R1; bug bounty R2. New OPS-108 (M1, continuous): automated evidence for change management, quarterly access reviews, vulnerability SLAs (critical 7 d / high 30 d), backup drills, incidents, vendor register and policies. Certification timing stays D-25 owner decision.
Affects: OPS-004, OPS-011, new OPS-107, OPS-108; REL-003.

### G-OPS-15 · Support access, operator identity and the `bridge-admin` CLI have no owning task
Severity: HIGH · Type: GAP
Evidence: `operations.md` — "Support access is time-bound, reason-coded, approved by customer policy and audited"; `RUNBOOKS.md` — "The implementation supplies a read-only `bridge-admin` CLI … FND-005/OPS-010 must test these interfaces"; grep "support access" in `docs/tasks` → only OPS-010's interface line; FND-005 does not mention it.
Why it matters: every runbook RB-01..RB-15 uses `bridge-admin`; without it on-call engineers will use ad-hoc SQL with broad roles — exactly the "unaudited impersonation" the contract forbids. Break-glass for AWS root and central Snowflake ACCOUNTADMIN is also unspecified.
Resolution: new OPS-106 (M3): operator SSO (IAM Identity Center, MFA), read-only `bridge-admin` CLI over an internal ops API, `support.access_grants` (tenant-approved, ≤ 4 h default, ≤ 24 h max, reason + ticket), a support permission profile inside the tenant (D-02) instead of impersonation, customer-visible audit entries, and a two-person break-glass procedure with alarms on use.
Affects: OPS-010, OPS-004; new OPS-106.

### G-OPS-16 · On-call model and tooling unspecified for a small team
Severity: MEDIUM · Type: GAP / VENDOR-FACT
Evidence: `RUNBOOKS.md` — "never promise24×7 response without a staffed rota"; `CHECKLIST.md` — "named on-call"; no task configures paging.
Why it matters: a sustainable 24×7 primary/secondary rota needs roughly 5–6 engineers (one week in six); with 2–3 engineers it burns out or is fictional. Tool choice matters: Atlassian ended Opsgenie sales on 2025-06-04 and ends support 2027-04-05 — VERIFIED (support.atlassian.com / hyperping.com snippets 2026-09-27) — a new integration on it would be migrated within months.
Resolution: OPS-102: business-hours coverage (e.g. 08:00–19:00 Europe/Paris, Mon–Fri; primary + secondary), out-of-hours paging only for SEV1 classes (suspected disclosure, total outage, broadly served financial corruption) with best-effort 60-min acknowledgment, paging tool chosen from those with a future (not Opsgenie), CloudWatch alarm → SNS → paging integration, every alarm carries `owner`, `severity`, `runbook_url`, `impact` tags (policy test rejects alarms without them). Contract/support policy must match (LCH-104).
Affects: OPS-003, OPS-010; new OPS-102, LCH-104.

### G-OPS-17 · Quality gates have no catalogue; "required vs advisory" and stale-success reuse are undefined
Severity: MEDIUM · Type: AMBIGUITY
Evidence: `OPS-002` — "Implement transport, transformation and financial invariant families with explicit required versus advisory severity"; failure list "stale success reused; missing gate record"; D-06 — "a failing tenant partition is excluded from that tenant's pointer advance".
Why it matters: without check IDs keyed to the candidate revision, a PASS computed on revision r1 can authorize publishing r2; without an ERROR state, a check that crashed looks like "no failure".
Resolution: the gate catalogue in OPS-002 (T01–T04 transport, X01–X04 transformation, F01–F06 financial, S01 semantic), results keyed by `(tenant_id, dataset, partition_key, candidate_revision_id, check_id, check_version)`, ERROR/missing = FAIL for gating, per-tenant gating under D-06.
Affects: OPS-002.

### G-OPS-18 · Metric cardinality and CloudWatch cost are unbudgeted
Severity: MEDIUM · Type: RISK
Evidence: `operations.md` — "Bound tenant/resource cardinality"; `OPS-001` oracle — "high-cardinality fixture does not create per-query metric series".
Why it matters: CloudWatch bills each custom metric series (ASSUMPTION ≈ USD 0.30/metric-month, TO VERIFY); `tenant_id × account × source × outcome` labels at C1 (50 accounts × 15 sources × 4 outcomes = 3,000 series) cost ≈ USD 900/month in one environment and exceed the whole R1 observability budget.
Resolution: allowed metric dimensions are a closed list (`env, service, component, lane, source_family, outcome, error_class, plan_tier`); tenant/account/batch IDs only in structured logs and in the internal Snowflake ops facts (`ops.*`), queried by Logs Insights or dashboards on the internal namespace; a CI check fails when a new metric declares a non-allowlisted dimension; budget ≤ 500 active custom series per environment.
Affects: OPS-001, OPS-101.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by |
|---|---|---|
| `packages/telemetry/schema/log-event.v1.json` | JSON Schema: `ts` (RFC 3339 UTC ms), `level`, `env`, `service`, `component`, `version` (image digest), `trace_id`, `span_id`, `request_id`, `run_id`, `batch_id`, `publication_id`, `job_id`, `tenant_id`, `account_ref`, `actor_type` (user/service/operator), `event` (registry name), `outcome` (success/failure/denied/retry/skipped), `error_class` (enum below), `duration_ms`, `attrs` (allowlisted keys only); `additionalProperties:false`. Forbidden keys list: `sql`, `query_text`, `password`, `token`, `authorization`, `email`, `user_name`, `payload`, `body` | OPS-001-S01 |
| `packages/telemetry/error_taxonomy.py` | Enum: `AUTH_EXPIRED, AUTH_DENIED, SOURCE_PERMISSION_DENIED, SOURCE_UNAVAILABLE, SOURCE_SCHEMA_DRIFT, NETWORK_TIMEOUT, SNOWFLAKE_QUERY_TIMEOUT, SNOWFLAKE_QUEUED_TIMEOUT, QUOTA_EXCEEDED, LEASE_LOST, VALIDATION_FAILED, QUALITY_GATE_FAILED, DEPENDENCY_UNAVAILABLE, CONFLICT, INTERNAL_BUG`; each with retryable flag and customer-visible category | OPS-001-S02 |
| `packages/telemetry/metrics-registry.yaml` | Every metric: name `bridge_<component>_<measure>_<unit>`, type, unit, allowed dimensions (closed list), owner, alarm refs; CI rejects unknown names/dimensions | OPS-001-S05 |
| `docs/operations/propagation.md` | W3C `traceparent` carriers: HTTP header; outbox column `traceparent`; SQS message attribute; ECS RunTask env `TRACEPARENT`; Dagster run tag `bridge/traceparent`; Snowflake QUERY_TAG JSON `{"c":<component>,"r":<run_id>,"t":<trace_id[0:16]>,"tn":<tenant or "multi">}` (≤ 2000 chars) | OPS-001-S03 |
| `infra/observability/slo/slo-catalog.yaml` | For each SLO: id, SLI numerator/denominator, exclusions (explicit, counted), source (ALB logs / API histogram / ops facts / probes), window (28-day rolling), target, burn alerts, owner, error-budget policy link (content in OPS-003 table) | OPS-003-S01 |
| `data/quality/gate-catalog.yaml` | Check id, family, version, SQL/asset reference, severity REQUIRED/ADVISORY, scope (partition), expected/observed schema, blocking rule (content in OPS-002) | OPS-002-S01 |
| DDL `ops.quality_results` (Snowflake) | `(tenant_id, dataset, partition_key, candidate_revision_id, check_id, check_version, status PASS/WARN/FAIL/ERROR, severity, observed VARIANT, expected VARIANT, evidence_ref, run_id, evaluated_at)`; PK first six columns | OPS-002-S02 |
| DDL `privacy.tombstones` (PG) + S3 object schema `tombstone.v1.json` | `seq BIGINT` (identity, gapless not required but monotonic), `tombstone_id UUID`, `kind` TENANT/ACCOUNT/SUBJECT/DATASET_RANGE, `tenant_id`, `account_id NULL`, `subject_hmac NULL`, `dataset NULL`, `range_start/end NULL`, `effective_at`, `request_id`, `legal_basis`, `created_by`; append-only (no UPDATE/DELETE grants) | OPS-104-S01 |
| DDL `privacy.deletion_requests`, `privacy.deletion_stages`, `privacy.legal_holds` (PG) | Request type SUBJECT_ACCESS/SUBJECT_ERASURE/TENANT_DELETION; states RECEIVED→PREVIEWED→APPROVED→HELD/EXECUTING→VERIFIED→CERTIFIED / REJECTED; stages per store with `expected_count`, `deleted_count`, `verified_at`; holds with `scope`, `reason_code`, `approved_by`, `review_by` | OPS-005-S01 |
| `data/contracts/recovery-manifest.v1.json` | `snapshot_id, as_of, central_account_locator, dbt_manifest_sha, schema_versions, publication_map[{tenant_id,dataset,partition_key,revision_id}], revisions[{dataset,tenant_id,partition_key,revision_id,s3_prefix,row_count,hash_agg,amount_sums{currency:decimal}}], config_versions[], security_snapshot_ref, tombstone_hwm, journal_hwm[{source,account_id,accepted_seq}]` | OPS-007-S01 |
| DDL `ops.processing_ledger` (Snowflake, internal) | `(run_id, model, tenant_id, input_rows, input_bytes, output_rows, started_at, ended_at)` written by every multi-tenant dbt run; basis for transform cost split | OPS-109-S02 |
| DDL `internal_cost.*` (separate Snowflake database, no customer grants) | `cost_source_line(provider, account, service, usage_start, usage_end, amount, currency, source_ref, source_version)`, `cost_driver_fact(period, driver, tenant_id, quantity)`, `tenant_platform_cost(period, tenant_id, component, amount, currency, allocation_version, method)`, `unallocated_cost(period, component, amount)` | OPS-009-S01 |
| `support.access_grants` (PG) + ops API OpenAPI `ops-api.v1.yaml` | Grant fields in OPS-106; endpoints `POST /ops/v1/support-grants`, `POST …/{id}/approve` (tenant admin), `POST …/{id}/revoke`, `GET /ops/v1/tenants/{t}/health`, `GET /ops/v1/batches/{id}`, `GET /ops/v1/coverage-diff`, `GET /ops/v1/reconciliations/{id}/explain` | OPS-106-S01 |
| `docs/operations/oncall-policy.md` | Coverage hours, SEV matrix → paging vs ticket, ack targets, escalation chain, handover template, compensation note, alarm tag policy | OPS-102-S01 |
| `docs/security/evidence-catalog.yaml` | Control id → evidence generator → frequency → storage path → reviewer (content in OPS-108) | OPS-108-S01 |

## 4. Revised production backlog

### 4.0 Re-milestoning and dependency corrections (summary)

| Task | Milestone now → proposed | Dependencies now → proposed | Reason |
|---|---|---|---|
| OPS-001 | M3 → **M1** | INF-005, CTL-004 → **FND-003, INF-005**; add edge CTL-004 +OPS-001 and ING-003 +OPS-001 | library must exist before the first worker/outbox is written |
| OPS-102 (new) | → M1 | OPS-001, INF-006 | alarms must page someone from first staging deploy |
| OPS-104 (new) | → M1 | CTL-002, INF-003, SEC-001 | tombstones must precede any restore drill |
| OPS-108 (new) | → M1 (continuous) | INF-007, SEC-008 | SOC 2 evidence window starts when controls start |
| OPS-006 | M9 → **M2** (re-run M10) | −OPS-005, −INF-006, −INF-003 (transitive) → INF-004, CTL-004, OPS-104, OPS-102 | drill needs tombstone log, not the full deletion workflow |
| OPS-103 (new) | → M2 | INF-008, CON-003 | live WIF tests and canaries need synthetic accounts |
| OPS-101 (new) | → M3 | OPS-001, ING-007, ORC-003 | pipeline dashboards/freshness emitters |
| OPS-106 (new) | → M3 | SEC-008, INF-006, ING-007 | runbooks need `bridge-admin` |
| OPS-109 (new) | → M3 | OPS-001, ORC-003, INF-008 | cost tags must be present in history OPS-009 reads |
| OPS-105 (new) | → M3 (+M5 part) | ING-008, ORC-003, OPS-101; part B +API-003 | capacity evidence before D-06/D-07 freeze |
| OPS-002 | M4 | +OPS-101 | dashboards consume gate results |
| OPS-003 | M9 → **M5** | −GOV-007, −RPT-005 → OPS-101, OPS-102, OPS-103, API-003 | API/freshness SLOs needed at first serving; delivery SLIs moved to OPS-110 |
| OPS-007 | M9 → **M5** | −OPS-005 → ING-011, FIN-010, DBT-006, OPS-104 | 90-day journal horizon expires ~60–90 days after first backfill |
| OPS-110 (new) | → M7 | OPS-003, GOV-007, RPT-005 | delivery SLIs |
| OPS-005 | M9 → **M7** | +OPS-104 | deletion workflow once reports exist |
| OPS-004, OPS-008, OPS-009, OPS-010, OPS-011 | M9 | +OPS-106 (004, 010); +OPS-105 (008); +OPS-109 (009); +OPS-110 (010); +OPS-107 (011) | final qualification only |
| OPS-107 (new) | → M9 (book at M6) | OPS-004 | external test after internal suite |
| OPS-111 (new, R2) | → R2 | OPS-007 | regional replication |

Cross-domain edges requested from other owners: REL-003 +OPS-107; ONB-101 +OPS-105; LCH-101 consumes OPS-008 C1 quotas.

### OPS-001 — Instrument shared telemetry contract, correlation and platform dashboards
Release: R1 · Estimate: 34–52 h · Risk: M · Decisions: D-06, D-07, D-22 · Closes: G-OPS-01, G-OPS-18
Dependency changes: `−CTL-004` (reversed: CTL-004 +OPS-001 so the outbox carries `traceparent` from day one), `+FND-003` (library tested in local Compose); milestone M3 → M1. Ingestion/dbt dashboards move to OPS-101.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-001-S01 | Author the log event JSON Schema with the field list and forbidden-key list from §3; add 10 valid and 10 invalid fixtures (missing `trace_id`, extra `sql` key, non-UTC `ts`, unknown `error_class`). | `packages/telemetry/schema/log-event.v1.json`, `tests/spec/OPS-001/fixtures/` | Schema validator accepts 10/10 valid and rejects 10/10 invalid fixtures. | 3 |
| OPS-001-S02 | Implement the error taxonomy enum with `retryable` and `customer_category`; map Snowflake connector auth/network/timeout exceptions, botocore throttling and SQLAlchemy errors to classes; unknown exceptions map to `INTERNAL_BUG`. | `packages/telemetry/error_taxonomy.py` | Table-driven test maps ≥ 25 exception fixtures; no exception escapes unmapped. | 2 |
| OPS-001-S03 | Implement W3C `traceparent` helpers for FastAPI middleware, outbox row column, SQS message attribute, ECS RunTask env `TRACEPARENT`, Dagster run tag `bridge/traceparent`, and the Snowflake QUERY_TAG builder (JSON, keys `c,r,t,tn`, hard cap 2000 chars, truncation drops `tn` first). | `packages/telemetry/propagation.py`, `docs/operations/propagation.md` | Round-trip tests for each carrier preserve trace_id; QUERY_TAG for a 5,000-char input is ≤ 2000 chars and valid JSON. | 4 |
| OPS-001-S04 | Build the structured logger (structlog JSON to stdout) with an allowlist processor that drops non-schema keys and a redaction processor for JWT (`eyJ…\.…\.…`), AWS keys (`(AKIA\|ASIA)[0-9A-Z]{16}`), PEM blocks, `password=`/`secret=`/`token=` pairs and bearer headers → `[REDACTED:<kind>]`. | `packages/telemetry/logging.py` | Planted-secret unit test: 12 fake secrets across message, exception text and nested attrs → 0 survive; performance ≤ 50 µs/event p95. | 4 |
| OPS-001-S05 | Create the metrics registry and an EMF emitter wrapper that refuses at import time any metric/dimension not in the registry; closed dimension list `env, service, component, lane, source_family, outcome, error_class, plan_tier`; CI job diffs registry vs code usage. | `packages/telemetry/metrics-registry.yaml`, `packages/telemetry/metrics.py`, `.github/workflows/telemetry-lint.yml` | Emitting `tenant_id` as a dimension raises in tests; CI fails on an unregistered metric name. | 3 |
| OPS-001-S06 | Add the ADOT collector sidecar module to the ECS task-definition module: OTLP in, traces → X-Ray, metrics → EMF; parent-based head sampling 10 % plus collector tail sampling keeping 100 % of error traces (tail-sampling support in the pinned ADOT build TO VERIFY LIVE). | `infra/observability/adot/`, task-def module input `telemetry = true` | Staging service shows traces in X-Ray; an error span is kept while a success sample rate is ≈ 10 % over 1,000 requests (±3 %). | 4 |
| OPS-001-S07 | Create the CloudWatch log-group Terraform module (KMS-encrypted, `retention_in_days`: app 30, security 90, access 90) and a policy-as-code rule (checkov/conftest) rejecting any `aws_cloudwatch_log_group` without retention. | `infra/modules/log-group/`, `infra/policy/log-retention.rego` | `terraform plan` of a fixture log group without retention fails the policy job. | 2 |
| OPS-001-S08 | Build platform dashboards as code: API RED (rate, errors by class, duration histogram), ECS CPU/memory/restarts, Aurora connections/CPU/replica lag, Redis memory/evictions/hit ratio, SQS oldest-message age and DLQ depth; each widget links a runbook anchor. | `infra/observability/dashboards/platform.json.tftpl` | Dashboards render in staging with live data; every widget has a runbook link (lint). | 4 |
| OPS-001-S09 | Implement the log-leak scanner: CI job over test logs and a nightly staging Logs Insights query for the redaction regexes plus planted canary strings `BRIDGE_CANARY_SECRET_<uuid>` injected by a test endpoint in non-prod only. | `tools/log-leak-scan/`, scheduled job `ops-log-leak-scan` | Planting 5 canaries through API, worker, Dagster and extraction paths → scanner finds 0 plaintext occurrences and reports 5 redaction hits. | 3 |
| OPS-001-S10 | Cardinality test: drive 10,000 distinct query IDs and 200 synthetic tenant IDs through API and a worker; count CloudWatch metric series before/after. | `tests/spec/OPS-001/test_cardinality.py` | Series count delta = 0 for tenant/query dimensions (only pre-registered series exist). | 2 |
| OPS-001-S11 | Restrict telemetry access: log groups and X-Ray readable only by operator permission sets; runtime task roles have no `logs:Get*`/`logs:StartQuery`; customer-facing roles have none. | IAM policies in `infra/iam/telemetry.tf` | IAM policy simulator: API/extractor task roles denied `logs:GetLogEvents` on all groups; ReadOnlyOps allowed. | 2 |
| OPS-001-S12 | End-to-end trace proof in staging: a synthetic request that fails in an outbox-driven worker (forced `VALIDATION_FAILED`) is followed request → outbox event → worker span → ECS task log line. | `docs/evidence/OPS-001/<commit>/trace.md` | One trace_id appears in all four places; Logs Insights query in evidence returns ≥ 4 correlated events. | 3 |
| OPS-001-S13 | Write the developer guide (how to log, name events, emit metrics) and runbook entries for trace dropped, log amplification (> 5× baseline ingest/hour alarm), clock skew (event `ts` vs ingestion time > 5 s alarm). | `docs/operations/telemetry.md`, `docs/runbooks/telemetry.md` | Alarms exist in Terraform with owner/severity/runbook tags; guide reviewed by one non-author. | 2 |

Task acceptance (task-specific, 3–8 items, NO boilerplate):
- [ ] One trace_id links API request, outbox event, worker span and ECS task log for the synthetic failure.
- [ ] 0 of 12 planted secrets and 0 of 5 canary strings appear unredacted in any log group.
- [ ] 10,000 distinct query IDs create 0 new metric series; non-registered dimensions fail CI.
- [ ] A log group without `retention_in_days` cannot be applied.
- [ ] Runtime and customer-facing roles cannot read logs or traces.

### OPS-002 — Implement publication quality gates and financial canaries
Release: R1 · Estimate: 38–58 h · Risk: H · Decisions: D-05, D-06, D-12 · Closes: G-OPS-17
Dependency changes: `+OPS-101` (gate results feed data-health dashboards and ops facts). Milestone M4 unchanged.

Gate catalogue (normative for S01): REQUIRED — T01 every manifest file has a LOADED receipt whose row count equals the manifest; T02 file SHA-256 at upload equals manifest; T03 Σ manifest rows = RAW rows for the batch; T04 schema fingerprint equals the registry version; X01 scoped natural-key uniqueness per staging model; X02 no orphan tenant/account keys (keys ∈ published config); X03 every staging row's batch_id ∈ accepted batches; X04 published window coverage contiguous; F01 Σ `fct_charge` per D-12 billing bucket = Σ authoritative source bucket, exact decimal; F02 warehouse query-attributed + idle = warehouse charge per warehouse-day; F03 allocated + unallocated = eligible per book/currency (when allocation enabled); F04 no aggregate row mixes currencies; S01 serving totals per tenant/month/currency = ledger totals for the candidate. ADVISORY — F05 tenant daily total > 10× trailing 7-day median AND > 100 currency units → WARN; F06 reconciliation status pass-through (blocks close, not publication); optional-source coverage gaps.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-002-S01 | Write the gate catalogue above as data (id, family, version, severity, scope, SQL/asset ref, owner) and get FinOps + Data sign-off. | `data/quality/gate-catalog.yaml` | Catalogue validates against its JSON Schema; two named reviewers recorded. | 3 |
| OPS-002-S02 | Create `ops.quality_results` (PK tenant, dataset, partition_key, candidate_revision_id, check_id, check_version) and an idempotent writer (insert-or-ignore on PK; a changed result for the same PK is an ERROR). | `data/dbt/models/ops/quality_results.sql` (DDL), `services/quality/results.py` | Writing the same result twice → 1 row; conflicting status for same PK → raises and records ERROR. | 2 |
| OPS-002-S03 | Implement T01–T04 as Dagster asset checks over receipts/manifests (ING-005/007 tables). | `services/quality/transport_checks.py` | Fixture batch with 3 files/2 receipts → T01 FAIL; checksum mismatch → T02 FAIL; clean batch → 4 PASS. | 4 |
| OPS-002-S04 | Implement X01–X04 as custom dbt generic tests with an `on-run-end` hook that writes per-partition results keyed by the candidate revision. | `data/dbt/tests/generic/{unique_scoped,no_orphan_tenant,accepted_batch_lineage,coverage_contiguous}.sql`, `data/dbt/macros/write_quality_results.sql` | Each test has one failing and one passing fixture; results rows carry the candidate revision id. | 5 |
| OPS-002-S05 | Implement F01–F04 against the canonical models (bucket authority per D-12, decomposition, conservation, currency separation) using exact DECIMAL(38,9) sums. | `data/dbt/tests/financial/f01…f04.sql` | F-270 fixture passes all four; EUR 20 bucket never summed with USD; query 140 + idle 60 = 200. | 6 |
| OPS-002-S06 | Implement S01 comparing serving views to ledger per tenant/month/currency for the candidate publication. | `data/dbt/tests/semantic/s01_serving_parity.sql` | Parity fixture PASS; a serving view with a dropped row → FAIL naming tenant/month/currency. | 3 |
| OPS-002-S07 | Implement advisory F05/F06 with WARN semantics that never block publication. | `data/dbt/tests/advisory/` | Spike fixture 10 → 150 → WARN, publication proceeds. | 2 |
| OPS-002-S08 | Implement `eligible(tenant, candidate)`: every partition of the candidate has PASS for every REQUIRED check at the current check_version for exactly that candidate revision; ERROR or missing result = FAIL; under D-06 a failing tenant is excluded from its pointer advance while others advance. | `services/quality/gate.py`, called by ORC-005 publisher | Two-tenant fixture: tenant A F01 FAIL, tenant B PASS → B pointer advances, A unchanged, A publication age metric grows. | 4 |
| OPS-002-S09 | Double-count fixture: ingest the billing reference twice under different batch IDs so the naive ledger totals 540. | `tests/spec/OPS-002/test_double_count.py` | F01 FAIL; API/UI still return 270 with `stale_since` metadata and stale banner; no 540 visible anywhere. | 4 |
| OPS-002-S10 | Missing-file fixture: manifest with 3 files, only 2 received. | same folder | Batch not accepted; no candidate built; Data Health shows coverage gap for that window. | 2 |
| OPS-002-S11 | Stale-success fixture: PASS recorded for r1, candidate r2 has no results. | same folder | r2 blocked with reason `MISSING_RESULT`; r1 remains published. | 1 |
| OPS-002-S12 | Optional-gap fixture: optional source denied (e.g. SEARCH_OPTIMIZATION detail). | same folder | Advisory WARN; required totals (270) published; coverage disclosed as partial for that detail. | 2 |
| OPS-002-S13 | Build the internal data-health dashboard (gate failures by check_id/family, no tenant dimension; tenant drill via ops views) and alarm "required gate failed" (owner Data platform, SEV2 business-hours page). | `infra/observability/dashboards/data-health.json.tftpl` | Injected F01 failure raises the alarm within 10 min with runbook RB-07 link. | 3 |
| OPS-002-S14 | Update RB-07 with gate IDs, the eligibility query and safe repoint procedure; collect evidence. | `docs/runbooks/RB-07-bad-publication.md`, `docs/evidence/OPS-002/<commit>/` | Second engineer locates the failing check for the 540 fixture using only RB-07. | 2 |

Task acceptance:
- [ ] 540 double count is blocked by F01; 270 remains served with stale metadata.
- [ ] A missing or ERROR gate result blocks exactly that tenant's candidate, never other tenants.
- [ ] A PASS for revision r1 can never authorize revision r2.
- [ ] Advisory failures never block publication and are visible on Data Health.
- [ ] Every REQUIRED check has a failing and a passing fixture in CI.

### OPS-003 — Define and qualify SLOs, synthetic probes and burn-rate alerting
Release: R1 · Estimate: 34–52 h · Risk: M · Decisions: D-06, D-08, D-22 · Closes: G-OPS-02, G-OPS-03, G-OPS-04
Dependency changes: `−GOV-007`, `−RPT-005` (delivery SLIs moved to OPS-110), `+OPS-101`, `+OPS-102`, `+OPS-103`, `+API-003`; milestone M9 → M5.

SLO catalogue (normative for S01; window 28 days rolling; exclusions are counted and displayed, never silently dropped):

| ID | Good / valid events | Source | Exclusions | Target |
|---|---|---|---|---|
| AVAIL-CTRL | valid: requests to control/auth endpoints (all `/v1/*` except analytics) + control probes; good: status < 500, not 429 `reason=platform_capacity`, completed < 15 s | ALB access logs (S3/Athena) + API histogram + probes | health checks, OPTIONS; synthetic-tenant traffic reported as its own series | 99.9 % |
| AVAIL-ANALYTICS | valid: `POST /v1/analytics/query`, `GET /v1/cost`, job-result fetch + analytics probes; bad: 5xx, 504 deadline, 429 `platform_capacity` | same | same | 99.5 % (R1) |
| LAT-WARM | valid: interactive analytics requests with `x-bridge-cache: hit`; good: server-side duration ≤ 2 s | API histogram (server span) | 202 async conversions | 95 % |
| LAT-COLD | valid: interactive analytics with cache miss (broker executed, includes warehouse resume); good: ≤ 10 s; > 15 s is impossible (deadline → 504, counted bad in AVAIL-ANALYTICS) | same | same | 95 % |
| FRESH-1 | valid: accepted steady-lane batches; good: `publication_committed_at − manifest.committed_at ≤ 30 min` | `ops.batch_timeline` (OPS-101) | backfill and replay lanes; tenants PAUSED/SUSPENDED. Batches blocked by a REQUIRED gate are bad, not excluded | 95 % |
| FRESH-E2E | reported decomposition: source latency, cadence wait, extraction, S3→receipt, dbt, publish (PRD §43) | canary facts (OPS-103) | – | informational |
| BACKLOG-STEADY | 1-min samples where oldest due-not-started steady account-cycle ≤ 2 × cadence AND oldest accepted-unprocessed batch ≤ 45 min | PG leases + `ops.processing_ledger` | paused tenants | 99 % |

Error-budget policy: budget = 1 − target over 28 days. Page when burn ≥ 14.4 over 1 h and 5 min, or ≥ 6 over 6 h and 30 min; ticket when ≥ 1 over 3 days and 6 h. A burn window with < 50 valid real events is evaluated on probe events only. Remaining budget < 25 % → freeze non-reliability releases of the responsible component (owner approval to override); one incident consuming ≥ 20 % → postmortem within 5 business days. Incidents with `cause=dependency:<vendor>` count against the SLO but do not trigger the release freeze.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-003-S01 | Encode the catalogue and policy above as data with owner per SLO. | `infra/observability/slo/slo-catalog.yaml`, `docs/operations/error-budget-policy.md` | Schema-valid; every SLO has numerator, denominator, exclusions, source, owner. | 3 |
| OPS-003-S02 | Emit `bridge_api_request_duration_seconds` histogram (buckets 0.25, 0.5, 1, 2, 4, 6, 8, 10, 15) with `endpoint_class ∈ {analytics_interactive, control, auth, job_submit, download}`, `cache ∈ {hit, miss, na}`, `outcome`. | API middleware in `apps/api/telemetry.py` | Contract test: cache hit/miss labelled correctly for 20 fixture requests. | 2 |
| OPS-003-S03 | Enable ALB access logs to S3, create the Athena table and a 5-minute job writing good/valid counts per SLO into `ops.sli_events` and CloudWatch metrics (no tenant dimension). | `infra/observability/slo/alb-logs.tf`, `services/slo/sli_job.py` | Replayed log fixture of 1,000 lines produces expected good/valid counts exactly. | 4 |
| OPS-003-S04 | Compute FRESH-1 from `ops.batch_timeline` at each publication commit; compute FRESH-E2E only for canary tenants. | `services/slo/freshness.py` | Fixture: 3 batches with 12, 29, 41 min → 2 good / 3 valid. | 3 |
| OPS-003-S05 | Sample BACKLOG-STEADY every minute (oldest due account-cycle, oldest accepted-unprocessed batch). | `services/slo/backlog.py` | Stopping the steady worker in staging makes the sample bad within 2 × cadence + 1 min. | 3 |
| OPS-003-S06 | Implement probes: 1-min API probe (GET `/v1/me`, analytics query hit and forced miss on canary tenant via unique date range), 5-min Cognito login with synthetic MFA user (TOTP seed in Secrets Manager), isolation probe (canary B requests canary A account ID → 404). | `tests/synthetic/` deployed as CloudWatch Synthetics canaries or scheduled ECS tasks | Probes run in staging for 24 h with ≥ 99 % success; isolation probe asserts 404 and no body leakage. | 5 |
| OPS-003-S07 | Implement multi-window burn alarms (metric math) with the ≥ 50-event guard and probe fallback. | `infra/observability/slo/burn-alarms.tf` | Replay: 1 failure among 3 requests in 5 min does not page; 30 % errors over 10 min with ≥ 50 events pages ≤ 5 min. | 4 |
| OPS-003-S08 | Add deadman alarms: probe no-data 5 min (`TreatMissingData=breaching`), `max_publication_age_minutes` > 90 for any active tenant, Dagster daemon heartbeat > 3 min, outbox oldest pending > 10 min. | same folder | Disabling the probe raises the alarm; uptime is never computed as 100 % from missing data. | 3 |
| OPS-003-S09 | Implement impact classification: a denied optional source maps to tenant data-health DEGRADED and does not touch AVAIL-*. | alarm tags + `services/slo/classify.py` | Revoking the optional source grant on SYN_B: AVAIL-ANALYTICS unchanged, Data Health DEGRADED. | 2 |
| OPS-003-S10 | Build the weekly error-budget report (per SLO: budget used, top incidents, cause class). | `services/slo/report.py`, dashboard `slo-overview` | Report generated from a fixture month with correct remaining budget (e.g. 99.5 % target, 0.3 % bad → 40 % remaining). | 2 |
| OPS-003-S11 | Run fault injection in staging: stop the steady worker; revoke a required source role on SYN_A; inject 30 % 503 through a non-prod fault flag. Record detection time and impact class. | `docs/evidence/OPS-003/<commit>/fault-injection.md` | Detection ≤ 5 min (503), ≤ 2×cadence+1 min (worker), required-source revoke classified `SOURCE_PERMISSION_DENIED` with account FAILING. | 4 |
| OPS-003-S12 | Enforce alarm hygiene: CI policy requires `owner`, `severity`, `runbook_url`, `impact` tags and an SNS target that exists. | `infra/policy/alarm-tags.rego` | An alarm without owner fails CI. | 1 |
| OPS-003-S13 | Write `docs/runbooks/slo.md` (how to read burn, when to freeze, how to classify dependency causes). | runbook | Reviewed by on-call rota members. | 2 |

Task acceptance:
- [ ] Every SLO has a numeric SLI, explicit exclusions and a live data source in staging.
- [ ] Missing probe data raises an alarm; it never yields 100 % availability.
- [ ] A denied optional source does not mark the API down; a required-source revoke is attributed to the source, not the platform.
- [ ] Low-traffic windows (< 50 events) cannot page on a single failure.
- [ ] Warm and cold latency are separable by the `cache` label for every interactive request.

### OPS-004 — Run adversarial tenant isolation and internal security qualification
Release: R1 · Estimate: 56–84 h · Risk: H · Decisions: D-02, D-22, D-25 · Closes: G-OPS-14 (internal part), G-OPS-15 (tests)
Dependency changes: `+OPS-106` (support access and ops API must be in the attack surface). Milestone M9 unchanged (SEC-008 early suite runs from M1).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-004-S01 | Generate the attack surface inventory from the public OpenAPI, ops API, report/download links, webhook config, S3 prefixes and Snowflake roles; write the attack matrix (actor, target, entry point, expected result, evidence). | `tests/security/attack-matrix.yaml` | Every OpenAPI operation with a tenant-scoped path/body ID has ≥ 1 attack row (CI diff check). | 4 |
| OPS-004-S02 | Generate BOLA/IDOR tests: for each tenant-scoped UUID parameter, tenant B session requests tenant A's ID. | `tests/isolation/test_bola_generated.py` | 100 % → 404 with identical body to a random UUID; p95 latency difference ≤ 50 ms (no timing oracle). | 6 |
| OPS-004-S03 | Scope forgery: analytics filters with an account outside the grant, OR-broadening (`account A OR team Finance` when grant is A AND Finance), empty grant, hidden-team account totals. | `tests/isolation/test_scope_forgery.py` | Out-of-grant → 403 `SCOPE_DENIED`; empty grant → 0 rows; team-restricted user never receives an account total including hidden teams. | 4 |
| OPS-004-S04 | Cache/cursor/job/link attacks: reuse A's cursor as B; fetch another user's async job result; download report after membership revocation; stale `permission_epoch` 31 s after revocation. | `tests/isolation/test_async_artifacts.py` | All denied; revocation effective ≤ 30 s including cached pages; no artifact bytes returned. | 5 |
| OPS-004-S05 | Auth attacks: ID token used as access token, `alg=none`, HS256 signed with the public key, wrong `aud`/`iss`/`token_use`, expired token, CSRF-less mutation, session fixation, refresh-token reuse after rotation. | `tests/security/test_auth.py` | Every case → 401/403; reused refresh token revokes the session family. | 5 |
| OPS-004-S06 | Webhook SSRF: `169.254.169.254`, `127.0.0.1`, `[::1]`, `10.0.0.1`, `::ffff:127.0.0.1`, DNS-rebinding hostname, 302 redirect to internal, non-443 port. | `tests/security/test_ssrf.py` | All rejected at validation or connect time; resolver pinning prevents rebinding. | 3 |
| OPS-004-S07 | CSV/XLSX export formula injection with cells starting `=`, `+`, `-`, `@`, tab, CR. | `tests/security/test_csv_injection.py` | Exported cells prefixed with `'`; numeric negatives still numeric in numeric columns. | 1 |
| OPS-004-S08 | Semantic-query injection: identifiers outside the registry, literal injection, QUERY_TAG injection via names. | `tests/security/test_query_injection.py` | Rejected with `INVALID_IDENTIFIER`; all literals bound (query log shows binds, no concatenation). | 3 |
| OPS-004-S09 | Snowflake serving attacks as tenant A's profile user: `USE ROLE` of another profile, `USE SECONDARY ROLES ALL`, `SELECT` on RAW, `ALTER ROW ACCESS POLICY`, read of entitlement table; mis-mapped entitlement row. | `tests/isolation/test_snowflake_principal.py` (staging live) | All statements fail with insufficient privileges; mis-mapped row yields 0 rows, not other-tenant rows. | 4 |
| OPS-004-S10 | PostgreSQL: assert runtime role is not owner/BYPASSRLS; missing `app.tenant_id` → 0 rows; two sequential transactions on one pooled connection do not leak context. | `tests/isolation/test_pg_rls.py` | All assertions pass on staging Aurora. | 2 |
| OPS-004-S11 | S3/IAM: connector role of account X writes/reads prefix of account Y; report objects public read; presigned URL for another tenant's key. | `tests/security/test_s3_iam.py` | AccessDenied in all cases; bucket policy `aws:SecureTransport=false` denied. | 3 |
| OPS-004-S12 | Operator/support attacks: ops API read of tenant analytics without grant, with expired grant, with grant for tenant A used on tenant B. | `tests/security/test_support_access.py` | 403 in all cases; each attempt appears in security audit; approved access appears in tenant audit. | 2 |
| OPS-004-S13 | Supply chain: image scan (grype or trivy) with fail on fixable critical/high, SBOM (syft) per image, GitHub Actions pinned by SHA, IaC scan (checkov) on all stacks. | `.github/workflows/security-scan.yml` | Pipeline blocks a fixture image with a known critical CVE; all actions pinned. | 4 |
| OPS-004-S14 | Run a 1-day manual abuse review by two engineers (business-logic abuse: plan quota bypass, report schedule spam, invitation abuse, onboarding step skipping). | `docs/security/qualification/manual-review-<date>.md` | Findings logged with severity; none left untriaged. | 8 |
| OPS-004-S15 | Fix/retest loop and exception register (id, severity, owner, compensating control, expiry ≤ 30 days); release rule: any open tenant-disclosure finding or critical/high exploitable finding → NO-GO. | `docs/security/qualification/exceptions.yaml` | Register empty of blocking items or REL-004 records NO-GO. | 4 |
| OPS-004-S16 | Assemble redacted evidence for REL-003 and LCH-102 questionnaires. | `docs/evidence/OPS-004/<commit>/` | Evidence references exact commit and environment. | 2 |

Task acceptance:
- [ ] Every tenant-scoped operation has a generated A→B attack and it is denied without name/count/timing leakage.
- [ ] Revocation is effective ≤ 30 s across cached pages, cursors, jobs and downloads.
- [ ] No Snowflake profile user can switch role, use secondary roles, read RAW or alter policies.
- [ ] Supply-chain gates block a known critical CVE image.
- [ ] Exception register contains no open blocking item at REL-004.

### OPS-005 — Implement retention enforcement, deletion/DSAR workflow, legal holds and audit verification
Release: R1 · Estimate: 58–86 h · Risk: H · Decisions: D-05, D-07, D-10, D-11, D-25 · Closes: G-OPS-09, G-OPS-10
Dependency changes: `+OPS-104` (tombstone log and data inventory); milestone M9 → M7 (reports exist after RPT-005).

Retention matrix (normative for S02; defaults from ADR-009/D-11; contract may override per tenant):

| Store / class | Retention | Enforcement mechanism | Tenant deletion | Residual after deletion |
|---|---|---|---|---|
| S3 `landing/` journal + manifests | 90 d | lifecycle expiration 90 d; `NoncurrentVersionExpiration` 7 d; expired delete-marker cleanup; abort incomplete multipart 1 d | S3 Inventory → keys containing `/tenant_id=<uuid>/` → S3 Batch Operations delete of **every version** | none |
| S3 quarantine | 30 d | lifecycle | same | none |
| Snowflake RAW | 90 d from acceptance | daily task `DELETE … WHERE _accepted_at < DATEADD(day,-90,CURRENT_TIMESTAMP())`; `DATA_RETENTION_TIME_IN_DAYS=1` | `DELETE WHERE tenant_id=…` on every RAW table | Time Travel 1 d + Fail-safe 7 d (Snowflake-internal) |
| Snowflake staging / intermediate | rebuildable | TRANSIENT tables (no Fail-safe, ≤ 1 d Time Travel) | delete | ≤ 1 d |
| Canonical facts, allocation, statements | 400 d (+ closed-statement evidence per contract) | partition expiry by partition date; revision GC (not in any publication map, not pinned by a closed statement, not referenced by an active job/cursor, older than 7 d); `DATA_RETENTION_TIME_IN_DAYS=7` | publication-map rows first, then facts | Time Travel 7 d + Fail-safe 7 d |
| Query-level detail (D-11) | 90 d hot | partition expiry | delete | as above |
| Query-family × day aggregates | 400 d | partition expiry | delete | as above |
| Snowflake Backups (Tier 1) | 35 d | backup policy expiry | not editable; restore path reapplies tombstones | ≤ 35 d |
| Recovery export bucket (Tier 2) | manifests 35 d; revisions while referenced | OPS-007 GC | delete tenant prefixes, all versions (break-glass governance bypass) | none |
| PostgreSQL control data | tenant lifetime | – | ordered DELETE per table; keep tombstone, minimal audit, commercial/invoice records (accounting retention per owner's jurisdiction) | Aurora PITR ≤ 35 d |
| PostgreSQL audit + S3 audit export | 365 d | monthly partitions, `DROP PARTITION` after export verified; S3 lifecycle 365 d | retained (legal basis, pseudonymous actor refs) | – |
| Redis | TTL ≤ 24 h, mandatory | TTL lint (every write sets EX) | `SCAN bridge:v1:{env}:{tenant}:*` + `UNLINK`; epoch bump | ≤ TTL |
| Report artifacts | 30 d (`retention=standard30` tag); statement evidence excluded (`retention=statement`) | tag-filtered lifecycle | delete tenant objects, all versions | none |
| CloudWatch Logs | app 30 d, security/access 90 d | `retention_in_days` enforced (OPS-001-S07) | cannot delete lines → logs carry only pseudonymous IDs | ≤ 90 d |
| Dagster runs / event logs | runs 30 d, event logs 7 d (D-07) | purge job | delete runs tagged with tenant | – |
| Identity dictionary (D-10) | subject lifetime | – | tenant KMS key scheduled for deletion (7-day minimum waiting) → ciphertext in all backups unreadable | ≤ 7 d key waiting period |

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-005-S01 | Create `privacy.deletion_requests` (type SUBJECT_ACCESS / SUBJECT_ERASURE / TENANT_DELETION; states RECEIVED → PREVIEWED → APPROVED → HELD or EXECUTING → VERIFIED → CERTIFIED; REJECTED), `privacy.deletion_stages` (store, expected_count, deleted_count, verified_at, error) and `privacy.legal_holds` (scope tenant/account/subject/dataset, reason_code, requested_by, approved_by, review_by ≤ 90 d, released_at). | Alembic migration `privacy_0001`, state machine `services/privacy/deletion_state.py` | Illegal transitions (e.g. RECEIVED → EXECUTING) rejected in tests; approver ≠ requester enforced. | 3 |
| OPS-005-S02 | Encode the retention matrix as data with a verification query per store. | `infra/lifecycle/retention-matrix.yaml` | Every store in OPS-104 data inventory has a row; CI fails on a store without a row. | 3 |
| OPS-005-S03 | Apply S3 lifecycle rules for landing (90 d), quarantine (30 d), reports (tag-filtered 30 d), audit (365 d) with noncurrent-version 7 d, delete-marker cleanup and multipart abort 1 d. | `infra/lifecycle/s3.tf` | Terraform test asserts every bucket has all four rule types; a statement-evidence tagged object is excluded. | 3 |
| OPS-005-S04 | Implement the Dagster run/event purge job and verify CloudWatch retention coverage. | `services/privacy/dagster_purge.py` | Runs older than 30 d and event logs older than 7 d removed in staging; no log group without retention. | 3 |
| OPS-005-S05 | Implement Snowflake retention tasks (RAW 90 d delete, canonical partition expiry 400 d) and set table-level Time Travel (RAW 1, canonical 7) and TRANSIENT for staging/intermediate. | `data/dbt/macros/retention/`, `infra/snowflake/retention.sql` | `SHOW TABLES` evidence: kinds and retention values match matrix; delete counts logged. | 4 |
| OPS-005-S06 | Implement the revision GC job with the DBT owner (collectible rule above), dry-run mode listing counts per dataset. | `services/privacy/revision_gc.py` | Fixture: revision pinned by a closed statement is kept; unreferenced revision older than 7 d is deleted; current publication untouched. | 4 |
| OPS-005-S07 | Implement PostgreSQL retention: audit partitions older than 365 d dropped only after the S3 export checksum verified; delivered outbox rows > 30 d; idempotency keys > 7 d; expired sessions > 30 d. | `services/privacy/pg_retention.py` | Partition drop refused when export verification is missing. | 3 |
| OPS-005-S08 | Enforce Redis TTL (lint rule on every write helper) and tenant purge by key prefix with epoch bump. | `packages/cache/ttl_lint.py`, `services/privacy/redis_purge.py` | Write without TTL fails CI; tenant purge leaves 0 keys for the tenant prefix. | 2 |
| OPS-005-S09 | Implement the tenant-deletion orchestrator with ordered stages: (1) tenant state DELETING, admission blocked; (2) pause schedules; (3) attach deny-all inline policy to the tenant's Bridge IAM roles and notify customer revoke script; (4) permission-epoch bump, sessions revoked; (5) fence in-flight leases; (6) export completed or waived (ONB-102); (7) Snowflake serving → canonical → RAW → ops facts; (8) S3 all versions; (9) recovery bucket prefixes; (10) Redis; (11) PostgreSQL except tombstone/minimal audit/commercial records; (12) schedule tenant KMS key deletion (7 d). Each stage idempotent and resumable. | `services/privacy/tenant_deletion.py` (Dagster job) | Kill the job after stage 7 and rerun → completes without duplicate side effects; stage table shows expected = deleted counts. | 8 |
| OPS-005-S10 | Implement verification queries per store (count = 0 for tenant) and the deletion certificate listing residual copies with expiry dates (Aurora latest backup + 35 d, Snowflake Backups + 35 d, Fail-safe + 7 d after Time Travel, KMS key deletion date). | `services/privacy/verify.py`, certificate JSON + PDF template | Certificate generated for synthetic tenant with all counts 0 and correct dates. | 4 |
| OPS-005-S11 | Implement SUBJECT_ACCESS export: dictionary entries for the subject HMAC plus pseudonym-linked activity (queries attributed, roles) as CSV within the tenant scope. | `services/privacy/subject_access.py` | Export for subject S contains only S's rows; foreign-tenant subject with same name returns nothing. | 4 |
| OPS-005-S12 | Implement SUBJECT_ERASURE per D-10: delete the dictionary entry, write SUBJECT tombstone, UI/API render "Erased user ‹first 4 hex of pseudonym›"; facts unchanged. | `services/privacy/subject_erasure.py` | Ledger totals unchanged before/after; name unresolvable in UI, exports and reports generated afterwards. | 3 |
| OPS-005-S13 | Enforce legal holds: each stage checks overlapping active holds → HELD; `review_by` passed → ticket + alarm; release requires approver ≠ requester. | `services/privacy/holds.py` | Held account blocks only its stages; other accounts of the tenant proceed; expired review raises alarm. | 3 |
| OPS-005-S14 | Race tests: extraction task finishing after stage 7; late Snowpipe receipt; report job completing during deletion. | `tests/privacy/test_deletion_races.py` | Acceptance rejects batches for tenant state DELETING; report artifact deleted in stage 8 and download returns 410. | 3 |
| OPS-005-S15 | Resurrection test with OPS-006/007: restore a pre-deletion Aurora point and Tier 2 snapshot into an isolated environment; replay tombstones. | `tests/recovery/test_no_resurrection.py` | Deleted tenant absent (0 rows, cannot authenticate) before traffic enable. | 4 |
| OPS-005-S16 | Stale report URL and cached analytics after deletion. | `tests/privacy/test_post_delete_access.py` | 410 for artifact links; cache keys absent; API 404 for tenant resources. | 1 |
| OPS-005-S17 | Admin API `POST /v1/privacy/requests` (preview returns per-store counts), `POST …/{id}/approve`, `GET …/{id}` with stages; hook into Settings › Privacy & retention; update RB-14. | `apps/api/privacy/`, `docs/runbooks/RB-14-offboarding.md` | Only Organization Owner can create TENANT_DELETION; Admin can create SUBJECT_*; foreign request ID → 404. | 4 |
| OPS-005-S18 | Evidence pack including a full synthetic tenant deletion and one subject erasure. | `docs/evidence/OPS-005/<commit>/` | Certificate and verification outputs attached. | 2 |

Task acceptance:
- [ ] Deleted synthetic tenant: 0 rows/objects/keys in every store, cannot authenticate, does not reappear after restore + tombstone replay.
- [ ] Object versions and delete markers leave no retrievable tenant object.
- [ ] Subject erasure leaves ledger totals unchanged and the subject unresolvable everywhere.
- [ ] Legal hold blocks exactly its scope and cannot be indefinite without review.
- [ ] Deletion certificate lists every residual copy with an expiry date.

### OPS-006 — Rehearse control-plane backup, PITR and side-effect reconciliation
Release: R1 · Estimate: 34–50 h · Risk: M · Decisions: D-25 · Closes: G-OPS-07, G-OPS-08
Dependency changes: `−OPS-005`, `−INF-003`, `−INF-006` (transitively satisfied or not needed), `+OPS-104`, `+OPS-102`; milestone M9 → M2 (first drill), re-executed at M10 as REL-002 evidence.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-006-S01 | Verify and codify: `backup_retention_period=35`, deletion protection, CMK encryption, `copy_tags_to_snapshot`; AWS Backup plan for daily snapshots with 35-day lifecycle (manual snapshots otherwise never expire); `bridge-restore-operator` role not assumable by application roles; KMS key policy grants it decrypt/create-grant. | `infra/backup/control/*.tf` | Terraform tests pass; IAM simulator denies API task role `rds:RestoreDBClusterToPointInTime`. | 3 |
| OPS-006-S02 | Define the control recovery manifest: requested recovery point, latest restorable time, migration head at that point, lease_epoch before/after, outbox cutoff, tombstone_hwm, operator, incident ID. | `data/contracts/control-recovery-manifest.v1.json` | Schema-valid fixture; manifest required by restore script. | 2 |
| OPS-006-S03 | Add the dispatch journal: the outbox dispatcher appends `{event_id, attempt_id, provider_message_id, accepted_at}` for every provider-accepted delivery to an append-only S3 prefix (coordinate with CTL-004/GOV-007 owners; M2 uses the synthetic dispatcher). | `services/outbox/dispatch_journal.py` | Crash after provider accept and before DB ack still leaves a journal record (fault-injection test). | 4 |
| OPS-006-S04 | Implement `bridge-admin restore control --to <UTC> --target <name> --dry-run` printing the manifest, expected loss window and schema version. | `apps/admin_cli/restore_control.py` | Dry run on staging prints latest restorable time and refuses a point earlier than retention. | 4 |
| OPS-006-S05 | Execute PITR into an isolated cluster (`restore-db-cluster-to-point-in-time` then `create-db-instance`), isolated security group, no application wiring. | runbook commands in `docs/runbooks/RB-10-aurora-restore.md` | New cluster reachable only from the operator bastion/SSM path. | 3 |
| OPS-006-S06 | Run the post-restore validation pack: migration head equals manifest; every tenant table has `relrowsecurity AND relforcerowsecurity`; runtime role not BYPASSRLS; tenant A/B probe; synthetic marker counts. | `tests/recovery/control/validate.sql`, `validate.py` | Pack returns PASS on restored cluster; seeded missing FORCE RLS on a fixture table → FAIL. | 3 |
| OPS-006-S07 | Implement post-restore fencing and reconciliation: increment `control.lease_epoch` first; expire all leases; reconcile PENDING/IN_FLIGHT outbox rows against the dispatch journal → `DELIVERED_RECONCILED`; mark coverage/watermarks for re-derivation from Snowflake receipts (ING-011 anti-entropy). | `services/recovery/control_reconcile.py` | Fixture of 20 events (10 delivered in the lost window): 0 re-sent, 10 remaining dispatched once. | 4 |
| OPS-006-S08 | Replay tombstones from the S3 log with `seq > manifest.tombstone_hwm`. | uses OPS-104 reader | Tenant deleted after the recovery point is absent after replay. | 2 |
| OPS-006-S09 | Cutover: stop old writers (scale services to 0 / revoke login of app role on old cluster), switch endpoint via Terraform variable and secret, rolling restart, flush versioned Redis keys. | runbook section "cutover" | Old cluster rejects app logins; new cluster serves traffic. | 3 |
| OPS-006-S10 | Timed drill: write a synthetic marker every 30 s; declare incident; restore; measure RPO (last marker written vs last recovered) and RTO (declaration → first successful probe). | `docs/evidence/OPS-006/<commit>/drill.md` | Measured RPO ≤ 5 min and RTO ≤ 4 h, or the gap is filed as a blocking task. | 4 |
| OPS-006-S11 | Dual-writer test: a worker holding a pre-restore lease attempts to commit. | `tests/recovery/control/test_epoch_fence.py` | Commit rejected with `LEASE_EPOCH_STALE`. | 2 |
| OPS-006-S12 | Redis loss under load: flush Redis during synthetic API + job traffic. | `tests/recovery/control/test_redis_loss.py` | No job lost; no stale-epoch authorization served; latency rises only within RB-12 limits. | 2 |
| OPS-006-S13 | Finalize RB-10 with exact commands, add quarterly drill to OPS-108 calendar. | runbook + calendar entry | Second engineer can run the dry-run from RB-10 alone. | 2 |

Task acceptance:
- [ ] Measured RPO ≤ 5 min and RTO ≤ 4 h for the synthetic footprint (or recorded blocking gap).
- [ ] Zero duplicate logical dispatches and zero dropped undelivered events in the 20-event fixture.
- [ ] Pre-restore lease tokens cannot commit after restore.
- [ ] A cannot read B on the restored cluster; tombstoned tenant does not reappear.

### OPS-007 — Implement tiered analytical recovery (backups, incremental revision export) and restore drill
Release: R1 · Estimate: 56–84 h · Risk: H · Decisions: D-03, D-05, D-21, D-23 · Closes: G-OPS-06, G-OPS-07
Dependency changes: `−OPS-005`, `+OPS-104`, `+DBT-006` (publication map and revision identity); milestone M9 → M5.

Recovery design (normative):

| Tier | Protects against | Mechanism | RPO | RTO (estimate, TO VERIFY by drill) | R1 cost (ASSUMPTION) |
|---|---|---|---|---|---|
| 1 | bad DML/DROP, faulty publication, operator error | Snowflake Backups: backup sets on LEDGER, SERVING, CONFIG, SECURITY databases; policy daily, expire 35 d, no retention lock | ≤ 24 h (plus Time Travel 7 d for finer points) | 15–60 min (`CREATE … FROM BACKUP`, swap) | storage only for changed micro-partitions; ≈ 0 extra under insert-only revisions |
| 2 | central account loss/compromise, Tier 1 unusable | incremental Parquet export of new revisions to recovery AWS account + daily manifest; restore by COPY INTO a newly bootstrapped account + journal replay | snapshot ≤ 24 h; with journal replay ≈ last accepted batch | 4–6 h at R1 volume (bootstrap 1.5–2 h, load 1–2 h, replay 0.5–1 h, verification 1 h) | S3 < USD 5/month; export 3–8 credits/month; restore ≈ 8–16 credits per drill |
| 3 (R2) | regional outage | database replication to a second EU account (OPS-111) | replication interval | ≈ 1–2 h | full storage duplicate + transfer + refresh compute |

Customer-side WIF installs are unaffected by a central-account rebuild because customer service users trust Bridge's AWS IAM roles (ADR-004), not the central Snowflake account; only Bridge-owned trust (central service users' WORKLOAD_IDENTITY, storage integrations' IAM trust/external IDs) is recreated.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-007-S01 | Write the recovery scope: fct_charge revisions, attribution bridges, allocation results, statements and closed-period evidence, published config versions, publication map and history, SECURITY entitlement/profile tables, reference rates, query-family × day aggregates, hot query detail (included so journal retention need not exceed 90 d). | `data/contracts/recovery-scope.yaml` | Every canonical dbt model tagged `recovery: include/exclude` with reason; CI fails on an untagged canonical model. | 3 |
| OPS-007-S02 | Define manifest v1 and checksum method per revision: `COUNT(*)`, `HASH_AGG(*)`, `SUM(amount)` per currency. | `data/contracts/recovery-manifest.v1.json` | Two exports of the same revision produce identical checksums. | 2 |
| OPS-007-S03 | Provision the recovery bucket in a separate AWS account: versioning, SSE-KMS with a CMK owned by that account, Object Lock governance mode 35 d (bypass only by break-glass role), bucket policy allowing `PutObject` only from the `RECOVERY_EXPORT_INT` storage-integration role; create Snowflake storage integration, stage and `RECOVERY_EXPORTER` role (SELECT on scope, USAGE on stage, nothing else). | `infra/recovery/*.tf`, `infra/snowflake/recovery.sql` | Exporter cannot DELETE objects; production app roles cannot read the bucket (IAM simulator). | 4 |
| OPS-007-S04 | Configure Tier 1 backup sets and policy (daily, expire 35 d, no retention lock); verify live which objects/attachments (row access policies, grants) a restore preserves — TO VERIFY LIVE. | `infra/snowflake/backups.sql` | `SHOW BACKUP SETS` evidence; restore of a table in staging preserves or documents policy attachment behaviour. | 3 |
| OPS-007-S05 | Implement the daily export asset: T = start time; select revisions with `created_at ≤ T` not in `ops.recovery_exports`; `COPY INTO @recovery_stage/ … PARTITION BY ('ds='\|\|dataset\|\|'/t='\|\|tenant_id\|\|'/pk='\|\|partition_key\|\|'/rev='\|\|revision_id) FILE_FORMAT=(TYPE=PARQUET) HEADER=TRUE` with `ALTER SESSION SET ENABLE_UNLOAD_PHYSICAL_TYPE_OPTIMIZATION=FALSE`; record row count, HASH_AGG, amounts. | `services/recovery/analytical_export.py` (Dagster asset `recovery_export`) | Second run on unchanged data exports 0 new revisions; decimal column types in Parquet equal logical types. | 5 |
| OPS-007-S06 | Write the daily manifest last: publication map read `AT(TIMESTAMP => T)`, referenced revisions, config/security snapshot, `tombstone_hwm`, `journal_hwm` per source/account; store SHA-256 of the manifest in a sibling object. | `services/recovery/manifest.py` | Manifest validates; tampering one byte fails verification. | 4 |
| OPS-007-S07 | Implement recovery-bucket GC: delete revision prefixes not referenced by any manifest dated within 35 days (break-glass role, audited). | `services/recovery/gc.py` | Fixture: revision superseded 36 days ago deleted; revision still current after 200 days kept. | 3 |
| OPS-007-S08 | Run the initial full export in staging and measure credits, bytes, duration. | evidence | Measured cost recorded in OPS-009 inputs. | 2 |
| OPS-007-S09 | Build the recovery bootstrap: reuse the INF-008 module with `recovery = true` to create databases/schemas/warehouses, central service users with WORKLOAD_IDENTITY for Bridge AWS roles, storage integrations (update Bridge bucket-role trust with the new external ID), row access policies. | `infra/snowflake/modules/central/` (`recovery` flag) | Bootstrap into an empty staging account completes unattended; second apply is a no-op. | 5 |
| OPS-007-S10 | Implement the restore loader: create tables from contract DDL, `COPY INTO … MATCH_BY_COLUMN_NAME=CASE_INSENSITIVE` per manifest prefix, verify COUNT/HASH_AGG/amounts per revision, rebuild publication map. | `services/recovery/analytical_restore.py` | Any checksum mismatch aborts before publication-map rebuild. | 5 |
| OPS-007-S11 | Reapply all tombstones from the S3 log; load SECURITY entitlements from current PostgreSQL state (not from the snapshot) so revocations after T hold. | same module | User revoked after T has no access on recovered account. | 3 |
| OPS-007-S12 | Journal catch-up: replay accepted batches with seq > `journal_hwm` via orchestrated `COPY INTO … FILES=(…)` (D-03), then dbt, gates (OPS-002) and publication. | `services/recovery/journal_catchup.py` | Batches accepted after T appear exactly once; gates PASS. | 4 |
| OPS-007-S13 | Old-partition fixture: a charge dated 180 days ago whose raw journal objects were expired; F-270 correction 12 → 11 (total 269); duplicate replay. | `tests/recovery/analytical/test_old_partition.py` | Old charge restored exactly; total 269; second replay leaves 269. | 4 |
| OPS-007-S14 | Serving gate: run the OPS-004 Snowflake/API isolation subset against the recovered account; totals per tenant/month/currency equal manifest; broker switch only via a release config change after gates PASS. | `tests/recovery/analytical/test_serving_gate.py` | Switch is refused while any gate is FAIL. | 3 |
| OPS-007-S15 | Timed Tier 2 drill in staging; record RPO/RTO/cost. | `docs/evidence/OPS-007/<commit>/drill-tier2.md` | RTO ≤ 8 h measured (target from `operations.md`); actual value recorded. | 4 |
| OPS-007-S16 | Timed Tier 1 drill: accidental `DELETE` on a canonical table in staging → `CREATE TABLE … FROM BACKUP` → swap. | `drill-tier1.md` | Recovery ≤ 60 min; totals equal pre-incident. | 2 |
| OPS-007-S17 | Write RB-11 with a decision tree (Tier 1 when account intact; Tier 2 when account lost/compromised) and exact commands. | `docs/runbooks/RB-11-snowflake-recovery.md` | Second engineer executes Tier 1 drill using RB-11 only. | 3 |
| OPS-007-S18 | Evidence and cost record. | `docs/evidence/OPS-007/<commit>/` | Includes manifest sample, checksums, timings, credits. | 2 |

Task acceptance:
- [ ] Old retained charge restored without its raw files; corrected total 269 restored exactly; duplicate replay leaves 269.
- [ ] Each revision is exported exactly once; daily export of unchanged data exports nothing.
- [ ] No serving from a recovered account before isolation and checksum gates pass.
- [ ] Deleted tenants and post-snapshot revocations remain effective after restore.
- [ ] Measured Tier 1 and Tier 2 RTO/RPO and cost recorded.

### OPS-008 — Qualify capacity (staged C1), noisy-neighbor protection and admission quotas
Release: R1 · Estimate: 56–90 h (+ approved benchmark spend, ASSUMPTION ≤ 300 credits) · Risk: H · Decisions: D-02, D-06, D-07, D-08, D-11 · Closes: G-OPS-11
Dependency changes: `+OPS-105` (early probes and simulator). Milestone M9 unchanged.

Capacity stages: C1 (R1 gate, executed) = 10 tenants × 5 accounts; median 300 k queries/account/day, p90 1 M, one skew account 3 M/day; 2 tenants backfilling 365 d concurrently while 8 are steady; 30 concurrent interactive users, peak 5 req/s; 50 report runs/day. Volume check: 50 accounts × ≈ 500 k mean × 2 query-grain sources (QUERY_HISTORY, QUERY_ATTRIBUTION_HISTORY) ≈ 50 M rows/day steady; backfill 2 × 5 × 365 × 500 k × 2 ≈ 3.65 B rows. C2 (R2) = 50 × 5 with 10 % at 1 M/day. C3 = PRD profile by extrapolation + one live bottleneck test.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-008-S01 | Write the benchmark manifest schema (profile, dataset size/skew, versions, spend cap, measured distributions) and get spend approval. | `tests/performance/benchmark-manifest.v1.json`, approval record | Owner approval with credit cap recorded. | 3 |
| OPS-008-S02 | Build the source simulator: tables/views in a synthetic account with the exact ACCOUNT_USAGE projections, selected by a registry override that is rejected by configuration validation in production. | `tests/performance/simulator/` | Adapter extracts from simulator with identical schema fingerprints; production config with override fails validation. | 6 |
| OPS-008-S03 | Generate C1 data with `GENERATOR()` (50 accounts × 365 days, skew account 3 M/day). | `tests/performance/simulator/generate_c1.sql` | Row counts per account/day match profile ± 1 %. | 4 |
| OPS-008-S04 | Extraction lane test: measure per account-cycle duration, rows/s, peak RSS (< 70 % of task memory), files/day and size histogram, customer-warehouse seconds per cycle and per backfill day. | `docs/operations/capacity.md#extraction` | Distributions p50/p95/p99 recorded; any OOM is a blocking defect. | 6 |
| OPS-008-S05 | Load/transform test: file landed → receipt latency, multi-tenant dbt run duration vs pending batches, FRESH-1 distribution under C1 steady + 2 backfills. | same doc | FRESH-1 ≥ 95 % ≤ 30 min, or a stated reduced target with cause. | 5 |
| OPS-008-S06 | Serving load (k6 or Locust): 70 % cacheable dashboard queries, 30 % ad hoc; 30 users, 5 req/s peak; record warm/cold p50/p95/p99 and Snowflake `QUEUED_OVERLOAD_TIME`. | `tests/performance/serving/` | LAT-WARM/LAT-COLD met or serving warehouse size/multi-cluster decision recorded with cost. | 5 |
| OPS-008-S07 | Report lane: 50 renders with concurrency 2; record peak memory and duration. | `tests/performance/reports/` | No OOM; p95 render time recorded. | 3 |
| OPS-008-S08 | Noisy-neighbor test: one tenant at 10× steady rate plus a 365-day backfill plus 4 heavy analysis jobs. | `tests/performance/noisy_neighbor/` | Other tenants keep FRESH-1 and LAT-COLD within target; weighted-fair admission logs show steady lane reserved. | 5 |
| OPS-008-S09 | Overload and cancellation: exceed tenant quotas and platform capacity. | `tests/performance/overload/` | 429 with `Retry-After` and `reason ∈ {tenant_quota, platform_capacity}`; cancelled heavy job frees warehouse within 30 s; 15 s statement timeout enforced. | 4 |
| OPS-008-S10 | PostgreSQL pool saturation with max replicas and an Aurora failover during load. | `tests/performance/pg/` | Configured pools ≤ 70 % of `max_connections`; failover recovers without job loss. | 3 |
| OPS-008-S11 | Tune only measured bottlenecks; each change has before/after numbers. | `docs/operations/capacity.md#tuning-log` | No tuning entry without measurements. | 6 |
| OPS-008-S12 | Publish measured C1 limits, derived admission quotas (accounts per tenant, concurrent backfills, heavy jobs, API rate) and C2/C3 extrapolation with assumptions separated from measurements. | `docs/operations/capacity.md` | Quotas loaded into LCH-101 entitlement defaults; extrapolated values labelled. | 4 |
| OPS-008-S13 | C3 bottleneck live test: one 1 M/day account × 365 d end-to-end within the approved budget. | evidence | Duration and credits recorded; bottleneck identified. | 4 |
| OPS-008-S14 | Compute unit costs (credits per million extracted/transformed rows; USD per tenant-month at C1). | input file for OPS-009 | Values reproducible from evidence. | 2 |
| OPS-008-S15 | Capacity dashboard and evidence. | `dashboards/capacity`, `docs/evidence/OPS-008/<commit>/` | Dashboard shows lane queue ages and quotas. | 2 |

Task acceptance:
- [ ] C1 executed with p50/p95/p99 for extraction, load, publish, serving and reports.
- [ ] One noisy tenant cannot starve steady-state lanes of other tenants.
- [ ] Quotas derived from measurements are enforced at admission (tenant #11 refused until C2 evidence).
- [ ] Extrapolated C2/C3 numbers are labelled as such.

### OPS-009 — Measure Bridge unit economics and internal cost allocation
Release: R1 · Estimate: 38–56 h · Risk: M · Decisions: D-02, D-06, D-08, D-17 · Closes: G-OPS-12, G-OPS-13
Dependency changes: `+OPS-109` (tags, processing ledger), `+LCH-101` (revenue references). Milestone M9 unchanged.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-009-S01 | Create database `INTERNAL_COST` with the §3 tables; grants only to `FINOPS_INTERNAL` and the cost loader; none to serving/transform/customer roles. | `data/dbt/models/internal_cost/`, `infra/snowflake/internal_cost.sql` | `SHOW GRANTS ON DATABASE INTERNAL_COST` lists only the two roles. | 2 |
| OPS-009-S02 | Ingest AWS CUR 2.0/Data Exports (daily Parquet) through a dedicated internal source contract. | `services/platform-cost/aws_cur.py` | A fixture month loads with line count and total equal to the export. | 4 |
| OPS-009-S03 | Ingest Bridge's own Snowflake usage (METERING_DAILY_HISTORY, WAREHOUSE_METERING_HISTORY, QUERY_ATTRIBUTION_HISTORY, PIPE_USAGE_HISTORY, TABLE_STORAGE_METRICS, USAGE_IN_CURRENCY_DAILY) with the product's own adapters into `INTERNAL_COST`. | `services/platform-cost/snowflake_own.py` | Month total equals Bridge's USAGE_IN_CURRENCY_DAILY total. | 4 |
| OPS-009-S04 | Control totals: Σ cost lines per provider/month vs provider invoice; signed delta recorded, no plug. | `internal_cost.control_totals` | Fixture invoice 1,000.00 vs lines 999.40 → delta −0.60 shown. | 3 |
| OPS-009-S05 | Build driver facts per G-OPS-12 (serving by tenant service user; transform by processing-ledger rows; Snowpipe by bytes; storage by row share; ECS task-seconds; NAT bytes; API requests; active users). | `internal_cost.cost_driver_fact` | Every driver has a source query and unit; no NULL tenant except explicit `UNALLOCATED`. | 5 |
| OPS-009-S06 | Allocate per component with exact decimal and largest-remainder at cent level; allocated + unallocated = source total; version the allocation method. | `data/dbt/models/internal_cost/tenant_platform_cost.sql` | Σ allocated + unallocated = provider total to the cent for fixture months. | 4 |
| OPS-009-S07 | Mark months PROVISIONAL until month end + 5 days and after CUR finalization; recompute on revisions. | same | A CUR revision changes the provisional month only. | 2 |
| OPS-009-S08 | Read revenue references from `commercial.invoice_refs` (LCH) and recognize straight-line over service period, labelled "estimate — finance approval required". | `internal_cost.revenue_estimate` | Annual invoice 12,000 for 12 months → 1,000/month. | 3 |
| OPS-009-S09 | Compute margin = (revenue − COGS)/revenue; revenue 0 → NULL. | `internal_cost.gross_margin` | Fixture 1000/100/120/80 → COGS 300, margin 70 %; zero revenue → NULL. | 2 |
| OPS-009-S10 | Encode COGS scope: production + canary + production share of observability = COGS; staging/dev = R&D; support staff cost entered monthly by finance. | `docs/operations/cogs-policy.md` | Staging costs never appear in `tenant_platform_cost`. | 2 |
| OPS-009-S11 | Report customer-side Bridge overhead credits (D-08, from customer QUERY_TAG/BRIDGE_FINOPS_WH) separately as `customer_borne_cost`, excluded from COGS. | `internal_cost.customer_borne_cost` | Test: customer overhead 12 credits does not change COGS. | 2 |
| OPS-009-S12 | Build the internal gross-margin dashboard and a price-floor table (inputs F, v, N, target GM). | `dashboards/gross-margin` | Reproduces G-OPS-13 examples (N=10, GM 75 % → 1,800). | 3 |
| OPS-009-S13 | Access tests for `INTERNAL_COST` from every customer/serving profile user and the API. | `tests/security/test_internal_cost_access.py` | All denied. | 2 |
| OPS-009-S14 | Double-count guard: if Snowflake is purchased via AWS Marketplace, Snowflake charges appear in CUR as Marketplace lines — exclude them from AWS and keep them in Snowflake source. | rule in S06 model + test | Fixture with Marketplace line counted once. | 2 |
| OPS-009-S15 | Evidence with one real staging month. | `docs/evidence/OPS-009/<commit>/` | Control totals and allocation conservation attached. | 2 |

Task acceptance:
- [ ] Allocated + unallocated equals each provider total exactly.
- [ ] 70 % margin fixture and zero-revenue NULL pass.
- [ ] Customer-side credits never enter COGS; Marketplace-billed Snowflake never double counts.
- [ ] No customer or serving role can read internal economics.

### OPS-010 — Publish runbooks, incident process and run incident exercises
Release: R1 · Estimate: 46–70 h · Risk: M · Decisions: D-25 · Closes: G-OPS-15 (process part), G-OPS-16 (process part)
Dependency changes: `+OPS-106` (`bridge-admin`), `+OPS-110`, `+OPS-102`. Milestone M9 unchanged.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-010-S01 | Create the runbook template and catalogue data (owner, trigger alarm IDs, diagnosis commands, containment, recovery, verification, escalation, last rehearsal date). | `docs/runbooks/_template.md`, `docs/runbooks/catalog.yaml` | Every alarm ID in Terraform maps to one runbook (CI check). | 2 |
| OPS-010-S02 | Write RB-01..RB-05 (WIF, Snowpipe lag, partial batch, schema drift, coverage hole) with exact `bridge-admin` commands and expected safe outputs. | `docs/runbooks/RB-01..05-*.md` | Each command executed once in staging with captured output. | 6 |
| OPS-010-S03 | Write RB-06..RB-08 (financial mismatch, bad publication, notification/report DLQ). | `docs/runbooks/RB-06..08-*.md` | Same. | 5 |
| OPS-010-S04 | Write RB-09 (tenant exposure): IC checklist, evidence preservation (CloudTrail/Logs export to evidence bucket), containment switches (REL-102 kill switches), communication templates, regulatory clock note (controller 72 h under GDPR Art. 33; processor informs controller without undue delay — contractual target 48 h, TO VERIFY with counsel). | `docs/runbooks/RB-09-tenant-exposure.md` | Tabletop completes with all checklist items owned. | 4 |
| OPS-010-S05 | Link RB-10..RB-15 to OPS-006/007/005/REL-002 procedures; write RB-15 noisy tenant with quota commands. | `docs/runbooks/RB-10..15-*.md` | Links resolve; commands present. | 4 |
| OPS-010-S06 | Write the incident process: SEV1–3 definitions, roles (incident commander, communications, scribe), update cadence (SEV1 every 30 min), blameless postmortem template with action items. | `docs/incidents/process.md`, `docs/incidents/postmortem-template.md` | Reviewed by on-call members. | 3 |
| OPS-010-S07 | Write support intake form and customer update templates (initial, update, resolved) with the "never ask for passwords/keys" rule. | `docs/support/intake.md`, `docs/support/templates/` | Templates contain no speculative-cause wording. | 2 |
| OPS-010-S08 | Drill: WIF revocation on SYN_A (RB-01). | `docs/evidence/OPS-010/<commit>/drill-rb01.md` | Detection time, containment and resume from checkpoint recorded; no RSA fallback attempted. | 3 |
| OPS-010-S09 | Drill: Snowpipe backlog by disabling notifications (RB-02). | `drill-rb02.md` | Manifests reconcile; no FORCE load; watermark contiguous. | 3 |
| OPS-010-S10 | Drill: schema drift by altering the SYN_B simulator view (RB-04). | `drill-rb04.md` | Only affected source quarantined; others continue. | 3 |
| OPS-010-S11 | Drill: financial mismatch 270 vs 271 (RB-06). | `drill-rb06.md` | Status FAILED with −1; closure blocked; no plug. | 2 |
| OPS-010-S12 | Drill: tenant exposure tabletop plus synthetic A/B exploit reproduction (RB-09). | `drill-rb09.md` | Vulnerable path disabled by kill switch; epochs invalidated. | 4 |
| OPS-010-S13 | Drill: deployment rollback with REL-002 (RB-13). | `drill-rb13.md` | Rollback duration measured. | 2 |
| OPS-010-S14 | Second-engineer oracle: an engineer who did not write RB-10/RB-11 executes one restore from docs only; every gap filed as a blocking task. | `drill-second-engineer.md` | Restore succeeds or gaps filed with owners. | 4 |
| OPS-010-S15 | Put drills on a calendar (restore quarterly, tabletop semi-annually) in OPS-108 evidence. | calendar entries | Next dates visible. | 1 |
| OPS-010-S16 | Evidence index. | `docs/evidence/OPS-010/<commit>/index.md` | All drills listed with outcome. | 2 |

Task acceptance:
- [ ] Every alarm maps to exactly one tested runbook.
- [ ] Six drills executed with measured detection/containment/restore times.
- [ ] A second engineer restores using only the runbook.
- [ ] No drill used unrecorded administrative access.

### OPS-011 — Complete cross-product QA and release evidence matrix
Release: R1 · Estimate: 44–66 h · Risk: M · Decisions: D-01 · Closes: G-OPS-14 (evidence gate)
Dependency changes: `+OPS-107`; INS-007 dependency becomes conditional on D-01 (if verified savings are R2, the matrix records it as a disclosed limitation instead of blocking).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-011-S01 | Define the evidence matrix schema (requirement → task → test level → environment → result → commit → owner → evidence URI → freshness) and generate it from `task-index.json` plus test reports. | `tools/evidence-matrix/`, `docs/evidence/release-matrix/matrix.json` | Matrix lists every R1 task with required levels. | 4 |
| OPS-011-S02 | Implement journey J1 (Playwright + API): signup → org WIF → 2 accounts → backfill → reconcile 270 → book A allocation 120/80 of 200 → budget 280 → monitor → report → action. | `tests/e2e/journeys/j1_first_value.spec.ts` | All figures match fixtures; journey green on staging. | 8 |
| OPS-011-S03 | Implement failure journeys: source loss, duplicate replay, late correction to 269, schema drift, permission revoked mid-session. | `tests/e2e/journeys/j2_failures.spec.ts` | Each shows the documented UX state and preserved totals. | 6 |
| OPS-011-S04 | Persona matrix: 8 roles × key pages with denied states. | `tests/e2e/personas/` | Denied pages reveal no counts/names. | 5 |
| OPS-011-S05 | UX state coverage audit (empty/loading/partial/error/denied/success) against UX-008. | `docs/testing/ux-state-coverage.md` | No required state missing. | 3 |
| OPS-011-S06 | API/UI parity for the same publication ID. | `tests/e2e/parity/` | Values identical to the cent. | 3 |
| OPS-011-S07 | Independent oracle review: FinOps recomputes F-270/allocation/budget fixtures by hand. | signed review record | Reviewer sign-off recorded. | 3 |
| OPS-011-S08 | Nightly live suite on staging against SYN accounts; results attested (cosign attestation on the evidence manifest). | `.github/workflows/live-suite.yml` | Attestation verifies for the candidate commit. | 4 |
| OPS-011-S09 | Promotion gate: fail if any required level lacks evidence for the candidate commit or a justified NOT_APPLICABLE. | policy consumed by REL-001 | Removing one live result blocks promotion. | 3 |
| OPS-011-S10 | Trace PRD §157/§158 items and CHECKLIST gates to evidence rows. | `docs/evidence/release-matrix/traceability.md` | Every §158 step maps to a journey or a disclosed limitation. | 3 |
| OPS-011-S11 | Maintain the limitations register (capability limits, R2 deferrals). | `docs/evidence/release-matrix/limitations.md` | Each limitation has customer-facing wording. | 2 |
| OPS-011-S12 | Publish redacted evidence. | `docs/evidence/OPS-011/<commit>/` | No secrets/customer data (leak scan). | 2 |

Task acceptance:
- [ ] End-to-end figures agree with 270/200/120/80/280 fixtures on staging.
- [ ] Every required test level has evidence for the candidate commit or a justified NOT_APPLICABLE.
- [ ] Live gates cannot be satisfied by mocked results (attestation check).
- [ ] PRD §158 steps are each covered or disclosed as a limitation.

## 5. New tasks required

### OPS-101 — Pipeline ops facts, freshness emitters and data-platform dashboards
Release: R1 · Estimate: 22–34 h · Risk: M · Decisions: D-03, D-06, D-07 · Closes: G-OPS-02, G-OPS-18
Why / where: OPS-001 moves to M1 before ingestion exists; the ingestion/dbt/publication dashboards and the per-batch timeline needed by FRESH-1 and Data Health (PRD §43) need their own task at M3. Plugs in after ING-007 and ORC-003; OPS-002 and OPS-003 depend on it.
Dependency changes: new; deps OPS-001, ING-007, ORC-003.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-101-S01 | Create internal `ops.batch_timeline(batch_id, tenant_id, account_id, source, window_start, window_end, lane, extracted_at, manifest_committed_at, first_receipt_at, accepted_at, processing_run_id, published_at, publication_id)` in an operator-only schema. | `data/dbt/models/ops/batch_timeline.sql` (DDL) | Customer/serving roles have no grant (SHOW GRANTS). | 3 |
| OPS-101-S02 | Emit timeline events at manifest commit, receipt, acceptance, processing-ledger inclusion and publication commit (idempotent upsert by batch_id + event type). | emit calls in ING-005/007, ORC-005 via `packages/telemetry/ops_events.py` | Replaying the same events leaves one row per batch with unchanged timestamps. | 4 |
| OPS-101-S03 | Register pipeline metrics without tenant dimensions: extraction duration/rows/bytes/files by `source_family, lane, outcome`; receipt latency; dbt run duration; `max_publication_age_minutes`; lane backlog ages. | `metrics-registry.yaml` entries | Metrics visible in staging; registry lint passes. | 3 |
| OPS-101-S04 | Build dashboards: ingestion, Snowpipe/receipts, dbt/publication, lanes; each widget links RB-02/03/05/07. | `infra/observability/dashboards/pipeline.json.tftpl` | Render with staging data. | 4 |
| OPS-101-S05 | Create operator saved queries (Logs Insights + Snowflake ops views) for per-tenant drill-down. | `infra/observability/queries/` | Operator finds a batch's full timeline by batch_id in < 1 min. | 2 |
| OPS-101-S06 | Alarms: receipt queue oldest age > 15 min, DLQ depth > 0, 2 consecutive dbt run failures, `max_publication_age_minutes` > 90. | `infra/observability/alarms/pipeline.tf` | Each alarm fires in a staging fault test. | 2 |
| OPS-101-S07 | Expose source lag vs platform lag per source/account to the Data Health API (ING-012): `source_current_through`, `platform_current_through`, `lag_minutes` decomposed. | `apps/api/health/lag.py` | Fixture: source 08:42, platform 08:47 → lag 5 min, matching PRD §121 example. | 3 |
| OPS-101-S08 | Synthetic timeline tests (late receipt, duplicate event, missing publication). | `tests/spec/OPS-101/` | Missing publication after 90 min raises alarm; duplicate event idempotent. | 2 |
| OPS-101-S09 | Evidence. | `docs/evidence/OPS-101/<commit>/` | Screenshots + queries attached. | 1 |

Task acceptance:
- [ ] Every accepted batch has a complete timeline from manifest to publication.
- [ ] Source lag and platform lag are reported separately per source/account.
- [ ] No pipeline metric carries a tenant/account dimension.

### OPS-102 — Alert routing, on-call rota, incident tooling and status page
Release: R1 · Estimate: 18–28 h · Risk: M · Decisions: D-25 · Closes: G-OPS-16
Why / where: CHECKLIST requires "named on-call" and "Working alert routes" but no task configures them; staging carries live synthetic Snowflake data from M2. Plugs in at M1 after OPS-001 and INF-006.
Dependency changes: new; deps OPS-001, INF-006.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-102-S01 | Write the on-call policy: coverage 08:00–19:00 Europe/Paris Mon–Fri (primary + secondary), out-of-hours pages only for SEV1 classes with best-effort 60-min ack, escalation primary → secondary (15 min) → engineering lead (30 min), handover template. Hours are placeholders until D-19 staffing is known. | `docs/operations/oncall-policy.md` | Owner approval recorded. | 2 |
| OPS-102-S02 | Select the paging tool with a decision record (criteria: EU data handling, SNS/CloudWatch integration, schedules, escalation, API; excluded: Opsgenie, end of support 2027-04-05). | `docs/decisions/paging-tool.md` | Record lists ≥ 2 evaluated tools and the choice. | 2 |
| OPS-102-S03 | Create SNS topics per env × severity (KMS-encrypted) and subscriptions to the paging tool and a non-paging Slack channel. | `infra/observability/routing.tf` | Test message reaches paging tool and Slack. | 2 |
| OPS-102-S04 | Enforce alarm tag policy (`owner`, `severity`, `runbook_url`, `impact`) and route by severity. | `infra/policy/alarm-tags.rego` (shared with OPS-003-S12) | Untagged alarm fails CI. | 2 |
| OPS-102-S05 | Configure schedules and escalation; staging alarms never page. | paging tool config exported to `infra/observability/paging/` | Staging alarm only posts to Slack. | 2 |
| OPS-102-S06 | Monthly end-to-end page test and a heartbeat alarm on the paging path itself. | scheduled test | Test page acknowledged; heartbeat absence alarms. | 2 |
| OPS-102-S07 | Set up the status page (components: Web app, API, Data freshness, Reports & notifications) with templates; private until launch. | status page config, `docs/support/status-templates.md` | Test incident published privately. | 3 |
| OPS-102-S08 | Automate incident channel creation and the incident record template. | Slack workflow / bot config | Declaring an incident creates channel + record. | 2 |
| OPS-102-S09 | Evidence. | `docs/evidence/OPS-102/<commit>/` | Page test + escalation captured. | 2 |

Task acceptance:
- [ ] A production SEV1 alarm pages the on-call engineer and escalates if unacknowledged.
- [ ] No alarm exists without owner, severity and runbook.
- [ ] Staging alarms never page.

### OPS-103 — Synthetic Snowflake canary organization and lagged financial canaries
Release: R1 · Estimate: 26–40 h (+ ≈ 100 credits/month, ASSUMPTION) · Risk: M · Decisions: D-08, D-13, D-21 · Closes: G-OPS-05
Why / where: live WIF tests (CON-002/005), canaries (OPS-003), drills (OPS-010) and the E2E live suite (OPS-011) all need continuously active synthetic Snowflake accounts; none is created or funded today. Plugs in at M2 after INF-008 and CON-003.
Dependency changes: new; deps INF-008, CON-003.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-103-S01 | Obtain owner approval/budget and create the synthetic organization with SYN_A (Enterprise, AWS eu-west-1) and SYN_B (Standard, a second region or cloud to exercise non-AWS egress); organization-account/ORGADMIN access for ORGANIZATION_USAGE — TO VERIFY LIVE. | `docs/operations/synthetic-estate.md` (locators in private evidence) | Both accounts reachable; ORGANIZATION_USAGE visible or limitation recorded. | 3 |
| OPS-103-S02 | Bootstrap SYN accounts as code: `SYN_WH` XSMALL AUTO_SUSPEND=60, resource monitors (monthly quota 60 credits, notify 80 %, suspend 100 %). | `infra/synthetic/snowflake.sql` | Second apply is a no-op; monitor visible. | 3 |
| OPS-103-S03 | Create the workload generator: stored procedure + TASK `CRON 7 * * * * UTC` running 20 deterministic queries over `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1` with QUERY_TAG `bridge_canary:<yyyymmddhh>:<n>`, 1 intentionally failing query, daily 10 MB CTAS (storage delta), weekly serverless task. | `infra/synthetic/generator.sql` | QUERY_HISTORY shows 21 tagged queries per hour for 24 h. | 4 |
| OPS-103-S04 | Install Bridge customer scripts (CON-003) on both accounts for staging and production service users; schedule both environments' extraction at the same minute to share one warehouse resume. | install evidence | Both environments extract; BRIDGE_FINOPS_WH resumes once per hour. | 3 |
| OPS-103-S05 | Create the known-answer table in ops (per hour: 20 success, 1 failed; warehouse SYN_WH). | `data/ops/canary_expectations.sql` | Rows generated for the next 7 days. | 2 |
| OPS-103-S06 | Implement lagged canaries: H+2 h count of tagged queries in published query facts = 20 (+1 failed); H+7 h WAREHOUSE_METERING_HISTORY row for SYN_WH hour H present; H+10 h Σ query-attributed + idle = metered compute for that warehouse-hour (exact decimal). | `services/canary/financial_canary.py` | 24 consecutive hours green in staging; removing one batch turns the matching hour red. | 4 |
| OPS-103-S07 | Measure source-availability latency: an ops task polls QUERY_HISTORY every 5 min for the canary tag and records first-seen; feed FRESH-E2E. | `services/canary/source_latency.py` | p50/p95 source latency recorded over 7 days. | 3 |
| OPS-103-S08 | Create production canary tenants CANARY_A/CANARY_B bound to SYN_A/SYN_B; isolation cross-reads in probes. | tenant provisioning script | Cross-tenant probe returns 404. | 2 |
| OPS-103-S09 | Monitor canary spend (credits/month) with alarm at 80 % of budget. | alarm | Alarm fires in a lowered-threshold test. | 2 |
| OPS-103-S10 | Add expiry/drift alarms: account contract/trial expiry date, WIF trust drift, generator task suspended. | alarms | Suspending the task raises an alarm within 2 h. | 1 |
| OPS-103-S11 | Documentation and evidence. | `docs/evidence/OPS-103/<commit>/` | Includes 7-day canary record and credits. | 2 |

Task acceptance:
- [ ] Canary hours evaluate at their lagged horizons and never pass vacuously on empty data.
- [ ] Canary spend stays within the approved monthly quota and suspends at 100 %.
- [ ] Staging and production extract the synthetic accounts through separate service users.

### OPS-104 — Tombstone registry outside restore scope and privacy data inventory
Release: R1 · Estimate: 22–34 h · Risk: H · Decisions: D-10 · Closes: G-OPS-07, G-OPS-09
Why / where: any restore drill (OPS-006 at M2) must replay tombstones from a log that the restore does not roll back. Plugs in at M1 after CTL-002, INF-003 and SEC-001.
Dependency changes: new; deps CTL-002, INF-003, SEC-001; OPS-005, OPS-006, OPS-007 depend on it.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-104-S01 | Create `privacy.tombstones` per §3 with an INSERT-only writer role (no UPDATE/DELETE grants to anyone except the migration owner). | Alembic migration `privacy_0000` | UPDATE by runtime role fails with permission denied. | 2 |
| OPS-104-S02 | Provision the tombstone bucket in the security/log-archive account: versioning, SSE-KMS, bucket policy allowing PutObject only from the dispatcher role, no lifecycle deletion. | `infra/privacy/tombstone-bucket.tf` | Dispatcher can put; nobody else can put or delete (IAM simulator). | 3 |
| OPS-104-S03 | Mirror tombstones: insert + outbox event in one transaction; dispatcher writes `tombstones/seq=<20-digit>.json` idempotently (same bytes on retry). | `services/privacy/tombstone_mirror.py` | Crash between insert and put → object eventually written exactly once. | 3 |
| OPS-104-S04 | Implement `load_tombstones(since_seq)` reading from S3 with gap detection against PG when PG is available. | `packages/privacy/tombstones.py` | Missing object for seq n raises `TOMBSTONE_GAP`. | 3 |
| OPS-104-S05 | Define per-store `apply_tombstone(kind, …)` interfaces (PG, Snowflake, S3, Redis, recovery bucket), idempotent; implementations completed in OPS-005/006/007. | same package | Applying a tombstone twice is a no-op in unit tests. | 3 |
| OPS-104-S06 | Build the data inventory from SEC-001 classes: store, data class, personal data yes/no, retention, deletion mechanism, backup residual, owner. | `docs/privacy/data-inventory.yaml` | Every store named in INF/CTL/ING tasks appears. | 4 |
| OPS-104-S07 | Resurrection unit fixture: PG restored to before tombstone seq 5 → loader applies seq 5 from S3. | `tests/spec/OPS-104/` | Tenant absent after apply. | 2 |
| OPS-104-S08 | Tamper handling: alarm on PutObject to an existing key; versioning preserves original. | CloudTrail data-event alarm | Overwrite attempt alarms. | 2 |
| OPS-104-S09 | Monitor PG max seq vs S3 max seq lag > 5 min. | alarm | Paused dispatcher triggers alarm. | 1 |
| OPS-104-S10 | Docs and evidence. | `docs/evidence/OPS-104/<commit>/` | – | 2 |

Task acceptance:
- [ ] A tombstone survives rollback of PostgreSQL and Snowflake and is replayable from S3.
- [ ] Tombstones contain no personal data (tenant/account UUIDs, subject HMAC only).
- [ ] Gaps and overwrites are detected.

### OPS-105 — Early capacity probes (ingestion at M3, serving at M5)
Release: R1 · Estimate: 26–40 h (+ ≤ 100 credits) · Risk: M · Decisions: D-02, D-06, D-07, D-08 · Closes: G-OPS-11
Why / where: D-06 (multi-tenant dbt), D-07 (account-cycle tasks) and D-02 (per-tenant principals/pools) are architecture bets whose limits must be measured before M4/M5 build on them, not at M9. Part A after ING-008/ORC-003; part B after API-003.
Dependency changes: new; deps ING-008, ORC-003, OPS-101 (part B: +API-003); feeds ONB-101 and OPS-008.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-105-S01 | Write the probe plan and budget cap. | `docs/operations/capacity-probes.md` | Owner approval. | 1 |
| OPS-105-S02 | Build a minimal simulator (subset of OPS-008-S02) and measure extraction rows/s and customer-warehouse seconds per daily chunk at 300 k / 1 M / 3 M queries/day on XSMALL. | probe results | Three data points with p50/p95. | 5 |
| OPS-105-S03 | Measure peak RSS vs Arrow batch size and prefetch settings. | same | Setting that keeps RSS < 70 % documented. | 2 |
| OPS-105-S04 | Measure files/day and size distribution at hourly cadence × 15 sources, and receipt latency p50/p95. | same | Values recorded. | 3 |
| OPS-105-S05 | Measure multi-tenant dbt run time for 10 synthetic tenants with pending batches, including staging-dedup MERGE lock waits on overlapping keys (TO VERIFY LIVE per lead facts). | same | Run time vs tenants curve; lock wait metrics from QUERY_HISTORY. | 5 |
| OPS-105-S06 | Calibrate customer credit estimates (BRIDGE_FINOPS_WH seconds per steady cycle and per backfill day) for ONB-101. | `data/estimates/customer-credit-coefficients.yaml` | Coefficients with confidence ranges. | 2 |
| OPS-105-S07 | Part B: broker query p95 warm/cold on XSMALL serving warehouse for 10 tenants with per-tenant principals (D-02). | same doc | p95 values recorded. | 4 |
| OPS-105-S08 | Part B: connection and pool budget under per-tenant/profile pools (idle pool eviction, max pools). | same doc | Budget formula validated. | 3 |
| OPS-105-S09 | Write recommendations to D-02/D-06/D-07 owners (keep/adjust, with numbers). | decision memo | Memo acknowledged by owners. | 2 |
| OPS-105-S10 | Evidence. | `docs/evidence/OPS-105/<commit>/` | – | 1 |

Task acceptance:
- [ ] Extraction, dbt and serving capacity numbers exist before M4/M5 exit.
- [ ] Customer credit coefficients are available to the onboarding estimate.

### OPS-106 — Operator identity, break-glass, `bridge-admin` CLI and customer-approved support access
Release: R1 · Estimate: 40–60 h · Risk: H · Decisions: D-02, D-22, D-25 · Closes: G-OPS-15
Why / where: every runbook depends on `bridge-admin`, and the operations contract requires time-bound, customer-approved, audited support access; no task builds either. Plugs in at M3 after SEC-008, INF-006, ING-007; support analytics access step waits for API-002.
Dependency changes: new; deps SEC-008, INF-006, ING-007; OPS-004 and OPS-010 depend on it.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-106-S01 | Create IAM Identity Center permission sets `ReadOnlyOps`, `IncidentResponder`, `BreakGlass` (MFA, session ≤ 4 h; BreakGlass requires two-person approval out of band). | `infra/iam/operators.tf` | Sessions expire at 4 h; BreakGlass assignment is empty by default. | 3 |
| OPS-106-S02 | Build the internal ops API (private ALB, SigV4 from operator roles only) per `ops-api.v1.yaml`. | `apps/ops_api/` | Request without SigV4 or from a runtime role → 403. | 4 |
| OPS-106-S03 | Build the `bridge-admin` CLI skeleton: mandatory `--env`, prints caller identity and target, refuses production without explicit `--env production`. | `apps/admin_cli/` | Missing `--env` exits non-zero. | 3 |
| OPS-106-S04 | Implement read-only commands: `health account`, `batch inspect`, `coverage diff`, `reconciliation explain`, `lease list`, `publication show`. | same | Each command tested in staging with captured output. | 8 |
| OPS-106-S05 | Implement dry-run manifests for mutating recovery actions (replay, publication repoint, restore) requiring a second approver's signed approval before execution. | `apps/admin_cli/manifests.py` | Execution without second approval refused. | 4 |
| OPS-106-S06 | Create `support.access_grants` (states REQUESTED → APPROVED → ACTIVE → EXPIRED/REVOKED; scope `health_read`, `analytics_read`, `config_write`; reason code; ticket; default 4 h, max 24 h). | Alembic migration, `services/support/grants.py` | Grant > 24 h rejected; expiry automatic. | 3 |
| OPS-106-S07 | Tenant approval path: Settings › Support access shows pending requests; tenant policy may auto-approve `health_read` only. | `apps/web/settings/support-access`, API | `analytics_read` never auto-approved. | 3 |
| OPS-106-S08 | Support analytics access via a support permission profile inside the tenant (D-02 role), scope = grant, revoked at expiry by epoch bump (after API-002). | broker integration | Expired grant → next query denied within 30 s. | 4 |
| OPS-106-S09 | Write customer-visible audit entries for every support action (who, reason, ticket, time, resource). | audit events | Tenant audit log shows the entries. | 2 |
| OPS-106-S10 | Break-glass: sealed AWS root MFA and Snowflake emergency admin procedure with two-person rule; alarms on CloudTrail root sign-in and Snowflake LOGIN_HISTORY use of the emergency user → SEV1 page. | `docs/security/break-glass.md`, alarms | Test sign-in pages on-call. | 4 |
| OPS-106-S11 | Negative tests: no grant, expired grant, grant for tenant A used on tenant B, read-only command attempting mutation, wrong env. | `tests/security/test_ops_access.py` | All denied and audited. | 3 |
| OPS-106-S12 | Docs and evidence. | `docs/evidence/OPS-106/<commit>/` | – | 2 |

Task acceptance:
- [ ] Operators have no standing access to tenant analytics; all access is granted, time-bound and visible to the tenant.
- [ ] Every runbook command exists in `bridge-admin` and is read-only unless a second approver signs a dry-run manifest.
- [ ] Break-glass use pages on-call.

### OPS-107 — External penetration test and vulnerability disclosure programme
Release: R1 · Estimate: 24–36 h engineering (+ vendor fee, ASSUMPTION EUR 12–25 k) · Risk: M · Decisions: D-25 · Closes: G-OPS-14
Why / where: enterprise security questionnaires require third-party test evidence; internal tests (OPS-004) are not independent. Book at M6 (4–8 week lead time), execute at M9 after OPS-004 on dark production (REL-104) or production-equivalent staging.
Dependency changes: new; deps OPS-004; REL-003 and OPS-011 depend on it.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-107-S01 | Write scope and rules of engagement: web, public API, auth/SSO, tenant isolation with two test tenants and all personas, report links, webhooks, ops API exposure, AWS config review (read-only audit role), central Snowflake config review; exclusions (customer accounts); windows; contacts. | `docs/security/pentest/scope-<year>.md` | Signed by owner and vendor. | 3 |
| OPS-107-S02 | Vendor selection support (certified testers, EU-based data handling). | selection record | Contract signed (owner). | 2 |
| OPS-107-S03 | Prepare environment, personas, SYN accounts access and audit role; freeze deploys during the window. | environment checklist | Vendor confirms access day 1. | 4 |
| OPS-107-S04 | Provide threat model (SEC-001) and architecture briefing. | briefing pack | Delivered. | 2 |
| OPS-107-S05 | Support testers (questions, triage, emergency stop). | log | – | 6 |
| OPS-107-S06 | Triage findings into the OPS-004 exception register; owners fix critical/high in their tasks. | register entries | Every finding has owner and due date. | 4 |
| OPS-107-S07 | Retest and obtain the attestation letter. | letter (private evidence) | No open critical/high. | 2 |
| OPS-107-S08 | Publish `/.well-known/security.txt` (RFC 9116), the disclosure policy page with safe-harbour wording (TO VERIFY with counsel) and the security@ triage procedure (ack ≤ 3 business days). | web route + `docs/security/vdp.md` | security.txt served with Expires field. | 3 |
| OPS-107-S09 | Redacted summary for REL-003/LCH-102. | evidence | – | 2 |

Task acceptance:
- [ ] Independent test executed on the release-candidate configuration; no open critical/high finding at REL-004.
- [ ] security.txt and disclosure policy live before first customer.

### OPS-108 — SOC 2-ready control evidence baseline (continuous from M1)
Release: R1 · Estimate: 32–48 h · Risk: M · Decisions: D-25 · Closes: G-OPS-14
Why / where: a Type II report requires months of evidence generated as operations happen; D-25 asks for SOC 2-ready controls in R1. Plugs in at M1 after INF-007 and SEC-008 and runs continuously.
Dependency changes: new; deps INF-007, SEC-008.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-108-S01 | Write the evidence catalogue: control → generator → frequency → storage → reviewer (change mgmt, access reviews, vulnerability mgmt, backups/DR drills, incidents, logging/monitoring, vendor mgmt, HR on/offboarding, risk assessment, policies, encryption). | `docs/security/evidence-catalog.yaml` | Every control has an automated or manual generator. | 4 |
| OPS-108-S02 | Create the evidence bucket (security account, versioned, retention per owner policy). | `infra/security/evidence-bucket.tf` | Write-only for generators; read for auditors role. | 2 |
| OPS-108-S03 | Change-management evidence: weekly export of branch protection rules; per deploy, release manifest linking PR, reviewers, CI run and deployer. | `tools/evidence/change_mgmt.py` | A deploy without an approved PR is flagged. | 4 |
| OPS-108-S04 | Quarterly access review automation: export IAM Identity Center assignments, GitHub org members/teams, central Snowflake grants (`SHOW GRANTS TO ROLE/USER`), Cognito admin group, PostgreSQL roles; create review ticket; store sign-off. | `tools/evidence/access_review.py` | First review completed with sign-off. | 5 |
| OPS-108-S05 | Vulnerability SLA tracking (critical 7 d, high 30 d) from Dependabot/Inspector/image scans with ageing report. | `tools/evidence/vuln_sla.py` | Report lists overdue items. | 3 |
| OPS-108-S06 | Joiner/mover/leaver checklist with evidence records. | `docs/security/jml.md` | Template used for current team. | 2 |
| OPS-108-S07 | Draft policies (information security, access control, change, incident response, BCP/DR, retention, vendor, acceptable use, encryption) for owner approval. | `docs/security/policies/` | Owner approval recorded. | 6 |
| OPS-108-S08 | Vendor register (AWS, Snowflake, GitHub, paging, status page, email) with SOC report dates and review cadence. | `docs/security/vendors.yaml` | All subprocessors from LCH-102 present. | 2 |
| OPS-108-S09 | AWS Config conformance rules (encryption, public access, CloudTrail on, root MFA) with periodic snapshots. | `infra/security/config-rules.tf` | Non-compliant fixture resource flagged. | 3 |
| OPS-108-S10 | Security training records and risk register. | `docs/security/risk-register.yaml` | First entries recorded. | 2 |
| OPS-108-S11 | Quarterly evidence completeness report. | `tools/evidence/completeness.py` | Missing evidence listed per control. | 2 |
| OPS-108-S12 | Evidence. | `docs/evidence/OPS-108/<commit>/` | – | 1 |

Task acceptance:
- [ ] Every catalogue control produces dated evidence from M1 onward.
- [ ] First quarterly access review signed off.
- [ ] Deploys without approved review are detectable.

### OPS-109 — Cost-attribution instrumentation (tags, QUERY_TAG, processing ledger)
Release: R1 · Estimate: 20–30 h · Risk: M · Decisions: D-02, D-06, D-07 · Closes: G-OPS-12
Why / where: OPS-009 at M9 can only attribute months for which tags and driver facts were recorded; they must be emitted from the first pipeline runs (M3).
Dependency changes: new; deps OPS-001, ORC-003, INF-008; OPS-009 depends on it.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-109-S01 | Enforce AWS tags `environment, component, cost_owner` via Terraform `default_tags` and an organization tag policy; activate them as cost-allocation tags. | `infra/tagging.tf` | Untagged resource fixture fails policy. | 2 |
| OPS-109-S02 | Create `ops.processing_ledger` and a dbt `on-run-end` hook writing input rows/bytes per tenant per model per run. | `data/dbt/macros/processing_ledger.sql` | A 3-tenant run writes 3 rows per model with correct counts. | 4 |
| OPS-109-S03 | Apply the QUERY_TAG builder in extraction, dbt (`query_tag` config), broker and reports. | code changes in those services | – | 3 |
| OPS-109-S04 | Maintain the serving-user → tenant registry for attribution (D-02). | `ops.serving_principal_map` | Every serving user maps to one tenant. | 2 |
| OPS-109-S05 | Record ECS task usage per account-cycle (tenant, account, vCPU, memory, seconds). | `ops.task_usage` | Sum of task-seconds per day within ± 2 % of ECS metrics. | 3 |
| OPS-109-S06 | Record extraction bytes per tenant (manifest bytes and network bytes if measurable). | `ops.batch_timeline` columns | – | 2 |
| OPS-109-S07 | Coverage test: over 24 h in staging, ≥ 99 % of central Snowflake queries have a parsable QUERY_TAG; untagged queries listed. | `tests/spec/OPS-109/` | Coverage report attached. | 3 |
| OPS-109-S08 | Enable AWS CUR 2.0/Data Exports (daily Parquet) to the internal cost bucket. | `infra/cost/cur.tf` | First export delivered. | 2 |
| OPS-109-S09 | Evidence. | `docs/evidence/OPS-109/<commit>/` | – | 1 |

Task acceptance:
- [ ] Every central Snowflake workload is attributable to a component and run; single-tenant queries also to a tenant.
- [ ] Multi-tenant dbt runs record per-tenant input rows.

### OPS-110 — Notification and report delivery SLIs
Release: R1 · Estimate: 14–22 h · Risk: L · Decisions: none · Closes: G-OPS-02
Why / where: split from OPS-003 so API/freshness SLOs are not delayed to M7. Plugs in after GOV-007 and RPT-005.
Dependency changes: new; deps OPS-003, GOV-007, RPT-005; OPS-010 depends on it.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-110-S01 | Define NOTIF-DELIVERY (logical notifications DELIVERED ≤ 10 min after episode open / all, target 99 %) and REPORT-DELIVERY (occurrences delivered ≤ 60 min after scheduled time, 99 %); customer-destination permanent errors are counted and shown as destination health, not silently excluded. | catalogue entries | Reviewed. | 2 |
| OPS-110-S02 | Emit SLI events from GOV-007/RPT outbox transitions. | `services/slo/delivery.py` | Fixture counts correct. | 3 |
| OPS-110-S03 | Classify destination permanent errors: HTTP 401/403/404/410, Slack `invalid_auth`/`channel_not_found`, SES permanent bounce. | `services/slo/destination_errors.py` | Table-driven test. | 2 |
| OPS-110-S04 | Burn alarms and DLQ alarms with owners. | alarms | Fault test fires. | 2 |
| OPS-110-S05 | Fault tests: webhook 500 then success within 10 min (good), permanent 410 (destination DEGRADED, visible), SES throttling. | `tests/spec/OPS-110/` | Outcomes as stated. | 3 |
| OPS-110-S06 | Dashboard and RB-08 update. | dashboard, runbook | – | 2 |
| OPS-110-S07 | Show destination health (status, last error class, last success time) per destination in Settings › Integrations so customer-caused permanent failures are visible to the customer. | `apps/web/settings/integrations` health panel | Revoked Slack token fixture shows DEGRADED with `invalid_auth` class. | 2 |
| OPS-110-S08 | Evidence. | `docs/evidence/OPS-110/<commit>/` | – | 1 |

Task acceptance:
- [ ] Delivery SLIs computed with visible, counted destination-error classes.

### OPS-111 — Regional recovery: Snowflake database replication and S3 cross-region copies (R2)
Release: R2 · Estimate: 22–36 h · Risk: M · Decisions: D-23 · Closes: G-OPS-06 (Tier 3)
Why / where: optional regional protection; requires owner decision on cost and EU-only residency (eu-west-1 → eu-central-1).
Dependency changes: new; deps OPS-007.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| OPS-111-S01 | Record owner decision (residency, cost ceiling, RTO target). | decision record | Approved. | 2 |
| OPS-111-S02 | Create secondary EU account and database replication for LEDGER/SERVING/CONFIG with hourly refresh; measure cost (TO VERIFY LIVE). | `infra/snowflake/replication.sql` | Refresh history shows success; cost measured. | 4 |
| OPS-111-S03 | Enable S3 cross-region replication for recovery and tombstone buckets. | `infra/recovery/crr.tf` | Replication status COMPLETED on test objects. | 2 |
| OPS-111-S04 | Measure replication lag and monthly cost for 30 days. | evidence | Values recorded. | 3 |
| OPS-111-S05 | Regional drill: writable clone of secondary databases, identities/policies recreated, broker switched. | drill record | RTO measured. | 6 |
| OPS-111-S06 | Decide Aurora cross-region snapshot copy vs Global Database. | decision record | Approved. | 4 |
| OPS-111-S07 | Write the owner cost/benefit memo: measured monthly cost vs RTO/RPO gained, residency confirmation. | decision memo | Owner decision recorded (keep or disable). | 2 |
| OPS-111-S08 | Runbook and evidence. | `docs/runbooks/RB-16-regional.md` | – | 3 |

Task acceptance:
- [ ] Regional drill executed with measured RPO/RTO and monthly cost.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| OPS-001 | R1 | 34 | 52 |
| OPS-002 | R1 | 38 | 58 |
| OPS-003 | R1 | 34 | 52 |
| OPS-004 | R1 | 56 | 84 |
| OPS-005 | R1 | 58 | 86 |
| OPS-006 | R1 | 34 | 50 |
| OPS-007 | R1 | 56 | 84 |
| OPS-008 | R1 | 56 | 90 |
| OPS-009 | R1 | 38 | 56 |
| OPS-010 | R1 | 46 | 70 |
| OPS-011 | R1 | 44 | 66 |
| OPS-101 | R1 | 22 | 34 |
| OPS-102 | R1 | 18 | 28 |
| OPS-103 | R1 | 26 | 40 |
| OPS-104 | R1 | 22 | 34 |
| OPS-105 | R1 | 26 | 40 |
| OPS-106 | R1 | 40 | 60 |
| OPS-107 | R1 | 24 | 36 |
| OPS-108 | R1 | 32 | 48 |
| OPS-109 | R1 | 20 | 30 |
| OPS-110 | R1 | 14 | 22 |
| **Total R1** | | **738** | **1120** |
| OPS-111 | R2 | 22 | 36 |
| **Total R2** | | **22** | **36** |

Excluded from hours: benchmark credits (≤ 300 + ≤ 100), canary estate (≈ 100 credits/month), pentest vendor fee, SOC 2 auditor/platform fees.

## 7. Owner questions (only those not already covered by D-01…D-25)

1. Support coverage hours and out-of-hours SEV1 commitment (drives OPS-102 rota and contract wording); how many engineers join the rota?
2. Budget approval: synthetic canary estate (~100 credits/month), benchmark spend (≤ 400 credits one-off), external pentest (EUR 12–25 k), SOC 2 platform/auditor (if pursued).
3. Is central Snowflake Enterprise (needed for row access policies) or Business Critical? BC changes Tier 1 (retention lock available but still not recommended) and makes failover groups available for OPS-111.
4. Paging and status-page vendors (must accept EU data handling; not Opsgenie).
5. Accounting retention period for commercial records kept after tenant deletion (jurisdiction-dependent; see LCH-103).
6. Is dbt cadence 15 min (FRESH-1 30 min, ≈ 243 transform credits/month) or 30 min (FRESH-1 45 min, ≈ 122 credits/month) for R1?

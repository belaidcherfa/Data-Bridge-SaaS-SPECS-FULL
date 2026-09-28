# ING — Implementation-readiness review and production backlog

Canonical contract: [ingestion.md](../../05-ingestion/ingestion.md) and [source-catalog.md](../../05-ingestion/source-catalog.md). Related: [ADR-006](../../architecture/adr/ADR-006-batch-commit-and-coverage.md), [ADR-009](../../architecture/adr/ADR-009-privacy-and-retention.md), [ADR-008](../../architecture/adr/ADR-008-queues-and-orchestration.md), [validation strategy — sync fault matrix](../../15-testing/validation-strategy.md), [RB-01…RB-05](../../16-observability/RUNBOOKS.md), [data-health UI](../../21-ui-ux/pages/data-health.md), PRD §17–§43 and §120–§128. Companion: [CON.md](CON.md). Tasks reviewed: ING-001 … ING-012. Reviewer: domain audit agent, 2026-09-27 (vendor checks run 2026-09-28). Status of all tasks: NOT_STARTED.

## 1. Verdict

The durability design is right: immutable objects, manifest-last, accepted-batch gating, interval coverage and replay under new keys. But the domain cannot produce correct data as specified. Two defects silently corrupt financial facts on day one:

1. **Long-running queries are lost** (G-ING-01). QUERY_HISTORY and QUERY_ATTRIBUTION_HISTORY are extracted by START_TIME with a finite overlap. Any query running longer than ≈75–120 min (QH), or ≈15 h (QAH), never gets extracted. Those are precisely the most expensive queries.
2. **Credits become floats** (G-ING-02). The Python connector turns every scaled NUMBER into float64 by default before Arrow/Parquet.

Other gaps:
- Parquet loading misreads timestamps without `USE_LOGICAL_TYPE` (G-ING-03).
- The key grammar and the IAM prefix policy allow cross-tenant key crafting (G-ING-04).
- The D-07 account-cycle runner and its trust path to the control plane have no owner (G-ING-08/09).
- Complete-partition snapshots can wipe billing data on a silent empty read (G-ING-07).

Author first: the registry schema with explicit watermark modes (§3.1 contract table), the key grammar, the manifest v1 schema, and the acceptance / revision / schema-diff / health decision tables (§3.2–§3.6). R1 effort is ≈ 595–865 senior hours (§6 after RECONCILIATION and the owner decisions of 2026-09-28: 657–973 h, including ING-105's R1 part for the D-20 service families). The task files assume 12 × 2–6 h. The INFORMATION_SCHEMA hot path is deferred to R2 (D-24 confirmed, G-ING-14).

## 2. Findings

### G-ING-01 · START_TIME windows with finite overlap silently lose long-running queries; "pending-query refresh" cannot be implemented as described
Severity: BLOCKER · Type: GAP / VENDOR-FACT
Evidence:
- `source-catalog.md` QUERY_HISTORY — "Account+QUERY_ID; START_TIME half-open … 15m cadence, 2h overlap … documented latency up to 45m. Long-running queries get a separate pending-query refresh until completion."
- QUERY_ATTRIBUTION_HISTORY — "START_TIME … Hourly, 24h overlap … Up to 8h source latency" (8 h VERIFIED, search snippet docs.snowflake.com/en/sql-reference/account-usage/query_attribution_history, 2026-09-28).
- `STATEMENT_TIMEOUT_IN_SECONDS` default 172800 s (48 h); a value of 0 enforces the maximum 604800 s (7 days). VERIFIED (search snippets of docs.snowflake.com parameters/show-parameters, 2026-09-28).
- The widely used dbt-snowflake-monitoring package filters QUERY_HISTORY with `where end_time > …` and the comment "must use end time in case query hasn't completed". VERIFIED (raw.githubusercontent.com/get-select/dbt-snowflake-monitoring/main/models/staging/stg_query_history.sql, 2026-09-28).
- Whether ACCOUNT_USAGE.QUERY_HISTORY exposes *running* queries is TO VERIFY LIVE. The design below does not depend on the answer.

Computation (QH, catalog defaults): at run time t the window starts at checkpoint − 2 h ≈ (t − 15 min) − 2 h. A query with start s and end e appears in the view at a ≤ e + L, where L ≤ 45 min. It is captured only if some run t ≥ a still has t − 2 h 15 min ≤ s. With 15-min runs, the worst case needs a ≤ s + 2 h. Therefore every query with duration > 2 h − L is lost:
- at L = 45 min, queries longer than **75 min** are lost;
- at L ≈ 0, queries longer than **120 min** are lost.

For QAH (hourly, 24 h overlap, L ≤ 8 h), the same computation gives: lost if duration > 24 h − 1 h − 8 h = **15 h**. The "pending-query refresh" needs to know that a query is running. ACCOUNT_USAGE either does not show running queries, or shows them without final values; INFORMATION_SCHEMA (the only no-latency source) is deferred by D-24 and limited to 10,000 rows per call.

Why it matters: dbt full refreshes, backfills and large ETL runs commonly exceed 75 minutes, and they dominate warehouse spend.
- QH rows carry user, role, warehouse and tag. Without them, QAH credits for those queries have no attributes, so allocation falls to "unallocated".
- A lost QAH row makes the query's compute appear as idle.
- Coverage "complete through T" is also false for still-running queries.

Resolution:
1. Replace "overlap" with explicit watermark modes (§3.1). QH and QAH use `END_TIME_SWEEP`: `END_TIME >= :ws AND END_TIME < :we AND START_TIME >= DATEADD(day, -8, :ws)`. The START_TIME bound is a pruning hint of 7 days maximum statement timeout plus 1 day. Each completed query falls into exactly one END_TIME window, whatever its duration. Coverage means "all queries *completed* before T".
2. Replace overlap re-reads with a **pass schedule** per window: FIRST at `we + first_delay` (PROVISIONAL) and SETTLE at `we + settle` (QH 1 h/2 h; QAH 1 h/12 h). Anything later is caught by checksum anti-entropy (§3.1).
3. QMH (Adaptive) keeps `QUERY_METERING_HOUR` windows plus a real pending set: rows with `QUERY_END_TIME IS NULL` are re-read by hour ≥ the oldest pending hour until closed, bounded at 8 days.
4. Start-keyed companions that lack END_TIME (ACCESS_HISTORY, R2) use a "long-tail companion" predicate: `QUERY_START_TIME` in the window, OR `QUERY_ID IN (<long queries completed in this QH window whose START_TIME < ws − O>)`.
5. ING-002-S08 live-benchmarks partition pruning of END_TIME-only versus START_TIME-bounded predicates and records the choice in the registry.
6. Alarm when observed `END_TIME − START_TIME > 7 d` (horizon breach).
7. Run a live probe (ING-101-S03): `SELECT COUNT(*) FROM TABLE(GENERATOR(TIMELIMIT => 5400))` on BRIDGE_FINOPS_WH (≈1.5 XS credits). Record whether and when the query appears in AU.QUERY_HISTORY and AU.QUERY_ATTRIBUTION_HISTORY.

This challenges source-catalog QH/QAH predicates and PRD §34. D-14 proration then works from complete START/END times.
Affects: ING-001, ING-002, ING-101, ING-008, ING-012, FIN-003 (D-14).

### G-ING-02 · The connector converts scaled NUMBER to float64 by default; batch schemas vary; empty results carry no schema
Severity: BLOCKER · Type: VENDOR-FACT
Evidence:
- snowflake-connector-python main: `connection.py` — `"arrow_number_to_decimal": (False, bool)`. `nanoarrow_cpp/ArrowIterator/CArrowTableIterator.cpp` — "Convert scaled fixed number to either Double, or Decimal based on setting … map to arrow:float64()".
- `cursor.fetch_arrow_batches(force_microsecond_precision=False)` docstring — "precision is determined per-batch based on the data, which may cause pyarrow schema mismatch errors when combining batches"; `fetch_arrow_all` returns `None` for zero rows unless `force_return_table=True`.
- All VERIFIED (github.com/snowflakedb/snowflake-connector-python, fetched 2026-09-28).
- Independently raised as G-FIN-02.
- `ingestion.md` — "Snowflake NUMBER→Arrow decimal128 with original precision/scale" (no flag named).

Why it matters: `CREDITS_USED NUMBER(38,9)` is written to the *immutable* journal as a binary float. Replay cannot repair it. An exact oracle such as "15 − 10 = 5 credits" can drift in the last digits. Per-batch timestamp units break ParquetWriter mid-file. An empty window yields no Arrow schema at all.
Resolution (ING-003):
- `arrow_number_to_decimal=True` on every extractor connection (CON-002-S02).
- `force_microsecond_precision=True` for sources whose registry timestamp scale ≤ 6. For scale > 6, keep nanoseconds and cast per batch.
- **Every batch is cast to the registry-derived Arrow schema** (`safe=True`, overflow → error); the Parquet schema comes from the registry, never from the first batch.
- A contract test fails on any `float`/`double` field that the registry does not declare as a FLOAT source (for example PIPE_USAGE_HISTORY FLOAT fields, which stay float64 and are normalized in dbt).
Affects: ING-003, ING-004, CON-002, FIN-001.

### G-ING-03 · Parquet load options: logical types, error mode and case matching are unspecified or contradictory
Severity: HIGH · Type: VENDOR-FACT / CONTRADICTION
Evidence:
- `ingestion.md` — "`MATCH_BY_COLUMN_NAME=CASE_INSENSITIVE`"; PRD §30 — "`MATCH_BY_COLUMN_NAME = CASE_SENSITIVE`".
- Without `USE_LOGICAL_TYPE = TRUE`, Parquet timestamps load as far-future dates. With `USE_VECTORIZED_SCANNER = TRUE`, logical types are always honoured; the vectorized scanner currently defaults to FALSE and will become default through a BCR. VERIFIED (search snippets of docs.snowflake.com CREATE FILE FORMAT and community.snowflake.com "How to load logical type TIMESTAMP data from Parquet files", 2026-09-28).
- Snowpipe's default `ON_ERROR` is SKIP_FILE, and `INCLUDE_METADATA` works only with `MATCH_BY_COLUMN_NAME`. VERIFIED (snippets of docs.snowflake.com copy-into-table and data-load-snowpipe-ts, 2026-09-28).

Why it matters:
- Silently shifted timestamps put every hour in the wrong billing period.
- `ON_ERROR=CONTINUE` (the COPY default for some formats) would create partial files that pass row counts only by luck.
- A case-sensitive match against upper-case RAW columns loads all-NULL rows.

Resolution:
- File format `BRIDGE_PARQUET_V1`: `TYPE=PARQUET USE_LOGICAL_TYPE=TRUE USE_VECTORIZED_SCANNER=TRUE BINARY_AS_TEXT=FALSE REPLACE_INVALID_CHARACTERS=FALSE`.
- Pipes use `MATCH_BY_COLUMN_NAME=CASE_INSENSITIVE`, explicit `ON_ERROR=SKIP_FILE` and `INCLUDE_METADATA`.
- Parquet field names are lower-snake from the registry; ING-004 rejects case-fold collisions. PRD §30 wording is superseded.
- RAW technical columns are `NOT NULL`, so a schema-mismatched file fails (and is skipped) instead of loading NULL rows.
- Live tests in ING-006-S08: NUMBER(38,9) extremes, negative adjustments, TIMESTAMP_LTZ(6) and (if used) nanoseconds, DATE, Unicode.
Affects: ING-004, ING-006.

### G-ING-04 · Source-first key layout plus wildcard IAM policies allow cross-tenant key crafting; "signed manifest" is undefined
Severity: HIGH · Type: GAP (security)
Evidence: `ingestion.md` — "`landing/source=<registry_id>/schema_major=<n>/tenant_id=<uuid>/…`" and "Sign/authorize manifest publication using the registered task identity … Do not trust tenant_id solely because a file contains it". INF-003 — "restrict connector writes to assigned tenant/account prefix". In IAM resource ARNs, `*` matches across `/`.
Why it matters: a natural policy `landing/source=*/schema_major=*/tenant_id=A/*` also matches `landing/source=QH/schema_major=1/tenant_id=B/…/x/schema_major=1/tenant_id=A/part.parquet`. That key begins inside tenant B's source prefix and lies inside B's pipe stage path. A compromised tenant-A extractor can thus plant files that B's pipe loads. Whether the rows are then attributed to B depends on whether identity is taken from the path or the content. "Signing" has no mechanism, key or verifier.
Resolution:
- (1) The connector role policy enumerates the full prefix per (source, schema_major) with no wildcard before `account_id=<a>/` (CON-001-S03).
- (2) The strict key grammar (§3.2) is enforced by the uploader, the acceptance intake and the pipe `PATTERN`. Snowpipe applies PATTERN to the path *after* the stage prefix (TO VERIFY LIVE), and the pattern allows exactly one `tenant_id=` segment at a fixed depth.
- (3) Acceptance requires path identity = content identity (single-valued `tenant_id/organization_id/account_id` per file) = manifest identity = PG `batch_attempts` identity.
- (4) Replace "signing" with a PG-planned batch registry. `batch_id` is issued by the control plane together with a lease `fencing_token`. The manifest must carry both, and acceptance rejects unplanned batch IDs and stale tokens. KMS signatures would add a key-management burden with no extra guarantee (OVER-ENGINEERING).
Affects: ING-005, ING-006, ING-007, CON-001, INF-003.

### G-ING-05 · The S3 commit protocol lacks conditional writes, and multipart breaks SHA-256 verification
Severity: HIGH · Type: GAP / VENDOR-FACT
Evidence:
- `ingestion.md` — "attempt retries use new batch IDs unless checking an identical existing checksum … Multipart upload aborts cleanly; do not overwrite accepted keys … store SHA-256".
- S3 supports `If-None-Match: *` on PutObject and CompleteMultipartUpload (412 if the key exists). Bucket policies can require it (condition key `s3:if-none-match`). When enforced, CopyObject into that prefix fails (403 or 501). VERIFIED (snippet of docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-writes-enforce.html, 2026-09-28).
- Multipart SHA-256 is a composite checksum of part checksums; full-object checksums for multipart exist for the CRC family. VERIFIED (snippets of docs.aws.amazon.com mpuoverview/checking-object-integrity, 2026-09-28).

Why it matters:
- Without If-None-Match, a retry or bug can overwrite an accepted key. With versioning, that also re-triggers Snowpipe with different bytes.
- Multipart SHA-256 values cannot be compared to a client-side full-file SHA-256.
- Replay via server-side copy breaks as soon as conditional writes are enforced.

Resolution:
- Files are capped at 256 MiB and use single-part PutObject (limit 5 GB) with `ChecksumAlgorithm=SHA256` and `If-None-Match: *`. On 412, `GetObjectAttributes(Checksum)` equal to the expected value means idempotent success; different means `KEY_CONFLICT` and a new attempt.
- The bucket policy denies `PutObject` without `s3:if-none-match` on `landing/`, `manifests/` and `replay/`, and denies `DeleteObject` to connector roles.
- Manifests live under a separate `manifests/` prefix that no pipe watches. Replay re-PUTs bytes (GET → verify SHA-256 → PUT) instead of CopyObject.
Affects: ING-005, ING-011, INF-003.

### G-ING-06 · Receipt evidence depends on load histories with latency and retention limits; duplicate loads are not handled
Severity: HIGH · Type: RISK / VENDOR-FACT
Evidence:
- `ingestion.md` — "Persist load receipts before Snowflake's history windows expire".
- ACCOUNT_USAGE.COPY_HISTORY: latency up to 120 min, and up to 2 days for some low-DML tables; retention 365 days. VERIFIED (snippet of docs.snowflake.com/en/sql-reference/account-usage/copy_history, 2026-09-28).
- Snowpipe load metadata: 14 days; bulk COPY: 64 days. VERIFIED (snippet of docs.snowflake.com/en/user-guide/data-load-snowpipe-intro, 2026-09-28).
- INFORMATION_SCHEMA.COPY_HISTORY: 14-day retention, no latency (TO VERIFY LIVE).
- Snowpipe REST load-history endpoints historically require key-pair JWT auth (TO VERIFY LIVE). That conflicts with D-21 (no RSA).

Why it matters:
- A receipt poller on ACCOUNT_USAGE.COPY_HISTORY adds 2 h–2 days to every acceptance.
- A poller that relies on 14-day histories loses evidence during a two-week incident.
- A repair `COPY INTO … FILES=(…)` after a missed notification can load a file the pipe also loaded, doubling rows.

Resolution (ING-007):
- Success evidence is derived **from RAW itself**: `INCLUDE_METADATA` gives `LOADER_FILENAME` and `LOADER_FILE_ROW_NUMBER`, so `COUNT(DISTINCT LOADER_FILE_ROW_NUMBER)` per file must equal the manifest row count. This never expires while RAW is retained.
- INFORMATION_SCHEMA.COPY_HISTORY is used only for files missing after 15 min, to capture LOAD_FAILED diagnostics. Diagnostics are persisted to PG immediately, with an alarm when any manifest file is receipt-less at day 3.
- `COUNT(*) > COUNT(DISTINCT row_number)` flags DUPLICATE_LOAD. Staging deduplicates by `(LOADER_FILENAME, LOADER_FILE_ROW_NUMBER)`, never by row hash (legitimate identical rows exist).
Affects: ING-006, ING-007, DBT-002.

### G-ING-07 · Complete-partition snapshots can erase billing data after a silent empty read or a retention-edge read
Severity: HIGH · Type: GAP
Evidence:
- `source-catalog.md` — "Latest complete snapshot replaces the partition logically".
- ING-008 oracle — "corrected partition 10+20→10 removes old 20".
- `connectivity.md` — "Empty is not denied".
- Some Snowflake metadata surfaces return 0 rows, not an error, for under-privileged roles (G-CON-08).
- The anti-entropy default is "weekly … over 30 days".

Why it matters: latest-wins turns a single mistaken empty or truncated read into a deletion of real spend. Examples: a grant change, a transient visibility glitch, or a re-read of a partition that has partially aged out of retention (the oldest day of a 365-day window). The deletion is then "reconciled".
Resolution (§3.4):
- **Suspect guard.** A new complete partition whose row count is 0, or whose primary measure sum drops > 50 %, relative to the currently selected revision (previous > 0) is accepted as `SUSPECT`. It is selectable only after a confirming batch ≥ 6 h later with a fresh AVAILABLE probe; alarm at 24 h.
- **Retention edge.** No complete-partition re-extraction for partitions within 7 days of the source retention cutoff.
- **Event sources.** Anti-entropy on event sources (QH, QAH) is **additive only**: it upserts and never deletes.
- The ING-008 oracle stays valid (10+20→10 is accepted when confirmed or when the drop is ≤ 50 % with 1 row remaining).
Affects: ING-008, ING-011, DBT-002, FIN-005.

### G-ING-08 · No component executes the D-07 account-cycle; per-(account, source, window) runs are implied everywhere
Severity: HIGH · Type: GAP
Evidence:
- D-07 — "One ECS task per account-cycle (all due sources, one customer warehouse resume)".
- ING-003 API — "iter_batches(context,window)".
- ORC orchestration — "steady-state extraction 8 total/2 per tenant/1 per account-source".
- No ING/ORC task owns cycle composition, per-source failure isolation, cycle deadline or warehouse suspend.

Why it matters: without a cycle runner, each (account, source, window) launches separately. That means ≈216k runs/day (AUDIT X-12), one customer warehouse resume per source (7–14× the credits in §3.3 of CON.md), and no place to order finance-first work or enforce the hourly budget.
Resolution: new ING-106. `run_account_cycle(cycle_id)`:
- one WIF session;
- due windows computed by ING-002;
- sources in priority order (MDH, WMH, MH, serverless, transfer, storage, QAH, QH);
- per-source try/classify/continue;
- fence and epoch checks between sources and before every manifest;
- hard deadline 45 min (steady) or 2 h (backfill chunk);
- suspend-after-cycle (CON-101);
- jittered start minute `5 + hash(connection_id) mod 50`.

`ORC-003 +ING-106`.
Affects: ING-003, ING-010, ORC-002, ORC-003, CON-101.

### G-ING-09 · The extractor's trust path to the control plane is undefined; Dagster workers cannot run under connection roles
Severity: HIGH · Type: GAP (security)
Evidence:
- ADR-004 — "use Fargate task roles for extraction".
- D-07 — "launched with that account's task role".
- ING-005/ING-008 need PG leases, fencing and batch attempts.
- `orchestration.md` — "Use the OSS ECS run launcher".
- Dagster run workers write event logs to the Dagster metadata DB.

Why it matters:
- If the extractor task holds a PG or Dagster-DB credential, every connection-role task carries a shared secret. A compromised task could then forge other tenants' leases or events, which negates the per-connection IAM boundary.
- If the Dagster run worker is the extractor, it needs both the Dagster DB and the connection role.
- Whether the Dagster ECS launcher supports per-run task-role override is unverified.

Resolution:
- The Dagster run (generic orchestrator role) launches a **separate** extractor ECS task via RunTask (`taskRoleArn` override, env = `cycle_id` only) and polls it. Dagster code never runs under a connection role.
- The extractor talks to an internal `sync-api` authenticated by a presigned `sts:GetCallerIdentity` request (the same pattern Snowflake WIF uses). The server calls STS, obtains `assumed-role/bridge-<env>-conn-<uuid32>/…` (role naming per RECONCILIATION C-11) and maps it to exactly one connection.
- The endpoints authorize only that connection's cycle, leases, batch attempts and manifest registrations. The extractor has no PG or Dagster credentials.
Affects: ING-106, ING-005, ING-007, ORC-001, ORC-002, INF-005.

### G-ING-10 · Backfill sizing, ordering and the catch-up phase are unrealistic at the stated volumes
Severity: MEDIUM · Type: RISK / challenges PRD §40
Evidence:
- PRD §38 — "QUERY_HISTORY 365 daily chunks"; PRD §40 — "365-day backfill ends at T0 … executes T0 → NOW catch-up before … HEALTHY".
- ING-010 — "catch-up never converges".
- D-11 — query grain hot 90 days as recommended; owner decision 2026-09-28: 365 days (`hot_days` default 365).
- G-SEC-15 — ≈3 ms per statement sanitization.

Computation for a 1M queries/day account:
- **Rows.** QH has 365 M rows. QAH ≈ 60 % of queries (short ones are excluded, VERIFIED ≤ ~100 ms) ≈ 220 M.
- **Arrow bytes (ASSUMPTION ≈ 350 B/row metadata, 1.5 KB mean text, 120 B/row QAH):**
  - QH metadata: 365 M × 350 B ≈ 128 GB;
  - text for all 365 days (D-11 owner decision): 365 M × 1.5 KB ≈ 548 GB (135 GB under the 90-day recommendation);
  - QAH: 220 M × 120 B ≈ 26 GB.
- **Parquet ZSTD (ASSUMPTION ratios 10:1 / 5:1 / 8:1):** ≈ 13 + 110 + 3.3 ≈ 126 GB, about 950 files of 128 MiB (43 GB and ≈ 350 files with 90 days of text).
- **Customer credits:** 730 day-chunks × 20–60 s on XS ≈ 4–12 credits, plus ≈ 2 for the other sources; projecting QUERY_TEXT on days 91–365 adds ≈ 0.8–2.3 credits (+10–30 s per QH day-chunk, ASSUMPTION, measured in ING-101-S04).
- **Sanitization:** 365 M texts × 1–3 ms ≈ 100–300 CPU-hours before caching (25–75 under the 90-day recommendation). The parameterized-hash cache, persisted between backfill chunks of one account (SEC-007-S17), is what keeps this tractable.

Why it matters:
- Throughput is bound by the sanitizer, not by Snowflake.
- With D-11 at 365 days every backfilled day carries sanitized text, so sanitizer CPU is ≈ 4× the 90-day plan and the cache hit ratio decides the backfill duration.
- Processing QH newest→oldest lets the oldest days expire from the 365-day source *during* a multi-day backfill.
- A T0→NOW catch-up can chase its own tail.

Resolution (ING-010):
- (a) **Tier-aware projection.** Windows within `hot_days` (default 365 = the whole Account Usage window) project sanitized QUERY_TEXT. Only when a tenant's plan sets `hot_days` < 365 do older windows skip QUERY_TEXT (COLD tail comment only, RECONCILIATION C-01).
- (b) **Ordering.** OU billing → MDH → WMH/MH → serverless/transfer/storage → QAH → QH. Within each source, the *expiring edge* (days within 7 days of the retention cutoff) goes first, then newest→oldest.
- (c) **Steady-first.** Steady-state cycles start at SYNCING from the enrollment boundary; the backfill covers `[start, enrollment_boundary)`. There is no separate catch-up phase, and HEALTHY is evaluated per source on union coverage. This challenges PRD §40 sequencing; its intent (no gap between history and now) is preserved.
- (d) Sanitizer cache per G-SEC-15, persisted between backfill chunks (SEC-007-S17), plus a process pool sized to task vCPUs.
- (e) The estimate shown before consent (CON-101).
Affects: ING-010, ING-107, CON-101, ONB-004.

### G-ING-11 · Small-file economics: per-file cost is gone; fragmentation and bookkeeping remain
Severity: MEDIUM · Type: VENDOR-FACT / RISK
Evidence:
- PRD §22 — "For small sources: one small file/window is preferable".
- Snowpipe simplified pricing, effective 2025-12-08: a fixed 0.0037 credits per GB, replacing per-second compute plus the per-1,000-files charge. Binary formats (Parquet) are billed on observed size. VERIFIED (snippet of docs.snowflake.com/en/release-notes/2025/other/2025-12-08-snowpipe-simplified-pricing, 2026-09-28). The applicable editions for the central account are TO VERIFY.

Computation: per account per day, ≈ 7 hourly sources × 24 windows × 2 passes on the 4 main sources, plus ≈ 10 daily items ≈ 275 files worst case (empty windows produce zero-file manifests, so the real count is lower).
- At 500 accounts: ≈ 137,500 files/day ≈ 1.6/s ≈ 12 M live objects under 90-day retention.
- Snowpipe at ≈ 10 MB/account/day: 5 GB/day × 0.0037 ≈ 0.02 credits/day. Under the old per-file model it would have been 137.5 × 0.06 ≈ 8.25 credits/day.
- S3 PUT: (137.5 k data + 137.5 k manifests) × USD 0.005/1000 ≈ USD 1.4/day.

Why it matters: cost no longer argues for coalescing, and tenant-prefix isolation forbids cross-tenant coalescing anyway. What remains:
- ≈ 11 k tiny micro-partitions per RAW table per day; staging scans become metadata-heavy;
- PG `batch_files` growth (≈ 50 M rows/year).

Resolution:
- One file per (account, source, window, pass) for small sources. No cross-tenant coalescing.
- Staging reads RAW through `LOADER_START_SCAN_TIME >= :last_processed − 1 h` (naturally load-ordered, so pruning works) joined to accepted batches.
- `batch_files` is partitioned monthly in PG and pruned after 400 days.
- OPS-105 benchmark gate: if staging RAW scans exceed a p95 of 60 s at 500 accounts, add daily RAW compaction (CTAS of partitions older than 2 days) as a follow-up.
Affects: ING-004, ING-006, ING-007, DBT-002, OPS-105.

### G-ING-12 · Schema drift must be tracked per account (BCR bundles differ by account) and has no concrete detection query
Severity: MEDIUM · Type: GAP
Evidence:
- PRD §32 — "Daily: DESCRIBE/metadata → compare".
- ING-009 — "Daily schema sensor compares approved inventory".
- Snowflake behavior-change bundles can be enabled or disabled per account during their testing and opt-out periods; the QUERY_HISTORY column change in bundle 2024_02 is an example (search result "QUERY_HISTORY view (Account Usage): Changes to columns and new columns", 2026-09-28). Per-account bundle visibility for the reader role is TO VERIFY LIVE.

Why it matters: a global "approved fingerprint" oscillates between accounts in the middle of a bundle rollout. That either quarantines healthy accounts or accepts a changed schema for the wrong ones. Semantic changes such as a changed meaning or unit are invisible to DESCRIBE.
Resolution: a per-(account, source) fingerprint from `DESCRIBE VIEW` (whether it needs a warehouse is TO VERIFY LIVE; otherwise use cursor `describe()` on the exact projection). The registry allows a *set* of accepted fingerprints per source major. The classification table is §3.5. A curated BCR watchlist (bundle → view → columns → semantic note) is reviewed weekly and can force BREAKING.
Affects: ING-009, CON-005.

### G-ING-13 · A 90-day journal equal to 90-day RAW gives no replay value for financial sources; the retention clock is undefined
Severity: MEDIUM · Type: RISK · challenges ADR-009
Evidence: ADR-009 — "Default S3 replay 90 days, RAW 90 days, canonical 400 days"; PRD §26 — "you can replay without reconnecting to every customer"; OPS backlog — "90-day journal horizon expires ~60–90 days after first backfill".
Why it matters: when a normalization or ledger bug is found on day 120, financial days 1–30 cannot be rebuilt from the journal. They would have to be re-extracted from customers (their credits, an active connection, 365-day source retention permitting). Snapshot-only sources (TABLE_STORAGE_METRICS) cannot be re-extracted at all. Financial sources are tiny: < 1 MB/account/day.
Resolution:
- **Retention tiers per registry `retention_class`.** FINANCIAL (metering, billing, storage, serverless, transfer, snapshots) keeps 400 days in the journal (S3 Glacier Instant Retrieval after 30 days). QUERY_GRAIN (QH, QAH, QMH, ACCESS) keeps 90 days, per D-11.
- **Clock.** The S3 lifecycle clock is object creation (= extraction date). The RAW purge clock is `LOADER_START_SCAN_TIME`. Canonical retention clocks on event date.
- Owner approval is needed (§7 Q2).
Affects: ING-005, ING-011, OPS-005, OPS-007, INF-003.

### G-ING-14 · Hot path should be deferred (D-24 confirmed), but Data Health thresholds and vocabulary are undefined
Severity: MEDIUM · Type: GAP
Evidence:
- ING-012 — "optional recent history with documented function limits; bisect saturated result windows".
- INFORMATION_SCHEMA.QUERY_HISTORY returns at most 10,000 rows over the last 7 days (select.dev snippet, consistent with docs.snowflake.com/en/sql-reference/functions/query_history RESULT_LIMIT; VERIFIED-3P 2026-09-28). Other users' queries require warehouse MONITOR-type privileges (TO VERIFY LIVE).
- PRD §42 lists states without thresholds.
- PRD §120 shows "Estimated coverage 96%", while `onboarding.md` says "use counts/dates, not invented percentages".

Why it matters:
- The hot path adds a broad privilege (MONITOR on every customer warehouse), per-10k-row bisection and a second authority. It returns no credits. It gains ≈ 1 h of freshness over AU plus an hourly cycle (45 min latency).
- Without thresholds, "DELAYED" and "STALE" are arbitrary per engineer.

Resolution:
- R1 ING-012 = Data Health model, API and UI without the hot path. The hot path becomes R2 ING-112.
- The §3.6 thresholds are derived from the registry pass schedule.
- Coverage % = accepted available days ÷ available days per source (measured, not estimated). No ETA is shown until throughput evidence exists.
Affects: ING-012, ONB-001, new ING-112.

### G-ING-15 · The ING chain is over-serialized, and several real edges are missing
Severity: MEDIUM · Type: RISK
Evidence (task-index):
- ING-004←ING-003; ING-006←ING-005; ING-009←ING-008; ING-010←ING-009+CON-006; ING-011←ING-010; ING-012←ING-011.
- ING-001←CON-005 while CON-005 consumes the registry (G-CON-07).
- ING-010 fair admission has no edge to ORC-003 fair queues.

Why it matters: 12 strictly serial ING tasks sit on the 73-task critical path. The Parquet writer does not need the executor, RAW DDL does not need the S3 committer, the schema-drift classifier does not need checkpoints, replay does not need the backfill planner, and Data Health does not need replay.
Resolution: the dependency changes listed per task in §4/§5. The chain becomes ING-001 → {ING-002, ING-004, ING-101…104} → ING-003 → ING-005 → ING-106 → ING-007 → ING-008 → {ING-009, ING-010, ING-011, ING-012} in parallel. That cuts ≈ 5 serial links. `+ORC-003→ING-010`, `+ING-106→ORC-003`.
Affects: all ING tasks, ORC-003.

### G-ING-16 · Orphan source queries and statement bounds are unspecified
Severity: LOW · Type: GAP
Evidence:
- ING-003 — "Kill process mid-fetch … record query ID for safe cancellation"; "orphan source query".
- Snowflake keeps running a query after client disconnect unless `ABORT_DETACHED_QUERY=TRUE` (session parameter; semantics TO VERIFY LIVE).

Why it matters: a killed backfill task leaves a query running on the customer's warehouse until the 3600 s warehouse timeout. That is up to 1 credit on XS per orphan.
Resolution:
- Session `ABORT_DETACHED_QUERY=TRUE`.
- `STATEMENT_TIMEOUT_IN_SECONDS` of 900 (steady) or 3600 (backfill).
- Execute asynchronously and persist the `sfqid` before fetching, so cancellation calls `SYSTEM$CANCEL_QUERY`.
- On a statement timeout, bisect the window (END_TIME halves) down to 5 min, then quarantine the window.
Affects: ING-003.

### G-ING-17 · The query-grain coverage gap from aggregated query history is not registered
Severity: LOW · Type: GAP
Evidence: the Account Usage catalog contains an AGGREGATE_QUERY_HISTORY view (search result title docs.snowflake.com/en/sql-reference/account-usage/aggregate_query_history, 2026-09-28; semantics TO VERIFY). The source catalog has no entry for it.
Why it matters: if high-frequency short queries (for example hybrid-table workloads) are aggregated rather than listed individually, query counts and workload attribution under-report, and the missing detail is invisible to the customer.
Resolution: an R2 registry entry via ING-105. In R1, CON-005 detects the view's non-emptiness and discloses "aggregated queries not itemized" in Data Health.
Affects: ING-105, ING-012.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by (task/micro-task) |
|---|---|---|
| Registry JSON Schema | `data/contracts/sources/_schema.v1.json`: `source_id`; `fq_view`; `scope` (ACCOUNT/ORG); `db_role`; `edition_gate`; `feature_gate`; `projection[]` (name, snowflake_type, scale, nullable, required, privacy_action); `watermark_mode` (END_TIME_SWEEP, START_TIME_INTERVAL, HOUR_PARTITION, DATE_PARTITION, SNAPSHOT, PENDING_REFRESH); `predicate_template`; `pruning_horizon`; `window_steady`; `first_delay`; `settle`; `semantics` (EVENT_UPSERT, COMPLETE_PARTITION, SNAPSHOT); `key[]` / `partition_key[]`; `primary_measure`; `suspect_guard`; `anti_entropy{schedule, method: RESNAPSHOT or CHECKSUM, window_days}`; `backfill_chunk`; `min_chunk`; `retention_days`; `availability_start`; `retention_class` (FINANCIAL/QUERY_GRAIN); `health{expected_lag, grace}`; `doc_url`; `verification_record` | ING-001-S01 |
| R1 source contracts | One file per §3.1 row: `data/contracts/sources/<source_id>.v1.json` with live verification record | ING-101…104 |
| Transport schema | Registry type → Arrow type map (`NUMBER(p,s)`→`decimal128(p,s)`; `FLOAT`→`float64`; `TIMESTAMP_LTZ/TZ(≤6)`→`timestamp[us, UTC]`, `(7–9)`→`timestamp[ns, UTC]`; `TIMESTAMP_NTZ`→`timestamp[us]` + registry semantics; `DATE`→`date32`; `BOOLEAN`→`bool`; `VARCHAR`→`large_utf8`; approved `VARIANT/OBJECT`→`large_utf8` JSON). Technical columns listed after this table. Fingerprint = sha256 of canonical JSON `[(name_lower, arrow_type, nullable)]` sorted by name. | ING-001-S05, ING-004-S01 |
| Key grammar | §3.2 regexes (landing, manifests, replay, probes) with builder/parser round-trip property tests | ING-005-S01 |
| Manifest v1 JSON Schema | Fields listed after this table. | ING-005-S05 |
| PG DDL `sync.*` | Tables listed after this table. | ING-002-S05, ING-005-S07, ING-007-S01, ING-010-S01, ING-011-S01; cycle table `sync.account_cycles` ORC-003-S01 (ING-106-S01 moved there; RECONCILIATION U-12) |
| Snowflake DDL | `RAW.<SOURCE>_V<major>` (technical NOT NULL + typed source columns + `LOADER_FILENAME`, `LOADER_FILE_ROW_NUMBER`, `LOADER_START_SCAN_TIME`, `LOADER_FILE_LAST_MODIFIED`, `LOADER_FILE_CONTENT_KEY`; `ENABLE_SCHEMA_EVOLUTION=FALSE`); file format `BRIDGE_PARQUET_V1`; stage and pipe per source × major; `CONTROL.ACCEPTED_BATCHES(batch_id PK, tenant_id, organization_id, account_id, source_id, schema_major, logical_window_id, window_start, window_end, pass_kind, generation, complete_partition, suspect, file_count, row_count, accepted_at, acceptance_version)` insert-only | ING-006-S01…S05, ING-007-S01 |
| Decision tables | §3.3 acceptance, §3.4 revision selection and suspect guard, §3.5 schema-diff classes, §3.6 health thresholds | ING-007-S05, ING-008-S03, ING-009-S02, ING-012-S01 |
| APIs | Listed after this table. | ING-010-S01, ING-011-S01, ING-012-S03, ING-106-S02 |
| Metrics catalog | Listed after this table. | per task |

Technical columns (transport schema): `tenant_id`, `organization_id`, `account_id` (null only for ORG scope), `source_batch_id`, `logical_window_id`, `source_window_start`, `source_window_end`, `source_extracted_at`, `source_schema_version`, `transport_schema_version`, `privacy_policy_version`, `row_hash`, and `is_bridge_overhead` (QH/QAH only).

Manifest v1 fields — the `ingestion.md` fields plus:
- `connection_id`, `connection_revision`, `connection_epoch`, `lease_id`, `fencing_token`, `attempt_no`;
- `watermark_mode`, `pass_kind` (FIRST/SETTLE/ANTI_ENTROPY/BACKFILL/REPLAY), `generation` (0 = original);
- `partitions_covered[]` (for COMPLETE_PARTITION);
- `observed_min_watermark`, `observed_max_watermark`;
- `files[]`: `ordinal`, `key`, `rows`, `bytes`, `sha256_hex`, `s3_version_id`, `parquet_schema_fingerprint`;
- `replay_of_batch_id` (REPLAY only).

`additionalProperties: false`.

PG tables in `sync.*`:
- `source_config(connection_id, source_id, state, cadence, contract_version)`;
- `planned_windows(logical_window_id, connection_id, source_id, ws, we, pass_kind, due_at, state)`;
- `batch_attempts(batch_id, logical_window_id, lease_id, fencing_token, state, attempt_no)`;
- `batch_files(batch_id, ordinal, key, sha256, rows, receipt_status, raw_rows, raw_distinct_rows, first_seen_at)`, partitioned monthly;
- `coverage(connection_id, source_id, stage, intervals tstzmultirange, settled tstzmultirange, revision bigint)`;
- `leases`, `backfill_plans`, `replay_requests`, `source_health`; the cycle table is ORC-003's `account_cycles` (replaces `cycle_requests`; RECONCILIATION U-12).

APIs:
- `POST /v1/sync/backfills` (preview) and `/{id}/approve`, `/pause`, `/resume`, `/cancel`;
- `POST /v1/sync/replays` (preview) and `/{id}/approve`;
- `GET /v1/data-health`, `GET /v1/data-health/accounts/{id}/sources/{source}/intervals`, `GET /v1/data-health/sync-history`;
- internal `sync-api`: `POST /cycles/{id}/claim`, `/heartbeat`, `/attempts`, `/manifests`, `/outcomes`, authenticated by STS caller identity.

Metrics catalog: `extract_rows_total{source}`, `extract_bytes_total`, `extract_window_seconds`, `cycle_duration_seconds`, `cycle_overrun_total`, `manifest_pending_age_seconds` (oldest), `acceptance_latency_seconds`, `receipt_missing_total`, `duplicate_load_total`, `suspect_partition_total`, `coverage_hole_seconds{stage}`, `source_current_through_lag_seconds{source}`, `schema_drift_total{class}`, `backfill_remaining_windows`, `sanitizer_seconds_total`. The source label is bounded to registry IDs; no tenant labels on public metrics.

### 3.1 Source activation contract table (required before activation; R1 unless marked)

All predicates use bound parameters `:ws/:we` (half-open, UTC session). "first/settle" are delays after the window end. For the D-13 FINAL horizons, maturity is owned by FIN; settle ≤ FINAL.

| Source | Scope · role | Mode · exact predicate | Steady window · first/settle | Semantics · key or partition | Backfill chunk · retention clamp | Anti-entropy | Privacy · special |
|---|---|---|---|---|---|---|---|
| AU.QUERY_HISTORY | ACCOUNT · GOVERNANCE_VIEWER | END_TIME_SWEEP · `END_TIME >= :ws AND END_TIME < :we AND START_TIME >= DATEADD(day,-8,:ws)` | 1 h · 1 h / 2 h | EVENT_UPSERT · (account, QUERY_ID) | 1 day, bisect 1 h, min 5 min · 365 d | Weekly CHECKSUM over 30 d per END_TIME day: COUNT(*), COUNT(DISTINCT QUERY_ID), SUM(TOTAL_ELAPSED_TIME); re-extract mismatched days (additive) | Tiered projection (D-11, RECONCILIATION C-01): HOT ≤ `hot_days` (default 365 = full Account Usage retention; owner decision 2026-09-28) sanitized QUERY_TEXT; COLD `QUERY_TEXT_TAIL_COMMENT` only — fallback for plans with `hot_days` < 365 — (regex in the customer warehouse, ≤ 4,096 chars, parsed by WRK-101, never persisted as text); NONE otherwise. Projection union (catalog + 16 INS columns + DATABASE_ID/NAME, SCHEMA_ID/NAME) frozen in ING-101 (C-10); QUERY_TAG sanitize; USER_NAME HMAC (SEC-103); `is_bridge_overhead`; horizon alarm > 7 d |
| AU.QUERY_ATTRIBUTION_HISTORY | ACCOUNT · USAGE_VIEWER | END_TIME_SWEEP · same predicate shape | 1 h · 1 h / 12 h | EVENT_UPSERT · (account, QUERY_ID) | 1 day · 365 d and availability start (TO VERIFY) | Daily CHECKSUM over 7 d, weekly over 30 d: COUNT, SUM(CREDITS_ATTRIBUTED_COMPUTE), SUM(CREDITS_USED_QUERY_ACCELERATION) | Queries ≤ ~100 ms absent by design (VERIFIED): a missing row means unknown, not zero; projection adds PARENT_QUERY_ID, ROOT_QUERY_ID (ING-101, RECONCILIATION C-10) |
| AU.QUERY_METERING_HISTORY (R1, D-20) | ACCOUNT · USAGE_VIEWER | HOUR_PARTITION + PENDING_REFRESH · `QUERY_METERING_HOUR >= :ws AND QUERY_METERING_HOUR < :we`; pending: hours ≥ oldest pending hour where `QUERY_END_TIME IS NULL`, bounded to 8 d | 1 h · 1 h / 3 h | EVENT_UPSERT · (account, QUERY_ID, QUERY_METERING_HOUR) | 1 day · 365 d | Daily CHECKSUM over 7 d: SUM(CREDITS_USED) per hour | Extracted per account when Adaptive is detected (CON-005-S06 `adaptive_present`) |
| AU.WAREHOUSE_METERING_HISTORY | ACCOUNT · USAGE_VIEWER | HOUR_PARTITION · `START_TIME >= :ws AND START_TIME < :we` | 1 h · 4 h / 24 h | COMPLETE_PARTITION · (account, hour); primary measure CREDITS_USED_COMPUTE + CREDITS_USED_CLOUD_SERVICES | 7 d · 365 d | Daily RESNAPSHOT of last 7 d; day 3 of month RESNAPSHOT of previous month | `CREDITS_ATTRIBUTED_COMPUTE_QUERIES` null for Adaptive (VERIFIED via G-FIN-07) |
| AU.METERING_HISTORY | ACCOUNT · USAGE_VIEWER | HOUR_PARTITION · START_TIME half-open | 1 h · 4 h / 24 h | COMPLETE_PARTITION · (account, hour) incl. null ENTITY_ID rows | 7 d · 365 d (TO VERIFY) | As WMH | Unknown SERVICE_TYPE values are data drift for FIN-021, not schema drift |
| AU.METERING_DAILY_HISTORY | ACCOUNT · USAGE_VIEWER | DATE_PARTITION · `USAGE_DATE >= :ds AND USAGE_DATE < :de` | 1 d · 4 h / 24 h | COMPLETE_PARTITION · (account, USAGE_DATE); measure CREDITS_BILLED (signed) | 31 d · 365 d | Daily RESNAPSHOT of open month + previous month until month_end + 5 d (D-13 N) | Signed adjustment retained |
| OU.USAGE_IN_CURRENCY_DAILY | ORG · ORGANIZATION_BILLING_VIEWER | DATE_PARTITION · USAGE_DATE half-open | 1 d · 24 h / 72 h | COMPLETE_PARTITION · (organization, USAGE_DATE) across all accounts; measure USAGE_IN_CURRENCY | 31 d · since supported start | Daily: open + previous month until month_end + 5 d; weekly: last 3 months; monthly: last 13 months | Reseller: DENIED/unavailable is a capability fact; account-null org fees kept |
| OU.RATE_SHEET_DAILY | ORG · ORGANIZATION_BILLING_VIEWER | DATE_PARTITION · `DATE` half-open | 1 d · 24 h / 48 h | COMPLETE_PARTITION · (organization, DATE) | 31 d · since supported start | As currency | Versioned pricing; never overwrite-only |
| OU.ACCOUNTS | ORG · ORGANIZATION_ACCOUNTS_VIEWER (TO VERIFY) | SNAPSHOT · no predicate (small) | 4×/day | SNAPSHOT · capture_id; key (region, locator) | none (snapshot only) | n/a | Feeds CON-004; contract authored in CON-004-S03, activated for the org cycle by ING-103 (RECONCILIATION U-23); a 0-row snapshot is SUSPECT |
| AU.STORAGE_USAGE | ACCOUNT · USAGE_VIEWER | DATE_PARTITION · USAGE_DATE | 1 d · 3 h / 24 h | COMPLETE_PARTITION · (account, USAGE_DATE) | 31 d · 365 d | Daily RESNAPSHOT of last 7 d | Operational measure (R11) |
| AU.DATABASE_STORAGE_USAGE_HISTORY | ACCOUNT · USAGE_VIEWER | DATE_PARTITION · USAGE_DATE | 1 d · 4 h / 24 h | COMPLETE_PARTITION · (account, USAGE_DATE) all databases, incl. deleted ones | 31 d · 365 d | Daily RESNAPSHOT of last 7 d | Needed for the D-15 "storage by database owner" rule |
| AU.DATABASES | ACCOUNT · OBJECT_VIEWER (TO VERIFY) | SNAPSHOT | daily 03:00 UTC cycle | SNAPSHOT · (account, DATABASE_ID, capture_id) incl. DELETED | none | n/a | Owner mapping for D-15 |
| AU.TABLE_STORAGE_METRICS (opt-in, G-CON-02) | ACCOUNT · TO VERIFY | SNAPSHOT | daily | SNAPSHOT · (account, ID, capture_id) | none; pre-enrollment unavailable | n/a | Strict suspect guard (0 rows when the previous snapshot was > 0 → SUSPECT) |
| AU.AUTOMATIC_CLUSTERING_HISTORY | ACCOUNT · USAGE_VIEWER | HOUR_PARTITION · START_TIME half-open (bucket = hour of START_TIME) | 1 h · 4 h / 24 h | COMPLETE_PARTITION · (account, hour) | 7 d · 365 d | Daily RESNAPSHOT of last 7 d | Reconciles to METERING service total once (FIN) |
| AU.SERVERLESS_TASK_HISTORY | ACCOUNT · USAGE_VIEWER | HOUR_PARTITION · START_TIME | 1 h · 4 h / 24 h | COMPLETE_PARTITION · (account, hour) | 7 d · 365 d | as above | CREDITS_USED documented as VARCHAR: transported as `large_utf8`, exact-decimal parse in dbt (R14) |
| AU.PIPE_USAGE_HISTORY | ACCOUNT · USAGE_VIEWER | HOUR_PARTITION · START_TIME | 1 h · 4 h / 24 h | COMPLETE_PARTITION · (account, hour) incl. null PIPE_ID | 7 d · 365 d | as above | FLOAT/VARIANT fields preserved as-is (G-ING-02 exception list) |
| AU.DATA_TRANSFER_HISTORY | ACCOUNT · USAGE_VIEWER | DATE_PARTITION on `START_TIME` day | 1 d · 4 h / 24 h | COMPLETE_PARTITION · (account, day) | 31 d · 365 d | Daily RESNAPSHOT of last 7 d | BYTES_TRANSFERRED VARIANT/number normalized in dbt |
| Extension families (ING-105) | as catalog | R1 part (D-20; sources of R1 FIN-006/008/012/015–020): MV/SOS/QAS/REPLICATION*/SPCS/CORTEX*/SNOWPIPE_STREAMING*/MARKETPLACE/OU.STORAGE_DAILY_HISTORY per catalog after live verification. R2 part: ACCESS_HISTORY long-tail companion (G-ING-01 §4); WAREHOUSE_EVENTS/LOAD_HISTORY (END_TIME_SWEEP where END exists); AGGREGATE_QUERY_HISTORY. TASK_HISTORY and DYNAMIC_TABLE_REFRESH_HISTORY moved to R1 ING-104 (RECONCILIATION C-10) | — | — | — | — | Each needs the same activation evidence as R1 |

R1 additions per RECONCILIATION C-10 (rows to be completed with the same columns during activation; roles TO VERIFY LIVE): **AU.SESSIONS** (SESSION_ID, CREATED_ON, pseudonymized USER_NAME, CLIENT_APPLICATION_ID/VERSION, CLIENT_ENVIRONMENT:APPLICATION; ING-101), **AU.TAG_REFERENCES** (daily snapshot, Enterprise-gated; ING-103), **AU.TASK_HISTORY** and **AU.DYNAMIC_TABLE_REFRESH_HISTORY** (END_TIME_SWEEP; ING-104, for WRK-004).

Per-row activation evidence (applies to every source): live DESCRIBE hash; bounded SELECT; key-uniqueness query (`SELECT key, COUNT(*) … HAVING COUNT(*) > 1` over 7 d = 0 rows, or a declared aggregation rule); observed latency from the canary or the max(watermark) lag; retention probe (MIN(watermark)); one WIF extraction; one replay fixture; the source-specific test matrix of `source-catalog.md`.

### 3.2 Key grammar (normative; `UUID` = `[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}`)

```text
landing:   ^landing/source=([A-Z][A-Z0-9_]{2,63})/schema_major=([1-9][0-9]{0,2})/tenant_id=(UUID)/organization_id=(UUID)/account_id=(UUID|org)/extraction_date=(20[0-9]{2}-[01][0-9]-[0-3][0-9])/batch_id=(UUID)/part-([0-9]{5})\.parquet$
manifests: ^manifests/source=(...same 5 identity segments...)/extraction_date=(...)/batch_id=(UUID)\.json$
replay:    ^replay/generation=([1-9][0-9]{0,5})/source=(...same as landing after "landing/"...)$
probes:    ^probes/tenant_id=(UUID)/connection_id=(UUID)/probe_id=(UUID)\.json$
pipe PATTERN (applied by Snowpipe to the path after the stage prefix landing/source=<S>/schema_major=<n>/ — TO VERIFY LIVE):
           tenant_id=[0-9a-f-]{36}/organization_id=[0-9a-f-]{36}/account_id=([0-9a-f-]{36}|org)/extraction_date=[0-9]{4}-[0-9]{2}-[0-9]{2}/batch_id=[0-9a-f-]{36}/part-[0-9]{5}[.]parquet
```

Rules: the builder is the only producer; the parser rejects any key that does not round-trip byte-for-byte. The org scope literal `org` is used only when the registry scope is ORG. Lower-case UUIDs only; no `..`, `//`, percent-encoding or trailing slash.

### 3.3 Acceptance decision table

| # | Condition (evaluated in order) | Outcome |
|---|---|---|
| A1 | Manifest fails JSON Schema, `batch_id` not planned in PG, or `fencing_token` ≠ the lease token at publish | REJECT_MANIFEST (alarm; attempt → QUARANTINED) |
| A2 | Any file key fails §3.2, or path identity ≠ manifest identity ≠ attempt identity | QUARANTINED + security alarm |
| A3 | `empty_window=true`, `files=[]`, and a capability observation ≤ 24 h old with status AVAILABLE or AVAILABLE_EMPTY | ACCEPT (confirmed empty coverage) |
| A4 | A3 but the source is COMPLETE_PARTITION financial and the currently selected partition is non-empty | ACCEPT with `suspect=true` (§3.4) |
| A5 | For every file: RAW `COUNT(DISTINCT LOADER_FILE_ROW_NUMBER)` = manifest rows; single-valued `tenant_id/organization_id/account_id/source_batch_id` equal to the manifest; Parquet fingerprint = manifest fingerprint = registry fingerprint for that major | ACCEPT |
| A6 | A5 holds but some file has `COUNT(*) > COUNT(DISTINCT row_number)` | ACCEPT with `duplicate_load=true` (staging dedups by `(LOADER_FILENAME, LOADER_FILE_ROW_NUMBER)`) |
| A7 | Any file has a LOAD_FAILED receipt (INFORMATION_SCHEMA.COPY_HISTORY) | QUARANTINED (new attempt required; the same key is never reloaded) |
| A8 | Any file has no RAW rows and no COPY_HISTORY entry 30 min after manifest arrival | REPAIR: `ALTER PIPE … REFRESH PREFIX` (eligibility window TO VERIFY LIVE, documented 7 d) or `COPY INTO … FILES=(…)` (≤ 1000 files, D-03). After 3 attempts or day 13 → QUARANTINED |
| A9 | RAW rows present but fewer distinct row numbers than the manifest (partial) | QUARANTINED + alarm (impossible under SKIP_FILE; signals a contract bug) |

### 3.4 Revision selection and suspect guard (consumed by DBT-002)

- **EVENT_UPSERT:** per `(tenant_id, account_id, key…)`, keep the row with max `(authority_rank, source_extracted_at, source_batch_id, LOADER_FILE_ROW_NUMBER)`. authority_rank: ACCOUNT_USAGE = 2, HOT (R2) = 1.
- **COMPLETE_PARTITION:** per `(tenant_id, scope_id, source_id, partition_key)`, select batch `b* = argmax(source_extracted_at, batch_id)` among accepted batches with `complete_partition=true` covering the partition and `suspect=false OR confirmed=true`. All rows of that partition come from `b*`; `b*` with 0 rows means the partition is empty.
- **Suspect when previous > 0:** new rows = 0, or `Σ primary_measure(new) < 0.5 × Σ primary_measure(selected)`. The suspect is confirmed if a later batch extracted ≥ 6 h after it, with a fresh AVAILABLE probe, agrees within 0.1 % on the measure. Otherwise the selected revision stays. Alarm at 24 h unresolved.
- **Retention edge:** partitions with `partition_date < now − retention_days + 7 d` are never re-snapshotted.
- **Worked examples:**
  - (a) Corrected partition 10 + 20 → 10 (1 row, measure drop 67 %) → SUSPECT → confirmed 6 h later → selected total 10. Without confirmation it stays 30 and alarms.
  - (b) Duplicate physical attempt: identical rows → unchanged totals.
  - (c) Empty read during a grant glitch → SUSPECT → the next probe is DENIED → never confirmed → previous revision kept.

### 3.5 Schema-diff classification (projected columns only)

| Change | Class | Action |
|---|---|---|
| New view column not in projection | NONE | Record in `observed_extra_columns`; no alarm |
| Add a column to the projection (registry change) | ADDITIVE | Privacy review → RAW `ALTER TABLE ADD COLUMN` (nullable) → transport minor → extractor; order enforced |
| NUMBER precision increase, same scale (≤ 38) | NONE | — |
| NUMBER scale change | BREAKING | New major (RAW table/pipe/stage); quarantine the source for that account |
| VARCHAR length change | NONE | — |
| TIMESTAMP scale increase within the transport unit | NONE; beyond → TRANSFORMABLE (transport minor, unit change) | — |
| TIMESTAMP_LTZ ↔ TIMESTAMP_NTZ, or DATE ↔ TIMESTAMP | BREAKING | — |
| NUMBER ↔ VARCHAR / FLOAT / VARIANT | TRANSFORMABLE only if the registry declares an exact-decimal parse rule and quarantine-on-malformed; else BREAKING | — |
| Nullable → NOT NULL | NONE | — |
| NOT NULL → nullable on a key or partition column | BREAKING | — |
| Optional projected column removed | TRANSFORMABLE | Emit null + `missing_optional` flag; Data Health note |
| Required or key column removed or renamed | BREAKING | Quarantine before extraction |
| View no longer visible | capability NOT_SUPPORTED / DENIED_OR_UNAVAILABLE | Dependent features gated |
| BCR watchlist marks a semantic change | BREAKING (manual) | Same as BREAKING |

### 3.6 Source health thresholds (per account × source; precedence top → bottom)

`expected_lag = first_delay + steady_window` and `grace = max(30 min, 0.25 × expected_lag)`.

| State | Rule |
|---|---|
| DISABLED | Module not selected, or source not activated |
| AWAITING_SETUP / PAUSED / REVOKED | Connection state (CON §3.4) |
| CUSTOMER_QUOTA_EXHAUSTED | Last cycle error class |
| NOT_AVAILABLE | Capability DENIED*, NOT_SUPPORTED or NOT_ENABLED (with reason) |
| QUARANTINED | Schema BREAKING or acceptance QUARANTINED on the frontier window |
| FAILING | ≥ 3 consecutive failed cycles for this source, or a non-retryable class |
| BACKFILLING | A backfill plan is RUNNING and requested-start coverage is not contiguous |
| STALE | `now − source_current_through > 2 × (expected_lag + grace)`, or > 24 h for hourly sources |
| DELAYED | `now − source_current_through > expected_lag + grace` |
| HEALTHY | otherwise |

Examples:
- QH: expected_lag = 1 h + 1 h = 2 h; grace = 30 min; DELAYED at 2 h 30 min; STALE at 5 h.
- WMH: expected_lag = 5 h; grace = 75 min; DELAYED at 6 h 15 min; STALE at 12 h 30 min.
- MDH: expected_lag = 28 h; grace = 7 h; DELAYED at 35 h.

`source_current_through` is the contiguous journaled upper bound. The UI also shows "settled through" and "published through" (ORC-005) as separate lines.

## 4. Revised production backlog

### ING-001 — Create executable source contracts and registry validation (framework)
Release: R1 · Estimate: 28–40 h · Risk: M · Decisions: D-11, D-13 · Closes: G-CON-07, G-ING-01 (modes), G-ING-13 (retention_class)
Dependency changes: `−CON-005 (inverted edge; CON-005 now depends on ING-001)`. FND-004 is retained. Live activation moves to ING-101…104.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-001-S01 | Write the registry JSON Schema with every field in §3 (watermark modes, pass schedule, semantics, suspect guard, anti-entropy, retention_class, health, verification_record). | `data/contracts/sources/_schema.v1.json` | 12 negative fixtures fail (missing key for EVENT_UPSERT, missing partition for COMPLETE_PARTITION, `settle < documented latency`, unknown mode, …). | 4 |
| ING-001-S02 | Implement the loader and validator (`load_registry()`). Cross-field rules: `first_delay ≤ settle`; the END_TIME_SWEEP projection must include START_TIME and END_TIME; `pruning_horizon ≥ 8 d` for END_TIME_SWEEP; each projected field has a privacy_action; no Bridge technical column name in the projection; source_id unique. | `services/extractor/registry.py` | `make validate-registry` runs in CI. A malformed contract fails before any connection is opened (unit test with a network-guard fixture). | 4 |
| ING-001-S03 | Define the generic adapter as a Protocol (`probe`, `plan_windows`, `build_query`, `iter_batches`, `normalize_transport`, `validate_schema`) with one data-driven implementation per watermark mode; custom subclasses only via registry `adapter_override`. | `services/extractor/adapters/base.py`, `modes.py` | Adding a new HOUR_PARTITION source requires only a JSON file (test adds a fixture source with no code change). | 4 |
| ING-001-S04 | Build the query builder: identifiers only from registry constants (quoted); predicate templates per mode with bind variables; `SELECT` list = projection, tier-aware with three tiers (RECONCILIATION C-01): HOT (sanitized `QUERY_TEXT`, ≤ `hot_days`, default 365 = the full Account Usage window — D-11 owner decision 2026-09-28), COLD (`QUERY_TEXT_TAIL_COMMENT` only — trailing-comment regex computed in the customer warehouse, truncated to 4,096 chars, parsed by WRK-101 and never persisted as text; documented fallback used only when a tenant's plan sets `hot_days` < 365) and NONE; never `SELECT *`. | `services/extractor/query_builder.py` | A snapshot test of the generated SQL for all R1 sources. Static scan: 0 `*`, 0 string interpolation of values. | 3 |
| ING-001-S05 | Derive the transport schema from the registry (§3 map) plus technical columns; implement the fingerprint algorithm. | `packages/parquet/transport_schema.py` | Fingerprint is stable across dict ordering; changing the scale of one column changes the fingerprint. | 3 |
| ING-001-S06 | Define version semantics: `source_schema_version`, `transport_schema_version` (major.minor), `raw_schema_major`; compatibility function `is_compatible(old, new) → NONE/ADDITIVE/TRANSFORMABLE/BREAKING` (feeds ING-009). | `services/extractor/versions.py` | Table-driven tests from §3.5 pass. | 3 |
| ING-001-S07 | Implement the activation state machine per source per environment (DRAFT→VERIFIED→ACTIVE→QUARANTINED→RETIRED) with the `verification_record` requirement for VERIFIED (account, edition, DESCRIBE hash, latency, retention, key-uniqueness result, evidence ref). | registry field + validator | A contract without a verification_record cannot be ACTIVE (CI fails). | 2 |
| ING-001-S08 | Encode the QMH grain oracle and source-specific lint rules (QMH key must include QUERY_METERING_HOUR; COMPLETE_PARTITION sources must declare a primary_measure). | registry lints | ING-001 oracle: "QMH grain includes metering hour" is enforced by lint. | 2 |
| ING-001-S09 | Write the documentation generator: registry → human-readable table (replaces hand-edited catalog columns). | `tools/registry_docs.py` | Generated doc diff is reviewed in PRs. | 2 |
| ING-001-S10 | Capture evidence. | `docs/evidence/ING-001/<commit>/` | Reviewed. | 1 |
Task acceptance:
- [ ] Every watermark mode, pass schedule, semantics and retention class is expressible and validated before any query runs.
- [ ] `SELECT *`, missing keys/partitions and settle < latency are rejected by CI.
- [ ] A new standard source needs only a contract file.
- [ ] Tier-aware projection omits QUERY_TEXT outside the hot horizon.

### ING-002 — Implement UTC window planning, pass schedules and source horizons
Release: R1 · Estimate: 36–52 h · Risk: H · Decisions: D-11, D-13, D-14 · Closes: G-ING-01, G-ING-07 (retention edge), G-ING-10 (expiring edge)
Dependency changes: none (ING-001, CTL-004).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-002-S01 | Build the aligned window grid: half-open UTC windows aligned to `window_steady` (1 h / 1 d) and backfill chunks; `logical_window_id = sha256(tenant, scope_id, source_id, contract_major, mode, ws, we)`. | `services/extractor/windows.py::grid` | Property test: the union of the grid over any range equals the range with no overlaps. The same inputs give the same IDs. | 3 |
| ING-002-S02 | Implement the pass schedule: for each window, FIRST due at `we + first_delay` and SETTLE due at `we + settle`. A window is `settled` once an accepted batch has `extracted_at ≥ we + settle`. | `windows.py::due_passes` | QH window [10:00, 11:00): FIRST due 12:00, SETTLE due 13:00. Once a SETTLE batch is accepted, no more passes (except anti-entropy). | 3 |
| ING-002-S03 | Implement the END_TIME_SWEEP planner including the pruning bound (`START_TIME ≥ ws − 8 d`) and the horizon alarm hook. | `modes.py::EndTimeSweep` | Fixture: a query running 01:00→07:00 lands in window [07:00, 08:00) only. A 3-day query lands once. | 3 |
| ING-002-S04 | Implement the PENDING_REFRESH planner (QMH): track pending `(query_id, oldest_open_hour)` from the last batch; re-read hours ≥ the oldest pending hour until `QUERY_END_TIME` is not null, capped at 8 d. | `modes.py::PendingRefresh` | Fixture: a running query's hour 10 row changes 0.25→0.30 between reads, then closes. The final selected row is 0.30 (G-FIN oracle Q1 1.05 intact). | 3 |
| ING-002-S05 | Write the PG `sync.coverage` migration using `tstzmultirange` for journaled/raw_accepted/published/settled, with a revision column, plus `sync.planned_windows`. Function `contiguous_through(multirange, requested_start)`. | migration + `coverage.py` | Accepted [00,01) and [02,03) → checkpoint 01. Filling [01,02) → 03. | 4 |
| ING-002-S06 | Implement the retention clamp and availability horizon: `earliest = max(requested_start, now − retention_days + 2 d safety, availability_start, enrollment_at for SNAPSHOT)`; unavailable intervals are stored explicitly with a reason. | `windows.py::clamp` | 365-day request on a 90-day source gives 90 available and 275 unavailable (RETENTION). A snapshot source gives available from enrollment only. | 3 |
| ING-002-S07 | Implement the anti-entropy planner per registry (RESNAPSHOT daily 7 d / open month / previous month until +5 d; CHECKSUM weekly 30 d). Exclude partitions within 7 d of the retention cutoff. | `windows.py::anti_entropy` | On 2026-10-03 the MDH plan includes Sept 1–30 and Oct 1–2; the QH checksum plan excludes days older than now − 358 d. | 3 |
| ING-002-S08 | Run a live pruning benchmark in an INF-101 estate account: for 1 h windows compare partitions scanned and elapsed time of (a) END_TIME-only, (b) END_TIME + START_TIME ≥ ws − 8 d, (c) START_TIME only (reference). Record the choice in the registry `predicate_template`. | evidence + registry update | The chosen predicate scans ≤ 2× the partitions of (c), or the registry documents the accepted cost. | 5 |
| ING-002-S09 | Write the edge-case test suite: END_TIME exactly = we goes to the next window; leap day 2028-02-29; DST irrelevance (UTC session plus TIMESTAMP_LTZ); future end clamped to `now − first_delay`; clock skew (DB time only); equal timestamps; sparse source; failed middle interval. | `tests/spec/ING-002/` | All pass. The oracle "late record inside settle is re-read; out-of-retention is unavailable, not zero" is asserted. | 4 |
| ING-002-S10 | Implement the long-duration alarm: if any extracted row has `END_TIME − START_TIME > 7 d − 1 d`, emit `watermark_horizon_breach_total{source}` and widen the pruning bound for that account via config. | alarm + config | Fixture with a 6.5-day query fires the alarm. | 2 |
| ING-002-S11 | Write the planner API `plan_windows(requested_range, policy, coverage, now)`: pure and deterministic (injected `now`). | `windows.py` | Identical inputs give identical output (hash test). | 2 |
| ING-002-S12 | Capture evidence. | `docs/evidence/ING-002/<commit>/` | Reviewed. | 1 |
Task acceptance:
- [ ] A query of any duration ≤ 7 d is extracted exactly once, by completion window.
- [ ] Coverage checkpoints never jump holes, and "settled" is tracked separately from "journaled".
- [ ] Retention and availability clamps produce explicit unavailable intervals.
- [ ] The anti-entropy plan never re-snapshots partitions near the retention cutoff.
- [ ] The predicate choice is backed by a live pruning measurement.

### ING-003 — Build bounded Arrow extraction with WIF cancellation
Release: R1 · Estimate: 38–55 h · Risk: H · Decisions: D-07, D-21 · Closes: G-ING-02, G-ING-16
Dependency changes: `−ING-002 (the executor needs the query builder, not the planner)`, `+ING-001`, `+OPS-001` (telemetry library before the first worker), `+FND-102` (recorded view fixtures; RECONCILIATION C-29). CON-002 and SEC-007 are retained. Connector decimal handling end to end is this task's acceptance (absorbs FIN-108-S08; RECONCILIATION U-03).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-003-S01 | Set up the session via CON-002 `connect()`: `USE WAREHOUSE BRIDGE_FINOPS_WH`; session parameters (UTC, QUERY_TAG, `STATEMENT_TIMEOUT_IN_SECONDS` 900/3600, `ABORT_DETACHED_QUERY=TRUE`); verify `arrow_number_to_decimal=True`. | `services/extractor/session.py` | The unit test fails if any flag is missing. Live: `SHOW PARAMETERS IN SESSION` shows the values. | 2 |
| ING-003-S02 | Execute asynchronously: `execute_async` → persist `sfqid` to the batch attempt (via sync-api) → `get_results_from_sfqid` → `fetch_arrow_batches(force_microsecond_precision=<scale ≤ 6>)`. | `services/extractor/executor.py` | The `sfqid` is recorded before the first batch is fetched (test with an injected crash after submit). | 3 |
| ING-003-S03 | Cast every batch to the registry Arrow schema (`pa.Table.cast(schema, safe=True)`). Overflow or invalid → `TransportCastError` with column name only. Zero rows → produce no batches and hand the registry schema to the writer. | `executor.py::normalize` | Fixtures: an int8 → int64 batch cast OK; a decimal overflow raises; float64 for a NUMBER source raises (G-ING-02 guard); an empty result yields a valid empty file schema. | 4 |
| ING-003-S04 | Add the float guard: a contract test over all R1 sources asserts no `float`/`double` in the transport schema unless the registry declares a FLOAT source column (PIPE_USAGE exceptions listed). | `tests/contracts/test_no_float.py` | CI fails when the registry is mutated to map CREDITS_USED to float. The decimal end-to-end check formerly in FIN-108-S08 (NUMBER(38,s) → Arrow decimal128 → Parquet, exact) passes here (RECONCILIATION U-03). | 2 |
| ING-003-S05 | Call the privacy hook per batch (ING-107) before any durable write; the hook is mandatory (the executor refuses to yield without it). | executor ↔ privacy interface | A test proves the Parquet writer never receives raw QUERY_TEXT (sentinel literal absent from files). | 2 |
| ING-003-S06 | Bound memory: `client_prefetch_threads=2`; per-batch row cap; RSS sampler (psutil) every 1 s; backpressure when RSS > 60 % of the container limit (pause fetch). | `executor.py::memory_guard` | A 10 M-row synthetic stream (QH-shaped with 1.5 KB text) stays < 70 % of 4 GB. A graph is attached to the evidence. | 5 |
| ING-003-S07 | Implement bisection: on statement timeout, or result bytes > 2 GiB, or rows > registry cap, split `[ws, we)` into halves recursively down to `min_chunk` (QH 5 min). An irreducible window → quarantine the window with reason `IRREDUCIBLE_SIZE`. Sub-windows keep the parent's logical window for coverage. | `executor.py::bisect` | Fixture: a 1-day window with a synthetic timeout at > 6 h spans → split to 4 × 6 h, accepted coverage equals the full day, no duplicate or missing boundary rows. | 5 |
| ING-003-S08 | Apply the oversized-row policy: QUERY_TEXT > 100 KB → sanitized text dropped with `text_omitted=SIZE`; any single row > 16 MB → quarantine that window. | executor + registry field | Fixture with a 2 MB query text → row kept, text null, flag set. | 2 |
| ING-003-S09 | Handle cancellation: a job cancel or epoch change triggers `SYSTEM$CANCEL_QUERY(sfqid)` or `cursor.abort_query`. A process kill is handled server-side via `ABORT_DETACHED_QUERY` (live-verify within 10 min). Orphan query IDs are listed in the cycle outcome. | `executor.py::cancel` | Live: kill -9 mid-query → AU.QUERY_HISTORY shows the query cancelled/aborted, not completed after its natural duration (TO VERIFY LIVE timing). | 5 |
| ING-003-S10 | Handle session expiry and revoked grants: an expired session triggers reconnect (CON-002-S08) and restarts the current window. A revoked grant → classify DENIED for this source; the cycle continues with other sources. | executor + errors | Live: REVOKE between sources → next source DENIED, remaining sources OK, coverage unchanged for the denied source. | 3 |
| ING-003-S11 | Add observability: `extract_rows_total`, `extract_bytes_total`, `extract_window_seconds`, `extract_bisect_total`, `extract_rss_peak_bytes`; logs carry `sfqid` and the window, never SQL text. | metrics + log schema | Dashboard panels exist. The log grep for `SELECT` is empty. | 2 |
| ING-003-S12 | Write the performance and live evidence: 10 M synthetic rows; one live 1-day QH chunk from an INF-101 estate account. | `docs/evidence/ING-003/<commit>/` | RSS < 70 %. Decimal exactness verified against a Snowflake `SUM(...)::VARCHAR` on the same window. | 3 |
Task acceptance:
- [ ] No float ever enters the transport for NUMBER sources; each batch is cast to the registry schema.
- [ ] Zero-row windows produce a valid empty schema for the writer.
- [ ] Oversized windows bisect without boundary loss; irreducible ones quarantine explicitly.
- [ ] Killed or cancelled jobs leave no long-running orphan queries on the customer warehouse.
- [ ] RSS stays < 70 % on the 10 M-row stream.

### ING-004 — Implement typed Parquet schema and size rotation
Release: R1 · Estimate: 24–36 h · Risk: M · Decisions: — · Closes: G-ING-03 (writer side), G-ING-11
Dependency changes: `−ING-003`, `+ING-001 (the writer needs only the transport schema)`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-004-S01 | Implement the type map per §3 and reject lossy narrowing and case-fold collisions (`Query_Id` vs `QUERY_ID`). | `packages/parquet/schema.py` | Table-driven tests for every registry type. A collision raises. | 3 |
| ING-004-S02 | Configure the writer: `ParquetWriter(version='2.6', compression='zstd', compression_level=3, write_statistics=True, use_dictionary=[low-card columns], data_page_size=1 MiB)`; row groups of about 64 MiB uncompressed; close the file when `sink.tell() ≥ 128 MiB` after a row group; hard cap 256 MiB. | `packages/parquet/writer.py` | A 1 GB synthetic stream yields files in the [100, 256] MiB band except the last. Row totals across files equal the input. | 5 |
| ING-004-S03 | Write key-value metadata: `bridge.batch_id`, `bridge.logical_window_id`, `bridge.schema_fingerprint`, `bridge.contract_version`, `bridge.extractor_image_digest`. | writer | Round-trip read returns the metadata. | 1 |
| ING-004-S04 | Compute `row_hash`: SHA-256 over a canonical encoding of the source fields (registry order; decimals as canonical strings; timestamps as ISO-8601 UTC with the declared precision; nulls as a sentinel), vectorized per batch. Used for diagnostics, not dedup. | `packages/parquet/row_hash.py` | Independent Python reference implementation equality on 10k fixture rows. Throughput ≥ 200k rows/s/core. | 3 |
| ING-004-S05 | Bound local disk: ephemeral storage 30 GiB (backfill); a spool file is deleted after upload is confirmed; `ENOSPC` → fail the batch (no partial manifest). | writer + tests | A disk-full injection leaves no manifest and the attempt is RETRYABLE_FAILED. | 2 |
| ING-004-S06 | Write empty-window output: no Parquet file; the writer returns `[]` with the schema fingerprint for the manifest (`empty_window=true`). | writer | ING-004 oracle: zero rows → valid empty manifest metadata. | 1 |
| ING-004-S07 | Run the Arrow round trip: NUMBER(38,9) max/min, negative adjustment −10.000000000, NUMBER(38,0) 10^37, TIMESTAMP_LTZ(6) at 2026-03-29 01:00 UTC, NTZ, DATE 2028-02-29, 4-byte Unicode, empty strings vs nulls. | `tests/spec/ING-004/roundtrip.py` | Byte-exact equality after Arrow→Parquet→Arrow. | 3 |
| ING-004-S08 | Run the Snowflake round trip in staging: load the same fixture via `BRIDGE_PARQUET_V1` (ING-006 file format) and compare with `SELECT … ::VARCHAR`. | `tests/live/parquet_roundtrip/` | All values equal as strings; nanosecond case recorded as supported or unsupported (TO VERIFY LIVE). | 4 |
| ING-004-S09 | Cross-check sizes: record the compression ratio per source on the synthetic corpus (feeds §G-ING-10 assumptions). | evidence | Ratios recorded; assumptions in G-ING-10 updated. | 1 |
| ING-004-S10 | Capture evidence. | `docs/evidence/ING-004/<commit>/` | Reviewed. | 1 |
Task acceptance:
- [ ] Decimals and timestamps round-trip exactly through Arrow, Parquet and Snowflake at declared precision.
- [ ] File rotation preserves row totals; files ≤ 256 MiB (single-part upload eligible).
- [ ] Case collisions and lossy mappings are rejected.
- [ ] Empty windows produce manifest metadata without files.

### ING-005 — Commit S3 batches and validated manifests
Release: R1 · Estimate: 36–52 h · Risk: H · Decisions: D-11 (retention class) · Closes: G-ING-04, G-ING-05, G-ING-13 (lifecycle rules input)
Dependency changes: `+CON-001 (connection role prefix policy)`, `+CTL-004 (leases/fencing)`. ING-004 and INF-003 are retained.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-005-S01 | Implement the key grammar builder and parser per §3.2; property tests (round-trip, rejection of `..`, `//`, uppercase UUIDs, repeated segments, extra segments). | `packages/parquet/keys.py` | 100k fuzzed keys: every parsed key rebuilds byte-identically. The crafted key with two `tenant_id=` segments is rejected. | 3 |
| ING-005-S02 | Upload single-part with `PutObject(ChecksumAlgorithm='SHA256', ChecksumSHA256=<b64>, IfNoneMatch='*', SSE-KMS)`. On 412, compare `GetObjectAttributes(ObjectAttributes=['Checksum','ObjectSize'])`: equal → idempotent success; different → `KEY_CONFLICT` (new attempt). | `services/extractor/s3.py` | A retry of the same bytes succeeds with 1 object version. Different bytes to the same key → KEY_CONFLICT and 0 overwrite. | 3 |
| ING-005-S03 | Write the bucket policy statements (to INF-003): deny `s3:PutObject` without `s3:if-none-match` on `landing/`, `manifests/`, `replay/`, `probes/`; deny non-TLS; deny non-KMS; deny `DeleteObject` to `bridge-conn-*` roles. | INF-003 change + policy test | A PUT without the header gets 403. A connector DeleteObject gets 403. | 2 |
| ING-005-S04 | Generate the S3 lifecycle rules from the registry `retention_class` (G-ING-13; D-26: FINANCIAL = billing/metering/storage sources, QUERY_GRAIN = query-level sources; INF-003-S03 applies them; RECONCILIATION C-02): QUERY_GRAIN prefixes expire at 90 d; FINANCIAL moves to Glacier IR at 30 d and expires at 400 d. Because the prefix is source-first, rules are per `landing/source=<S>/`. No transitions that generate ObjectCreated events. | INF-003 Terraform input | The Terraform plan shows one rule per source. The lifecycle validation test shows no ObjectCreated event on transition (S3 event log). | 2 |
| ING-005-S05 | Write the manifest v1 JSON Schema (§3 fields, `additionalProperties:false`) and the builder. | `data/contracts/batch-manifest.v1.json`, `packages/parquet/manifest.py` | Positive and negative fixtures pass or fail. The synthetic `ingestion.md` example validates after adding the new required fields. | 3 |
| ING-005-S06 | Publish the manifest last: HEAD every file (size + SHA-256 via GetObjectAttributes) → validate the Parquet footer fingerprint of each file (range GET of the footer) → PUT the manifest to `manifests/…` with If-None-Match → register it via sync-api. | `s3.py::commit` | Crash injection before the manifest PUT → no manifest; the attempt is found by the reconciler as orphan files. | 5 |
| ING-005-S07 | Implement the PG attempt lifecycle (through sync-api): PLANNED → LEASED → EXTRACTING → JOURNALED; `fencing_token` is checked by the server at manifest registration (stale → 409 and the attempt is fenced). | `services/sync_api/attempts.py` | A stale worker registering after lease takeover gets 409 and its manifest is marked REJECT_MANIFEST at intake (A1). | 4 |
| ING-005-S08 | Build the reconciler: an S3 event on `manifests/` plus an hourly LIST of `manifests/` for the last 48 h. Adopt manifests whose PG state is < JOURNALED (crash after manifest, before PG). | `services/ingestion/manifest_reconciler.py` | Fault-matrix case "crash after manifest commit, before PG checkpoint" repaired within ≤ 1 h. | 3 |
| ING-005-S09 | Run the orphan janitor: data files without a manifest 24 h after attempt start → `batch_files.orphan=true`. The janitor role deletes them after 7 d (it is the only role with DeleteObject on landing). RAW rows from orphans are never accepted. | `services/ingestion/janitor.py` | A fixture orphan is deleted at day 7. Acceptance never references it. | 3 |
| ING-005-S10 | Run the fault tests: crash before the last file, after the last file, after the manifest; missing 1 of 3 files (A8 path); duplicate retry. | `tests/recovery/ing_005/` | Validation-strategy fault-matrix rows 1, 4 and 5 pass with checksums recorded. | 3 |
| ING-005-S11 | Run the security negatives (with CON-001-S11): wrong-tenant prefix PUT; crafted key; forged manifest for an unplanned batch_id; manifest with another connection's fencing token. | `tests/security/ing_005.py` | 4/4 denied or rejected with audit/alarm. | 3 |
| ING-005-S12 | Add observability and runbook: `manifest_commit_seconds`, `s3_put_conflict_total`, `orphan_files_total`; RB-03 command shapes (list attempt files, compare checksums). | metrics + runbook | RB-03 dry run on the fixture. | 2 |
Task acceptance:
- [ ] Accepted keys can never be overwritten (conditional writes enforced by bucket policy).
- [ ] SHA-256 is verifiable end to end (single-part ≤ 256 MiB).
- [ ] The manifest is published last, carries fencing/lease identity, and unplanned or stale manifests are rejected.
- [ ] Crash at every commit boundary converges to one logical outcome.
- [ ] Crafted and cross-tenant keys are refused at upload and at intake.

### ING-006 — Provision typed RAW tables, stages and Snowpipe
Release: R1 · Estimate: 37–54 h · Risk: H · Decisions: D-03 · Closes: G-ING-03, G-ING-04 (pipe PATTERN), G-ING-11 (RAW pruning column)
Dependency changes: `−ING-005 (DDL needs the transport schema, not the committer)`, `+ING-004`, `+INF-003`. INF-008 is retained.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-006-S01 | Write the RAW DDL generator from the registry: `RAW.<SOURCE>_V<major>` with technical columns NOT NULL (account_id nullable only for ORG scope), typed source columns, the five `LOADER_*` columns, `ENABLE_SCHEMA_EVOLUTION=FALSE`, `DATA_RETENTION_TIME_IN_DAYS=1`, `COMMENT` = contract version. | `infra/snowflake/ingestion/raw_ddl.py`, generated SQL | Generated DDL for all R1 sources in CI. A re-run is a no-op diff. | 4 |
| ING-006-S02 | Create the storage integration: `STORAGE_ALLOWED_LOCATIONS = ('s3://<bucket>/landing/', 's3://<bucket>/replay/')` (manifests and probes are excluded); IAM trust with external ID from `DESC INTEGRATION`; KMS key policy grants decrypt to the Snowflake IAM user/role. | Terraform + SQL | `LIST @stage` works on landing. `LIST` on `manifests/` via an ad-hoc stage fails (not allowed). | 5 |
| ING-006-S03 | Create file format `BRIDGE_PARQUET_V1` (`USE_LOGICAL_TYPE=TRUE USE_VECTORIZED_SCANNER=TRUE BINARY_AS_TEXT=FALSE REPLACE_INVALID_CHARACTERS=FALSE`). | SQL | The timestamp fixture loads correctly. A control load without logical types reproduces the far-future-date defect (documented once). | 2 |
| ING-006-S04 | Create stages per source × major (`URL='s3://<bucket>/landing/source=<S>/schema_major=<n>/'`) and non-auto replay stages (`replay/`). | SQL generator | Stage count = active sources × majors + replay. | 2 |
| ING-006-S05 | Create the pipes: `CREATE PIPE … AUTO_INGEST=TRUE AWS_SNS_TOPIC='<arn>' AS COPY INTO RAW.<S>_V<n> FROM @stage FILE_FORMAT=BRIDGE_PARQUET_V1 MATCH_BY_COLUMN_NAME=CASE_INSENSITIVE INCLUDE_METADATA=(LOADER_FILENAME=METADATA$FILENAME, LOADER_FILE_ROW_NUMBER=METADATA$FILE_ROW_NUMBER, LOADER_START_SCAN_TIME=METADATA$START_SCAN_TIME, LOADER_FILE_LAST_MODIFIED=METADATA$FILE_LAST_MODIFIED, LOADER_FILE_CONTENT_KEY=METADATA$FILE_CONTENT_KEY) ON_ERROR=SKIP_FILE PATTERN='<§3.2 pipe pattern>'`. | SQL generator | The pipe definition matches a golden file. `SYSTEM$PIPE_STATUS` shows RUNNING. | 3 |
| ING-006-S06 | Build the event topology: an S3 notification on `landing/` suffix `.parquet` → SNS topic → subscriptions (Snowflake pipe queue from `notification_channel`, Bridge `receipt-hints` SQS). A separate notification on `manifests/` suffix `.json` → Bridge `manifest-intake` SQS (with DLQ). | Terraform | Duplicate-delivery test: 1 file → Snowflake loads once; the Bridge queue receives ≥ 1 message; the consumer is idempotent. | 4 |
| ING-006-S07 | Grant roles: `INGEST_OWNER` owns the RAW tables and pipes; the `ingest-acceptor` WIF user gets SELECT on RAW plus INSERT on `CONTROL.ACCEPTED_BATCHES` only; the API reader has no RAW access (INF-008 proof reused). | SQL + tests | The API reader `SELECT` on RAW → insufficient privileges. | 2 |
| ING-006-S08 | Run the live load tests: exactness fixture (ING-004-S07 values); duplicate SNS deliveries; malformed Parquet (LOAD_FAILED visible in INFORMATION_SCHEMA.COPY_HISTORY); a file missing the `tenant_id` column (NOT NULL → file skipped); an extra unknown column (ignored); a crafted key failing PATTERN (not loaded; TO VERIFY LIVE semantics). | `tests/live/snowpipe/` | 6/6 scenarios behave as expected; evidence contains the COPY_HISTORY rows. | 6 |
| ING-006-S09 | Build pipe health: poll `SYSTEM$PIPE_STATUS` every 5 min (executionState, pendingFileCount, lastIngestedTimestamp, lastReceivedMessageTimestamp) → metrics; alarm when paused or when pending > 0 for 30 min with no ingestion. | `services/ingestion/pipe_health.py` | A paused pipe fires the alarm ≤ 10 min. | 3 |
| ING-006-S10 | Write the repair/replay COPY templates (D-03): `COPY INTO RAW.<S>_V<n> FROM @replay_stage FILES=(…≤1000) FILE_FORMAT=… MATCH_BY_COLUMN_NAME=CASE_INSENSITIVE INCLUDE_METADATA=(…) ON_ERROR=ABORT_STATEMENT` via the WIF SQL session of `ingest-acceptor`. | `infra/snowflake/ingestion/copy_templates.sql`, executor | A 3-file replay loads exactly once; a second COPY with the same files loads 0 (64-day load metadata) — recorded. | 3 |
| ING-006-S11 | Write the major-version runbook: new major = new RAW table, stage and pipe; the old pipe keeps running until drained; no ALTER PIPE on an active definition. | runbook | Dry run on staging with a synthetic major 2. | 2 |
| ING-006-S12 | Capture evidence. | `docs/evidence/ING-006/<commit>/` | Reviewed. | 1 |
Task acceptance:
- [ ] Parquet values land typed and exact (logical types on); schema mismatches skip the whole file.
- [ ] Only grammar-conformant keys under landing are loaded; manifests, probes and crafted keys never are.
- [ ] Duplicate notifications produce one load; loader metadata columns are populated on every row.
- [ ] Repair and replay COPY paths exist and are distinct from auto-ingest.
- [ ] Pipe pause or stall is detected ≤ 10 min.

### ING-007 — Build file receipts and complete-batch acceptance
Release: R1 · Estimate: 44–64 h · Risk: H · Decisions: D-03, D-04 (insert-only pattern), D-06 · Closes: G-ING-04 (acceptance checks), G-ING-06
Dependency changes: `+ING-005 (manifests)`, `+ING-106 (the sync-api exists)`. ING-006 and CTL-004 are retained.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-007-S01 | Write the migrations: PG `sync.batch_files` receipt columns (`raw_rows`, `raw_distinct_rows`, `receipt_status`, `copy_history_status`, `first_seen_at`), monthly partitioning; Snowflake `CONTROL.ACCEPTED_BATCHES` (insert-only; `batch_id` PK enforced by an `INSERT … SELECT … WHERE NOT EXISTS`). | migrations + DDL | A second insert of the same batch_id is a no-op (row count unchanged). | 3 |
| ING-007-S02 | Build the manifest intake consumer (SQS `manifest-intake` + reconciler hook): JSON Schema validation, rules A1–A2, register the expected files. | `services/ingestion/intake.py` | A1/A2 fixtures reject or quarantine with alarm. A valid manifest creates N expected-file rows. | 4 |
| ING-007-S03 | Write the RAW evidence query, batched per RAW table every 5 min while pending files exist: `SELECT LOADER_FILENAME, COUNT(*), COUNT(DISTINCT LOADER_FILE_ROW_NUMBER), MIN(tenant_id), MAX(tenant_id), MIN(account_id), MAX(account_id), MIN(source_batch_id), MAX(source_batch_id), MIN(LOADER_START_SCAN_TIME) FROM RAW.<S>_V<n> WHERE LOADER_START_SCAN_TIME >= :oldest_pending − 1 h AND LOADER_FILENAME IN (:pending) GROUP BY 1`. | `services/ingestion/receipts.py` | Plan inspection: pruned by `LOADER_START_SCAN_TIME`. Fixture receipts match. | 5 |
| ING-007-S04 | Capture failure evidence: for files with no RAW rows 15 min after manifest, query `INFORMATION_SCHEMA.COPY_HISTORY(TABLE_NAME=>…, START_TIME=>…)` and persist status and first error (sanitized, no row content) to PG immediately. | `receipts.py::diagnose` | A malformed-file fixture shows LOAD_FAILED in PG within 20 min. | 3 |
| ING-007-S05 | Implement the acceptance decision table §3.3 (A1–A9) as a pure function with a table-driven test. | `services/ingestion/acceptance.py` | 9 rule fixtures give the expected outcomes. The ING-007 oracle 100+100 rows: one file loaded → 0 accepted; both → 200; duplicate → 200 canonical. | 5 |
| ING-007-S06 | Publish acceptance: the `ingest-acceptor` WIF session inserts into `CONTROL.ACCEPTED_BATCHES`, then acks PG (compare-and-set on the attempt state, outbox). Crash reconciliation both ways: Snowflake row without a PG ack → PG adopts; PG ack without a Snowflake row → impossible by ordering (asserted). | `acceptance.py::publish` | A crash injected between insert and ack converges in ≤ 1 cycle. A duplicate acceptance event leaves 1 row. | 5 |
| ING-007-S07 | Implement repair (A8): `ALTER PIPE … REFRESH PREFIX='<batch path>'` when within the eligible window (TO VERIFY LIVE: 7 d), else `COPY INTO … FILES=(…)` from ING-006-S10; ≤ 3 attempts spaced 30 min; then QUARANTINED + RB-02 alarm. | `services/ingestion/repair.py` | Fixture with a dropped notification → repaired and accepted. A double load is detected by A6, not double-counted. | 5 |
| ING-007-S08 | Write the staging contract for DBT-002: staging reads RAW ⋈ `CONTROL.ACCEPTED_BATCHES` on `source_batch_id`, filters `LOADER_START_SCAN_TIME >= :watermark − 1 h`, deduplicates transport duplicates by `(LOADER_FILENAME, LOADER_FILE_ROW_NUMBER)`, and never reads unaccepted rows. | `data/dbt/models/staging/_accepted_batches.sql` contract + dbt test | A dbt test on a fixture with an unaccepted batch → 0 rows in staging. A duplicate load → no duplicates. | 3 |
| ING-007-S09 | Handle late manifests: files loaded before the manifest arrives stay invisible; the manifest arriving later triggers immediate evaluation. | tests | Fault-matrix row 2 passes. | 2 |
| ING-007-S10 | Run the adversarial fixtures: out-of-order loads; a missing file; a duplicate file; a foreign-tenant row inside tenant A's file (A2/A5 → QUARANTINED + security alarm). | `tests/spec/ING-007/` | All incomplete or invalid attempts are invisible to staging (asserted by the dbt test). | 3 |
| ING-007-S11 | Add metrics and alarms: `acceptance_latency_seconds` p95 (target ≤ 20 min after the last file), `manifest_pending_age_seconds` (alarm > 60 min), `receipt_missing_total`, `duplicate_load_total`, `batch_quarantined_total{reason}`; day-3 receipt deadline alarm. | metrics | Alarms fire on fixtures. | 2 |
| ING-007-S12 | Write RB-02 and RB-03 concrete command shapes (batch → files → RAW evidence → COPY_HISTORY → repair). | runbook | Operator dry run ≤ 15 min to diagnosis. | 2 |
| ING-007-S13 | Capture live evidence: 48 h steady state on 2 INF-101 estate accounts; acceptance latency distribution. | `docs/evidence/ING-007/<commit>/` | p95 ≤ 20 min; 0 unexplained pending. | 2 |
Task acceptance:
- [ ] A batch is accepted only when every file's distinct loaded rows equal the manifest and identities agree across path, content, manifest and PG.
- [ ] Receipt success never depends on 14-day load histories; failures are diagnosed and persisted within 20 min.
- [ ] Duplicate loads never duplicate canonical rows.
- [ ] Acceptance is idempotent and crash-safe across Snowflake and PG.

### ING-008 — Advance fenced checkpoints and deterministic source revisions
Release: R1 · Estimate: 32–46 h · Risk: H · Decisions: D-05, D-06, D-13 · Closes: G-ING-07
Dependency changes: none (ING-007, ING-002).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-008-S01 | Implement `compare_and_advance(connection_id, source_id, stage, expected_revision, fencing_token, intervals)`: `UPDATE … SET intervals = intervals + :new, revision = revision + 1 WHERE revision = :expected AND lease token valid`. | `services/ingestion/checkpoints.py` | Concurrent writers: exactly one succeeds; the loser retries with a re-read; a stale fence gets 409. | 4 |
| ING-008-S02 | Implement stage progression: JOURNALED on manifest registration; RAW_ACCEPTED on acceptance ack; SETTLED when a pass meets the settle rule; PUBLISHED on the ORC-005 publication ack. | checkpoints | Fault-matrix "lease expires while old worker runs" passes. | 3 |
| ING-008-S03 | Write the revision-selection specification (§3.4) as dbt macros plus reference SQL for DBT-002: EVENT_UPSERT ordering; COMPLETE_PARTITION `b*` selection; SNAPSHOT capture handling. | `data/contracts/source-revisions.v1.md`, `data/dbt/macros/select_revision.sql` | Macro unit tests (dbt unit tests) match an independent Python reference on 20 fixtures. | 6 |
| ING-008-S04 | Implement the suspect guard: `suspect` flag at acceptance (A4 plus measure-drop rule); confirmation job (≥ 6 h later, fresh probe, ±0.1 %); `CONTROL.PARTITION_CONFIRMATIONS` insert-only. | `services/ingestion/suspect.py` + DDL | Worked examples (a)–(c) of §3.4 produce the documented totals (10 after confirmation; 30 kept without it; previous kept on DENIED). | 5 |
| ING-008-S05 | Enforce the retention edge: the planner refuses RESNAPSHOT of partitions near the cutoff (ING-002-S07); the selection ignores batches flagged `retention_edge`. | code + test | The fixture re-read of the oldest day returning fewer rows does not change totals. | 2 |
| ING-008-S06 | Run the cross-store reconciler (hourly): `CONTROL.ACCEPTED_BATCHES` vs PG raw_accepted coverage; missing-in-PG → adopt; missing-in-Snowflake with PG accepted → alarm (should be impossible). | `services/ingestion/reconcile_coverage.py` | Fault-matrix row 4 passes. | 3 |
| ING-008-S07 | Write the oracle tests: failed middle interval blocks the checkpoint; identical replay yields the same facts; corrected partition 10+20→10 (confirmed) → 10; zero-row confirmed correction → 0; QMH 0.25 + 0.75 then correction 0.30 → 1.05. | `tests/spec/ING-008/` | All pass; values computed independently. | 4 |
| ING-008-S08 | Add metrics: `coverage_hole_seconds{stage}`, `suspect_partition_total`, `suspect_unresolved_age_seconds`, `checkpoint_conflict_total`. | metrics | Dashboard. | 2 |
| ING-008-S09 | Write the RB-05 coverage-hole runbook with multirange queries. | runbook | Dry run. | 2 |
| ING-008-S10 | Capture evidence. | `docs/evidence/ING-008/<commit>/` | Reviewed. | 1 |
Task acceptance:
- [ ] Checkpoints advance only contiguously and only by the current fence holder.
- [ ] Complete-partition corrections delete phantom rows, but only after the suspect guard is satisfied.
- [ ] Silent empty reads and retention-edge reads never reduce selected totals.
- [ ] Snowflake acceptance and PG coverage converge after any crash.

### ING-009 — Handle schema drift and source BCR changes
Release: R1 · Estimate: 28–40 h · Risk: M · Decisions: — · Closes: G-ING-12
Dependency changes: `−ING-008`, `+ING-001 (compatibility function)`, `+ING-006 (major versions)`, `+CON-005 (per-account DESCRIBE)`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-009-S01 | Build the daily schema sensor in the 03:00 UTC account cycle: `DESCRIBE VIEW` for each active source (warehouse need TO VERIFY LIVE; fallback `cursor.describe(projection)`); per-(account, source) fingerprint of projected columns. | `services/extractor/schema_diff.py::sense` | 500 accounts × 17 sources = 8,500 DESCRIBEs/day, fitting inside existing cycles (no extra warehouse resume). | 4 |
| ING-009-S02 | Implement the classifier per §3.5 (uses ING-001-S06). | `schema_diff.py::classify` | Table-driven tests for every row of §3.5. | 3 |
| ING-009-S03 | Support multiple accepted fingerprints per source major (a BCR rollout period); per-account acceptance. | registry field + check | Account X on the new fingerprint and account Y on the old are both healthy when both are listed as accepted. | 2 |
| ING-009-S04 | Maintain a curated BCR watchlist (`bundle`, `view`, `columns`, `semantic_note`, `action`); weekly review task; optional `SYSTEM$BEHAVIOR_CHANGE_BUNDLE_STATUS` per account (privilege TO VERIFY LIVE). | `data/contracts/bcr_watchlist.json`, reviewer checklist | The watchlist entry for a synthetic bundle forces BREAKING for the named column. | 2 |
| ING-009-S05 | Implement the quarantine flow: BREAKING → source state QUARANTINED_SCHEMA for that (account, source) only; the next cycle skips it; Data Health reason; the previous publication stays served. | `schema_diff.py::quarantine` | The ING-009 oracle "removed QUERY_ID blocks that source before publication" holds; other sources keep running. | 3 |
| ING-009-S06 | Enforce the compatible deploy order: registry change → RAW `ALTER TABLE ADD COLUMN` → transport minor → extractor image. The deploy pipeline refuses the extractor if the RAW column is missing. | CI check | CI blocks an out-of-order deploy in a fixture PR. | 3 |
| ING-009-S07 | Build the breaking migration path: new major contract, RAW table, stage and pipe; dual-version staging union with explicit mapping; re-backfill of the impacted windows via ING-010. | runbook + generator support | Staging drill with synthetic major 2: old Parquet still replayable into V1; new files into V2. | 5 |
| ING-009-S08 | Handle rollback: roll the extractor back to the previous version after a partial deploy; previously accepted batches stay valid (fingerprints recorded per batch). | test | Rollback drill passes with no coverage regression. | 2 |
| ING-009-S09 | Handle a denied probe: a failed DESCRIBE (permission) → capability event, not a schema change. | test | The fixture does not quarantine and does raise a capability alert. | 1 |
| ING-009-S10 | Write RB-04 concrete steps and metrics `schema_drift_total{class}`. | runbook + metric | Dry run. | 2 |
| ING-009-S11 | Capture evidence. | `docs/evidence/ING-009/<commit>/` | Reviewed. | 1 |
Task acceptance:
- [ ] Schema is fingerprinted per account daily; multiple accepted fingerprints are supported during BCR rollouts.
- [ ] Only the affected (account, source) is quarantined; other sources and prior publications are unaffected.
- [ ] Compatible changes deploy in enforced order; breaking changes use a new major with replayable old data.

### ING-010 — Plan historical backfills with steady-first coverage and fair admission
Release: R1 · Estimate: 48–70 h · Risk: H · Decisions: D-07, D-08, D-11, D-13 · Closes: G-ING-10
Dependency changes: `−ING-009`, `−CON-006 (the wizard consumes this plan; removes the implicit cycle)`, `+ING-008`, `+ING-106`, `+ORC-003 (fair queues)`, `+CON-101 (credit estimate)`, `+WRK-101` (COLD-tier `QUERY_TEXT_TAIL_COMMENT` projection, WRK-101-S12), `+LCH-101` (`history_days` entitlement checked at backfill admission; RECONCILIATION U-08).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-010-S01 | Write the `sync.backfill_plans` model plus API: `POST /v1/sync/backfills` (preview: per source requested/available/unavailable ranges with reasons, chunk count, estimated rows, customer credits range, duration range) and `/{id}/approve`, `/pause`, `/resume`, `/cancel` with `If-Match` and idempotency. | `apps/api/sync/backfills.py`, OpenAPI | Preview is side-effect free. Approve twice with the same key → one plan. | 5 |
| ING-010-S02 | Run source-side sizing (cheap aggregate on BRIDGE_FINOPS_WH): `SELECT DATE_TRUNC('day', END_TIME), COUNT(*) FROM QH WHERE END_TIME >= :start GROUP BY 1` and equivalents for QAH/QMH. Other sources use registry row estimates. | `services/ingestion/backfill_sizing.py` | Live: sizing for 365 d runs in one query ≤ 60 s on XS (TO VERIFY LIVE). | 4 |
| ING-010-S03 | Chunk: day chunks for QH/QAH, split to hours when estimated rows > 2 M; 7 d chunks for hourly financial sources; 31 d for daily sources. | `backfill.py::chunk` | Fixture of 1 M/day → 365 day chunks; a spike day with 5 M → 24 hour chunks. | 3 |
| ING-010-S04 | Implement ordering and tiering: source order OU billing → MDH → WMH/MH → serverless/transfer/storage → QAH → QH; within a source, expiring edge (days < retention cutoff + 7 d) first, then newest→oldest; tier-aware projection per ING-001-S04 (D-11, RECONCILIATION C-01): HOT windows ≤ `hot_days` (default 365) project sanitized QUERY_TEXT; COLD windows (only when a plan sets `hot_days` < 365) project only `QUERY_TEXT_TAIL_COMMENT`. | `backfill.py::order` | Order snapshot test. With the default `hot_days` = 365 the generated SQL for a day 200 days old projects sanitized QUERY_TEXT; with a plan fixture `hot_days` = 90 the same day lacks QUERY_TEXT and projects QUERY_TEXT_TAIL_COMMENT. | 3 |
| ING-010-S05 | Implement steady-first: on READY→SYNCING, enable steady cycles with an enrollment boundary `E = floor_hour(now) − settle`; backfill covers `[start, E)`; HEALTHY is evaluated on union coverage (no separate catch-up phase). | `backfill.py::boundaries` | Fixture: backfill finishing after 3 days leaves no gap between history and steady windows (multirange contiguous). | 4 |
| ING-010-S06 | Implement admission: backfill chunks are separate work items in the ORC-003 backfill lane; max 1 active backfill task per account and 1 per tenant (initial); per-plan customer credit cap; `history_days` entitlement enforced through LCH-101 `entitlements.check()` (U-08); pause automatically when the resource monitor is ≥ 80 % (from CON-101 status). | `backfill.py::admit` + ORC config | Flood test: tenant A with a 365-day plan, tenant B hourly steady → B's queue age p95 ≤ 10 min (ORC-003 target). | 6 |
| ING-010-S07 | Implement adaptive chunk sizing: measured seconds and bytes per chunk → halve the next chunk if > 10 min or > 2 GiB, double if < 1 min (bounded by registry min/max). | `backfill.py::adapt` | Simulated durations converge within 5 chunks. | 3 |
| ING-010-S08 | Implement the state machine DRAFT → APPROVED → RUNNING ⇄ PAUSED → COMPLETED / CANCELLED / FAILED_PARTIAL; resume reads coverage and never restarts accepted windows. | `backfill.py::state` | Resume after 40 % → remaining 60 % only (counted by windows). Cancel leaves accepted windows accepted. | 5 |
| ING-010-S09 | Re-clamp at execution: each chunk re-computes the retention clamp; newly expired days → unavailable with reason RETENTION_EXPIRED_DURING_BACKFILL. | `backfill.py::execute_chunk` | A fixture with the clock advanced 2 days mid-plan → 2 days reported unavailable, not failed. | 2 |
| ING-010-S10 | Show progress data for Data Health and onboarding: per source accepted days ÷ available days, rows loaded, bytes; ETA only after ≥ 10 completed chunks (throughput evidence). | API fields | UI fixture shows counts and dates; no ETA before 10 chunks. | 3 |
| ING-010-S11 | Write the oracle tests: 365-day request vs 90-day source → 90 available / 275 unavailable; pause/resume; tenant fairness; customer pause via connection PAUSED (epoch) stops the plan. | `tests/spec/ING-010/` | All pass. | 4 |
| ING-010-S12 | Run the performance evidence on a synthetic 1 M queries/day source (a Snowflake table with the QH schema in a Bridge-owned account, generated) plus one live AU backfill of 30 days in an INF-101 estate account. | `docs/evidence/ING-010/<commit>/` | Throughput (rows/s, sanitizer CPU-h) recorded; G-ING-10 assumptions updated. | 6 |
Task acceptance:
- [ ] The backfill preview shows available versus unavailable history, credit and duration estimates before consent.
- [ ] Finance sources complete first; expiring days are captured before they age out.
- [ ] Steady-state data flows from day one; there is no catch-up phase and no gap at the boundary.
- [ ] Steady-state tenants keep their queue-age SLO during another tenant's 365-day backfill.
- [ ] Resume never re-extracts accepted windows.

### ING-011 — Implement journal replay and anti-entropy repair
Release: R1 · Estimate: 39–57 h · Risk: M · Decisions: D-03, D-11 · Closes: G-ING-05 (replay re-PUT), G-ING-07 (additive anti-entropy), G-ING-13
Dependency changes: `−ING-010`, `+ING-007`, `+ING-008`, `+ING-006`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-011-S01 | Write the replay request model and API: `POST /v1/sync/replays` (preview: affected accepted batches, manifest availability, storage class, restore time and cost for Glacier IR/Deep Archive, downstream dbt assets); approve with reason; RBAC `sync.replay` plus audit. | `apps/api/sync/replays.py` | Preview for 7 days of WMH lists exact batch IDs and 0 missing. A foreign tenant gets 404. | 4 |
| ING-011-S02 | Implement restore handling: for non-instant storage classes, RestoreObject plus polling; the plan waits (state RESTORING); expiry of the restored copy is tracked. | `services/ingestion/replay.py::restore` | A fixture with a mocked archive class goes through RESTORING → READY. | 3 |
| ING-011-S03 | Rehydrate: GET the original → verify SHA-256 against the manifest → PUT to `replay/generation=<g>/…` with If-None-Match (no CopyObject; G-ING-05) → write a replay manifest (`pass_kind=REPLAY`, `replay_of_batch_id`, same `source_batch_id` content). | `replay.py::rehydrate` | A checksum mismatch aborts only the affected batch, with an alarm. | 5 |
| ING-011-S04 | Load via orchestrated COPY (ING-006-S10) and accept through the same A-table with `generation=g`. | `replay.py::load` | Replay twice → the second generation is accepted, and canonical totals are unchanged (staging dedup by business key and revision rules). | 4 |
| ING-011-S05 | Implement generation selection in staging: rows from generations are identical in content; EVENT_UPSERT/COMPLETE_PARTITION rules pick one deterministically; add a dbt test "replay does not change totals". | dbt test | The WMH fixture total is identical before and after 2 replays. | 3 |
| ING-011-S06 | Build the anti-entropy executor: RESNAPSHOT plans run as normal windows with `pass_kind=ANTI_ENTROPY`. CHECKSUM plans run the source aggregate query, compare with canonical per day, and enqueue re-extraction of mismatched days only (additive for EVENT_UPSERT). | `services/ingestion/anti_entropy.py` | A fixture with 3 injected missing QH rows on day D → only D is re-extracted and the 3 rows appear. Nothing is deleted. | 6 |
| ING-011-S07 | Report missing journal coverage: expired or missing files → affected intervals marked `REPLAY_UNAVAILABLE` (not failed coverage); disclose the re-extraction option (customer credits, 365-day source limit). | replay report | The oracle "missing retained file blocks only affected coverage" passes. | 3 |
| ING-011-S08 | Serialize with steady state: a replay takes a per-(connection, source) replay lease; steady cycles skip SETTLE/ANTI_ENTROPY passes for the leased windows (FIRST passes continue). | lease rules | Race test: replay and a steady pass on an overlapping window → deterministic final selection, no lost update. | 3 |
| ING-011-S09 | Assert no customer query: a replay run emits 0 Snowflake customer sessions (assert via launcher logs: no extractor task launched). | test | Asserted in the recovery suite. | 1 |
| ING-011-S10 | Run the recovery drill: delete a disposable RAW partition (staging), replay, compare canonical row counts and credit totals to baseline; run twice. | `tests/recovery/replay/` | Totals equal the baseline both times (validation-strategy fault row "Replay after Snowflake file history expiry"). | 4 |
| ING-011-S11 | Write the runbooks `docs/runbooks/replay.md` and RB-05 anti-entropy section. | runbooks | Dry run. | 2 |
| ING-011-S12 | Capture evidence. | `docs/evidence/ING-011/<commit>/` | Reviewed. | 1 |
Task acceptance:
- [ ] Replay reconstructs RAW from retained journal bytes (checksum-verified) without customer queries, and totals are unchanged after two replays.
- [ ] Anti-entropy re-extracts only mismatched days for event sources and never deletes rows there.
- [ ] Missing journal coverage is disclosed per interval, with the re-extraction alternative.
- [ ] Replay and steady state never race on the same window.

### ING-012 — Truthful Data Health model, API and UX (hot path deferred to ING-112 per D-24)
Release: R1 · Estimate: 44–64 h · Risk: M · Decisions: D-24, D-13, D-18 · Closes: G-ING-14, G-ING-17 (disclosure)
Dependency changes: `−ING-011`, `+ING-008 (coverage)`, `+CON-005 (capabilities)`, `+ING-010 (backfill state)`. UX-001 is retained.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-012-S01 | Implement the health model per §3.6 (precedence, thresholds from the registry) as a pure function over coverage, capability, connection state and last errors. | `services/ingestion/health.py` | The QH example thresholds (DELAYED at 2 h 30 min, STALE at 5 h) are asserted with an injected clock. | 4 |
| ING-012-S02 | Materialize `sync.source_health` updated per cycle and acceptance event (not per API call); history of state transitions retained 400 d. | migration + updater | State flaps are debounced (≥ 2 evaluations) and asserted. | 3 |
| ING-012-S03 | Build the API: `GET /v1/data-health?organization_id=&account_id=` (per account and source: state, reason code, source_current_through, settled_through, published_through, source latency vs pipeline lag, last error class, next action); `GET …/sources/{source}/intervals` (keyset-paginated coverage segments); `GET /v1/data-health/sync-history`; `GET /v1/data-health/batches/{batch_id}` (manifest summary, file set, acceptance evidence; scope-checked) for API-005 Explain leaves (RECONCILIATION C-27). RBAC and tenant scope; no Dagster IDs exposed to customers. | `apps/api/data_health/` | A foreign account or batch gets 404. The response contains no SQL, hostnames or Dagster run IDs (scan). | 8 |
| ING-012-S04 | Write the customer language catalog: per state and reason, a message, the affected metrics (from the semantic registry's `required_sources`) and the next action; externalized strings (D-18). | `apps/web/data_health/messages.en.json` | Every §3.6 state and §3.5 reason has text. Lint for missing keys. | 3 |
| ING-012-S05 | Build the Data Health page `/platform/data-health` per [data-health.md](../../21-ui-ux/pages/data-health.md): coverage timeline per account and source, Stage/State/Coverage/Next-action table, "Source data current through … / Last successful synchronization …" (PRD §43). | `apps/web/data_health/` | Playwright: values equal the API fixtures. Availability and maturity are shown as separate axes. | 7 |
| ING-012-S06 | Build the source-detail and sync-history subpages (intervals, batches, retries, replay entry point for authorized roles). | `apps/web/data_health/source/`, `sync_history/` | The retry story fixture (attempt 2 accepted under the same logical window) renders as specified. | 5 |
| ING-012-S07 | Implement permitted actions: re-probe (CON-005), retry a failed window (enqueue with idempotency), open replay preview (ING-011); RBAC per action; audit. | UI + API wiring | A read-only user sees no actions; the server returns 403 on forced calls. | 3 |
| ING-012-S08 | Build the single Bridge overhead panel (credits month-to-date vs estimate, computed by CON-101-S06; CON-006-S12 and UX-103 link here — RECONCILIATION U-22) and a disclosure row for "aggregated queries not itemized" when detected (G-ING-17). | UI | Fixture values match. | 2 |
| ING-012-S09 | Supply the onboarding progress data: per source accepted days ÷ available days, rows and bytes by stage (extracted, journaled, accepted, transformed, published); no invented percentages or ETA without evidence. | API fields for ONB-001 | PRD §120 example numbers render from fixtures; ETA hidden before 10 chunks. | 3 |
| ING-012-S10 | Run the UX state matrix: empty (no connection → wizard; no usage → confirmed empty intervals), loading, partial, delayed vs failing vs stale, denied, error; 390 px; keyboard; axe. | Playwright specs | All states asserted; 0 serious a11y violations. | 5 |
| ING-012-S11 | Capture evidence. | `docs/evidence/ING-012/<commit>/` | Reviewed. | 1 |
Task acceptance:
- [ ] Every account × source shows a state computed from registry-derived thresholds, with reason and next action.
- [ ] Source latency, pipeline lag and publication lag are displayed separately, with exact UTC timestamps.
- [ ] Unknown is never shown as zero; confirmed empty intervals are distinguished from missing coverage.
- [ ] No Dagster internals are exposed; actions are RBAC-checked and audited.

## 5. New tasks required

### ING-101 — Activate query-family source contracts (QH, QAH, QMH)
Release: R1 (incl. QMH, D-20) · Estimate: 32–46 h · Risk: H · Decisions: D-10, D-11, D-15, D-20 · Closes: G-ING-01 (live proof)
Why: the catalog rows are docs-derived; the activation gate (V03) has no owner. The projection union requested by INS/ALC/WRK must be frozen here, before the first 365-day backfill, because fields not extracted then are lost for history (RECONCILIATION C-10). Plugs in after ING-001, CON-005 and INF-101; blocks ING-106 activation of these sources.
Dependency changes: `+ING-001`, `+CON-005`, `+CON-002`, `+INF-101` (test estate; replaces the requested `+OPS-103`, RECONCILIATION U-03), `+WRK-101` (COLD-tier tail-comment projection handoff WRK-101-S09; C-10), `+ING-107` (S07 validates the live privacy path; U-04).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-101-S01 | Author the QH contract per the §3.1 row (projection, privacy actions, END_TIME_SWEEP, pass schedule, anti-entropy CHECKSUM) with the frozen projection union (RECONCILIATION C-10): catalog projection + the 16 INS columns (G-INS-01: hash versions, spill, partitions, compilation/queue times, cluster, warehouse type, CREDITS_USED_CLOUD_SERVICES, rows, error code) + DATABASE_ID/NAME, SCHEMA_ID/NAME + the COLD-tier `QUERY_TEXT_TAIL_COMMENT` (C-01; fallback for plans with `hot_days` < 365). | `data/contracts/sources/au_query_history.v1.json` | `validate-registry` passes; a CI check lists every INS/ALC/WRK-requested QH field as projected. | 4 |
| ING-101-S02 | Author the QAH (+ PARENT_QUERY_ID, ROOT_QUERY_ID) and QMH contracts and the new AU.SESSIONS contract (SESSION_ID, CREATED_ON, pseudonymized USER_NAME, CLIENT_APPLICATION_ID/VERSION, CLIENT_ENVIRONMENT:APPLICATION) (RECONCILIATION C-10). | `au_query_attribution_history.v1.json`, `au_query_metering_history.v1.json`, `au_sessions.v1.json` | Validate. The QMH key includes the hour. USER_NAME in SESSIONS has privacy action `HMAC_USER`. | 5 |
| ING-101-S03 | Run the long-query probe in an INF-101 estate account: `SELECT COUNT(*) FROM TABLE(GENERATOR(TIMELIMIT => 5400))` on BRIDGE_FINOPS_WH; poll AU.QH/QAH every 15 min; record visibility while running, appearance latency after completion, and START/END values. | evidence | The question "Does AU.QH expose running queries?" is answered with query IDs; registry notes are updated. | 3 |
| ING-101-S04 | Capture the live DESCRIBE plus type/scale/nullability of the projections (incl. AU.SESSIONS) in Standard and Enterprise accounts; record the fingerprint; measure the customer warehouse seconds and result bytes per backfill day of projecting QUERY_TEXT for sanitization (HOT tier, all 365 days by default — D-11) and of the COLD-tier tail-comment regex (fallback), and hand both to CON-101's disclosed estimate (RECONCILIATION C-01, D-08). | verification records | Records attached; mismatches vs catalog resolved in contract; text-projection and regex cost per backfill day recorded. | 4 |
| ING-101-S05 | Check key uniqueness: `SELECT QUERY_ID, COUNT(*) FROM AU.QH WHERE END_TIME >= DATEADD(day,-7,CURRENT_TIMESTAMP()) GROUP BY 1 HAVING COUNT(*) > 1` (and the QAH/QMH equivalents with their keys). | evidence | 0 rows, or an explicit dedup rule documented. | 2 |
| ING-101-S06 | Measure latency and retention: the canary (CON-005-S05) for QH; `MIN(END_TIME)` for retention; QAH lag distribution over 48 h. | evidence | Settle defaults are confirmed or adjusted (settle ≥ p99 observed lag × 1.5). | 3 |
| ING-101-S07 | Validate the privacy path on live data: sanitizer, HMAC and tier-aware projection on 1 day of QH (ING-107). | evidence | A sentinel secret in a test query's literal is absent from Parquet. | 3 |
| ING-101-S08 | Run one WIF extraction plus replay fixture per source; complete the source-catalog test matrix rows (empty window, missing grant, missing optional column, decimal edge, duplicate attempt, late data beyond settle via anti-entropy, retention clamp). | `tests/live/sources/query_family/` | Matrix passes; activation state → VERIFIED. | 7 |
| ING-101-S09 | Activate in production (config) with review sign-off. | registry state change | State ACTIVE with evidence links. | 1 |
Task acceptance:
- [ ] QH, QAH, QMH (D-20; live-verified on an estate account with an Adaptive warehouse) and AU.SESSIONS contracts are live-verified with types, keys, latency and retention; the QH/QAH projection union of RECONCILIATION C-10 is frozen before the first backfill.
- [ ] Long-query behaviour is measured and the END_TIME sweep captures a 90-minute query exactly once.
- [ ] The privacy path is proven on live data.

### ING-102 — Activate metering and billing source contracts (WMH, MH, MDH, OU currency, OU rate sheet)
Release: R1 · Estimate: 29–42 h · Risk: H · Decisions: D-12, D-13 · Closes: G-ING-07 (suspect guard parameters)
Dependency changes: `+ING-001`, `+CON-005`, `+CON-002`, `+INF-101` (test estate; replaces the requested `+OPS-103`, RECONCILIATION U-03). ING-102 owns the per-source DESCRIBE/latency/retention facts (incl. S06 source latency); FIN-108 keeps billing-semantics verification and depends on this task (FIN-108 +ING-102; U-03).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-102-S01 | Author the WMH and MH contracts (HOUR_PARTITION, COMPLETE_PARTITION, primary measure, RESNAPSHOT). | contract files | Validate. | 3 |
| ING-102-S02 | Author the MDH contract (DATE_PARTITION; signed adjustment; open-month anti-entropy). | contract | Validate. | 2 |
| ING-102-S03 | Author the OU.USAGE_IN_CURRENCY_DAILY and OU.RATE_SHEET_DAILY contracts (ORG scope; 13-month monthly sweep). | contracts | Validate. | 3 |
| ING-102-S04 | Run live DESCRIBE and type checks in account plus org accounts; record the NUMBER scales of the credit and currency columns. | verification records | Recorded. The transport schema uses the exact scales. | 3 |
| ING-102-S05 | Verify partition completeness: for 7 days compare per-hour row sets of two extractions 24 h apart and measure the fraction of changed hours (WMH cloud services revision); confirms the settle and suspect-guard thresholds. | evidence | Changed-hour fraction and max measure delta recorded. The 50 % suspect threshold is confirmed or tuned. | 5 |
| ING-102-S06 | Check latency and retention per source (max(START_TIME) lag, MIN(date)); record the OU latency (≤ 72 h documented). | evidence | Registry values updated. | 3 |
| ING-102-S07 | Validate the reseller/denied path: an org account without billing access → DENIED_OR_UNAVAILABLE plus FIN imported-statement path flag. | test | Fixture passes. | 2 |
| ING-102-S08 | Run the source-catalog test matrix including "complete partition with deleted old row" (synthetic view) and "independent billing comparison" (MDH CREDITS_BILLED vs OU USAGE for one day, FIN-owned oracle). | `tests/live/sources/metering_family/` | Matrix passes; activation → VERIFIED. | 7 |
| ING-102-S09 | Activate in production. | registry | ACTIVE. | 1 |
Task acceptance:
- [ ] Hourly and daily metering partitions are complete snapshots with measured revision behaviour.
- [ ] Org billing sources work in organization-account and ORGADMIN modes, or are explicitly unavailable (reseller).
- [ ] Credit and currency scales are exact in transport.

### ING-103 — Activate storage, object and inventory contracts (STORAGE_USAGE, DATABASE_STORAGE_USAGE_HISTORY, DATABASES, TABLE_STORAGE_METRICS opt-in, OU.ACCOUNTS)
Release: R1 (TABLE_STORAGE_METRICS opt-in per CON Q3) · Estimate: 24–35 h · Risk: M · Decisions: D-15 · Closes: G-CON-02 (TSM mapping), G-ING-07 (snapshot guard)
Dependency changes: `+ING-001`, `+CON-005`, `+INF-101` (test estate; replaces the requested `+OPS-103`, RECONCILIATION U-03). Adds AU.TAG_REFERENCES for ALC-001 (C-10); OU.ACCOUNTS is authored by CON-004-S03 and only activated here (U-23).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-103-S01 | Author the STORAGE_USAGE and DATABASE_STORAGE_USAGE_HISTORY contracts and the AU.TAG_REFERENCES daily snapshot contract (Enterprise-gated; required by ALC-001, G-ALC-11; RECONCILIATION C-10). | contracts | Validate. | 5 |
| ING-103-S02 | Author the AU.DATABASES snapshot contract (owner, deleted); activate CON-004-S03's OU.ACCOUNTS contract for the org cycle (authored there; RECONCILIATION U-23). | contracts | Validate. | 1 |
| ING-103-S03 | Verify TABLE_STORAGE_METRICS access: test with USAGE_VIEWER, OBJECT_VIEWER and GOVERNANCE_VIEWER separately, then IMPORTED PRIVILEGES; record which returns rows. | evidence + privilege map update | The mapping is decided; if IMPORTED PRIVILEGES is needed, the module is opt-in with disclosure. | 4 |
| ING-103-S04 | Author the TSM snapshot contract with the strict suspect guard (0 rows vs previous > 0). | contract | Validate. | 2 |
| ING-103-S05 | Run live DESCRIBE, type and latency checks (incl. AU.TAG_REFERENCES on Enterprise; NOT_SUPPORTED on Standard); key uniqueness per snapshot (`ID` per capture). | evidence | Recorded. | 4 |
| ING-103-S06 | Test "pre-enrollment history unavailable" for snapshot sources (catalog matrix row). | test | Data Health shows unavailable before enrollment. | 2 |
| ING-103-S07 | Run the test matrix and activate. | `tests/live/sources/storage_family/` | VERIFIED → ACTIVE. | 6 |
Task acceptance:
- [ ] Storage and owner inventories are live-verified; TSM access is decided with explicit privilege disclosure.
- [ ] Snapshot sources never infer pre-enrollment history, and empty snapshots cannot wipe prior data.

### ING-104 — Activate serverless and transfer contracts (AUTOMATIC_CLUSTERING, SERVERLESS_TASK, PIPE_USAGE, DATA_TRANSFER)
Release: R1 · Estimate: 30–45 h · Risk: M · Decisions: D-15 · Closes: G-ING-02 (FLOAT/VARCHAR exceptions)
Dependency changes: `+ING-001`, `+CON-005`, `+INF-101` (test estate; replaces the requested `+OPS-103`, RECONCILIATION U-03). TASK_HISTORY and DYNAMIC_TABLE_REFRESH_HISTORY are pulled from R2 ING-105 into this task for R1 WRK-004 (RECONCILIATION C-10).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-104-S01 | Author the four contracts (HOUR/DATE partitions, COMPLETE_PARTITION) plus AU.TASK_HISTORY and AU.DYNAMIC_TABLE_REFRESH_HISTORY (END_TIME_SWEEP; moved from ING-105, RECONCILIATION C-10). | contracts | Validate. | 6 |
| ING-104-S02 | Record the documented non-NUMBER types (SERVERLESS_TASK CREDITS_USED VARCHAR; PIPE_USAGE FLOAT/VARIANT; DATA_TRANSFER VARIANT bytes) as explicit transport exceptions with dbt parse rules owned by FIN. | registry exceptions list | The ING-003-S04 float guard passes with explicit exceptions only. | 2 |
| ING-104-S03 | Run live DESCRIBE, type and latency checks (all six sources); interval-boundary behaviour (START/END not aligned to hours → bucketing by START_TIME hour documented). | evidence | Recorded. | 8 |
| ING-104-S04 | Generate activity in the INF-101 estate (a clustering-enabled table, a serverless task, a pipe, a task graph run, a dynamic-table refresh) so that the sources are non-empty; verify rows appear. | fixture workload | Rows observed for each source. | 5 |
| ING-104-S05 | Run the test matrix and activate (six sources). | `tests/live/sources/serverless_family/` | VERIFIED → ACTIVE. | 9 |
Task acceptance:
- [ ] All six sources (incl. TASK_HISTORY and DYNAMIC_TABLE_REFRESH_HISTORY for WRK-004) are live-verified with explicit non-NUMBER exceptions and documented interval bucketing.

### ING-105 — Activate extension source families (R1 part per D-20, R2 remainder)
Release: R1 (S01, S03, S04: sources of the R1 service-detail tasks, D-20 2026-09-28) · R2 (S02, S05) · Estimate: 70–125 h (R1 part 49–88 h; R2 part 21–37 h) · Risk: M · Decisions: D-01, D-20 · Closes: G-ING-17
Why: ACCESS_HISTORY (long-tail companion), WAREHOUSE_EVENTS/LOAD, MV/SOS/QAS, replication, SPCS, Cortex (AISQL cut-over), Snowpipe Streaming, marketplace, AGGREGATE_QUERY_HISTORY and OU.STORAGE_DAILY_HISTORY each need the same activation evidence. D-20 (2026-09-28) puts every service family in R1, so the families behind R1 FIN tasks — MV (FIN-016), SOS (FIN-015), QAS (FIN-017), replication (FIN-008), SPCS (FIN-019), Cortex (FIN-018), Snowpipe Streaming (FIN-012), marketplace (FIN-020) and OU.STORAGE_DAILY_HISTORY (FIN-006 estimate) — are activated in R1 (S01, S03, S04); this also closes the earlier gap where R1 FIN-006/015/016 read sources activated only in R2. The R2 remainder (S02, S05) serves R2 consumers only: ACCESS_HISTORY (INS-104, ALC table-access attribute), WAREHOUSE_EVENTS/LOAD (INS-106) and AGGREGATE_QUERY_HISTORY. TASK/DT history moved to R1 ING-104 (RECONCILIATION C-10).
Dependency changes: `+ING-101…104` (pattern), `+ING-106`. FIN-006, FIN-008, FIN-012 and FIN-015…FIN-020 need the R1 part before their live evidence (edge proposal for the task graph).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-105-S01 | (R1) Inventory the current Account Usage / Org Usage catalog vs the registry (script over `SHOW VIEWS IN SCHEMA SNOWFLAKE.ACCOUNT_USAGE` in the INF-101 estate); produce the gap list. | inventory report | Gap list reviewed. | 4 |
| ING-105-S02 | (R2) Implement the ACCESS_HISTORY long-tail companion predicate using QH long-query IDs. | contract + adapter override | A 3-hour query's access row is captured exactly once. | 10 |
| ING-105-S03 | (R1, D-20) Author contracts plus live verification for the 7 R1 families: MV, SOS and QAS, replication, SPCS, Cortex, Snowpipe Streaming, marketplace, OU.STORAGE_DAILY_HISTORY (≈ 6–10 h each, budgeted at the low end as before; TASK_HISTORY/DT refresh moved to ING-104 per RECONCILIATION C-10); the INF-101 workload generator creates activity for each family it can. | contracts + evidence | Each R1 family VERIFIED, or NOT_RUN with a recorded reason where the estate cannot generate activity (e.g. marketplace purchases). | 39 |
| ING-105-S04 | (R1) Resolve the Cortex old/new view authority rule (effective-dated) with FIN-018. | contract notes | No UNION ALL of amounts. | 6 |
| ING-105-S05 | (R2) Author contracts plus live verification for WAREHOUSE_EVENTS/LOAD_HISTORY (INS-106) and AGGREGATE_QUERY_HISTORY. | contracts + evidence | Each family VERIFIED. | 11 |
Task acceptance:
- [ ] Each activated family has live verification evidence equivalent to R1 sources.
- [ ] Every source family consumed by an R1 FIN task is ACTIVE before that task's live evidence (D-20).

### ING-106 — Account-cycle runner and extractor ↔ control-plane trust path (D-07)
Release: R1 · Estimate: 37–54 h · Risk: H · Decisions: D-07, D-08 · Closes: G-ING-08, G-ING-09
Why: nothing composes due windows into one warehouse resume per account, and connection-role tasks have no safe path to leases and attempts. ING-106 owns the dedicated extraction launcher, the in-task executor and the sync-api; the cycle table, planner, admission and schedule formula are ORC-003's (RECONCILIATION U-12, C-03, C-04). Plugs in after ING-003, ING-005, CON-101 and ORC-003; ING-007, ING-010 and INS-102 depend on it.
Dependency changes: `+ING-002`, `+ING-003`, `+ING-005`, `+ING-107`, `+CON-001`, `+CON-101`, `+INF-005`, `+ORC-003` (cycle table and admission contract first; the launcher consumes ADMITTED cycles). The requested reverse edge `ORC-003 +ING-106` is rejected (RECONCILIATION U-12, C-25).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-106-S01 | Moved to ORC-003-S01 per RECONCILIATION U-12 (single cycle table `sync.account_cycles`, extended with `kind`, `due_windows`, `connection_epoch`, `fencing_token`, `deadline_at` and the "one active STEADY per connection" index) — consume it here | — | — | 0 |
| ING-106-S02 | Build the internal `sync-api` authenticated by a presigned `sts:GetCallerIdentity` (header carries the signed request; the server calls STS with a 5 s timeout and caches 5 min by signature hash), mapping `assumed-role/bridge-<env>-conn-<uuid32>/*` to a connection (RECONCILIATION C-11); authorize only that connection's cycle, attempts and manifests. Private ALB; no public route. | `services/sync_api/auth.py`, routes | Attack tests: a task with role A calling for B's cycle → 403; a replayed signature after 15 min → 401; the API role (not a connector role) → 403. | 7 |
| ING-106-S03 | Build the dedicated extraction launcher service (D-07; RECONCILIATION C-04, U-12): claim ADMITTED cycles from ORC-003's `sync.account_cycles`; resolve `connection_id → role` from PostgreSQL (absorbs CON-001-S06's `services/launcher/resolve.py` and its negative test); call `RunTask` (extractor family, `taskRoleArn` override, env `CYCLE_ID` only, `clientToken` = cycle idempotency key); an ECS task-state event completes the cycle; ORC-002-S03's sensor turns sync outcomes into asset observations. No Dagster run per account-cycle; only the launcher task role holds `iam:PassRole` on connection roles (INF-005-S08). | `services/launcher/` (`claim.py`, `resolve.py`), ECS state-change event rule | A request carrying `role_arn` → 400 `CON_FIELD_NOT_ALLOWED`; the API or Dagster role calling PassRole → AccessDenied; no Dagster run exists per cycle; the extractor container has no Dagster/PG environment variables (inspection test). | 7 |
| ING-106-S04 | Build the cycle executor: claim (fencing token) → one WIF session → sources in finance-first order → for each due window: ING-003 → ING-107 → ING-004 → ING-005 → register via sync-api; per-source try/classify/continue. | `services/extractor/cycle.py` | Fixture: source 3 of 7 DENIED → 6 sources accepted, 1 reason recorded. | 6 |
| ING-106-S05 | Check fences: before each source and before each manifest registration, check the epoch and lease via sync-api; a mismatch exits after closing the current file set without a manifest. | cycle | Pause mid-cycle → no manifest after the next check (CON-006-S09 test). | 3 |
| ING-106-S06 | Enforce budgets: STEADY deadline 45 min; BACKFILL_CHUNK 2 h; remaining due windows stay due; metric `cycle_overrun_total`. | cycle | A synthetic slow source triggers the deadline → the cycle ends cleanly; the next cycle picks up the remainder. | 2 |
| ING-106-S07 | Suspend the warehouse and clean up: CON-101-S03 suspend-after-cycle; close the session; flush metrics. | cycle | Live: WMH billed ≤ 70 s per steady cycle. | 2 |
| ING-106-S08 | Moved to ORC-003-S02 per RECONCILIATION U-12, C-03 (cycle minute = `5 + (hash(connection_id) mod 50)`, daily 03:00 UTC-hour and ORG 06:10 UTC cycles, implemented once in the planner) — consume it here | — | — | 0 |
| ING-106-S09 | Size resources (initial, benchmark-gated): STEADY 1 vCPU / 4 GB / 21 GiB ephemeral; BACKFILL 4 vCPU / 16 GB / 60 GiB; record in the task definitions. | task definitions | OPS-105 benchmark referenced. | 2 |
| ING-106-S10 | Run the failure tests: duplicate cycle launch → the second exits NOOP; task killed → lease expiry → the next cycle resumes from coverage; epoch change mid-cycle; sync-api unavailable → the task exits without manifests (retry next cycle). | `tests/recovery/cycle/` | All pass; coverage unchanged by failed cycles. | 4 |
| ING-106-S11 | Add observability: `cycle_duration_seconds`, `cycle_sources_total{outcome}`, `cycle_overrun_total`, `cycle_skipped_total{reason}`, `sync_api_auth_fail_total`; per-cycle outcome record (no SQL). | metrics + schema | Dashboard. | 2 |
| ING-106-S12 | Capture live evidence: 48 hourly cycles × 2 INF-101 estate accounts plus 1 org cycle. | `docs/evidence/ING-106/<commit>/` | Success rate and billed seconds recorded. | 2 |
Task acceptance:
- [ ] One warehouse resume per account-cycle; per-source failures are isolated.
- [ ] Extractor tasks hold no PG or Dagster credentials; the sync-api authorizes by STS caller identity only for the matching connection.
- [ ] Cycles respect epoch, fences and deadlines; duplicate or killed cycles do not change coverage.

### ING-107 — Privacy transforms in the extraction path with a throughput budget
Release: R1 · Estimate: 22–33 h · Risk: H · Decisions: D-10, D-11 · Closes: G-ING-10 (sanitizer throughput), G-CON-11 (overhead flag ordering)
Why: ADR-009 requires sanitize-before-transport, and D-10 requires pseudonymization at extraction. The extraction-side integration, ordering and throughput have no owner; the WRK-101, SEC-007 and SEC-103 libraries provide the primitives (ING-107 owns operation order, in-process key handling, throughput budget and failure semantics — RECONCILIATION U-04).
Dependency changes: `+SEC-007`, `+SEC-103 (pseudonym scheme, G-SEC-16)`, `+ING-001`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-107-S01 | Implement the registry privacy actions `KEEP`, `SANITIZE_SQL`, `SANITIZE_TAG`, `HMAC_USER` (SEC-103 scheme), `DROP` and `TIER_WINDOW` (D-11), and the per-batch hook API. | `services/extractor/privacy_hook.py` | Every R1 projected field has exactly one action (lint). | 3 |
| ING-107-S02 | Order the operations: (1) compute `is_bridge_overhead` on plaintext; (2) extract allowlisted comment and tag metadata (WRK-101 library, step (1) of SEC-007 `sanitize()`; U-04); (3) sanitize the SQL body; (4) HMAC user names; (5) drop plaintext columns. Plaintext never leaves process memory. | hook | The sentinel test covers USER_NAME, QUERY_TEXT literal and QUERY_TAG secret; all are absent from Parquet and logs. | 4 |
| ING-107-S03 | Manage the per-tenant HMAC key (in-extractor part of SEC-103-S04; RECONCILIATION U-04): decrypt once per task via KMS with encryption context `tenant_id`; hold in memory only; never logged; wrong-context decrypt → hard fail. | key loader | A test with a mismatched tenant context fails closed. | 3 |
| ING-107-S04 | Use SEC-007-S08's sanitized-body cache (single cache, RECONCILIATION U-04) and size the sanitizer process pool to vCPUs − 1. | hook | Cache correctness: two queries differing only in comments keep their own allowlisted metadata. | 2 |
| ING-107-S05 | Run the throughput benchmark on a 1M-row synthetic corpus with realistic repetition; record rows/s per vCPU and cache hit rate (in-process and with SEC-007-S17's persisted cache); size the backfill task for 365 days of sanitized text (D-11: ≈ 365 M statements for a 1 M/day account). | evidence | Result feeds ING-010 estimates (G-ING-10) and CON-101. | 4 |
| ING-107-S06 | Handle failures: sanitizer error → text null + `privacy_mode_effective=METADATA_ONLY` for that row; no exception message with SQL; metric `sanitizer_failures_total`. | hook | A malformed SQL fixture gives a null text and a flag, with no log line containing the input. | 2 |
| ING-107-S07 | Record the privacy policy version in the manifest and the technical column; replay uses the original version (ING-011). | manifest field | Replay with a newer sanitizer does not re-sanitize journaled text (asserted). | 2 |
| ING-107-S08 | Capture evidence. | `docs/evidence/ING-107/<commit>/` | Reviewed. | 2 |
Task acceptance:
- [ ] No plaintext user name, SQL literal or secret tag reaches Parquet, logs, quarantine or evidence.
- [ ] Bridge-overhead classification happens before pseudonymization.
- [ ] Sanitizer throughput is measured and sized for backfill.

### ING-112 — Bounded INFORMATION_SCHEMA hot path (R2, moved out of ING-012 per D-24)
Release: R2 · Estimate: 40–60 h · Risk: M · Decisions: D-24 · Closes: G-ING-14 (R2 part)
Dependency changes: `+ING-012`, `+ING-008`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ING-112-S01 | Verify privileges and limits live: `QUERY_HISTORY_BY_WAREHOUSE` / `QUERY_HISTORY` table functions, RESULT_LIMIT 10,000, 7-day range, required MONITOR-type privileges; privilege disclosure text. | evidence | Documented. | 6 |
| ING-112-S02 | Build the HOT adapter: bisect time ranges until < 10,000 rows; irreducible saturation → an INCOMPLETE flag on that interval. | adapter | A saturated fixture shows incomplete coverage. | 10 |
| ING-112-S03 | Enforce authority precedence (AU = 2 > HOT = 1) in revision selection; HOT rows expire after AU settles. | dbt macro | "Hot + authoritative copy of Q1 counts once" oracle. | 8 |
| ING-112-S04 | Show UI labels for PROVISIONAL-hot, and keep cost unknown for hot rows. | UI | Fixture assertion. | 8 |
| ING-112-S05 | Measure the cost of hot polling and add it to the CON-101 estimate. | evidence | Estimate updated. | 8 |
Task acceptance:
- [ ] Hot rows never override settled Account Usage rows, and saturated windows are disclosed as incomplete.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| ING-001 | R1 | 28 | 40 |
| ING-002 | R1 | 36 | 52 |
| ING-003 | R1 | 38 | 55 |
| ING-004 | R1 | 24 | 36 |
| ING-005 | R1 | 36 | 52 |
| ING-006 | R1 | 37 | 54 |
| ING-007 | R1 | 44 | 64 |
| ING-008 | R1 | 32 | 46 |
| ING-009 | R1 | 28 | 40 |
| ING-010 | R1 | 48 | 70 |
| ING-011 | R1 | 39 | 57 |
| ING-012 | R1 | 44 | 64 |
| ING-101 | R1 | 32 | 46 |
| ING-102 | R1 | 29 | 42 |
| ING-103 | R1 | 24 | 35 |
| ING-104 | R1 | 30 | 45 |
| ING-106 | R1 | 37 | 54 |
| ING-107 | R1 | 22 | 33 |
| ING-105 R1 part (S01, S03, S04; D-20) | R1 | 49 | 88 |
| ING-105 R2 part (S02, S05) | R2 | 21 | 37 |
| ING-112 | R2 | 40 | 60 |
| **Total R1** | | **657** | **973** |
| **Total R2** | | **61** | **97** |

## 7. Owner questions

1. **Q1 — Customer fallback for lost data.** When a financial partition cannot be recovered from the journal (for example, a bug found after journal expiry), may Bridge re-extract from the customer's account automatically within the 365-day source retention? That costs customer credits (≈ 0.02–0.1 credit per re-extracted day of metering). Or is explicit customer approval required each time?
2. **Q2 — Journal retention for financial sources.** Approve 400-day journal retention for FINANCIAL retention-class sources (G-ING-13; ≈ < 1 MB/account/day, Glacier IR after 30 days). This challenges the ADR-009 90-day default for those sources only. — Resolved by D-26 (400 d for FINANCIAL, 90 d for QUERY_GRAIN; RECONCILIATION C-02).
3. **Q3 — Unrecoverable history in backfills.** Should backfills proceed automatically when a source's oldest days are about to expire, before the customer approves the plan (the "expiring edge" is lost daily)? Or must extraction always wait for consent?
4. **Q4 — Freshness tier.** Is a customer-selectable "fresher" tier (15-min QH cadence, ≈ +36 credits/month customer cost) a product offering in R1, or hourly only?

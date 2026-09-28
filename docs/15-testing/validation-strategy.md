# Validation strategy and independent oracles

This file owns cross-domain proof requirements. Task files add exact feature-specific inputs, failures and acceptance. All tests described here are future implementation requirements; only documentation checks are executed during specification authoring. FND-004 builds fixtures and FND-005 builds the dispatcher.

## Test layers and gates

| Level | Scope and required examples | Execution / evidence |
|---|---|---|
| Unit | UTC windows, Decimal rates, largest remainder, dedup keys, permissions predicates, sanitizer, monitor fingerprints, statistical eligibility | Every change; fixed fixtures and property tests where useful |
| Contract | Source projections/types/grain; Arrow/Parquet round trip; JSON APIs/config; response metadata; backward-compatible metric versions | PR gate; schema diff and positive/negative payloads |
| dbt | Unique scoped natural keys, relationships, not-null rules with documented exceptions, service inclusion, financial conservation, incremental/full parity | Isolated CI schema with synthetic sources and pinned dbt adapter |
| Integration | PostgreSQL FORCE RLS/transaction pooling; outbox/leases; Redis outage; API/worker interactions; report renderer | Local containers plus staging actual services |
| Snowflake live | WIF positive/negative/revocation, grants and real view columns/types, UTC behavior, Snowpipe receipts, row policy attacks, dbt publication | Dedicated synthetic accounts; exact connector/adapter/version evidence. (amended 2026-09-28, U-03, D-32) One non-production estate owned by INF-101 (test organizations T-A and T-B, continuous deterministic workload, canaries) whose organization account is **tenant zero**; live oracles are parity checks (direct view query = Bridge journal/RAW for windows older than the maturity horizon) plus tenant zero's real usage statement (FIN-108), because live credits are not deterministic; budget ≤ 150 credits/month |
| AWS integration | IAM trust/prefix/KMS denial, ECS task/execution roles, S3 notifications, queue duplicate/reorder, private networking and OIDC subjects | Staging only; actual AWS IDs kept in approved private evidence |
| Security / isolation | Every foreign identifier, stale epoch, BOLA, missing query filter, SSRF, CSV formula, session/CSRF and report revocation | Mandatory before M1/M5/M9 promotion as interfaces become available |
| Performance | Streaming RSS, small-file skew, hot partitions, query deadlines, cancellation, pool budgets, noisy tenant and report saturation | Published executed scale/cost; p50/p95/p99 and error distributions |
| Failure / recovery | Crash at each commit boundary; retries/duplicates/late data/schema drift/replay; PG/Snowflake restore and deletion tombstones | Controlled fault injection with exact before/after checksums/totals |
| E2E / UX | Signup→WIF→history→reconciliation→Explorer→allocation→budget→monitor→report→action; all personas and UI states | Playwright plus visual/accessibility review; screenshots supplement assertions |
| Financial | Independent golden operands and expected amounts; source/reference comparison; signed adjustments/currencies/restatements | Decimal exactness, reconciliation evidence and FinOps review |

A failing live permission test cannot be replaced with a mock. Unit test expected values must be independently calculated, not obtained by calling the same implementation under test. No task is DONE because it compiles. `NOT_APPLICABLE` requires a reason identifying why that layer cannot exercise the task.

## Golden financial fixture F-270

All amounts are synthetic USD. The2 USD/credit rate is fixture-only. Values come from declared authoritative charge inputs; detailed query/service records are attribution evidence where indicated.

| Additive component | Expected amount |
|---|---:|
| Warehouse100 credits | 200.00 |
| Cloud services15 gross credits minus10-credit adjustment | 10.00 |
| Storage | 12.00 |
| Serverless: pipe5 + task7 + clustering2 + search2 + MV2 | 18.00 |
| Cortex | 6.00 |
| SPCS | 8.00 |
| Transfer | 4.00 |
| Marketplace/application fee | 10.00 |
| Organization support fee | 5.00 |
| Organization rebate | -3.00 |
| **Total** | **270.00** |

Warehouse decomposition is query70 credits→140 and idle30→60, still200. Organization fee net2 has nullable account; account components total268. EUR20 remains separate. Correction storage12→11 produces269 once; duplicate correction/replay remains269. Ledger270 versus independent invoice271 gives delta−1 and FAILED under zero-tolerance fixture. No balancing entry is allowed. Charge/service authority mappings must preserve these outputs even when billing reference rows and query detail are both loaded.

Other independent oracles:

- Adaptive query Q1: hour rows0.25 +0.75=1.00 credit; correction first row0.30 gives1.05, not1.30 or1.80.
- Serverless QAS3 service total with2 query-attributed detail leaves1 unattributed; total is3. A parent AI charge10 with4 child detail remains10.
- Allocation book A: query140 split84/56; distribute idle60 proportionally→Finance120/Marketing80. Book B:84/56/Platform60. Each conserves200; never add books to400.
- Monetary rounding:1.00 split thirds gives0.34/0.33/0.33 by stable recipient ID tie-break;−1.00 mirrors signs. Sum is exact in currency minor units. (amended 2026-09-28, G-ALC-05) Mixed signs use the sign-normalized signed largest remainder: lines +1.005, −0.335, −0.335 (exact +0.335) round to a total of 0.34 and lines that sum to 0.34 (the withdrawn absolute-value method gave 0.32).
- (added 2026-09-28, G-FIN-01, D-12) Supersession F-SUP-01: estimate 100 credits × 2.00 = 200.00, then billed capacity 80 credits = 160.00 and overage 20 credits × 2.50 = 50.00 → active total 210.00, never 410.00; estimate accuracy Δ = −10.00.
- (added 2026-09-28, D-14) Temporal attribution: a query from 23:30 to 01:30 with 2.0 credits contributes 0.5 / 1.0 / 0.5 to the three metering hours, so day 1 = 0.5 and day 2 = 1.5; `PRORATION_RESIDUAL` per hour = warehouse attributed credits − Σ prorated query credits.
- (added 2026-09-28, G-ING-01) Long-running extraction: a query running 01:00–07:00 and a 20-hour query each appear exactly once in the END_TIME sweep window of their completion, whatever the extraction cadence.
- (added 2026-09-28, G-API-04) Percentiles: day A 100 queries at 1 s, day B 5 queries at 100 s → true p95 = 1 s, never the 50.5 s average of daily p95s.
- Budget280,15 complete days at10/day: actual150, remaining130, burn10/day, 30-day run-rate forecast300, forecast variance20 and7.142857…%. Forecast is estimated even if actual is RECONCILED.
- Robust anomaly: baseline median100, MAD10, current160 gives z=60/(1.4826×10)≈4.04694456 and absolute impact60. Missing day is unavailable; zero MAD uses documented fallback.
- (added 2026-09-28, X-30, G-GOV-01) Monitor confirmation over distinct windows: static daily monitor over100 — D1 = 101 (counter 1), D2 = 102 (incident opens), D3 = 103 (attaches, occurrence 3), D4 INSUFFICIENT_DATA (holds), D5 = 99, D6 = 98 (RESOLVED); 23 further hourly ticks over D2 with the same publication create 0 observations; 100 retries of the D2 evaluation create 1 observation, 1 incident, 1 notification. The earlier "101/102 then hourly 103" fixture is withdrawn.
- (added 2026-09-28, G-RPT-01) Scheduling: a daily 02:30 America/New_York report on 2026-03-08 runs at 07:30Z (shift forward, RFC 5545); 01:30 on 2026-11-01 runs once at 05:30Z (first occurrence).
- Workload comparison:10×2=20 versus20×3=60 gives delta40; baseline-price volume effect20 plus current-volume price effect20. Two concurrent10-second queries give invocation wall time10s and execution sum20s.
- Savings: baseline200/100 units=2 per unit; observed120 units at180 costs→counterfactual240 and saving60. Observed260→saving−20. Two overlapping actions cannot claim120; estimated80 stays distinct.
- Bridge economics: revenue1000 and COGS100+120+80=300→70% gross margin; zero revenue→null percentage.

## Synchronization fault matrix

| Fault injection | Expected durable state and proof |
|---|---|
| Crash after first Parquet file, before manifest | No accepted batch; no RAW publication or coverage advance; orphan attempt safely quarantined |
| Snowpipe event arrives before manifest | Rows may land RAW, but cannot enter dbt accepted input until complete manifest receipts validated |
| Duplicate/reordered S3 or queue events | One logical file receipt and accepted business revision; no duplicate charge |
| Crash after manifest commit, before PG checkpoint | Reconciler finds committed manifest; retry adopts/replays idempotently; contiguous journal coverage repaired |
| Missing second file of three | Batch remains incomplete; no published watermark jump; missing-file alarm names batch |
| Empty source window | Explicit zero-row manifest with window/capability evidence; may advance confirmed empty coverage |
| Late event or corrected hourly aggregate | Overlap fetch replaces correct business revision; impacted partition rebuilt; stable total on replay (amended 2026-09-28: SETTLE pass or anti-entropy supplies the correction; event-source anti-entropy is additive) |
| (added 2026-09-28) Silently empty or truncated read of a complete billing partition | Accepted as SUSPECT; the previous revision stays selected until a confirming batch ≥ 6 h later with a fresh AVAILABLE probe; alarm at 24 h |
| (added 2026-09-28) Retry overwrites an accepted key | `If-None-Match: *` returns 412; equal checksum = idempotent success, different = `KEY_CONFLICT` and a new attempt |
| (added 2026-09-28) File loaded twice (pipe plus repair COPY) | Flagged DUPLICATE_LOAD; staging deduplicates by (file, row number); totals unchanged |
| (added 2026-09-28) Scaled NUMBER through the connector | No float field in Arrow/Parquet; NUMBER(38,9) extremes round-trip exactly |
| Added nullable field | Minor compatible schema accepted only by defined policy; unknown field safely retained/ignored as contract says |
| Type/precision/grain breaking change | Quarantine major version; preserve prior serving data; migrate with dual-version fixture |
| Replay after Snowflake file history expiry | New immutable replay keys with original lineage; business dedup independent of file-load memory |
| Lease expires while old worker runs | New fenced owner proceeds; old worker cannot advance checkpoints or accept publication |
| One account/source denied | Other work proceeds under fairness; health/coverage explicitly partial; no fabricated zeros |

## Adversarial isolation matrix

Create tenant A with accountsA1/A2 and tenant B withB1; create A-admin, A-reader limited toA1, A-team-reader and B-admin. (amended 2026-09-28) Add the review's attack cases (SEC backlog Appendix I): a restricted-profile Snowflake session attempting secondary or alternate roles; a policy mutation replacing `CURRENT_ROLE()` by `IS_ROLE_IN_SESSION()` that the suite must catch; a team reader deriving a sibling's amount from weights, denominators or "Other" buckets; an account-limited reader learning organization totals by subtraction; a landing key crafted to start inside another tenant's prefix; a Dagster run tag trying to override the extractor task role; a tenant header swapped in a second browser tab; a sealed cursor replayed after a scope change (409 `SCOPE_CHANGED`). Use overlapping resource names and query IDs to expose missing composite keys. For each API/list/autocomplete/aggregate/cursor/job/report/notification/action/statement: submit foreign IDs, drop filters, reuse stale permission epochs, swap tenant headers, replay signed cursors and revoke the user during execution. Expect scoped403 or non-enumerating404, never foreign names/counts/totals. At database level, execute deliberately filter-free reads under runtime identities and prove PG/Snowflake enforce isolation. Attempt alternate roles, entitlement mutation and cross-prefix S3 access. Compare timing only within controlled tolerance; do not claim zero side-channel risk from one test.

## UX state matrix

Every task with customer UX must prove persona, goal, entry, happy path, empty, loading, partial, error, denied, success, drilldown and primary actions. Test390px and desktop widths, keyboard-only flow, focus/error announcements, chart alternatives, contrast and long/negative/multicurrency labels. Keep scope/filter/back navigation across drilldowns. Tenant switch clears old data before new responses; late A response cannot appear after selecting B. PROVISIONAL/FINAL/RECONCILED labels have text meaning; color alone is insufficient.

## Evidence and commands

```bash
make validate-task TASK=ING-008 ENV=local
make validate-task TASK=CON-002 ENV=staging
make validate-task TASK=OPS-011 ENV=staging
```

These commands are implementation interfaces specified by FND-005, not already implemented tools. Evidence record fields: task/test ID, implementation commit, environment/account references, dependency versions, fixture/input hashes, expected/observed, PASS/FAIL/NOT_RUN, UTC time, reviewer, artifact references and rollback result. Remove secrets and real customer payloads before committing any evidence. Keep customer-specific proof privately and commit only a safe reference. Re-run only affected tests plus required promotion gates; do not claim previous evidence covers a changed security or financial contract.

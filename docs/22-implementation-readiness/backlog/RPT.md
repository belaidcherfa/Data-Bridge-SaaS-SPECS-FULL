# RPT — Implementation-readiness review and production backlog

Canonical contract: [reporting.md](../../14-reporting/reporting.md) (with [governance.md](../../12-budgets-monitoring/governance.md) delivery rules, [ADR-009](../../architecture/adr/ADR-009-privacy-and-retention.md), [allocation.md](../../11-allocation/allocation.md) statements, PRD §109–§111, [pages/reports.md](../../21-ui-ux/pages/reports.md), [pages/dashboards.md](../../21-ui-ux/pages/dashboards.md)). Tasks reviewed: RPT-001, RPT-002, RPT-003, RPT-004, RPT-005. Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

## 1. Verdict

Implementable after targeted corrections. The security posture is right: isolated renderer, no user HTML, secure links by default, re-authorization at send and download. What is under-specified are the calendar and authorization mechanics, and some rules are wrong or contradictory:
- The DST "skip" default contradicts RFC 5545 and silently drops weekly reports.
- An occurrence key that includes the schedule revision allows duplicate sends after an edit.
- Schedules ignore data maturity, so a CFO Monthly report on the 1st is always provisional.
- Positive-offset timezones would report an incomplete UTC day.
- Recipients with a narrower scope than the owner have no defined outcome.
- 30-day artifact retention (ADR-009) contradicts "retention does not erase required closed-statement evidence".
- Slack and Teams webhooks cannot carry attachments.

The biggest schedule risk is RPT-003 waiting on eight templates across five other domains. Author first: the component and definition schemas (RPT-001-S01/S02), the schedule resolver specification with DST fixtures (RPT-004-S02/S03), the artifact manifest and retention classes (RPT-002-S10, RPT-005-S08), and the recipient-authorization rule (G-RPT-04). R1 = four templates (Executive FinOps, CFO Monthly, Team Showback, Chargeback Statement), PDF + CSV, email and Slack/Teams **link** delivery. PNG, the other four templates, external recipients, attachments and dashboards move to R2.

## 2. Findings

### G-RPT-01 · The DST "skip nonexistent occurrence" default is wrong for a reporting product
Severity: HIGH · Type: CONTRADICTION
Evidence: `reporting.md`: "For daylight saving: skip a nonexistent local occurrence and record SKIPPED_DST; use the earlier offset once for an ambiguous occurrence." `pages/reports.md`: "DST gap skipped and logged". RFC 5545 §3.3.5 (iCalendar, the scheduling convention users expect) interprets a nonexistent local time "using the UTC offset before the gap". Python `zoneinfo` with `fold=0` yields exactly that instant.
Computation: America/New_York spring-forward is Sunday 2026-03-08 02:00→03:00 (Mar 1 2026 is a Sunday, so the second Sunday is Mar 8). Daily 02:30: under SKIP there is no report; under RFC 5545 it runs at 02:30 EST = 07:30Z = 03:30 EDT. Europe/Paris switches Sunday 2026-03-29 at 01:00Z: a 02:30 schedule runs at 01:30Z = 03:30 CEST. A weekly Sunday 02:30 report is skipped entirely that week under SKIP. For the ambiguous case (NY fall-back Sunday 2026-11-01 01:30), "earlier offset" means the pre-transition offset EDT −04:00 → 05:30Z (first occurrence), not the numerically smaller −05:00. The wording is ambiguous.
Why it matters: A missing weekly or monthly report is a customer-visible defect that looks like an outage. The ambiguity lets an implementer pick 06:30Z.
Resolution: Default `dst_gap_policy=SHIFT_FORWARD` (RFC 5545, `fold=0`), with SKIP available per schedule and audited as SKIPPED_DST. The overlap rule is fixed as FIRST occurrence (`fold=0`, pre-transition offset). Both are recorded on the occurrence as `dst_adjustment ∈ {NONE, SHIFTED_FORWARD, SKIPPED, FIRST_OF_AMBIGUOUS}`. This challenges reporting.md and pages/reports.md.
Affects: RPT-004.

### G-RPT-02 · An occurrence key that includes the schedule revision permits duplicate reports
Severity: HIGH · Type: AMBIGUITY
Evidence: `reporting.md`: "A logical occurrence key includes schedule revision and resolved UTC instant; a retry cannot create another logical report." RPT-004 failure list: "duplicate schedule revision".
Why it matters: A user edits recipients at 08:05 after the 08:00 run, which creates revision 2. Catch-up logic that looks for "the most recent missed occurrence" of revision 2 finds today's 08:00 slot unrun under revision 2 and sends the report again. A timezone edit changes the UTC instant for the same local slot and produces the same duplicate.
Resolution: Uniqueness is `(tenant_id, schedule_id, cadence_kind, slot_key)`. slot_key is the local calendar slot: DAILY `2026-03-08`, WEEKLY `2026-W10-7`, MONTHLY `2026-03`, QUARTERLY `2026-Q1`. schedule_revision and resolved_instant_utc are attributes, not key parts. The planner only plans slots whose nominal instant ≥ `revision.effective_from`. A deliberate re-send is an explicit "run again" with a new `manual_run_id`.
Affects: RPT-004.

### G-RPT-03 · Report data period and data readiness are undefined
Severity: HIGH · Type: GAP
Evidence: `reporting.md` defines cadence and wall time only. `governance.md`: "Default monthly UTC periods". D-13: USAGE_IN_CURRENCY_DAILY FINAL at date_end + 72 h; a month is billing-stable at month_end + 5 days. The PRD §110 CFO Monthly template "disclose provisional periods".
Computation: A daily report at 08:00 Asia/Tokyo on local 2026-10-02 fires at 2026-10-01T23:00Z. "Previous day" relative to the local date is UTC 2026-10-01, which is incomplete for another hour and has no FINAL sources. A CFO Monthly on the 1st at 08:00 Europe/Paris always shows the prior month as PROVISIONAL, and USAGE_IN_CURRENCY_DAILY may lack the last 3 days.
Why it matters: Finance receives a monthly report with silently missing days, or an "as-of" confusion between local and UTC periods. Numbers then disagree with the Explorer.
Resolution:
- Data periods are always UTC financial periods: the latest complete UTC day, ISO week, month or quarter whose end ≤ the nominal instant. The Tokyo example therefore reports 2026-09-30.
- `readiness_policy ∈ {RUN_ON_TIME, WAIT_FOR_FINAL(max_wait_days)}`. Default WAIT_FOR_FINAL(7) for CFO Monthly and Chargeback, RUN_ON_TIME for others.
- While waiting, the occurrence status is WAITING_DATA, re-checked hourly against D-13 maturity. After the maximum wait it runs with a PROVISIONAL banner and an owner notice.
- The UI shows "Sent at 08:00 Tokyo time; covers UTC day 2026-09-30".
Affects: RPT-004, RPT-003.

### G-RPT-04 · The recipient authorization model is undefined when scopes differ
Severity: HIGH · Type: GAP
Evidence: `reporting.md`: "recipient entitlement is checked before payload delivery … If owner/recipient loses scope, pause or redact by regenerating under the narrower valid scope; never send a previously broader artifact"; "Default external distribution is an authenticated secure link". `security.md`: "A scope is a union of grant clauses".
Why it matters: A team-scoped recipient on a CFO report has three possible outcomes: receive the owner's full artifact (a leak), receive a per-recipient re-render (N renders per occurrence, N Snowflake snapshots), or be dropped silently. An "authenticated secure link" cannot work for an external address with no account. Silently narrowing a CFO report when the *owner* loses scope produces a misleading total under the same title.
Resolution:
- R1 recipients are tenant users (including invited guest viewers) and groups resolved to users at dispatch.
- The artifact carries `scope_class = sha256(canonical(owner permission profile ∩ definition filters))` (D-02 normalized profile).
- A recipient receives the artifact iff `scope_class(recipient profile ∩ definition filters) == artifact scope_class`. Otherwise the delivery is EXCLUDED(RECIPIENT_SCOPE_INSUFFICIENT), audited, and the owner is notified. Canonical inequality is conservative: equivalent but differently expressed scopes are excluded (acceptable, logged).
- Owner scope change → schedule PAUSED(OWNER_SCOPE_CHANGED) until an admin reassigns the owner or confirms the narrower scope. Silent narrowing is not allowed.
- Per-recipient redacted renders and external addresses are R2 (RPT-102).
Affects: RPT-004, RPT-005, new RPT-102.

### G-RPT-05 · 30-day artifact retention conflicts with chargeback statement evidence
Severity: HIGH · Type: CONTRADICTION
Evidence: ADR-009: "reports 30 days … canonical 400 days … No irreversible Object Lock compliance mode by default". RPT-005: "Enforce default30-day artifact retention except approved statement preservation policy" and oracle "retention does not erase required closed-statement evidence". `allocation.md`: "creates immutable statement lines".
Why it matters: The issued chargeback PDF is what finance circulated. Regeneration after 30 days is not byte-identical once templates, fonts or Chromium change. After 400 days, even the statement lines may be gone. The "approved statement preservation policy" is referenced but defined nowhere.
Resolution: Two artifact retention classes:
- **EPHEMERAL**: 30 days (ADR-009), prefix `reports/ephemeral/`.
- **RECORD**: chargeback statement artifacts and any artifact explicitly "filed" by a FinOps Admin. Prefix `reports/record/`, default retention = max(400 days, tenant contract value), configurable up to 7 years via CTL-007 entitlement (owner question Q2). Object Lock GOVERNANCE mode (reversible by a break-glass role, consistent with ADR-009's "no compliance mode by default").
- Statement templates render no user-level personal data (team/cost-center only), so D-10 erasure never requires editing RECORD PDFs.
- Statement lines in Snowflake must be retained ≥ RECORD retention. This is a dependency on ALC/OPS retention; flag it to OPS-005.
Affects: RPT-005, RPT-003; OPS-005, ALC-008.

### G-RPT-06 · Renderer isolation assumptions on Fargate
Severity: MEDIUM · Type: RISK / VENDOR-FACT
Evidence: `reporting.md`: "Use a pinned browser image … network egress denied except an explicit internal data handoff". `platform.md`: "non-root/read-only filesystems where compatible". Chromium's own sandbox relies on user namespaces/seccomp. Whether the Fargate runtime allows Chromium's namespace sandbox without `--no-sandbox` is TO VERIFY LIVE. Fargate does not grant SYS_ADMIN.
Why it matters: If `--no-sandbox` is required, the browser process boundary is weaker. A shared long-lived worker with one IAM role could also write any tenant's S3 prefix, so a renderer bug becomes a cross-tenant write.
Resolution: (1) Only a bundled static app and typed JSON are loaded, and `page.route('**/*')` aborts every non-bundle URL. (2) Security group egress is limited to the S3 gateway endpoint, SQS and the PG proxy. Snowflake is not reachable from the renderer: the snapshot runs in the snapshot step via the query broker. (3) One fresh browser process and profile directory per job, killed afterwards. (4) Per-job STS AssumeRole with a session policy restricting `s3:PutObject/GetObject` to `tenant/{tenant_id}/reports/runs/{run_id}/*` and the KMS encryption context `tenant_id`. (5) FONTCONFIG restricted to bundled fonts. (6) Record the sandbox result in RPT-002-S06.
Affects: RPT-002.

### G-RPT-07 · Presigned URL revocation exposure is larger than stated
Severity: MEDIUM · Type: VENDOR-FACT
Evidence: `reporting.md`: "URL lifetime bounds residual revocation exposure". VERIFIED (docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html, search snippet 2026-09-27): "If you created a presigned URL using a temporary token, then the URL expires when the token expires", and "Amazon S3 checks the expiration date and time of a signed URL at the time of the HTTP request".
Why it matters: Exposure = URL lifetime (to *start* the download) + transfer duration. A download started at second 59 of a 60 s URL completes after revocation. A URL signed by a task role whose credentials expire sooner than X-Amz-Expires fails early and causes spurious errors.
Resolution: The broker signs with credentials that have ≥ 15 min remaining, sets `X-Amz-Expires=60`, `response-content-disposition=attachment; filename*=UTF-8''…` and `response-cache-control=private, no-store`, and returns a 302. The disclosed exposure is "60 s to start plus transfer time". Tenants with `HIGH_SENSITIVITY` use the brokered byte stream (authorization is checked before streaming starts; a revocation mid-stream is not interrupted, also disclosed). Every broker decision is audited. — Superseded in part by RECONCILIATION U-10/C-12: the broker is SEC-006-S08 (single artifact broker) and the presigned lifetime is 30 s everywhere; the ≥ 15 min signer-credential rule and the brokered stream for HIGH_SENSITIVITY tenants are kept.
Affects: RPT-005.

### G-RPT-08 · Attachments cannot be delivered through the specified Slack/Teams integrations
Severity: MEDIUM · Type: GAP
Evidence: PRD §110 channels: "email Slack Teams secure link"; formats "PDF PNG CSV". `governance.md`: Slack via "OAuth/incoming webhook", Teams via "Workflow/Power Automate webhook". Slack incoming webhooks accept message payloads only, and file upload needs a bot token with files scopes (TO VERIFY LIVE). Teams Workflows webhooks post cards (TO VERIFY LIVE).
Why it matters: A "PDF to Slack" option fails at runtime or forces a broader bot-token OAuth scope (files:write) that security has not reviewed.
Resolution: Slack/Teams deliveries in R1 are link-only cards (title, period, as-of, maturity badge, secure link). Attachments are email-only and R2 behind a tenant policy (RPT-102) with a 10 MiB post-encoding cap. Over the cap, the delivery falls back to link-only with the reason ATTACHMENT_TOO_LARGE. The SES v2 message size limit is TO VERIFY LIVE.
Affects: RPT-004, new RPT-102.

### G-RPT-09 · The CSV formula-injection rule is incomplete
Severity: MEDIUM · Type: GAP
Evidence: `reporting.md`: "CSV neutralizes spreadsheet formula prefixes after leading whitespace/control characters while preserving the numeric typed fields."
Why it matters: The prefix set, Unicode variants, encoding and the numeric exemption are unspecified. Escaping "-20.00" corrupts signed amounts. Not escaping full-width "＝" or "|" leaves known spreadsheet vectors open. A missing BOM makes Excel mangle non-ASCII team names.
Resolution: The CSV spec (RPT-002-S08):
- UTF-8 with BOM, CRLF, RFC 4180 quoting of all string fields.
- Typed numeric/money columns are written from Decimal as `^-?\d+(\.\d+)?$` (no thousands separator, currency in its own column) and are never escaped.
- For string columns: strip-test leading `[\u0000-   -​　﻿]`. If the first remaining character ∈ `= + - @ | % \t \r` or full-width `＝ ＋ － ＠`, prefix the original value with `'`.
- Dates are ISO-8601 UTC.
- Locale formatting (D-18) applies to PDF/UI only.
- Test vectors: `=1+1`, `  =cmd|' /C calc'!A0`, `\t=1`, `＝1`, `@SUM(A1)`, `-20.00` in a money column (unchanged), `-foo` in a label (escaped).
Affects: RPT-002; also INS-101 export and API-004 exports (shared writer).

### G-RPT-10 · Snapshot placement contradicts the renderer's egress isolation
Severity: MEDIUM · Type: CONTRADICTION
Evidence: `reporting.md`: "Snowflake owns values and result snapshots. Private S3 stores generated PDF/PNG/CSV plus a checksum manifest", and "network egress denied except an explicit internal data handoff".
Why it matters: If the snapshot lives in Snowflake, the renderer needs Snowflake connectivity and credentials, which removes the egress isolation. Storing snapshot rows in Snowflake per report also adds write cost for no reader.
Resolution: The snapshot step (not the renderer) executes component queries through the query broker (D-22) against a **pinned publication map**. It writes `snapshot.json` (typed; decimals as strings) with a sha256 to the run's S3 prefix. The renderer reads only that object. Snowflake remains the value authority through the pinned `publication_id`s in the manifest. This challenges the "Snowflake owns … result snapshots" wording.
Affects: RPT-002.

### G-RPT-11 · Over-serialized dependencies and missing edges
Severity: HIGH · Type: RISK
Evidence: task-index: RPT-003 deps `['RPT-002','ALC-008','GOV-008','WRK-005','UX-007']`; RPT-004 deps `['RPT-003','GOV-007']`; RPT-002 deps `['RPT-001','ORC-003','INF-004']`.
Why it matters: Scheduling cannot start until all eight templates (dbt, AI, incidents) exist, although it only needs one renderable report. RPT-002 lacks the ECS/IAM base (INF-005), leases/fencing (CTL-004), the job contract (API-004) and the query broker (API-002).
Resolution: RPT-002 `+INF-005, +CTL-004, +API-004, +API-002`. RPT-003 (R1 templates) `−GOV-008, −WRK-005, −UX-007, +ALC-007, +GOV-001, +GOV-004` (monitor summary needs incidents only); the R2 templates move to RPT-101 with WRK-005/UX-007/INS-101. RPT-004 `−RPT-003, +RPT-002` (it can run with the Executive template fixture; keep GOV-007). RPT-005 `+SEC-006` (revocation epochs).
Affects: RPT-002..005, new RPT-101.

### G-RPT-12 · The per-report execution model and its cost are unspecified
Severity: MEDIUM · Type: RISK
Evidence: `reporting.md`: "isolated ECS report worker launched/coordinated by Dagster". PRD §16: "PDF reports 10" concurrency. The same concern as D-07 applies.
Computation (prices TO VERIFY, AWS Fargate x86 public list): 2 vCPU/4 GiB ≈ 2 × 0.04048 + 4 × 0.004445 = 0.0987 USD/h. A 30 s render ≈ 0.0008 USD. The snapshot runs 8 component queries × ~2 s on an XS serving warehouse (1 credit/h) = 16 s ≈ 0.0044 credits ≈ 0.013 USD at 3 USD/credit. About 14 USD per 1,000 reports; Snowflake dominates. One always-warm worker costs ≈ 72 USD/month/environment. Launching one Fargate task per report adds 30–90 s of start and image pull for a ~1 GB Chromium image.
Resolution: Dagster (or the RPT-004 planner) only enqueues. A long-running ECS report-worker service consumes the ORC-003 `report` queue with per-tenant fairness and autoscales 1→N on queue depth (1 warm for interactive previews). Isolation is per job (G-RPT-06), not per task. RPT-002-S14 measures and publishes cost per report.
Affects: RPT-002.

### G-RPT-13 · Narrative "validated templates" have no grammar
Severity: MEDIUM · Type: GAP
Evidence: `reporting.md`: "Narrative uses validated templates over known numbers, with no invented causes." The RPT-001 oracle: "narrative contains only evidenced values".
Resolution: The narrative is a list of template IDs from `narrative/v1/*.json`. Each template has typed slots bound to snapshot JSON paths (for example `{kpi.spend.value|money}`). Direction words (`increased`/`decreased`/`unchanged`) are derived from the sign with a ±0.5 % unchanged band. Causal vocabulary ("because", "due to", "driven by", "caused") is allowed only in templates bound to an evidence type (a top contributor from the breakdown). No free text is accepted. The validator rejects unbound slots. Tests assert that every number in rendered narrative text appears in the snapshot.
Affects: RPT-001, RPT-003.

### G-RPT-14 · PDF determinism and acceptance fencing are undefined
Severity: MEDIUM · Type: GAP
Evidence: RPT-002 oracle: "A repeated job accepts one artifact manifest". Failure list: "half-upload". Contract: "deterministic fixtures". Chromium embeds a creation date and document ID in PDFs, so repeated renders differ byte-wise.
Resolution: Post-process with pikepdf to set `/CreationDate` = `/ModDate` = run.generated_at (the logical time) and `/ID` derived from run_id + attempt-independent content hash. Identical input and image digest then give identical bytes, which makes checksum parity tests possible. Upload with the object tag `accepted=false`. Acceptance is a PG transaction guarded by the CTL-004 fence token and `status <> CANCELLED`, and it then sets the tag `accepted=true`. An S3 lifecycle rule deletes `accepted=false` objects after 1 day.
Affects: RPT-002.

### G-RPT-15 · Chargeback statement artifacts depend on schedules instead of issuance
Severity: MEDIUM · Type: GAP
Evidence: `reporting.md`: "Chargeback uses a closed statement version". ALC-008: "issued version immutable; duplicate request returns same statement". No task renders the issued statement at issuance.
Why it matters: If the only artifact comes from a schedule, the circulated statement may be rendered days later with a newer template, or never.
Resolution: A statement-issued event (ALC-008 outbox) triggers exactly one RECORD-class render per `statement_version_id` (idempotent key). Scheduled "Chargeback Statement" reports reference the latest *issued* version for the period and never an open one.
Affects: RPT-003, RPT-005; ALC-008.

### G-RPT-16 · UI contradictions and an unowned route
Severity: LOW · Type: CONTRADICTION / GAP
Evidence: `pages/reports.md` schedule dialog "Time UTC: [____]" vs the contract "IANA timezone, local wall time". `product.md` navigation includes "Dashboards"; `pages/dashboards.md` has two routes, while CTL-007 ("saved views, dashboards and commercial control records") stores configuration only. No task builds the dashboard UI or widget data path (grep over docs/tasks).
Resolution: The schedule dialog gets Time + Timezone (IANA picker, default browser zone, UTC explicit) plus a next-five preview. The dashboard builder reuses the RPT-001 component contracts, with viewer-scoped widget data, as new R2 task RPT-103.
Affects: RPT-004, new RPT-103.

### G-RPT-17 · Limit semantics and the pre-enqueue check
Severity: LOW · Type: AMBIGUITY
Evidence: "Default ceilings: 100 pages, 50k CSV rows for interactive exports and250k for asynchronous exports, 60s render CPU deadline, 100MiB artifact".
Resolution: The 60 s CPU limit (RLIMIT_CPU on the browser process tree) is separate from a 120 s wall deadline per render stage. The pages estimate (Σ component rows/35 + fixed sections) and the CSV row estimate (COUNT query via broker) are checked at validate/enqueue time and return 413 REPORT_TOO_LARGE with a suggested filter. Post-render overflow fails with REPORT_PAGE_LIMIT and no partial artifact. PDF tables show "N rows not shown; totals include all rows", with totals computed server-side over the full set.
Affects: RPT-001, RPT-002.

### G-RPT-18 · R1 scope proposal (D-01)
Severity: MEDIUM · Type: OVER-ENGINEERING
Evidence: PRD §109/§110 require 8 templates × 3 formats × 4 channels. RPT-003 "Build all eight templates".
Resolution: R1 covers the Executive FinOps, CFO Monthly, Team Showback and Chargeback Statement templates, PDF + CSV, email secure link plus Slack/Teams link cards, and tenant-user recipients. R2 covers Platform Review, Warehouse Review, dbt Review, AI/Cortex Review and PNG (RPT-101), external recipients and attachments (RPT-102), and dashboards (RPT-103). The first-customer journey (ONB-005 "deliver an authorized test notification/report") is fully covered by R1.
Affects: RPT-003, RPT-004.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by |
|---|---|---|
| `data/contracts/report-definition.schema.json` | definition (id, tenant, owner, title ≤ 120, template_id@version, page_size A4/Letter, locale "en", filters, layout grid 12 col, components[]), immutable revision, visibility | RPT-001-S01 |
| `data/contracts/report-components/*.schema.json` (11) | Input: component_type@version, metric_id@version, dimensions[], grain, period_ref, currency_mode {SINGLE, PER_CURRENCY}, cost_basis, maturity_policy, top_n ≤ 50, sort. Output: rows[], totals_by_currency{}, maturity_summary, coverage, publication_id, as_of, truncation{shown, total} | RPT-001-S02 |
| Narrative grammar v1 | Template list, slot types (money, pct, date, entity), direction band ±0.5 %, allowed causal templates bound to evidence types | RPT-001-S06 |
| State machines | report_run: QUEUED→SNAPSHOTTING→RENDERING→UPLOADING→READY \| FAILED \| CANCELLED; READY→EXPIRED. occurrence: PLANNED→WAITING_DATA→ENQUEUED→COMPLETED \| SKIPPED_DST \| SKIPPED_PAUSED \| MISSED \| FAILED. delivery: PENDING_AUTH→AUTHORIZED \| EXCLUDED(reason)→SENDING→SENT \| FAILED→DLQ | RPT-002-S01, RPT-004-S01 |
| Schedule schema + resolver spec | cadence, byweekday, day_of_month (1–31 \| LAST), month_in_quarter, local_time, tz (IANA, pinned tzdata version), dst_gap_policy {SHIFT_FORWARD, SKIP}, overlap FIRST, data_period, readiness_policy, catch_up {LATEST_ONLY, NONE}, recipients, formats, channels; DST fixture table (RPT-004-S03) | RPT-004-S01..S03 |
| Artifact manifest schema | run_id, attempt, formats[{format, s3_key, bytes, sha256}], template@version, metric/dataset versions, publication_ids{}, timezone, filter_summary, scope_class, permissions_snapshot_hash, generated_at, source_as_of, maturity, coverage, retention_class, renderer_image_digest | RPT-002-S10 |
| CSV serialization spec | G-RPT-09 rules + test vectors, folded into API-102-S03's shared CSV writer `packages/exporters/csv.py` (RECONCILIATION U-10) | API-102-S03 (RPT-002-S08 adds the G-RPT-09 vectors) |
| S3 layout + lifecycle | `tenant/{t}/reports/runs/{run}/attempt/{n}/…` (tag accepted); `reports/ephemeral` 30 d, `reports/record` retention policy, NoncurrentVersionExpiration 1 d (ephemeral), ExpiredObjectDeleteMarker; KMS key + encryption context | RPT-002-S10, RPT-005-S08 |
| IAM | report-worker task role (AssumeRole only), per-job session policy template, broker role (GetObject + kms:Decrypt on tenant context) | RPT-002-S12 (presigning is SEC-006-S08's broker; RECONCILIATION U-10) |
| Renderer image spec | Playwright + Chromium version pinned by digest; fonts: Inter, Noto Sans, Noto Sans Mono, Noto Sans Symbols 2, Noto Sans CJK subset; fontconfig allowlist; TZ=UTC; non-root; read-only rootfs | RPT-002-S04 |
| OpenAPI | `/v1/reports` CRUD, `/v1/reports/validate`, `/v1/reports/{id}/preview`, `/v1/report-runs` (POST 202, GET list/detail, POST cancel), `/v1/report-runs/{id}/artifacts/{aid}/download`, `/v1/report-schedules` CRUD, `/v1/report-schedules/{id}/preview-occurrences`, `/v1/report-schedules/{id}/runs` (manual slot) | RPT-001, RPT-002, RPT-004, RPT-005 |
| Error codes | REPORT_UNSUPPORTED_METRIC 422, REPORT_CURRENCY_MIXED 422, REPORT_TEXT_UNSAFE 422, STATEMENT_NOT_ISSUED 422, REPORT_TOO_LARGE 413, REPORT_STALE_REVISION 409, PERMISSION_EPOCH_CHANGED, SNAPSHOT_STALE, REPORT_PAGE_LIMIT, RENDER_TIMEOUT, RECIPIENT_SCOPE_INSUFFICIENT, OWNER_SCOPE_CHANGED, ATTACHMENT_TOO_LARGE | all |

## 4. Revised production backlog

### RPT-001 — Define report schema and reusable component contracts
Release: R1 · Estimate: 36–54 h · Risk: M · Decisions: D-01, D-02, D-18, D-22 · Closes: G-RPT-13, G-RPT-17 (pre-enqueue)
Dependency changes: `+CTL-003` (scoped CRUD and optimistic concurrency pattern). Keep API-001, API-004, UX-001.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| RPT-001-S01 | Author the definition/revision/layout JSON Schema (§3) | `data/contracts/report-definition.schema.json` | Schema tests: unknown template, 13-column layout and missing owner rejected | 3 |
| RPT-001-S02 | Author the 11 component input/output schemas (KPI, Trend, Breakdown, Waterfall, Table, TopN, Budget, Insight, MonitorSummary, AllocationSummary, Narrative) | `data/contracts/report-components/*.schema.json` | Each schema has one valid and one invalid example under test | 4 |
| RPT-001-S03 | Compatibility validator against the API-001 registry: metric/dimension existence, component×metric rules (Waterfall needs an additive signed metric; Budget needs a budget scope; Insight/Allocation widgets need the module capability, else UNAVAILABLE placeholder) | `services/reporting/validation.py` | Broken metric reference → 422 REPORT_UNSUPPORTED_METRIC with the field path | 3 |
| RPT-001-S04 | Currency rule: a money component over a multi-currency scope must be PER_CURRENCY; a single KPI over mixed currencies → 422 REPORT_CURRENCY_MIXED unless an approved FX dataset ID is referenced | validator | 270 USD + 20 EUR preview gives two totals, never 290 | 2 |
| RPT-001-S05 | Text safety: titles/labels/footer are plain text ≤ 200 chars; reject control chars (footer allows `\n`), URL schemes (`[a-z][a-z0-9+.-]*:` followed by `//` or `javascript:`/`data:`) and tag-like `<…>` → 422 REPORT_TEXT_UNSAFE | validator | Vectors `<img src=x onerror=alert(1)>`, `javascript:alert(1)`, `https://evil`, `=HYPERLINK("x")` → 422 (the last one is accepted as text but CSV-escaped later) | 2 |
| RPT-001-S06 | Narrative grammar v1 (G-RPT-13) and validator | `services/reporting/narrative/v1/*.json`, `narrative.py` | A template with an unbound slot fails; rendering on the fixture only uses snapshot numbers (property test) | 3 |
| RPT-001-S07 | Reference checks: a chargeback component requires `statement_version_id` with status ISSUED; an insight component references the published insight set | validator | Open statement → 422 STATEMENT_NOT_ISSUED | 2 |
| RPT-001-S08 | Pre-enqueue size estimate (pages and CSV rows via broker COUNT) and the 30-component limit → 413 REPORT_TOO_LARGE | `services/reporting/estimate.py` | 300k-row table component → 413 before any job exists | 2 |
| RPT-001-S09 | PostgreSQL migrations: `report_definition`, `report_revision` (immutable), `report_component`; tenant composite keys, FORCE RLS, revision column | `apps/api/migrations/*_reports.sql` | RLS negative test passes | 3 |
| RPT-001-S10 | API: CRUD `/v1/reports`, `POST /v1/reports/{id}/revisions` (expected_revision), `POST /v1/reports/validate`, `POST /v1/reports/{id}/preview` (202 via API-004) returning missing capabilities and scope errors | `apps/api/reports/routes.py` | Stale revision → 409 REPORT_STALE_REVISION with no change | 3 |
| RPT-001-S11 | Permissions: Analyst edits own reports; Team Admin edits team reports; FinOps Admin edits all plus chargeback templates; revoked owner → definition read-only and hook to pause schedules | policy + tests | Foreign report UUID → 404; Viewer create → 403 | 3 |
| RPT-001-S12 | Preview fixtures: 270 USD/20 EUR, partial coverage 80 %, restricted team reader, malicious labels | `tests/spec/RPT-001/fixtures/` | Golden preview JSON stable across runs | 2 |
| RPT-001-S13 | Report builder UI (`/reports/new`, builder canvas) with validation errors beside fields | `apps/web/reports/builder/*` | Playwright: invalid metric shows an inline error; keyboard path | 4 |
Task acceptance:
- [ ] Preview totals 270 USD and 20 EUR separately.
- [ ] Unsupported metric or layout is rejected before enqueue.
- [ ] Narrative contains only evidenced values.
- [ ] No HTML/URL/script is accepted in any definition field.

### RPT-002 — Implement isolated snapshot and render workers
Release: R1 · Estimate: 42–63 h · Risk: H · Decisions: D-02, D-22, D-18 · Closes: G-RPT-06, G-RPT-09, G-RPT-10, G-RPT-12, G-RPT-14, G-RPT-17
Dependency changes: `+INF-005` (ECS base/roles), `+CTL-004` (leases/fence), `+API-004` (job contract), `+API-002` (query broker). Keep RPT-001, ORC-003, INF-004.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| RPT-002-S01 | `report_run` model and state machine with lease/fence token and attempt_no; idempotency unique on (tenant, occurrence_id) or (tenant, request Idempotency-Key) | migration + `services/reporting/runs.py` | 10 identical POSTs → one run | 3 |
| RPT-002-S02 | Snapshot step: pin the tenant publication map at start; execute component queries via the broker under the owner's profile/epoch; typed JSON (decimal strings) + sha256 to the attempt prefix; compute scope_class and permissions_snapshot_hash | `services/reporting/snapshot.py` | Snapshot of the fixture equals golden JSON; publication IDs recorded | 4 |
| RPT-002-S03 | Stale handling: epoch change mid-job → abort with PERMISSION_EPOCH_CHANGED and re-plan once; publication retired before read → SNAPSHOT_STALE, re-pin once | same | Revocation between snapshot and render → run FAILED, no artifact | 2 |
| RPT-002-S04 | Renderer image per §3 spec (pinned Chromium digest, bundled fonts, fontconfig allowlist, TZ=UTC, non-root, read-only rootfs, tmpfs /tmp) | `services/reporting/Dockerfile`, `fonts/` | `fc-list` in container shows only bundled fonts; image digest recorded | 3 |
| RPT-002-S05 | Render isolation: static bundle via `file://` or 127.0.0.1; `page.route('**/*')` aborts non-bundle requests; SG egress only to S3 endpoint/SQS/PG proxy | `services/reporting/render/browser.py`, Terraform SG | Label `<img src=https://attacker>` renders as text; request log shows 0 external requests; `curl snowflakecomputing.com` from the task times out | 3 |
| RPT-002-S06 | Chromium sandbox probe on Fargate (TO VERIFY LIVE); if `--no-sandbox` is required, document compensating controls; one browser process per job, killed after | `docs/evidence/RPT-002/sandbox.md` | Evidence recorded with the runtime platform version | 2 |
| RPT-002-S07 | PDF: A4/Letter, printBackground, CSS paged media (repeat `thead`, `break-inside: avoid` on rows and total groups), maturity/coverage footer per page; pikepdf normalizes CreationDate/ModDate/ID | `render/pdf.py`, `render/print.css` | Two renders of the same input → identical sha256 | 4 |
| RPT-002-S08 | Reuse API-102-S03's CSV writer library on the snapshot (not the DOM) and add the G-RPT-09 test vectors to it (RECONCILIATION U-10) | `render/csv.py` (uses `packages/exporters/csv.py`) | All test vectors pass; `-20.00` money unchanged; `-foo` label escaped | 1 |
| RPT-002-S09 | Limits: RLIMIT_CPU 60 s on the browser process tree, 120 s wall per stage, page count ≤ 100 checked post-render, 100 MiB cap, 4 GiB task memory; failures → safe codes, no partial publish | `render/limits.py` | 150-page fixture → REPORT_PAGE_LIMIT; infinite-layout fixture → RENDER_TIMEOUT | 3 |
| RPT-002-S10 | Upload + acceptance: objects tagged `accepted=false`; manifest written last; PG acceptance transaction checks fence and not-cancelled, then tags `accepted=true`; lifecycle deletes untagged after 1 d | `runs.py`, S3 lifecycle Terraform | Crash injected between upload and acceptance → retry yields exactly one accepted manifest (oracle) | 4 |
| RPT-002-S11 | Cancellation: CANCEL_REQUESTED checked at each stage; acceptance refuses a cancelled run | same | Cancel during render → no READY, objects removed by lifecycle | 2 |
| RPT-002-S12 | Per-job STS session policy scoped to `tenant/{t}/reports/runs/{run}/*` and KMS encryption context | IAM policy template, `worker.py` | Job for tenant A writing to B's prefix → AccessDenied (test) | 3 |
| RPT-002-S13 | Worker service: long-running ECS service consuming the ORC-003 `report` queue with per-tenant fairness; autoscale 1→N on queue depth; Dagster/planner only enqueue | Terraform + `worker.py` | 20 queued jobs from one tenant do not delay another tenant's single job by > 1 job duration | 3 |
| RPT-002-S14 | Capacity and cost benchmark: 5/20/100-page fixtures; p50/p95 render, peak RSS, snapshot credits; publish cost per report | `docs/evidence/RPT-002/capacity.md` | Numbers published; the 100-page fixture stays within 60 s CPU or ceilings are revised | 3 |
| RPT-002-S15 | Observability: `rpt_render_duration_seconds{template,format}`, `rpt_run_total{outcome}`, `rpt_snapshot_query_seconds`, `rpt_queue_age_seconds`; alarms: failure rate > 5 % over 1 h, queue age > 15 min; runbook | OTel + alarms + `docs/runbooks/report-worker.md` | Synthetic failure triggers the alarm in staging | 2 |
Task acceptance:
- [ ] A repeated job accepts exactly one manifest.
- [ ] No external URL is fetched; the renderer cannot reach Snowflake.
- [ ] 270 stays 270 across snapshot, PDF text, CSV and API.
- [ ] Cancellation never publishes a partial PDF.
- [ ] Cross-tenant S3 write is impossible from a job session.

### RPT-003 — Implement and visually qualify the R1 report templates
Release: R1 (4 templates; the other 4 → RPT-101) · Estimate: 36–54 h · Risk: M · Decisions: D-01, D-12, D-13 · Closes: G-RPT-15, G-RPT-18
Dependency changes: `−GOV-008`, `−WRK-005`, `−UX-007` (R2 templates → RPT-101); `+ALC-007` (showback), `+GOV-001` (budget component), `+GOV-004` (monitor summary). Keep RPT-002, ALC-008.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| RPT-003-S01 | Template catalog v1: sections, components, required capabilities, page-size rules for the 4 R1 templates | `services/reporting/templates/catalog.v1.json` | Catalog validates against the RPT-001 schemas | 2 |
| RPT-003-S02 | Executive FinOps: KPI strip (spend, change, forecast, budget, potential savings if INS enabled, verified savings), trend, top-N services/accounts/teams, coverage footer, narrative | `templates/executive_finops/` | Golden PDF passes numeric parity | 4 |
| RPT-003-S03 | CFO Monthly: per-currency totals (never summed), PROVISIONAL banner and period disclosure, reconciliation status, signed adjustments/credits, month-over-month waterfall per currency | `templates/cfo_monthly/` | Multicurrency fixture shows two waterfalls; −20 adjustment rendered signed | 4 |
| RPT-003-S04 | Team Showback: team scope, allocation summary, explicit unallocated, budget vs actual | `templates/team_showback/` | Restricted team reader fixture shows only own team; unallocated visible | 3 |
| RPT-003-S05 | Chargeback Statement: bound to the issued statement version; lines from immutable ALC-008 rows; rounding-delta row; superseded notice; no user-level names | `templates/chargeback_statement/` | 120 + 80 = 200 exact; open statement → STATEMENT_NOT_ISSUED | 4 |
| RPT-003-S06 | Issuance hook: ALC-008 statement-issued event → one RECORD-class render per statement_version_id | consumer | Duplicate event → same run | 2 |
| RPT-003-S07 | Fixtures per template: complete, empty, partial (80 %), negative adjustment, multicurrency (270 USD/20 EUR), long labels (200 chars incl. CJK) | `tests/reports/golden/*` | Fixture set checked in with expected numbers | 4 |
| RPT-003-S08 | Numeric parity: extract PDF text (pdfminer), compare every money token with snapshot, CSV and API | `tests/reports/parity_test.py` | 0 mismatches across all fixtures | 3 |
| RPT-003-S09 | Visual qualification: rasterize with pdftoppm at 110 dpi vs golden (tolerance ≤ 0.1 % pixels), A4 and Letter; programmatic checks: text boxes inside the page, headers repeated, last row and its total on the same page | `tests/reports/visual_test.py` | Long-label fixture has no clipped totals; CJK glyphs render (no tofu) | 4 |
| RPT-003-S10 | Unavailable-module blocks (Insight/Allocation not enabled) render "Not available: <reason>", never 0 | component fallback | Fixture with INS disabled shows the block | 1 |
| RPT-003-S11 | `/reports/templates` gallery with static thumbnails (built from fixtures) and a generate flow | `apps/web/reports/templates/*` | Playwright: generate → run appears in history | 3 |
| RPT-003-S12 | Staging evidence, runbook entries for template versioning | `docs/evidence/RPT-003/` | Evidence complete | 2 |
Task acceptance:
- [ ] All 4 R1 templates pass numeric parity and visual review at A4 and Letter.
- [ ] Chargeback 120 + 80 = 200 from the immutable statement; issuance produces one RECORD artifact.
- [ ] CFO totals remain per currency, with provisional periods disclosed.

### RPT-004 — Implement calendar schedules and report occurrence planning
Release: R1 · Estimate: 40–60 h · Risk: H · Decisions: D-02, D-13, D-24 · Closes: G-RPT-01, G-RPT-02, G-RPT-03, G-RPT-04 (dispatch), G-RPT-08, G-RPT-16 (dialog)
Dependency changes: `−RPT-003`, `+RPT-002` (a renderable report is enough; use the Executive fixture). Keep GOV-007.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| RPT-004-S01 | Schedule schema and migration per §3 (status ACTIVE / PAUSED(reason), revision, effective_from) | `apps/api/migrations/*_report_schedules.sql` | Invalid IANA zone and day_of_month 32 rejected | 3 |
| RPT-004-S02 | Pure resolver `(schedule, slot) → instant_utc \| SKIPPED_DST` using zoneinfo `fold=0`, SHIFT_FORWARD default, day clamp; tzdata version recorded | `services/reporting/schedule_resolver.py` | 100 % branch coverage | 3 |
| RPT-004-S03 | DST and calendar fixtures: NY daily 02:30 on 2026-03-08 → 07:30Z (SHIFT) / SKIPPED_DST (SKIP); NY 01:30 on 2026-11-01 → 05:30Z once; Paris 02:30 on 2026-03-29 → 01:30Z; Paris 02:30 on 2026-10-25 → 00:30Z once; monthly day 31 → 2026-02-28, 2028-02-29, 2026-04-30; quarterly month 3 day 31 → Mar 31, Jun 30, Sep 30, Dec 31; weekly Monday 08:00 Paris → 07:00Z in winter, 06:00Z in summer | `tests/spec/RPT-004/resolver_test.py` | All fixtures pass | 3 |
| RPT-004-S04 | Slot-key uniqueness `(tenant, schedule, cadence_kind, slot_key)`; plan only slots ≥ revision.effective_from; `INSERT … ON CONFLICT DO NOTHING` | planner + unique index | 10 concurrent planner ticks → 1 occurrence (oracle); edit at 08:05 creates no second 08:00 report | 3 |
| RPT-004-S05 | Planner loop every minute: `SELECT … FOR UPDATE SKIP LOCKED` due schedules; create occurrence and outbox job in one transaction (CTL-004) | `services/reporting/scheduler.py` | Kill the planner mid-transaction → no orphan job; restart resumes | 3 |
| RPT-004-S06 | Catch-up LATEST_ONLY: slots older than grace (6 h daily, 24 h weekly+) → MISSED; the most recent missed slot within one cadence period runs; data period derived from the slot; manual historical run by slot_key (audited) | planner | Outage 2026-05-01 00:00Z–05-04 12:00Z, daily 08:00Z → May 1–3 MISSED, May 4 run covers UTC day May 3 | 3 |
| RPT-004-S07 | Readiness policy WAIT_FOR_FINAL(max_days): WAITING_DATA with hourly D-13 maturity check; after max → run with PROVISIONAL banner and owner notice | `readiness.py` | CFO Monthly slot 2026-10-01 waits until September is billing-stable (D-13 +5 d) → runs 2026-10-06 | 3 |
| RPT-004-S08 | Data-period rule: latest complete UTC period with end ≤ nominal instant | `periods.py` | Tokyo 08:00 on local 2026-10-02 (23:00Z Oct 1) → UTC day 2026-09-30 | 2 |
| RPT-004-S09 | tzdata upgrade: re-resolve PLANNED (not enqueued) occurrences, keep enqueued ones, audit the diff | job + test | Simulated zone rule change moves only unenqueued instants | 2 |
| RPT-004-S10 | Dispatch authorization per G-RPT-04: expand groups to users; per recipient check active membership, current epoch and scope_class equality; EXCLUDED(reason) + owner notice; owner scope change → PAUSED(OWNER_SCOPE_CHANGED) | `dispatch.py` | Team-scoped recipient on an org report → EXCLUDED; revoked between render and dispatch → no delivery | 4 |
| RPT-004-S11 | Delivery through the GOV-007 outbox: email with secure link; Slack/Teams link cards; logical delivery id = (occurrence, recipient/destination, format); retries reuse it | adapter bindings | Ambiguous-timeout retry → one logical delivery, at most duplicate transport, deduplicated in history | 3 |
| RPT-004-S12 | API + UI: CRUD, `preview-occurrences` (next five, with DST annotations), pause/resume, run now, stale revision 409; dialog with Time + IANA timezone | `apps/api/report-schedules`, `apps/web/reports/schedule/*` | Playwright: NY schedule preview shows "shifted to 03:30 (DST)" on Mar 8 | 4 |
| RPT-004-S13 | Negative tests: revoked recipient, revoked destination, foreign schedule UUID → 404, schedule owned by a removed user → paused | tests | All pass without leakage | 2 |
| RPT-004-S14 | Observability: `rpt_occurrence_total{outcome}`, `rpt_planner_lag_seconds` (alarm > 5 min), `rpt_delivery_excluded_total{reason}`; runbook (missed slots, manual rerun) | alarms + runbook | Planner stop in staging fires the alarm | 2 |
Task acceptance:
- [ ] One occurrence per slot regardless of ticks, retries or edits.
- [ ] DST gap shifted forward (or skipped when configured, and audited); ambiguous time uses the first occurrence once.
- [ ] Day 31 clamps to month end, including leap years.
- [ ] No recipient ever receives an artifact broader than their current scope.
- [ ] Monthly finance reports wait for billing-stable data or disclose PROVISIONAL.

### RPT-005 — Implement report history, secure access and retention
Release: R1 · Estimate: 25–38 h · Risk: M · Decisions: D-02, D-10, D-25 · Closes: G-RPT-05, G-RPT-07
Dependency changes: `+SEC-006` (revocation epochs; its S08 is the single artifact download broker into which this task plugs a report authorization resolver — RECONCILIATION U-10). Keep RPT-004, SEC-008, CTL-007.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| RPT-005-S01 | History API `GET /v1/report-runs` (cursor) and detail with generation, authorization and delivery states separated | `apps/api/report-runs/*` | Foreign run ID → 404 | 3 |
| RPT-005-S02 | History UI `/reports/history`: columns Run, Artifact, Delivery, Scope; states pending/running/ready/failed/expired; safe retry (same occurrence, new attempt) | `apps/web/reports/history/*` | Playwright: failed run retry keeps the occurrence ID | 3 |
| RPT-005-S03 | Plug the report authorization resolver into SEC-006-S08's single artifact download broker (RECONCILIATION U-10): artifact READY and unexpired, requester ∈ owner ∪ delivered recipients ∪ report viewers, current scope_class equals the artifact's; otherwise 404/403 with a regenerate offer | `apps/api/report-downloads/resolver.py` | User revoked after generation → 404; narrowed scope → 403 + regenerate | 1 |
| RPT-005-S04 | Moved to SEC-006-S08 per RECONCILIATION U-10, C-12 (presign 30 s — not 60 s —, attachment disposition, private/no-store, signer credentials ≥ 15 min remaining, 302) | — | — | 0 |
| RPT-005-S05 | Brokered stream mode for HIGH_SENSITIVITY tenants (chunked, Content-Disposition attachment, Cache-Control no-store, 100 MiB cap) | broker | 100 MiB fixture streams with bounded API memory (< 64 MiB RSS delta) | 3 |
| RPT-005-S06 | Notification secure link = app route (no bearer token); login then broker | link builder | Link contains no signature or token query parameters | 1 |
| RPT-005-S07 | Download audit (actor, artifact, mode, decision, reason) via SEC-008 | audit emitter | Every broker decision has one audit row | 1 |
| RPT-005-S08 | Retention classes EPHEMERAL (30 d) / RECORD (default 400 d, entitlement up to 7 y; Object Lock GOVERNANCE); lifecycle rules incl. noncurrent versions (1 d) and delete markers | Terraform S3 config + policy | `list-object-versions` shows no ephemeral versions 2 days after expiry (staging, accelerated rule) | 3 |
| RPT-005-S09 | Expiry job marks runs EXPIRED; an expired link offers regeneration under current authorization ("as of original publication" only if still retained) | job + UI | Expired fixture offers regenerate; the new run records the new scope_class | 2 |
| RPT-005-S10 | Owner/admin deletion of allowed artifacts (EPHEMERAL only; RECORD requires break-glass with reason); tenant offboarding interface for OPS-005 | API + tests | Analyst deleting a RECORD artifact → 403 | 2 |
| RPT-005-S11 | Negative suite: guessed foreign run/artifact IDs, replayed presigned URL, stale epoch cookie, non-owner delete | `tests/spec/RPT-005/security_test.py` | All non-enumerating | 2 |
| RPT-005-S12 | Evidence: purge of abandoned `accepted=false` attempts, RECORD retention visible on the statement artifact | `docs/evidence/RPT-005/` | Evidence complete | 2 |
| RPT-005-S13 | Observability (`rpt_download_total{mode,decision}`) and runbook (legal hold, retention change) | runbook | Reviewed | 2 |
Task acceptance:
- [ ] A revoked user receives no artifact; a guessed foreign job ID reveals nothing.
- [ ] Presigned URL lifetime 30 s via SEC-006-S08 (RECONCILIATION C-12), with the exposure disclosed; brokered stream available.
- [ ] Ephemeral artifacts and their versions are gone after 30 days; closed-statement RECORD artifacts are retained per policy.

## 5. New tasks required

### RPT-101 — R2 templates and PNG (Platform Review, Warehouse Review, dbt Review, AI/Cortex Review)
Release: R2 · Estimate: 30–45 h · Risk: M · Decisions: D-01, D-20 · Closes: G-RPT-11, G-RPT-18
Why/where: Split from RPT-003 to take WRK/UX-007/INS dependencies off the R1 path. Deps: RPT-003, WRK-005, UX-007, INS-101, FIN-018.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| RPT-101-S01 | Platform Review template (services, storage, serverless, data health coverage) | `templates/platform_review/` | Parity test passes | 4 |
| RPT-101-S02 | Warehouse Review (idle, top warehouses, R1 insights WH01/WH02 with impact kinds) | `templates/warehouse_review/` | CEILING vs ESTIMATE labelled | 4 |
| RPT-101-S03 | dbt Review with exact vs inferred run labels (WRK-002) | `templates/dbt_review/` | Inferred groups excluded from exact run metrics | 4 |
| RPT-101-S04 | AI/Cortex Review with non-overlapping service totals (FIN-018 authority layer) | `templates/ai_review/` | Parent/child totals not stacked | 4 |
| RPT-101-S05 | PNG export (page 1 or a selected component at 2× DPR) for Slack/Teams previews | `render/png.py` | PNG sha256 stable across two renders | 3 |
| RPT-101-S06 | Fixtures (complete/empty/partial/negative/multicurrency/long labels) × 4 | golden files | Checked in | 4 |
| RPT-101-S07 | Visual + numeric qualification | tests | 0 mismatches | 4 |
| RPT-101-S08 | Evidence | docs | Complete | 3 |
Task acceptance:
- [ ] All 8 templates pass parity at A4 and Letter.
- [ ] dbt exact/inferred distinction and AI non-overlap are proven.

### RPT-102 — External recipients and attachment policy
Release: R2 · Estimate: 22–33 h · Risk: H · Decisions: D-25 · Closes: G-RPT-04 (external), G-RPT-08
Why/where: External, non-user distribution needs a separate trust model. Deps: RPT-004, RPT-005, GOV-006.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| RPT-102-S01 | Tenant policy object: attachments allowed (Y/N), allowed recipient domains, max classification, acknowledgement text "delivered copies cannot be revoked" signed by an Org Admin | `report_distribution_policy` + API | No policy → attachments impossible | 3 |
| RPT-102-S02 | External recipient type (email only) validated against the domain allowlist; artifact rendered under the owner's scope_class, recorded per delivery | dispatch extension | Non-allowlisted domain → 422 | 3 |
| RPT-102-S03 | Email attachment via SES (MIME) with a 10 MiB post-encoding cap; over the cap → link-only fallback (users) or failure (externals) with ATTACHMENT_TOO_LARGE | adapter | 12 MiB PDF fixture → fallback recorded | 3 |
| RPT-102-S04 | Per-recipient redacted render option (scope-class grouping: one render per distinct class) with a cap of 10 classes per occurrence | dispatch | 3 recipients in 2 classes → 2 renders | 4 |
| RPT-102-S05 | Audit and disclosure in history ("attachment delivered; cannot be revoked") | UI + audit | Visible on the delivery row | 2 |
| RPT-102-S06 | Security tests (header injection in recipient names, allowlist bypass via subdomain/IDN homograph) | tests | All rejected | 3 |
| RPT-102-S07 | SES bounce/complaint handling for external addresses: suppress the recipient after a hard bounce or complaint and notify the owner | SNS consumer + suppression list | Simulated hard bounce → recipient SUPPRESSED; next occurrence skips it with a reason | 2 |
| RPT-102-S08 | Evidence | docs | Complete | 2 |
Task acceptance:
- [ ] Attachments only under an acknowledged tenant policy and for email only.
- [ ] External recipients restricted to allowlisted domains.

### RPT-103 — Dashboards builder and viewer-scoped widgets
Release: R2 · Estimate: 27–41 h · Risk: M · Decisions: D-02, D-18 · Closes: G-RPT-16
Why/where: `/dashboards` and `/dashboard-builder` are in the navigation and UI spec but have no implementing task; CTL-007 only stores configuration. Reuses the RPT-001 component contracts. RPT-103 owns the backend (dashboard definition as a report layout kind, widget data API under the viewer's scope, sharing, export to report); the list, builder and viewer UI are UX-101's, into which CTL-103 is merged (RECONCILIATION U-01). Deps: RPT-001, CTL-007, UX-004; UX-101 depends on this task.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| RPT-103-S01 | Dashboard definition = a report definition with layout kind DASHBOARD (12-col responsive, 1 col mobile) | schema extension | Validator shared with reports | 3 |
| RPT-103-S02 | Widget data API: each widget queried under the **viewer's** scope (visibility grant ≠ data grant) | `apps/api/dashboards/*` | Restricted viewer sees restricted numbers for the same dashboard | 5 |
| RPT-103-S03 | Moved to UX-101-S02/S03 per RECONCILIATION U-01 (builder UI) — expose the definition/widget API it consumes | — | — | 0 |
| RPT-103-S04 | Moved to UX-101-S06 per RECONCILIATION U-01 (viewer UI and widget states) — the widget data API returns the state codes | — | — | 0 |
| RPT-103-S05 | Sharing (visibility grants) and optimistic concurrency | API | Stale save → 409 | 4 |
| RPT-103-S06 | "Export dashboard to report" (same components) | converter | Numbers equal between dashboard and PDF | 4 |
| RPT-103-S07 | Isolation suite (foreign dashboard ID, shared dashboard to an out-of-scope user) | tests | Non-enumerating | 3 |
| RPT-103-S08 | Performance (12 widgets, p95 ≤ 2 s warm), evidence | docs | Published | 3 |
| RPT-103-S09 | Accessibility (200 % zoom, keyboard, screen-reader chart summaries) | tests | Pass | 3 |
| RPT-103-S10 | Runbook and docs | docs | Reviewed | 2 |
Task acceptance:
- [ ] Sharing a dashboard never shares data beyond the viewer's scope.
- [ ] Dashboard and exported report show identical numbers for the same publication.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| RPT-001 | R1 | 36 | 54 |
| RPT-002 | R1 | 42 | 63 |
| RPT-003 | R1 | 36 | 54 |
| RPT-004 | R1 | 40 | 60 |
| RPT-005 | R1 | 25 | 38 |
| RPT-101 | R2 | 30 | 45 |
| RPT-102 | R2 | 22 | 33 |
| RPT-103 | R2 | 27 | 41 |
| **Total R1** | | **179** | **269** |
| **Total R2** | | **79** | **119** |

## 7. Owner questions

1. Default DST gap policy: RFC 5545 shift-forward (recommended) or the currently specified skip?
2. RECORD retention for issued chargeback statement artifacts (and the underlying statement lines): 400 days, the contract term, or 7 years? This drives OPS-005 and storage cost.
3. Are external (non-user) recipients and email attachments needed for the first customer (proposed R2)?
4. Should monthly finance reports wait for billing-stable data by default (WAIT_FOR_FINAL, 7 days), even if that means the report arrives around the 6th instead of the 1st?
5. Is the brokered byte stream (highest assurance, API bandwidth cost) required for any first-customer tenant, or is a 30 s presigned URL (RECONCILIATION C-12) acceptable?
6. Is the Dashboards area (PRD navigation) required for R1, or can the Home page plus reports cover executive needs until R2?

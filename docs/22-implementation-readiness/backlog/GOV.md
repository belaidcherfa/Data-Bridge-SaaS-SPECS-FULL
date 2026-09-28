# GOV — Implementation-readiness review and production backlog

Canonical contract: [governance.md](../../12-budgets-monitoring/governance.md). Tasks reviewed: GOV-001, GOV-002, GOV-003, GOV-004, GOV-005, GOV-006, GOV-007, GOV-008 (plus PRD §89–§96, ADR-003/005/007/008, [semantic-api.md](../../09-api/semantic-api.md), [control-plane.md](../../03-control-plane/control-plane.md), [security.md](../../02-security/security.md), [intelligence.md](../../13-insights/intelligence.md), [reporting.md](../../14-reporting/reporting.md), [validation-strategy.md](../../15-testing/validation-strategy.md), UI pages budgets/monitors). Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

## 1. Verdict

Partly implementable. The statistical defaults are unusually concrete, and the budget and anomaly fixtures recompute correctly: 280 − 150 = 130; 150 + 10 × 15 = 300; 20 / 280 = 7.142857…% (PASS); 60 / (1.4826 × 10) = 4.0469445568… → 4.04694456 (PASS); MAD = 0 cases 100→101 suppressed, 100→130 flagged (PASS).

Four defects must be fixed before coding:
1. Monitor confirmation counts schedule ticks, not new evidence, so the 101/102/103 fixture FAILS as written against a `last_complete_day` window (AUDIT X-30, G-GOV-01).
2. The forecast rules contradict each other on minimum history: 84 days, not 56 (G-GOV-02).
3. Weekday anomaly cohorts can never activate from a 28-day baseline (G-GOV-03).
4. Team budgets need an allocated-spend metric that the registry lacks (G-GOV-04).

Vendor facts change three notification designs: Office 365 connectors are retired and Workflows URLs moved to `*.environment.api.powerplatform.com`; Slack allows 1 msg/s per channel; Standard Webhooks gives a ready signing scheme. As written, GOV-001…008 also sit on the 73-task critical path behind the showback UI and the public API. Realistic effort is about 352–500 h for R1 (8 existing + 3 new tasks) and 40–57 h for R2 (2 new tasks).

## 2. Findings

### G-GOV-01 · Monitor confirmation counts ticks, not distinct evidence; the worked fixture is inconsistent
Severity: HIGH · Type: CONTRADICTION (confirms AUDIT X-30)
Evidence: `governance.md` makes these statements:
- "Default evaluation is hourly UTC over the last complete daily window"
- "Sustained threshold breach requires 2 eligible evaluations"
- "Observation identity includes config, scope partition, logical schedule tick, time window and input publication"
- "observations101/102 opens one incident; the next hourly103 attaches"

The monitors UI echoes the same thing: "Eligible breaches: 3 — 101, 102 and 103", "Episode age 2 h".

Why it matters: two hourly ticks read the same completed day and the same publication. Because the tick is part of the identity, they count as two eligible evaluations. Every daily-window breach therefore "sustains" one hour later, and hysteresis does nothing. The fixture's values change hourly, which is impossible for a fixed completed day unless data is being corrected. **FAIL as written.**

Resolution (challenges governance.md on observation identity):
- **Observation key** = `(tenant, monitor_id, monitor_version, condition_version, partition_key_hash, window_start, window_end, input_publication_id)`. The tick is stored as an attribute only. A tick whose (window, publication) already has an observation is skipped with no Snowflake query.
- **Counters** advance only on a *new distinct window*. A newer publication for an already-counted window *supersedes* its result and does not add a count.
- **Tracker state** is a pure fold over the ordered list of latest results per distinct window since the last episode boundary, so replay is deterministic.
- **Rewritten fixture** (daily windows):
  - D1 101: counter 1.
  - D2 102: episode OPENS.
  - D3 103: attaches, occurrence 3.
  - D4 INSUFFICIENT_DATA: holds, no counter change.
  - D5 99: ok counter 1.
  - D6 98: RESOLVED (OBSERVED_RECOVERY).
  - 23 further hourly ticks over D2 with the same publication: 0 new observations.
  - 100 retries of the D2 evaluation: 1 observation, 1 incident, 1 notification.
- For sub-daily sustain, use `window.kind = trailing_complete_hours:n` (each tick is a distinct window).

Affects: GOV-003, GOV-004, GOV-008.

### G-GOV-02 · Forecast minimum history is internally inconsistent (56-day trend vs 4 folds × 28 training days)
Severity: HIGH · Type: CONTRADICTION
Evidence: `governance.md` says:
- "Theil–Sen slope… over the last56 complete days"
- "Automatic model selection starts only with enough data for four rolling7-day holdout folds, each with at least28 training days"
- "calibrated intervals only after held-out coverage and width are recorded over at least20 rolling forecast origins"

Computation:
- The four 7-day holdouts cover the last 28 days. The earliest fold has only (h − 28) training days.
- "≥ 28 training days" needs h ≥ 56. Fitting the specified 56-day Theil–Sen window in that earliest fold needs h ≥ 56 + 28 = **84** contiguous complete days.
- Calibration over 20 daily origins, with a month-end horizon of up to H = 30 days and selection at each origin, needs 84 + 19 + 30 = **133** days. Seasonal-naive only needs 28 + 19 + 30 = 77.

Why it matters: an implementer can read 56 and get a trend fitted on 28 points in early folds (a different model from production), or read 84. Backtests are then not comparable across versions, and leakage checks cannot be written.

Resolution:
- Eligibility ladder on contiguous complete days h:
  - h < 7: INSUFFICIENT_HISTORY.
  - 7–27: RUN_RATE_FALLBACK.
  - 28–83: SEASONAL_NAIVE without selection (label `NO_SELECTION_EVIDENCE`).
  - h ≥ 84: selection between SN and TS on 4 folds. Fold holdouts are [t−27..t−21], [t−20..t−14], [t−13..t−7], [t−6..t]. SN trains on the prior 28 days, TS on the prior 56. MAE is pooled over the 28 holdout days. TS wins iff MAE_TS ≤ 0.9 × MAE_SN.
- Intervals: attempted only with h ≥ 133 (TS-eligible) or ≥ 77 (SN-only). Published only if held-out coverage of the nominal 80% interval falls in [75%, 85%]; otherwise null + UNCALIBRATED.
- Per the release plan, R1 ships run-rate + SN (GOV-002). TS, selection and intervals ship in R2 (GOV-105).

Affects: GOV-002, GOV-105.

### G-GOV-03 · Weekday anomaly cohorts are unreachable with a 28-day baseline; "missing day" is ambiguous
Severity: HIGH · Type: CONTRADICTION / AMBIGUITY
Evidence: `governance.md` says:
- "Default anomaly baseline is the previous28 complete daily observations"
- "Use same-weekday cohorts only when at least8 prior comparable weekdays exist"
- "Missing days suppress evaluation; zero observed spend on a complete day is valid"

Computation: 28 days contain exactly 4 of each weekday, so 8 prior same weekdays need a 56-day lookback. The cohort rule never fires as written.

Why it matters:
- Weekly-seasonal workloads (weekday ETL) flag every Monday against a baseline full of weekend days.
- It is unclear whether "missing" means a coverage gap or zero spend. If pre-creation days count as zeros, every new resource flags as an anomaly.

Resolution (versioned `anomaly_v1`):
- **Cohort**: the last 8 same-weekday complete observations within a 56-day lookback. If fewer than 8, fall back to the 28-day all-days baseline.
- **Baseline start**: the partition's `first_seen` date. If fewer than 28 baseline observations exist, return INSUFFICIENT_HISTORY; new spend is handled by the `new_resource` condition.
- **"Missing"** means a coverage gap only. A missing current day means no evaluation. Any missing baseline day means suppression with reason `MISSING_BASELINE`. A complete day with no activity is 0.
- **Threshold**: `score ≥ 3.5` includes equality. This differs deliberately from INS's strict thresholds and must be documented in both places.

Affects: GOV-005, GOV-101, INS-001.

### G-GOV-04 · Team/group budgets need an allocated-spend metric that the registry does not define
Severity: HIGH · Type: GAP
Evidence:
- `governance.md`: "Scope can be organization/account/service/team/group…"; "allocation book/version policy"; "Actual is the same signed net spend metric as explorer; do not create a separate budget formula".
- `semantic-api.md`: the metric table has `spend` (fct_charge) and no allocated metric.
- `security.md`: "a team-restricted identity must never query an account-only total".

Why it matters: a Finance budget cannot be computed from `spend` (fct_charge has no group), and restricted team owners cannot read `spend` at all. Implementers would invent a budget-only allocated formula, which the contract forbids.

Resolution:
- Budgets reference a registry metric: `spend v1` for organization/account/service/warehouse/custom scopes, or `allocated_spend v1` with a required `book_id` for team/group scopes (ALC-102).
- Book/version policy: `FLOATING_LATEST_PUBLISHED` by default. Each evaluation records the allocation publication used. A republished allocation re-evaluates the budget, and threshold incidents follow correction semantics (G-GOV-08).
- Overlapping budgets are evaluated independently. No API returns a sum of budgets or actuals across budgets.

Affects: GOV-001, GOV-002, ALC-102.

### G-GOV-05 · Which identity evaluates monitors, budgets and forecasts is undefined; batching conflicts with RLS unless keyed by profile
Severity: HIGH · Type: GAP / RISK (security)
Evidence:
- ADR-005: "each distinct tenant permission profile maps to a constrained… identity… Broad aggregates cannot serve narrower readers".
- `governance.md`: "Distinct partitions have distinct episodes and independent authorization checks"; "Reauthorize sensitive payload generation".
- GOV-003: "Validate… permissions".

Why it matters: a tenant-wide evaluator could compute partitions outside the monitor owner's scope and push them to a Slack channel. The only guard would be application code, which is exactly the filter-only enforcement ADR-005 rejects. Per-monitor queries under each owner's role, however, destroy batching (G-GOV-06).

Resolution (consistent with ADR-005 and D-02, no amendment):
- Each monitor, budget and forecast runs as its owner's current normalized **profile role**. It is re-resolved at every tick from durable PG state (SEC-006). No GOV process holds serving credentials: evaluators submit server-signed batch plans to the broker's JOB class (API-002), which assumes the tenant user and sets the profile role; Python results are written through ORC-103 under the central writer identity (RECONCILIATION C-09).
- Batches are keyed `(tenant, profile_role, dataset, window, input_publication)`. Many monitors share the FinOps Admin profile, so batching survives.
- If the owner is removed, or the owner's scope no longer covers the monitor scope, the monitor becomes `PAUSED_AUTH`. It is never silently narrowed. Its open incidents stay visible, and admins are notified to reassign.
- Delivery reauthorizes each email recipient against the partition scope. Channel destinations use `authorized_scope` plus `disclosure_level` (G-GOV-11).

Affects: GOV-001, GOV-002, GOV-003, GOV-004, GOV-007.

### G-GOV-06 · Planner cost: unbatched hourly evaluation multiplies Snowflake queries; sync/SLA monitors do not need Snowflake
Severity: HIGH · Type: RISK
Evidence:
- AUDIT X-26/X-27: "100 tenants × 20 monitors × 24 hourly evaluations = 48,000 queries/day unless batched".
- `governance.md`: "Operational sync/SLA monitors may use5-minute windows".
- `control-plane.md`: sync coverage lives in PG (`sync.coverage_intervals`).

Why it matters:
- Each Snowflake query costs at least one warehouse-seconds unit and keeps the serving warehouse warm around the clock (OPS-009).
- 5-minute SLA monitors in Snowflake would cost 12× more for data that already lives in PG.

Resolution:
1. Skip unchanged: no query when (window, publication) has already been observed. Daily cost windows change only when a day completes or a correction publishes.
2. Batch evaluation: one SQL per (tenant, profile_role, dataset, window, publication) computes every member monitor's partitions through a `cfg_monitor_scope` join. The scope table is published via D-04.
3. Evaluate `sync_failure`/`sla_violation` from PG `sync` state. This costs zero Snowflake credits.
4. Per-tenant evaluation budget: 60 queries per hour by default. Overflow defers lower-severity batches (`monitor_planner_deferred`).

Expected: ≤ 3 datasets × ≤ 24 publications per tenant per day, so ≤ 72 queries/tenant/day. That is 7,200/day at 100 tenants, against 48,000. TO VERIFY LIVE in GOV-103.

Affects: GOV-003, GOV-004, GOV-103.

### G-GOV-07 · Partition enumeration bounds are unspecified (e.g. partition_by user with 10k users)
Severity: HIGH · Type: GAP
Evidence:
- `governance.md`: "Partition enumeration is bounded and authorized; unseen groups can be discovered by the generic engine".
- PRD §92: "Automatically monitors every model… user".
- GOV-004 failure list: "partition renamed; high cardinality".

Why it matters:
- 10k users × a 28-day anomaly baseline is 280k points per tick per monitor.
- Per-partition incidents could send 10k notifications.
- Names used as keys make a rename open a new episode.
- User partitions expose personal data (D-10).

Resolution:
- `max_partitions`: default 500, hard cap 5,000 per monitor (plan quota, D-17).
- Validation dry-run estimates cardinality (distinct partition keys, last 30 days, in scope). If the cap is exceeded: 422 `PARTITION_CARDINALITY`, unless `partition_overflow = TOP_N_PLUS_OTHER`. That mode evaluates the top N by window value plus one explicitly labelled `__other__` aggregate. Anomaly is disabled on `__other__`.
- Partition key = canonical JSON of **stable IDs** (resource id, workload id, user pseudonym per D-10), never names. Labels are resolved at display time for authorized viewers only.
- The digest caps notifications (G-GOV-11/GOV-005).

Affects: GOV-003, GOV-004, GOV-005.

### G-GOV-08 · Incident state machine lacks transitions for corrections, definition edits, cooldown, manual resolve, silence expiry and loss of authorization
Severity: HIGH · Type: GAP
Evidence:
- `governance.md`: "States OPEN/ACKNOWLEDGED/INVESTIGATING/RESOLVED"; "corrected versions supersede…"; "A still-breaching condition may reopen only after the explicit cooldown/silence policy permits it".
- GOV-004: "reevaluation updates incident rather than creating duplicates".
- There is no transition table.

Why it matters: without explicit transitions, an edit to a monitor's threshold, a data correction that erases the breach, or a manual resolve during a live breach each produce implementation-specific duplicates or zombie incidents.

Resolution (exact table; unique partial index `(tenant, monitor_id, condition_version, partition_key_hash) WHERE state <> 'RESOLVED'`):

| From | Event | Guard | To | Effects |
|---|---|---|---|---|
| none | BREACH(new window) | breach_count+1 ≥ N_b ∧ now ≥ cooldown_until | OPEN | incident created; outbox `incident.opened` unless silenced |
| none | BREACH(new window) | otherwise | none | breach_count++ |
| OPEN/ACK/INV | BREACH(new window) | — | same | occurrence++ (saturating 10,000); `incident.updated` only on severity escalation or 24 h reminder |
| OPEN/ACK/INV | OK(new window) | ok_count+1 ≥ N_r | RESOLVED(OBSERVED_RECOVERY) | cooldown_until = now + cooldown; `incident.recovered` |
| OPEN/ACK/INV | OK(new window) | otherwise | same | ok_count++, breach_count=0 |
| any | INSUFFICIENT_DATA | — | same | counters unchanged; timeline note; monitor-level insufficient > 48 h → owner notice (not an incident) |
| OPEN/ACK/INV | SUPERSEDE(window) | re-fold no longer reaches N_b | RESOLVED(DATA_CORRECTION) | `incident.recovered{reason:DATA_CORRECTION}` (≤ 1 per 24 h) |
| none | SUPERSEDE(window) | re-fold reaches N_b | OPEN | opened with `opened_by_correction=true` |
| OPEN | ACKNOWLEDGE | actor scope ⊇ partition | ACKNOWLEDGED | audit |
| OPEN/ACK | INVESTIGATE | actor scope | INVESTIGATING | audit |
| OPEN/ACK/INV | ASSIGN | assignee scope ⊇ partition | same | audit |
| OPEN/ACK/INV | MANUAL_RESOLVE | reason ≥ 10 chars | RESOLVED(MANUAL) | counters reset; cooldown applies; not "measured recovery" |
| OPEN/ACK/INV | CONDITION_VERSION_BUMP | — | RESOLVED(DEFINITION_CHANGED) | new key starts at zero |
| OPEN/ACK/INV | MONITOR_PAUSED/DELETED | — | RESOLVED(MONITOR_DISABLED) | — |
| any | OWNER_SCOPE_LOST | — | same; monitor PAUSED_AUTH | deliveries stop; admins notified |
| RESOLVED | any | — | RESOLVED (terminal) | a new episode gets a new id |

Silence is an overlay on delivery only. Its scope is a monitor or monitor+partition, with owner, reason, expiry ≤ 30 days (default 24 h). On expiry with the incident still open and the last event suppressed, exactly one `incident.updated{still_active}` is sent.

Affects: GOV-004, GOV-008.

### G-GOV-09 · Teams: connectors are retired, Workflows URLs changed domain, and the payload is an Adaptive Card envelope with accept-only semantics
Severity: HIGH · Type: VENDOR-FACT
Evidence:
- `governance.md`: "Teams uses a currently supported Workflow/Power Automate webhook… do not build new dependence on retired Office 365 connectors".
- Search results (2026-09-27):
  - Microsoft devblog/Learn: Office 365 connector deadline "extended to April 30, 2026… migrated to Workflows before May 18, 2026".
  - Power Automate HTTP/Teams-webhook trigger URLs moved from `logic.azure.com` to `https://<env>.aa.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/…`; "calls to old URLs will no longer work after" November 30, 2025.
  - Workflows expect "Adaptive Cards wrapped in a specific envelope". VERIFIED via search snippets of devblogs.microsoft.com/microsoft365dev/retirement-of-office-365-connectors-within-microsoft-teams and learn.microsoft.com add-incoming-webhook.

Why it matters: an adapter built on MessageCard or legacy URLs fails at launch. A 202 from the flow does not prove the post happened. A workflow stops when its owner leaves, and Bridge cannot see that until sends fail. The URL embeds a `sig=` credential.

Resolution:
- Accept only `https` URLs whose host ends with `.environment.api.powerplatform.com` and whose path starts `/powerautomate/automations/direct/workflows/`. A `logic.azure.com` URL gets 422 `TEAMS_LEGACY_URL`.
- Store the whole URL as a secret.
- Payload: `{"type":"message","attachments":[{"contentType":"application/vnd.microsoft.card.adaptive","content":{AdaptiveCard}}]}`.
- Record the result as `ACCEPTED_BY_PROVIDER`, not DELIVERED.
- 4xx means PERMANENT with the remediation "workflow disabled or owner removed".
- The payload cap is 24 KB; the actual Teams limit (reportedly ~28 KB) and flow throttling are TO VERIFY LIVE.
- Release R1* (only if the D-20 customer uses Teams).

Affects: GOV-006, GOV-102.

### G-GOV-10 · Slack: choose OAuth bot token over incoming webhooks; enforce 1 msg/s/channel
Severity: MEDIUM · Type: VENDOR-FACT
Evidence:
- `governance.md`: "Slack uses supported OAuth/incoming webhook integration with destination/channel validation".
- Slack docs: "apps may post no more than one message per second per channel, whether a message is posted via chat.postMessage, an incoming webhook", and 429 with `Retry-After`. VERIFIED via search snippet of docs.slack.dev/apis/web-api/rate-limits (2026-09-27).

Why it matters:
- Incoming webhooks cannot thread recovery notices under the original incident message.
- A deleted channel shows up only as a send failure.
- A per-channel URL secret must be stored for every channel.
- Parallel dispatch to one channel gets 429s.

Resolution:
- Use a Slack app with OAuth v2 and bot scopes `chat:write`, `channels:read`, `groups:read`. Private channels require an explicit invite; `chat:write.public` is not used.
- Store one bot token per (tenant, workspace) in Secrets Manager.
- Validate the channel with `conversations.info`.
- Updates and recoveries are `chat.postMessage` with `thread_ts` of the opening message, stored per (incident, destination).
- `invalid_auth`/`token_revoked`/`channel_not_found`/`not_in_channel` are PERMANENT → destination REVOKED/PAUSED.
- Token bucket: 1 msg/s per channel.
- Whether a publicly distributed app faces install policies in enterprise grids is TO VERIFY LIVE and an owner question.

Affects: GOV-006, GOV-102.

### G-GOV-11 · Generic webhook signing, SSRF defences and disclosure need an exact scheme
Severity: HIGH · Type: GAP / VENDOR-FACT
Evidence:
- `governance.md`: "signed timestamp/event ID and secret rotation. Block private/link-local/metadata IPs, revalidate DNS on connection, reject redirects… defend IPv6 equivalents and DNS rebinding".
- Standard Webhooks spec: headers `webhook-id`, `webhook-timestamp`, `webhook-signature`; signed content `msg_id.timestamp.payload`; `v1,<base64 HMAC-SHA256>`; secret `whsec_` base64 of 24–64 bytes; "During secret rotation… Both signatures are sent space delimited"; "Keep… payloads… smaller than 20kb"; SSRF via "proxying webhook requests through filters that block internal IPs". VERIFIED (github.com/standard-webhooks/standard-webhooks spec, 2026-09-27).
- Smokescreen is "a HTTP CONNECT proxy" that "resolves each domain name… and ensures that it is a publicly routable IP address". VERIFIED (github.com/stripe/smokescreen, 2026-09-27); its IPv6 handling is TO VERIFY LIVE.

Why it matters: a home-grown signature format forces custom verification code on every customer. Validating DNS without pinning the connection leaves rebinding open. IPv4-mapped and NAT64 IPv6 forms bypass naive deny lists.

Resolution:
- **Signing**: adopt Standard Webhooks v1 symmetric signing.
  - `webhook-id` = logical delivery id.
  - Secret = `whsec_` + 32 random bytes.
  - Rotation overlap: 24 h by default, 7 days max.
  - Receiver guidance: 5-minute timestamp tolerance; dedupe by webhook-id.
  - Payload ≤ 64 KB hard, ≤ 20 KB target.
- **URL rules**: https only; port 443; no userinfo; hostname required (no IP literals); IDN normalized to punycode.
- **Resolution**: resolve A and AAAA with Bridge's own resolver. Reject if *any* address is in the deny list:
  - IPv4: 0/8, 10/8, 100.64/10, 127/8, 169.254/16, 172.16/12, 192.0.0/24, 192.0.2/24, 192.168/16, 198.18/15, 198.51.100/24, 203.0.113/24, 224/4, 240/4.
  - IPv6: ::/128, ::1, fc00::/7 (covers AWS IMDS fd00:ec2::254), fe80::/10, ff00::/8, 2001:db8::/32, 100::/64.
  - Embedded-IPv4 forms are checked recursively: ::ffff:0:0/96, 64:ff9b::/96, 2002::/16, 2001::/32.
- **Connection**: connect to the validated IP with SNI/Host = hostname (pinned), through the Smokescreen egress proxy in an isolated subnet.
- **Redirects and responses**: never follow redirects (3xx → PERMANENT `REDIRECT_NOT_ALLOWED`); read at most 8 KB of the response; connect timeout 5 s, total 10 s.
- **Per attempt**: re-resolve and re-validate on every attempt.
- **Disclosure**: channel destinations carry `authorized_scope` (the creator's scope, revalidated) and `disclosure_level`. SUMMARY carries no amounts or names; STANDARD carries amounts and labels within scope. SQL text is never included.

Affects: GOV-006, GOV-007, GOV-102.

### G-GOV-12 · SES: production access, authentication records and bounce/complaint handling are not designed
Severity: MEDIUM · Type: GAP / VENDOR-FACT
Evidence:
- `governance.md`: "Use SES verified domains/DKIM and production-access gate; sandbox messages are only to approved test recipients".
- AWS: sandbox allows "a maximum of 200 messages per 24-hour period"; configuration-set event destinations publish BOUNCE and COMPLAINT events to SNS; the account-level suppression list auto-adds hard bounces and complaints. VERIFIED via search snippets of docs.aws.amazon.com/ses (request-production-access, monitor-sending-activity-using-notifications), 2026-09-27.

Why it matters: without a bounce/complaint pipeline, SES reputation drops and sending pauses for **all** tenants. Production access has lead time.

Resolution:
- Dedicated subdomain `notify.<bridge-domain>` per environment.
- Easy DKIM (2048-bit); custom MAIL FROM `bounce.notify.…` for SPF alignment; DMARC `p=quarantine`, moving to `reject` after 30 clean days, with `rua` reporting.
- Configuration set → SNS → SQS (+DLQ) for BOUNCE, COMPLAINT, DELIVERY, REJECT and DELIVERY_DELAY. Hard bounce marks the tenant user's email UNDELIVERABLE. Complaint opts that user out of email for that tenant. Account-level suppression is on.
- Alarms: complaint rate > 0.1%, bounce rate > 2%.
- Staging stays in the sandbox with verified recipients only. Request production access in GOV-102 week 1.

Affects: GOV-006, GOV-102.

### G-GOV-13 · The logical delivery key includes template version (duplicates on deploy); "secure link" is undefined
Severity: MEDIUM · Type: CONTRADICTION / AMBIGUITY
Evidence:
- GOV-007: "Logical delivery key event/destination/template version".
- `governance.md`: "secure investigation link"; "Reauthorize… secure-link access".
- `security.md`: "Never store tokens in localStorage or URL parameters".

Why it matters: deploying a new template during a retry window changes the key and produces a second logical delivery. A tokenized "secure link" in an email would contradict security.md, and forwarded emails would grant access.

Resolution:
- `logical_delivery_id = uuid5(event_id, destination_id)`, where `event_id = (incident_id, transition_seq)`.
- `template_version` and `destination_version` are pinned at the first attempt.
- Secure links are plain deep links (`/govern/incidents/{id}`) with no tokens. Opening one requires a session, the scope is rechecked, a foreign incident returns a non-enumerating 404, and the post-login redirect accepts only validated relative paths.

Affects: GOV-007, GOV-008.

### G-GOV-14 · PRD premium alert example includes "Likely avoidable cost", which governance forbids inventing
Severity: MEDIUM · Type: CONTRADICTION
Evidence:
- PRD §96 example: "Likely avoidable cost $2.1K–$3.0K/day".
- `governance.md`: "Never invent likely savings or cause".
- `intelligence.md`: "Suppress a numerical estimate when required utilization or rates are unavailable".

Why it matters: a fabricated savings range in an alert is a financial claim with no evidence, and it would be delivered to external channels.

Resolution: the alert composer may include a savings line only when a **validated INS opportunity** (INS-001 publication) exists for the same scope, window and currency. The line quotes its range, confidence method and link. Otherwise the line is omitted. "Main contributor" lines come only from verified attribution (top ≤ 3 children by delta within the destination's authorized scope). This refines PRD §96.

Affects: GOV-007, INS-001.

### G-GOV-15 · With `minimum_data_status: FINAL`, D-13 horizons delay cost alerts by 1–3 days
Severity: MEDIUM · Type: RISK
Evidence:
- `governance.md` command example: `"minimum_data_status": "FINAL"`.
- D-13: "WMH… FINAL at hour_end+24h… USAGE_IN_CURRENCY_DAILY at date_end+72h".

Computation: a spike on day D becomes FINAL at the earliest at D+1 24:00 (+24 h) for metering, or D+4 for currency billing. Sustained confirmation (2 distinct days) then adds another day, so first notification comes at D+2…D+5.

Why it matters: "alerts" that arrive after the budget is already blown undermine the monitor product.

Resolution:
- Default `minimum_data_status` = PROVISIONAL for spend, threshold and anomaly monitors. Messages show the data status, and later corrections flow through DATA_CORRECTION semantics (G-GOV-08).
- FINAL is the default only for budget monitors on currency-billed scopes and anything chargeback-related.
- The monitor editor shows the estimated detection delay computed from the D-13 registry.

Affects: GOV-003, GOV-004.

### G-GOV-16 · Budget arithmetic edge cases and calendars are underspecified
Severity: MEDIUM · Type: AMBIGUITY
Evidence:
- `governance.md`: "explicit fiscal calendars are configuration"; "Burn rate uses complete observed days"; "Zero budget has null variance percentage"; "Unavailable currency conversion blocks mixed-currency budget evaluation".
- GOV-001 failures: "partial day; scope changed mid period; deleted owner".

Why it matters: days remaining, burn rate and revision semantics each have two plausible readings that give different numbers.

Resolution (pure functions, Decimal):
- `last_complete_date` = min over the scope's required sources of the last complete UTC date at the required status.
- `complete_days = last_complete_date − start + 1`.
- `burn_rate = actual / complete_days`, with unit "<CUR>/day"; null when complete_days = 0.
- `days_remaining = end − (last_complete_date + 1)`. This includes source-lagged days, per the governance "forecast remaining… includes source-lagged unobserved days".
- `remaining = amount − actual`. `variance = actual − amount`. `variance_pct = variance/amount`, or null when amount = 0.
- Amount changes create a revision effective immediately; history is kept.
- A scope edit applies to the whole period (actual always equals "current scope over the period"); prior scopes stay in revision history.
- Calendars in R1: month, quarter or year with `fiscal_year_start_month`. Custom 4-4-5 and explicit period lists are R2 (GOV-104). All periods are UTC dates.
- Mixed currency: 422 `MIXED_CURRENCY_SCOPE` listing the accounts.
- Unpriced spend (null cost) or partial coverage gives status `UNKNOWN_RISK`, never "under budget".
- Owner removal moves the budget to the FinOps Admin queue.

Affects: GOV-001, GOV-002.

### G-GOV-17 · Over-serialized and missing dependency edges (incl. INS and RPT)
Severity: MEDIUM · Type: RISK
Evidence (task-index.json):
- GOV-001←ALC-007 (showback UI); GOV-003←API-006 (public API credentials); GOV-002←WRK-005 (workload comparison); GOV-004←GOV-002 (all monitors wait on forecasting).
- GOV-005←GOV-004 and INS-001←GOV-005, so insights wait for the whole monitor engine to reuse pure statistics functions.
- GOV-006←GOV-004 (adapters wait for incident state).
- GOV-008←UX-008 (a whole-product UX validation task).
- GOV-006→GOV-007→GOV-008 lies on the 73-task LCH path (`… GOV-006 → GOV-007 → GOV-008 → RPT-003 …`).

Resolution:
- New GOV-101 statistics library depending only on FND-004. INS-001: −GOV-005 +GOV-101 (outside this domain; flagged to INS).
- GOV-001: −ALC-007 +API-002 +CTL-005 (+ALC-102 for team scope only).
- GOV-002: −WRK-005 +GOV-101 +ORC-005.
- GOV-003: −API-006 +API-002 +CTL-005.
- GOV-004: −GOV-002 (forecast_breach step only) +GOV-101 +CTL-004.
- GOV-006: −GOV-004 +GOV-102 +CTL-004.
- GOV-007: +GOV-004 +SEC-006.
- GOV-008: −UX-008 +UX-002 (UX-008 should instead depend on GOV-008).

Affects: all GOV tasks, INS-001, UX-008.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by |
|---|---|---|
| `data/contracts/budget.json` + PG DDL | Budget schema (scope = semantic filter JSON; metric spend/allocated_spend + book_id; currency; period calendar + fiscal_year_start_month + [start,end) UTC dates; amount ≥ 0 decimal string; owner; thresholds [{measure ACTUAL/FORECAST, pct}]; allocation_version_policy); `governance.budgets`, `budget_revisions(effective_from)` | GOV-001-S01/S02 |
| Budget formula sheet | Exact formulas of G-GOV-16 with the 280/150 fixture and the zero-budget, zero-day and partial-coverage cases | GOV-001-S06 |
| `packages/bridge_stats` API | median (even-length mean of middle two), mad, robust_z(→ score or None + method), impact_floor, mad_zero_rule, weekday_cohort(min 8, lookback 56), run_rate, seasonal_naive, theil_sen(56), rolling_origin_folds(4×7, SN 28/TS 56), mae; every function carries `algorithm_version` | GOV-101 |
| `data/contracts/forecast.json` + `py_forecast` DDL | Key (tenant, scope_ref, period, model_version, input_publication_id); model ∈ INSUFFICIENT_HISTORY/RUN_RATE_FALLBACK/SEASONAL_NAIVE/THEIL_SEN; training window; history_days; point_total; remaining_estimate; interval_low/high NULL + interval_status; backtest metrics; eligibility_reason; adjustments_added | GOV-002-S01 |
| `data/contracts/monitor.json` (JSON Schema 2020-12) | Top level: name, dataset, metric+version, currency, scope, window oneOf {last_complete_day, trailing_complete_days n 1–31, trailing_complete_hours n (ops only), month_to_date}, condition oneOf 12 types, partition_by ≤ 3 dims, max_partitions, partition_overflow, schedule.every_minutes ∈ {5 (PG ops datasets only), 60, 1440}, coverage_policy, minimum_data_status, breach/recovery_evaluations 1–10, cooldown_seconds 0–604800, severity, destination_ids ≤ 10; decimals as `^-?\d{1,20}(\.\d{1,12})?$` strings; additionalProperties false; ≤ 16 KB | GOV-003-S01/S02 |
| Condition catalog | Parameters and semantics for static_threshold, relative_threshold, results_found, period_comparison, anomaly, budget_breach, forecast_breach, new_resource, cost_regression, missing_activity, sla_violation, sync_failure; dataset each applies to (Snowflake vs PG) | GOV-003-S02 |
| Observation DDL | `fct_monitor_observation` key per G-GOV-01; result enum BREACH/OK/INSUFFICIENT_DATA; insufficient_reason; supersedes | GOV-004-S01 |
| Tracker/incident PG DDL + transition table | `monitor.condition_trackers`, `incident_workflow`, `incident_events`, `silences`; unique partial index; transition table of G-GOV-08 | GOV-004-S05/S06 |
| Planner batching spec + cost model | Batch key; skip rule; per-tenant query budget; expected queries/day formula | GOV-003-S08, GOV-103 |
| Destination DDL + adapter interface | `monitor.destinations` (type, version, config, secret_ref, status, disclosure_level, authorized_scope); `send(delivery, payload) → AttemptResult{outcome ∈ ACCEPTED, ACCEPTED_BY_PROVIDER, TRANSIENT, PERMANENT, RATE_LIMITED; retry_after; provider_ref}` | GOV-006-S01/S02 |
| Webhook spec | Standard Webhooks v1 headers and signature; rotation; event envelope JSON Schema `incident.v1` (type, id, created_at, schema_version, incident{id, monitor_id, name, partition labels, state, severity, window, metric, value, threshold, impact{absolute, currency, relative}, data_status, source_as_of, link}); receiver verification guide | GOV-006-S08, GOV-007-S08 |
| SSRF deny list + validator | IPv4/IPv6 ranges and embedded-IPv4 rules of G-GOV-11; the error code table | GOV-006-S09 |
| Retry and classification table | Schedule +0, +1 m, +5 m, +15 m, +1 h, +3 h, +8 h, +20 h (±20% jitter; ≤ 24 h; 8 attempts); Retry-After ≤ 1 h honored; 2xx ok; 408/425/429/5xx/timeouts transient; 3xx/400/401/403/404/410/413/422 permanent | GOV-007-S03 |
| Templates | Email HTML+text, Slack Block Kit (≤ 50 blocks, section ≤ 3,000 chars), Teams Adaptive Card, webhook JSON; truncation rules; snapshot fixtures | GOV-007-S08 |
| Error codes | `MIXED_CURRENCY_SCOPE, BUDGET_SCOPE_UNAUTHORIZED, PARTITION_CARDINALITY, METRIC_VERSION_UNSUPPORTED, CONDITION_INVALID, TEAMS_LEGACY_URL, WEBHOOK_URL_FORBIDDEN, REDIRECT_NOT_ALLOWED, DESTINATION_PAUSED, INVALID_TRANSITION, SILENCE_EXPIRY_REQUIRED` | each task |

## 4. Revised production backlog

### GOV-001 — Implement scoped budgets and actuals
Release: R1 (custom calendars R2 → GOV-104) · Estimate: 42–60 h · Risk: M · Decisions: D-02, D-04, D-12, D-13 · Closes: G-GOV-04, G-GOV-05 (budgets), G-GOV-16
Dependency changes: `−ALC-007` (org/account/service budgets do not need showback), `+API-002` (planner), `+CTL-005` (config publication); `+ALC-102` only for S03's team-scope path.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| GOV-001-S01 | Author the budget JSON Schema (scope reuses the analytics filter schema; metric + book_id; period; thresholds; allocation_version_policy) | `data/contracts/budget.json` | Positive and negative suites pass; SQL-like values rejected | 3 |
| GOV-001-S02 | Create PG `governance.budgets`, `budget_revisions(effective_from)` with FORCE RLS and composite FKs | migration | An amount edit creates a revision; history is queryable | 3 |
| GOV-001-S03 | Validate: registry metric and dimensions; scope ⊆ owner grants; single native currency across scope accounts (else 422 `MIXED_CURRENCY_SCOPE` listing accounts); team dimension requires allocated_spend + book_id | `apps/api/budgets/validate.py` | EUR+USD accounts → 422 with both listed; a Finance Team Admin cannot budget Marketing | 3 |
| GOV-001-S04 | Implement the R1 period generator (month/quarter/year, fiscal_year_start_month) with boundary tests | `apps/api/budgets/periods.py` | FY starting Feb: Q1 = Feb 1–May 1 [); leap Feb 29 included; year crossing correct | 3 |
| GOV-001-S05 | Build the actuals daily series via the semantic planner (no new SQL formula), run as the owner's profile role through the broker's JOB class (API-002; RECONCILIATION C-09) and batched per (tenant, profile); `last_complete_date` from D-13 | `data/dbt/models/marts/budgets/mart_budget_actual_daily.sql` + batch job | Actual equals the Explorer `spend` for the same scope/period (150.00) | 4 |
| GOV-001-S06 | Implement the pure derived measures (remaining, variance, variance_pct, burn_rate, days_remaining, forecast refs) | `packages/budgets/measures.py` | 280/150 → remaining 130, burn 10/day; zero budget → pct null + absolute overrun; zero complete days → burn null | 3 |
| GOV-001-S07 | Keep overlapping budgets independent: list/detail responses have no cross-budget total field | API + UI | Schema has no sum field; UI shows no total row | 1 |
| GOV-001-S08 | Handle partial data: coverage < 100% on any day → PARTIAL; unpriced spend → `UNKNOWN_RISK`, never under-budget | measures + API | Fixture with a null-cost day shows UNKNOWN_RISK | 2 |
| GOV-001-S09 | Implement `/v1/budgets` CRUD and `GET /v1/budgets/{id}/status` (pins publication, meta incl. allocation publication) with Idempotency-Key and If-Match | `apps/api/budgets` | Contract tests; stale If-Match → 409 | 4 |
| GOV-001-S10 | Owner lifecycle: owner removed → FinOps Admin queue; owner scope reduced → budget PAUSED_AUTH | API + job | Tests pass; the audit event is emitted | 2 |
| GOV-001-S11 | Publish the budget config via the config-publisher (D-04) for evaluation and forecasting | CTL-005 handler | A config_version exists in Snowflake after publish | 2 |
| GOV-001-S12 | Build the budgets list and new-budget UI (zero-budget explanation, currency block message) | `apps/web/budgets` | Playwright UX matrix passes | 4 |
| GOV-001-S13 | Build the budget detail UI (actual/remaining/burn/days remaining, coverage and status labels, drilldown to explorer) | `apps/web/budgets/detail` | 390 px and keyboard checks pass | 4 |
| GOV-001-S14 | Add authorization tests: foreign budget → 404; Viewer read-only; restricted Finance owner reads allocated_spend only | API tests | All pass | 2 |
| GOV-001-S15 | Record observability (evaluation lag, UNKNOWN_RISK count) and evidence | runbook + evidence | Complete | 2 |

Task acceptance:
- [ ] Actual equals the Explorer value for the same scope (150); remaining 130; burn 10 USD/day.
- [ ] Zero budget → null percentage plus absolute overrun; mixed currency is blocked with an account list.
- [ ] Overlapping budgets are never summed; team budgets use allocated_spend on one book.
- [ ] Partial or unpriced data never shows "under budget".

### GOV-002 — Implement forecasting (R1: run-rate + seasonal-naive)
Release: R1 (Theil–Sen, selection and intervals → GOV-105 R2) · Estimate: 30–43 h · Risk: M · Decisions: D-13 · Closes: G-GOV-02 (R1 part)
Dependency changes: `−WRK-005`, `+GOV-101`, `+ORC-005` (triggered by publication events), `+ORC-103` (`py_forecast` lands through ORC-103's writer; RECONCILIATION U-18, C-09); keep GOV-001.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| GOV-002-S01 | Author the forecast contract and `py_forecast` DDL (insert-only, key incl. input_publication_id) | `data/contracts/forecast.json` | Schema suite passes | 3 |
| GOV-002-S02 | Build the series builder: complete UTC calendar days; gross recurring vs signed exceptional adjustments (FIN entry_kind); coverage gap = null, zero-activity complete day = 0 | `services/intelligence/forecast/series.py` | Missing day stays null (not 0); rebate day separated | 3 |
| GOV-002-S03 | Apply the eligibility ladder for R1: h < 7 INSUFFICIENT_HISTORY; 7–27 RUN_RATE_FALLBACK; ≥ 28 SEASONAL_NAIVE (mean of last 4 same weekdays); a gap inside the required window falls back to run-rate over the contiguous tail ≥ 7 | `services/intelligence/forecast/select.py` | Table-driven tests for h = 6, 7, 27, 28 and a gap on day 20 | 3 |
| GOV-002-S04 | Compute remaining dates from last_complete_date+1 to end−1 inclusive (lagged days included); forecast_total = actual + Σ predictions + approved scheduled adjustments | `forecast/project.py` | 15 days × 10 → 300; with a 2-day source lag remaining days are still counted | 2 |
| GOV-002-S05 | Handle adjustments: extrapolate only the gross stream; add future credits only from approved scheduled changes; never extrapolate historical refunds | `forecast/adjust.py` | A −50 refund in history does not reduce the forecast | 2 |
| GOV-002-S06 | Build the Dagster asset `forecast_budgets`: one series read per (tenant, profile role), submitted as a server-signed batch plan to the broker's JOB class (API-002) — no GOV process holds serving credentials — triggered by ORC-005 publication, writing results through ORC-103's writer under the central writer identity (RECONCILIATION C-09, U-18, C-17) | `services/intelligence/forecast/asset.py` | Per tenant, one Snowflake read per profile per publication | 4 |
| GOV-002-S07 | Make runs idempotent: forecast key → identical row on rerun; a newer publication supersedes | tests | Byte-identical output on replay | 2 |
| GOV-002-S08 | Add statistical fixtures: constant 10/day; Mon 20/others 10 over 35 days → Mondays 20; abrupt growth (SN lags, documented limitation); all-zero; refund day; missing period | `tests/statistics/forecast/` | Expected values independently computed | 4 |
| GOV-002-S09 | Implement `GET /v1/budgets/{id}/forecast` returning method, history days, limitations, interval null + UNCALIBRATED | API | Contract test; no "90%" text anywhere | 2 |
| GOV-002-S10 | Build the forecast panel and methodology page (training period, input publication, eligibility, limitations) | `apps/web/budgets/forecast` | UX matrix passes | 3 |
| GOV-002-S11 | Record observability (forecast lag after publication, model mix) and evidence | runbook + evidence | Complete | 2 |

Task acceptance:
- [ ] The 280/150 fixture forecasts 300 labelled RUN_RATE_FALLBACK, forecast variance 20 (7.142857…%).
- [ ] Missing days are never zero-filled; insufficient history is labelled, not forecast.
- [ ] No interval is published in R1 (null + UNCALIBRATED).
- [ ] Forecasts are keyed by input publication and reproducible.

### GOV-003 — Define monitor DSL, validation and schedule planner
Release: R1 · Estimate: 45–64 h · Risk: H · Decisions: D-02, D-04, D-13, D-17 · Closes: G-GOV-01 (identity), G-GOV-06, G-GOV-07 (validation), G-GOV-15
Dependency changes: `−API-006` (public credentials not needed), `+API-002`, `+CTL-005`; GOV-001 kept only for budget_breach/forecast_breach validation (S02).

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| GOV-003-S01 | Author the monitor JSON Schema (top level, window kinds, schedule values, limits) | `data/contracts/monitor.json` | Invalid `every_minutes: 7` → rejected; 17 KB doc → rejected | 4 |
| GOV-003-S02 | Author the 12 condition sub-schemas and the condition catalog (params, dataset: Snowflake vs PG ops) | `data/contracts/monitor-conditions.json` + doc | One positive and one negative payload per type | 4 |
| GOV-003-S03 | Validate against the registry: metric/version, dataset, partition dims, filters, currency policy, allowed minimum_data_status, anomaly requires a daily additive metric, missing_activity requires a coverage signal | `apps/api/monitors/validate.py` | Unsupported metric version → 422 `METRIC_VERSION_UNSUPPORTED` | 3 |
| GOV-003-S04 | Validate scope ⊆ creator grants and destinations authorized for scope and disclosure level | validator | Foreign destination id → 404; broader scope → 403 | 2 |
| GOV-003-S05 | Estimate cardinality with a dry-run (distinct partition keys, last 30 days, in scope); enforce max_partitions/overflow | validator + planner call | 1,200 users with cap 500 → 422 `PARTITION_CARDINALITY` unless TOP_N_PLUS_OTHER | 3 |
| GOV-003-S06 | Create PG `monitor.definitions`, `monitor_versions`; condition_version bumps only on condition/metric/window/partition/scope/coverage change | migrations | Changing destinations keeps condition_version; changing the threshold bumps it | 3 |
| GOV-003-S07 | Implement `/v1/monitors` CRUD, `:validate` and `:dry-run` (last 7 windows at the current publication; no incidents or notifications) | `apps/api/monitors` | Dry-run shows would-be episodes; zero rows written to incidents/outbox | 4 |
| GOV-003-S08 | Build the planner: 5-minute Dagster schedule; due monitors → batches keyed (tenant, profile_role, dataset, window, publication); skip already-observed; deterministic run keys; fenced lease | `services/monitor/planner.py` | 24 hourly ticks over one daily window → 1 evaluation | 4 |
| GOV-003-S09 | Resolve windows (last_complete_day from D-13 per tenant/sources; trailing days/hours; month_to_date); UTC only in R1 | `services/monitor/windows.py` | Tests at month end, leap day and source-lag boundaries | 3 |
| GOV-003-S10 | Enforce the cost guard: per-tenant query budget (60/h default), global budget, deferral metric | planner | Overflow defers low-severity batches; the metric is emitted | 2 |
| GOV-003-S11 | Route datasets: sync_failure/sla_violation evaluate from PG sync state (no Snowflake) | planner routing | SLA monitor tick issues 0 Snowflake queries | 2 |
| GOV-003-S12 | Add tests: injected expression in value → 422; unsupported metric → 422; all 12 types dry-run on fixture snapshots; missing source → INSUFFICIENT_DATA | `tests/spec/GOV-003/` | All pass | 4 |
| GOV-003-S13 | Build the monitor-creation UI with capability-mapped templates, dry-run results, partition warning and estimated detection delay (G-GOV-15) | `apps/web/monitors/new` | Playwright UX matrix passes | 4 |
| GOV-003-S14 | Record observability (planner lag, skip ratio, deferred batches) and evidence | runbook + evidence | Complete | 3 |

Task acceptance:
- [ ] One generic engine handles all 12 condition types; invalid metrics or dimensions fail before scheduling.
- [ ] Re-ticking an unchanged window at the same publication costs zero Snowflake queries.
- [ ] Cardinality above the cap is rejected or explicitly bounded as top-N + `__other__`.
- [ ] Sync/SLA monitors run without Snowflake.

### GOV-004 — Implement partition evaluation, incident state and suppression
Release: R1 · Estimate: 47–67 h · Risk: H · Decisions: D-02, D-05, D-10 · Closes: G-GOV-01, G-GOV-05, G-GOV-07, G-GOV-08
Dependency changes: `−GOV-002` (only S03's forecast_breach evaluation needs it; it moves to a follow-up step gated on GOV-002), `+GOV-101`, `+CTL-004` (outbox).

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| GOV-004-S01 | Write the observation DDL (insert-only; key per G-GOV-01; supersedes) | `data/dbt/models/marts/monitor_events/fct_monitor_observation` DDL | Contract test passes | 3 |
| GOV-004-S02 | Build the batch evaluator SQL: one query per batch via the `cfg_monitor_scope` join, submitted as a server-signed batch plan keyed (tenant, profile role, dataset, window, input publication) to the broker's JOB class (API-002), which sets the profile role (RECONCILIATION C-09), partition key = canonical JSON of stable IDs, overflow top-N + `__other__` | `services/monitor/evaluator.py` + SQL templates (bound parameters) | Batch of 20 monitors → 1 query; results equal 20 single queries | 4 |
| GOV-004-S03 | Evaluate conditions in Python (Decimal; bridge_stats for anomaly); null/incomplete → INSUFFICIENT_DATA with reason; complete zero-day = 0 | `services/monitor/conditions.py` | Null cost → INSUFFICIENT_DATA(`UNPRICED`); zero spend → OK for gt 100 | 3 |
| GOV-004-S04 | Re-evaluate on corrections: windows within lookback (7 windows or since the oldest active episode, ≤ 35 days) when a newer publication revises them | planner hook | Revised D2 produces a superseding observation | 3 |
| GOV-004-S05 | Build the tracker as a pure fold over distinct windows; transactional upsert with `SELECT … FOR UPDATE`; unique partial index on active episodes | `services/monitor/tracker.py` + migration | 20 parallel evaluations of the same key → 1 active incident | 4 |
| GOV-004-S06 | Implement the full transition table (G-GOV-08) incl. cooldown, manual resolve, DATA_CORRECTION, DEFINITION_CHANGED, MONITOR_DISABLED, PAUSED_AUTH | `services/monitor/transitions.py` | Table-driven test covers every row | 4 |
| GOV-004-S07 | Implement silences (scope, owner, reason, expiry ≤ 30 d, default 24 h) and the one-time "still active" on expiry | `monitor.silences` + job | Silence without expiry → 422 `SILENCE_EXPIRY_REQUIRED`; expiry emits exactly one event | 3 |
| GOV-004-S08 | Emit outbox events `incident.opened/updated/recovered/resolved_manual` with event_id = (incident_id, seq) | outbox writer | Duplicate transition → no second event | 2 |
| GOV-004-S09 | Run the corrected static fixture D1…D6, 23 extra hourly ticks and 100 retries of D2 | `tests/spec/GOV-004/test_static_fixture.py` | 1 incident, occurrence 3, RESOLVED(OBSERVED_RECOVERY) at D6, 1 opening notification | 3 |
| GOV-004-S10 | Run the late-correction fixture: D2 102→95 after opening → RESOLVED(DATA_CORRECTION) + notification | test | Exactly 1 correction notification | 3 |
| GOV-004-S11 | Handle missing activity and stale sources: stale ingestion → INSUFFICIENT_DATA, never a "no activity" breach | test | Stale source fixture yields no incident | 2 |
| GOV-004-S12 | Test partition rename (stable id keeps the episode) and overflow labelling | tests | Rename → same incident id | 2 |
| GOV-004-S13 | Test concurrency and lease loss: two workers on one batch → fenced; the old worker cannot write observations | test | Only the fenced owner's observation lands | 3 |
| GOV-004-S14 | Build the incident read API (list/detail/timeline) used by GOV-008, scope-checked per partition | `apps/api/incidents` | Foreign incident → 404 | 3 |
| GOV-004-S15 | Add the follow-up step (gated on GOV-002): forecast_breach evaluation reading `py_forecast` at the pinned publication | condition + test | Forecast 300 > budget 280 → BREACH with impact +20 | 2 |
| GOV-004-S16 | Record observability (evaluations, skip ratio, insufficient ratio, publication→observation latency, lag > 2 h alarm), runbook and evidence | runbook + evidence | Complete | 3 |

Task acceptance:
- [ ] Confirmation counts distinct windows; re-ticks and retries add no observation, occurrence or notification.
- [ ] At most one active episode per key under concurrency; renames keep the episode.
- [ ] INSUFFICIENT_DATA never increments counters and never resolves.
- [ ] Corrections that erase a breach resolve as DATA_CORRECTION with one notification.
- [ ] Monitors run under the owner's profile role; loss of scope pauses the monitor.

### GOV-005 — Implement robust anomaly candidates and quality gates
Release: R1 · Estimate: 18–26 h · Risk: M · Decisions: D-10 · Closes: G-GOV-03, G-GOV-07 (digest)
Dependency changes: `+GOV-101` (statistics moved there), `+ORC-103` (`py_anomaly_candidate` lands through ORC-103's writer; RECONCILIATION U-18); GOV-004 kept (monitor integration). GOV-005 is the anomaly evaluator; INS-003's Q07 calls it (INS-003 +GOV-005; U-09).

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| GOV-005-S01 | Build the anomaly condition evaluator on bridge_stats: baseline = previous 28 complete days excluding the current day, from first_seen; weekday cohort = 8 same weekdays within 56 days; < 28 obs → INSUFFICIENT_HISTORY | `services/intelligence/anomaly/evaluate.py` | A Monday series with 8 prior Mondays uses the cohort; 7 prior → 28-day baseline | 3 |
| GOV-005-S02 | Split gross-positive and refund streams; write through ORC-103's writer (RECONCILIATION U-18, C-17) `py_anomaly_candidate` (baseline median, MAD, score or null, method ROBUST_Z/ABSOLUTE_DEVIATION, impact signed and abs, sample count, coverage, model version, publication) | DDL + writer | A refund spike flags only in the refund stream | 3 |
| GOV-005-S03 | Version the parameter set `anomaly_v1` (3.5, 10%, 20% MAD0, ISO-4217 minor units) | `data/contracts/anomaly.json` | Parameters persisted with every candidate | 1 |
| GOV-005-S04 | Build the digest: ≤ 10 candidates per tenant/evaluation ranked by absolute impact, grouped by parent resource; suppressed candidates inspectable | `anomaly/digest.py` | 10k-partition noise fixture → ≤ 10 delivered; the rest listed as suppressed | 3 |
| GOV-005-S05 | Suppress candidates inside declared scheduled changes (actions or user-declared) with a label | `anomaly/planned.py` | Planned change window → labelled suppression | 2 |
| GOV-005-S06 | Add fixtures: 100/MAD10/160 → 4.0469445568…, impact 60, flag; constant 100 → MAD0; 101 suppress; 130 flag; exact 3.5 flags; missing current → no eval; missing baseline → `MISSING_BASELINE` | `tests/statistics/anomaly/` | Independently computed values match | 3 |
| GOV-005-S07 | Add a CI lint forbidding forks: the constant `1.4826` or median/MAD implementations outside `packages/bridge_stats` fail the build (INS reuse) | CI rule | A deliberate fork fails CI | 1 |
| GOV-005-S08 | Record observability (candidates/day, suppression ratio) and evidence | evidence | Complete | 2 |

Task acceptance:
- [ ] The anomaly fixture scores 4.04694456 (8 dp) and flags; the MAD=0 fallbacks behave as specified.
- [ ] Positive and refund streams are independent; missing data suppresses, zero spend does not.
- [ ] The digest caps notifications at 10 per tenant/evaluation; INS imports the same library.

### GOV-006 — Implement Email, Slack, Teams and secure webhook adapters
Release: R1 (Email, Slack, Webhook); Teams R1* · Estimate: 44–62 h · Risk: H · Decisions: D-20 (Teams), D-23 · Closes: G-GOV-09, G-GOV-10, G-GOV-11, G-GOV-12
Dependency changes: `−GOV-004` (adapters are independent of incident state), `+GOV-102` (infrastructure), `+CTL-004`; keep SEC-008 and INF-003.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| GOV-006-S01 | Create the destinations PG DDL (type, version, config, secret_ref, status, disclosure_level, authorized_scope) with FORCE RLS | migration | Secrets never stored in PG (column check) | 3 |
| GOV-006-S02 | Define the adapter interface and result classification with connect 5 s / total 10 s timeouts | `services/notifications/adapters/base.py` | Contract tests pass | 2 |
| GOV-006-S03 | Build the email adapter: SES v2 SendEmail with configuration set; one message per recipient; recipients must be tenant members with a verified email; suppression check | `adapters/email.py` | Sandbox receipt to a verified test recipient | 3 |
| GOV-006-S04 | Build the bounce/complaint consumer (SQS): hard bounce → UNDELIVERABLE; complaint → opt-out; idempotent by SES message id | `adapters/ses_events.py` | Duplicate SNS message processed once | 3 |
| GOV-006-S05 | Build the Slack OAuth v2 install (state CSRF, tenant binding), channel picker and `conversations.info` validation, `chat.postMessage` with thread_ts | `adapters/slack.py` + API | Test-workspace receipt; recovery posts in the incident thread | 4 |
| GOV-006-S06 | Build the Slack events endpoint for `tokens_revoked`/`app_uninstalled`, verified with the signing secret and a 5-minute tolerance | API route | Forged signature → 401; revoke → destination REVOKED | 2 |
| GOV-006-S07 | Build the Teams adapter (R1*): host/path validation, legacy URL rejection, Adaptive Card envelope, ACCEPTED_BY_PROVIDER, 4xx → PERMANENT remediation | `adapters/teams.py` | `logic.azure.com` URL → 422 `TEAMS_LEGACY_URL`; sandbox tenant receipt | 3 |
| GOV-006-S08 | Build the webhook adapter: Standard Webhooks v1 signing, rotation with dual signatures, 64 KB cap | `adapters/webhook.py` | The reference verifier (standardwebhooks lib) accepts both signatures during rotation | 3 |
| GOV-006-S09 | Build the URL validator and pinned connector through the egress proxy (G-GOV-11 rules; re-resolve per attempt; no redirects; 8 KB response cap) | `adapters/net_guard.py` | Unit and integration tests pass | 4 |
| GOV-006-S10 | Run the SSRF suite: 169.254.169.254, [fd00:ec2::254], 127.0.0.1, 10.0.0.1, [::ffff:10.0.0.1], [64:ff9b::a00:1], decimal 2130706433, rebinding (TTL 0 public/private), redirect to internal, port 8080, http://, userinfo | `tests/security/GOV-006/` | Every case rejected with its error code; the proxy log shows no internal connect | 4 |
| GOV-006-S11 | Implement the destination APIs: create/update (new version), requested test (labelled TEST payload, 5/hour/destination), rotate, pause, delete; secrets write-only | `apps/api/destinations` | Secret never returned; test rate limit enforced | 4 |
| GOV-006-S12 | Add secret hygiene: log scrubber for full Teams URLs, `xoxb-` tokens and `whsec_`; errors never echo URLs | scrubber + tests | Log capture shows no secret patterns | 2 |
| GOV-006-S13 | Build the destinations UI at `/settings/destinations` (configured/verified/degraded, remediation) | `apps/web/destinations` | Playwright UX matrix passes | 4 |
| GOV-006-S14 | Record sandbox evidence for Email, Slack, Webhook (and Teams if R1*); no live customer messages | evidence | Complete | 3 |

Task acceptance:
- [ ] Email, Slack and webhook produce verified sandbox receipts (Teams when R1*).
- [ ] All SSRF vectors, including IPv6-embedded and rebinding, are denied.
- [ ] Webhook signatures verify with the Standard Webhooks reference library, including rotation.
- [ ] Secrets are absent from PG, logs and API responses.

### GOV-007 — Implement delivery outbox, retries, DLQ and premium alerts
Release: R1 · Estimate: 39–55 h · Risk: H · Decisions: D-10, D-18 · Closes: G-GOV-11 (disclosure), G-GOV-13, G-GOV-14
Dependency changes: `+GOV-004` (incident events), `+SEC-006` (reauthorization); keep GOV-006 and CTL-004.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| GOV-007-S01 | Build the delivery model: `logical_delivery_id = uuid5(event_id, destination_id)`, template and destination versions pinned at first attempt; per-recipient rows for email; states PENDING/SENDING/ACCEPTED/RETRY_SCHEDULED/DEAD/SKIPPED_UNAUTHORIZED/SUPPRESSED_SILENCE/CANCELLED | migration + model | A template deploy mid-retry does not create a second logical delivery | 3 |
| GOV-007-S02 | Build the dispatcher: `FOR UPDATE SKIP LOCKED`, fenced lease, per-destination token buckets (Slack 1/s/channel, Teams 1/s/URL, webhook 10/s default, email ≤ SES quota) in Redis with an in-process fallback | `services/notifications/dispatcher.py` | Redis outage → dispatch continues at the fallback rate | 4 |
| GOV-007-S03 | Implement the retry schedule and classification table; honor Retry-After ≤ 1 h | `dispatcher/retry.py` | 429 Retry-After 30 → next attempt ≥ 30 s; 8 attempts max within 24 h | 3 |
| GOV-007-S04 | Handle permanent failure: pause the destination with a remediation code; notify the destination owner | dispatcher | 410 → PAUSED; remaining attempts cancelled | 2 |
| GOV-007-S05 | Implement the DLQ: DEAD after 8 attempts; admin list/replay under the same logical id with current authorization | API + job | Replay after fixing the URL delivers once; alarm on DLQ depth | 3 |
| GOV-007-S06 | Reauthorize at send: recipient membership and scope ⊇ partition; destination authorized_scope still valid → else SKIPPED_UNAUTHORIZED + audit | dispatcher | Recipient revoked between enqueue and send → skipped | 3 |
| GOV-007-S07 | Build the payload composer at send time: what changed, absolute impact + unit/currency, relative (null if baseline 0), window, as-of and data status, top ≤ 3 verified contributors within scope, limitations, deep link; savings only from a validated INS opportunity | `services/notifications/compose.py` | The fixture alert has no savings line without INS evidence | 4 |
| GOV-007-S08 | Build versioned channel templates (email HTML+text sandboxed/autoescaped, Slack Block Kit, Teams card, webhook `incident.v1`) with truncation and snapshot tests; strings externalized (D-18) | `services/notifications/templates/` | Snapshots stable; a 5,000-char label is truncated safely | 4 |
| GOV-007-S09 | Apply the disclosure policy: SUMMARY vs STANDARD; never SQL; user identifiers pseudonymized (D-10) except for authorized email recipients | compose | SUMMARY payload contains no amounts or names (scan test) | 2 |
| GOV-007-S10 | Run the crash matrix: crash after provider accept before ack → a possible external duplicate with the same webhook-id; provider 429; destination revoked mid-retry | `tests/spec/GOV-007/` | One logical delivery record per case; documented duplicate | 4 |
| GOV-007-S11 | Implement deep-link handling: session required, scope recheck, foreign → 404, relative-path-only post-login redirect | web route + API | Open-redirect attempt `//evil.com` rejected | 2 |
| GOV-007-S12 | Write the runbook (SES reputation, Slack revoked, Teams owner removed, DLQ replay, webhook secret rotation) | `docs/runbooks/notifications.md` | Reviewed | 2 |
| GOV-007-S13 | Add observability: event→accepted p95 ≤ 2 min target, attempts, DLQ depth, bounce/complaint alarms | metrics + alarms | Alarms tested in staging | 2 |
| GOV-007-S14 | Record evidence | evidence | Complete | 1 |

Task acceptance:
- [ ] One logical delivery per (event, destination) across retries, crashes and template deploys; external duplicates carry the same id.
- [ ] Retries stop at 8 attempts / 24 h → DLQ; permanent failures pause the destination.
- [ ] Payloads are reauthorized at send and contain no SQL, no secrets, and no savings without INS evidence.
- [ ] Recovery messages reference the same incident and state OBSERVED vs DATA_CORRECTION.

### GOV-008 — Build incident center and governance E2E acceptance
Release: R1 · Estimate: 33–47 h · Risk: M · Decisions: — · Closes: G-GOV-08 (UI), G-GOV-01 (E2E)
Dependency changes: `−UX-008` (inverted: UX-008 should depend on GOV-008), `+UX-002`, `+GOV-002`, `+GOV-005` (the governance E2E acceptance covers forecast and anomaly monitors, which GOV-004 −GOV-002 and INS-001 −GOV-005 had orphaned; RECONCILIATION C-29); keep GOV-007.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| GOV-008-S01 | Implement the workflow APIs `:acknowledge/:assign/:investigate/:resolve(reason)/:silence(expiry)` with If-Match, the transition table, audit and per-partition scope | `apps/api/incidents/workflow.py` | Illegal transition → 409 `INVALID_TRANSITION`; stale revision → 409 | 4 |
| GOV-008-S02 | Build the monitor list/detail UI with an INSUFFICIENT_DATA group separate from healthy, and last-evaluation coverage | `apps/web/monitors` | UX matrix passes | 4 |
| GOV-008-S03 | Build the incident center list (filters, keyset pagination) | `apps/web/incidents` | 10k incidents paginate without offset | 4 |
| GOV-008-S04 | Build the incident detail: timeline (observations, notifications, transitions), evidence panel with explain links | `apps/web/incidents/detail` | Timeline shows the retry not counted | 3 |
| GOV-008-S05 | Distinguish closure types in the UI: MANUAL (actor, reason), OBSERVED_RECOVERY, DATA_CORRECTION, DEFINITION_CHANGED, MONITOR_DISABLED | UI | Each shows distinct text (not color only) | 2 |
| GOV-008-S06 | Build the silence UI: expiry required, ≤ 30 days, silenced incidents visible | UI | No-expiry silence cannot be saved | 2 |
| GOV-008-S07 | Add security tests: foreign incident → 404; user losing scope mid-session → 403 on next action | tests | All pass | 3 |
| GOV-008-S08 | Run the E2E budget 280 / forecast 300: forecast_breach monitor opens after 2 distinct daily windows → sandbox email + Slack + webhook → investigate → resolve; impact +20 USD (7.14%) links to the same budget publication | `tests/e2e/governance/budget_forecast.spec.ts` | All assertions pass with recorded ids | 4 |
| GOV-008-S09 | Run the corrected static fixture D1…D6 through the UI and API | E2E | Occurrence 3; one notification; observed recovery | 3 |
| GOV-008-S10 | Run the UX state matrix and accessibility checks (390 px, keyboard, labels) | Playwright | All pass | 3 |
| GOV-008-S11 | Record evidence | evidence | Complete | 1 |

Task acceptance:
- [ ] The forecast breach +20 links to the same budget data and publication.
- [ ] A user cannot act on a foreign or out-of-scope incident; acknowledgment keeps history.
- [ ] Manual closure, observed recovery and data correction are visibly distinct.

## 5. New tasks required

### GOV-101 — Shared statistics library (`packages/bridge_stats`)
Release: R1 · Estimate: 20–28 h · Risk: M · Decisions: — · Closes: G-GOV-02 (definitions), G-GOV-03, G-GOV-17
Why: GOV-005 and INS-001 need the same pure functions; today INS waits for the whole monitor engine. Plugs in after FND-004 only; required by GOV-002, GOV-004, GOV-005 and INS-001.
Dependency changes: new task; deps `FND-004`; new downstream edges `GOV-002, GOV-004, GOV-005 → GOV-101`; `INS-001: −GOV-005 +GOV-101`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| GOV-101-S01 | Create the package skeleton (pure Python, Decimal only, no I/O) with typed results carrying algorithm_version and parameters | `packages/bridge_stats/` | mypy strict; import has no side effects | 2 |
| GOV-101-S02 | Implement median (even-length mean of the middle two, exact) and MAD | `robust.py` | Parity with `statistics.median` on 10k random Decimal vectors | 2 |
| GOV-101-S03 | Implement robust_z and impact_floor (max(pct·abs(median), minor unit)), the single monetary impact floor, parameterized per tenant/currency with INS-supplied config (INS-001-S04 consumes it; RECONCILIATION U-09); score ≥ 3.5 inclusive | `robust.py` | 100/10/160 → 4.046944556859571… | 2 |
| GOV-101-S04 | Implement the MAD=0 ABSOLUTE_DEVIATION rule (20% or one minor unit; never divide by epsilon) | `robust.py` | 100→101 suppress; 100→130 flag; equal → never flag | 2 |
| GOV-101-S05 | Implement the weekday cohort selector (8 within 56 days) and baseline builder (from first_seen, coverage-gap aware) | `cohorts.py` | Boundary tests at 7/8 prior weekdays | 2 |
| GOV-101-S06 | Implement run_rate and seasonal_naive with actual calendar dates (no compaction) | `forecast.py` | Gap handling equals the GOV-002 ladder | 3 |
| GOV-101-S07 | Implement rolling_origin_folds (4×7 holdouts, per-model training length) with a leakage assertion | `backtest.py` | Instrumented test: no training index ≥ holdout start | 3 |
| GOV-101-S08 | Add property tests (translation and scale invariance of z, MAD ≥ 0, no ZeroDivisionError) | `tests/statistics/bridge_stats/` | 10k Hypothesis cases pass | 2 |
| GOV-101-S09 | Write docs with formulas and fixture table; record evidence | README + evidence | Reviewed by data science | 2 |

Task acceptance:
- [ ] All governance statistical fixtures pass with independently computed values; INS and GOV import this package only.

### GOV-102 — Notification delivery infrastructure (SES, egress proxy, Slack app, Teams setup)
Release: R1 (Teams parts R1*) · Estimate: 14–20 h · Risk: M · Decisions: D-23, D-25 · Closes: G-GOV-09, G-GOV-10, G-GOV-11 (proxy), G-GOV-12
Why: lead-time items (Slack app registration) and network isolation must exist before GOV-006. The SES identity (`notify.<domain>`), configuration set and production-access request are INF-006-S11's; GOV-102 keeps the egress proxy, Slack app, Teams guide and destination secrets (RECONCILIATION U-07). Plugs in after INF-002 (egress) and INF-006 (DNS, SES).
Dependency changes: new task; deps `INF-002, INF-003, INF-006`; new downstream edge `GOV-006 → GOV-102`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| GOV-102-S01 | Moved to INF-006-S11 per RECONCILIATION U-07 (SES identity for `notify.<domain>`, Easy DKIM, custom MAIL FROM, DMARC) — consume it here | — | — | 0 |
| GOV-102-S02 | Moved to INF-006-S11 per RECONCILIATION U-07 (SES production-access request) | — | — | 0 |
| GOV-102-S03 | Moved to INF-006-S11 per RECONCILIATION U-07 (configuration set → SNS → SQS bounces/complaints) — GOV-006/GOV-007 consume its queue | — | — | 0 |
| GOV-102-S04 | Deploy the Smokescreen egress proxy in an isolated subnet; notification worker SG egress only to the proxy + VPC endpoints; ACL per role | IaC `infra/egress-proxy/` | A worker connecting directly to the internet or to 10.0.0.0/8 is blocked | 4 |
| GOV-102-S05 | Verify the proxy's IPv6 behaviour; if unsupported, remove the IPv6 route from the proxy subnet (TO VERIFY LIVE) | test report | Documented result | 2 |
| GOV-102-S06 | Register the Slack app: OAuth v2 scopes chat:write, channels:read, groups:read; redirect URL; signing secret; distribution enabled | app manifest in repo | Install into the test workspace succeeds | 3 |
| GOV-102-S07 | Write the Teams setup guide (R1*): Workflows template "Post to a channel when a webhook request is received", URL host pattern, owner-continuity advice | `docs/customer/teams-destination.md` | Reviewed | 2 |
| GOV-102-S08 | Configure secrets: KMS CMK per environment; path `/bridge/{env}/tenant/{tenant_id}/destination/{id}`; IAM limits the worker to that prefix | IaC | Cross-tenant secret read → AccessDenied | 2 |
| GOV-102-S09 | Record evidence | evidence | Complete | 1 |

Task acceptance:
- [ ] (Delivered by INF-006-S11, RECONCILIATION U-07.) SES authenticated sending plus bounce/complaint pipeline are live in staging; production access requested.
- [ ] Notification workers can reach the internet only through the SSRF-filtering proxy.

### GOV-103 — Monitor evaluation scale and cost benchmark
Release: R1 · Estimate: 13–18 h · Risk: M · Decisions: D-08, D-17 · Closes: G-GOV-06 (live)
Why: monitor evaluation is a recurring central cost; batching and skip ratios must be measured before OPS-009 margins. Plugs in after GOV-004; feeds OPS-009.
Dependency changes: new task; deps `GOV-004, GOV-007`; new downstream edge `OPS-009 → GOV-103`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| GOV-103-S01 | Generate synthetic load: 200 tenants × 20 monitors (5 partitioned by warehouse ×100, 1 by user capped at 1,000), hourly publications | bench config | Deterministic seed | 2 |
| GOV-103-S02 | Measure Snowflake queries/day, credits (QUERY_TAG `bridge_finops:gov_eval`) and batch latency | report §snowflake | Target ≤ 1 query per (tenant, profile, dataset, window, publication) (TO VERIFY LIVE) | 2 |
| GOV-103-S03 | Measure the skip ratio across 24 h | report §skip | ≥ 90% of ticks skipped for daily windows | 1 |
| GOV-103-S04 | Measure PG load: tracker upserts/hour, lock waits, incident rows | report §pg | p95 upsert < 20 ms (TO VERIFY LIVE) | 2 |
| GOV-103-S05 | Measure notification throughput under a 500-incident burst with per-destination limits | report §delivery | No 429 storms; DLQ empty | 2 |
| GOV-103-S06 | Tune the batch size and per-tenant budget, then rerun | PR + report | Before/after recorded | 2 |
| GOV-103-S07 | Publish the OPS-009 cost-model entry and propose plan quotas (monitors, partitions) | cost model | Reviewed | 1 |
| GOV-103-S08 | Record evidence | evidence | Complete | 1 |

Task acceptance:
- [ ] Measured queries, credits and latency at reference load published with quota proposals.

### GOV-104 — Custom fiscal calendars (4-4-5 and explicit periods)
Release: R2 · Estimate: 18–26 h · Risk: L · Decisions: — · Closes: G-GOV-16 (R2)
Why: explicit fiscal calendars are named in the contract but are not needed for most first customers. Plugs in after GOV-001.
Dependency changes: new task; deps `GOV-001`; no R1 downstream edges.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| GOV-104-S01 | Define the calendar entity: explicit contiguous non-overlapping periods [start,end) UTC; pattern generators 4-4-5/4-5-4/5-4-4 | contract + migration | Overlap or gap → 422 | 3 |
| GOV-104-S02 | Handle 53-week years (extra week placement policy) | generator | Tests for 52/53-week years | 2 |
| GOV-104-S03 | Let budgets reference calendar periods; recurring budgets roll by calendar period | API | Budget on P3 of a 4-4-5 year evaluates the correct dates | 3 |
| GOV-104-S04 | Test calendar edits after use: new version only; old budgets keep their period dates | tests | Existing budgets unchanged | 2 |
| GOV-104-S05 | Build the calendar editor UI | `apps/web/settings/calendars` | UX matrix passes | 3 |
| GOV-104-S06 | Wire calendar periods into reports and monitor windows (`fiscal_period_to_date`) | registry + windows | Monitor window resolves to the fiscal period | 2 |
| GOV-104-S07 | Migrate R1 budgets: map `fiscal_year_start_month` budgets to generated calendar ids without changing their period dates | migration | Before/after period dates identical for all fixture budgets | 2 |
| GOV-104-S08 | Record evidence | evidence | Complete | 1 |

### GOV-105 — Theil–Sen trend, rolling-origin selection and calibrated intervals
Release: R2 · Estimate: 22–31 h · Risk: M · Decisions: — · Closes: G-GOV-02
Why: per the release plan, model selection and intervals are R2. The internally consistent thresholds (84/133 days) are defined here. Plugs in after GOV-002 and GOV-101.
Dependency changes: new task; deps `GOV-002, GOV-101`; no R1 downstream edges.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| GOV-105-S01 | Implement Theil–Sen over the last 56 days: slope = median pairwise (y_j−y_i)/(x_j−x_i) on calendar-day index; intercept = median(y − slope·x); predictions capped ≥ 0 gross | `bridge_stats/forecast.py` | Linear 10+1/day series → slope 1 exactly | 3 |
| GOV-105-S02 | Implement fold construction per G-GOV-02 (SN 28 / TS 56 training), selection requiring h ≥ 84 | `bridge_stats/backtest.py` | h = 83 → no selection; 84 → selection | 3 |
| GOV-105-S03 | Implement selection: pooled MAE over 28 holdout days; TS iff MAE_TS ≤ 0.9·MAE_SN; ties → SN; leakage assertion | `forecast/select.py` | Trend series → TS; noisy flat → SN | 3 |
| GOV-105-S04 | Implement calibration: 20 daily origins, period-total residual quantiles for a nominal 80% interval; publish only if coverage ∈ [75%, 85%]; minimum h 133 (TS) / 77 (SN) | `forecast/intervals.py` | A miscalibrated fixture → null + UNCALIBRATED | 4 |
| GOV-105-S05 | Add fixtures: structural break, trend, noise, calibration pass/fail | tests | Independently computed values match | 3 |
| GOV-105-S06 | Update the UI to show model evidence (fold MAEs, chosen model, interval coverage) | UI | UX matrix passes | 3 |
| GOV-105-S07 | Govern model versions: any parameter change creates a new model_version; publish a side-by-side backtest report old vs new before activation | model registry entry + report | Activation blocked without the report | 2 |
| GOV-105-S08 | Record evidence | evidence | Complete | 1 |

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| GOV-001 | R1 | 42 | 60 |
| GOV-002 | R1 | 30 | 43 |
| GOV-003 | R1 | 45 | 64 |
| GOV-004 | R1 | 47 | 67 |
| GOV-005 | R1 | 18 | 26 |
| GOV-006 | R1 (Teams R1*) | 44 | 62 |
| GOV-007 | R1 | 39 | 55 |
| GOV-008 | R1 | 33 | 47 |
| GOV-101 | R1 | 20 | 28 |
| GOV-102 | R1 | 14 | 20 |
| GOV-103 | R1 | 13 | 18 |
| GOV-104 | R2 | 18 | 26 |
| GOV-105 | R2 | 22 | 31 |
| **Total R1** | | **345** | **490** |
| **Total R2** | | **40** | **57** |

(Teams-specific effort inside R1 totals, conditional on D-20: GOV-006-S07 3 h + GOV-102-S07 2 h + evidence ≈ 6–9 h.)

## 7. Owner questions (only those not already covered by D-01…D-25)

1. **Default monitor data status.** PROVISIONAL (alerts about 1 day after the event; may later self-correct as DATA_CORRECTION) or FINAL (2–5 days later)? Recommended: PROVISIONAL for spend/anomaly monitors, FINAL for budget monitors on currency-billed scopes.
2. **Slack distribution.** Will Bridge operate a publicly distributed Slack app, which customers' Slack admins must approve? Or should R1 accept per-channel incoming-webhook URLs only (no threading, weaker revocation signals)?
3. **Plan quotas.** Monitors per tenant, max partitions per monitor (proposed 500 default, 5,000 cap), destinations per tenant and simulation quotas. These tie into D-17 entitlements.
4. **Email sender identity.** Which domain and brand for `notify.<domain>`? Are per-tenant custom sender domains (tenant DKIM) ever required? Recommended: no in R1.
5. **Budget timezone.** Does the first customer need budgets on non-UTC calendar days? This would need hourly-grain actuals; R1 assumes UTC days only.

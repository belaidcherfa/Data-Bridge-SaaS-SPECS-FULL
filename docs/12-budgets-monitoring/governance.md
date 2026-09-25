# Budgets, forecasting, monitors and notification delivery

Canonical domain contract. Owner: Backend / Data science / Frontend. Implementation state: NOT_STARTED.


## Budget contract

Budgets define tenant/scope query, period `[start,end)` UTC, currency, amount, owner, allocation book/version policy, included cost basis, thresholds and effective revision. Scope can be organization/account/service/team/group/project/warehouse/application/workload/custom supported filter. Default monthly UTC periods; explicit fiscal calendars are configuration with tested boundaries. Actual is the same signed net spend metric as explorer; do not create a separate budget formula. Overlapping budgets are independently evaluated and not added as if they were disjoint spending buckets.

Actual, remaining, variance, burn rate, days remaining and forecast share publication/coverage. Remaining=budget−actual; negative means exceeded. Burn rate uses complete observed days and names its unit. Zero budget has null variance percentage plus absolute overrun. Unavailable currency conversion blocks mixed-currency budget evaluation.

Forecasts are versioned Python outputs in Snowflake, keyed by scope/period/model/input publication. Start with seasonal-naive and robust trend candidates; rolling-origin backtest chooses the simplest eligible model beating an agreed baseline. Minimum 28 complete daily observations for weekly seasonality; use an explicitly labelled simple run-rate fallback for shorter history and suppress forecasts with insufficient coverage. Preserve prediction intervals, training window, error metrics and known scheduled changes. Negative adjustments are modelled separately from recurring gross activity where appropriate. No claimed confidence percentage without calibration evidence.

Golden budget fixture: 30-day period, budget280 USD, first15 complete days at10/day → actual150, remaining130, burn10/day, forecast300, forecast variance20 (7.142857…%). Forecast is an estimate even when actuals are reconciled.

## Generic monitor definition

A versioned monitor is dataset + authorized scope + metric + aggregation + evaluation window + condition + schedule + partition dimensions + severity + maturity/coverage policy + destinations + suppression. Conditions: static threshold, relative threshold, results found, period comparison, anomaly, budget/forecast breach, new resource, cost regression, missing activity, SLA violation and sync failure. Scheduled report is a delivery action referencing a report definition, not another alert engine.

Metric/dimension validation uses the same semantic registry as the API. Partition enumeration is bounded and authorized; unseen groups can be discovered by the generic engine without generating one monitor object per model. Store definitions/workflow in PostgreSQL, evaluated analytical observations and evidence in Snowflake. Null/incomplete data yields INSUFFICIENT_DATA, not zero, firing or automatic recovery. Missing activity requires healthy source coverage; stale ingestion cannot prove no workload ran.

Observation identity includes config, scope partition, logical schedule tick, time window and input publication. Retries reuse the same tick; corrected versions supersede that tick's observation and cannot increment confirmation counters twice. An observation key includes the evaluation window and input publication. An active incident episode key is tenant/monitor/condition-version/partition and deliberately excludes both the moving evaluation window and dataset version. Enforce at most one active episode per key transactionally; successive failing windows and corrected reevaluations attach to that episode. After confirmed recovery, a new sustained breach creates a new episode ID. States OPEN/ACKNOWLEDGED/INVESTIGATING/RESOLVED; occurrence count is bounded workflow metadata. Hysteresis, cooldown and recovery confirmation avoid flapping. Silence windows have owner/reason/expiry and are audited.

## Notification delivery

Email, Slack, Teams and signed HTTPS webhook are launch requirements. Definitions store a destination reference; credentials go to Secrets Manager. Transactional outbox records logical delivery ID, event/report reference, destination version, recipient authorization snapshot, attempt state and next retry. Reauthorize sensitive payload generation and secure-link access. External providers can deliver twice after ambiguous timeouts; promise at-least-once delivery with logical deduplication, not impossible global exactly-once.

Use SES verified domains/DKIM and production-access gate; sandbox messages are only to approved test recipients. [SES sandbox](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html). Slack uses supported OAuth/incoming webhook integration with destination/channel validation. [Slack webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/). Teams uses a currently supported Workflow/Power Automate webhook or approved Graph-based integration; do not build new dependence on retired Office 365 connectors. Validate workflow owner continuity and tenant policy. [Teams webhook guidance](https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook).

Generic webhooks require HTTPS, no URL credentials, bounded payload, signed timestamp/event ID and secret rotation. Block private/link-local/metadata IPs, revalidate DNS on connection, reject redirects and unsupported ports, defend IPv6 equivalents and DNS rebinding. Default retry: exponential jitter, honor safe Retry-After, maximum8 attempts/24h then DLQ; permanent auth/4xx failures pause destination with remediation. Destination test action sends only a clearly labelled test payload when the customer requests it.

## Premium notification content

Include what changed, absolute/relative impact with unit, evaluation period, source as-of/maturity, top verified contributors, confidence/limitations and a secure investigation link. Never invent likely savings or cause. Suppress sensitive SQL and customer identifiers beyond destination policy. Recovery notices reference the same incident and explain whether recovery was observed or a data correction.


## Initial executable statistical defaults

These are versioned product defaults, not vendor guarantees. Persist every parameter and expose the chosen method. Fixtures test the exact rules before data scientists tune them.

- Forecast input: complete daily net-cost series in one currency. Separate recurring gross spend from exceptional signed adjustments; approved exceptional items are added explicitly, never silently dropped. Fewer than7 complete days → INSUFFICIENT_HISTORY. From7–27 days, use mean spend per complete day × remaining days and label RUN_RATE_FALLBACK. The15-day fixture therefore forecasts300.
- With28+ complete days, eligible seasonal-naive forecast for a weekday is the mean of the last four complete occurrences of that weekday. Missing required observations suppress that candidate rather than filling zeros. A robust-trend candidate fits Theil–Sen slope (median pairwise daily slope) and median intercept over the last56 complete days, capped at nonnegative predicted gross daily spend; signed approved adjustments remain separate.
- Automatic model selection starts only with enough data for four rolling7-day holdout folds, each with at least28 training days. Score mean absolute error in currency units. Choose seasonal-naive unless trend improves MAE by at least10%; ties choose the simpler seasonal-naive. Never train on any point in the evaluated holdout. Before eligible comparison, use the qualified baseline and label the lack of selection evidence.
- Prediction intervals are optional, not fabricated. A version may publish empirically calibrated intervals only after held-out coverage and width are recorded over at least20 rolling forecast origins. Otherwise return null interval with UNCALIBRATED, plus method/history limitations. A run-rate line is not labelled a calibrated90% confidence interval.
- Default anomaly baseline is the previous28 complete daily observations, excluding current point. Use same-weekday cohorts only when at least8 prior comparable weekdays exist. Score `abs(current−median)/(1.4826×MAD)`; flag when score≥3.5 and absolute impact≥max(10% of abs(median), one currency minor unit). Positive spend and refund streams are evaluated separately.
- With MAD=0, equal current/baseline never flags. Use an explicitly labelled ABSOLUTE_DEVIATION rule when impact≥max(20% of abs(median), one minor unit); do not divide by epsilon and report a spurious huge z-score. Fixtures100→101 suppress and100→130 flag under this fallback. Missing days suppress evaluation; zero observed spend on a complete day is valid.
- Candidate ranking uses absolute monetary impact. Default digest emits at most10 candidates per tenant/evaluation and groups related resources; suppressed candidates remain inspectable. This controls notification volume, not a claimed statistical false-discovery rate. Calibration and false-positive reviews may revise thresholds with a new model version.

## Monitor defaults and command shape

Default evaluation is hourly UTC over the last complete daily window for cost monitors; source-specific availability horizons decide which day is complete. Operational sync/SLA monitors may use5-minute windows. Sustained threshold breach requires2 eligible evaluations; recovery requires2 eligible nonbreaching evaluations. INSUFFICIENT_DATA never increments either counter. Cooldown1h; silence requires expiry, default24h. Manual resolve records a reason and does not claim measured recovery. A still-breaching condition may reopen only after the explicit cooldown/silence policy permits it.

```json
{
  "metric": "spend", "metric_version": "v1", "currency": "USD",
  "scope": {"account_ids": ["authorized-account-uuid"]},
  "window": {"kind": "last_complete_day", "timezone": "UTC"},
  "condition": {"type": "static_threshold", "operator": "gt", "value": "100.00"},
  "partition_by": ["warehouse"], "schedule": {"every_minutes": 60},
  "coverage_policy": "REQUIRE_COMPLETE", "minimum_data_status": "FINAL",
  "breach_evaluations": 2, "recovery_evaluations": 2,
  "cooldown_seconds": 3600, "destination_ids": ["authorized-destination-uuid"]
}
```

A static monitor over100 at observations101/102 opens one incident; the next hourly103 attaches to the same incident; incomplete data leaves it open;99/98 confirms recovery. An evaluation retry at102 adds no duplicate occurrence or notification. Distinct partitions have distinct episodes and independent authorization checks.

Forecast date arithmetic uses actual UTC calendar dates, never a compacted sequence with missing days removed. Eligible training windows must be contiguous and complete. Forecast remaining spend begins after the last complete actual date and includes source-lagged unobserved days as estimates; it does not skip them because the wall clock has advanced.


## Implementation sequence

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [GOV-001](../tasks/GOV/GOV-001.md) | Implement scoped budgets and actuals | ALC-007, API-001 | M7 |
| [GOV-002](../tasks/GOV/GOV-002.md) | Implement calibrated forecasting and model selection | GOV-001, WRK-005 | M7 |
| [GOV-003](../tasks/GOV/GOV-003.md) | Define monitor DSL, validation and schedule planner | GOV-001, API-006 | M7 |
| [GOV-004](../tasks/GOV/GOV-004.md) | Implement partition evaluation, incident state and suppression | GOV-003, GOV-002, ORC-005 | M7 |
| [GOV-005](../tasks/GOV/GOV-005.md) | Implement robust anomaly candidates and quality gates | GOV-004 | M7 |
| [GOV-006](../tasks/GOV/GOV-006.md) | Implement Email, Slack, Teams and secure webhook adapters | GOV-004, SEC-008, INF-003 | M7 |
| [GOV-007](../tasks/GOV/GOV-007.md) | Implement delivery outbox, retries, DLQ and premium alerts | GOV-006, CTL-004 | M7 |
| [GOV-008](../tasks/GOV/GOV-008.md) | Build incident center and governance E2E acceptance | GOV-007, UX-008 | M7 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

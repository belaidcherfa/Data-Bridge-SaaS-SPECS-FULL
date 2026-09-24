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

Observation identity includes config, scope partition, time window and input publication. Incident fingerprint excludes changing dataset version and includes tenant/monitor/config condition/partition/window bucket, allowing corrected reevaluation to update the same incident. States OPEN/ACKNOWLEDGED/INVESTIGATING/RESOLVED; occurrence count is bounded workflow metadata. Hysteresis, cooldown and recovery confirmation avoid flapping. Silence windows have owner/reason/expiry and are audited.

## Notification delivery

Email, Slack, Teams and signed HTTPS webhook are launch requirements. Definitions store a destination reference; credentials go to Secrets Manager. Transactional outbox records logical delivery ID, event/report reference, destination version, recipient authorization snapshot, attempt state and next retry. Reauthorize sensitive payload generation and secure-link access. External providers can deliver twice after ambiguous timeouts; promise at-least-once delivery with logical deduplication, not impossible global exactly-once.

Use SES verified domains/DKIM and production-access gate; sandbox messages are only to approved test recipients. [SES sandbox](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html). Slack uses supported OAuth/incoming webhook integration with destination/channel validation. [Slack webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/). Teams uses a currently supported Workflow/Power Automate webhook or approved Graph-based integration; do not build new dependence on retired Office 365 connectors. Validate workflow owner continuity and tenant policy. [Teams webhook guidance](https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook).

Generic webhooks require HTTPS, no URL credentials, bounded payload, signed timestamp/event ID and secret rotation. Block private/link-local/metadata IPs, revalidate DNS on connection, reject redirects and unsupported ports, defend IPv6 equivalents and DNS rebinding. Default retry: exponential jitter, honor safe Retry-After, maximum8 attempts/24h then DLQ; permanent auth/4xx failures pause destination with remediation. Destination test action sends only a clearly labelled test payload when the customer requests it.

## Premium notification content

Include what changed, absolute/relative impact with unit, evaluation period, source as-of/maturity, top verified contributors, confidence/limitations and a secure investigation link. Never invent likely savings or cause. Suppress sensitive SQL and customer identifiers beyond destination policy. Recovery notices reference the same incident and explain whether recovery was observed or a data correction.


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

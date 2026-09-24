# Reporting, rendering and secure scheduled distribution

Canonical domain contract. Owner: Backend / Frontend / QA. Implementation state: NOT_STARTED.


## Report contract

PostgreSQL stores report definition, layout, filters, schedule, recipient references, template version and job lifecycle. Snowflake owns values and result snapshots. Private S3 stores generated PDF/PNG/CSV plus a checksum manifest. Report generation runs in an isolated ECS report worker launched/coordinated by Dagster; the API only validates/enqueues and returns202. Rendering code must not perform unrestricted browsing or execute user HTML/scripts.

Reusable components: KPI, Trend, Breakdown, Waterfall, Table, Top N, Budget, Insight, Monitor summary, Allocation summary and deterministic Narrative. Each declares compatible metric/dimension IDs, unit, cost basis, scope, maturity, coverage and input publication. Narrative uses validated templates over known numbers, with no invented causes. Optional future LLM text cannot become numerical authority. Insights and allocation widgets show explicit unavailability before those modules are enabled.

Required templates: Executive FinOps; CFO Monthly; Platform Review; Team Showback; Chargeback Statement; Warehouse Review; dbt Review; AI/Cortex Review. All share the semantic registry and financial conventions. Chargeback uses a closed statement version, not a mutable latest dashboard. CFO reports keep currencies distinct and disclose provisional periods. Each artifact records timezone, filter summary, permissions snapshot hash, template/metric/dataset versions, generated-at and source as-of.

## Scheduling and authorization

Schedules support daily, weekly, monthly and quarterly cadence with IANA timezone, local wall time and calendar policy. Default UTC. For daylight saving: skip a nonexistent local occurrence and record SKIPPED_DST; use the earlier offset once for an ambiguous occurrence. Monthly day31 clamps to month end. A logical occurrence key includes schedule revision and resolved UTC instant; a retry cannot create another logical report. Catch up at most the most recent missed occurrence by default, with explicit manual historical requests.

Report owner permissions are rechecked at execution; recipient entitlement is checked before payload delivery and on secure-link access. Group recipients resolve to an auditable set at dispatch. If owner/recipient loses scope, pause or redact by regenerating under the narrower valid scope; never send a previously broader artifact. Default external distribution is an authenticated secure link; attachments require explicit tenant policy acknowledging that an already delivered copy cannot be revoked. No public S3 objects or permanent bearer links. Download response uses attachment disposition, private/no-store caching and short expiry; a broker checks current authorization before issuing a short-lived URL. URL lifetime bounds residual revocation exposure and is disclosed; highly sensitive tenants use a brokered byte stream.

## Renderer security and fidelity

Use a pinned browser image, bundled fonts, fixed locale/timezone and deterministic fixtures. Render only a self-contained approved application origin/static bundle, with network egress denied except an explicit internal data handoff. Escape labels, sanitize rich text, prohibit user-provided URLs and reject oversized jobs. Default ceilings: 100 pages, 50k CSV rows for interactive exports and250k for asynchronous exports, 60s render CPU deadline, 100MiB artifact; revise through measured capacity tests. Large data uses paginated summaries plus explicit truncation metadata, never silent row loss.

CSV neutralizes spreadsheet formula prefixes after leading whitespace/control characters while preserving the numeric typed fields. PDF/PNG show maturity and coverage legibly on every relevant page. Tables repeat headers, keep totals adjacent to their rows and avoid clipped labels. Financial numbers in UI, CSV and PDF must agree before cosmetic approval.


## Implementation sequence

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [RPT-001](../tasks/RPT/RPT-001.md) | Define report schema and reusable component contracts | API-001, API-004, UX-001 | M7 |
| [RPT-002](../tasks/RPT/RPT-002.md) | Implement isolated snapshot and render workers | RPT-001, ORC-003, INF-004 | M7 |
| [RPT-003](../tasks/RPT/RPT-003.md) | Implement and visually qualify eight report templates | RPT-002, ALC-008, GOV-008, WRK-005, UX-007 | M7 |
| [RPT-004](../tasks/RPT/RPT-004.md) | Implement calendar schedules and report occurrence planning | RPT-003, GOV-007 | M7 |
| [RPT-005](../tasks/RPT/RPT-005.md) | Implement report history, secure access and retention | RPT-004, SEC-008, CTL-007 | M7 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

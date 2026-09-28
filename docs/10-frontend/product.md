# Premium product experience and cost exploration

Canonical domain contract. Owner: Frontend / UX lead. Implementation state: NOT_STARTED.


## Product design system

Use React + TypeScript, shadcn/ui primitives, TanStack Query/Table and one accessible chart library selected/pinned in FND-002. Light theme only: warm off-white canvas, white surfaces, muted borders, restrained gold brand accent and semantic status colors with text/icons. Dense analytics must remain readable; no futuristic gradients or engineering-console vocabulary. Define spacing, typography, money/UTC formatting, focus rings, table density, skeletons, empty states and modal/drawer patterns as tokens/components. (amended 2026-09-28, D-18, G-UX-08) R1 ships in **English with every UI string externalized** (FormatJS/ICU message catalogs per locale, a lint rule rejecting literal strings in JSX, a pseudo-locale in visual tests) and locale-aware number, date and currency formatting from UX-001; money is formatted from the server's decimal string, never through a JavaScript `number`; financial dates are labelled UTC. Server-side messages (errors, notification and report templates) use message keys with parameters. French follows in R2.

(amended 2026-09-28, D-28) The React SPA is a static bundle served from S3 through CloudFront with Origin Access Control, not a Fargate `frontend` service; the API is reached through a CloudFront VPC origin to an internal ALB (refines PRD §5; see the [platform contract](../17-devops/platform.md)).

Global navigation follows the PRD: Home; Explore (Cost Explorer, Warehouses, Queries, Workloads, Storage, Serverless, AI/Cortex, SPCS); Allocate (Tag Studio, Allocation Studio, Usage Groups, Showback, Chargeback); Govern (Budgets, Monitors, Reports); Optimize (Insights, Actions, Savings); Dashboards; Platform (Data Health, Integration Health); Settings. Reconciliation is available from financial-status badges and the Govern area. Avoid duplicate cost formulas or duplicated page-specific alert engines. (amended 2026-09-28, G-UX-01, D-20) All 87 designed screens have an owning task in the screen-ownership table of [UX backlog](../22-implementation-readiness/backlog/UX.md) §3.1 — including UX-102 (settings, roles, audit, privacy, support), UX-103 (Integration Health with egress IPs and the customer warehouse footprint), UX-104 (Explain drawer, jobs and exports center), WRK-102 (workloads overview and ad hoc), INS-101 (insights list and detail) and ING-012 (Data Health); dashboards are R2 (UX-101) and in R1 the Dashboards item lists saved views. AI/Cortex and SPCS pages are R1 under D-20.

## Shared interaction contract

Persistent scope bar: organization/account selection, UTC period, comparison window, currency, maturity filter and dataset as-of. (amended 2026-09-28, G-API-13, G-UX-05, G-UX-06) The tenant travels on every request (`X-Bridge-Tenant` header and `/t/{tenant_slug}/` route prefix); responses for another tenant are dropped, so a tenant switch in one tab cannot render another tenant's numbers in a second tab; a page pins one publication for all its tiles and offers an explicit refresh when a newer publication exists. Valid preset windows: 7/30/60/90/180/365 days; availability constrains actual coverage. (amended 2026-09-28, D-11) Query-level detail covers 365 days by default; statistics beyond the query-level retention come from sketch aggregates and are labelled approximate. Users can select exact UTC boundaries. Preserve filters when drilling account→service→resource→workload→query; browser Back restores state and scroll. Use opaque IDs in routes. Comparison aligns complete equivalent periods and explicitly marks a partial current period.

All financial tiles expose Explain This Number, unit, price basis and maturity. PROVISIONAL/FINAL/RECONCILED have text labels; invoice close is separate. Unknown cost uses an em dash plus reason, not 0. Empty confirmed usage, filtered-empty, missing access and incomplete ingestion have different copy/actions. Background refresh keeps prior accepted values with as-of label; a new dataset version replaces related tiles together. Never show a transient zero before loading.

Tables support column selection, search, multi-filter, grouping/pivot from semantic dimensions, stable sort, saved views, bounded export and keyboard navigation. Server-side queries/pagination handle large data; browser never downloads 500M rows. Charts and table use the same query response/version. Top N has an explicit Other bucket so totals reconcile. (amended 2026-09-28, G-UX-07, G-API-02) Totals, the Other row, deltas and percentages come only from the server (`meta.totals`, `__OTHER__`, `delta`/`delta_pct`); sorting is server-side; a grouping by resource dimension shows the `attributed_cost` substitution banner; "not applicable at this scope" is null with a reason, never 0. Drilldowns include breadcrumbs and scope summary; a restricted user cannot discover hidden resources through autocomplete/counts.

Accessibility target: WCAG 2.2 AA design intent, tested with automated checks plus keyboard/screen-reader review; do not claim certification. Text at 200% zoom remains usable; charts have tabular equivalents and no color-only encoding. Handle 1280px desktop and 390px mobile review with deliberate table horizontal scroll, not clipped actions.

## Page composition

Home answers spend, drivers, ownership, risk, opportunity and next action. Separate estimated potential savings from validated realized savings. Cost Explorer combines KPI ribbon, trend, contribution waterfall and pivot table. Warehouse detail orders cost→query attribution/idle→workload→performance→evidence; warehouse-type capability changes visible KPIs. Query detail shows compute component scope, performance, workload lineage and privacy-approved SQL. Storage separates billed cost from bytes/retention. Serverless/AI/SPCS use family-specific units and coverage rather than forcing warehouse terminology.

Integration Health summarizes identity/grants/destinations; Data Health summarizes source/transport/transformation/reconciliation. Do not expose Dagster, internal queues, SQL stack traces or cloud role names as the primary customer explanation. Technical evidence is available through a safe expandable support detail.

## UX proof

Every page task below specifies persona, goal, entry, happy path, all states, drilldown and actions. Use a stable synthetic demo fixture with realistic but anonymized names; no customer screenshots. Playwright tests assert labels/values/filters/access and capture desktop/mobile screenshots for visual review. Test slow responses, empty data, partial coverage, stale publication, permission revocation and error recovery. A screenshot alone does not prove totals or isolation.


## Implementation sequence

(amended 2026-09-28) The dependency and gate columns below are the original index. Execution follows the revised graph ([revised-task-graph.json](../22-implementation-readiness/revised-task-graph.json), [revised critical path](../22-implementation-readiness/REVISED_CRITICAL_PATH.md)) and phases P0–P6 of the [release plan](../22-implementation-readiness/RELEASE_PLAN.md); new tasks, revised steps, dependencies and task acceptance are in [backlog/UX.md](../22-implementation-readiness/backlog/UX.md).

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [UX-001](../tasks/UX/UX-001.md) | Create light-theme component system and application shell | FND-003 | M0 |
| [UX-002](../tasks/UX/UX-002.md) | Integrate authenticated scope state and semantic query components | UX-001, API-003, SEC-006 | M5 |
| [UX-003](../tasks/UX/UX-003.md) | Build Home and executive drivers experience | UX-002, FIN-009 | M5 |
| [UX-004](../tasks/UX/UX-004.md) | Build Cost Explorer with pivots and saved analyses | UX-003, CTL-007, API-005 | M5 |
| [UX-005](../tasks/UX/UX-005.md) | Build warehouse and query cost deep dives | UX-004, FIN-004 | M5 |
| [UX-006](../tasks/UX/UX-006.md) | Build storage and serverless resource views | UX-004, FIN-006, FIN-007 | M5 |
| [UX-007](../tasks/UX/UX-007.md) | Build AI/Cortex and SPCS analytical experiences | UX-004, FIN-018, FIN-019 | M5 |
| [UX-008](../tasks/UX/UX-008.md) | Validate product states, accessibility and navigation end to end | UX-005, UX-006, UX-007 | M5 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.

## Detailed design extension

The authorized UI/UX phase provides [87 screen specifications in ASCII](../21-ui-ux/SCREEN_INDEX.md), [shared component contracts](../21-ui-ux/COMPONENTS.md), [fixture scope](../21-ui-ux/FIXTURES_AND_SCOPE.md) and a [standalone React mockup](../../prototypes/finops-react/README.md). [ADR-013](../architecture/adr/ADR-013-ui-design-prototype.md) records its boundaries. This extends presentation detail without changing canonical production metrics, tenancy or implementation gates.

(amended 2026-09-28, G-UX-07, G-UX-11) The prototype is a reference for visual identity and interaction only. It computes totals, budgets, savings and allocations in the browser, fabricates a daily series from a monthly total, rounds with floating point and renders $0.00 where a value is not applicable; **production must not copy any of it**. Production money values are a branded `MoneyString` from the generated API types; the lint rule `bridge/no-money-arithmetic` forbids arithmetic on money and imports from `prototypes/**`; status badges read `data_status`, `reconciliation_status` and close status from the response; largest-remainder rounding exists only in FIN-106/ALC-008 on exact decimals. Route vocabulary, entity identity in routes and the reuse matrix are in [UX backlog](../22-implementation-readiness/backlog/UX.md) §3.

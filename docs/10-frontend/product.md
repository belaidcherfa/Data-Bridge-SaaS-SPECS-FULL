# Premium product experience and cost exploration

Canonical domain contract. Owner: Frontend / UX lead. Implementation state: NOT_STARTED.


## Product design system

Use React + TypeScript, shadcn/ui primitives, TanStack Query/Table and one accessible chart library selected/pinned in FND-002. Light theme only: warm off-white canvas, white surfaces, muted borders, restrained gold brand accent and semantic status colors with text/icons. Dense analytics must remain readable; no futuristic gradients or engineering-console vocabulary. Define spacing, typography, money/UTC formatting, focus rings, table density, skeletons, empty states and modal/drawer patterns as tokens/components.

Global navigation follows the PRD: Home; Explore (Cost Explorer, Warehouses, Queries, Workloads, Storage, Serverless, AI/Cortex, SPCS); Allocate (Tag Studio, Allocation Studio, Usage Groups, Showback, Chargeback); Govern (Budgets, Monitors, Reports); Optimize (Insights, Actions, Savings); Dashboards; Platform (Data Health, Integration Health); Settings. Reconciliation is available from financial-status badges and the Govern area. Avoid duplicate cost formulas or duplicated page-specific alert engines.

## Shared interaction contract

Persistent scope bar: organization/account selection, UTC period, comparison window, currency, maturity filter and dataset as-of. Valid preset windows: 7/30/60/90/180/365 days; availability constrains actual coverage. Users can select exact UTC boundaries. Preserve filters when drilling account→service→resource→workload→query; browser Back restores state and scroll. Use opaque IDs in routes. Comparison aligns complete equivalent periods and explicitly marks a partial current period.

All financial tiles expose Explain This Number, unit, price basis and maturity. PROVISIONAL/FINAL/RECONCILED have text labels; invoice close is separate. Unknown cost uses an em dash plus reason, not 0. Empty confirmed usage, filtered-empty, missing access and incomplete ingestion have different copy/actions. Background refresh keeps prior accepted values with as-of label; a new dataset version replaces related tiles together. Never show a transient zero before loading.

Tables support column selection, search, multi-filter, grouping/pivot from semantic dimensions, stable sort, saved views, bounded export and keyboard navigation. Server-side queries/pagination handle large data; browser never downloads 500M rows. Charts and table use the same query response/version. Top N has an explicit Other bucket so totals reconcile. Drilldowns include breadcrumbs and scope summary; a restricted user cannot discover hidden resources through autocomplete/counts.

Accessibility target: WCAG 2.2 AA design intent, tested with automated checks plus keyboard/screen-reader review; do not claim certification. Text at 200% zoom remains usable; charts have tabular equivalents and no color-only encoding. Handle 1280px desktop and 390px mobile review with deliberate table horizontal scroll, not clipped actions.

## Page composition

Home answers spend, drivers, ownership, risk, opportunity and next action. Separate estimated potential savings from validated realized savings. Cost Explorer combines KPI ribbon, trend, contribution waterfall and pivot table. Warehouse detail orders cost→query attribution/idle→workload→performance→evidence; warehouse-type capability changes visible KPIs. Query detail shows compute component scope, performance, workload lineage and privacy-approved SQL. Storage separates billed cost from bytes/retention. Serverless/AI/SPCS use family-specific units and coverage rather than forcing warehouse terminology.

Integration Health summarizes identity/grants/destinations; Data Health summarizes source/transport/transformation/reconciliation. Do not expose Dagster, internal queues, SQL stack traces or cloud role names as the primary customer explanation. Technical evidence is available through a safe expandable support detail.

## UX proof

Every page task below specifies persona, goal, entry, happy path, all states, drilldown and actions. Use a stable synthetic demo fixture with realistic but anonymized names; no customer screenshots. Playwright tests assert labels/values/filters/access and capture desktop/mobile screenshots for visual review. Test slow responses, empty data, partial coverage, stale publication, permission revocation and error recovery. A screenshot alone does not prove totals or isolation.


## Implementation sequence

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

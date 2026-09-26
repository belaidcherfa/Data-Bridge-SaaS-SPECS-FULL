# Warehouses — detailed screen design

Design unit: `warehouses`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../10-frontend/workloads.md).

This file covers 2 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## warehouses — Warehouses

Route: `/warehouses` (prototype `#/warehouses`). Persona: **FinOps analyst / data engineer**.

Goal: Find the balance between performance and spend.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Warehouses                                                            |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Find the balance between performance and spend.                                                          |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| WAREHOUSE COMPUTE: $20,000.00 [i]  ||  QUERY COMPUTE: $14,000.00 [i]                                     |
| Billed compute · excludes cloud services  ||  Attribution within warehouse charge                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CLASSIC IDLE: $6,000.00 [i]  ||  COMPLETED QUERIES: 12,480 [i]                                           |
| 20,000 minus 14,000  ||  7,488 Finance + 4,992 Marketing                                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: ANALYTICS_PROD [>]                                                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| COST BY WAREHOUSE                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Only ANALYTICS_PROD contributes to the closed-period fixture; unavailable adaptive costs stay null.      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| EFFICIENCY                                                                                               |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Classic query 14,000 + idle 6,000 = warehouse 20,000. Adaptive warehouses do not expose fabricated       |
| classic idle.                                                                                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Warehouse                 | Type                      | Cost USD                  | Owner                     |
+---------------------------+---------------------------+---------------------------+---------------------------+
| ANALYTICS_PROD            | Classic                   | 20,000.00                 | Finance                   |
| ADAPTIVE_LAB              | Adaptive                  | —                         | Not observed              |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| An unavailable resource is not included in totals; label its capability and data coverage.               |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `warehouse` | Warehouse compute: **$20,000.00** | Billed compute · excludes cloud services | August 2026 / synthetic; RECONCILED |
| `querycompute` | Query compute: **$14,000.00** | Attribution within warehouse charge | August 2026 / synthetic; RECONCILED |
| `idle` | Classic idle: **$6,000.00** | 20,000 minus 14,000 | August 2026 / synthetic; RECONCILED |
| `queries` | Completed queries: **12,480** | 7,488 Finance + 4,992 Marketing | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Cost by warehouse**: Only ANALYTICS_PROD contributes to the closed-period fixture; unavailable adaptive costs stay null.
- **Efficiency**: Classic query 14,000 + idle 6,000 = warehouse 20,000. Adaptive warehouses do not expose fabricated classic idle.
- **DataTable** columns, in order: Warehouse, Type, Cost USD, Owner. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/warehouse-detail`. Use named links; never assume every row represents the same execution.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Save view                                           [X]                    |
| Selected metric / resource: [label and identifier]                         |
| Scope and period: [explicit, retained from entry]                          |
| Basis / input publication / coverage: [explain]                            |
| Evidence: [authorized source / parent component]                           |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Save view]                                                      |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | FinOps analyst / data engineer |
| Goal | Find the balance between performance and spend. |
| Entry point | Explore navigation; deep link supported. |
| Happy path | Read context → inspect Cost by warehouse → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No warehouses for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: warehouse-detail. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; An unavailable resource is not included in totals; label its capability and data coverage. |

### Domain subtleties

An unavailable resource is not included in totals; label its capability and data coverage.

Classic query 14,000 + idle 6,000 = warehouse 20,000. Adaptive warehouses do not expose fabricated classic idle.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Warehouses                               |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Cost by warehouse                        |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/warehouses` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `warehouse` explanation and status.
- [ ] Inspect exact columns: Warehouse, Type, Cost USD, Owner. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## warehouse-detail — ANALYTICS_PROD

Route: `/warehouse-detail` (prototype `#/warehouse-detail`). Persona: **FinOps analyst / data engineer**.

Goal: Classic warehouse · PRODUCTION · Finance owned

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  ANALYTICS_PROD                                                        |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Classic warehouse · PRODUCTION · Finance owned                                                           |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| WAREHOUSE COMPUTE: $20,000.00 [i]  ||  QUERY COMPUTE: $14,000.00 [i]                                     |
| Billed compute · excludes cloud services  ||  Attribution within warehouse charge                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CLASSIC IDLE: $6,000.00 [i]  ||  COMPLETED QUERIES: 12,480 [i]                                           |
| 20,000 minus 14,000  ||  7,488 Finance + 4,992 Marketing                                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| COST COMPOSITION                                                                                         |
|      Query compute [##############] 14,000   Idle [######] 6,000                                         |
| 20,000 billed warehouse = 14,000 query compute attribution + 6,000 idle; cloud services excluded.        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PERFORMANCE                                                                                              |
|      Query compute [##############] 14,000   Idle [######] 6,000                                         |
| P50 2.4 s, P95 18.6 s; 12,480 completed executions. Percentiles computed over individual queries.        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CONFIGURATION EVIDENCE                                                                                   |
|      Query compute [##############] 14,000   Idle [######] 6,000                                         |
| Size Medium; auto suspend 300 s in synthetic evidence. Recommendations require an observation window,    |
| not one instantaneous setting.                                                                           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Workload                  | Query compute USD         | Share                     | Evidence                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| finance_daily             | 8,400.00                  | 60%                       | Verified                  |
| marketing_refresh         | 5,600.00                  | 40%                       | Verified                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Tabs: Overview, Queries, Workloads, Performance, Evidence. Evidence is descriptive; this mockup never    |
| changes Snowflake configuration.                                                                         |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `warehouse` | Warehouse compute: **$20,000.00** | Billed compute · excludes cloud services | August 2026 / synthetic; RECONCILED |
| `querycompute` | Query compute: **$14,000.00** | Attribution within warehouse charge | August 2026 / synthetic; RECONCILED |
| `idle` | Classic idle: **$6,000.00** | 20,000 minus 14,000 | August 2026 / synthetic; RECONCILED |
| `queries` | Completed queries: **12,480** | 7,488 Finance + 4,992 Marketing | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Cost composition**: 20,000 billed warehouse = 14,000 query compute attribution + 6,000 idle; cloud services excluded.
- **Performance**: P50 2.4 s, P95 18.6 s; 12,480 completed executions. Percentiles computed over individual queries.
- **Configuration evidence**: Size Medium; auto suspend 300 s in synthetic evidence. Recommendations require an observation window, not one instantaneous setting.
- **DataTable** columns, in order: Workload, Query compute USD, Share, Evidence. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `warehouses`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Save view                                           [X]                    |
| Selected metric / resource: [label and identifier]                         |
| Scope and period: [explicit, retained from entry]                          |
| Basis / input publication / coverage: [explain]                            |
| Evidence: [authorized source / parent component]                           |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Save view]                                                      |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | FinOps analyst / data engineer |
| Goal | Classic warehouse · PRODUCTION · Finance owned |
| Entry point | Parent route /warehouses; deep link supported. |
| Happy path | Read context → inspect Cost composition → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No analytics_prod for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Tabs: Overview, Queries, Workloads, Performance, Evidence. Evidence is descriptive; this mockup never changes Snowflake configuration. |

### Domain subtleties

Tabs: Overview, Queries, Workloads, Performance, Evidence. Evidence is descriptive; this mockup never changes Snowflake configuration.

Size Medium; auto suspend 300 s in synthetic evidence. Recommendations require an observation window, not one instantaneous setting.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| ANALYTICS_PROD                           |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Cost composition                         |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/warehouse-detail` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `warehouse` explanation and status.
- [ ] Inspect exact columns: Workload, Query compute USD, Share, Evidence. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

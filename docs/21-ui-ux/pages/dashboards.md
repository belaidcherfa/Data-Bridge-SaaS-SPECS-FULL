# Dashboards — detailed screen design

Design unit: `dashboards`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../10-frontend/product.md).

This file covers 2 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## dashboards — Dashboards

Route: `/dashboards` (prototype `#/dashboards`). Persona: **FinOps lead / executive**.

Goal: A shared view for each decision and audience.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  OVERVIEW  /  Dashboards                                                           |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| A shared view for each decision and audience.                                                            |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DASHBOARDS: 3 [i]  ||  SHARED DASHBOARDS: 2 [i]                                                          |
| Two shared and one private  ||  Data permissions still required                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PRIVATE DASHBOARDS: 1 [i]  ||  WIDGET FAMILIES: 8 [i]                                                    |
| Current demo user only  ||  Registry-compatible dimensions                                               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Executive dashboard [>]                                                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SAVED COMPOSITION                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| KPI, trend, breakdown, waterfall, budget, insight, table and monitor widgets use canonical metrics.      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SHARING                                                                                                  |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Visibility grants do not grant underlying data permissions. Restricted viewers receive restricted widget |
| data.                                                                                                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Dashboard                 | Audience                  | Visibility                | Updated                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Executive overview        | Leadership                | Shared                    | Today                     |
| Platform operations       | Engineering               | Shared                    | Yesterday                 |
| My exploration            | You                       | Private                   | Today                     |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Saved views are configuration; no analytical facts move to PostgreSQL.                                   |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `dashboardcount` | Dashboards: **3** | Two shared and one private | August 2026 / synthetic; Observed |
| `sharedviews` | Shared dashboards: **2** | Data permissions still required | August 2026 / synthetic; Observed |
| `privateviews` | Private dashboards: **1** | Current demo user only | August 2026 / synthetic; Observed |
| `widgets` | Widget families: **8** | Registry-compatible dimensions | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Saved composition**: KPI, trend, breakdown, waterfall, budget, insight, table and monitor widgets use canonical metrics.
- **Sharing**: Visibility grants do not grant underlying data permissions. Restricted viewers receive restricted widget data.
- **DataTable** columns, in order: Dashboard, Audience, Visibility, Updated. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/dashboard-builder`. Use named links; never assume every row represents the same execution.

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
| Persona | FinOps lead / executive |
| Goal | A shared view for each decision and audience. |
| Entry point | Overview navigation; deep link supported. |
| Happy path | Read context → inspect Saved composition → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No dashboards for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: dashboard-builder. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Saved views are configuration; no analytical facts move to PostgreSQL. |

### Domain subtleties

Saved views are configuration; no analytical facts move to PostgreSQL.

Visibility grants do not grant underlying data permissions. Restricted viewers receive restricted widget data.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Dashboards                               |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Saved composition                        |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/dashboards` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `dashboardcount` explanation and status.
- [ ] Inspect exact columns: Dashboard, Audience, Visibility, Updated. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## dashboard-builder — Executive dashboard

Route: `/dashboard-builder` (prototype `#/dashboard-builder`). Persona: **FinOps lead / executive**.

Goal: Arrange widgets without losing the metric contract.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  OVERVIEW  /  Executive dashboard                                                  |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Arrange widgets without losing the metric contract.                                                      |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| NET SNOWFLAKE SPEND: $27,000.00 [i]  ||  WAREHOUSE COMPUTE: $20,000.00 [i]                               |
| Signed charges · USD  ||  Billed compute · excludes cloud services                                       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BILLED STORAGE: $1,200.00 [i]  ||  ORGANIZATION NET: $200.00 [i]                                         |
| Priced billing basis  ||  Support 500 less rebate 300                                                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| RESPONSIVE GRID                                                                                          |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| 12 columns desktop, one column mobile; minimum chart height preserves legends and data access.           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| WIDGET CONFIGURATION                                                                                     |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Compatible registry dimensions only; stale widgets keep publication/as-of, not silent zeros.             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Widget                    | Metric                    | Dimension                 | Scope                     |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Total spend               | spend                     | None                      | Organization              |
| Service mix               | spend                     | Service                   | Organization              |
| Ownership                 | allocated cost            | Teams                     | Warehouse book            |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Prototype draft persists in browser storage; production permissions and version conflicts remain         |
| implementation tasks.                                                                                    |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `spend` | Net Snowflake spend: **$27,000.00** | Signed charges · USD | August 2026 / synthetic; RECONCILED |
| `warehouse` | Warehouse compute: **$20,000.00** | Billed compute · excludes cloud services | August 2026 / synthetic; RECONCILED |
| `storage` | Billed storage: **$1,200.00** | Priced billing basis | August 2026 / synthetic; RECONCILED |
| `orgnet` | Organization net: **$200.00** | Support 500 less rebate 300 | August 2026 / synthetic; RECONCILED |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Responsive grid**: 12 columns desktop, one column mobile; minimum chart height preserves legends and data access.
- **Widget configuration**: Compatible registry dimensions only; stale widgets keep publication/as-of, not silent zeros.
- **DataTable** columns, in order: Widget, Metric, Dimension, Scope. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save dashboard draft. Opens labelled form fields; required values validate before local save. In production, server validates authorization, schema and stale version.
- **Parent**: `dashboards`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Save dashboard draft                                           [X]         |
| Dashboard name: [____________________________]                             |
| Audience: [____________________________]                                   |
| Visibility: [____________________________]                                 |
| Description: [____________________________]                                |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Save dashboard draft]                                           |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | FinOps lead / executive |
| Goal | Arrange widgets without losing the metric contract. |
| Entry point | Parent route /dashboards; deep link supported. |
| Happy path | Read context → inspect Responsive grid → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No executive dashboard for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save dashboard draft reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save dashboard draft; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Prototype draft persists in browser storage; production permissions and version conflicts remain implementation tasks. |

### Domain subtleties

Prototype draft persists in browser storage; production permissions and version conflicts remain implementation tasks.

Compatible registry dimensions only; stale widgets keep publication/as-of, not silent zeros.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Executive dashboard                      |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Responsive grid                          |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save dashboard draft]                   |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/dashboard-builder` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `spend` explanation and status.
- [ ] Inspect exact columns: Widget, Metric, Dimension, Scope. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

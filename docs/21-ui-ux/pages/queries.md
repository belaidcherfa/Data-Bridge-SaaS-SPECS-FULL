# Queries — detailed screen design

Design unit: `queries`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../10-frontend/workloads.md).

This file covers 3 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## queries — Queries

Route: `/queries` (prototype `#/queries`). Persona: **FinOps analyst / data engineer**.

Goal: Cost and execution evidence, with privacy built in.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Queries                                                               |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Cost and execution evidence, with privacy built in.                                                      |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| QUERY COMPUTE: $14,000.00 [i]  ||  COMPLETED QUERIES: 12,480 [i]                                         |
| Attribution within warehouse charge  ||  7,488 Finance + 4,992 Marketing                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| P95 EXECUTION: 18.6 s [i]  ||  FAILED EXECUTIONS: 0 [i]                                                  |
| Individual query percentile · synthetic  ||  Fully observed selected fixture                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Query · q_demo_042 [>] | Execution explorer [>]                                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| QUERY COST DISTRIBUTION                                                                                  |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Grouped counts total 12,480; compute attribution totals 14,000. This is not total Snowflake spend.       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| EXECUTION FILTERS                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Filter by sanitized hash, status, workload, warehouse or complete UTC execution window.                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Query group               | Count                     | Compute USD               | Workload                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Finance models            | 7,488                     | 8,400.00                  | dbt                       |
| Marketing refreshes       | 4,992                     | 5,600.00                  | Power BI                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Table rows are grouped fixtures. Opening a representative execution does not imply all grouped           |
| executions have identical costs.                                                                         |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `querycompute` | Query compute: **$14,000.00** | Attribution within warehouse charge | August 2026 / synthetic; RECONCILED |
| `queries` | Completed queries: **12,480** | 7,488 Finance + 4,992 Marketing | August 2026 / synthetic; Observed |
| `p95` | P95 execution: **18.6 s** | Individual query percentile · synthetic | August 2026 / synthetic; Observed |
| `failed` | Failed executions: **0** | Fully observed selected fixture | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Query cost distribution**: Grouped counts total 12,480; compute attribution totals 14,000. This is not total Snowflake spend.
- **Execution filters**: Filter by sanitized hash, status, workload, warehouse or complete UTC execution window.
- **DataTable** columns, in order: Query group, Count, Compute USD, Workload. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/query-detail`, `/query-executions`. Use named links; never assume every row represents the same execution.

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
| Goal | Cost and execution evidence, with privacy built in. |
| Entry point | Explore navigation; deep link supported. |
| Happy path | Read context → inspect Query cost distribution → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No queries for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: query-detail, query-executions. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Table rows are grouped fixtures. Opening a representative execution does not imply all grouped executions have identical costs. |

### Domain subtleties

Table rows are grouped fixtures. Opening a representative execution does not imply all grouped executions have identical costs.

Filter by sanitized hash, status, workload, warehouse or complete UTC execution window.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Queries                                  |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Query cost distribution                  |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/queries` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `querycompute` explanation and status.
- [ ] Inspect exact columns: Query group, Count, Compute USD, Workload. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## query-detail — Query · q_demo_042

Route: `/query-detail` (prototype `#/query-detail`). Persona: **FinOps analyst / data engineer**.

Goal: Sanitized execution · completed · ANALYTICS_PROD

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Query · q_demo_042                                                    |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Sanitized execution · completed · ANALYTICS_PROD                                                         |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| EXECUTION COMPUTE: $2.80 [i]  ||  TOTAL DURATION: 12.4 s [i]                                             |
| Included in parent workload  ||  0.4 compile + 0.2 queue + 11.8 execution                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| QUEUE TIME: 0.2 s [i]  ||  ROWS RETURNED: 120,000 [i]                                                    |
| Representative execution  ||  Representative query evidence                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| EXECUTION TIMELINE                                                                                       |
|      Compile | Queue | Execution --------------------> [Evidence]                                        |
| Compile 0.4 + queue 0.2 + execution 11.8 = total 12.4 seconds in this synthetic non-overlapping fixture. |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SANITIZED SQL                                                                                            |
|      Compile | Queue | Execution --------------------> [Evidence]                                        |
| SELECT region, SUM(amount) FROM analytics.sales WHERE customer_id = ? GROUP BY region; no raw literals,  |
| identity values or secrets.                                                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PROFILE AVAILABILITY                                                                                     |
|      Compile | Queue | Execution --------------------> [Evidence]                                        |
| Historical August execution exceeds the on-demand plan window. Explain unavailable profile instead of    |
| drawing invented operator nodes.                                                                         |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Stage                     | Duration                  | Evidence                  | Status                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Compilation               | 0.4 s                     | Query history             | Complete                  |
| Queue                     | 0.2 s                     | Query history             | Complete                  |
| Execution                 | 11.8 s                    | Query history             | Complete                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Cost 2.80 USD is query compute only and belongs inside the finance workload; never add it again to       |
| parent totals.                                                                                           |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `singlequery` | Execution compute: **$2.80** | Included in parent workload | q_demo_042 / Aug 30; FINAL |
| `duration` | Total duration: **12.4 s** | 0.4 compile + 0.2 queue + 11.8 execution | August 2026 / synthetic; Observed |
| `queue` | Queue time: **0.2 s** | Representative execution | August 2026 / synthetic; Observed |
| `rows` | Rows returned: **120,000** | Representative query evidence | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Execution timeline**: Compile 0.4 + queue 0.2 + execution 11.8 = total 12.4 seconds in this synthetic non-overlapping fixture.
- **Sanitized SQL**: SELECT region, SUM(amount) FROM analytics.sales WHERE customer_id = ? GROUP BY region; no raw literals, identity values or secrets.
- **Profile availability**: Historical August execution exceeds the on-demand plan window. Explain unavailable profile instead of drawing invented operator nodes.
- **DataTable** columns, in order: Stage, Duration, Evidence, Status. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `queries`; breadcrumb and browser Back preserve scope.

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
| Goal | Sanitized execution · completed · ANALYTICS_PROD |
| Entry point | Parent route /queries; deep link supported. |
| Happy path | Read context → inspect Execution timeline → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No query · q_demo_042 for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Cost 2.80 USD is query compute only and belongs inside the finance workload; never add it again to parent totals. |

### Domain subtleties

Cost 2.80 USD is query compute only and belongs inside the finance workload; never add it again to parent totals.

Historical August execution exceeds the on-demand plan window. Explain unavailable profile instead of drawing invented operator nodes.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Query · q_demo_042                       |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Execution timeline                       |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/query-detail` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `singlequery` explanation and status.
- [ ] Inspect exact columns: Stage, Duration, Evidence, Status. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## query-executions — Execution explorer

Route: `/query-executions` (prototype `#/query-executions`). Persona: **FinOps analyst / data engineer**.

Goal: A full query-column contract with safe synthetic examples.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Execution explorer                                                    |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| A full query-column contract with safe synthetic examples.                                               |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| EXECUTION COMPUTE: $2.80 [i]  ||  TOTAL DURATION: 12.4 s [i]                                             |
| Included in parent workload  ||  0.4 compile + 0.2 queue + 11.8 execution                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| QUEUE TIME: 0.2 s [i]  ||  ROWS RETURNED: 120,000 [i]                                                    |
| Representative execution  ||  Representative query evidence                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| COLUMN CHOOSER                                                                                           |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Default subset favors query ID, compute, duration, warehouse and workload; all 16 fields are             |
| discoverable through column selection and horizontal scroll.                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| COST BASIS                                                                                               |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Representative query uses 1.40 attributed compute credits at fixture rate 2 USD/credit; query cost is a  |
| component, not a second billed charge.                                                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+
| Query ID                  | Hash                      | Compute USD               | Credits                   | Warehouse                 | User alias                | Role                      | Application               | Workload                  | Duration s                | Queue s                   | Compile s                 | Bytes scanned             | Spill bytes               | Tables                    | Query tag                 |
+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+
| q_demo_042                | h_fin_v1                  | 2.80                      | 1.40                      | ANALYTICS_PROD            | svc_finance               | ANALYST                   | dbt                       | finance_daily             | 12.4                      | 0.2                       | 0.4                       | 120 MB                    | 0                         | analytics.sales           | project=finance_daily     |
+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| One representative execution, not a full export of the 12,480-query month. Parameterized hash version is |
| h_fin_v1; literal text remains sanitized.                                                                |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `singlequery` | Execution compute: **$2.80** | Included in parent workload | q_demo_042 / Aug 30; FINAL |
| `duration` | Total duration: **12.4 s** | 0.4 compile + 0.2 queue + 11.8 execution | August 2026 / synthetic; Observed |
| `queue` | Queue time: **0.2 s** | Representative execution | August 2026 / synthetic; Observed |
| `rows` | Rows returned: **120,000** | Representative query evidence | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Column chooser**: Default subset favors query ID, compute, duration, warehouse and workload; all 16 fields are discoverable through column selection and horizontal scroll.
- **Cost basis**: Representative query uses 1.40 attributed compute credits at fixture rate 2 USD/credit; query cost is a component, not a second billed charge.
- **DataTable** columns, in order: Query ID, Hash, Compute USD, Credits, Warehouse, User alias, Role, Application, Workload, Duration s, Queue s, Compile s, Bytes scanned, Spill bytes, Tables, Query tag. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `queries`; breadcrumb and browser Back preserve scope.

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
| Goal | A full query-column contract with safe synthetic examples. |
| Entry point | Parent route /queries; deep link supported. |
| Happy path | Read context → inspect Column chooser → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No execution explorer for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; One representative execution, not a full export of the 12,480-query month. Parameterized hash version is h_fin_v1; literal text remains sanitized. |

### Domain subtleties

One representative execution, not a full export of the 12,480-query month. Parameterized hash version is h_fin_v1; literal text remains sanitized.

Representative query uses 1.40 attributed compute credits at fixture rate 2 USD/credit; query cost is a component, not a second billed charge.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Execution explorer                       |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Column chooser                           |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/query-executions` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `singlequery` explanation and status.
- [ ] Inspect exact columns: Query ID, Hash, Compute USD, Credits, Warehouse, User alias, Role, Application, Workload, Duration s, Queue s, Compile s, Bytes scanned, Spill bytes, Tables, Query tag. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

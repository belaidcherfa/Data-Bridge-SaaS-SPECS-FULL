# Workloads — detailed screen design

Design unit: `workloads`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../10-frontend/workloads.md).

This file covers 14 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## workloads — Workloads

Route: `/workloads` (prototype `#/workloads`). Persona: **FinOps analyst / data engineer**.

Goal: Connect technical activity to business purpose.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Workloads                                                             |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Connect technical activity to business purpose.                                                          |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| QUERY COMPUTE: $14,000.00 [i]  ||  COMPLETED QUERIES: 12,480 [i]                                         |
| Attribution within warehouse charge  ||  7,488 Finance + 4,992 Marketing                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CLASSIFIED COMPUTE: 100% [i]  ||  UNCLASSIFIED GROUPS: 0 [i]                                             |
| 14,000 assigned / 14,000 observed  ||  Observed fixture only                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: dbt intelligence [>] | Power BI workloads [>] | Native pipelines [>] | Stored procedures [>] | |
| Dynamic tables [>] | Native Applications [>] | Custom applications [>] | Ad hoc activity [>]             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| WORKLOAD MIX                                                                                             |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Group by verified application type. Unknown metadata remains unknown, not force classified.              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| EXECUTION HIERARCHY                                                                                      |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Project/application → environment → invocation/activity → model/hash → query. Native pipelines use       |
| verified parent IDs.                                                                                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Workload                  | Type                      | Compute USD               | Evidence                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| finance_daily             | dbt                       | 8,400.00                  | Explicit metadata         |
| marketing_refresh         | Power BI                  | 5,600.00                  | Verified activity         |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Confidence and missing identifiers remain visible at every drilldown.                                    |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `querycompute` | Query compute: **$14,000.00** | Attribution within warehouse charge | August 2026 / synthetic; RECONCILED |
| `queries` | Completed queries: **12,480** | 7,488 Finance + 4,992 Marketing | August 2026 / synthetic; Observed |
| `classified` | Classified compute: **100%** | 14,000 assigned / 14,000 observed | August 2026 / synthetic; Observed |
| `unknown` | Unclassified groups: **0** | Observed fixture only | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Workload mix**: Group by verified application type. Unknown metadata remains unknown, not force classified.
- **Execution hierarchy**: Project/application → environment → invocation/activity → model/hash → query. Native pipelines use verified parent IDs.
- **DataTable** columns, in order: Workload, Type, Compute USD, Evidence. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/dbt`, `/power-bi`, `/pipelines`, `/procedures`, `/dynamic-tables`, `/native-apps`, `/custom-apps`, `/ad-hoc`. Use named links; never assume every row represents the same execution.

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
| Goal | Connect technical activity to business purpose. |
| Entry point | Explore navigation; deep link supported. |
| Happy path | Read context → inspect Workload mix → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No workloads for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: dbt, power-bi, pipelines, procedures, dynamic-tables, native-apps, custom-apps, ad-hoc. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Confidence and missing identifiers remain visible at every drilldown. |

### Domain subtleties

Confidence and missing identifiers remain visible at every drilldown.

Project/application → environment → invocation/activity → model/hash → query. Native pipelines use verified parent IDs.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Workloads                                |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Workload mix                             |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/workloads` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `querycompute` explanation and status.
- [ ] Inspect exact columns: Workload, Type, Compute USD, Evidence. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## dbt — dbt intelligence

Route: `/dbt` (prototype `#/dbt`). Persona: **FinOps analyst / data engineer**.

Goal: Projects, invocations and model costs in context.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  dbt intelligence                                                      |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Projects, invocations and model costs in context.                                                        |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DBT QUERY COMPUTE: $8,400.00 [i]  ||  VERIFIED INVOCATIONS: 30 [i]                                       |
| Finance workload subset  ||  Only count explicit invocation IDs                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MODEL GROUPS: 3 [i]  ||  FAILED INVOCATIONS: 0 [i]                                                       |
| Verified project models  ||  Complete synthetic observations                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: finance_daily [>]                                                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PROJECT TREND                                                                                            |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Observed query compute, not a second billed cost stream.                                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| COVERAGE                                                                                                 |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| The fixture contains verified invocation IDs. Without IDs, production shows inferred session groups      |
| without exact run-count claims.                                                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Project                   | Environment               | Compute USD               | Identification            |
+---------------------------+---------------------------+---------------------------+---------------------------+
| finance_daily             | Production                | 8,400.00                  | Verified query metadata   |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| No artifact upload is required for baseline coverage; lineage detail is conditional on evidence.         |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `dbtcost` | dbt query compute: **$8,400.00** | Finance workload subset | August 2026 / synthetic; RECONCILED |
| `dbtruns` | Verified invocations: **30** | Only count explicit invocation IDs | August 2026 / synthetic; Observed |
| `dbtmodels` | Model groups: **3** | Verified project models | August 2026 / synthetic; Observed |
| `dbtfail` | Failed invocations: **0** | Complete synthetic observations | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Project trend**: Observed query compute, not a second billed cost stream.
- **Coverage**: The fixture contains verified invocation IDs. Without IDs, production shows inferred session groups without exact run-count claims.
- **DataTable** columns, in order: Project, Environment, Compute USD, Identification. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `workloads`; breadcrumb and browser Back preserve scope.
- **Drilldowns**: `/dbt-project`. Use named links; never assume every row represents the same execution.

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
| Goal | Projects, invocations and model costs in context. |
| Entry point | Parent route /workloads; deep link supported. |
| Happy path | Read context → inspect Project trend → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No dbt intelligence for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: dbt-project. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; No artifact upload is required for baseline coverage; lineage detail is conditional on evidence. |

### Domain subtleties

No artifact upload is required for baseline coverage; lineage detail is conditional on evidence.

The fixture contains verified invocation IDs. Without IDs, production shows inferred session groups without exact run-count claims.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| dbt intelligence                         |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Project trend                            |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/dbt` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `dbtcost` explanation and status.
- [ ] Inspect exact columns: Project, Environment, Compute USD, Identification. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## dbt-project — finance_daily

Route: `/dbt-project` (prototype `#/dbt-project`). Persona: **FinOps analyst / data engineer**.

Goal: dbt project · Production · Finance

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  finance_daily                                                         |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| dbt project · Production · Finance                                                                       |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DBT QUERY COMPUTE: $8,400.00 [i]  ||  VERIFIED INVOCATIONS: 30 [i]                                       |
| Finance workload subset  ||  Only count explicit invocation IDs                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MODEL GROUPS: 3 [i]  ||  FAILED INVOCATIONS: 0 [i]                                                       |
| Verified project models  ||  Complete synthetic observations                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Invocation · inv_0830 [>] | fct_sales [>]                                                      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PROJECT PERFORMANCE                                                                                      |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| 30 observed invocations, three model groups, 8,400 total query compute over August.                      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MODEL CONTRIBUTION                                                                                       |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| fct_sales 4,200; dim_customer 2,520; agg_revenue 1,680. These sum to project compute.                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Invocation                | Started UTC               | Cost USD                  | Status                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| inv_0828                  | Aug 28 02:00              | 280.00                    | Success                   |
| inv_0829                  | Aug 29 02:00              | 280.00                    | Success                   |
| inv_0830                  | Aug 30 02:00              | 280.00                    | Success                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Three displayed invocations are a sample of 30; sample subtotal 840 is not the full project total.       |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `dbtcost` | dbt query compute: **$8,400.00** | Finance workload subset | August 2026 / synthetic; RECONCILED |
| `dbtruns` | Verified invocations: **30** | Only count explicit invocation IDs | August 2026 / synthetic; Observed |
| `dbtmodels` | Model groups: **3** | Verified project models | August 2026 / synthetic; Observed |
| `dbtfail` | Failed invocations: **0** | Complete synthetic observations | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Project performance**: 30 observed invocations, three model groups, 8,400 total query compute over August.
- **Model contribution**: fct_sales 4,200; dim_customer 2,520; agg_revenue 1,680. These sum to project compute.
- **DataTable** columns, in order: Invocation, Started UTC, Cost USD, Status. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `dbt`; breadcrumb and browser Back preserve scope.
- **Drilldowns**: `/dbt-invocation`, `/dbt-model`. Use named links; never assume every row represents the same execution.

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
| Goal | dbt project · Production · Finance |
| Entry point | Parent route /dbt; deep link supported. |
| Happy path | Read context → inspect Project performance → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No finance_daily for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: dbt-invocation, dbt-model. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Three displayed invocations are a sample of 30; sample subtotal 840 is not the full project total. |

### Domain subtleties

Three displayed invocations are a sample of 30; sample subtotal 840 is not the full project total.

fct_sales 4,200; dim_customer 2,520; agg_revenue 1,680. These sum to project compute.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| finance_daily                            |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Project performance                      |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/dbt-project` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `dbtcost` explanation and status.
- [ ] Inspect exact columns: Invocation, Started UTC, Cost USD, Status. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## dbt-invocation — Invocation · inv_0830

Route: `/dbt-invocation` (prototype `#/dbt-invocation`). Persona: **FinOps analyst / data engineer**.

Goal: finance_daily · Aug 30 02:00 UTC · verified invocation ID

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Invocation · inv_0830                                                 |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| finance_daily · Aug 30 02:00 UTC · verified invocation ID                                                |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| INVOCATION COMPUTE: $280.00 [i]  ||  WALL DURATION: 13 min [i]                                           |
| 140 + 84 + 56  ||  Concurrent models; duration sum is 17 min                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MODELS EXECUTED: 3 [i]  ||  EXECUTION STATUS: SUCCESS [i]                                                |
| All three succeeded  ||  Complete verified fixture                                                       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| EXECUTION GRAPH                                                                                          |
|      [Root / parallel inputs] ---> [dependent execution] ---> [evidence]                                 |
| dim_customer and fct_sales run concurrently; agg_revenue follows. Wall duration 13 min; sum of model     |
| durations 17 min.                                                                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CRITICAL PATH                                                                                            |
|      [Root / parallel inputs] ---> [dependent execution] ---> [evidence]                                 |
| fct_sales → agg_revenue. Cost 140 + 84 + 56 = 280; overlap changes duration, not conserved cost.         |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Model                     | Compute USD               | Wall time                 | Status                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| fct_sales                 | 140.00                    | 8 min                     | Success                   |
| dim_customer              | 84.00                     | 4 min                     | Success                   |
| agg_revenue               | 56.00                     | 5 min                     | Success                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Graph links are verified in this fixture; missing lineage must not create inferred exact dependencies.   |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `runcost` | Invocation compute: **$280.00** | 140 + 84 + 56 | inv_0830 / Aug 30; FINAL |
| `runduration` | Wall duration: **13 min** | Concurrent models; duration sum is 17 min | August 2026 / synthetic; Observed |
| `runmodels` | Models executed: **3** | All three succeeded | August 2026 / synthetic; Observed |
| `runstatus` | Execution status: **SUCCESS** | Complete verified fixture | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Execution graph**: dim_customer and fct_sales run concurrently; agg_revenue follows. Wall duration 13 min; sum of model durations 17 min.
- **Critical path**: fct_sales → agg_revenue. Cost 140 + 84 + 56 = 280; overlap changes duration, not conserved cost.
- **DataTable** columns, in order: Model, Compute USD, Wall time, Status. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `dbt-project`; breadcrumb and browser Back preserve scope.

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
| Goal | finance_daily · Aug 30 02:00 UTC · verified invocation ID |
| Entry point | Parent route /dbt-project; deep link supported. |
| Happy path | Read context → inspect Execution graph → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No invocation · inv_0830 for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Graph links are verified in this fixture; missing lineage must not create inferred exact dependencies. |

### Domain subtleties

Graph links are verified in this fixture; missing lineage must not create inferred exact dependencies.

fct_sales → agg_revenue. Cost 140 + 84 + 56 = 280; overlap changes duration, not conserved cost.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Invocation · inv_0830                    |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Execution graph                          |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/dbt-invocation` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `runcost` explanation and status.
- [ ] Inspect exact columns: Model, Compute USD, Wall time, Status. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## dbt-model — fct_sales

Route: `/dbt-model` (prototype `#/dbt-model`). Persona: **FinOps analyst / data engineer**.

Goal: Model history · finance_daily · sanitized query hash

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  fct_sales                                                             |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Model history · finance_daily · sanitized query hash                                                     |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MODEL COMPUTE: $4,200.00 [i]  ||  MODEL EXECUTIONS: 30 [i]                                               |
| 30 model executions × 140  ||  Verified IDs in August                                                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MODEL P95 DURATION: 8 min [i]  ||  MODEL FAILURE RATE: 0% [i]                                            |
| Synthetic individual executions  ||  0 / 30 observed executions                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| COST PER EXECUTION                                                                                       |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| 30 observed model executions at 140 USD = 4,200 USD. Normalized cost uses actual processed units when    |
| available.                                                                                               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| REGRESSION INVESTIGATION                                                                                 |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Compare common complete observations; distinguish changed query hash and changed data volume before      |
| claiming regression.                                                                                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Run                       | Compute USD               | Rows processed            | Status                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| inv_0828                  | 140.00                    | 1.2 M                     | Success                   |
| inv_0829                  | 140.00                    | 1.2 M                     | Success                   |
| inv_0830                  | 140.00                    | 1.2 M                     | Success                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| No percentiles averaged across daily percentiles.                                                        |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `modelcost` | Model compute: **$4,200.00** | 30 model executions × 140 | August 2026 / synthetic; RECONCILED |
| `modelruns` | Model executions: **30** | Verified IDs in August | August 2026 / synthetic; Observed |
| `modelp95` | Model P95 duration: **8 min** | Synthetic individual executions | August 2026 / synthetic; Observed |
| `modelfailure` | Model failure rate: **0%** | 0 / 30 observed executions | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Cost per execution**: 30 observed model executions at 140 USD = 4,200 USD. Normalized cost uses actual processed units when available.
- **Regression investigation**: Compare common complete observations; distinguish changed query hash and changed data volume before claiming regression.
- **DataTable** columns, in order: Run, Compute USD, Rows processed, Status. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `dbt-project`; breadcrumb and browser Back preserve scope.

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
| Goal | Model history · finance_daily · sanitized query hash |
| Entry point | Parent route /dbt-project; deep link supported. |
| Happy path | Read context → inspect Cost per execution → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No fct_sales for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; No percentiles averaged across daily percentiles. |

### Domain subtleties

No percentiles averaged across daily percentiles.

Compare common complete observations; distinguish changed query hash and changed data volume before claiming regression.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| fct_sales                                |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Cost per execution                       |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/dbt-model` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `modelcost` explanation and status.
- [ ] Inspect exact columns: Run, Compute USD, Rows processed, Status. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## power-bi — Power BI workloads

Route: `/power-bi` (prototype `#/power-bi`). Persona: **FinOps analyst / data engineer**.

Goal: Understand Snowflake cost behind business reporting.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Power BI workloads                                                    |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Understand Snowflake cost behind business reporting.                                                     |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| POWER BI COMPUTE: $5,600.00 [i]  ||  VERIFIED ACTIVITIES: 25 [i]                                         |
| Snowflake only · excludes Fabric  ||  Explicit ActivityId only                                           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| POWER BI QUERIES: 4,992 [i]  ||  UNCLASSIFIED GROUPS: 0 [i]                                              |
| August query count  ||  Observed fixture only                                                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Activity · pbi_0830 [>]                                                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| REFRESH AND QUERY PATTERNS                                                                               |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Import refreshes versus DirectQuery are separate classifications. Dataset/report identity is optional.   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SCOPE OF COST                                                                                            |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Only Snowflake compute is shown. Fabric capacity units and Power BI licensing are excluded.              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Application               | Mode                      | Compute USD               | Identification            |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Marketing reporting       | Import                    | 5,600.00                  | Verified ActivityId       |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Unknown mode or missing ActivityId remains explicit.                                                     |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `pbicost` | Power BI compute: **$5,600.00** | Snowflake only · excludes Fabric | August 2026 / synthetic; RECONCILED |
| `pbiactivities` | Verified activities: **25** | Explicit ActivityId only | August 2026 / synthetic; Observed |
| `pbiqueries` | Power BI queries: **4,992** | August query count | August 2026 / synthetic; Observed |
| `unknown` | Unclassified groups: **0** | Observed fixture only | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Refresh and query patterns**: Import refreshes versus DirectQuery are separate classifications. Dataset/report identity is optional.
- **Scope of cost**: Only Snowflake compute is shown. Fabric capacity units and Power BI licensing are excluded.
- **DataTable** columns, in order: Application, Mode, Compute USD, Identification. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `workloads`; breadcrumb and browser Back preserve scope.
- **Drilldowns**: `/power-bi-activity`. Use named links; never assume every row represents the same execution.

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
| Goal | Understand Snowflake cost behind business reporting. |
| Entry point | Parent route /workloads; deep link supported. |
| Happy path | Read context → inspect Refresh and query patterns → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No power bi workloads for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: power-bi-activity. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Unknown mode or missing ActivityId remains explicit. |

### Domain subtleties

Unknown mode or missing ActivityId remains explicit.

Only Snowflake compute is shown. Fabric capacity units and Power BI licensing are excluded.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Power BI workloads                       |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Refresh and query patterns               |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/power-bi` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `pbicost` explanation and status.
- [ ] Inspect exact columns: Application, Mode, Compute USD, Identification. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## power-bi-activity — Activity · pbi_0830

Route: `/power-bi-activity` (prototype `#/power-bi-activity`). Persona: **FinOps analyst / data engineer**.

Goal: Marketing reporting · Import refresh · verified ActivityId

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Activity · pbi_0830                                                   |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Marketing reporting · Import refresh · verified ActivityId                                               |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ACTIVITY COMPUTE: $224.00 [i]  ||  ACTIVITY WALL TIME: 8 min [i]                                         |
| 56 + 168  ||  Representative activity                                                                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ACTIVITY QUERIES: 32 [i]  ||  EXECUTION STATUS: SUCCESS [i]                                              |
| 8 dimension + 24 fact  ||  Complete verified fixture                                                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ACTIVITY TIMELINE                                                                                        |
|      Compile | Queue | Execution --------------------> [Evidence]                                        |
| 32 queries in the representative activity; 224 USD belongs inside the 5,600 aggregate.                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| REPORT CONTEXT                                                                                           |
|      Compile | Queue | Execution --------------------> [Evidence]                                        |
| Dataset: Marketing semantic model; report identity not observed. Do not guess report ownership from SQL  |
| text.                                                                                                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Step                      | Queries                   | Compute USD               | Evidence                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Dimension refresh         | 8                         | 56.00                     | ActivityId                |
| Fact refresh              | 24                        | 168.00                    | ActivityId                |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Activity and monthly count metrics use distinct periods labelled in their panels.                        |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `pbiactivitycost` | Activity compute: **$224.00** | 56 + 168 | pbi_0830 / Aug 30; FINAL |
| `pbiduration` | Activity wall time: **8 min** | Representative activity | August 2026 / synthetic; Observed |
| `pbiquerycount` | Activity queries: **32** | 8 dimension + 24 fact | August 2026 / synthetic; Observed |
| `runstatus` | Execution status: **SUCCESS** | Complete verified fixture | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Activity timeline**: 32 queries in the representative activity; 224 USD belongs inside the 5,600 aggregate.
- **Report context**: Dataset: Marketing semantic model; report identity not observed. Do not guess report ownership from SQL text.
- **DataTable** columns, in order: Step, Queries, Compute USD, Evidence. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `power-bi`; breadcrumb and browser Back preserve scope.

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
| Goal | Marketing reporting · Import refresh · verified ActivityId |
| Entry point | Parent route /power-bi; deep link supported. |
| Happy path | Read context → inspect Activity timeline → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No activity · pbi_0830 for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Activity and monthly count metrics use distinct periods labelled in their panels. |

### Domain subtleties

Activity and monthly count metrics use distinct periods labelled in their panels.

Dataset: Marketing semantic model; report identity not observed. Do not guess report ownership from SQL text.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Activity · pbi_0830                      |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Activity timeline                        |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/power-bi-activity` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `pbiactivitycost` explanation and status.
- [ ] Inspect exact columns: Step, Queries, Compute USD, Evidence. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## pipelines — Native pipelines

Route: `/pipelines` (prototype `#/pipelines`). Persona: **FinOps analyst / data engineer**.

Goal: Tasks, procedures and dynamic tables with verified lineage.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Native pipelines                                                      |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Tasks, procedures and dynamic tables with verified lineage.                                              |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TASK PIPELINE COST: $700.00 [i]  ||  OBSERVED PIPELINE: 1 [i]                                            |
| Included in serverless total  ||  Verified native task lineage                                           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| FAILED TASK RUNS: 0 [i]  ||  OBSERVED FRESHNESS LAG: 4 min [i]                                           |
| Complete observed fixture  ||  Against 5 min target                                                      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: revenue_refresh [>]                                                                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PIPELINE OVERVIEW                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Native IDs provide parent/child links; shared execution charges are attributed once.                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| FRESHNESS                                                                                                |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Target lag is a service objective; distinguish current lag, observation coverage and failed activity.    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Pipeline                  | Type                      | Cost USD                  | Status                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| revenue_refresh           | Serverless task           | 700.00                    | Healthy                   |
| inventory_transform       | Dynamic table             | —                         | No observations           |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Serverless task cost is inside serverless 1,800, not an additional charge.                               |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `pipelinecost` | Task pipeline cost: **$700.00** | Included in serverless total | August 2026 / synthetic; RECONCILED |
| `pipelines` | Observed pipeline: **1** | Verified native task lineage | August 2026 / synthetic; Observed |
| `pipelinefailure` | Failed task runs: **0** | Complete observed fixture | August 2026 / synthetic; Observed |
| `lag` | Observed freshness lag: **4 min** | Against 5 min target | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Pipeline overview**: Native IDs provide parent/child links; shared execution charges are attributed once.
- **Freshness**: Target lag is a service objective; distinguish current lag, observation coverage and failed activity.
- **DataTable** columns, in order: Pipeline, Type, Cost USD, Status. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `workloads`; breadcrumb and browser Back preserve scope.
- **Drilldowns**: `/pipeline-detail`. Use named links; never assume every row represents the same execution.

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
| Goal | Tasks, procedures and dynamic tables with verified lineage. |
| Entry point | Parent route /workloads; deep link supported. |
| Happy path | Read context → inspect Pipeline overview → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No native pipelines for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: pipeline-detail. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Serverless task cost is inside serverless 1,800, not an additional charge. |

### Domain subtleties

Serverless task cost is inside serverless 1,800, not an additional charge.

Target lag is a service objective; distinguish current lag, observation coverage and failed activity.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Native pipelines                         |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Pipeline overview                        |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/pipelines` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `pipelinecost` explanation and status.
- [ ] Inspect exact columns: Pipeline, Type, Cost USD, Status. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## pipeline-detail — revenue_refresh

Route: `/pipeline-detail` (prototype `#/pipeline-detail`). Persona: **FinOps analyst / data engineer**.

Goal: Serverless task graph · Finance · verified task IDs

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  revenue_refresh                                                       |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Serverless task graph · Finance · verified task IDs                                                      |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TASK PIPELINE COST: $700.00 [i]  ||  OBSERVED PIPELINE: 1 [i]                                            |
| Included in serverless total  ||  Verified native task lineage                                           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| FAILED TASK RUNS: 0 [i]  ||  OBSERVED FRESHNESS LAG: 4 min [i]                                           |
| Complete observed fixture  ||  Against 5 min target                                                      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DEPENDENCY GRAPH                                                                                         |
|      [Root / parallel inputs] ---> [dependent execution] ---> [evidence]                                 |
| ingest_events precedes aggregate_revenue; total 700 USD once per charge identity.                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| FAILURE PATH                                                                                             |
|      [Root / parallel inputs] ---> [dependent execution] ---> [evidence]                                 |
| A retry appears as an attempt under the same logical run. Inspect exact failed edge and safe evidence.   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Node                      | Role                      | Cost USD                  | Status                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| ingest_events             | Root                      | 280.00                    | Success                   |
| aggregate_revenue         | Child                     | 420.00                    | Success                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| No arbitrary customer-specific workflow code is implied.                                                 |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `pipelinecost` | Task pipeline cost: **$700.00** | Included in serverless total | August 2026 / synthetic; RECONCILED |
| `pipelines` | Observed pipeline: **1** | Verified native task lineage | August 2026 / synthetic; Observed |
| `pipelinefailure` | Failed task runs: **0** | Complete observed fixture | August 2026 / synthetic; Observed |
| `lag` | Observed freshness lag: **4 min** | Against 5 min target | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Dependency graph**: ingest_events precedes aggregate_revenue; total 700 USD once per charge identity.
- **Failure path**: A retry appears as an attempt under the same logical run. Inspect exact failed edge and safe evidence.
- **DataTable** columns, in order: Node, Role, Cost USD, Status. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `pipelines`; breadcrumb and browser Back preserve scope.

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
| Goal | Serverless task graph · Finance · verified task IDs |
| Entry point | Parent route /pipelines; deep link supported. |
| Happy path | Read context → inspect Dependency graph → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No revenue_refresh for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; No arbitrary customer-specific workflow code is implied. |

### Domain subtleties

No arbitrary customer-specific workflow code is implied.

A retry appears as an attempt under the same logical run. Inspect exact failed edge and safe evidence.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| revenue_refresh                          |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Dependency graph                         |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/pipeline-detail` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `pipelinecost` explanation and status.
- [ ] Inspect exact columns: Node, Role, Cost USD, Status. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## procedures — Stored procedures

Route: `/procedures` (prototype `#/procedures`). Persona: **FinOps analyst / data engineer**.

Goal: Separate parent invocation from attributed child queries.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Stored procedures                                                     |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Separate parent invocation from attributed child queries.                                                |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ATTRIBUTION COVERAGE: — [i]                                                                              |
| Unavailable: required linkage or usage telemetry not observed                                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CALL HIERARCHY                                                                                           |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Parent procedure and child query links require verified IDs; do not infer exact call structure from      |
| similar SQL.                                                                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| COST ACCOUNTING                                                                                          |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Charge each query once, then attribute it to the procedure when evidence permits. Parent runtime and     |
| summed child runtime differ.                                                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Procedure                 | Observed cost             | Child linkage             | Coverage                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| rebuild_summary           | —                         | Not observed              | Unavailable               |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| The unobserved sample procedure has no synthetic billed amount. Query compute KPI is broader account     |
| context and labelled as such.                                                                            |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `unavailable` | Attribution coverage: **—** | Unavailable: required linkage or usage telemetry not observed | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Call hierarchy**: Parent procedure and child query links require verified IDs; do not infer exact call structure from similar SQL.
- **Cost accounting**: Charge each query once, then attribute it to the procedure when evidence permits. Parent runtime and summed child runtime differ.
- **DataTable** columns, in order: Procedure, Observed cost, Child linkage, Coverage. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `workloads`; breadcrumb and browser Back preserve scope.

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
| Goal | Separate parent invocation from attributed child queries. |
| Entry point | Parent route /workloads; deep link supported. |
| Happy path | Read context → inspect Call hierarchy → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No stored procedures for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; The unobserved sample procedure has no synthetic billed amount. Query compute KPI is broader account context and labelled as such. |

### Domain subtleties

The unobserved sample procedure has no synthetic billed amount. Query compute KPI is broader account context and labelled as such.

Charge each query once, then attribute it to the procedure when evidence permits. Parent runtime and summed child runtime differ.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Stored procedures                        |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Call hierarchy                           |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/procedures` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `unavailable` explanation and status.
- [ ] Inspect exact columns: Procedure, Observed cost, Child linkage, Coverage. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## dynamic-tables — Dynamic tables

Route: `/dynamic-tables` (prototype `#/dynamic-tables`). Persona: **FinOps analyst / data engineer**.

Goal: Refresh cost and freshness objectives together.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Dynamic tables                                                        |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Refresh cost and freshness objectives together.                                                          |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ATTRIBUTION COVERAGE: — [i]                                                                              |
| Unavailable: required linkage or usage telemetry not observed                                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| REFRESH HISTORY                                                                                          |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Refresh mode, timestamps, rows, warehouse and status are evidence fields; missing cost attribution       |
| remains null.                                                                                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SLA INVESTIGATION                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| A missed freshness target is distinct from missing refresh telemetry. Link source coverage before        |
| calling it a failed refresh.                                                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Dynamic table             | Refresh cost              | Target lag                | State                     |
+---------------------------+---------------------------+---------------------------+---------------------------+
| inventory_transform       | —                         | 5 min                     | No observations           |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| No fabricated cost or exact refresh count when refresh history is unavailable.                           |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `unavailable` | Attribution coverage: **—** | Unavailable: required linkage or usage telemetry not observed | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Refresh history**: Refresh mode, timestamps, rows, warehouse and status are evidence fields; missing cost attribution remains null.
- **SLA investigation**: A missed freshness target is distinct from missing refresh telemetry. Link source coverage before calling it a failed refresh.
- **DataTable** columns, in order: Dynamic table, Refresh cost, Target lag, State. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `workloads`; breadcrumb and browser Back preserve scope.

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
| Goal | Refresh cost and freshness objectives together. |
| Entry point | Parent route /workloads; deep link supported. |
| Happy path | Read context → inspect Refresh history → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No dynamic tables for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; No fabricated cost or exact refresh count when refresh history is unavailable. |

### Domain subtleties

No fabricated cost or exact refresh count when refresh history is unavailable.

A missed freshness target is distinct from missing refresh telemetry. Link source coverage before calling it a failed refresh.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Dynamic tables                           |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Refresh history                          |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/dynamic-tables` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `unavailable` explanation and status.
- [ ] Inspect exact columns: Dynamic table, Refresh cost, Target lag, State. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## native-apps — Native Applications

Route: `/native-apps` (prototype `#/native-apps`). Persona: **FinOps analyst / data engineer**.

Goal: Provider fees and execution costs as distinct components.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Native Applications                                                   |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Provider fees and execution costs as distinct components.                                                |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| APPLICATION FEES: $1,000.00 [i]  ||  ATTRIBUTION COVERAGE: — [i]                                         |
| Already included in ledger  ||  Unavailable: required linkage or usage telemetry not observed            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| COST LAYERS                                                                                              |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| The 1,000 USD application fee is already in the ledger. Compute may belong to warehouse/SPCS parents; do |
| not add allocated compute twice.                                                                         |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| OWNERSHIP                                                                                                |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Verified installation/application IDs map to external ownership. Provider identities and contracts are   |
| permission scoped.                                                                                       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Application               | Fee USD                   | Compute attribution       | Billing basis             |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Partner analytics         | 1,000.00                  | —                         | Contract fee              |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Application fee is observed; execution linkage is unavailable in the fixture.                            |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `appfees` | Application fees: **$1,000.00** | Already included in ledger | August 2026 / synthetic; RECONCILED |
| `unavailable` | Attribution coverage: **—** | Unavailable: required linkage or usage telemetry not observed | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Cost layers**: The 1,000 USD application fee is already in the ledger. Compute may belong to warehouse/SPCS parents; do not add allocated compute twice.
- **Ownership**: Verified installation/application IDs map to external ownership. Provider identities and contracts are permission scoped.
- **DataTable** columns, in order: Application, Fee USD, Compute attribution, Billing basis. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `workloads`; breadcrumb and browser Back preserve scope.

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
| Goal | Provider fees and execution costs as distinct components. |
| Entry point | Parent route /workloads; deep link supported. |
| Happy path | Read context → inspect Cost layers → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No native applications for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Application fee is observed; execution linkage is unavailable in the fixture. |

### Domain subtleties

Application fee is observed; execution linkage is unavailable in the fixture.

Verified installation/application IDs map to external ownership. Provider identities and contracts are permission scoped.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Native Applications                      |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Cost layers                              |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/native-apps` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `appfees` explanation and status.
- [ ] Inspect exact columns: Application, Fee USD, Compute attribution, Billing basis. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## custom-apps — Custom applications

Route: `/custom-apps` (prototype `#/custom-apps`). Persona: **FinOps analyst / data engineer**.

Goal: Verified application identity before cost attribution.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Custom applications                                                   |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Verified application identity before cost attribution.                                                   |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ATTRIBUTION COVERAGE: — [i]                                                                              |
| Unavailable: required linkage or usage telemetry not observed                                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CLASSIFICATION                                                                                           |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Explicit application metadata outranks weak query-type heuristics. Conflicting evidence stays            |
| unresolved.                                                                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| JOURNEY                                                                                                  |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Application → environment → activity → query. Show unavailable child levels when IDs are missing.        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Application               | Observed compute          | Identity evidence         | Coverage                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Internal planning         | —                         | No verified session ID    | Unavailable               |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Do not invent application cost by subtracting unrelated known categories.                                |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `unavailable` | Attribution coverage: **—** | Unavailable: required linkage or usage telemetry not observed | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Classification**: Explicit application metadata outranks weak query-type heuristics. Conflicting evidence stays unresolved.
- **Journey**: Application → environment → activity → query. Show unavailable child levels when IDs are missing.
- **DataTable** columns, in order: Application, Observed compute, Identity evidence, Coverage. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `workloads`; breadcrumb and browser Back preserve scope.

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
| Goal | Verified application identity before cost attribution. |
| Entry point | Parent route /workloads; deep link supported. |
| Happy path | Read context → inspect Classification → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No custom applications for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Do not invent application cost by subtracting unrelated known categories. |

### Domain subtleties

Do not invent application cost by subtracting unrelated known categories.

Application → environment → activity → query. Show unavailable child levels when IDs are missing.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Custom applications                      |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Classification                           |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/custom-apps` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `unavailable` explanation and status.
- [ ] Inspect exact columns: Application, Observed compute, Identity evidence, Coverage. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## ad-hoc — Ad hoc activity

Route: `/ad-hoc` (prototype `#/ad-hoc`). Persona: **FinOps analyst / data engineer**.

Goal: Make unclassified usage inspectable without exposing query secrets.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Ad hoc activity                                                       |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Make unclassified usage inspectable without exposing query secrets.                                      |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ATTRIBUTION COVERAGE: — [i]                                                                              |
| Unavailable: required linkage or usage telemetry not observed                                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| UNKNOWN OWNERSHIP                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Unknown classification is a valid bucket, not a default assignment to a guessed user or team.            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| INVESTIGATION                                                                                            |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Authorized query hashes, sanitized text and role metadata support manual review. Group-restricted        |
| viewers receive only their scope.                                                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Category                  | Observed cost             | Sanitized hash            | Coverage                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Ad hoc / unknown          | —                         | Not observed              | Unavailable               |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| This unavailable fixture is not evidence of zero ad hoc cost; the two known query groups cover the       |
| observed compute example.                                                                                |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `unavailable` | Attribution coverage: **—** | Unavailable: required linkage or usage telemetry not observed | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Unknown ownership**: Unknown classification is a valid bucket, not a default assignment to a guessed user or team.
- **Investigation**: Authorized query hashes, sanitized text and role metadata support manual review. Group-restricted viewers receive only their scope.
- **DataTable** columns, in order: Category, Observed cost, Sanitized hash, Coverage. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `workloads`; breadcrumb and browser Back preserve scope.

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
| Goal | Make unclassified usage inspectable without exposing query secrets. |
| Entry point | Parent route /workloads; deep link supported. |
| Happy path | Read context → inspect Unknown ownership → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No ad hoc activity for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; This unavailable fixture is not evidence of zero ad hoc cost; the two known query groups cover the observed compute example. |

### Domain subtleties

This unavailable fixture is not evidence of zero ad hoc cost; the two known query groups cover the observed compute example.

Authorized query hashes, sanitized text and role metadata support manual review. Group-restricted viewers receive only their scope.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Ad hoc activity                          |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Unknown ownership                        |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/ad-hoc` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `unavailable` explanation and status.
- [ ] Inspect exact columns: Category, Observed cost, Sanitized hash, Coverage. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

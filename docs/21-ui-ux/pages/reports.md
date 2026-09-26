# Reports — detailed screen design

Design unit: `reports`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../14-reporting/reporting.md).

This file covers 4 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## reports — Reports

Route: `/reports` (prototype `#/reports`). Persona: **FinOps lead / finance controller**.

Goal: Decision-ready reports, built from the same numbers.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  GOVERN  /  Reports                                                                |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Decision-ready reports, built from the same numbers.                                                     |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| REPORT TEMPLATES: 8 [i]  ||  ACTIVE DEMO SCHEDULES: 2 [i]                                                |
| All required audience templates  ||  No external scheduler connected                                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| FAILED PREVIEW JOB: 1 [i]  ||  READY ARTIFACTS: 2 [i]                                                    |
| Synthetic renderer failure  ||  Synthetic history only                                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Executive FinOps report [>] | Schedule a report [>] | Report history [>]                       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TEMPLATE LIBRARY                                                                                         |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Eight approved templates. Widgets use shared metrics and retain scope/maturity/as-of.                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DELIVERY HISTORY                                                                                         |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Generation, authorization and delivery are separate states; a ready artifact is not proof of delivery.   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Template                  | Audience                  | Basis                     | Cadence                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Executive FinOps          | Leadership                | Signed net spend          | Weekly                    |
| CFO Monthly               | Finance                   | Ledger / reconciliation   | Monthly                   |
| Platform Review           | Engineering               | Cost / performance        | Weekly                    |
| Team Showback             | Team owner                | Selected book             | Monthly                   |
| Chargeback Statement      | Finance                   | Closed statement          | Monthly                   |
| Warehouse Review          | Platform                  | Warehouse component       | Weekly                    |
| dbt Review                | Data team                 | Query compute             | Weekly                    |
| AI / Cortex Review        | AI owner                  | Billed family             | Monthly                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Prototype offers printable preview and CSV. Production PDF worker and scheduled delivery are not         |
| implemented.                                                                                             |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `reporttemplates` | Report templates: **8** | All required audience templates | August 2026 / synthetic; Observed |
| `reportschedules` | Active demo schedules: **2** | No external scheduler connected | August 2026 / synthetic; Observed |
| `reportfail` | Failed preview job: **1** | Synthetic renderer failure | August 2026 / synthetic; Observed |
| `reportready` | Ready artifacts: **2** | Synthetic history only | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Template library**: Eight approved templates. Widgets use shared metrics and retain scope/maturity/as-of.
- **Delivery history**: Generation, authorization and delivery are separate states; a ready artifact is not proof of delivery.
- **DataTable** columns, in order: Template, Audience, Basis, Cadence. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/report-builder`, `/report-schedule`, `/report-history`. Use named links; never assume every row represents the same execution.

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
| Persona | FinOps lead / finance controller |
| Goal | Decision-ready reports, built from the same numbers. |
| Entry point | Govern navigation; deep link supported. |
| Happy path | Read context → inspect Template library → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No reports for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: report-builder, report-schedule, report-history. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Prototype offers printable preview and CSV. Production PDF worker and scheduled delivery are not implemented. |

### Domain subtleties

Prototype offers printable preview and CSV. Production PDF worker and scheduled delivery are not implemented.

Generation, authorization and delivery are separate states; a ready artifact is not proof of delivery.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Reports                                  |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Template library                         |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/reports` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `reporttemplates` explanation and status.
- [ ] Inspect exact columns: Template, Audience, Basis, Cadence. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## report-builder — Executive FinOps report

Route: `/report-builder` (prototype `#/report-builder`). Persona: **FinOps lead / finance controller**.

Goal: Arrange a narrative from verified metrics.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  GOVERN  /  Executive FinOps report                                                |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Arrange a narrative from verified metrics.                                                               |
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
| CANVAS                                                                                                   |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Header → KPI strip → trend → service table → coverage footer. Move optional blocks without changing      |
| their formulas.                                                                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PREVIEW                                                                                                  |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Show page breaks, repeated table headers, currency, period, as-of and source publication.                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Block                     | Metric                    | Scope                     | Display                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Summary                   | spend                     | Organization              | KPI                       |
| Cost drivers              | service cost              | Organization              | Breakdown                 |
| Ownership                 | allocated cost            | Teams book                | Table                     |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| No user HTML, scripts or arbitrary remote URLs in report definitions.                                    |
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

- **Canvas**: Header → KPI strip → trend → service table → coverage footer. Move optional blocks without changing their formulas.
- **Preview**: Show page breaks, repeated table headers, currency, period, as-of and source publication.
- **DataTable** columns, in order: Block, Metric, Scope, Display. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save report draft. Opens labelled form fields; required values validate before local save. In production, server validates authorization, schema and stale version.
- **Parent**: `reports`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Save report draft                                           [X]            |
| Report title: [____________________________]                               |
| Template: [____________________________]                                   |
| Owner: [____________________________]                                      |
| Footer note: [____________________________]                                |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Save report draft]                                              |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | FinOps lead / finance controller |
| Goal | Arrange a narrative from verified metrics. |
| Entry point | Parent route /reports; deep link supported. |
| Happy path | Read context → inspect Canvas → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No executive finops report for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save report draft reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save report draft; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; No user HTML, scripts or arbitrary remote URLs in report definitions. |

### Domain subtleties

No user HTML, scripts or arbitrary remote URLs in report definitions.

Show page breaks, repeated table headers, currency, period, as-of and source publication.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Executive FinOps report                  |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Canvas                                   |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save report draft]                      |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/report-builder` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `spend` explanation and status.
- [ ] Inspect exact columns: Block, Metric, Scope, Display. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## report-schedule — Schedule a report

Route: `/report-schedule` (prototype `#/report-schedule`). Persona: **FinOps lead / finance controller**.

Goal: Deliver to authorized recipients at a predictable time.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  GOVERN  /  Schedule a report                                                      |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Deliver to authorized recipients at a predictable time.                                                  |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ACTIVE DEMO SCHEDULES: 2 [i]  ||  READY ARTIFACTS: 2 [i]                                                 |
| No external scheduler connected  ||  Synthetic history only                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| FAILED PREVIEW JOB: 1 [i]  ||  NEXT SCHEDULED DATE: Sep 30 [i]                                           |
| Synthetic renderer failure  ||  09:00 UTC; no real delivery                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CALENDAR SUBTLETIES                                                                                      |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| DST gap skipped and logged; ambiguous time uses earlier offset once; default catch-up only most recent   |
| missed occurrence.                                                                                       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SECURE DISTRIBUTION                                                                                      |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Authenticated links by default; permission revoked before dispatch pauses/regenerates under narrower     |
| scope.                                                                                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Setting                   | Value                     | Policy                    | Preview                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Cadence                   | Monthly                   | Day 31 clamps             | Sep 30                    |
| Time zone                 | UTC                       | Explicit IANA zone        | 09:00 UTC                 |
| Recipients                | Finance group             | Reauthorize at send       | 2 demo users              |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Saving a local schedule never triggers real email.                                                       |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `reportschedules` | Active demo schedules: **2** | No external scheduler connected | August 2026 / synthetic; Observed |
| `reportready` | Ready artifacts: **2** | Synthetic history only | August 2026 / synthetic; Observed |
| `reportfail` | Failed preview job: **1** | Synthetic renderer failure | August 2026 / synthetic; Observed |
| `nextdelivery` | Next scheduled date: **Sep 30** | 09:00 UTC; no real delivery | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Calendar subtleties**: DST gap skipped and logged; ambiguous time uses earlier offset once; default catch-up only most recent missed occurrence.
- **Secure distribution**: Authenticated links by default; permission revoked before dispatch pauses/regenerates under narrower scope.
- **DataTable** columns, in order: Setting, Value, Policy, Preview. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save schedule draft. Opens labelled form fields; required values validate before local save. In production, server validates authorization, schema and stale version.
- **Parent**: `reports`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Save schedule draft                                           [X]          |
| Schedule name: [____________________________]                              |
| Cadence: [____________________________]                                    |
| Time UTC: [____________________________]                                   |
| Recipient group: [____________________________]                            |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Save schedule draft]                                            |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | FinOps lead / finance controller |
| Goal | Deliver to authorized recipients at a predictable time. |
| Entry point | Parent route /reports; deep link supported. |
| Happy path | Read context → inspect Calendar subtleties → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No schedule a report for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save schedule draft reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save schedule draft; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Saving a local schedule never triggers real email. |

### Domain subtleties

Saving a local schedule never triggers real email.

Authenticated links by default; permission revoked before dispatch pauses/regenerates under narrower scope.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Schedule a report                        |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Calendar subtleties                      |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save schedule draft]                    |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/report-schedule` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `reportschedules` explanation and status.
- [ ] Inspect exact columns: Setting, Value, Policy, Preview. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## report-history — Report history

Route: `/report-history` (prototype `#/report-history`). Persona: **FinOps lead / finance controller**.

Goal: Track generation and delivery independently.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  GOVERN  /  Report history                                                         |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Track generation and delivery independently.                                                             |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| READY ARTIFACTS: 2 [i]  ||  FAILED PREVIEW JOB: 1 [i]                                                    |
| Synthetic history only  ||  Synthetic renderer failure                                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ACTIVE DEMO SCHEDULES: 2 [i]  ||  REPORT TEMPLATES: 8 [i]                                                |
| No external scheduler connected  ||  All required audience templates                                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| FAILURE DETAIL                                                                                           |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Render failure offers regenerate on same logical occurrence, with version and permission checks.         |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ACCESS                                                                                                   |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Production downloads reauthorize before granting a short-lived artifact access; historical broad export  |
| cannot bypass revoked scope.                                                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Run                       | Artifact                  | Delivery                  | Scope                     |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Aug CFO                   | Ready                     | Simulated sent            | Organization              |
| Aug showback              | Ready                     | Simulated sent            | Teams                     |
| Sep preview               | Failed                    | Not attempted             | Organization              |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| No real reports or recipient addresses are present.                                                      |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `reportready` | Ready artifacts: **2** | Synthetic history only | August 2026 / synthetic; Observed |
| `reportfail` | Failed preview job: **1** | Synthetic renderer failure | August 2026 / synthetic; Observed |
| `reportschedules` | Active demo schedules: **2** | No external scheduler connected | August 2026 / synthetic; Observed |
| `reporttemplates` | Report templates: **8** | All required audience templates | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Failure detail**: Render failure offers regenerate on same logical occurrence, with version and permission checks.
- **Access**: Production downloads reauthorize before granting a short-lived artifact access; historical broad export cannot bypass revoked scope.
- **DataTable** columns, in order: Run, Artifact, Delivery, Scope. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `reports`; breadcrumb and browser Back preserve scope.

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
| Persona | FinOps lead / finance controller |
| Goal | Track generation and delivery independently. |
| Entry point | Parent route /reports; deep link supported. |
| Happy path | Read context → inspect Failure detail → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No report history for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; No real reports or recipient addresses are present. |

### Domain subtleties

No real reports or recipient addresses are present.

Production downloads reauthorize before granting a short-lived artifact access; historical broad export cannot bypass revoked scope.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Report history                           |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Failure detail                           |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/report-history` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `reportready` explanation and status.
- [ ] Inspect exact columns: Run, Artifact, Delivery, Scope. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

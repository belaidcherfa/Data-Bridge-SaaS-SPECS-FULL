# Monitors & incidents — detailed screen design

Design unit: `monitors`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../12-budgets-monitoring/governance.md).

This file covers 3 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## monitors — Monitors & incidents

Route: `/monitors` (prototype `#/monitors`). Persona: **FinOps lead / finance controller**.

Goal: Signals with enough context to make a decision.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  GOVERN  /  Monitors & incidents                                                   |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Signals with enough context to make a decision.                                                          |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MONITOR DEFINITIONS: 2 [i]  ||  ACTIVE INCIDENTS: 1 [i]                                                  |
| One breach; one missing-data control  ||  One episode despite repeated breach                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| INSUFFICIENT DATA: 1 [i]  ||  ACTIVE SILENCES: 0 [i]                                                     |
| Never interpreted as recovery  ||  Owner and expiry required                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Create a monitor [>] | Incident · daily warehouse spend [>]                                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| INCIDENT INBOX                                                                                           |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| One episode per condition/partition; repeated evaluation attaches evidence rather than duplicate         |
| incidents.                                                                                               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| EVALUATION HEALTH                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Incomplete data never increments breach/recovery counters and never auto-resolves an incident.           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Monitor                   | Condition                 | State                     | Destination               |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Warehouse daily spend     | Over 100 USD twice        | OPEN                      | FinOps email              |
| Missing finance run       | Coverage required         | INSUFFICIENT_DATA         | Platform channel          |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| External notifications are simulated and labelled; none are sent.                                        |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `monitors` | Monitor definitions: **2** | One breach; one missing-data control | August 2026 / synthetic; Observed |
| `incidents` | Active incidents: **1** | One episode despite repeated breach | August 2026 / synthetic; Observed |
| `insufficient` | Insufficient data: **1** | Never interpreted as recovery | August 2026 / synthetic; Observed |
| `silenced` | Active silences: **0** | Owner and expiry required | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Incident inbox**: One episode per condition/partition; repeated evaluation attaches evidence rather than duplicate incidents.
- **Evaluation health**: Incomplete data never increments breach/recovery counters and never auto-resolves an incident.
- **DataTable** columns, in order: Monitor, Condition, State, Destination. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/monitor-new`, `/incident`. Use named links; never assume every row represents the same execution.

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
| Goal | Signals with enough context to make a decision. |
| Entry point | Govern navigation; deep link supported. |
| Happy path | Read context → inspect Incident inbox → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No monitors & incidents for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: monitor-new, incident. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; External notifications are simulated and labelled; none are sent. |

### Domain subtleties

External notifications are simulated and labelled; none are sent.

Incomplete data never increments breach/recovery counters and never auto-resolves an incident.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Monitors & incidents                     |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Incident inbox                           |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/monitors` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `monitors` explanation and status.
- [ ] Inspect exact columns: Monitor, Condition, State, Destination. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## monitor-new — Create a monitor

Route: `/monitor-new` (prototype `#/monitor-new`). Persona: **FinOps lead / finance controller**.

Goal: Choose a signal, its scope and the response.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  GOVERN  /  Create a monitor                                                       |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Choose a signal, its scope and the response.                                                             |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MONITOR DEFINITIONS: 2 [i]  ||  ACTIVE INCIDENTS: 1 [i]                                                  |
| One breach; one missing-data control  ||  One episode despite repeated breach                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| INSUFFICIENT DATA: 1 [i]  ||  ACTIVE SILENCES: 0 [i]                                                     |
| Never interpreted as recovery  ||  Owner and expiry required                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CONDITION BUILDER                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Dataset, metric, aggregation, complete window, condition, partition dimensions, cadence, severity,       |
| maturity and coverage.                                                                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PREVIEW EVALUATION                                                                                       |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| 101, 102 opens one incident; 103 attaches; missing data holds; 99, 98 recovers. Retry 102 does not       |
| duplicate.                                                                                               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Setting                   | Value                     | Validation                | Purpose                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Metric                    | spend USD                 | Registry-backed           | Same formula as explorer  |
| Threshold                 | 100.00                    | Decimal                   | Static breach             |
| Confirmations             | 2                         | Positive integer          | Avoid flapping            |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Destinations are references; never expose webhook credentials in UI.                                     |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `monitors` | Monitor definitions: **2** | One breach; one missing-data control | August 2026 / synthetic; Observed |
| `incidents` | Active incidents: **1** | One episode despite repeated breach | August 2026 / synthetic; Observed |
| `insufficient` | Insufficient data: **1** | Never interpreted as recovery | August 2026 / synthetic; Observed |
| `silenced` | Active silences: **0** | Owner and expiry required | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Condition builder**: Dataset, metric, aggregation, complete window, condition, partition dimensions, cadence, severity, maturity and coverage.
- **Preview evaluation**: 101, 102 opens one incident; 103 attaches; missing data holds; 99, 98 recovers. Retry 102 does not duplicate.
- **DataTable** columns, in order: Setting, Value, Validation, Purpose. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save monitor draft. Opens labelled form fields; required values validate before local save. In production, server validates authorization, schema and stale version.
- **Parent**: `monitors`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Save monitor draft                                           [X]           |
| Monitor name: [____________________________]                               |
| Threshold USD: [____________________________]                              |
| Partition dimension: [____________________________]                        |
| Destination: [____________________________]                                |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Save monitor draft]                                             |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | FinOps lead / finance controller |
| Goal | Choose a signal, its scope and the response. |
| Entry point | Parent route /monitors; deep link supported. |
| Happy path | Read context → inspect Condition builder → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No create a monitor for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save monitor draft reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save monitor draft; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Destinations are references; never expose webhook credentials in UI. |

### Domain subtleties

Destinations are references; never expose webhook credentials in UI.

101, 102 opens one incident; 103 attaches; missing data holds; 99, 98 recovers. Retry 102 does not duplicate.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Create a monitor                         |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Condition builder                        |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save monitor draft]                     |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/monitor-new` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `monitors` explanation and status.
- [ ] Inspect exact columns: Setting, Value, Validation, Purpose. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## incident — Incident · daily warehouse spend

Route: `/incident` (prototype `#/incident`). Persona: **FinOps lead / finance controller**.

Goal: High priority · ANALYTICS_PROD · one active episode

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  GOVERN  /  Incident · daily warehouse spend                                       |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| High priority · ANALYTICS_PROD · one active episode                                                      |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| LATEST ELIGIBLE VALUE: $103.00 [i]  ||  BREACH THRESHOLD: $100.00 [i]                                    |
| Daily evaluation · 11:00 UTC  ||  Strictly greater than 100 twice                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ELIGIBLE BREACHES: 3 [i]  ||  EPISODE AGE: 2 h [i]                                                       |
| 101, 102 and 103; retry not counted  ||  Synthetic timeline                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| INVESTIGATION TIMELINE                                                                                   |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Assign → acknowledge → investigate → resolve. Manual resolve records reason and does not claim measured  |
| recovery.                                                                                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| NOTIFICATIONS                                                                                            |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Delivery attempts belong to a logical event ID; ambiguous provider timeout may yield duplicate delivery. |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Evaluation                | Value USD                 | Coverage                  | Outcome                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
| 09:00 UTC                 | 101.00                    | Complete                  | First breach              |
| 10:00 UTC                 | 102.00                    | Complete                  | Opened                    |
| 11:00 UTC                 | 103.00                    | Complete                  | Attached                  |
| 12:00 UTC                 | —                         | Incomplete                | Hold state                |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| This monitor fixture uses its own daily evaluation period, not the August cumulative total.              |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `incidentvalue` | Latest eligible value: **$103.00** | Daily evaluation · 11:00 UTC | Monitor fixture / synthetic; FINAL |
| `threshold` | Breach threshold: **$100.00** | Strictly greater than 100 twice | Monitor fixture / synthetic; POLICY |
| `occurrences` | Eligible breaches: **3** | 101, 102 and 103; retry not counted | August 2026 / synthetic; Observed |
| `incidentage` | Episode age: **2 h** | Synthetic timeline | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Investigation timeline**: Assign → acknowledge → investigate → resolve. Manual resolve records reason and does not claim measured recovery.
- **Notifications**: Delivery attempts belong to a logical event ID; ambiguous provider timeout may yield duplicate delivery.
- **DataTable** columns, in order: Evaluation, Value USD, Coverage, Outcome. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Acknowledge incident. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `monitors`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Acknowledge incident                                           [X]         |
| Selected metric / resource: [label and identifier]                         |
| Scope and period: [explicit, retained from entry]                          |
| Basis / input publication / coverage: [explain]                            |
| Evidence: [authorized source / parent component]                           |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Acknowledge incident]                                           |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | FinOps lead / finance controller |
| Goal | High priority · ANALYTICS_PROD · one active episode |
| Entry point | Parent route /monitors; deep link supported. |
| Happy path | Read context → inspect Investigation timeline → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No incident · daily warehouse spend for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Acknowledge incident reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Acknowledge incident; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; This monitor fixture uses its own daily evaluation period, not the August cumulative total. |

### Domain subtleties

This monitor fixture uses its own daily evaluation period, not the August cumulative total.

Delivery attempts belong to a logical event ID; ambiguous provider timeout may yield duplicate delivery.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Incident · daily warehouse spend         |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Investigation timeline                   |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Acknowledge incident]                   |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/incident` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `incidentvalue` explanation and status.
- [ ] Inspect exact columns: Evaluation, Value USD, Coverage, Outcome. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

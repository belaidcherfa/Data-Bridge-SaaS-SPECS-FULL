# Actions — detailed screen design

Design unit: `actions`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../13-insights/intelligence.md).

This file covers 2 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## actions — Actions

Route: `/actions` (prototype `#/actions`). Persona: **Platform owner / FinOps analyst**.

Goal: Turn an accepted insight into an accountable change.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  OPTIMIZE  /  Actions                                                              |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Turn an accepted insight into an accountable change.                                                     |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| OPEN ACTIONS: 1 [i]  ||  VERIFIED ACTIONS: 1 [i]                                                         |
| Tracking does not execute SQL  ||  Evidence-backed study fixture                                         |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| VERIFIED REALIZED: $6,000.00 [i]  ||  POTENTIAL SAVINGS: $8,000.00 [i]                                   |
| 24,000 normalized minus 18,000 observed  ||  Estimate · never add to realized                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Review warehouse schedule [>]                                                                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| LIFECYCLE                                                                                                |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Proposed → accepted → in progress → implemented → verifying → verified / rejected. Store responsible     |
| owner and dates.                                                                                         |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| NO AUTOMATIC EXECUTION                                                                                   |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Tracking a change is separate from changing Snowflake resources. Mockup never runs administrative SQL.   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Action                    | Owner                     | State                     | Evidence                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Review warehouse schedule | Alex Morgan               | Investigating             | Insight linked            |
| Validate efficiency       | Taylor Chen               | Verified                  | Savings study             |
| change                    |                           |                           |                           |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Action completion alone does not certify realized savings.                                               |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `actionopen` | Open actions: **1** | Tracking does not execute SQL | August 2026 / synthetic; Observed |
| `actiondone` | Verified actions: **1** | Evidence-backed study fixture | August 2026 / synthetic; Observed |
| `verifiedsavings` | Verified realized: **$6,000.00** | 24,000 normalized minus 18,000 observed | Independent study / synthetic; VERIFIED |
| `potential` | Potential savings: **$8,000.00** | Estimate · never add to realized | Independent study / synthetic; ESTIMATE |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Lifecycle**: Proposed → accepted → in progress → implemented → verifying → verified / rejected. Store responsible owner and dates.
- **No automatic execution**: Tracking a change is separate from changing Snowflake resources. Mockup never runs administrative SQL.
- **DataTable** columns, in order: Action, Owner, State, Evidence. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/action-detail`. Use named links; never assume every row represents the same execution.

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
| Persona | Platform owner / FinOps analyst |
| Goal | Turn an accepted insight into an accountable change. |
| Entry point | Optimize navigation; deep link supported. |
| Happy path | Read context → inspect Lifecycle → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No actions for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: action-detail. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Action completion alone does not certify realized savings. |

### Domain subtleties

Action completion alone does not certify realized savings.

Tracking a change is separate from changing Snowflake resources. Mockup never runs administrative SQL.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Actions                                  |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Lifecycle                                |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/actions` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `actionopen` explanation and status.
- [ ] Inspect exact columns: Action, Owner, State, Evidence. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## action-detail — Review warehouse schedule

Route: `/action-detail` (prototype `#/action-detail`). Persona: **Platform owner / FinOps analyst**.

Goal: Assigned to Alex Morgan · target Sep 30

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  OPTIMIZE  /  Review warehouse schedule                                            |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Assigned to Alex Morgan · target Sep 30                                                                  |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| OPEN ACTIONS: 1 [i]  ||  POTENTIAL SAVINGS: $8,000.00 [i]                                                |
| Tracking does not execute SQL  ||  Estimate · never add to realized                                      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| VERIFIED REALIZED: $6,000.00 [i]  ||  ESTIMATE CONFIDENCE: MEDIUM [i]                                    |
| 24,000 normalized minus 18,000 observed  ||  Qualitative evidence assessment                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ACTION TIMELINE                                                                                          |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Keep evidence URLs safe, ownership, due dates, review and rollback plan visible.                         |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| VERIFICATION                                                                                             |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Require baseline/post windows, normalized usage, comparable coverage and overlap exclusion before        |
| realized label.                                                                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Step                      | Owner                     | State                     | Evidence                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Approve proposal          | FinOps lead               | Done                      | Review note               |
| Apply approved change     | Platform owner            | Pending                   | Change ticket             |
| Verify savings            | Analyst                   | Pending                   | Normalized study          |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Prototype saves a draft only; no issue tracker or customer platform is modified.                         |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `actionopen` | Open actions: **1** | Tracking does not execute SQL | August 2026 / synthetic; Observed |
| `potential` | Potential savings: **$8,000.00** | Estimate · never add to realized | Independent study / synthetic; ESTIMATE |
| `verifiedsavings` | Verified realized: **$6,000.00** | 24,000 normalized minus 18,000 observed | Independent study / synthetic; VERIFIED |
| `confidence` | Estimate confidence: **MEDIUM** | Qualitative evidence assessment | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Action timeline**: Keep evidence URLs safe, ownership, due dates, review and rollback plan visible.
- **Verification**: Require baseline/post windows, normalized usage, comparable coverage and overlap exclusion before realized label.
- **DataTable** columns, in order: Step, Owner, State, Evidence. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save action draft. Opens labelled form fields; required values validate before local save. In production, server validates authorization, schema and stale version.
- **Parent**: `actions`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Save action draft                                           [X]            |
| Action title: [____________________________]                               |
| Owner: [____________________________]                                      |
| Due date: [____________________________]                                   |
| Review note: [____________________________]                                |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Save action draft]                                              |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | Platform owner / FinOps analyst |
| Goal | Assigned to Alex Morgan · target Sep 30 |
| Entry point | Parent route /actions; deep link supported. |
| Happy path | Read context → inspect Action timeline → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No review warehouse schedule for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save action draft reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save action draft; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Prototype saves a draft only; no issue tracker or customer platform is modified. |

### Domain subtleties

Prototype saves a draft only; no issue tracker or customer platform is modified.

Require baseline/post windows, normalized usage, comparable coverage and overlap exclusion before realized label.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Review warehouse schedule                |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Action timeline                          |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save action draft]                      |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/action-detail` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `actionopen` explanation and status.
- [ ] Inspect exact columns: Step, Owner, State, Evidence. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

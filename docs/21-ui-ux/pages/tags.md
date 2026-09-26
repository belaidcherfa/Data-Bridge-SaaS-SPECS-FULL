# External Tag Studio — detailed screen design

Design unit: `tags`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../11-allocation/allocation.md).

This file covers 3 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## tags — External Tag Studio

Route: `/tags` (prototype `#/tags`). Persona: **Finance controller / team owner**.

Goal: Make cost ownership understandable and reviewable.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  ALLOCATE  /  External Tag Studio                                                  |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Make cost ownership understandable and reviewable.                                                       |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TEAM TAG COVERAGE: 100% [i]  ||  PUBLISHED RULES: 3 [i]                                                  |
| Warehouse subset only  ||  Synthetic ruleset registry                                                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BLOCKING CONFLICTS: 0 [i]  ||  UNOWNED WAREHOUSE GROUPS: 0 [i]                                           |
| Equal-priority conflicts would block  ||  Selected resource set only                                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Rule · Finance ownership [>] | Review tagging impact [>]                                       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| COVERAGE BY DIMENSION                                                                                    |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Coverage denominator names its scope. External tags do not modify customer Snowflake tags.               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| RULE GOVERNANCE                                                                                          |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Versioned definitions, effective dates and provenance. Same-priority conflicts block publication.        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Dimension                 | Values                    | Coverage                  | Source                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Team                      | Finance, Marketing        | 100% warehouse            | External rules            |
| Environment               | Production                | 100% observed             | Native evidence           |
| Cost center               | FIN-01, MKT-02            | 100% warehouse            | Approved mapping          |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Access-relevant group changes require authorization review.                                              |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `tagcoverage` | Team tag coverage: **100%** | Warehouse subset only | August 2026 / synthetic; Observed |
| `tagrules` | Published rules: **3** | Synthetic ruleset registry | August 2026 / synthetic; Observed |
| `tagconflicts` | Blocking conflicts: **0** | Equal-priority conflicts would block | August 2026 / synthetic; Observed |
| `unowned` | Unowned warehouse groups: **0** | Selected resource set only | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Coverage by dimension**: Coverage denominator names its scope. External tags do not modify customer Snowflake tags.
- **Rule governance**: Versioned definitions, effective dates and provenance. Same-priority conflicts block publication.
- **DataTable** columns, in order: Dimension, Values, Coverage, Source. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/tag-rule`, `/tag-preview`. Use named links; never assume every row represents the same execution.

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
| Persona | Finance controller / team owner |
| Goal | Make cost ownership understandable and reviewable. |
| Entry point | Allocate navigation; deep link supported. |
| Happy path | Read context → inspect Coverage by dimension → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No external tag studio for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: tag-rule, tag-preview. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Access-relevant group changes require authorization review. |

### Domain subtleties

Access-relevant group changes require authorization review.

Versioned definitions, effective dates and provenance. Same-priority conflicts block publication.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| External Tag Studio                      |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Coverage by dimension                    |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/tags` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `tagcoverage` explanation and status.
- [ ] Inspect exact columns: Dimension, Values, Coverage, Source. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## tag-rule — Rule · Finance ownership

Route: `/tag-rule` (prototype `#/tag-rule`). Persona: **Finance controller / team owner**.

Goal: Typed rule editor · draft version 3

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  ALLOCATE  /  Rule · Finance ownership                                             |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Typed rule editor · draft version 3                                                                      |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MATCHED WORKLOAD: 1 [i]  ||  BEFORE COVERAGE: 0% [i]                                                     |
| finance_daily rule preview  ||  Isolated Finance subset preview                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| AFTER COVERAGE: 100% [i]  ||  BLOCKING CONFLICTS: 0 [i]                                                  |
| Isolated Finance subset preview  ||  Equal-priority conflicts would block                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| RULE BUILDER                                                                                             |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| IF verified project equals finance_daily AND environment equals production THEN team=Finance. No         |
| arbitrary SQL/Python.                                                                                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PRECEDENCE                                                                                               |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Priority 100; valid from Sep 01. Override is effective-dated and auditable.                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Condition                 | Operator                  | Value                     | Result                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| project                   | equals                    | finance_daily             | Matches                   |
| environment               | equals                    | production                | Matches                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Save draft is local in the prototype; preview does not publish production facts.                         |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `tagmatches` | Matched workload: **1** | finance_daily rule preview | August 2026 / synthetic; Observed |
| `tagbefore` | Before coverage: **0%** | Isolated Finance subset preview | August 2026 / synthetic; Observed |
| `tagafter` | After coverage: **100%** | Isolated Finance subset preview | August 2026 / synthetic; Observed |
| `tagconflicts` | Blocking conflicts: **0** | Equal-priority conflicts would block | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Rule builder**: IF verified project equals finance_daily AND environment equals production THEN team=Finance. No arbitrary SQL/Python.
- **Precedence**: Priority 100; valid from Sep 01. Override is effective-dated and auditable.
- **DataTable** columns, in order: Condition, Operator, Value, Result. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save rule draft. Opens labelled form fields; required values validate before local save. In production, server validates authorization, schema and stale version.
- **Parent**: `tags`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Save rule draft                                           [X]              |
| Rule name: [____________________________]                                  |
| Dimension value: [____________________________]                            |
| Priority: [____________________________]                                   |
| Effective from: [____________________________]                             |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Save rule draft]                                                |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | Finance controller / team owner |
| Goal | Typed rule editor · draft version 3 |
| Entry point | Parent route /tags; deep link supported. |
| Happy path | Read context → inspect Rule builder → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No rule · finance ownership for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save rule draft reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save rule draft; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Save draft is local in the prototype; preview does not publish production facts. |

### Domain subtleties

Save draft is local in the prototype; preview does not publish production facts.

Priority 100; valid from Sep 01. Override is effective-dated and auditable.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Rule · Finance ownership                 |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Rule builder                             |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save rule draft]                        |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/tag-rule` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `tagmatches` explanation and status.
- [ ] Inspect exact columns: Condition, Operator, Value, Result. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## tag-preview — Review tagging impact

Route: `/tag-preview` (prototype `#/tag-preview`). Persona: **Finance controller / team owner**.

Goal: Simulation · ruleset v3 · input publication v1

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  ALLOCATE  /  Review tagging impact                                                |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Simulation · ruleset v3 · input publication v1                                                           |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MATCHED WORKLOAD: 1 [i]  ||  BEFORE COVERAGE: 0% [i]                                                     |
| finance_daily rule preview  ||  Isolated Finance subset preview                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| AFTER COVERAGE: 100% [i]  ||  BLOCKING CONFLICTS: 0 [i]                                                  |
| Isolated Finance subset preview  ||  Equal-priority conflicts would block                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BEFORE / AFTER                                                                                           |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| 8,400 USD of query compute receives Finance ownership in this isolated rule preview.                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| APPROVAL GATE                                                                                            |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Block if any conflict, stale input, expired approval or access-relevant impact lacks security review.    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Impact                    | Before                    | After                     | Review                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Finance-owned workload    | Unclassified              | Finance                   | Approved mapping          |
| Query compute ownership   | 0%                        | 100%                      | Warehouse subset          |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| This preview changes one subset; it does not claim organization-wide allocation coverage.                |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `tagmatches` | Matched workload: **1** | finance_daily rule preview | August 2026 / synthetic; Observed |
| `tagbefore` | Before coverage: **0%** | Isolated Finance subset preview | August 2026 / synthetic; Observed |
| `tagafter` | After coverage: **100%** | Isolated Finance subset preview | August 2026 / synthetic; Observed |
| `tagconflicts` | Blocking conflicts: **0** | Equal-priority conflicts would block | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Before / after**: 8,400 USD of query compute receives Finance ownership in this isolated rule preview.
- **Approval gate**: Block if any conflict, stale input, expired approval or access-relevant impact lacks security review.
- **DataTable** columns, in order: Impact, Before, After, Review. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Approve demo preview. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `tags`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Approve demo preview                                           [X]         |
| Selected metric / resource: [label and identifier]                         |
| Scope and period: [explicit, retained from entry]                          |
| Basis / input publication / coverage: [explain]                            |
| Evidence: [authorized source / parent component]                           |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Approve demo preview]                                           |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | Finance controller / team owner |
| Goal | Simulation · ruleset v3 · input publication v1 |
| Entry point | Parent route /tags; deep link supported. |
| Happy path | Read context → inspect Before / after → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No review tagging impact for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Approve demo preview reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Approve demo preview; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; This preview changes one subset; it does not claim organization-wide allocation coverage. |

### Domain subtleties

This preview changes one subset; it does not claim organization-wide allocation coverage.

Block if any conflict, stale input, expired approval or access-relevant impact lacks security review.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Review tagging impact                    |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Before / after                           |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Approve demo preview]                   |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/tag-preview` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `tagmatches` explanation and status.
- [ ] Inspect exact columns: Impact, Before, After, Review. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

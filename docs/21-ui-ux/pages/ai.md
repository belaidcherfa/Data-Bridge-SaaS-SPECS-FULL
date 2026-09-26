# AI / Cortex — detailed screen design

Design unit: `ai`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../10-frontend/workloads.md).

This file covers 5 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## ai — AI / Cortex

Route: `/ai` (prototype `#/ai`). Persona: **FinOps analyst / data engineer**.

Goal: AI spend with traceable cost layers and native usage.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  AI / Cortex                                                           |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| AI spend with traceable cost layers and native usage.                                                    |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| AI / CORTEX COST: $600.00 [i]  ||  OBSERVED TOKENS: 12 M [i]                                             |
| Additive family charges  ||  AI functions only                                                           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| AI FUNCTION EXECUTIONS: 400 [i]  ||  FAMILY COST COVERAGE: 100% [i]                                      |
| Other families use native units  ||  Absolute covered billed amount                                      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: AI functions [>] | Cortex Search [>] | Cortex Analyst [>]                                      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| AI COST LAYERS                                                                                           |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Total 600 USD by additive billed family. Child call allocation explains parent cost; it never adds       |
| another charge.                                                                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| UNIT DISCIPLINE                                                                                          |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Tokens only cover token-based AI functions. Search/Analyst do not inherit token metrics without          |
| evidence.                                                                                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Family                    | Billed USD                | Unit                      | Coverage                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| AI functions              | 400.00                    | Tokens                    | Observed                  |
| Cortex Search             | 150.00                    | Service credits           | Observed                  |
| Cortex Analyst            | 50.00                     | Service units             | Observed                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Model and token quantities are native evidence, not proof of a fabricated pricing formula.               |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `cortex` | AI / Cortex cost: **$600.00** | Additive family charges | August 2026 / synthetic; RECONCILED |
| `aitokens` | Observed tokens: **12 M** | AI functions only | August 2026 / synthetic; Observed |
| `aiexecutions` | AI function executions: **400** | Other families use native units | August 2026 / synthetic; Observed |
| `aicoverage` | Family cost coverage: **100%** | Absolute covered billed amount | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **AI cost layers**: Total 600 USD by additive billed family. Child call allocation explains parent cost; it never adds another charge.
- **Unit discipline**: Tokens only cover token-based AI functions. Search/Analyst do not inherit token metrics without evidence.
- **DataTable** columns, in order: Family, Billed USD, Unit, Coverage. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/ai-family`, `/ai-search`, `/ai-analyst`. Use named links; never assume every row represents the same execution.

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
| Goal | AI spend with traceable cost layers and native usage. |
| Entry point | Explore navigation; deep link supported. |
| Happy path | Read context → inspect AI cost layers → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No ai / cortex for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: ai-family, ai-search, ai-analyst. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Model and token quantities are native evidence, not proof of a fabricated pricing formula. |

### Domain subtleties

Model and token quantities are native evidence, not proof of a fabricated pricing formula.

Tokens only cover token-based AI functions. Search/Analyst do not inherit token metrics without evidence.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| AI / Cortex                              |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| AI cost layers                           |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/ai` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `cortex` explanation and status.
- [ ] Inspect exact columns: Family, Billed USD, Unit, Coverage. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## ai-family — AI functions

Route: `/ai-family` (prototype `#/ai-family`). Persona: **FinOps analyst / data engineer**.

Goal: Model and application usage · observed token-based calls

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  AI functions                                                          |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Model and application usage · observed token-based calls                                                 |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| AI FUNCTIONS COST: $400.00 [i]  ||  OBSERVED TOKENS: 12 M [i]                                            |
| Subset of Cortex total  ||  AI functions only                                                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| OBSERVED FUNCTION CALLS: 400 [i]  ||  EFFECTIVE COST / M TOKENS: $33.33 [i]                              |
| Verified synthetic calls  ||  400 USD / 12 M observed tokens                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: AI execution · ai_042 [>]                                                                      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| APPLICATION ATTRIBUTION                                                                                  |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Use verified request/application identifiers; unknown stays unassigned.                                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| UNIT ECONOMICS                                                                                           |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| 400 USD / 12 M observed tokens = 33.3333 USD per million for this aggregate, an effective ratio rather   |
| than a vendor list price.                                                                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Model alias               | Billed USD                | Observed tokens           | Application               |
+---------------------------+---------------------------+---------------------------+---------------------------+
| approved-model-a          | 280.00                    | 8 M                       | Support summarizer        |
| approved-model-b          | 120.00                    | 4 M                       | Catalog enrichment        |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Input and output token breakdown is unavailable in this fixture; do not invent it.                       |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `aifunctioncost` | AI functions cost: **$400.00** | Subset of Cortex total | August 2026 / synthetic; RECONCILED |
| `aitokens` | Observed tokens: **12 M** | AI functions only | August 2026 / synthetic; Observed |
| `aifunctioncalls` | Observed function calls: **400** | Verified synthetic calls | August 2026 / synthetic; Observed |
| `tokenrate` | Effective cost / M tokens: **$33.33** | 400 USD / 12 M observed tokens | AI functions / August; Derived |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Application attribution**: Use verified request/application identifiers; unknown stays unassigned.
- **Unit economics**: 400 USD / 12 M observed tokens = 33.3333 USD per million for this aggregate, an effective ratio rather than a vendor list price.
- **DataTable** columns, in order: Model alias, Billed USD, Observed tokens, Application. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `ai`; breadcrumb and browser Back preserve scope.
- **Drilldowns**: `/ai-execution`. Use named links; never assume every row represents the same execution.

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
| Goal | Model and application usage · observed token-based calls |
| Entry point | Parent route /ai; deep link supported. |
| Happy path | Read context → inspect Application attribution → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No ai functions for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: ai-execution. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Input and output token breakdown is unavailable in this fixture; do not invent it. |

### Domain subtleties

Input and output token breakdown is unavailable in this fixture; do not invent it.

400 USD / 12 M observed tokens = 33.3333 USD per million for this aggregate, an effective ratio rather than a vendor list price.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| AI functions                             |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Application attribution                  |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/ai-family` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `aifunctioncost` explanation and status.
- [ ] Inspect exact columns: Model alias, Billed USD, Observed tokens, Application. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## ai-execution — AI execution · ai_042

Route: `/ai-execution` (prototype `#/ai-execution`). Persona: **FinOps analyst / data engineer**.

Goal: Support summarizer · verified parent request

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  AI execution · ai_042                                                 |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Support summarizer · verified parent request                                                             |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PARENT REQUEST COST: $10.00 [i]  ||  OBSERVED CALL TOKENS: 300,000 [i]                                   |
| Child 4 plus residual 6  ||  Representative request                                                      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| REQUEST WALL TIME: 3.2 s [i]  ||  EXECUTION STATUS: SUCCESS [i]                                          |
| Representative request  ||  Complete verified fixture                                                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CALL TREE                                                                                                |
|      Compile | Queue | Execution --------------------> [Evidence]                                        |
| Parent 10 contains child attribution 4 and residual 6. Display as nested composition, never a 20 USD     |
| table total.                                                                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PRIVACY                                                                                                  |
|      Compile | Queue | Execution --------------------> [Evidence]                                        |
| Prompt and response content are unavailable by default. Show sanitized labels and permitted identifiers  |
| only.                                                                                                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Layer                     | Cost USD                  | Role                      | Additive                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Parent request            | 10.00                     | Billed parent             | Yes                       |
| Child model call          | 4.00                      | Attribution               | No                        |
| Remaining parent          | 6.00                      | Attribution               | No                        |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Representative 10 USD is included in the AI functions 400 USD.                                           |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `aicallcost` | Parent request cost: **$10.00** | Child 4 plus residual 6 | ai_042 / Aug 30; FINAL |
| `aicalltokens` | Observed call tokens: **300,000** | Representative request | August 2026 / synthetic; Observed |
| `aiduration` | Request wall time: **3.2 s** | Representative request | August 2026 / synthetic; Observed |
| `runstatus` | Execution status: **SUCCESS** | Complete verified fixture | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Call tree**: Parent 10 contains child attribution 4 and residual 6. Display as nested composition, never a 20 USD table total.
- **Privacy**: Prompt and response content are unavailable by default. Show sanitized labels and permitted identifiers only.
- **DataTable** columns, in order: Layer, Cost USD, Role, Additive. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `ai-family`; breadcrumb and browser Back preserve scope.

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
| Goal | Support summarizer · verified parent request |
| Entry point | Parent route /ai-family; deep link supported. |
| Happy path | Read context → inspect Call tree → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No ai execution · ai_042 for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Representative 10 USD is included in the AI functions 400 USD. |

### Domain subtleties

Representative 10 USD is included in the AI functions 400 USD.

Prompt and response content are unavailable by default. Show sanitized labels and permitted identifiers only.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| AI execution · ai_042                    |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Call tree                                |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/ai-execution` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `aicallcost` explanation and status.
- [ ] Inspect exact columns: Layer, Cost USD, Role, Additive. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## ai-search — Cortex Search

Route: `/ai-search` (prototype `#/ai-search`). Persona: **FinOps analyst / data engineer**.

Goal: Service cost and freshness without token assumptions.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Cortex Search                                                         |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Service cost and freshness without token assumptions.                                                    |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CORTEX SEARCH COST: $150.00 [i]  ||  ATTRIBUTION COVERAGE: — [i]                                         |
| Inside Cortex family total  ||  Unavailable: required linkage or usage telemetry not observed            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| NATIVE USAGE                                                                                             |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Expose indexing/serving units only when present in the verified source contract. Do not borrow AI-       |
| function token formulas.                                                                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ATTRIBUTION                                                                                              |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| 150 USD is inside the 600 USD Cortex family total. Application attribution may be unknown.               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Service                   | Billed USD                | Indexed bytes             | Coverage                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| catalog_search            | 150.00                    | —                         | Cost observed             |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| No token estimate or guessed price is shown.                                                             |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `aisearchcost` | Cortex Search cost: **$150.00** | Inside Cortex family total | August 2026 / synthetic; RECONCILED |
| `unavailable` | Attribution coverage: **—** | Unavailable: required linkage or usage telemetry not observed | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Native usage**: Expose indexing/serving units only when present in the verified source contract. Do not borrow AI-function token formulas.
- **Attribution**: 150 USD is inside the 600 USD Cortex family total. Application attribution may be unknown.
- **DataTable** columns, in order: Service, Billed USD, Indexed bytes, Coverage. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `ai`; breadcrumb and browser Back preserve scope.

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
| Goal | Service cost and freshness without token assumptions. |
| Entry point | Parent route /ai; deep link supported. |
| Happy path | Read context → inspect Native usage → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No cortex search for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; No token estimate or guessed price is shown. |

### Domain subtleties

No token estimate or guessed price is shown.

150 USD is inside the 600 USD Cortex family total. Application attribution may be unknown.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Cortex Search                            |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Native usage                             |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/ai-search` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `aisearchcost` explanation and status.
- [ ] Inspect exact columns: Service, Billed USD, Indexed bytes, Coverage. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## ai-analyst — Cortex Analyst

Route: `/ai-analyst` (prototype `#/ai-analyst`). Persona: **FinOps analyst / data engineer**.

Goal: Request activity with the native billing basis.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Cortex Analyst                                                        |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Request activity with the native billing basis.                                                          |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CORTEX ANALYST COST: $50.00 [i]  ||  ATTRIBUTION COVERAGE: — [i]                                         |
| Inside Cortex family total  ||  Unavailable: required linkage or usage telemetry not observed            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| COST AUTHORITY                                                                                           |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| 50 USD belongs inside the 600 USD family total; exact source/service model determines supported native   |
| units.                                                                                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PRIVACY                                                                                                  |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Semantic request labels can be shown after sanitization; user questions and generated SQL remain         |
| protected.                                                                                               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Application               | Billed USD                | Observed requests         | Coverage                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| revenue_analyst           | 50.00                     | —                         | Cost observed             |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Request count unavailable; do not divide by an invented denominator.                                     |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `aianalystcost` | Cortex Analyst cost: **$50.00** | Inside Cortex family total | August 2026 / synthetic; RECONCILED |
| `unavailable` | Attribution coverage: **—** | Unavailable: required linkage or usage telemetry not observed | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Cost authority**: 50 USD belongs inside the 600 USD family total; exact source/service model determines supported native units.
- **Privacy**: Semantic request labels can be shown after sanitization; user questions and generated SQL remain protected.
- **DataTable** columns, in order: Application, Billed USD, Observed requests, Coverage. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `ai`; breadcrumb and browser Back preserve scope.

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
| Goal | Request activity with the native billing basis. |
| Entry point | Parent route /ai; deep link supported. |
| Happy path | Read context → inspect Cost authority → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No cortex analyst for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Request count unavailable; do not divide by an invented denominator. |

### Domain subtleties

Request count unavailable; do not divide by an invented denominator.

Semantic request labels can be shown after sanitization; user questions and generated SQL remain protected.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Cortex Analyst                           |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Cost authority                           |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/ai-analyst` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `aianalystcost` explanation and status.
- [ ] Inspect exact columns: Application, Billed USD, Observed requests, Coverage. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

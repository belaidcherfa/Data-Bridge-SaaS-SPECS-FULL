# Integration Health — detailed screen design

Design unit: `integrations`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../04-snowflake-connectivity/connectivity.md).

This file covers 3 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## integrations — Integration Health

Route: `/integrations` (prototype `#/integrations`). Persona: **Tenant admin / data platform owner**.

Goal: Connections, permissions and destinations you can trust.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  PLATFORM  /  Integration Health                                                   |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Connections, permissions and destinations you can trust.                                                 |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CONNECTED ORGANIZATION: 1 [i]  ||  AVAILABLE CAPABILITIES: 2 / 3 [i]                                     |
| Demo connection only  ||  Historical operator profile unavailable                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| NOTIFICATION CHANNELS: 4 [i]  ||  ACTIONABLE IDENTITY ISSUES: 0 [i]                                      |
| Email, Slack, Teams, HTTPS  ||  Unavailable historical profile is expected                               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Acme Snowflake connection [>] | Connect your Snowflake organization [>]                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| IDENTITY VERSUS DATA                                                                                     |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Connected identity does not prove every source permission or completed historical coverage.              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DESTINATIONS                                                                                             |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Secrets masked. Tests are explicit actions with clear test payload and recipient scope.                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Integration               | Type                      | State                     | Action                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Acme Snowflake            | AWS WIF                   | Connected                 | Inspect                   |
| FinOps email              | Email                     | Verified demo             | Inspect                   |
| Platform channel          | Slack                     | Demo configured           | Inspect                   |
| Teams workflow            | Teams                     | Demo configured           | Inspect                   |
| Audit webhook             | Signed HTTPS              | Demo configured           | Inspect                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| This prototype contains no credentials and never calls these providers.                                  |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `connections` | Connected organization: **1** | Demo connection only | August 2026 / synthetic; Observed |
| `capabilities` | Available capabilities: **2 / 3** | Historical operator profile unavailable | August 2026 / synthetic; Observed |
| `destinationcount` | Notification channels: **4** | Email, Slack, Teams, HTTPS | August 2026 / synthetic; Observed |
| `integrationissues` | Actionable identity issues: **0** | Unavailable historical profile is expected | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Identity versus data**: Connected identity does not prove every source permission or completed historical coverage.
- **Destinations**: Secrets masked. Tests are explicit actions with clear test payload and recipient scope.
- **DataTable** columns, in order: Integration, Type, State, Action. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/connection-detail`, `/onboarding`. Use named links; never assume every row represents the same execution.

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
| Persona | Tenant admin / data platform owner |
| Goal | Connections, permissions and destinations you can trust. |
| Entry point | Platform navigation; deep link supported. |
| Happy path | Read context → inspect Identity versus data → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No integration health for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: connection-detail, onboarding. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; This prototype contains no credentials and never calls these providers. |

### Domain subtleties

This prototype contains no credentials and never calls these providers.

Secrets masked. Tests are explicit actions with clear test payload and recipient scope.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Integration Health                       |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Identity versus data                     |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/integrations` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `connections` explanation and status.
- [ ] Inspect exact columns: Integration, Type, State, Action. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## connection-detail — Acme Snowflake connection

Route: `/connection-detail` (prototype `#/connection-detail`). Persona: **Tenant admin / data platform owner**.

Goal: Organization · one observed account · AWS WIF

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  PLATFORM  /  Acme Snowflake connection                                            |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Organization · one observed account · AWS WIF                                                            |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CONNECTED ORGANIZATION: 1 [i]  ||  OBSERVED ACCOUNTS: 1 [i]                                              |
| Demo connection only  ||  PRODUCTION; no fabricated discovered account                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| AVAILABLE CAPABILITIES: 2 / 3 [i]  ||  ACTIONABLE IDENTITY ISSUES: 0 [i]                                 |
| Historical operator profile unavailable  ||  Unavailable historical profile is expected                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CONNECTION HEALTH                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Organization identity, account locator, last verification and allowed capability matrix.                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| REPAIR PERMISSIONS                                                                                       |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Least-privilege instructions and copyable placeholders; never ask for persistent RSA private keys.       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Capability                | State                     | Impact                    | Remediation               |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Account usage             | Available                 | Account analytics         | None                      |
| Organization billing      | Available                 | Org charges               | None                      |
| Operator profiles         | Unavailable historical    | No old plans              | Expected window           |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Production WIF statements must come from connectivity contract, not invented mock credentials.           |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `connections` | Connected organization: **1** | Demo connection only | August 2026 / synthetic; Observed |
| `accounts` | Observed accounts: **1** | PRODUCTION; no fabricated discovered account | August 2026 / synthetic; Observed |
| `capabilities` | Available capabilities: **2 / 3** | Historical operator profile unavailable | August 2026 / synthetic; Observed |
| `integrationissues` | Actionable identity issues: **0** | Unavailable historical profile is expected | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Connection health**: Organization identity, account locator, last verification and allowed capability matrix.
- **Repair permissions**: Least-privilege instructions and copyable placeholders; never ask for persistent RSA private keys.
- **DataTable** columns, in order: Capability, State, Impact, Remediation. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `integrations`; breadcrumb and browser Back preserve scope.

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
| Persona | Tenant admin / data platform owner |
| Goal | Organization · one observed account · AWS WIF |
| Entry point | Parent route /integrations; deep link supported. |
| Happy path | Read context → inspect Connection health → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No acme snowflake connection for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Production WIF statements must come from connectivity contract, not invented mock credentials. |

### Domain subtleties

Production WIF statements must come from connectivity contract, not invented mock credentials.

Least-privilege instructions and copyable placeholders; never ask for persistent RSA private keys.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Acme Snowflake connection                |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Connection health                        |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/connection-detail` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `connections` explanation and status.
- [ ] Inspect exact columns: Capability, State, Impact, Remediation. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## onboarding — Connect your Snowflake organization

Route: `/onboarding` (prototype `#/onboarding`). Persona: **Tenant admin / data platform owner**.

Goal: A guided path from identity to first reconciled value.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  PLATFORM  /  Connect your Snowflake organization                                  |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| A guided path from identity to first reconciled value.                                                   |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ONBOARDING STAGES: 5 [i]  ||  OBSERVED ACCOUNTS: 1 [i]                                                   |
| Identity, WIF, grants, history, first value  ||  PRODUCTION; no fabricated discovered account            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| OBSERVED COVERAGE: 100% [i]  ||  CONNECTED ORGANIZATION: 1 [i]                                           |
| Complete selected synthetic intervals  ||  Demo connection only                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| WIZARD SEQUENCE                                                                                          |
|      (1 Identity) -- (2 WIF) -- (3 Grants) -- (4 History) -- (5 Value)                                   |
| Organization → account identity → generated WIF instructions → verify grants → source/history coverage → |
| first-value checklist.                                                                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PARTIAL ONBOARDING                                                                                       |
|      (1 Identity) -- (2 WIF) -- (3 Grants) -- (4 History) -- (5 Value)                                   |
| Insufficient org billing rights can permit account analytics with explicit organization-level            |
| limitation.                                                                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Step                      | Owner                     | State                     | Expected evidence         |
+---------------------------+---------------------------+---------------------------+---------------------------+
| 1. Organization           | Admin                     | Complete demo             | Identity                  |
| 2. WIF trust              | Snowflake admin           | Review                    | Temporary AWS identity    |
| 3. Capabilities           | Platform                  | Pending                   | Read-only probes          |
| 4. History                | Data owner                | Pending                   | Coverage                  |
| 5. First value            | FinOps                    | Pending                   | Reconciliation            |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Continue simulates readiness only. Do not paste real credentials into this mockup.                       |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `onboardingsteps` | Onboarding stages: **5** | Identity, WIF, grants, history, first value | August 2026 / synthetic; Observed |
| `accounts` | Observed accounts: **1** | PRODUCTION; no fabricated discovered account | August 2026 / synthetic; Observed |
| `coverage` | Observed coverage: **100%** | Complete selected synthetic intervals | August 2026 / synthetic; Observed |
| `connections` | Connected organization: **1** | Demo connection only | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Wizard sequence**: Organization → account identity → generated WIF instructions → verify grants → source/history coverage → first-value checklist.
- **Partial onboarding**: Insufficient org billing rights can permit account analytics with explicit organization-level limitation.
- **DataTable** columns, in order: Step, Owner, State, Expected evidence. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Validate demo connection. Opens labelled form fields; required values validate before local save. In production, server validates authorization, schema and stale version.
- **Parent**: `integrations`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Validate demo connection                                           [X]     |
| Organization label: [____________________________]                         |
| Account locator: [____________________________]                            |
| History days: [____________________________]                               |
| Contact role: [____________________________]                               |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Validate demo connection]                                       |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | Tenant admin / data platform owner |
| Goal | A guided path from identity to first reconciled value. |
| Entry point | Parent route /integrations; deep link supported. |
| Happy path | Read context → inspect Wizard sequence → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No connect your snowflake organization for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Validate demo connection reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Validate demo connection; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Continue simulates readiness only. Do not paste real credentials into this mockup. |

### Domain subtleties

Continue simulates readiness only. Do not paste real credentials into this mockup.

Insufficient org billing rights can permit account analytics with explicit organization-level limitation.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Connect your Snowflake organization      |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Wizard sequence                          |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Validate demo connection]               |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/onboarding` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `onboardingsteps` explanation and status.
- [ ] Inspect exact columns: Step, Owner, State, Expected evidence. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

# Welcome to Bridge — detailed screen design

Design unit: `sign-in`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../02-security/security.md).

This file covers 2 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## sign-in — Welcome to Bridge

Route: `/sign-in` (prototype `#/sign-in`). Persona: **Invited workspace member**.

Goal: Your Snowflake cost, with clarity and control.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  ACCESS  /  Welcome to Bridge                                                      |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Your Snowflake cost, with clarity and control.                                                           |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Verify your sign-in [>]                                                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SIGN-IN CARD                                                                                             |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Workspace domain → Continue with SSO. Production redirects to Cognito with validated state/PKCE and      |
| exact redirect URIs.                                                                                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PRIVACY                                                                                                  |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Do not put tokens in local storage or URLs. The prototype uses no real identity provider.                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Method                    | Policy                    | Outcome                   | Next                      |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Workspace SSO             | Enterprise identity       | Demo only                 | MFA                       |
| Recovery                  | Admin approved            | No credentials here       | Support                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| No passwords, MFA codes or tokens should be entered in this public synthetic mockup.                     |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

No financial KPI on identity screens. Avoid disclosure before authorization.

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Sign-in card**: Workspace domain → Continue with SSO. Production redirects to Cognito with validated state/PKCE and exact redirect URIs.
- **Privacy**: Do not put tokens in local storage or URLs. The prototype uses no real identity provider.
- **DataTable** columns, in order: Method, Policy, Outcome, Next. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Continue demo sign-in. Opens labelled form fields; required values validate before local save. In production, server validates authorization, schema and stale version.
- **Drilldowns**: `/mfa`. Use named links; never assume every row represents the same execution.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Continue demo sign-in                                           [X]        |
| Workspace domain: [____________________________]                           |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Continue demo sign-in]                                          |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | Invited workspace member |
| Goal | Your Snowflake cost, with clarity and control. |
| Entry point | Access navigation; deep link supported. |
| Happy path | Read context → inspect Sign-in card → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No welcome to bridge for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Continue demo sign-in reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: mfa. |
| Primary actions | Continue demo sign-in; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; No passwords, MFA codes or tokens should be entered in this public synthetic mockup. |

### Domain subtleties

No passwords, MFA codes or tokens should be entered in this public synthetic mockup.

Do not put tokens in local storage or URLs. The prototype uses no real identity provider.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Welcome to Bridge                        |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Sign-in card                             |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Continue demo sign-in]                  |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/sign-in` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `identity` explanation and status.
- [ ] Inspect exact columns: Method, Policy, Outcome, Next. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## mfa — Verify your sign-in

Route: `/mfa` (prototype `#/mfa`). Persona: **Invited workspace member**.

Goal: A step-up check before sensitive access.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  ACCESS  /  Verify your sign-in                                                    |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| A step-up check before sensitive access.                                                                 |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MFA HANDOFF                                                                                              |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Real MFA challenge is managed by identity provider. Do not create a fake six-digit secret collection     |
| form.                                                                                                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| RECOVERY                                                                                                 |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Use approved recovery flow, with rate limits and audited admin support.                                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| State                     | Message                   | Action                    | Result                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Pending                   | Complete identity-        | Continue demo             | Home                      |
|                           | provider challenge        |                           |                           |
| Expired                   | Challenge expired         | Restart sign-in           | New challenge             |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Prototype Continue is navigation only, never proof of authentication.                                    |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

No financial KPI on identity screens. Avoid disclosure before authorization.

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **MFA handoff**: Real MFA challenge is managed by identity provider. Do not create a fake six-digit secret collection form.
- **Recovery**: Use approved recovery flow, with rate limits and audited admin support.
- **DataTable** columns, in order: State, Message, Action, Result. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Continue to demo. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `sign-in`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Continue to demo                                           [X]             |
| Selected metric / resource: [label and identifier]                         |
| Scope and period: [explicit, retained from entry]                          |
| Basis / input publication / coverage: [explain]                            |
| Evidence: [authorized source / parent component]                           |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Continue to demo]                                               |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | Invited workspace member |
| Goal | A step-up check before sensitive access. |
| Entry point | Parent route /sign-in; deep link supported. |
| Happy path | Read context → inspect MFA handoff → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No verify your sign-in for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Continue to demo reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Continue to demo; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Prototype Continue is navigation only, never proof of authentication. |

### Domain subtleties

Prototype Continue is navigation only, never proof of authentication.

Use approved recovery flow, with rate limits and audited admin support.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Verify your sign-in                      |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| MFA handoff                              |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Continue to demo]                       |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/mfa` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `identity` explanation and status.
- [ ] Inspect exact columns: State, Message, Action, Result. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

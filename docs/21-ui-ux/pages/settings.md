# Workspace settings — detailed screen design

Design unit: `settings`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../02-security/security.md).

This file covers 10 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## settings — Workspace settings

Route: `/settings` (prototype `#/settings`). Persona: **Tenant admin / security admin**.

Goal: People, access and workspace preferences.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  SETTINGS  /  Workspace settings                                                   |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| People, access and workspace preferences.                                                                |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ACTIVE MEMBERS: 3 [i]  ||  TEAMS: 2 [i]                                                                  |
| Synthetic names only  ||  Finance and Marketing                                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ASSIGNED ROLES: 3 [i]  ||  VISIBLE AUDIT EVENTS: 3 [i]                                                   |
| Admin, group viewer, platform admin  ||  Representative authorized sample                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: People & teams [>] | Security & SSO [>] | Audit log [>] | Privacy & retention [>] |            |
| Notification destinations [>] | Subscription & billing [>] | Help & support [>] | Organizations &        |
| accounts [>] | Roles & access scopes [>]                                                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ADMINISTRATION                                                                                           |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Tenant administration changes are audited and effective-dated where relevant.                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SCOPE SAFETY                                                                                             |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Settings do not grant hidden analytical access merely by displaying an organization name.                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Area                      | Purpose                   | Access                    | Destination               |
+---------------------------+---------------------------+---------------------------+---------------------------+
| People & teams            | Membership                | Admin                     | People                    |
| Security & SSO            | Authentication            | Security admin            | Security                  |
| Privacy                   | Data policy               | Admin                     | Privacy                   |
| Billing                   | Subscription              | Billing admin             | Billing                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| All displayed identities and subscription values are synthetic.                                          |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `members` | Active members: **3** | Synthetic names only | August 2026 / synthetic; Observed |
| `teams` | Teams: **2** | Finance and Marketing | August 2026 / synthetic; Observed |
| `roles` | Assigned roles: **3** | Admin, group viewer, platform admin | August 2026 / synthetic; Observed |
| `auditcount` | Visible audit events: **3** | Representative authorized sample | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Administration**: Tenant administration changes are audited and effective-dated where relevant.
- **Scope safety**: Settings do not grant hidden analytical access merely by displaying an organization name.
- **DataTable** columns, in order: Area, Purpose, Access, Destination. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/settings-people`, `/settings-security`, `/settings-audit`, `/settings-privacy`, `/settings-notifications`, `/settings-billing`, `/support`, `/settings-organizations`, `/settings-roles`. Use named links; never assume every row represents the same execution.

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
| Persona | Tenant admin / security admin |
| Goal | People, access and workspace preferences. |
| Entry point | Settings navigation; deep link supported. |
| Happy path | Read context → inspect Administration → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No workspace settings for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: settings-people, settings-security, settings-audit, settings-privacy, settings-notifications, settings-billing, support, settings-organizations, settings-roles. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; All displayed identities and subscription values are synthetic. |

### Domain subtleties

All displayed identities and subscription values are synthetic.

Settings do not grant hidden analytical access merely by displaying an organization name.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Workspace settings                       |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Administration                           |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/settings` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `members` explanation and status.
- [ ] Inspect exact columns: Area, Purpose, Access, Destination. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## settings-people — People & teams

Route: `/settings-people` (prototype `#/settings-people`). Persona: **Tenant admin / security admin**.

Goal: Clear roles and scoped access from the first invitation.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  SETTINGS  /  People & teams                                                       |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Clear roles and scoped access from the first invitation.                                                 |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ACTIVE MEMBERS: 3 [i]  ||  TEAMS: 2 [i]                                                                  |
| Synthetic names only  ||  Finance and Marketing                                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ASSIGNED ROLES: 3 [i]  ||  PENDING INVITATIONS: 0 [i]                                                    |
| Admin, group viewer, platform admin  ||  No messages sent by mockup                                      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| INVITE DIALOG                                                                                            |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Email, role, group scope, expiry and confirmation. Server verifies inviter can grant chosen scope.       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| REVOCATION                                                                                               |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Revoke membership invalidates future access, caches and exports; does not rely on hiding sidebar links.  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Member                    | Role                      | Scope                     | Status                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Alex Morgan               | FinOps admin              | Organization              | Active                    |
| Taylor Chen               | Group viewer              | Finance                   | Active                    |
| Jordan Lee                | Platform admin            | Production                | Active                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Demo Invite saves a local draft and sends no invitation.                                                 |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `members` | Active members: **3** | Synthetic names only | August 2026 / synthetic; Observed |
| `teams` | Teams: **2** | Finance and Marketing | August 2026 / synthetic; Observed |
| `roles` | Assigned roles: **3** | Admin, group viewer, platform admin | August 2026 / synthetic; Observed |
| `pendinginvites` | Pending invitations: **0** | No messages sent by mockup | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Invite dialog**: Email, role, group scope, expiry and confirmation. Server verifies inviter can grant chosen scope.
- **Revocation**: Revoke membership invalidates future access, caches and exports; does not rely on hiding sidebar links.
- **DataTable** columns, in order: Member, Role, Scope, Status. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Prepare invitation. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `settings`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Prepare invitation                                           [X]           |
| Selected metric / resource: [label and identifier]                         |
| Scope and period: [explicit, retained from entry]                          |
| Basis / input publication / coverage: [explain]                            |
| Evidence: [authorized source / parent component]                           |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Prepare invitation]                                             |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | Tenant admin / security admin |
| Goal | Clear roles and scoped access from the first invitation. |
| Entry point | Parent route /settings; deep link supported. |
| Happy path | Read context → inspect Invite dialog → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No people & teams for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Prepare invitation reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Prepare invitation; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Demo Invite saves a local draft and sends no invitation. |

### Domain subtleties

Demo Invite saves a local draft and sends no invitation.

Revoke membership invalidates future access, caches and exports; does not rely on hiding sidebar links.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| People & teams                           |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Invite dialog                            |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Prepare invitation]                     |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/settings-people` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `members` explanation and status.
- [ ] Inspect exact columns: Member, Role, Scope, Status. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## settings-security — Security & SSO

Route: `/settings-security` (prototype `#/settings-security`). Persona: **Tenant admin / security admin**.

Goal: Federation, MFA and session policy.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  SETTINGS  /  Security & SSO                                                       |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Federation, MFA and session policy.                                                                      |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| FEDERATION: SAML / OIDC [i]  ||  MFA POLICY: REQUIRED [i]                                                |
| Production Cognito contract  ||  Visual draft only                                                       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DEMO SESSIONS: 3 [i]  ||  UNRESOLVED SECURITY EVENTS: 0 [i]                                              |
| Not authenticated sessions  ||  Synthetic fixture only                                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SIGN-IN POLICY                                                                                           |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Cognito-backed login in production; SSO callback validates state and tenant routing. Recovery prevents   |
| accidental last-admin lockout.                                                                           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SENSITIVE CHANGES                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Step-up authentication, approval and audited effective policy; no trust in browser role state.           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Control                   | Policy                    | State                     | Owner                     |
+---------------------------+---------------------------+---------------------------+---------------------------+
| SSO                       | SAML / OIDC               | Demo configured           | Security admin            |
| MFA                       | Required                  | Design preview            | Security admin            |
| Session                   | Short-lived tokens        | Design preview            | Platform                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Prototype controls are visual drafts, not authentication/security enforcement.                           |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `sso` | Federation: **SAML / OIDC** | Production Cognito contract | August 2026 / synthetic; Observed |
| `mfa` | MFA policy: **REQUIRED** | Visual draft only | August 2026 / synthetic; Observed |
| `sessions` | Demo sessions: **3** | Not authenticated sessions | August 2026 / synthetic; Observed |
| `securityevents` | Unresolved security events: **0** | Synthetic fixture only | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Sign-in policy**: Cognito-backed login in production; SSO callback validates state and tenant routing. Recovery prevents accidental last-admin lockout.
- **Sensitive changes**: Step-up authentication, approval and audited effective policy; no trust in browser role state.
- **DataTable** columns, in order: Control, Policy, State, Owner. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save policy draft. Opens labelled form fields; required values validate before local save. In production, server validates authorization, schema and stale version.
- **Parent**: `settings`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Save policy draft                                           [X]            |
| Identity provider label: [____________________________]                    |
| Allowed domain: [____________________________]                             |
| Session minutes: [____________________________]                            |
| Change reason: [____________________________]                              |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Save policy draft]                                              |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | Tenant admin / security admin |
| Goal | Federation, MFA and session policy. |
| Entry point | Parent route /settings; deep link supported. |
| Happy path | Read context → inspect Sign-in policy → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No security & sso for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save policy draft reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save policy draft; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Prototype controls are visual drafts, not authentication/security enforcement. |

### Domain subtleties

Prototype controls are visual drafts, not authentication/security enforcement.

Step-up authentication, approval and audited effective policy; no trust in browser role state.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Security & SSO                           |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Sign-in policy                           |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save policy draft]                      |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/settings-security` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `sso` explanation and status.
- [ ] Inspect exact columns: Control, Policy, State, Owner. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## settings-audit — Audit log

Route: `/settings-audit` (prototype `#/settings-audit`). Persona: **Tenant admin / security admin**.

Goal: An accountable record of sensitive changes.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  SETTINGS  /  Audit log                                                            |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| An accountable record of sensitive changes.                                                              |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| VISIBLE AUDIT EVENTS: 3 [i]  ||  ACTORS IN SAMPLE: 3 [i]                                                 |
| Representative authorized sample  ||  No hidden actor enumeration                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DENIED REQUESTS: 1 [i]  ||  AUDIT RETENTION: Policy [i]                                                  |
| Recorded access denial fixture  ||  Set by canonical tenant/legal policy                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| AUDIT INSPECTION                                                                                         |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Actor, tenant, action, resource, request correlation and safe changed-field summary. No tokens or raw    |
| SQL.                                                                                                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| EXPORT                                                                                                   |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Bounded authorized export; original immutable audit evidence is not editable from UI.                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Time UTC                  | Actor                     | Action                    | Outcome                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Sep 02 09:00              | Alex Morgan               | Statement issued          | Success                   |
| Sep 03 11:20              | Jordan Lee                | Capability verified       | Success                   |
| Sep 04 15:30              | Taylor Chen               | Forbidden scope request   | Denied                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| All events are synthetic and cannot certify production security.                                         |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `auditcount` | Visible audit events: **3** | Representative authorized sample | August 2026 / synthetic; Observed |
| `auditactors` | Actors in sample: **3** | No hidden actor enumeration | August 2026 / synthetic; Observed |
| `auditfail` | Denied requests: **1** | Recorded access denial fixture | August 2026 / synthetic; Observed |
| `auditretention` | Audit retention: **Policy** | Set by canonical tenant/legal policy | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Audit inspection**: Actor, tenant, action, resource, request correlation and safe changed-field summary. No tokens or raw SQL.
- **Export**: Bounded authorized export; original immutable audit evidence is not editable from UI.
- **DataTable** columns, in order: Time UTC, Actor, Action, Outcome. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `settings`; breadcrumb and browser Back preserve scope.

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
| Persona | Tenant admin / security admin |
| Goal | An accountable record of sensitive changes. |
| Entry point | Parent route /settings; deep link supported. |
| Happy path | Read context → inspect Audit inspection → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No audit log for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; All events are synthetic and cannot certify production security. |

### Domain subtleties

All events are synthetic and cannot certify production security.

Bounded authorized export; original immutable audit evidence is not editable from UI.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Audit log                                |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Audit inspection                         |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/settings-audit` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `auditcount` explanation and status.
- [ ] Inspect exact columns: Time UTC, Actor, Action, Outcome. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## settings-privacy — Privacy & retention

Route: `/settings-privacy` (prototype `#/settings-privacy`). Persona: **Tenant admin / security admin**.

Goal: Keep the evidence you need, without exposing query secrets.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  SETTINGS  /  Privacy & retention                                                  |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Keep the evidence you need, without exposing query secrets.                                              |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SQL SANITIZATION: ENABLED [i]  ||  RAW SQL PERSISTENCE: OFF [i]                                          |
| Design requirement; no raw query collection  ||  Unsupported parsing quarantines text                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DATA RETENTION: Policy [i]  ||  ACTIVE PRIVACY EXCEPTIONS: 0 [i]                                         |
| Contract-specific; not invented legal duration  ||  No support elevation in fixture                      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SANITIZATION PREVIEW                                                                                     |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Customer literal becomes ?. Unsupported dialect parsing quarantines text rather than leaking raw         |
| content.                                                                                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DELETION WORKFLOW                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Verify requester, retention/legal obligations, tenant scope and derived artifacts before execution.      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Data class                | Policy                    | Retention                 | Behavior                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Query text                | Sanitize before           | Contract policy           | No raw literals           |
|                           | persistence               |                           |                           |
| Raw transport             | Private immutable         | Retention policy          | Replay window             |
| Financial snapshots       | Versioned                 | Contract policy           | Close preserved           |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Saving a mock policy does not alter stored customer data.                                                |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `sanitized` | SQL sanitization: **ENABLED** | Design requirement; no raw query collection | August 2026 / synthetic; Observed |
| `rawsql` | Raw SQL persistence: **OFF** | Unsupported parsing quarantines text | August 2026 / synthetic; Observed |
| `retention` | Data retention: **Policy** | Contract-specific; not invented legal duration | August 2026 / synthetic; Observed |
| `privacyexceptions` | Active privacy exceptions: **0** | No support elevation in fixture | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Sanitization preview**: Customer literal becomes ?. Unsupported dialect parsing quarantines text rather than leaking raw content.
- **Deletion workflow**: Verify requester, retention/legal obligations, tenant scope and derived artifacts before execution.
- **DataTable** columns, in order: Data class, Policy, Retention, Behavior. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save privacy draft. Opens labelled form fields; required values validate before local save. In production, server validates authorization, schema and stale version.
- **Parent**: `settings`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Save privacy draft                                           [X]           |
| Policy name: [____________________________]                                |
| Sanitized text retention days: [____________________________]              |
| Support access duration minutes: [____________________________]            |
| Approval reason: [____________________________]                            |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Save privacy draft]                                             |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | Tenant admin / security admin |
| Goal | Keep the evidence you need, without exposing query secrets. |
| Entry point | Parent route /settings; deep link supported. |
| Happy path | Read context → inspect Sanitization preview → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No privacy & retention for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save privacy draft reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save privacy draft; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Saving a mock policy does not alter stored customer data. |

### Domain subtleties

Saving a mock policy does not alter stored customer data.

Verify requester, retention/legal obligations, tenant scope and derived artifacts before execution.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Privacy & retention                      |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Sanitization preview                     |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save privacy draft]                     |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/settings-privacy` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `sanitized` explanation and status.
- [ ] Inspect exact columns: Data class, Policy, Retention, Behavior. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## settings-notifications — Notification destinations

Route: `/settings-notifications` (prototype `#/settings-notifications`). Persona: **Tenant admin / security admin**.

Goal: A safe route for each alert and report.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  SETTINGS  /  Notification destinations                                            |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| A safe route for each alert and report.                                                                  |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| NOTIFICATION CHANNELS: 4 [i]  ||  SIMULATED DELIVERIES: 2 [i]                                            |
| Email, Slack, Teams, HTTPS  ||  Not evidence of real messages                                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SIMULATED FAILURES: 1 [i]  ||  PENDING DELIVERIES: 0 [i]                                                 |
| Synthetic provider timeout  ||  No external outbox connected                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DESTINATION EDITOR                                                                                       |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Validated destination reference, owner, allowed scope and payload class. Credentials remain masked.      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TEST DELIVERY                                                                                            |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Explicit test action; show logical delivery ID, attempts and safe response. Mockup only previews         |
| payload.                                                                                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Destination               | Type                      | State                     | Sensitive payload         |
+---------------------------+---------------------------+---------------------------+---------------------------+
| FinOps email              | Email                     | Verified demo             | Secure link               |
| Platform channel          | Slack                     | Demo configured           | Summary                   |
| Teams workflow            | Teams                     | Demo configured           | Summary                   |
| Audit webhook             | HTTPS                     | Demo configured           | Signed event              |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| No actual message or network request is generated.                                                       |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `destinationcount` | Notification channels: **4** | Email, Slack, Teams, HTTPS | August 2026 / synthetic; Observed |
| `deliverysuccess` | Simulated deliveries: **2** | Not evidence of real messages | August 2026 / synthetic; Observed |
| `deliveryfailed` | Simulated failures: **1** | Synthetic provider timeout | August 2026 / synthetic; Observed |
| `deliverypending` | Pending deliveries: **0** | No external outbox connected | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Destination editor**: Validated destination reference, owner, allowed scope and payload class. Credentials remain masked.
- **Test delivery**: Explicit test action; show logical delivery ID, attempts and safe response. Mockup only previews payload.
- **DataTable** columns, in order: Destination, Type, State, Sensitive payload. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Preview test payload. Opens labelled form fields; required values validate before local save. In production, server validates authorization, schema and stale version.
- **Parent**: `settings`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Preview test payload                                           [X]         |
| Destination name: [____________________________]                           |
| Type: [____________________________]                                       |
| Owner: [____________________________]                                      |
| Allowed scope: [____________________________]                              |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Preview test payload]                                           |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | Tenant admin / security admin |
| Goal | A safe route for each alert and report. |
| Entry point | Parent route /settings; deep link supported. |
| Happy path | Read context → inspect Destination editor → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No notification destinations for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Preview test payload reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Preview test payload; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; No actual message or network request is generated. |

### Domain subtleties

No actual message or network request is generated.

Explicit test action; show logical delivery ID, attempts and safe response. Mockup only previews payload.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Notification destinations                |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Destination editor                       |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Preview test payload]                   |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/settings-notifications` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `destinationcount` explanation and status.
- [ ] Inspect exact columns: Destination, Type, State, Sensitive payload. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## settings-billing — Subscription & billing

Route: `/settings-billing` (prototype `#/settings-billing`). Persona: **Tenant admin / security admin**.

Goal: Your Bridge subscription, separate from Snowflake cost.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  SETTINGS  /  Subscription & billing                                               |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Your Bridge subscription, separate from Snowflake cost.                                                  |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BRIDGE SUBSCRIPTION: Pilot [i]  ||  PAYMENT STATUS: DEMO [i]                                             |
| Separate SaaS commercial contract  ||  No payment claimed                                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BILLING CONTACT ROLE: 1 [i]  ||  RENEWAL DATE: Contract [i]                                              |
| No real address stored  ||  Commercial terms required                                                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| COMMERCIAL ONBOARDING                                                                                    |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Verified manual B2B payment at first release; payment acceptance recorded by authorized operator, not    |
| inferred from frontend state.                                                                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CUSTOMER DOCUMENTS                                                                                       |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Private authorized order and billing evidence; no invented paid status or automatic processor            |
| integration.                                                                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Item                      | Period                    | Amount                    | State                     |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Bridge pilot subscription | September 2026            | Contract-defined          | Demo pending              |
| Snowflake charges         | August 2026               | 27,000.00 USD             | Separate ledger           |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| SaaS subscription fees do not become customer Snowflake charges.                                         |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `subscription` | Bridge subscription: **Pilot** | Separate SaaS commercial contract | August 2026 / synthetic; Observed |
| `billingstatus` | Payment status: **DEMO** | No payment claimed | August 2026 / synthetic; Observed |
| `billingcontacts` | Billing contact role: **1** | No real address stored | August 2026 / synthetic; Observed |
| `renewal` | Renewal date: **Contract** | Commercial terms required | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Commercial onboarding**: Verified manual B2B payment at first release; payment acceptance recorded by authorized operator, not inferred from frontend state.
- **Customer documents**: Private authorized order and billing evidence; no invented paid status or automatic processor integration.
- **DataTable** columns, in order: Item, Period, Amount, State. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `settings`; breadcrumb and browser Back preserve scope.

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
| Persona | Tenant admin / security admin |
| Goal | Your Bridge subscription, separate from Snowflake cost. |
| Entry point | Parent route /settings; deep link supported. |
| Happy path | Read context → inspect Commercial onboarding → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No subscription & billing for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; SaaS subscription fees do not become customer Snowflake charges. |

### Domain subtleties

SaaS subscription fees do not become customer Snowflake charges.

Private authorized order and billing evidence; no invented paid status or automatic processor integration.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Subscription & billing                   |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Commercial onboarding                    |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/settings-billing` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `subscription` explanation and status.
- [ ] Inspect exact columns: Item, Period, Amount, State. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## support — Help & support

Route: `/support` (prototype `#/support`). Persona: **Tenant admin / security admin**.

Goal: Resolve issues with safe, useful context.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  SETTINGS  /  Help & support                                                       |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Resolve issues with safe, useful context.                                                                |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DRAFT SUPPORT REQUEST: 1 [i]  ||  RESOLVED DEMO CASES: 2 [i]                                             |
| Local browser only  ||  Synthetic history                                                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| OBSERVED COVERAGE: 100% [i]  ||  LAST ACCEPTED SNAPSHOT: Sep 01 [i]                                      |
| Complete selected synthetic intervals  ||  00:00 UTC; synthetic fixed as-of                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUPPORT REQUEST                                                                                          |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Issue category, concise description, affected time/scope and sanitized support bundle preview.           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUPPORT ACCESS                                                                                           |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Time-bounded audited authorization; no standing cross-tenant access or raw credential collection.        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Topic                     | Guidance                  | Evidence                  | Owner                     |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Cost mismatch             | Open reconciliation       | Publication and delta     | FinOps                    |
| Missing history           | Open Data Health          | Source coverage           | Platform                  |
| Access issue              | Review membership         | Safe request ID           | Admin                     |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Mockup stores a local request draft and contacts nobody.                                                 |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `supportopen` | Draft support request: **1** | Local browser only | August 2026 / synthetic; Observed |
| `supportresolved` | Resolved demo cases: **2** | Synthetic history | August 2026 / synthetic; Observed |
| `coverage` | Observed coverage: **100%** | Complete selected synthetic intervals | August 2026 / synthetic; Observed |
| `lastsync` | Last accepted snapshot: **Sep 01** | 00:00 UTC; synthetic fixed as-of | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Support request**: Issue category, concise description, affected time/scope and sanitized support bundle preview.
- **Support access**: Time-bounded audited authorization; no standing cross-tenant access or raw credential collection.
- **DataTable** columns, in order: Topic, Guidance, Evidence, Owner. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save support draft. Opens labelled form fields; required values validate before local save. In production, server validates authorization, schema and stale version.
- **Parent**: `settings`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Save support draft                                           [X]           |
| Subject: [____________________________]                                    |
| Category: [____________________________]                                   |
| Description: [____________________________]                                |
| Contact role: [____________________________]                               |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Save support draft]                                             |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | Tenant admin / security admin |
| Goal | Resolve issues with safe, useful context. |
| Entry point | Parent route /settings; deep link supported. |
| Happy path | Read context → inspect Support request → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No help & support for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save support draft reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save support draft; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Mockup stores a local request draft and contacts nobody. |

### Domain subtleties

Mockup stores a local request draft and contacts nobody.

Time-bounded audited authorization; no standing cross-tenant access or raw credential collection.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Help & support                           |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Support request                          |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save support draft]                     |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/support` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `supportopen` explanation and status.
- [ ] Inspect exact columns: Topic, Guidance, Evidence, Owner. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## settings-organizations — Organizations & accounts

Route: `/settings-organizations` (prototype `#/settings-organizations`). Persona: **Tenant admin / security admin**.

Goal: Discover accounts and make capability boundaries explicit.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  SETTINGS  /  Organizations & accounts                                             |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Discover accounts and make capability boundaries explicit.                                               |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CONNECTED ORGANIZATION: 1 [i]  ||  OBSERVED ACCOUNTS: 1 [i]                                              |
| Demo connection only  ||  PRODUCTION; no fabricated discovered account                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| AVAILABLE CAPABILITIES: 2 / 3 [i]  ||  OBSERVED COVERAGE: 100% [i]                                       |
| Historical operator profile unavailable  ||  Complete selected synthetic intervals                       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DISCOVERY REVIEW                                                                                         |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Show discovered, connected, excluded and unreachable accounts separately. An account omitted by          |
| privileges cannot be claimed nonexistent.                                                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SAFE REFRESH                                                                                             |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Account discovery is repeatable and records verification time/capabilities. It never creates customer-   |
| specific pipeline code.                                                                                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Organization              | Account                   | Identity                  | Coverage                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Acme Group                | PRODUCTION                | WIF demo verified         | August complete           |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| One observed synthetic account does not claim complete coverage of an actual organization.               |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `connections` | Connected organization: **1** | Demo connection only | August 2026 / synthetic; Observed |
| `accounts` | Observed accounts: **1** | PRODUCTION; no fabricated discovered account | August 2026 / synthetic; Observed |
| `capabilities` | Available capabilities: **2 / 3** | Historical operator profile unavailable | August 2026 / synthetic; Observed |
| `coverage` | Observed coverage: **100%** | Complete selected synthetic intervals | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Discovery review**: Show discovered, connected, excluded and unreachable accounts separately. An account omitted by privileges cannot be claimed nonexistent.
- **Safe refresh**: Account discovery is repeatable and records verification time/capabilities. It never creates customer-specific pipeline code.
- **DataTable** columns, in order: Organization, Account, Identity, Coverage. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `settings`; breadcrumb and browser Back preserve scope.

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
| Persona | Tenant admin / security admin |
| Goal | Discover accounts and make capability boundaries explicit. |
| Entry point | Parent route /settings; deep link supported. |
| Happy path | Read context → inspect Discovery review → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No organizations & accounts for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; One observed synthetic account does not claim complete coverage of an actual organization. |

### Domain subtleties

One observed synthetic account does not claim complete coverage of an actual organization.

Account discovery is repeatable and records verification time/capabilities. It never creates customer-specific pipeline code.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Organizations & accounts                 |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Discovery review                         |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/settings-organizations` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `connections` explanation and status.
- [ ] Inspect exact columns: Organization, Account, Identity, Coverage. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## settings-roles — Roles & access scopes

Route: `/settings-roles` (prototype `#/settings-roles`). Persona: **Tenant admin / security admin**.

Goal: Explicit permissions with group and account boundaries.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  SETTINGS  /  Roles & access scopes                                                |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Explicit permissions with group and account boundaries.                                                  |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ASSIGNED ROLES: 3 [i]  ||  ACTIVE MEMBERS: 3 [i]                                                         |
| Admin, group viewer, platform admin  ||  Synthetic names only                                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TEAMS: 2 [i]  ||  PENDING INVITATIONS: 0 [i]                                                             |
| Finance and Marketing  ||  No messages sent by mockup                                                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ROLE EDITOR                                                                                              |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Choose named capabilities, allowed scopes, effective membership and audited reason. Cannot grant broader |
| scope than actor may delegate.                                                                           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ISOLATION PREVIEW                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Client role preview is UX only. Production API and Snowflake/PostgreSQL policies independently reject    |
| guessed cross-tenant identifiers.                                                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Role                      | Analytics                 | Configuration             | Financial close           |
+---------------------------+---------------------------+---------------------------+---------------------------+
| FinOps admin              | Authorized organization   | Allowed                   | Approval required         |
| Group viewer              | Assigned groups only      | Denied                    | Denied                    |
| Platform admin            | Assigned accounts         | Connections only          | Denied                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| No frontend role switch is represented as real security enforcement.                                     |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `roles` | Assigned roles: **3** | Admin, group viewer, platform admin | August 2026 / synthetic; Observed |
| `members` | Active members: **3** | Synthetic names only | August 2026 / synthetic; Observed |
| `teams` | Teams: **2** | Finance and Marketing | August 2026 / synthetic; Observed |
| `pendinginvites` | Pending invitations: **0** | No messages sent by mockup | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Role editor**: Choose named capabilities, allowed scopes, effective membership and audited reason. Cannot grant broader scope than actor may delegate.
- **Isolation preview**: Client role preview is UX only. Production API and Snowflake/PostgreSQL policies independently reject guessed cross-tenant identifiers.
- **DataTable** columns, in order: Role, Analytics, Configuration, Financial close. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `settings`; breadcrumb and browser Back preserve scope.

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
| Persona | Tenant admin / security admin |
| Goal | Explicit permissions with group and account boundaries. |
| Entry point | Parent route /settings; deep link supported. |
| Happy path | Read context → inspect Role editor → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No roles & access scopes for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; No frontend role switch is represented as real security enforcement. |

### Domain subtleties

No frontend role switch is represented as real security enforcement.

Client role preview is UX only. Production API and Snowflake/PostgreSQL policies independently reject guessed cross-tenant identifiers.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Roles & access scopes                    |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Role editor                              |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/settings-roles` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `roles` explanation and status.
- [ ] Inspect exact columns: Role, Analytics, Configuration, Financial close. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

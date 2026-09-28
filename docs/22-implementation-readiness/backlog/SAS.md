# SAS — SaaS surfaces (site, docs, trust, status, e-mail, back office, analytics, support, flags, account, demo)

Source analysis: [SAAS_COMPLETENESS.md](../SAAS_COMPLETENESS.md) (feature matrix vs select.dev and peers, gaps G-SAS-xx, owner questions). Reviewer: SaaS completeness agent, 2026-09-28; integrated into the [revised graph](../revised-task-graph.json) the same day. Status of all tasks: NOT_STARTED. Lane H.

### SAS-001 — Marketing website, pricing page, pilot-request intake and French legal notices
Release: R1 · Estimate: 35–51 h · Risk: M · Decisions: D-17, D-18, D-23, D-36 · Closes: G-SAS-01
Why / where: buyers and procurement land on the website first; D-17 removes the free trial, so the conversion path is "request a pilot"; the French entity must publish LCEN legal notices. Built in P4, public at go-live (LCH-003) through REL-003.
Dependency changes: new; deps INF-006, UX-001; REL-003 +SAS-001. Step-level (no graph edge, keeps the LCH-002 chain unchanged — §4.2): S07 publishes LCH-102's approved legal texts; S04 reads `trust-facts.yaml` from SAS-004-S09, which itself depends on SAS-001's hosting module.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-001-S01 | Write the information architecture and content brief: home (Snowflake-only positioning: ledger reconciled to the invoice, chargeback statements, verified savings), four product pages (Explore, Allocate, Govern, Optimize), integrations, security link, pricing, pilot request, docs, status, legal; English only (D-18). | `sites/www/CONTENT.md` | Owner approval recorded; every claim maps to an R1 row of RELEASE_PLAN §2 in the claims table. | 3 |
| SAS-001-S02 | Scaffold the static site with Astro (version pinned in the FND-002 matrix), shared design tokens from UX-001, no client JavaScript except the form; add a `sites/` workspace to the FND-001 boundary rules. | `sites/www/`, `packages/design-tokens/` | CI builds the site; Lighthouse CI thresholds pass (performance ≥ 90, accessibility ≥ 95). | 3 |
| SAS-001-S03 | Provision hosting: dedicated S3 bucket and CloudFront distribution in a `web-public` stack (never the app distribution), OAC, security headers (CSP `default-src 'self'`, HSTS, `frame-ancestors 'none'`), apex→www redirect, 404 page. | `infra/terraform/modules/public_site/` | Header scan grade A; app and site distributions share no origin or cache behaviour (plan diff). | 3 |
| SAS-001-S04 | Build the home, product and integrations pages (editions and contracts per D-20; dbt, Power BI; Slack, Teams, e-mail, webhook; Entra ID, Okta, Google SSO) and "How Bridge connects" (WIF without stored credentials, fixed egress IPs, customer-side footprint ≈ 12.6–13.2 credits/month/account from D-08). | `sites/www/src/pages/**` | Content review against CONTENT.md passes; the footprint figure is read from `trust-facts.yaml` once SAS-004-S09 lands (CON-101 estimate until then). | 4 |
| SAS-001-S05 | Build the pricing page per D-17: USD platform fee plus managed-spend band, the LCH-105 band rule (MONTH_STABLE ledger total at billed rates, trial accounts excluded, per spend currency), contracted pilot instead of a free trial, FAQ; price levels shown or "on request" per owner answer (§5 Q2); plan data generated from the LCH-001-S01 catalogue. | `sites/www/src/pages/pricing.astro`, `sites/www/data/plans.yaml` | CI fails when `plans.yaml` differs from the approved catalogue version. | 3 |
| SAS-001-S06 | Build the pilot-request form (name, work e-mail, company, number of Snowflake accounts, spend range, region, message) posting to a Lambda function URL behind CloudFront: store in DynamoDB (eu-west-1, TTL 400 days), notify the sales inbox via SES; honeypot and WAF rate rule; consent text with privacy-notice link; no CRM vendor in R1. | `services/public_intake/`, `infra/terraform/modules/public_intake/` | A test submission appears in DynamoDB and the inbox; the 11th submission within one minute from one IP is blocked. | 4 |
| SAS-001-S07 | Publish the legal notices page (*mentions légales*, LCEN art. 1-1: company name, legal form, share capital, registered office, RCS/SIREN, VAT number, publication director, host name/address/phone) in French and English, plus links to privacy notice, cookie notice and terms (LCH-102). | `sites/www/src/pages/legal/*` | Text version matches the counsel-approved entry in `docs/legal/approvals.yaml`. | 2 |
| SAS-001-S08 | Implement cookieless audience measurement from CloudFront standard logs: nightly Athena job aggregates page views and referrers per day, drops IP and user agent before storage, 13-month retention; document the CNIL-exemption analysis; no consent banner is needed because no cookie or tracker is set. | `services/site_analytics/`, `docs/legal/cookie-analysis.md` | A Playwright crawl of every page records 0 cookies and 0 third-party requests; aggregated table has no IP column. | 3 |
| SAS-001-S09 | Add SEO metadata: titles, descriptions, OpenGraph images, `sitemap.xml`, canonical URLs, Organization/SoftwareApplication structured data; `robots.txt` disallows everything on staging. | site config | Staging returns `Disallow: /`; production sitemap validates. | 2 |
| SAS-001-S10 | Run accessibility and responsive checks (axe at 390 px and 1280 px, keyboard navigation, contrast from the UX-001 token audit). | `sites/www/tests/a11y.spec.ts` | 0 critical or serious axe violations on every page. | 2 |
| SAS-001-S11 | Centralize outbound links (app, docs, status, trust, legal) in one `links.yaml` and run a link checker in CI. | `sites/links.yaml`, CI job | A broken link fails CI. | 1 |
| SAS-001-S12 | Review claims: forbid "SOC 2 certified" (D-25), "99.9 % SLA" (D-31 objectives only), "real-time" (D-24) and savings percentages without verified evidence; lint the phrases. | `sites/www/CLAIMS.md`, lint rule | Reviewer sign-off; a forbidden phrase fails CI. | 2 |
| SAS-001-S13 | Create the publish pipeline: password-protected staging preview (CloudFront function + signed cookie), production publish with manual approval, rollback to the previous build. | `.github/workflows/site-publish.yml` | Staging is not publicly reachable; production publish requires an approver; rollback rehearsed. | 2 |
| SAS-001-S14 | Evidence. | `docs/evidence/SAS-001/<commit>/` | – | 1 |

Task acceptance:
- [ ] The public site states only R1-true claims, explains D-17 pricing and routes prospects to a pilot request without a third-party CRM.
- [ ] Legal notices required of a French company are published in counsel-approved wording.
- [ ] No cookie, tracker or third-party request is set by the site; audience statistics contain no IP address.

### SAS-002 — Public documentation site with versioning, search and a generated metric glossary
Release: R1 · Estimate: 32–46 h · Risk: M · Decisions: D-08, D-09, D-13, D-18, D-38 · Closes: G-SAS-02
Why / where: ONB-002 authors the customer guides in `docs/customer/**`; D-38 requires customers to find them without staff; the app must deep-link to stable anchors. Plugs in after ONB-002 drafting (M5) and API-001; REL-003 +SAS-002.
Dependency changes: new; deps API-001, SAS-001, UX-001; REL-003 +SAS-002. Step-level: S02 publishes whatever ONB-002 has drafted and the release docs version is cut when ONB-002 finalizes (no graph edge on ONB-002, which finishes late — §4.2).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-002-S01 | Record the docs-stack decision (Astro Starlight, Pagefind static search, no hosted search vendor) and pin versions in the FND-002 matrix. | `docs/architecture/decisions/docs-site.md` | Reviewed by FE lead; versions locked. | 1 |
| SAS-002-S02 | Scaffold `sites/docs/` whose content is read from `docs/customer/**` at build time (single source, no copies); sidebar from `docs/customer/index.md`. | `sites/docs/` | Build renders every ONB-002 guide; a guide missing from the sidebar fails CI. | 3 |
| SAS-002-S03 | Version docs per release (REL-001 manifest): `/latest/` and `/v<major.minor>/` paths, outdated-version banner, build per release tag. | build scripts | Two versions build side by side; the old one shows the banner. | 3 |
| SAS-002-S04 | Generate reference pages: metric glossary from the API-001 registry (id, version, unit, additivity, maturity behaviour, formula reference), permissions reference from CON-003 templates, onboarding blocker codes from `docs/onboarding/blockers.yaml`, API problem types from OpenAPI. | `tools/docs/generate_reference.py` | A registry change without regenerated docs fails CI (diff check). | 4 |
| SAS-002-S05 | Write concept pages reviewed by the FinOps owner: PROVISIONAL/FINAL/MONTH_STABLE/RECONCILED and close (D-13), unknown ≠ zero, allocation books and residuals, potential vs verified savings, Bridge overhead (D-08), managed spend (D-17). | `docs/customer/concepts/*.md` | FinOps reviewer sign-off recorded. | 4 |
| SAS-002-S06 | Render install pages from the generated CON-003 scripts for a sample configuration (reuse ONB-002-S02's CI diff), with copy buttons and highlighted placeholders. | include component | Script text on the page equals the generated script for the same config revision. | 2 |
| SAS-002-S07 | Add Pagefind search indexed at build; no external calls at query time. | search integration | Offline search finds "OPERATE" in the install guide; network log shows no third-party request. | 2 |
| SAS-002-S08 | Host at `docs.<domain>` through the SAS-001 `public_site` module (own distribution, same headers), 404 page, redirect map for moved pages. | Terraform instance | TLS and headers grade A; a moved page redirects with 301. | 2 |
| SAS-002-S09 | Publish a stable anchor registry `docs-links.yaml` consumed by the app (SAS-007, UX help links) with a CI check that each anchor exists. | `sites/docs/docs-links.yaml`, CI check | Removing a referenced heading fails CI. | 2 |
| SAS-002-S10 | Add a "Was this page helpful?" control posting page id and vote to the SAS-001 intake endpoint (no third party, no free text in R1). | component | Votes stored with page id only. | 2 |
| SAS-002-S11 | Add quality gates: Vale terminology lint (e.g., "managed spend", "PROVISIONAL"), link check, spelling (EN), screenshot freshness from ONB-002-S10 per release. | CI jobs | A banned synonym or stale screenshot fails CI. | 3 |
| SAS-002-S12 | Run accessibility checks (axe on all pages; code blocks keyboard-scrollable). | test job | 0 critical axe violations. | 1 |
| SAS-002-S13 | Wire publishing into REL-002 (docs version published with each release) and on docs-only merges, with rollback to the previous build. | workflow | Release rehearsal publishes the matching docs version. | 2 |
| SAS-002-S14 | Evidence. | `docs/evidence/SAS-002/<commit>/` | – | 1 |

Task acceptance:
- [ ] Every customer guide, generated reference and concept page is public, searchable and versioned with the release it matches.
- [ ] Metric definitions shown in docs cannot drift from the API-001 registry.
- [ ] App help links resolve to existing anchors (CI-enforced).

### SAS-003 — Public changelog, release-notes pipeline and in-app "What's new"
Release: R1 · Estimate: 17–25 h · Risk: L · Decisions: D-18, D-19 · Closes: G-SAS-03
Why / where: LCH-003-S06 writes v1.0.0 notes once; continuous delivery by coding agents (D-19) needs dated, reviewable entries, deprecation notices and in-app awareness; metric-definition changes must be announced to keep financial trust. Plugs in after REL-001.
Dependency changes: new; deps REL-001, SAS-002, UX-001, SAS-013.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-003-S01 | Define the entry schema (date UTC, title, category NEW/IMPROVED/FIXED/DEPRECATED/SECURITY, audience, affected metric ids and versions, flag keys, links) and add a "customer-visible change" field to the PR template. | `changelog/schema.json`, `.github/pull_request_template.md` | Schema lint rejects an entry without category or date. | 2 |
| SAS-003-S02 | Build the drafter: from merged PRs in the REL-001 release manifest labelled customer-visible, produce draft entries; a human edits; nothing auto-publishes. | `tools/release/changelog_draft.py` | Draft generated for a fixture release; publish requires a reviewed commit. | 3 |
| SAS-003-S03 | Publish at `docs.<domain>/changelog` with RSS/Atom feeds and per-entry permalinks. | docs pages, feeds | Feeds validate (W3C feed validator). | 2 |
| SAS-003-S04 | CI rule: any API-001 metric version bump or methodology document change requires a changelog entry referencing the metric id. | CI check | A registry bump without an entry fails CI. | 2 |
| SAS-003-S05 | Deprecation entries carry a sunset date ≥ 90 days after publication (aligned with API-006-S06 `Sunset` headers when the public API ships). | schema rule | An entry with a 30-day sunset fails validation. | 1 |
| SAS-003-S06 | Build the in-app "What's new" panel from a same-origin JSON copy of the feed published into the SPA bucket at release; unread marker per user from the SAS-013 preference store; no third-party widget. | `apps/web/src/platform/whats-new/` | New entry shows the unread dot once per user; the CSP needs no new origin. | 3 |
| SAS-003-S07 | Coordinate SECURITY entries with the OPS-107 disclosure policy (CVE references, fixed versions). | policy section | Template reviewed by the security owner. | 1 |
| SAS-003-S08 | Tests: feed schema, unread logic, keyboard and screen-reader access of the panel. | `tests/spec/SAS-003/` | All pass; axe clean. | 2 |
| SAS-003-S09 | Evidence. | `docs/evidence/SAS-003/<commit>/` | – | 1 |

Task acceptance:
- [ ] Every release with customer-visible changes has a reviewed, dated entry; metric-definition changes cannot ship silently.
- [ ] Users see new entries in the app without any third-party script.

### SAS-004 — Trust center: security overview, subprocessors, legal hub and accessibility statement
Release: R1 · Estimate: 25–36 h · Risk: M · Decisions: D-10, D-21, D-23, D-25, D-31, D-36, D-37 · Closes: G-SAS-04
Why / where: procurement reads a trust page before sending a questionnaire; LCH-102 produces DPA annexes, whitepaper and questionnaire answers as files, OPS-107 the VDP and `security.txt`, OPS-108 the vendor register. D-25 (SOC 2-ready, not certified) must be worded exactly. Plugs in after LCH-102 and OPS-107; REL-003 +SAS-004.
Dependency changes: new; deps LCH-102, OPS-107, OPS-108, SAS-001; REL-003 +SAS-004. Step-level: S03 sends through SAS-006, S05 routes to SAS-011's helpdesk.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-004-S01 | Write the security overview: what Bridge reads and never stores (sanitized SQL, pseudonymized users — D-10), WIF without stored Snowflake credentials (D-21), isolation layers, encryption, backup and recovery tiers, single EU region (D-23), availability objectives (D-31, objectives not SLA), breach notice ≤ 48 h to the controller, compliance status "SOC 2-ready controls" (D-25). | `sites/trust/src/pages/index.md` | Security owner and owner approve; no claim beyond D-25 wording. | 3 |
| SAS-004-S02 | Generate the subprocessor page from `docs/legal/subprocessors.md` / `docs/security/vendors.yaml` (entity, purpose, data categories, location, transfer mechanism); list customer-directed destinations separately (LCH-102-S04); CI check that every vendor configured in infrastructure (status, error tracking, helpdesk, e-mail) appears in the register. | generator + CI check | A vendor DSN/endpoint in Terraform without a register row fails CI. | 3 |
| SAS-004-S03 | Implement subprocessor change notifications: double-opt-in subscription (SAS-006), notice ≥ 30 days before a new subprocessor, public archive of notices. | subscription endpoint, archive page | A test notice reaches a subscribed address; unsubscribed addresses receive nothing. | 3 |
| SAS-004-S04 | Build the legal hub: ToS/MSA, DPA with annexes, privacy notice, cookie notice, acceptable use, support policy (LCH-104), SLA stance, legal notices; each with version, effective date, PDF and archived prior versions. | `sites/trust/src/pages/legal/**` | Every document version equals the approved entry in `docs/legal/approvals.yaml`. | 3 |
| SAS-004-S05 | Implement the NDA-gated document request (pentest letter, questionnaire pack, SOC 2 report when one exists): form → helpdesk ticket (SAS-011) → manual NDA; no gated-portal vendor in R1. | form + ticket routing | A request creates a ticket tagged `trust-docs` with SLA timer. | 2 |
| SAS-004-S06 | Publish the accessibility statement: WCAG 2.2 AA target, method (UX-008 axe on all routes + screen-reader checklist), known limitations, contact; record the EAA applicability analysis for counsel (B2B-only service; micro-enterprise status TO VERIFY). | `sites/trust/src/pages/accessibility.md`, `docs/legal/eaa-analysis.md` | Statement lists the limitations open in the UX-008 register. | 2 |
| SAS-004-S07 | Link `security.txt`, the VDP (OPS-107-S08) and the security contact; optional PGP key. | page section | Links resolve; `security.txt` Expires field present. | 1 |
| SAS-004-S08 | Publish a self-assessment summary derived from LCH-102-S07 answers (CAIQ-lite style); each answer cites evidence or states NOT_IMPLEMENTED. | `sites/trust/src/pages/self-assessment.md` | Reviewer finds no answer without evidence or NOT_IMPLEMENTED. | 3 |
| SAS-004-S09 | Create `trust-facts.yaml` (RPO/RTO per tier, retention days, breach-notice hours, session timeouts, egress IPs policy, customer-side footprint) consumed by the trust, marketing and docs sites; CI compares it with the OPS-005 retention matrix and SEC Appendix D values. | `sites/trust-facts.yaml`, CI check | Changing a retention value in only one place fails CI. | 3 |
| SAS-004-S10 | Host at `trust.<domain>` with the SAS-001 module; schedule a quarterly review in the OPS-108 evidence calendar. | Terraform instance, calendar entry | Page live on staging; review task exists. | 1 |
| SAS-004-S11 | Evidence. | `docs/evidence/SAS-004/<commit>/` | – | 1 |

Task acceptance:
- [ ] A buyer can read the security posture, subprocessors, legal documents and accessibility statement without contacting Bridge; gated documents follow a ticketed NDA path.
- [ ] Numbers on the trust page cannot diverge from the operational sources (CI).
- [ ] Compliance wording never exceeds "SOC 2-ready" until an audit report exists.

### SAS-005 — Status page automation, maintenance windows and in-app service banners
Release: R1 · Estimate: 18–26 h · Risk: M · Decisions: D-31, D-37 · Closes: G-SAS-05
Why / where: OPS-102-S07 sets up a private status page (3 h) and LCH-104-S07 makes it public (1 h); no task chooses the vendor, maps components to SLIs, hosts outside the failure domain, notifies subscribers or shows incidents in the app. Plugs in after OPS-003 and OPS-102; REL-003 +SAS-005.
Dependency changes: new; deps OPS-102, OPS-003, LCH-104, CTL-102, UX-001.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-005-S01 | Record the vendor decision: EU-hosted service (recommended: Better Stack, EU data, subscriber e-mails, API) vs self-hosted static page on a non-AWS host; criteria include independence from eu-west-1 and subprocessor impact (subscriber e-mails are personal data). | `docs/decisions/status-page.md` | ≥ 2 options evaluated; owner answer to §5 Q1 recorded; LCH-102 register updated. | 2 |
| SAS-005-S02 | Define components aligned with SLOs: Web app and sign-in, Analytics API, Data freshness (per source family), Reports and notifications, Snowflake connectivity (Bridge side); map each to OPS-003 SLIs and synthetic probes. | `docs/support/status-components.yaml` | Every component has ≥ 1 SLI and a runbook link. | 2 |
| SAS-005-S03 | Build `status_sync`: an OPS-003 burn-rate page for a component opens a DRAFT incident through the vendor API; a human incident commander publishes; recovery suggests resolution. | `services/status_sync/` | A staging probe failure creates a draft within 5 min; nothing becomes public without a human action. | 3 |
| SAS-005-S04 | Schedule maintenance windows from the ops API (CTL-102) to the status page and the in-app banner ≥ 5 business days ahead (LCH-104-S03). | ops API command | A scheduled window appears on both surfaces with the same times (UTC and CET). | 2 |
| SAS-005-S05 | Serve in-app service status from a static JSON in the SPA bucket updated by `status_sync` (works when the API is degraded) and render a banner component with severity and link. | `apps/web/src/platform/service-banner/`, JSON writer | With the API origin disabled in staging the banner still renders the incident. | 3 |
| SAS-005-S06 | Enable subscriber notifications (e-mail, RSS) per component. | vendor config | A subscribed test address receives the drill notification. | 1 |
| SAS-005-S07 | Configure `status.<domain>` DNS and TLS; verify reachability with the app distribution disabled. | DNS record | Status page reachable during the simulated app outage. | 1 |
| SAS-005-S08 | Write incident templates (investigating, identified, monitoring, resolved) and the data-correction notice for financial restatements, aligned with LCH-104-S05. | `docs/support/status-templates.md` | Reviewed by support owner. | 1 |
| SAS-005-S09 | Drill: simulated outage → draft → publish → banner → resolve; record timings. | drill record | Publication ≤ 15 min after detection during coverage hours (D-37). | 2 |
| SAS-005-S10 | Evidence. | `docs/evidence/SAS-005/<commit>/` | – | 1 |

Task acceptance:
- [ ] Probe failures reach a draft status incident automatically; publication is a human decision.
- [ ] Customers see incidents and maintenance on the status page and in the app, even when the API is down.

### SAS-006 — Transactional and lifecycle e-mail system (templates, preferences, Cognito via SES, deliverability)
Release: R1 · Estimate: 37–54 h · Risk: H · Decisions: D-10, D-18, D-23, D-38 · Closes: G-SAS-06
Why / where: Cognito's default sender is capped at 50 e-mails/day per user pool and honours custom message parameters only with `DEVELOPER` (VERIFIED); invitation e-mails (CTL-003-S05) have no template owner; there is no preference center or one-click unsubscribe; lifecycle nudges drive self-service completion (D-38). S02 lands with SEC-002 in P1; the rest in P4. Respects RECONCILIATION U-07 (INF-006 owns the SES identity; GOV-006/007 own adapters and dispatch).
Dependency changes: new; deps INF-006, GOV-006, GOV-007, SEC-002, CTL-003, ONB-001; REL-003 +SAS-006. S02 is scheduled with SEC-002 in P1 (step-level).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-006-S01 | Write the e-mail catalogue: every system e-mail with category (TRANSACTIONAL_SECURITY: password reset, MFA change, SSO configuration change, support-access request/approval/expiry, privacy-mode change; TRANSACTIONAL_SERVICE: invitation, connection broken, backfill complete, first reconciliation available, spend band threshold approaching (LCH-105), deletion certificate ready, maintenance notice; LIFECYCLE: onboarding stalled, first reconciliation → create a budget, inactive 30 days; ANNOUNCEMENT: product updates, subprocessor changes), trigger event, recipients, disclosure level (no amounts in subjects; D-10 pseudonyms). | `docs/email/catalogue.yaml` | Every outbox event that mentions e-mail in CTL/ONB/OPS/LCH tasks has a catalogue row. | 3 |
| SAS-006-S02 | Configure the Cognito user pool with `EmailSendingAccount=DEVELOPER` on the INF-006 SES identity and a custom-message Lambda rendering branded templates from message keys (D-18); add a policy test forbidding `COGNITO_DEFAULT`. | `infra/terraform/modules/cognito_email/`, `services/cognito_messages/` | 100 staging verification e-mails in one hour are all delivered; `terraform plan` with `COGNITO_DEFAULT` fails the policy job. | 4 |
| SAS-006-S03 | Build the template package: MJML sources compiled to HTML and plain text at build, strings from the shared FormatJS catalogue, brand header, legal footer (company notice, preferences link), snapshot tests per template. | `packages/email_templates/` | Snapshot suite passes; a literal string in a template fails lint. | 4 |
| SAS-006-S04 | Route system e-mails through the GOV-007 outbox as kind `system_message` (same logical-delivery id and retry semantics) and the GOV-006 e-mail adapter; one SES configuration set per category. | `services/notifications/system_messages.py` | Duplicate event → one logical delivery; configuration set visible per message in SES events. | 3 |
| SAS-006-S05 | Isolate reputation: TRANSACTIONAL_* on `notify.<domain>` (INF-006), LIFECYCLE/ANNOUNCEMENT on `news.<domain>` with its own DKIM, custom MAIL FROM and DMARC (change request to INF-006). | Terraform change request, SES identities | Both identities DKIM-verified; DMARC aligned for each. | 2 |
| SAS-006-S06 | Implement preferences: per-user, per-category opt-out stored in `identity.notification_preferences` (TRANSACTIONAL_* cannot be disabled); `List-Unsubscribe` and `List-Unsubscribe-Post: List-Unsubscribe=One-Click` (RFC 8058) on LIFECYCLE/ANNOUNCEMENT; signed-token unsubscribe endpoint that needs no login. | migration, `apps/api/email_preferences/` | One-click POST unsubscribes without a session; security e-mails still send after opt-out. | 3 |
| SAS-006-S07 | Apply suppression: SES account-level suppression list plus the GOV-006-S04 bounce/complaint consumer; a hard-bounced invitation notifies the inviter in the app. | consumer extension | Bounced invitation shows "undeliverable" to the inviter; address suppressed. | 2 |
| SAS-006-S08 | Build the lifecycle engine: daily rules over domain facts (ONB-001 projection, last login, budget count) with at most one lifecycle e-mail per user per 3 days, no weekend sends, stop when the condition resolves; rules versioned in `lifecycle_rules.yaml`. | `services/lifecycle/` | Fixture user stalled at the install step receives one nudge; after the step completes, none. | 4 |
| SAS-006-S09 | Monitor deliverability: bounce rate > 2 % and complaint rate > 0.08 % alarms (below SES review thresholds), weekly DMARC aggregate-report parsing, seed-inbox test (Gmail, Outlook test accounts) on every template change. | alarms, `tools/email/dmarc_report.py` | Alarms fire in a staging fault test; seed test lands in inbox, not spam. | 3 |
| SAS-006-S10 | Send security notifications to tenant Owners on SSO configuration change, support-access grant, privacy-mode change and bulk export, triggered from SEC-008 audit events. | rule set | Each audit action in the list produces exactly one Owner e-mail. | 2 |
| SAS-006-S11 | Disable SES open/click tracking, forbid tracking pixels and redirect links; add recipient addresses to the OPS-104 data inventory. | configuration, inventory row | Rendered HTML contains no tracking pixel or redirect host (test). | 1 |
| SAS-006-S12 | Tests: idempotent retry, opt-out respected, security category not opt-outable, one-click unsubscribe, localized Cognito reset template, rendering at 390 px and in dark-mode clients via Playwright screenshots of the HTML. | `tests/spec/SAS-006/` | All pass. | 4 |
| SAS-006-S13 | Runbook (SES sandbox → production, reputation incident, template rollback) and evidence. | `docs/runbooks/email.md`, `docs/evidence/SAS-006/<commit>/` | Drill executed. | 2 |

Task acceptance:
- [ ] Cognito sends through SES with branded, localized templates; the 50/day default can never be configured.
- [ ] Every system e-mail has an owner, a category and a template; non-transactional mail carries one-click unsubscribe and respects preferences.
- [ ] Lifecycle nudges are bounded, stop when resolved and contain no amounts or tracking.

### SAS-007 — In-app getting-started checklist, contextual help and empty-state calls to action
Release: R1 · Estimate: 21–30 h · Risk: M · Decisions: D-18, D-38 · Closes: G-SAS-07
Why / where: ONB-001 ends at first value; the practice-building steps that follow have no guidance, and UX-001's StateBlock has no content contract for calls to action. Plugs in after ONB-001 and the pages it links to (P4).
Dependency changes: new; deps ONB-001, UX-001, UX-002, GOV-001, GOV-006, RPT-004, ALC-003, CTL-003. Step-level: S04/S05 consume SAS-002's anchor registry.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-007-S01 | Define the practice checklist as projections of domain facts (as ONB-001, G-ONB-01): ≥ 2 members invited, ruleset published, budget created, Slack/Teams destination verified, monitor active, report scheduled, first insight reviewed; each with its completion predicate API. | `docs/onboarding/practice-checklist.md` | Every item's predicate references an existing domain API. | 2 |
| SAS-007-S02 | Implement `GET /v1/getting-started` computed from domain facts (no mutable status), dismissible per user. | `apps/api/getting_started/` | Revoking the only Slack destination re-opens that item on the next call. | 3 |
| SAS-007-S03 | Build the Home checklist card for Owner and FinOps Admin personas with progress and deep links into creation flows carrying context. | `apps/web/src/pages/home/getting-started/` | Playwright: each link opens the right form pre-filled; viewers do not see the card. | 3 |
| SAS-007-S04 | Write the empty-state content contract for each page family of UX §3.1: empty-confirmed copy, primary action, docs anchor (SAS-002 `docs-links.yaml`), permission-aware variant ("ask your administrator"). | `apps/web/src/content/empty-states.ts` (message keys) | Every screen in §3.1 has an entry (CI check). | 3 |
| SAS-007-S05 | Add contextual help: a help affordance on KPI tiles opening the generated metric-glossary entry (SAS-002) next to Explain; help drawer renders docs excerpts from a same-origin JSON. | component | Keyboard-operable; no cross-origin request. | 3 |
| SAS-007-S06 | Offer guided first actions as drafts only: "Budget from last 3 complete months run-rate", "Daily warehouse spend anomaly monitor", "Weekly digest to a channel" (PRO-003); nothing activates without explicit save. | templates | Drafts are created inactive; activation requires the normal form submit. | 3 |
| SAS-007-S07 | Emit checklist completion events to SAS-009 and build the funnel view. | event registrations | Funnel shows fixture tenants' progress. | 1 |
| SAS-007-S08 | Tests: projection correctness, viewer copy, axe and keyboard. | `tests/spec/SAS-007/` | All pass. | 2 |
| SAS-007-S09 | Evidence. | `docs/evidence/SAS-007/<commit>/` | – | 1 |

Task acceptance:
- [ ] The checklist can never claim completion that domain state contradicts.
- [ ] Every empty page explains why it is empty and offers the permitted next action with a docs link.

### SAS-008 — Customer-360 back-office view and operator workflows
Release: R1 · Estimate: 33–48 h · Risk: H · Decisions: D-17, D-19, D-25, D-37 · Closes: G-SAS-08
Why / where: CTL-102 owns the single ops plane, OPS-106 the CLI, SEC-104 support grants, LCH-001 finance forms (RECONCILIATION U-05); no page shows one customer's state. With 1–2 humans on support (D-19, D-37), triage time is the constraint. The view is metadata-only unless a SEC-104 grant exists. Plugs in on CTL-102's console after SEC-104 and ONB-001.
Dependency changes: new; deps CTL-102, SEC-104, LCH-001, LCH-101, ONB-001, ING-012, CON-005, REL-102, OPS-101.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-008-S01 | Write the data contract: fields visible without a support grant (tenant/org/account ids and names, connection and capability status, coverage dates, publication times, reconciliation outcome codes without amounts, incident counts, entitlement counters, subscription state; invoice references for `finance_operator` only); everything else requires a SEC-104 `analytics_read` grant. | `docs/operations/customer-360-contract.md` | Reviewed and signed by the security owner. | 3 |
| SAS-008-S02 | Implement ops API read endpoints aggregating these fields per tenant on the CTL-102 plane (roles `ops_viewer`, `support_agent`, `finance_operator`), each field read from its owning domain API — no copies. | `apps/ops_api/customer360/` | Contract test: response keys ⊆ the contract allowlist per role. | 4 |
| SAS-008-S03 | Build the console pages: tenant list (filters: state, plan, health flags) and tenant page with tabs Overview, Connections and coverage, Pipeline (OPS-101 timeline links), Financial status (codes), Commercial (finance only), Flags and entitlements, Support, Operator audit. | `apps/internal_console/customer360/` | Playwright on fixture tenants renders every tab; the Commercial tab is absent for `support_agent`. | 4 |
| SAS-008-S04 | Compute rule-based health flags (no score in R1): connection failing > 24 h, coverage gap, publication age > SLO, reconciliation FAILED, PAST_DUE, onboarding stalled > 5 business days, delivery DLQ > 0. | `apps/ops_api/customer360/flags.py` | Each flag has a fixture that raises it and one that clears it. | 3 |
| SAS-008-S05 | Expose existing commands from the page, each with its own authorization: request support access (SEC-104), pause tenant extraction (REL-102 kill switch), re-probe a connection (CON-005), resend an invitation (CTL-003). | action buttons calling existing endpoints | Each action is refused for a role lacking its capability; all are audited. | 3 |
| SAS-008-S06 | Add append-only operator notes (`ops.customer_notes`) with a lint blocking pasted money values, SQL and e-mail addresses. | migration, API | A note containing `SELECT` or `1,234.56 USD` is rejected. | 2 |
| SAS-008-S07 | Audit every console view of a tenant (`ops.customer360.viewed`) to the platform security stream (SEC-008-S09); tenant-visible audit only for grant use (SEC-104-S06). | emitter | View events recorded with operator id, tenant id, tab. | 2 |
| SAS-008-S08 | Show linked tickets and SLA timers from SAS-011 (tenant id and request ids on tickets). | panel | Fixture ticket appears on the tenant page with its timer. | 2 |
| SAS-008-S09 | Add search by tenant slug, account locator, request_id and batch_id. | search endpoint | Each key finds the fixture tenant in < 1 s. | 2 |
| SAS-008-S10 | Access tests: `support_agent` without grant sees no amounts, names beyond the contract or SQL; customer Cognito session rejected; public internet cannot reach the console. | `tests/security/test_customer360.py` | All denied as specified. | 3 |
| SAS-008-S11 | Performance and resilience: tenant page p95 < 2 s on a 100-tenant fixture; each panel fails independently with its request id. | load test | Measured p95 recorded; a failing panel does not blank the page. | 2 |
| SAS-008-S12 | Write the first-response triage runbook using the page, linked from RB-xx runbooks. | `docs/runbooks/customer-triage.md` | Second operator completes a fixture triage from the runbook. | 2 |
| SAS-008-S13 | Evidence. | `docs/evidence/SAS-008/<commit>/` | – | 1 |

Task acceptance:
- [ ] One page answers "what is wrong with this customer?" from metadata only; analytics require a customer-approved grant.
- [ ] Every operator view and action is audited; roles see only their contract fields.

### SAS-009 — First-party product analytics with privacy controls
Release: R1 · Estimate: 22–32 h · Risk: M · Decisions: D-10, D-23, D-25, D-38 · Closes: G-SAS-09
Why / where: no task measures feature adoption beyond ONB-001-S16 funnel counters; D-38's self-service claim, customer success and R2 prioritization need evidence. A third-party SDK in a financial app would see routes and content and add a subprocessor; first-party events avoid both. Plugs in after OPS-001 and UX-002.
Dependency changes: new; deps OPS-001, UX-002, OPS-104, INF-008. Step-level: S04 reuses OPS-009's `INTERNAL_COST` grant pattern; S06 feeds LCH-102-S09's privacy notice.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-009-S01 | Define event taxonomy v1 (≤ 60 events, e.g. `page_viewed(route_id)`, `explain_opened(metric_id)`, `export_created(kind)`, `budget_created`, `insight_status_changed(to)`, `digest_created`) with a property allowlist: no values, amounts, names, SQL, free text or URLs (route ids only). | `packages/product_events/taxonomy.v1.yaml` | Schema lint rejects a property outside the allowlist. | 3 |
| SAS-009-S02 | Define identity keys: `user_key = HMAC(k_analytics, subject_id)` with yearly key rotation, `tenant_key` opaque; re-identification only through the SAS-008 console. | key management note, KMS key | No subject id or e-mail reaches the event store (scan). | 2 |
| SAS-009-S03 | Emit server-side from API mutations (authoritative) and minimal client events through a batched `POST /v1/product-events` (BFF, schema-validated, unknown keys dropped, rate-limited). | `packages/product_events/`, endpoint | 1,000 fixture events validate; an event with an amount property is dropped and counted. | 3 |
| SAS-009-S04 | Store in an `INTERNAL_PRODUCT` schema of the central Snowflake internal database provisioned by INF-008 (same grant pattern as OPS-009 `INTERNAL_COST`: no serving or customer role), 25-month retention. | `infra/snowflake/internal_product.sql`, loader | `SHOW GRANTS` lists only the internal analytics and loader roles. | 3 |
| SAS-009-S05 | Honour controls: tenant-level opt-out (Owner, Settings › Privacy) at emission; support-access sessions (SEC-104) and synthetic/demo tenants never emit. | checks in emitter | Opt-out tenant and support sessions produce 0 events in tests. | 2 |
| SAS-009-S06 | Document the legal basis (legitimate interest for service improvement; balancing test for counsel), privacy-notice section (LCH-102-S09) and OPS-104 inventory row. | `docs/legal/product-analytics-lia.md` | Counsel review requested; inventory CI passes. | 2 |
| SAS-009-S07 | Build internal dashboards: time to FV-1, weekly active users per tenant, feature adoption matrix, getting-started funnel (SAS-007). | internal dashboards | Dashboards render fixture data. | 3 |
| SAS-009-S08 | Tests: payload scanner rejects money-like values, e-mails, SQL fragments and URLs with query strings; taxonomy v1 → v2 evolution stays readable. | `tests/spec/SAS-009/` | All pass. | 3 |
| SAS-009-S09 | Evidence. | `docs/evidence/SAS-009/<commit>/` | – | 1 |

Task acceptance:
- [ ] Adoption and activation are measurable without any third-party analytics vendor, cookie or session replay.
- [ ] Events contain no customer values, names, SQL or URLs; tenants can opt out.

### SAS-010 — Error monitoring and real-user monitoring with scrubbing
Release: R1 · Estimate: 19–28 h · Risk: M · Decisions: D-23, D-25 · Closes: G-SAS-10
Why / where: OPS-001 provides logs, traces and metrics; UX-001-S11 sends client telemetry "to an OPS endpoint" that no task builds; nothing groups exceptions into issues with release regression detection and source-mapped stacks, which coding agents need to fix defects. Plugs in after OPS-001 and INF-007 (M1–M3); REL-003 +SAS-010.
Dependency changes: new; deps OPS-001, UX-001, INF-007, OPS-102; REL-003 +SAS-010. Step-level: S01 adds the chosen vendor to LCH-102's subprocessor register (no edge, so error monitoring is live during development, P1–P2).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-010-S01 | Record the backend decision per owner answer (§5 Q1): Sentry SaaS EU region (Frankfurt; US-parented → subprocessor and transfer assessment) or self-hosted GlitchTip (Sentry-SDK compatible, on ECS with its own database); SDK code identical either way. | `docs/decisions/error-monitoring.md` | Decision recorded; LCH-102 register updated if SaaS. | 2 |
| SAS-010-S02 | Integrate backend SDKs (FastAPI, workers, broker, extraction task, Dagster ops code) with a `before_send` scrubber reusing OPS-001 redaction processors and a context-key allowlist; no request bodies; user = pseudonymous subject hash; IP not stored. | `packages/telemetry/errors.py` | Planted exception in each service appears as an issue with trace_id tag. | 3 |
| SAS-010-S03 | Integrate the frontend SDK: error capture and web-vitals (LCP, INP, CLS) sampled at 10 %; no session replay; breadcrumbs limited to route ids; console capture off; CSP `connect-src` updated (UX-001-S14). | `apps/web/src/platform/telemetry.ts` | A thrown panel error is grouped with its release; CSP reports no violation. | 3 |
| SAS-010-S04 | Upload source maps privately at build (INF-007); never serve them publicly; release = short commit sha, environment tags. | CI step | Public fetch of `*.map` returns 404; issue stack shows original TypeScript lines. | 2 |
| SAS-010-S05 | Scrubbing tests: planted money values, SQL, e-mails, JWTs and tenant names in exception messages and context → 0 survive in stored events (checked through the tool's API). | `tests/spec/SAS-010/test_scrubbing.py` | 0 of 20 planted secrets retrievable. | 3 |
| SAS-010-S06 | Alert rules: new production issue after a release → non-paging Slack; spike (> 10 events in 5 min for one issue) → OPS-102 routing by severity; issue links to the trace (OPS-001). | alert config exported to repo | Fault injection raises both alerts in staging. | 2 |
| SAS-010-S07 | Real-user dashboards: p75 LCP/INP per route family against UX-001 budgets (LCP ≤ 2.5 s); alert when p75 breaches for 3 consecutive days. | dashboard | Throttled staging run shows values per route family. | 2 |
| SAS-010-S08 | Retention 30 days, EU residency, access restricted to the engineering SSO group. | config | Access review lists only the engineering group. | 1 |
| SAS-010-S09 | Evidence. | `docs/evidence/SAS-010/<commit>/` | – | 1 |

Task acceptance:
- [ ] Every production exception is grouped, source-mapped and linked to its trace and release; regressions alert.
- [ ] No money value, SQL, name or credential reaches the error store; data stays in the EU.

### SAS-011 — Help center, in-app support entry points and ticket SLA tooling
Release: R1 · Estimate: 19–28 h · Risk: M · Decisions: D-37, D-38 · Closes: G-SAS-11
Why / where: LCH-104-S04 sets up "helpdesk or shared inbox" (3 h) and UX-102-S06 a support form without a backend; missing: SLA timers on the D-37 calendar, tenant/request-id enrichment, one knowledge source, CSAT and the link to SAS-008. Plugs in after LCH-104 and UX-102; REL-003 +SAS-011.
Dependency changes: new; deps LCH-104, UX-102, SAS-008; REL-003 +SAS-011. Step-level: S05 publishes articles on SAS-002.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-011-S01 | Record the helpdesk decision per owner answer (§5 Q1): Crisp (French company, EU hosting) or self-hosted Zammad; criteria: EU data, SLA timers, API, agent SSO+MFA; subprocessor record. | `docs/decisions/helpdesk.md` | Decision and LCH-102 register entry recorded. | 2 |
| SAS-011-S02 | Configure SLA policies (SEV1 1 h first response in hours / best effort outside, SEV2 4 business hours, SEV3 next business day — LCH-104-S01) on a Mon–Fri 09:00–18:00 CET calendar with French public holidays; SEV1 escalates to OPS-102. | helpdesk config exported to `docs/support/helpdesk-config.md` | A SEV1 test ticket pages via OPS-102; timers pause outside hours for SEV2/3. | 2 |
| SAS-011-S03 | Implement `POST /v1/support/requests` behind UX-102-S06: forwards to the helpdesk API with tenant id, role, request ids, route id, app version and the diagnostics bundle (no values, no SQL); support@ e-mail remains a fallback. | `apps/api/support/` | Ticket fields populated; payload scan finds no money values or SQL. | 3 |
| SAS-011-S04 | Add in-app entry points (help menu: docs search, status, contact support, shortcuts); no third-party chat script inside the authenticated app (CSP and data exposure); a chat widget is allowed on the marketing site only. | `apps/web/src/platform/help-menu/` | CSP unchanged for the app; menu keyboard-accessible. | 2 |
| SAS-011-S05 | Keep one knowledge source: troubleshooting and FAQ articles on the docs site (SAS-002); helpdesk macros link to docs anchors. | docs section, macros | Each macro references an existing anchor (checked against `docs-links.yaml`). | 2 |
| SAS-011-S06 | Show the customer's tickets in the app (status, last update) for Owner/Admin through the helpdesk API. | `apps/web/src/pages/support/tickets` | Viewer cannot see tickets; Owner sees fixture tickets. | 3 |
| SAS-011-S07 | Send a one-question CSAT on resolution; store results for SAS-019. | helpdesk config | Survey received on a resolved test ticket. | 1 |
| SAS-011-S08 | Secure the helpdesk: agent SSO with MFA, attachment scanning, 24-month retention, OPS-104 inventory row. | config, inventory | Agent login without MFA fails. | 2 |
| SAS-011-S09 | Drill with LCH-104-S08 including the out-of-hours SEV1 best-effort path. | drill record | Response times within policy. | 1 |
| SAS-011-S10 | Evidence. | `docs/evidence/SAS-011/<commit>/` | – | 1 |

Task acceptance:
- [ ] Every ticket carries tenant and request context and an SLA timer on the published calendar.
- [ ] Customers reach docs, status and support from the app without any third-party script in the app.

### SAS-012 — Tenant-targeted release flags, beta programme and plan-gating UX
Release: R1 · Estimate: 19–28 h · Risk: M · Decisions: D-17, D-19 · Closes: G-SAS-12
Why / where: REL-102 provides server-side flags and kill switches, LCH-101 entitlements; progressive exposure per tenant (internal → canary → beta → all) is how continuous agent-built releases contain regressions, and gated features need one consistent UX. Plugs in after REL-102 and LCH-101.
Dependency changes: new; deps REL-102, LCH-101, UX-002, SEC-002, OPS-103.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-012-S01 | Extend `control.feature_flags` with `targeting` (all, tenant allowlist, percentage by `sha256(flag_key ‖ tenant_id)`, cohort internal/canary/beta) and `kind` (release, ops, entitlement-linked); audit every change. | migration | Changes without reason rejected (REL-102 rule kept). | 2 |
| SAS-012-S02 | Extend the evaluation library: deterministic tenant bucketing; precedence kill switch > entitlement > targeting; OpenFeature-compatible providers for Python and TypeScript. | `packages/flags/` | Same tenant gets the same bucket across processes and releases. | 3 |
| SAS-012-S03 | Deliver evaluated flags for the active tenant only in `GET /v1/auth/session`; bump the client epoch on change; never send rules to the browser. | session payload | Tenant A's session never contains tenant B's targeting data (test). | 2 |
| SAS-012-S04 | Beta programme: Owner setting "join beta features", cohort membership, beta badge and feedback link on beta features. | settings + component | Opted-in tenant sees the beta flag enabled; others do not. | 2 |
| SAS-012-S05 | Plan-gating component `<Entitled capability>` rendering a locked state with explanation and "contact us", fed by LCH-101 `entitlements.check()`; no dark patterns. | `apps/web/src/platform/entitled.tsx` | Locked state renders for a denied capability; API still returns 403 `ENTITLEMENT_LIMIT`. | 3 |
| SAS-012-S06 | Rollout playbook: internal → canary tenants (OPS-103) → beta → 10 % → 100 %, with OPS-003 SLO guard that recommends halting on burn. | `docs/releases/progressive-rollout.md` | Rehearsed on a staging flag with the halt path. | 2 |
| SAS-012-S07 | Tests: bucketing stability, flags never widen authorization (REL-102-S05 reused), cross-tenant leakage. | `tests/spec/SAS-012/` | All pass. | 2 |
| SAS-012-S08 | Stale-flag automation: open a removal PR for release flags at 100 % for > 30 days. | bot workflow | Fixture flag triggers a PR. | 2 |
| SAS-012-S09 | Evidence. | `docs/evidence/SAS-012/<commit>/` | – | 1 |

Task acceptance:
- [ ] Any release flag can be exposed progressively by tenant cohort and halted within REL-102's 60 s propagation.
- [ ] Gated capabilities render one explained locked state and are still enforced server-side.

### SAS-013 — My account: profile, sessions, notification preferences, personal-data export and account deletion
Release: R1 · Estimate: 18–26 h · Risk: M · Decisions: D-10, D-18 · Closes: G-SAS-13
Why / where: Bridge is controller for its own users' account data (GDPR Art. 15/17/20); OPS-005 covers tenants and Snowflake-user subjects, SEC-002 lists sessions; no profile page exists among the 87 screens and SAS-003/SAS-006 need a preference store. Plugs in after SEC-002 and OPS-005.
Dependency changes: new; deps SEC-002, SEC-004, SEC-008, OPS-005, OPS-104, SAS-006, UX-002.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-013-S01 | Author the screen contract for `/me` (profile, security, sessions, notifications, data) as screen 88 of the catalog. | `docs/21-ui-ux/pages/me.md` (new file in the next UX pass) | Reviewed by UX and SEC owners. | 1 |
| SAS-013-S02 | Profile: display name, locale (EN now, FR in R2), number/date display preference (financial dates stay UTC); e-mail changes only through the IdP or Cognito's verified flow. | `apps/web/src/pages/me/profile` | Changing locale updates formatting only, never UTC financial dates. | 2 |
| SAS-013-S03 | Security: MFA/passkey management (SEC-002), sessions list and revoke (existing API); SSO-managed accounts shown read-only. | page | Revoked session is refused on its next request. | 2 |
| SAS-013-S04 | Notification preferences UI over SAS-006 categories and GOV destinations the user subscribes to. | page | Opting out of LIFECYCLE stops the next nudge (test). | 2 |
| SAS-013-S05 | Personal data export (Art. 15/20): JSON of profile, memberships, preferences and own audit events (SEC-008 filter actor = self), delivered through the SEC-006-S08 broker. | `apps/api/me/export.py` | Export contains no other user's data (fixture with two users). | 3 |
| SAS-013-S06 | Account deletion: leave a tenant (refused for the last Owner); delete the Bridge account after a 7-day cancellable grace — memberships removed, Cognito user deleted, sessions revoked, audit actor references pseudonymized, `APP_USER` tombstone written to OPS-104. | `apps/api/me/delete.py`, OPS-104 change request | Last Owner deletion → 409 `LAST_OWNER`; deleted user cannot authenticate. | 4 |
| SAS-013-S07 | Tests including restore replay: a deleted user stays deleted after a PITR restore with tombstone replay (OPS-006 harness). | `tests/spec/SAS-013/` | All pass. | 3 |
| SAS-013-S08 | Evidence. | `docs/evidence/SAS-013/<commit>/` | – | 1 |

Task acceptance:
- [ ] Users manage their profile, sessions and preferences and can export or delete their own account without staff.
- [ ] Deletion survives restores and never deletes tenant financial data.

### SAS-014 — Sales demo workspace with refreshed synthetic data
Release: R1 · Estimate: 17–25 h · Risk: L · Decisions: D-17, D-35 · Closes: G-SAS-14
Why / where: D-17 routes evaluation through demos and a contracted pilot; demos from staging show test debris and depend on staging uptime; the website and docs need stable screenshots. FND-004 fixtures and `tenant.is_synthetic` exist. Plugs in after ingestion and serving are live in production (P5).
Dependency changes: new; deps FND-004, INF-101, CTL-102, SEC-004, OPS-103, REL-104 (dark production).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-014-S01 | Specify the demo tenant: 2 organizations, 6 accounts, 13 months of history, dbt and Power BI workloads, one RECONCILED closed month, open insights with one verified saving, budgets, monitors and incidents; anonymized names. | `docs/sales/demo-tenant.md` | Owner approval. | 2 |
| SAS-014-S02 | Feed it through the normal ingestion path from FND-004 generators as accepted batches (never direct table writes), 13 months backfilled. | `tools/demo/generate_batches.py` | Demo totals equal the generator's known answers per month. | 3 |
| SAS-014-S03 | Provision in production as `is_synthetic=true` tenant `demo` via CTL-102; exclude from LCH-105 metering, SLO denominators and SAS-009 analytics. | provisioning record | Metering job skips it; SLO queries filter it (tests). | 2 |
| SAS-014-S04 | Access: sales users as members; time-boxed prospect invitations (read-only persona, 14 days, MFA required). | invitation policy | Expired prospect access is refused. | 2 |
| SAS-014-S05 | Daily refresh with rolling dates so "last 30 days" is always populated; nightly reset of mutated configuration from a seed. | scheduled job | Two consecutive refreshes are idempotent; a changed budget is reset overnight. | 3 |
| SAS-014-S06 | Watermark "Demo data" in the shell, reports and exports (same mechanism as D-35 trial labelling). | UI + report header | Every export header carries the watermark. | 1 |
| SAS-014-S07 | Make it the screenshot source for SAS-001 and SAS-002. | screenshot job config | Screenshot job runs against the demo tenant. | 1 |
| SAS-014-S08 | Tests: LCH-002 M12 gate rejects the demo tenant; isolation probes include it; refresh idempotency. | `tests/spec/SAS-014/` | All pass. | 2 |
| SAS-014-S09 | Evidence. | `docs/evidence/SAS-014/<commit>/` | – | 1 |

Task acceptance:
- [ ] Prospects and sales use a production demo workspace with realistic, current, clearly labelled synthetic data.
- [ ] The demo tenant can never be billed, metered or counted in SLOs.

### SAS-015 — API reference portal and developer documentation
Release: R2 · Estimate: 22–32 h · Risk: L · Decisions: D-17 · Closes: G-SAS-15
Why / where: the public API ships with API-006 (R2); developers need a reference, guides and quickstarts generated from the released contract. Plugs in after API-006.
Dependency changes: new; deps API-006, SAS-002, SAS-003, SAS-014.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-015-S01 | Generate the reference from the released OpenAPI (API-006-S07) with a static renderer (Scalar or Redoc), one page per tag, examples mandatory. | `sites/docs/api/` | Every operation renders with an example; build fails on a missing example. | 3 |
| SAS-015-S02 | Write guides: client-credentials authentication, capabilities and scopes, sealed-cursor pagination, idempotency keys, rate limits and 429 handling, money as strings, publication pins and maturity fields, problem+json errors. | `docs/customer/api/*.md` | API owner review sign-off. | 4 |
| SAS-015-S03 | Write quickstarts (Python SDK from API-006-S08 and curl): "export last month's allocated cost", "list open incidents", "read budget status". | quickstart pages | Each quickstart runs green in CI against staging. | 3 |
| SAS-015-S04 | Publish the API changelog and deprecation schedule from SAS-003 entries tagged `api`. | docs page | API entries appear with sunset dates. | 2 |
| SAS-015-S05 | Provide a read-only sandbox against the demo tenant (SAS-014) with demo client credentials; "try it" disabled against customer tenants. | sandbox config | Demo credentials cannot read any non-demo tenant (test). | 3 |
| SAS-015-S06 | Version the portal per API major; run link checks and execute every code sample in CI. | CI jobs | A broken sample fails CI. | 3 |
| SAS-015-S07 | Generate and publish the Python SDK reference (pdoc). | `sites/docs/sdk/python/` | Reference matches the released SDK version. | 2 |
| SAS-015-S08 | Accessibility and search integration (Pagefind indexes API pages). | checks | Axe clean; search finds operation ids. | 1 |
| SAS-015-S09 | Evidence. | `docs/evidence/SAS-015/<commit>/` | – | 1 |

Task acceptance:
- [ ] The reference, guides and quickstarts are generated from and tested against the released API.
- [ ] Sandbox access is limited to the demo tenant.

### SAS-016 — Terraform provider for configuration as code
Release: R2 · Estimate: 46–67 h · Risk: M · Decisions: D-17 · Closes: G-SAS-16
Why / where: Vantage ships a Terraform provider for reports, dashboards, teams and notifications [V2]; CloudZero manages allocation rules as code [Z1]; PRD §145 names "future Terraform". Platform teams manage budgets, monitors, destinations and ownership rules through reviewed code. Plugs in after API-006.
Dependency changes: new; deps API-006, SAS-015, ALC-003, GOV-001, GOV-003, GOV-006, RPT-004, CTL-007, PRO-003.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-016-S01 | Define the resource model: `bridge_budget`, `bridge_monitor`, `bridge_destination` (secrets write-only), `bridge_usage_group_set`, `bridge_usage_group`, `bridge_tag_rule` (draft only — publication stays a maker-checker action in the app, ALC-003), `bridge_report_schedule`, `bridge_digest`, `bridge_saved_view`; data sources `bridge_accounts`, `bridge_metrics`. | `terraform-provider-bridge/DESIGN.md` | Reviewed with ALC, GOV and API owners. | 3 |
| SAS-016-S02 | Close API gaps: every resource has create/read/update/delete with If-Match revisions, stable ids and lookup by `external_id`. | API change PRs | Contract tests cover CRUD for each resource. | 4 |
| SAS-016-S03 | Scaffold the Go provider on terraform-plugin-framework; authenticate with API-006 client credentials; honour Retry-After. | `terraform-provider-bridge/` | `terraform plan` against staging succeeds. | 4 |
| SAS-016-S04 | Implement `bridge_budget` and `bridge_monitor`. | resources | Acceptance tests create, update and destroy both. | 4 |
| SAS-016-S05 | Implement `bridge_destination` with write-only secrets (sensitive, never read back). | resource | State file contains no secret (scan). | 3 |
| SAS-016-S06 | Implement `bridge_usage_group_set` and `bridge_usage_group`. | resources | Acceptance tests pass. | 4 |
| SAS-016-S07 | Implement `bridge_tag_rule` as drafts with simulation status read back. | resource | Applying never publishes a ruleset. | 4 |
| SAS-016-S08 | Implement `bridge_report_schedule`, `bridge_digest` and `bridge_saved_view`. | resources | Acceptance tests pass. | 3 |
| SAS-016-S09 | Support `terraform import` and drift detection from server revisions. | import functions | A UI edit shows as drift on the next plan. | 3 |
| SAS-016-S10 | Run acceptance tests (TF_ACC) against the staging demo tenant in CI. | CI job | Suite green. | 4 |
| SAS-016-S11 | Write registry-format docs and examples. | `docs/` in provider repo | Registry docs preview renders. | 3 |
| SAS-016-S12 | Release with GoReleaser (GPG-signed) to the Terraform and OpenTofu registries. | release workflow | Provider installable from both registries. | 3 |
| SAS-016-S13 | Security: no secret or token in logs, sensitive attributes marked, minimal client capabilities documented. | review record | Log scan finds no token. | 2 |
| SAS-016-S14 | Versioning policy tying provider majors to API majors. | `VERSIONING.md` | Reviewed. | 1 |
| SAS-016-S15 | Evidence. | `docs/evidence/SAS-016/<commit>/` | – | 1 |

Task acceptance:
- [ ] Budgets, monitors, destinations, usage groups, rule drafts, schedules, digests and saved views are manageable as code with import and drift detection.
- [ ] Terraform can never publish an allocation ruleset or expose a destination secret.

### SAS-017 — Enterprise admin controls: audit-log SIEM streaming, IP allowlist and session-policy UI
Release: R2 · Estimate: 24–35 h · Risk: M · Decisions: D-25 · Closes: G-SAS-17
Why / where: enterprise security teams pipe SaaS audit logs into their SIEM and ask for network restrictions [T1]; SEC-008 provides the signed export chain, SEC Appendix D the session model. Plugs in after SEC-008 and UX-102.
Dependency changes: new; deps SEC-008, SEC-002, SEC-003, UX-102, GOV-006, GOV-102, INF-006.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-017-S01 | Design SIEM destinations: HTTPS (Standard Webhooks-signed JSONL batches), Splunk HEC, Datadog logs intake (EU site), customer S3 bucket via cross-account role with ExternalId; payload = SEC-008 `event.v1` with an OCSF mapping document. | `docs/security/siem-streaming.md` | Reviewed by the security owner. | 3 |
| SAS-017-S02 | Build the streaming worker from the SEC-008 export ledger: at-least-once per destination cursor, backoff, DLQ, destination health visible to tenant admins. | `services/audit_stream/` | Killing the worker mid-batch resumes without gaps (sequence check). | 4 |
| SAS-017-S03 | Implement HEC and Datadog adapters through the GOV-102 egress proxy with the GOV-006-S09 SSRF guard. | adapters | SSRF suite passes for the new adapters. | 3 |
| SAS-017-S04 | Implement the S3 destination with `sts:AssumeRole` + per-tenant ExternalId and a customer role template. | adapter + template | Wrong ExternalId is refused; objects land with SSE. | 3 |
| SAS-017-S05 | Implement the per-tenant IP allowlist (≤ 50 CIDRs) enforced in the BFF from CloudFront's viewer-address header (trusted only from the CloudFront origin), applied to UI sessions and API clients; audited; lock-out prevention requires confirming the current IP. | `apps/api/security/ip_allowlist.py` | A spoofed `X-Forwarded-For` is ignored; saving a list excluding the caller requires explicit confirmation. | 4 |
| SAS-017-S06 | Surface session policy in UX-102's security page: idle/absolute timeouts within SEC Appendix D bounds, MFA enforcement for native users, SSO enforcement toggle (SEC-003). | UI | Out-of-bounds values rejected client- and server-side. | 2 |
| SAS-017-S07 | Tests: streaming sequence continuity, allowlist enforcement for UI and API, policy bounds. | `tests/spec/SAS-017/` | All pass. | 3 |
| SAS-017-S08 | Docs and evidence. | SAS-002 pages, `docs/evidence/SAS-017/<commit>/` | – | 2 |

Task acceptance:
- [ ] Tenant audit events stream to the customer's SIEM without gaps and with verifiable signatures.
- [ ] IP allowlists apply to UI and API and cannot be bypassed with forwarded headers.

### SAS-018 — In-app notification center
Release: R2 · Estimate: 18–26 h · Risk: M · Decisions: D-18 · Closes: G-SAS-18
Why / where: a persistent per-user inbox for incidents assigned, exports and reports ready, jobs done, support-access requests and announcements; UX-104-S06 has only transient toasts. Plugs in after GOV-007 and SAS-006.
Dependency changes: new; deps GOV-007, UX-104, SAS-006, SAS-013.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-018-S01 | Create `notify.inbox_items` (tenant, user, kind, ref, created_at, read_at, expires_at = +90 d) with FORCE RLS; list producers (incident assigned, report/export ready, job done, support-access request, connection failure, announcement). | migration, producer list | RLS test: foreign tenant reads 0 rows. | 3 |
| SAS-018-S02 | Fan out from GOV-007 and SAS-006 events; reauthorize at read time (scope may have changed since creation). | fan-out worker | Item for a resource outside the reader's current scope is hidden. | 3 |
| SAS-018-S03 | API: list (keyset), mark read, mark all read, unread count cached per user. | `apps/api/inbox/` | Concurrent mark-all is idempotent. | 2 |
| SAS-018-S04 | UI: bell with count, panel grouped by day, deep links; reuse UX-104-S06 toasts. | `apps/web/src/platform/inbox/` | Keyboard-operable; live region announces new items. | 3 |
| SAS-018-S05 | Preferences per category: in-app, e-mail or both (SAS-013). | preference fields | Disabled category produces no inbox item. | 2 |
| SAS-018-S06 | Record the transport decision (polling with backoff vs server-sent events). | decision note | Reviewed. | 1 |
| SAS-018-S07 | Tests: revoked scope hides items, tenant switch shows only the active tenant, accessibility. | `tests/spec/SAS-018/` | All pass. | 3 |
| SAS-018-S08 | Evidence. | `docs/evidence/SAS-018/<commit>/` | – | 1 |

Task acceptance:
- [ ] Users find every notification relevant to them in one place, filtered by their current scope and tenant.

### SAS-019 — Customer health scoring, value reports and renewal tooling
Release: R2 · Estimate: 19–28 h · Risk: M · Decisions: D-17 · Closes: G-SAS-19
Why / where: renewal risk and demonstrated ROI protect revenue; the inputs exist after SAS-008, SAS-009, SAS-011 and INS-007. Plugs in after one quarter of R1 operation.
Dependency changes: new; deps SAS-008, SAS-009, SAS-011, INS-007, LCH-001, LCH-105, RPT-003, PRO-004.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-019-S01 | Define health score v1: explainable weighted components (data freshness, reconciliation status, weekly active users, practice-checklist completion, open SEV tickets, verified-savings trend, subscription state), each 0–100 with thresholds; version stored with every score. | `docs/operations/health-score-v1.md` | Reviewed by owner. | 3 |
| SAS-019-S02 | Compute daily in `INTERNAL_PRODUCT` with history and component drivers. | model | Fixture tenants reproduce hand-computed scores. | 3 |
| SAS-019-S03 | Show score, trend and top risk drivers in SAS-008; alert customer success on a drop > 20 points in a week. | console panel, alert | Fixture drop raises the alert. | 2 |
| SAS-019-S04 | Build the quarterly customer value report as an RPT template: verified savings only (INS-007), spend under management, allocation-coverage change (PRO-004), incidents caught. | `templates/value_review/` | Golden PDF passes; no potential savings in totals. | 4 |
| SAS-019-S05 | Renewal calendar from LCH-001 term dates: 90/60/30-day tasks for `finance_operator`; band trend from LCH-105. | ops tasks | Fixture subscription creates the three tasks. | 2 |
| SAS-019-S06 | Privacy review: only pseudonymous product events; no customer analytics values in the score. | review note | Signed. | 1 |
| SAS-019-S07 | Tests: determinism, value report excludes unverified savings, role access. | `tests/spec/SAS-019/` | All pass. | 3 |
| SAS-019-S08 | Evidence. | `docs/evidence/SAS-019/<commit>/` | – | 1 |

Task acceptance:
- [ ] At-risk customers are visible with explainable drivers before renewal.
- [ ] Value reports quote only verified savings.

### SAS-020 — Contractual SLA and service credits
Release: R2 · Estimate: 17–25 h · Risk: M · Decisions: D-30, D-31, D-37 · Closes: G-SAS-20
Why / where: enterprise MSAs ask for credits; R1 publishes objectives only (LCH-104-S02). Offer credits after at least three months of measured SLIs. Plugs in after OPS-003 and SAS-005.
Dependency changes: new; deps OPS-003, LCH-104, LCH-001, SAS-005.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-020-S01 | Draft the SLA schedule for counsel: covered services (control plane 99.9 %, analytics 99.5 % monthly — D-31), exclusions (customer Snowflake unavailability or network policy, announced maintenance), measurement by synthetic probes and API success ratio, claim process, credit tiers as % of the monthly platform fee. | `docs/legal/sla-schedule-draft.md` | Counsel review requested; owner approves tiers. | 3 |
| SAS-020-S02 | Compute per-tenant monthly availability from OPS-003 SLIs (tenant-scoped probes + API success ratio), stored immutably per month. | `services/slo/tenant_sla.py` | Fixture month reproduces hand-computed availability. | 4 |
| SAS-020-S03 | Publish the monthly SLA report per tenant (Owner-visible) and on request. | report + page | Owner sees the month; viewer does not. | 2 |
| SAS-020-S04 | Compute credits and create a finance-operator task to issue a credit note (manual invoicing, D-30; LCH-001 credit-note flow). | job | Fixture breach creates one task with the computed amount. | 2 |
| SAS-020-S05 | Check consistency between status-page incident history (SAS-005) and computed SLIs; differences reviewed monthly. | reconciliation job | Injected mismatch is reported. | 2 |
| SAS-020-S06 | Tests: maintenance exclusion, partial month, boundary at exactly 99.9 %. | `tests/spec/SAS-020/` | All pass. | 2 |
| SAS-020-S07 | Runbook for claims. | `docs/runbooks/sla-claims.md` | Reviewed. | 1 |
| SAS-020-S08 | Evidence. | `docs/evidence/SAS-020/<commit>/` | – | 1 |

Task acceptance:
- [ ] Credits derive from measured per-tenant SLIs with documented exclusions and flow into the manual credit-note process.

### SAS-021 — French localization (UI, e-mail, notifications, reports, key docs)
Release: R2 · Estimate: 24–35 h (+ translation cost) · Risk: M · Decisions: D-18 · Closes: G-SAS-21
Why / where: RELEASE_PLAN §2 lists "FR localization (D-18)" for R2 but no task owns it; UX-001 externalizes strings from day one. Plugs in after UX-001, SAS-006 and RPT-003.
Dependency changes: new; deps UX-001, SAS-006, GOV-007, RPT-003, SAS-001, SAS-002, SAS-013.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| SAS-021-S01 | Build the EN↔FR terminology glossary for FinOps and product terms (e.g., managed spend, chargeback, PROVISIONAL, reconciliation) approved by the owner. | `docs/i18n/glossary-fr.md` | Owner approval recorded. | 2 |
| SAS-021-S02 | Set up the translation workflow (file-based review in PRs or self-hosted Weblate); no unreviewed machine translation of financial terms. | `docs/i18n/workflow.md` | First batch reviewed through the workflow. | 2 |
| SAS-021-S03 | Integrate the FR UI catalogue with ICU plural/select checks and missing-key detection. | `apps/web/src/i18n/fr.json`, CI | Missing key fails CI; pseudo-locale still passes. | 4 |
| SAS-021-S04 | Localize server-side messages: problem types, notification templates (GOV-007-S08), e-mail templates (SAS-006), Cognito messages. | catalogues | Snapshot tests per locale pass. | 3 |
| SAS-021-S05 | Localize the four R1 report templates (RPT-003) with locale formatting (money keeps its currency code; UTC labels unchanged). | report templates | Golden FR PDFs pass. | 4 |
| SAS-021-S06 | Locale resolution: user preference (SAS-013) → tenant default → Accept-Language; report recipients' locale. | resolver | Table-driven tests pass. | 2 |
| SAS-021-S07 | Translate marketing site and the ten most-read docs pages (SAS-009 data). | site and docs pages | Link check and axe pass in FR. | 3 |
| SAS-021-S08 | Visual regression in fr-FR for text expansion (~20 %) at 390 px and 1280 px. | Playwright job | No clipped primary action. | 3 |
| SAS-021-S09 | Evidence. | `docs/evidence/SAS-021/<commit>/` | – | 1 |

Task acceptance:
- [ ] French users get the UI, e-mails, notifications and R1 reports in French with approved financial terminology.
- [ ] Missing translations fail CI; UTC financial labels and currency codes are unchanged by locale.

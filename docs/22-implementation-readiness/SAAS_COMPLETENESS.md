# SaaS completeness review: Bridge vs recognized Snowflake FinOps platforms

Review date: 2026-09-28 UTC. Scope: the R1/R2 plan as of the owner's decision record ([DECISIONS_REQUIRED.md](DECISIONS_REQUIRED.md), D-01…D-38), the [release plan](RELEASE_PLAN.md), the 249-entry [revised task graph](revised-task-graph.json), every [backlog](backlog/) file (§4/§5 task headers and the tasks that touch the areas below), the [screen catalog](../21-ui-ux/SCREEN_INDEX.md) and the [product contract](../10-frontend/product.md). Question: does the plan describe "a SaaS worthy of the name, like select.dev or other recognized platforms", production-grade and buildable by coding agents? Production implementation remains **NOT_STARTED**; this document proposes additions only and does not amend any existing file.

Prefixes: **SAS-xxx** = platform and SaaS surfaces; **PRO-xxx** = missing product features (PRD is reserved for the product requirements document). Findings are **G-SAS-xx** / **G-PRO-xx**.

## 0. Verdict

**The analytical core is ahead of the market; the SaaS around it is not yet planned.** The plan is deeper than any peer on the things peers do not do at all — an exact, signed, reconciled ledger with maturity, close and restatement, maker-checker chargeback statements, identity-enforced tenant isolation and pseudonymized user data. But a buyer who compares Bridge with select.dev, Snowflake's own Cost Management UI or Vantage during a pilot will find two classes of gaps:

1. **Product parity gaps that every recognized peer (and now Snowflake itself) ships** and that enterprise FinOps buyers test in the first week: capacity-contract burn-down and renewal forecast (Snowflake's free Organization Overview has it; the plan extracts neither `REMAINING_BALANCE_DAILY` nor `CONTRACT_ITEMS`), a deterministic "why did this change?" explanation that alerts and incidents can quote (PRD §96 requires it; GOV-007-S07 consumes "top contributors" that no task computes), inline scheduled spend digests per owner, attribution-coverage and query-tagging guidance, performance guardrails on "verified" savings, and a standard (FOCUS 1.3) bulk export of the allocated ledger.
2. **SaaS surfaces with no owning task**: marketing site and pricing page (with the French *mentions légales* the French entity must publish), public docs site (ONB-002 writes guides into the repository but nothing publishes them), changelog, trust center, status automation, transactional and lifecycle e-mail, in-app getting-started guidance, a customer-360 back-office view, first-party product analytics, error monitoring, help-center tooling, tenant-targeted release flags, a "My account" page and a demo workspace for a product that has no free trial (D-17).

**Two findings are hard defects, not polish:**

- **G-SAS-06 · Cognito e-mail limit.** No task sets the Cognito user pool's `EmailSendingAccount` to `DEVELOPER` (SES). With the default sender, Cognito sends at most 50 e-mails per day per user pool and honours custom e-mail message parameters only with `DEVELOPER` (VERIFIED, [AWS Cognito e-mail settings](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-email.html)); native-user verification and password-reset e-mails would be throttled by the first burst of invitations, resets or demo accounts, unbranded and not localizable (D-18). Fixed by SAS-006-S02.
- **G-PRO-07 · Irreversible BI attribution loss.** WRK-101's allowlist v1 is frozen before the first backfill and query text is never persisted (G-WRK-01). Tableau writes workbook/dashboard LUIDs into `QUERY_TAG` by default for Snowflake connections (VERIFIED, [Tableau query tagging](https://help.tableau.com/current/api/rest_api/en-us/REST/rest_api_how_to_query_tagging.htm)) and Sigma adds query comments automatically (VERIFIED snippet, [select.dev Sigma changelog](https://select.dev/changelog/2025-01-28-sigma-integration)). If those keys are not in allowlist v1, 365 days of BI-tool attribution are lost even though the BI feature itself is R2. Fixed by PRO-007-S01/S02, tagged R1 inside an R2 task.

Effort (senior-engineer-equivalent hours, same convention as the backlog files: low = Σ micro-step hours, high ≈ 1.45 × low):

| Release | New tasks | Hours | Effect on plan totals |
|---|---:|---:|---|
| R1 | 20 (SAS-001…014, PRO-001…006) + R1 part of PRO-007 | **524–761** | 7,116–10,488 → 7,640–11,249 (+7.4 %) |
| R2 | 14 (SAS-015…021, PRO-007 remainder, PRO-008…013) | **376–546** | 614–948 → 990–1,494 |

None of the new R1 tasks lengthens the critical chain to the first payment (still 1,362–2,006 h, recomputed with every proposed edge — §4.2); they add review load, mostly in lanes A1, D, E and G.

## 1. Method, evidence and limits

- **Repository inputs** were read in full for the decision record, release plan, screen index and product contract; the backlog files were read at task-header level and in full for every task that overlaps an area reviewed here (LCH-001…105, OPS-001/005/009/101…111, UX-001/101…104, SEC-008/104/106, API-006, ONB-001/002/102, CTL-102, REL-102, GOV-001/002/005/006/007/008, INS-006/007, WRK-002/003/101, FIN G-FIN-09 and the funding-class contract). Every task ID cited below was checked against [revised-task-graph.json](revised-task-graph.json).
- **Competitor evidence**: `select.dev` pages could not be fetched (egress proxy blocks the domain); select.dev claims are therefore **VERIFIED (snippet)** — from search-result snippets of the cited select.dev URLs on 2026-09-28 — or **UNVERIFIED** when only a page title or a third-party summary was available. GitHub was fetched directly. Vendor marketing claims (savings percentages) are reported as claims, not facts.
- **Not verified live**: nothing in this document was tested against a live Snowflake, AWS or vendor account. Snowflake view columns and privileges that matter for new tasks are marked **TO VERIFY LIVE** and have an explicit probe step.
- Legal statements (LCEN, CNIL, EAA, GDPR bases) are prompts for counsel (as in [README.md](README.md) "Method and limits"), not advice.

### 1.1 Evidence register

| ID | Source | What it supports | Status |
|---|---|---|---|
| S1 | [select.dev — Usage Groups docs](https://select.dev/docs/usage-groups) | Allocation to teams/projects by user, role, tags, database, workload; operators in/includes/starts-with | VERIFIED (snippet) |
| S2 | [select.dev — Announcing Budgets](https://select.dev/changelog/2024-04-16-announcing-budgets) | Monthly/yearly budgets per usage group with forecast to exceed | VERIFIED (snippet) |
| S3 | [select.dev — Free trial guide](https://select.dev/docs/reference/usage-guide/select-free-trial-guide), [SELECT vs Snowflake](https://select.dev/docs/resources/comparisons/select-vs-snowflake) | Monitors: recurring spend digests per usage group, anomaly alerts, Slack/Teams/e-mail; free trial exists | VERIFIED (snippet) |
| S4 | [select.dev — Monitor Snowflake contract capacity](https://select.dev/changelog/2023-08-02-contract-overview) | Contract overview: capacity, expiry, used vs forecast (linear regression, adjustable window), early-renewal savings; uses `REMAINING_BALANCE_DAILY` + `CONTRACT_ITEMS` | VERIFIED (snippet) |
| S5 | [select.dev — Automated Savings](https://select.dev/features/automated-savings) | Automated warehouse-setting changes, per-warehouse toggle, 8-day calibration before/after; claims 10–20 % | VERIFIED (snippet) |
| S6 | [select.dev — Tracking actions and savings](https://select.dev/changelog/actions-track-realized-savings) | Actions with realized savings | VERIFIED (title/snippet) |
| S7 | [select.dev — Insight management (2026-04-07)](https://select.dev/changelog/2026-04-07-insight-management), [Insights docs](https://select.dev/docs/reference/using-select/insights) | Insights with savings potential, effort, status; group/sort/filter | VERIFIED (snippet) |
| S8 | [select.dev — Sigma](https://select.dev/changelog/2025-01-28-sigma-integration), [Looker explores](https://select.dev/changelog/2023-07-14-cost-per-looker-explore), [Looker enhancements](https://select.dev/changelog/2024-04-22-looker-integration-enhancements), [Tableau beta](https://select.dev/changelog/tableau-integration-in-beta) | Cost per Sigma workbook/dashboard (from query comments, no setup), Looker dashboards/looks/explores, Tableau workbooks | VERIFIED (snippet) |
| S9 | [get-select/dbt-snowflake-monitoring](https://github.com/get-select/dbt-snowflake-monitoring), [get-select/dbt-snowflake-query-tags](https://github.com/get-select/dbt-snowflake-query-tags), [Custom Workloads docs](https://select.dev/docs/custom-workloads) | dbt query tagging package (now deprecated in favour of a multi-platform one), custom workloads from query tags/comments | FETCHED (GitHub) / VERIFIED (snippet) |
| S10 | [select.dev — Going headless](https://select.dev/changelog/select-is-going-headless) | API v2 = the app's own API (connections, budgets, insights), cursor pagination, v1 deprecation | VERIFIED (snippet) |
| S11 | [select.dev — Copilot MCP](https://select.dev/changelog/copilot-mcp-server), [Copilot in Slack](https://select.dev/changelog/copilot-in-slack), [AI Copilot](https://select.dev/changelog/ai-copilot) | Read-only Copilot in app, Slack and MCP; drills anomalies to root cause | VERIFIED (snippet) |
| S12 | [select.dev — Audit logs](https://select.dev/changelog/view-your-select-audit-logs), [changelog index](https://select.dev/changelog) | Audit logs in Settings (2026-07-23); direct Okta/Entra/SAML sign-in configuration (2026-04-14); SPCS spend (2026-04-16); pipeline analysis (2026-05-25) | VERIFIED (snippet) |
| S13 | [select.dev — SOC 2 Type 2](https://select.dev/posts/soc2), [security](https://select.dev/security) | SOC 2 Type II; report on request; read-only metadata access | VERIFIED (snippet) |
| S14 | [select.dev — Self-serve Stripe billing](https://select.dev/changelog/self-serve-billing-in-select), [Status alerts and product updates in the app](https://select.dev/changelog/status-alerts-and-product-updates-in-the-app) | Billing tab (invoices, card, address via Stripe); in-app status alerts/product updates | VERIFIED (snippet) / UNVERIFIED (content of the second) |
| S15 | [select.dev — Export data](https://select.dev/changelog/2024-02-12-export-data), [Connect Snowflake](https://select.dev/docs/snowflake-metadata-access) | CSV/clipboard export of any chart/table; metadata exported to a GCS bucket rather than data sharing | VERIFIED (snippet) |
| S16 | [cubeapm review of select.dev pricing](https://cubeapm.com/blog/select-dev-pricing-and-review/) | Pricing from USD 1,499/month; "can be paid with existing Snowflake credits" | UNVERIFIED (third party) |
| N1 | [Snowflake — Budgets](https://docs.snowflake.com/en/user-guide/budgets), [custom budgets](https://docs.snowflake.com/en/user-guide/budgets/custom-budget), [notifications](https://docs.snowflake.com/en/user-guide/budgets/notifications), [AI FinOps blog](https://www.snowflake.com/en/blog/ai-finops-cost-management-governance-snowflake/) | Account and custom (incl. tag-based) monthly budgets; projected-overrun notifications to e-mail, SNS/Event Grid/PubSub, webhooks (Slack, Teams, PagerDuty) | VERIFIED (snippet) |
| N2 | [Snowflake — Cost anomalies](https://docs.snowflake.com/en/user-guide/cost-anomalies), [Snowsight UI](https://docs.snowflake.com/en/user-guide/cost-anomalies-ui) | Account/org-level daily anomaly detection, ≥ 30 days history | VERIFIED (snippet) |
| N3 | [Snowflake — Exploring overall cost](https://docs.snowflake.com/en/user-guide/cost-exploring-overall), [Cost Management interface](https://www.snowflake.com/en/blog/optimize-spend-new-cost-management-interface/) | Account overview, top warehouses/queries, recommendations; Organization Overview with remaining balance, contract consumption vs forecast | VERIFIED (snippet) |
| N4 | [REMAINING_BALANCE_DAILY](https://docs.snowflake.com/en/sql-reference/organization-usage/remaining_balance_daily), [CONTRACT_ITEMS](https://docs.snowflake.com/en/sql-reference/organization-usage/contract_items), [SNOWFLAKE database roles](https://docs.snowflake.com/en/sql-reference/snowflake-db-roles) | Capacity/rollover/free/on-demand balances (latency ≤ 72 h); contract items (not for reseller contracts; only the primary organization of a shared contract); ORGANIZATION_BILLING_VIEWER | VERIFIED (snippet); exact columns TO VERIFY LIVE |
| N5 | [FOCUS_COST_USAGE_V1_3](https://docs.snowflake.com/en/sql-reference/billing/focus_cost_usage_v1_3), [FOCUS spec](https://focus.finops.org/focus-specification/) | Snowflake publishes FOCUS 1.3 billing data for org-enabled accounts; FOCUS 1.3 ratified Dec 2025 | VERIFIED (snippet) |
| N6 | [Marketplace Capacity Drawdown](https://docs.snowflake.com/en/collaboration/marketplace-capacity-drawdown), [MCD program](https://www.snowflake.com/en/product/features/marketplace/marketplace-capacity-drawdown-program/) | Paying Marketplace listings from capacity; GA for US consumers buying from US providers, private preview UK/CH/MX; eligible types: data shares, Native Apps, Connected Apps | VERIFIED (snippet) |
| V1 | [Vantage — Unit costs](https://docs.vantage.sh/per_unit_costs), [best tools 2026 (Vantage blog)](https://www.vantage.sh/blog/best-cloud-cost-management-tools-2026) | Business-metric unit costs; virtual tagging; hierarchical budgets; Snowflake among 30+ integrations; MCP support | VERIFIED (snippet, vendor blog) |
| V2 | [Vantage — Terraform provider](https://docs.vantage.sh/terraform), [registry](https://registry.terraform.io/providers/vantage-sh/vantage/latest/docs/resources/cost_report) | Cost reports, folders, saved filters, dashboards, teams, access grants, report notifications as code | VERIFIED (snippet) |
| V3 | [Vantage — Report notifications](https://docs.vantage.sh/report_notifications), [anomaly alerts](https://www.vantage.sh/blog/vantage-launches-cost-anomaly-alerts), [FinOps agent](https://www.vantage.sh/blog/finops-ai-agent) | Daily/weekly/monthly digests to e-mail/Slack/Teams; anomaly alerts; AI agent | VERIFIED (snippet) |
| V4 | [Vantage — Security](https://www.vantage.sh/legal/security), [SSO docs](https://docs.vantage.sh/sso) | SOC 1/SOC 2 Type 2; self-service SAML SSO; SCIM not found | VERIFIED (snippet) / SCIM UNVERIFIED |
| C1 | [Slingshot product](https://www.capitalone.com/software/products/slingshot/), [warehouse scheduling](https://www.capitalone.com/software/blog/capital-one-slingshot-snowflake-warehouse-scheduling-provisioning/), [recommendations](https://www.capitalone.com/software/blog/confidently-apply-slingshot-warehouse-recommendations/), [QAS + recommendations hub](https://www.capitalone.com/software/blog/slingshot-new-features-qas-new-recommendations-home-page/) | Warehouse size/cluster/auto-suspend schedules, recommendations from query load, queueing and spill, value report of savings, fine-grained RBAC, warehouse templates, approval workflows | VERIFIED (snippet) |
| K1 | [Keebo](https://keebo.ai/), [query routing](https://keebo.ai/query-routing/) | Autonomous warehouse rightsizing/auto-suspend; smart query routing | VERIFIED (snippet; savings are claims) |
| E1 | [Espresso AI — how it works](https://espresso.ai/how-it-works) | Autoscaling and scheduling agents, SQL optimization; paid on realized savings | VERIFIED (snippet) |
| D1 | [Sundeck OpsCenter quickstart](https://quickstarts.snowflake.com/guide/sundeck_opscenter/index.html), [The New Stack](https://thenewstack.io/sundeck-launches-query-engineering-platform-for-snowflake/) | Query hooks (route/rewrite/reject); OpsCenter as a free Snowflake Native App (workload labelling, forecasting, alerting) | VERIFIED (snippet) |
| Z1 | [CloudZero Snowflake](https://www.cloudzero.com/integration/snowflake/), [Dimensions](https://www.cloudzero.com/platform/dimensions/) | 100 % allocation without tags, cost per customer/product/feature, CostFormation rules as code, anomaly routing to owners | VERIFIED (snippet) |
| F1 | [Finout Snowflake](https://www.finout.io/finout-snowflake-solution), [anomalies](https://docs.finout.io/user-guide/optimize/anomalies) | MegaBill, virtual tags, anomalies by warehouse/account/database, unit economics | VERIFIED (snippet) |
| R1x | [Revefi Snowflake](https://www.revefi.com/solutions/snowflake), [RADEN on Marketplace](https://www.revefi.com/press-releases/revefi-launches-raden-ai-agent-on-snowflake-marketplace) | AI agent for spend, performance and data quality; Marketplace listing | VERIFIED (snippet) |
| G1 | [Chaos Genius (now Flexera)](https://chaosgenius.io/cost-allocation-and-visibility.html), [docs](https://documentation.chaosgenius.io/) | Cost across all services, warehouse right-sizing and query recommendations, e-mail/Slack reports and alerts | VERIFIED (snippet) |
| B1 | [Bluesky Snowflake](https://www.getbluesky.io/snowflake), [Copilot for Snowflake](https://finance.yahoo.com/news/bluesky-releases-bluesky-copilot-snowflake-160000501.html) | Query-pattern analysis, workload automation, budgeting/forecasting, anomaly detection | VERIFIED (snippet) |
| U1 | [Unravel for Snowflake](https://www.unraveldata.com/solutions/technologies/snowflake/), [agents](https://www.unraveldata.com/solutions/technologies/snowflake-agents/) | AI agents (FinOps, DataOps), chargeback by department/warehouse/user, forecasting, guardrails | VERIFIED (snippet) |
| T1 | [EnterpriseReady](https://www.enterpriseready.io/), [audit log guide](https://www.enterpriseready.io/features/audit-log/), [WorkOS 2026 checklist](https://workos.com/blog/enterprise-readiness-checklist-2026) | SSO, SCIM, RBAC, audit log with export/SIEM, trust page, SOC 2, DPA, SLA, change management | VERIFIED (snippet) |
| L1 | [francenum.gouv.fr — mentions légales](https://www.francenum.gouv.fr/guides-et-conseils/developpement-commercial/site-web/quelles-sont-les-mentions-legales-pour-un-site), [CNIL audience measurement](https://www.cnil.fr/fr/cookies-et-autres-traceurs/regles/cookies-solutions-pour-les-outils-de-mesure-daudience), [EAA and B2B software](https://karlgroves.com/the-european-accessibility-act-and-b2b-software-what-internal-platforms-must-comply-with/) | LCEN legal notices on French company websites; consent exemption for strictly anonymous first-party audience measurement; EAA scope (consumer-facing; micro-enterprise exemption for services) | VERIFIED (snippet); counsel to confirm |
| X1 | [Sentry data storage location](https://docs.sentry.io/organization/data-storage-location/), [PostHog Cloud EU](https://posthog.com/blog/posthog-cloud-eu), [Crisp GDPR status](https://help.crisp.chat/en/article/crisp-eu-gdpr-compliance-status-nhv54c/), [Better Stack (EuropeanStack)](https://europeanstack.com/software/better-stack) | EU data residency options: Sentry EU (Frankfurt), PostHog EU (Frankfurt), Crisp (French, EU hosting), Better Stack (Czech, EU data) | VERIFIED (snippet) |
| X2 | [Looker context comments](https://docs.cloud.google.com/looker/docs/admin-panel-database-queries) | Looker prepends `-- Looker Query Context '{"user_id":…,"history_slug":…,"instance_slug":…}'` | VERIFIED (snippet) |

### 1.2 Feature matrix — product capabilities

Legend: **Yes** = evidence found; **Partial** = narrower than the row; **No** = not offered per evidence; **UNVERIFIED** = not confirmed; **—** = not applicable. Bridge columns cite the owning tasks; **Gap →** points to the new task in §3.

| Capability | select.dev | Snowflake native | Vantage | Slingshot | Bridge R1 (plan) | Bridge R2 (plan) |
|---|---|---|---|---|---|---|
| Spend across every Snowflake service (compute, storage, serverless, transfer, AI/Cortex, SPCS) | Yes [S12, S15] | Yes [N3] | Yes (Snowflake integration; depth UNVERIFIED) [V1] | Partial (warehouse focus) [C1] | Yes — FIN-001…021, UX-004…007 (D-20) | — |
| Cost per query, idle attribution | Yes (cost-per-query algorithm) [S3] | Partial (QUERY_ATTRIBUTION_HISTORY; top queries in UI) [N3] | UNVERIFIED | Partial [C1] | Yes — FIN-003, FIN-103, UX-005 | — |
| Invoice / usage-statement reconciliation, period close, restatement | No evidence | Partial (views + reconciliation guide) [N4] | No evidence | No evidence | **Yes — FIN-009, FIN-010, FIN-101, FIN-107 (differentiator)** | — |
| Allocation to teams, rules, simulation | Yes (usage groups) [S1] | Partial (tag-based budgets) [N1] | Yes (virtual tags) [V1] | UNVERIFIED | Yes — ALC-001…008 with simulation and publication | Regex operators (D-16) |
| Showback portal and chargeback statements | Partial (usage groups + budgets) [S1, S2] | No evidence | UNVERIFIED | No evidence | **Yes — ALC-007, ALC-008 (statements with rounding and adjustments)** | — |
| Budgets with forecast, scoped to team/workload/tag | Yes [S2] | Yes (monthly, tag-based) [N1] | Yes (hierarchical) [V1] | No evidence | Yes — GOV-001, GOV-002 (run-rate, seasonal-naive) | GOV-104, GOV-105 |
| Anomaly detection | Yes [S3] | Yes [N2] | Yes [V3] | No evidence | Yes — GOV-005 (robust z, MAD) | — |
| Anomaly/change **root cause** explanation | Yes (Copilot drill-down) [S11] | No evidence | Partial (AI agent) [V3] | No evidence | **Gap → PRO-002 (R1)**; single-level movers only in UX-003-S04, WRK-005 | — |
| Scheduled spend **digests** inline in Slack/Teams/e-mail | Yes [S3] | No (budget notifications only) [N1] | Yes [V3] | No evidence | Partial — RPT-004 link-only cards (G-RPT-08); **Gap → PRO-003 (R1)** | — |
| Alert channels | Slack, Teams, e-mail [S3] | E-mail, SNS/Event Grid/PubSub, webhooks [N1] | E-mail, Slack, Teams [V3] | UNVERIFIED | E-mail, Slack, Teams, signed webhook — GOV-006 | **Gap → PRO-012** Jira, ServiceNow, PagerDuty |
| dbt cost per project/invocation/model | Yes [S9] | No evidence | No evidence | No evidence | Yes — WRK-002 | — |
| BI cost per dashboard (Looker, Sigma, Tableau, Power BI) | Yes (Looker, Sigma, Tableau) [S8] | No evidence | No evidence | No evidence | Power BI only — WRK-003; **allowlist capture Gap → PRO-007-S01/S02 (R1)** | **Gap → PRO-007** |
| Custom workloads from query tags; tagging guidance | Yes [S9] | No evidence | No evidence | No evidence | Partial — rules on raw `query_tag` (ALC), dbt snippet (WRK-002-S10); **Gap → PRO-004 (R1)** | WRK-105 custom apps |
| Recommendations with estimated savings | Yes (savings, effort, status) [S7] | Partial (recommendations) [N3] | Yes (agent) [V3] | Yes [C1] | Yes — 8 detectors, INS-001…004, INS-101 | INS-103…106 (28 more) |
| Action tracking and **verified** savings | Yes [S5, S6] | No evidence | UNVERIFIED | Yes (value report) [C1] | **Yes — INS-006, INS-007 (bootstrap intervals, confounders)** | — |
| Performance guardrails on savings (latency, queueing, spill) | UNVERIFIED (automation detail) [S5] | No evidence | No evidence | Yes (queueing, spill in recommendations) [C1] | **Gap → PRO-005 (R1)** — INS-007 is cost-only | — |
| Automated warehouse optimization (write access) | Yes [S5] | Partial (Adaptive warehouses size themselves; not FinOps-driven — FIN-004) | Partial (agent) [V3] | Yes (schedules, approvals) [C1] | No (read-only by design, PRD §10) | **Gap → PRO-009** |
| Query routing/rewriting | No evidence | No evidence | No evidence | No evidence | No | Not proposed (Keebo/Sundeck/Espresso niche, §1.4) |
| Capacity **contract burn-down**, balance, renewal/overage forecast | Yes [S4] | Yes (Organization Overview) [N3] | UNVERIFIED | No evidence | **Gap → PRO-001 (R1)**; balance sources not extracted | — |
| Unit economics (cost per customer/order) | No evidence | No evidence | Yes [V1] | No evidence | No (AI07/SP04 lack denominators) | **Gap → PRO-008** |
| AI/Cortex and SPCS cost | Yes (LLM, SPCS) [S12] | Yes [N3] | UNVERIFIED | No evidence | Yes — FIN-018, FIN-019, UX-007 | INS-005 detectors |
| Data export | CSV [S15] | FOCUS 1.3 view (unallocated) [N5] | UNVERIFIED | UNVERIFIED | On-demand CSV — API-102; **Gap → PRO-006 (R1)** FOCUS + scheduled bulk | **Gap → PRO-010** Secure Data Share |
| Public API | Yes (v2 = app API) [S10] | SQL views | Yes [V2] | UNVERIFIED | No (API-006 R2) | API-006; **SAS-015** reference portal |
| AI assistant / MCP | Yes (app, Slack, MCP) [S11] | UNVERIFIED (general Cortex agents, not FinOps-specific) | Yes (agent, MCP) [V1, V3] | No evidence | No | **Gap → PRO-011** read-only MCP |
| Configuration as code | UNVERIFIED | Partial (budgets via SQL) [N1] | Yes (Terraform) [V2] | No evidence | No | **Gap → SAS-016** Terraform provider |
| Marketplace procurement (pay from Snowflake capacity) | UNVERIFIED [S16] | — | No evidence | No evidence | No | **Gap → PRO-013** decision spike (French entity ineligible for MCD today [N6]) |

### 1.3 Feature matrix — SaaS surfaces

| Surface | select.dev | Snowflake native | Vantage | Slingshot | Bridge R1 (plan) | Bridge R2 (plan) |
|---|---|---|---|---|---|---|
| SSO (SAML/OIDC) | Yes (Okta, Entra, SAML) [S12] | — | Yes (SAML) [V4] | UNVERIFIED | Yes — SEC-003 (Entra, Okta, Google) | — |
| SCIM provisioning | UNVERIFIED | — | UNVERIFIED | UNVERIFIED | No (deprovisioning bounded by 12 h absolute session, SEC Appendix D) | SEC-106 |
| Scoped RBAC | Partial (roles) [S10] | — | Yes (access grants) [V2] | Yes (fine-grained RBAC) [C1] | **Yes — SEC-004, SEC-101 (row-level, identity-enforced)** | SEC-106 resource scopes |
| Audit log UI and export | Yes (UI) [S12] | — | UNVERIFIED | UNVERIFIED | Yes — SEC-008 (signed export chain), UX-102-S04 | **Gap → SAS-017** SIEM streaming |
| SOC 2 | Type II [S13] | — | SOC 1/2 Type 2 [V4] | UNVERIFIED | SOC 2-ready controls — OPS-108 (D-25) | Certification (business decision) |
| Trust/security page, subprocessors, DPA | Yes (security page) [S13] | Yes ([trust center](https://trust.snowflake.com/)) | Yes [V4] | UNVERIFIED | Files only — LCH-102, OPS-107 security.txt; **Gap → SAS-004 (R1)** | — |
| Status page | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | Planned but thin — OPS-102-S07 (3 h), LCH-104-S07 (1 h); **Gap → SAS-005 (R1)** | — |
| In-app status/product announcements | Yes (UNVERIFIED content) [S14] | — | UNVERIFIED | UNVERIFIED | No; **Gap → SAS-003, SAS-005 (R1)** | **SAS-018** notification center |
| Public docs site | Yes [S1, S7, S9] | Yes [N1–N5] | Yes [V1] | UNVERIFIED | Guides authored in repo — ONB-002; **Gap → SAS-002 (R1)** | **SAS-015** API reference |
| Public changelog | Yes [S12] | Yes (release notes) | Partial (launch blog posts) [V2, V3] | Partial (feature blog posts) [C1] | One-off v1.0.0 notes — LCH-003-S06; **Gap → SAS-003 (R1)** | — |
| Marketing site, pricing page | Yes (price level UNVERIFIED) [S16] | — | Yes ([pricing page](https://www.vantage.sh/pricing)) | Partial (product site; pricing UNVERIFIED) [C1] | **No task → SAS-001 (R1)** | — |
| Evaluation path | Free trial [S3] | — | Free tier (UNVERIFIED) | UNVERIFIED | Contracted pilot, no trial (D-17); **demo workspace Gap → SAS-014 (R1)** | — |
| In-app onboarding | UNVERIFIED | — | UNVERIFIED | UNVERIFIED | Yes to FV-1 — ONB-001 (projection-based wizard); **post-wizard guidance Gap → SAS-007 (R1)** | — |
| Self-serve billing portal | Yes (Stripe tab) [S14] | — | UNVERIFIED | UNVERIFIED | Invoice list and spend-band usage — LCH-001-S11, LCH-105-S05 (manual invoicing, D-30) | Automated billing ADR (D-30) |
| Transactional + lifecycle e-mail | n/p | n/p | n/p | n/p | Alerts/reports only — GOV-006/007; **Gap → SAS-006 (R1)** incl. Cognito defect | — |
| Help center, support channels | UNVERIFIED | Yes (community and support portal) | UNVERIFIED | UNVERIFIED | Policy + ticketing — LCH-104; **tooling Gap → SAS-011 (R1)** | — |
| Account/tenant deletion, data portability | UNVERIFIED | — | UNVERIFIED | UNVERIFIED | Yes (tenant, subject) — OPS-005, ONB-102; **app-user self-service Gap → SAS-013 (R1)** | — |
| Data residency | UNVERIFIED | Yes (customer-chosen region) | UNVERIFIED | UNVERIFIED | Single EU deployment (D-23) | Other regions as separate stacks |
| Contractual SLA with credits | UNVERIFIED | Yes (99.9 % Enterprise+, OPS G-OPS-03) | UNVERIFIED | UNVERIFIED | Objectives only (LCH-104-S02) | **Gap → SAS-020** |
| Accessibility statement | UNVERIFIED | — | UNVERIFIED | UNVERIFIED | WCAG 2.2 AA intent — UX-001, UX-008; **statement Gap → SAS-004 (R1)** | — |
| Localization | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | EN, externalized strings (D-18, UX-001-S03) | FR listed in RELEASE_PLAN §2 but **no task → SAS-021** |
| Internal: back-office, product analytics, error monitoring, feature flags | n/p (select ships in-app status/updates [S14]) | n/p | n/p | n/p | Ops plane + CLI (CTL-102, OPS-106), flags (REL-102); **Gaps → SAS-008, SAS-009, SAS-010, SAS-012 (R1)** | **SAS-019** health scoring |

### 1.4 Other peers — what they add to the picture

| Peer | Distinctive capability | Relevance to Bridge |
|---|---|---|
| Keebo [K1] | Autonomous rightsizing and query routing through a private endpoint | Confirms automation as the second competitive axis → PRO-009 (R2) |
| Espresso AI [E1] | Autoscaling and scheduling agents; priced on realized savings | Validates Bridge's verified-savings method (INS-007) as a commercial asset |
| Sundeck [D1] | Query hooks; OpsCenter as a free Snowflake Native App | Native-app distribution precedent → PRO-013 |
| CloudZero [Z1] | Allocation rules as code (CostFormation), cost per customer | Unit economics (PRO-008), config as code (SAS-016) |
| Finout [F1] | Virtual tags across vendors, anomalies routed to owners | Multi-vendor consolidation argues for FOCUS export (PRO-006) rather than competing on breadth |
| Revefi [R1x] | AI agent, Marketplace listing | Marketplace channel (PRO-013) |
| Chaos Genius / Flexera [G1] | Warehouse/query recommendations, e-mail/Slack reports | Digests (PRO-003) are table stakes |
| Bluesky [B1] | Query-pattern grouping, workload automation | Query-family aggregates (WRK-104) already match the pattern approach |
| Unravel [U1] | Chargeback, forecasting, AI agents with guardrails | Guardrails (PRO-005) |

### 1.5 Where the plan already exceeds peers (keep, and say so publicly)

Exact signed decimal ledger with billing-bucket supersession (D-12); PROVISIONAL/FINAL/MONTH_STABLE/RECONCILED and close as independent states (D-13); invoice and usage-statement reconciliation controls C1–C9 (FIN-009, FIN-101); restatement with prior-period adjustments (FIN-107); chargeback statements with largest-remainder rounding and maker-checker (ALC-008); verified savings with confounders and deterministic bootstrap intervals (INS-007); identity-enforced tenant isolation down to Snowflake row policies (SEC-005); pseudonymized user identifiers with a deletable dictionary (D-10); WIF-only access with no stored Snowflake credential (D-21). The trust center (SAS-004), docs (SAS-002) and marketing site (SAS-001) must carry these, because no peer evidence shows them.

## 2. Gaps

Scope rule applied: **R1 = needed for a credible paid production launch to enterprise FinOps buyers** (a buyer's pilot checklist, procurement, legal duty of the French entity, or an operational need for 1–2 human reviewers running production under D-19/D-37). Everything else is R2. Each gap names the existing tasks it builds on; new tasks never re-implement an owned capability (RECONCILIATION rulings U-05 ops plane, U-07 notifications, U-10 exports, U-11 deletion are respected).

### 2.1 Product gaps

#### G-PRO-01 · No Snowflake capacity-contract burn-down, balance tracking or renewal forecast
Severity: HIGH · Type: GAP (parity) · Scope: **R1** → PRO-001
- **Evidence.** select.dev Contract Overview uses `REMAINING_BALANCE_DAILY` and `CONTRACT_ITEMS` [S4]; Snowflake's own Organization Overview shows remaining balance and contract consumption vs forecast [N3]. The plan's source catalog extracts `USAGE_IN_CURRENCY_DAILY` and `RATE_SHEET_DAILY` (ING-102-S03) but neither balance nor contract view; FIN.md mentions `REMAINING_BALANCE_DAILY` only as vendor evidence for `funding_class` and in the R2 note "switch to the overage rate when REMAINING_BALANCE_DAILY shows capacity exhausted"; no screen exists.
- **Why it matters.** D-20 puts capacity contracts in R1. "Will we exhaust capacity before term end, forfeit unused capacity, or need an early renewal?" is the first CFO question for capacity customers and a renewal-negotiation input worth far more than Bridge's fee. A FinOps product that is behind Snowsight's free page on this question loses credibility in the first demo.
- **Design notes.** New ORG-scope source contracts through the existing ING framework (ORGANIZATION_BILLING_VIEWER; latency ≤ 72 h; FINANCIAL retention class, D-26). Drawdown derived from balance deltas with explicit contract events (top-ups, rollover injections) — never negative consumption — and cross-checked against ledger charges by `funding_class` (FIN §3), which lets Bridge show *which services* consumed the commitment (peers show totals only). Reseller contracts and non-primary organizations cannot read `CONTRACT_ITEMS` [N4]: manual contract record with maker-checker, linked to FIN-105 rates. Forecast reuses GOV-002 methods (UNCALIBRATED label, no intervals in R1). No new vendor or subprocessor.
- **Depends on.** ING-001, ING-102, CON-005, FIN-002, FIN-104, FIN-105, GOV-002, GOV-003, API-001, UX-002.

#### G-PRO-02 · "Why did this change?" is required by the PRD but computed by no task
Severity: HIGH · Type: GAP (under-specified) · Scope: **R1** → PRO-002
- **Evidence.** PRD §96 premium alert: "Main contributor dbt project FINANCE · Primary model daily_transactions · Change execution count 4.2x". GOV-007-S07 composes "top ≤ 3 verified contributors within scope" without a producer; UX-003-S04 movers and WRK-005 compare are single-level; WRK.md notes "Without a stated formula, two engineers produce different drivers". select's Copilot "drills down into anomalies until the root cause is identified" [S11].
- **Why it matters.** Anomaly alerts without a driver are the noise PRD §96 forbids; incident triage (GOV-008), Home (UX-003) and digests (PRO-003) all need the same, conserved explanation.
- **Design notes.** Deterministic recursive decomposition over registry-declared drill paths, compiled as semantic queries through the broker (API-002) under the requester's profile; Σ children + Other + residual = parent delta exactly; volume vs unit-cost split reuses WRK-005's fixed order; co-occurring change events (INS-102 config snapshots, first-seen resources, rate changes) attached as evidence, never as causality. LLM narration is out of scope (PRO-011 exposes the tree to MCP clients in R2).
- **Depends on.** API-001, API-002, API-004, API-104, WRK-005, WRK-104, INS-102, ALC-102.

#### G-PRO-03 · No inline scheduled spend digests
Severity: MEDIUM · Type: GAP (parity) · Scope: **R1** → PRO-003
- **Evidence.** select sends per-usage-group spend digests to Slack/Teams/e-mail [S3]; Vantage report notifications daily/weekly/monthly [V3]; Chaos Genius e-mail/Slack reports [G1]. The plan's Slack/Teams report delivery is link-only (RPT G-RPT-08) and requires login; GOV-005-S04's digest is an anomaly list.
- **Why it matters.** Showback changes behaviour only when budget owners see their numbers where they work. It is the cheapest retention feature in the category.
- **Design notes.** Reuse RPT-004's occurrence planner, GOV-006 adapters, GOV-007 outbox/reauthorization and disclosure levels; channel digests default to SUMMARY (percentages and statuses, no amounts) because Slack/Teams channel membership is outside Bridge's access control. No new vendor.
- **Depends on.** GOV-006, GOV-007, RPT-004, ALC-102, GOV-001, INS-101, PRO-002.

#### G-PRO-04 · No attribution-coverage KPI or query-tagging guidance
Severity: MEDIUM · Type: GAP · Scope: **R1** → PRO-004
- **Evidence.** ALC-006 remediates unowned resources; WRK-002-S10 gives a dbt snippet; ALC rules can match raw `query_tag`. No coverage-by-mechanism metric, no generated snippets for other tools, no regression alert. select documents custom workloads via query tags and ships tagging packages [S9].
- **Why it matters.** Chargeback accuracy is capped by attribution coverage; enterprise buyers ask "what share of spend is attributable, and how do we raise it?" in week one.
- **Design notes.** Coverage from existing ALC quality facts (no new formula); snippets for dbt, Python connector/Airflow `session_parameters`, `ALTER USER … SET QUERY_TAG`, Tableau/Power BI notes; customer key conventions validated against WRK-101's allowlist (keys outside it are dropped at extraction — surfaced as an allowlist request, never silently).
- **Depends on.** ALC-006, ALC-102, WRK-001, WRK-101, API-104, GOV-003, SAS-002.

#### G-PRO-05 · "Verified savings" ignore performance regressions
Severity: HIGH · Type: GAP (credibility) · Scope: **R1** → PRO-005
- **Evidence.** INS-007 validates on cost with confounders and bootstrap intervals, but no latency, queueing or spill measure; Slingshot recommendations weigh queued queries and spillage [C1]; automation vendors constrain by SLA [K1, S5].
- **Why it matters.** A downsizing that saves 40 % while doubling p95 latency would be reported VALIDATED(SAVING). Data-platform owners reject such claims, and the verified-savings figure is Bridge's commercial proof (Home "Realized YTD", LCH-004 value review).
- **Design notes.** Guardrails from D-11 family aggregates with mergeable sketches (t-digest, never averaged percentiles — G-API-04); outcome PASS/BREACH/INCONCLUSIVE joined to INS-007's outcome; BREACH excluded from verified totals unless the owner accepts the trade-off (audited). Manual changes only in R1.
- **Depends on.** INS-006, INS-007, WRK-104, INS-102, GOV-101.

#### G-PRO-06 · No standard bulk export of the allocated ledger (FOCUS 1.3)
Severity: MEDIUM · Type: GAP · Scope: **R1** → PRO-006
- **Evidence.** API-102 provides on-demand CSV exports; nothing scheduled, nothing in a standard schema. Snowflake now publishes unallocated FOCUS 1.3 data [N5]; FinOps suites (Vantage, CloudZero, Finout) consolidate multi-vendor spend [V1, Z1, F1].
- **Why it matters.** Enterprise FinOps teams run a multi-cloud tool or warehouse; Bridge wins that seat by being the *allocated, reconciled* Snowflake source for it, not by competing on multi-cloud breadth.
- **Design notes.** New API-102 export kinds (U-10) `FOCUS_1_3_ALLOCATED` and `LEDGER_NATIVE`, Parquet + CSV with manifest; server-side unload under the tenant profile through the broker JOB class; `x_`-prefixed Bridge columns for data status, reconciliation status, publication and book; schedules via RPT-004; delivery via SEC-006-S08 and a signed `export.ready` webhook. Column mapping TO VERIFY against the FOCUS 1.3 text.
- **Depends on.** API-102, API-004, ALC-005, ALC-008, FIN-009, FIN-010, SEC-006, RPT-004, GOV-006.

#### G-PRO-07 · BI attribution beyond Power BI is absent, and its metadata will be lost at the first backfill
Severity: HIGH (irreversibility) · Type: GAP · Scope: **R2**, with **S01–S02 in R1** → PRO-007
- **Evidence.** WRK-003 covers Power BI only; select covers Looker, Sigma, Tableau [S8]. Tableau tags Snowflake queries with LUIDs by default; Looker prepends a context comment [X2] (leading comments are stripped from `QUERY_TEXT` — SEC G-SEC-15 — so Looker likely needs its API; TO VERIFY LIVE).
- **Why it matters.** Dashboards are a top-3 spend driver in BI-heavy accounts. The allowlist freeze before the first backfill makes the capture step urgent even though the feature is R2.
- **Design notes.** R1: specify signals and extend WRK-101 allowlist v1 before freeze (PII review; Looker `user_id` → HMAC per D-10). R2: classifier rules, facts, optional name enrichment by customer CSV or a stored read-only BI API credential — a new third-party credential class requiring SEC review (PRD §2.2 forbids stored *Snowflake* credentials only).
- **Depends on.** WRK-101 (step-level, before freeze), WRK-001, WRK-104, API-104, UX-002.

#### G-PRO-08 · No unit economics
Severity: MEDIUM · Scope: **R2** → PRO-008 · Evidence: Vantage [V1], CloudZero [Z1], Finout [F1]; INS matrix marks AI07/SP04 inputs "no source; customer dataset". Design: customer-approved business metrics by CSV upload or a customer view extracted with an explicit grant; unit cost null when the denominator is missing or zero. Depends on ALC-005, ALC-102, API-001, CTL-005, GOV-003.

#### G-PRO-09 · No automated optimization (action plane)
Severity: MEDIUM (strategic) · Scope: **R2**, owner go/no-go (§5 Q3) → PRO-009 · Evidence: select [S5], Keebo [K1], Espresso [E1], Slingshot [C1]. Design per PRD §10/§147: separate operator WIF identity per account, allowlisted warehouses, bounds, schedules, maker-checker or bounded auto mode, rollback on guardrail breach (PRO-005), kill switches (REL-102), verification through INS-007. Depends on CON-003, INF-103, SEC-102, REL-102, INS-006, INS-007, PRO-005, OPS-004.

#### G-PRO-10 · No delivery of allocated data into the customer's Snowflake account
Severity: LOW · Scope: **R2** → PRO-010 · Design: per-tenant share of secure views over the export dataset; cross-region delivery only through listing auto-fulfillment, which replicates data outside the EU region unless restricted — opt-in with residency waiver (D-23). Depends on PRO-006, DBT-006, SEC-005, INF-008, REL-103.

#### G-PRO-11 · No AI-client access (MCP) to the semantic API
Severity: LOW · Scope: **R2** → PRO-011 · Evidence: select Copilot over MCP [S11], Vantage MCP [V1]; PRD §145–§146. Design: read-only tools over the public API (API-006) with the caller's token; every figure carries unit, maturity, publication id and deep link. Depends on API-006, API-001, API-005, API-104, PRO-002.

#### G-PRO-12 · No ticketing/paging integrations for actions and incidents
Severity: LOW · Scope: **R2** → PRO-012 · Evidence: PRD §95 "Later: Jira, PagerDuty, Opsgenie"; Snowflake budgets already post to PagerDuty via webhook [N1]. Depends on GOV-006, GOV-007, INS-006, GOV-008.

#### G-PRO-13 · Marketplace/Native App distribution undecided
Severity: LOW (strategic) · Scope: **R2 decision spike** → PRO-013 · Evidence: MCD GA only for US-based providers and consumers [N6]; Sundeck and Revefi distribute through the Marketplace [D1, R1x]. The French invoicing entity (D-36) is ineligible today; a Native App would move computation into customer accounts, against the central-ledger architecture. Owner question §5 Q4.

### 2.2 Platform and SaaS-surface gaps

#### G-SAS-01 · No marketing website, pricing page or legally required site notices
Severity: HIGH · Scope: **R1** → SAS-001
- **Why.** Buyers and procurement land on the website before a demo; with no free trial (D-17) the site's job is "request a pilot". The French entity (D-36) must publish LCEN legal notices (company name, legal form, capital, registered office, host) on its website [L1].
- **Design.** Static site (Astro) in a separate CloudFront distribution and bucket from the app (no shared origin); pricing page explains the D-17 model and the LCH-105 band rule, with price levels per owner answer (§5 Q2); pilot-request form to a Lambda + DynamoDB + SES inbox — no CRM subprocessor in R1; audience measurement from CloudFront logs with IPs dropped (no cookies, no client script) inside the CNIL exemption conditions [L1] → no consent banner. EU region, no new subprocessor.
- **Depends on.** INF-006, UX-001, LCH-102, SAS-004.

#### G-SAS-02 · Customer documentation is written but never published
Severity: HIGH · Scope: **R1** → SAS-002
- **Why.** D-38 promises a wizard usable without Bridge staff; install scripts, permissions, network allowlisting and financial-status semantics must be findable and linkable from the app. ONB-002 writes `docs/customer/**` in the repository only.
- **Design.** Astro Starlight site at `docs.<domain>`, content sourced from `docs/customer/**` (single source), reference pages generated from the API-001 metric registry, CON-003 templates, onboarding blocker codes and OpenAPI problem types; Pagefind static search (no Algolia subprocessor); versioned per release. Depends on ONB-002, API-001, SAS-001, UX-001.

#### G-SAS-03 · No changelog or in-app "What's new"
Severity: MEDIUM · Scope: **R1** → SAS-003 · Why: coding agents ship continuously (D-19); customers' change management and financial trust need dated entries, especially for metric-definition changes. Design: entries in-repo, drafted from the REL-001 release manifest, human-edited, RSS/Atom, in-app panel from a same-origin JSON (no widget vendor); any API-001 registry version bump requires an entry (CI). Depends on REL-001, SAS-002, UX-001, SAS-013.

#### G-SAS-04 · No public trust center
Severity: HIGH · Scope: **R1** → SAS-004 · Why: procurement reads a trust page before sending a questionnaire [T1]; peers publish SOC 2 status and security pages [S13, V4]. LCH-102 produces the inputs as files for counsel; OPS-107 publishes `security.txt`. Design: static page generated from the approved legal/security sources with one `trust-facts.yaml` whose numbers are CI-checked against the OPS-005 retention matrix and SEC Appendix D; subprocessor register with ≥ 30-day change notice subscription; NDA-gated documents through the helpdesk (no SafeBase-type vendor in R1); accessibility statement (EAA likely out of scope for a B2B-only service, counsel to confirm [L1]); compliance wording "SOC 2-ready" exactly per D-25. Depends on LCH-102, OPS-107, OPS-108, SAS-001, SAS-006, SAS-011.

#### G-SAS-05 · Status page planned without automation, independence or in-app banners
Severity: MEDIUM · Scope: **R1** → SAS-005 · Evidence: OPS-102-S07 (3 h, private setup), LCH-104-S07 (1 h, make public); vendor open (OPS Q4). Design: EU vendor (Better Stack, Czech, EU data [X1]) or self-hosted static page off AWS eu-west-1; components mapped to OPS-003 SLIs; probe failure opens a *draft* incident, a human publishes; in-app banner served from a static JSON so it works when the API is degraded. Subprocessor: subscriber e-mails if the vendor sends them. Depends on OPS-102, OPS-003, LCH-104, CTL-102, UX-001.

#### G-SAS-06 · Transactional and lifecycle e-mail has no owner; Cognito default sender is capped at 50/day
Severity: HIGH (Cognito cap is a production defect) · Scope: **R1** → SAS-006
- **Evidence.** Cognito `COGNITO_DEFAULT` quota (50/day) and `DEVELOPER` requirement for custom message parameters (VERIFIED, AWS docs); CTL-003-S05 "outbox `invitation.created` → email" without a template owner; GOV-007 covers alert/report deliveries only; no preference center or one-click unsubscribe (RFC 8058, required by large mailbox providers for non-transactional bulk mail).
- **Design.** Cognito `EmailSendingAccount=DEVELOPER` on the INF-006 SES identity + custom-message Lambda with externalized strings (D-18); MJML templates; system messages through the GOV-007 outbox and GOV-006 e-mail adapter (U-07 respected); separate sending subdomain for lifecycle/announcements to isolate reputation; SES open/click tracking disabled; lifecycle nudges as rules over domain facts (ONB-001 projection). No new subprocessor (SES is already AWS).
- **Depends on.** INF-006, GOV-006, GOV-007, SEC-002, CTL-003, ONB-001.

#### G-SAS-07 · No guidance after the onboarding wizard; empty states have no content contract
Severity: MEDIUM · Scope: **R1** → SAS-007 · Why: the steps that turn data into a FinOps practice (invite owners, publish rules, create a budget, connect Slack, schedule a report) are where self-service trials stall; ONB-001 ends at FV-1. Design: checklist as a projection of domain facts (same principle as ONB-001, G-ONB-01), empty-state copy/CTA/docs-anchor registry, contextual help linking the generated metric glossary. Depends on ONB-001, UX-001, UX-002, SAS-002, GOV-001, GOV-006, RPT-004, ALC-003, CTL-003.

#### G-SAS-08 · No customer-360 view in the back office
Severity: HIGH (operational) · Scope: **R1** → SAS-008 · Why: 1–2 humans (D-19) support customers in EU business hours (D-37); triage needs one page per tenant. CTL-102 provides the ops plane, OPS-106 a CLI, SEC-104 support grants — none aggregates state. Design: metadata-only by contract (no amounts, names or SQL without a SEC-104 grant), each panel sourced from its owning domain API, views audited. Depends on CTL-102, SEC-104, LCH-001, LCH-101, ONB-001, ING-012, CON-005, REL-102, OPS-101.

#### G-SAS-09 · No product analytics
Severity: MEDIUM · Scope: **R1 (first-party, minimal)** → SAS-009 · Why: adoption evidence for D-38's self-service claim, for customer success and for R2 prioritization. Design: server-authoritative event taxonomy with a property allowlist (no values, names, SQL, URLs), HMAC user keys, storage in an internal Snowflake schema with no customer/serving grants (OPS-009 pattern), tenant opt-out, no session replay. PostHog EU or self-hosted [X1] only if R2 needs funnels beyond SQL. Depends on OPS-001, UX-002, OPS-104, LCH-102, OPS-009.

#### G-SAS-10 · No error monitoring or real-user monitoring
Severity: HIGH (operational) · Scope: **R1** → SAS-010 · Evidence: UX-001-S11 emits client telemetry "to an OPS endpoint" that no task builds; OPS-001 has logs/traces/metrics but no issue grouping, regression detection or source-mapped stacks. Design: Sentry SDKs everywhere; backend = Sentry SaaS EU region (Frankfurt [X1], US-parented → subprocessor + transfer assessment) or self-hosted GlitchTip (Sentry-SDK compatible) per owner answer (§5 Q1); scrubbing reuses OPS-001 redaction; no session replay; private source maps. Depends on OPS-001, UX-001, INF-007, OPS-102, LCH-102.

#### G-SAS-11 · Support tooling is a placeholder
Severity: MEDIUM · Scope: **R1** → SAS-011 · Evidence: LCH-104-S04 "helpdesk or shared inbox" (3 h); UX-102-S06 support form without a backend. Design: helpdesk with SLA timers on the D-37 calendar (Crisp — French, EU-hosted [X1] — or self-hosted Zammad), app intake enriched with tenant id and request ids, help articles live on the docs site (one knowledge source), no third-party chat script inside the authenticated app. Depends on LCH-104, UX-102, SAS-002, SAS-008.

#### G-SAS-12 · Flags lack tenant targeting, beta cohorts and plan-gating UX
Severity: MEDIUM · Scope: **R1** → SAS-012 · Evidence: REL-102 = server-side flags and kill switches; LCH-101 = entitlements. Design: deterministic tenant bucketing, cohorts (internal, canary, beta), OpenFeature-compatible providers, flags delivered in the session payload for the active tenant only, a single `<Entitled>` locked state. Self-built (no LaunchDarkly subprocessor). Depends on REL-102, LCH-101, UX-002, SEC-002, OPS-103.

#### G-SAS-13 · No "My account" page, personal data export or app-user deletion
Severity: MEDIUM (GDPR controller duty) · Scope: **R1** → SAS-013 · Why: Bridge is controller for its own users' account data; OPS-005 covers tenant deletion and Snowflake-user subjects, not app users. No profile screen exists among the 87 routes. Depends on SEC-002, SEC-004, SEC-008, OPS-005, OPS-104, SAS-006, UX-002.

#### G-SAS-14 · No demo workspace although there is no free trial
Severity: MEDIUM · Scope: **R1** → SAS-014 · Why: D-17 routes evaluation through demos and a contracted pilot; demos from staging show test debris and depend on staging. Design: production tenant `is_synthetic=true` fed through the normal ingestion path from FND-004 generators, rolling dates, watermark, excluded from metering, SLO denominators and analytics. Depends on FND-004, INF-101, CTL-102, SEC-004, OPS-103.

#### G-SAS-15 … G-SAS-21 · R2 surfaces
| Gap | Why | Design / residency | Task |
|---|---|---|---|
| G-SAS-15 API reference portal | Public API ships with API-006 (R2); developers need reference, guides, quickstarts | Static Scalar/Redoc from released OpenAPI on the docs site; no vendor | SAS-015 |
| G-SAS-16 Configuration as code | Vantage Terraform provider [V2], CloudZero CostFormation [Z1]; PRD §145 "future Terraform" | Go provider (terraform-plugin-framework) on API-006 credentials; published to Terraform and OpenTofu registries | SAS-016 |
| G-SAS-17 SIEM streaming, IP allowlist | Enterprise security teams pipe audit logs to SIEM [T1]; IP restrictions are a common questionnaire item | Stream SEC-008 events to HTTPS/Splunk HEC/Datadog EU/customer S3; allowlist enforced at the BFF from CloudFront's viewer address | SAS-017 |
| G-SAS-18 In-app notification center | Persistent inbox for incidents, exports, reports, support requests | PG inbox with read-time reauthorization; polling, no websocket | SAS-018 |
| G-SAS-19 Customer health, value reports | Renewal risk and ROI evidence for the fee | Explainable score from SAS-009/SAS-011 signals; value report counts only verified savings | SAS-019 |
| G-SAS-20 Contractual SLA with credits | Enterprise MSAs ask for credits; R1 publishes objectives only (LCH-104-S02) | Per-tenant monthly SLI computation from OPS-003 probes; credits as manual credit notes (D-30) | SAS-020 |
| G-SAS-21 French localization | RELEASE_PLAN §2 lists FR for R2 but no task exists | UI, e-mail, Cognito, notification and report templates, top docs pages; human review of financial terms | SAS-021 |

### 2.3 Covered or partially covered — no new task

| Capability | Where it is covered | Residual note |
|---|---|---|
| Workload-level and tag budgets | GOV-001 (scope reuses the analytics filter schema, incl. usage group, warehouse, workload) | — |
| dbt cost per model/invocation | WRK-002 | Exact run metrics only with verified invocation ids (by design) |
| Recommendations with estimated savings | INS-001…004, INS-101 (8 detectors) | ST03/ST04 have no numeric estimate in R1 (needs AU.TABLES) |
| Credit/balance tracking | PRO-001 (new) plus FIN `funding_class` | — |
| Data sharing and Marketplace **costs** | FIN-020, FIN-008 | Delivery of Bridge data by share is PRO-010 (R2) |
| Usage metering for the spend-band plan | LCH-105 (+ LCH-101-S10 limits display) | "Band threshold approaching" e-mail added as a SAS-006 catalogue event |
| Feature flags, kill switches | REL-102 | Targeting and gating UX: SAS-012 |
| Audit log UI and export | SEC-008, UX-102-S04 | SIEM streaming: SAS-017 (R2) |
| SCIM | SEC-106 (R2) | Keep R2; trust center states IdP deprovisioning lag ≤ 12 h absolute session (SEC Appendix D) |
| Tenant deletion, DSAR, offboarding export | OPS-005, ONB-102, UX-102-S05 | App-user self-service: SAS-013 |
| Support access with customer approval | SEC-104 | — |
| Accessibility | UX-001-S02/S16, UX-008 (axe on all routes) | Public statement: SAS-004 |
| i18n readiness | UX-001-S03/S04 (FormatJS, pseudo-locale, lint) | FR: SAS-021 (R2) |
| Uptime SLOs | OPS-003 (99.9 % control plane, 99.5 % analytics — D-31) | Contractual credits: SAS-020 (R2) |
| Public API | API-006 (R2) | Reference portal SAS-015, Terraform SAS-016, MCP PRO-011 |
| Penetration test, VDP, security.txt | OPS-107 | Linked from SAS-004 |

## 3. New tasks

Format as in the domain backlogs' §4/§5. Estimates are senior-engineer-equivalent hours including tests, review fixes and evidence; low = Σ micro-step hours, high ≈ 1.45 × low. Vendor fees, counsel and translation costs are excluded. Every task ends with an evidence step under `docs/evidence/<TASK>/<commit>/` per the [delivery methodology](../../DELIVERY_METHODOLOGY.md).

### 3.0 Proposed dependency edges into existing tasks

No existing file is edited by this document; the edges below are proposals for the next reconciliation pass of [revised-task-graph.json](revised-task-graph.json).

| Existing task | Proposed change | Reason |
|---|---|---|
| REL-003 | `+SAS-001, +SAS-002, +SAS-004, +SAS-005, +SAS-006, +SAS-010, +SAS-011` | Launch-readiness pack cannot be complete without public site, docs, trust page, status automation, working e-mail, error monitoring and support tooling |
| REL-004 | `+PRO-001, +PRO-002, +PRO-003, +PRO-004, +PRO-005, +PRO-006, +SAS-007, +SAS-008, +SAS-009, +SAS-012, +SAS-013, +SAS-014` | R1 scope completeness at the production gate |
| WRK-101 | step-level: WRK-101-S01 (allowlist v1) includes PRO-007-S02's keys before freeze; no graph edge (as RECONCILIATION C-29 step-level edges) | Irreversible extraction (G-WRK-01) |
| ING-102 | step-level: activates the two source contracts authored in PRO-001-S01 | Avoids a cycle PRO-001 ↔ ING-102 |
| SEC-002 | step-level: SAS-006-S02 (Cognito `DEVELOPER` e-mail) lands with SEC-002 in phase P1 | Native-user e-mails are throttled under the default 50/day sender |
| INF-006 | step-level: DNS map adds `www`, apex, `docs`, `trust`, `status`, `news` (lifecycle sender) | Hosting for SAS-001…006 |
| OPS-104 | step-level: tombstone kind `APP_USER` (SAS-013-S06) | App-user deletion must survive restores |
| LCH-102 | step-level: subprocessor register includes the vendors chosen in SAS-005-S01, SAS-010-S01, SAS-011-S01 | Subprocessor completeness (CI check in SAS-004-S02) |
| GOV-007 | soft: GOV-007-S07 quotes PRO-002's summary when available, else omits contributors; no graph edge | Keeps GOV off PRO-002's chain |
| UX catalog | adds screens 88 `/me` (SAS-013), 89 `/contract` (PRO-001), 90 `/allocation/coverage` (PRO-004), `/settings/digests` (PRO-003), `/settings/exports` (PRO-006) | Screen-ownership rule of UX §3.1 |

The task sections moved to [backlog/SAS.md](backlog/SAS.md) and [backlog/PRO.md](backlog/PRO.md) when they were integrated into the revised graph (2026-09-28). PRO-007 was split: its R1 part (signal specification and WRK-101 allowlist change before freeze, 4–6 h) keeps the ID PRO-007 and WRK-101 now depends on it; the R2 remainder is PRO-014 (34–49 h). The §3.0 edges were applied: REL-003 and REL-004 gained the listed dependencies.

| Task | Release | Estimate (h) | Backlog |
|---|---|---|---|
| SAS-001 — Marketing website, pricing page, pilot-request intake and French legal notices | R1 | 35–51 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-002 — Public documentation site with versioning, search and a generated metric glossary | R1 | 32–46 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-003 — Public changelog, release-notes pipeline and in-app "What's new" | R1 | 17–25 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-004 — Trust center: security overview, subprocessors, legal hub and accessibility statement | R1 | 25–36 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-005 — Status page automation, maintenance windows and in-app service banners | R1 | 18–26 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-006 — Transactional and lifecycle e-mail system (templates, preferences, Cognito via SES, deliverability) | R1 | 37–54 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-007 — In-app getting-started checklist, contextual help and empty-state calls to action | R1 | 21–30 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-008 — Customer-360 back-office view and operator workflows | R1 | 33–48 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-009 — First-party product analytics with privacy controls | R1 | 22–32 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-010 — Error monitoring and real-user monitoring with scrubbing | R1 | 19–28 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-011 — Help center, in-app support entry points and ticket SLA tooling | R1 | 19–28 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-012 — Tenant-targeted release flags, beta programme and plan-gating UX | R1 | 19–28 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-013 — My account: profile, sessions, notification preferences, personal-data export and account deletion | R1 | 18–26 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-014 — Sales demo workspace with refreshed synthetic data | R1 | 17–25 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-015 — API reference portal and developer documentation | R2 | 22–32 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-016 — Terraform provider for configuration as code | R2 | 46–67 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-017 — Enterprise admin controls: audit-log SIEM streaming, IP allowlist and session-policy UI | R2 | 24–35 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-018 — In-app notification center | R2 | 18–26 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-019 — Customer health scoring, value reports and renewal tooling | R2 | 19–28 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-020 — Contractual SLA and service credits | R2 | 17–25 | [backlog/SAS.md](backlog/SAS.md) |
| SAS-021 — French localization (UI, e-mail, notifications, reports, key docs) | R2 | 24–35 | [backlog/SAS.md](backlog/SAS.md) |
| PRO-001 — Snowflake capacity-contract burn-down, balance tracking and renewal forecast | R1 | 41–59 | [backlog/PRO.md](backlog/PRO.md) |
| PRO-002 — Cost-change root-cause engine (driver decomposition and co-occurring change events) | R1 | 38–55 | [backlog/PRO.md](backlog/PRO.md) |
| PRO-003 — Scheduled spend digests (inline Slack/Teams/e-mail) per owner and usage group | R1 | 27–39 | [backlog/PRO.md](backlog/PRO.md) |
| PRO-004 — Attribution coverage and query-tagging guidance | R1 | 26–38 | [backlog/PRO.md](backlog/PRO.md) |
| PRO-005 — Right-sizing experiments with performance guardrails | R1 | 27–39 | [backlog/PRO.md](backlog/PRO.md) |
| PRO-006 — FOCUS 1.3-aligned allocated-cost export and scheduled bulk exports | R1 | 29–42 | [backlog/PRO.md](backlog/PRO.md) |
| PRO-007 — Capture BI-tool attribution signals before the WRK-101 allowlist freeze | R1 | 4–6 | [backlog/PRO.md](backlog/PRO.md) |
| PRO-008 — Unit economics with customer business metrics | R2 | 28–41 | [backlog/PRO.md](backlog/PRO.md) |
| PRO-009 — Opt-in automated warehouse optimization (action plane) | R2 | 51–74 | [backlog/PRO.md](backlog/PRO.md) |
| PRO-010 — Allocated-cost delivery via Snowflake Secure Data Sharing | R2 | 26–38 | [backlog/PRO.md](backlog/PRO.md) |
| PRO-011 — Read-only MCP server over the semantic API | R2 | 23–33 | [backlog/PRO.md](backlog/PRO.md) |
| PRO-012 — Ticketing and paging integrations for actions and incidents (Jira, ServiceNow, PagerDuty) | R2 | 23–33 | [backlog/PRO.md](backlog/PRO.md) |
| PRO-013 — Snowflake Marketplace / Native App distribution decision spike | R2 | 21–30 | [backlog/PRO.md](backlog/PRO.md) |
| PRO-014 — BI-tool workload attribution: Tableau, Sigma, Looker (classifier, marts, metadata, pages) | R2 | 34–49 | [backlog/PRO.md](backlog/PRO.md) |

## 4. Estimate summary

### 4.1 Per task

Lane letters follow [RELEASE_PLAN.md §3](RELEASE_PLAN.md#3-parallel-lanes); phases follow its §6 (P0–P6).

| Task | Title (short) | Release | Low h | High h | Lane | Phase |
|---|---|---|---:|---:|---|---|
| SAS-001 | Marketing site, pricing, pilot intake, legal notices | R1 | 35 | 51 | G | P4 (legal page P6) |
| SAS-002 | Public docs site, generated reference | R1 | 32 | 46 | G | P4 scaffold, P6 content cut |
| SAS-003 | Changelog and in-app "What's new" | R1 | 17 | 25 | G | P6 |
| SAS-004 | Trust center, legal hub, accessibility statement | R1 | 25 | 36 | G | P6 |
| SAS-005 | Status automation and in-app banners | R1 | 18 | 26 | A1 | P5 |
| SAS-006 | Transactional/lifecycle e-mail, Cognito via SES | R1 | 37 | 54 | A2 / E | S02 in P1, rest P5 |
| SAS-007 | Getting-started checklist, help, empty states | R1 | 21 | 30 | D | P5 |
| SAS-008 | Customer-360 back office | R1 | 33 | 48 | A2 | P4–P5 |
| SAS-009 | First-party product analytics | R1 | 22 | 32 | A1 | P5 |
| SAS-010 | Error monitoring and RUM | R1 | 19 | 28 | A1 | P1–P2 |
| SAS-011 | Help center and ticket SLA tooling | R1 | 19 | 28 | G | P5 |
| SAS-012 | Tenant-targeted flags, beta, plan gating | R1 | 19 | 28 | A1 | P3 |
| SAS-013 | My account and personal-data rights | R1 | 18 | 26 | A2 | P5 |
| SAS-014 | Sales demo workspace | R1 | 17 | 25 | G | P3–P4 |
| PRO-001 | Contract burn-down and renewal forecast | R1 | 41 | 59 | C / E | S01 in P2, rest P4 |
| PRO-002 | Root-cause engine | R1 | 38 | 55 | D | P5 |
| PRO-003 | Scheduled spend digests | R1 | 27 | 39 | E | P5 |
| PRO-004 | Attribution coverage and tagging guidance | R1 | 26 | 38 | E | P5 |
| PRO-005 | Right-sizing experiments with guardrails | R1 | 27 | 39 | F | P5 |
| PRO-006 | FOCUS 1.3 and scheduled bulk exports | R1 | 29 | 42 | D | P5 |
| PRO-007 (S01–S02) | BI signal capture before allowlist freeze | R1 part | 4 | 6 | B / D | P1 (with WRK-101) |
| **Total R1** | **20 tasks + 1 R1 part** | | **524** | **761** | | |
| SAS-015 | API reference portal | R2 | 22 | 32 | G | R2 |
| SAS-016 | Terraform provider | R2 | 46 | 67 | D | R2 |
| SAS-017 | SIEM streaming, IP allowlist, session policy UI | R2 | 24 | 35 | A2 | R2 |
| SAS-018 | In-app notification center | R2 | 18 | 26 | D | R2 |
| SAS-019 | Health scoring, value reports, renewals | R2 | 19 | 28 | G | R2 |
| SAS-020 | Contractual SLA and credits | R2 | 17 | 25 | A1 | R2 |
| SAS-021 | French localization | R2 | 24 | 35 | D | R2 |
| PRO-007 (S03–S13) | BI-tool attribution (Tableau, Sigma, Looker) | R2 | 34 | 49 | D | R2 (R1 if first customer's main BI tool) |
| PRO-008 | Unit economics | R2 | 28 | 41 | E | R2 |
| PRO-009 | Automated warehouse optimization | R2 | 51 | 74 | F | R2 (owner go/no-go) |
| PRO-010 | Secure Data Sharing delivery | R2 | 26 | 38 | C | R2 |
| PRO-011 | Read-only MCP server | R2 | 23 | 33 | D | R2 |
| PRO-012 | Jira, ServiceNow, PagerDuty | R2 | 23 | 33 | E | R2 |
| PRO-013 | Marketplace / Native App decision spike | R2 | 21 | 30 | G | R2 |
| **Total R2** | **14 tasks (PRO-007 remainder counted here)** | | **376** | **546** | | |

| Summary | Tasks | Low h | High h |
|---|---:|---:|---:|
| New R1 — SaaS surfaces (SAS) | 14 | 332 | 483 |
| New R1 — product (PRO, incl. PRO-007 R1 part) | 6 + part | 192 | 278 |
| **New R1 total** | **20 + part** | **524** | **761** |
| New R2 — SaaS surfaces (SAS) | 7 | 170 | 248 |
| New R2 — product (PRO) | 7 | 206 | 298 |
| **New R2 total** | **14** | **376** | **546** |
| Plan R1 after this review (7,116–10,488 + new) | 229 + 20 | 7,640 | 11,249 |
| Plan R2 after this review (614–948 + new) | 20 + 14 | 990 | 1,494 |

Excluded from hours: vendor subscriptions (status page, error monitoring, helpdesk if SaaS), counsel review (legal notices, DPA/privacy updates, SLA schedule, EAA analysis), translation (SAS-021), Snowflake credits for PRO-009/PRO-010 live proofs (inside the D-32 estate budget), Terraform/OpenTofu registry and GPG setup time beyond the steps listed.

### 4.2 Scheduling and critical path

- Recomputed from [revised-task-graph.json](revised-task-graph.json) plus the 34 new tasks and every proposed edge of §3.0: **the chain to the first payment (LCH-002) stays 1,362–2,006 h** and contains no new task. Minimum slack along dependency chains is 27 h (low) before REL-003 (SAS-004, gated by LCH-102/OPS-107) and 44 h before REL-004 (PRO-006); start those tasks as soon as their inputs exist.
- This required nine dependencies to be **step-level rather than graph edges** (they are written that way in the task headers): SAS-001 ← LCH-102 legal texts; SAS-002 ← ONB-002 content; SAS-004 ← SAS-006 and SAS-011; SAS-011, SAS-007 and PRO-004 ← SAS-002 publishing; SAS-009 and SAS-010 ← LCH-102 register. As hard edges they would lengthen the chain by up to 82–108 h, because LCH-102, OPS-107 and ONB-002 finish late.
- **Front-load three steps**: SAS-006-S02 (Cognito on SES) with SEC-002 in P1; SAS-010 in P1–P2 so development and staging already report errors; PRO-007-S01/S02 in P1 before the WRK-101 allowlist freeze and ING-010's first backfill.
- Review load: 20 R1 tasks + the PRO-007 R1 part = 219 micro-steps, in lanes G (6 tasks), A1 (4), A2 (3), D (3), E (2), C/E (1) and F (1). Under D-19 (2–3 agent lanes per reviewer) this fits the existing lanes' P4–P6 windows without a new lane.

### 4.3 Vendor, residency and subprocessor implications (R1)

| Capability | Recommended | Self-hosted alternative | Personal data sent | Region | Subprocessor? |
|---|---|---|---|---|---|
| Marketing site, docs, trust, changelog | Static on S3 + CloudFront (existing AWS) | — | Pilot-request form fields | eu-west-1 | No new (AWS) |
| Site audience measurement | CloudFront logs → Athena, IP dropped | — | None stored | eu-west-1 | No |
| Docs search | Pagefind (static) | — | None | — | No |
| Transactional/lifecycle e-mail | SES (existing, INF-006) | — | Recipient e-mail, name | eu-west-1 | No new (AWS) |
| Product analytics | First-party events in central Snowflake | PostHog self-host (R2 option) | HMAC user key only | EU (central account) | No |
| Status page | Better Stack (Czech, EU data) [X1] | Static page off AWS (e.g., Gatus/Upptime) | Subscriber e-mails | EU | Yes (if SaaS) |
| Error monitoring/RUM | Sentry EU region (Frankfurt; US-parented) [X1] | GlitchTip on ECS | Pseudonymous subject hash, scrubbed stacks; no IP | EU | Yes (if SaaS), with transfer assessment |
| Helpdesk | Crisp (French, EU hosting) [X1] | Zammad on ECS | Customer contacts, ticket content | EU | Yes (if SaaS) |
| Feature flags | In-house on REL-102 (OpenFeature interface) | — | None | — | No |

## 5. Owner questions (decisions not already covered by D-01…D-38 or the domain backlogs' §7)

1. **Subprocessors vs self-hosting for SaaS tooling** (consolidates LCH §7 Q4 and OPS §7 Q4). Approve the EU-hosted vendors proposed in §4.3 — status page (Better Stack), error monitoring (Sentry EU region, US-parented, needs a transfer assessment), helpdesk (Crisp) — or require self-hosting (static status page off AWS, GlitchTip, Zammad) at an estimated extra 2–4 operating hours per tool per month and a larger attack surface to patch. *Recommendation*: Better Stack and Crisp (EU companies), Sentry EU; self-host GlitchTip only if no US-parented subprocessor is acceptable. Blocks SAS-005-S01, SAS-010-S01, SAS-011-S01 and the LCH-102 register.
2. **Public price disclosure.** D-17 fixes the model (USD platform fee + managed-spend band, contracted pilot) but not what the pricing page shows: (a) full band table and fees, (b) a "from USD X/month" platform fee with bands on request, or (c) model explained, prices on request. *Recommendation*: (b). Blocks SAS-001-S05.
3. **Write access to customer Snowflake in R2 (PRO-009).** Automated warehouse changes are the main competitive axis after visibility (select, Keebo, Espresso, Slingshot), but they end Bridge's read-only promise and change the DPA, threat model, pentest scope and marketing claims. Go / no-go for R2? *Recommendation*: go, opt-in per warehouse, after three months of R1 operation and PRO-005 guardrail evidence. Until answered, SAS-001/SAS-004 describe Bridge as read-only.
4. **Snowflake Marketplace distribution (PRO-013).** Paying Bridge from Snowflake capacity (Marketplace Capacity Drawdown) is available today only to US-based providers and consumers; the French entity (D-36) is not eligible. Should R2 include the decision spike (and, depending on its outcome, a US entity or a Connected App listing)? *Recommendation*: run the spike in R2 only if pipeline evidence shows capacity-drawdown buyers; otherwise defer.

Answers already requested elsewhere and needed here without a new decision: product domain and brand (INF §7 Q2, UX Q-UX-5) for SAS-001…006; company size and invoicing tool (LCH §7 Q1) for the legal notices in SAS-001-S07.

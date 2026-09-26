# Screen catalog and implementation coverage

87 routes across 26 design units. Every route has a dedicated ASCII composition, KPI definition, table contract, dialog, mobile layout, 13 UX requirements and acceptance checklist. [Foundations](FOUNDATIONS.md) · [Workbench](README.md).

| Group | Screen / route | Detailed ASCII design | Parent |
|---|---|---|---|
| Overview | `/home` — Your spend, in focus | [Design](pages/home.md) | Navigation root |
| Explore | `/explorer` — Cost Explorer | [Design](pages/explorer.md) | Navigation root |
| Explore | `/ledger` — Billing ledger | [Design](pages/explorer.md) | explorer |
| Explore | `/services` — Service breakdown | [Design](pages/explorer.md) | explorer |
| Explore | `/warehouses` — Warehouses | [Design](pages/warehouses.md) | Navigation root |
| Explore | `/warehouse-detail` — ANALYTICS_PROD | [Design](pages/warehouses.md) | warehouses |
| Explore | `/queries` — Queries | [Design](pages/queries.md) | Navigation root |
| Explore | `/query-detail` — Query · q_demo_042 | [Design](pages/queries.md) | queries |
| Explore | `/workloads` — Workloads | [Design](pages/workloads.md) | Navigation root |
| Explore | `/dbt` — dbt intelligence | [Design](pages/workloads.md) | workloads |
| Explore | `/dbt-project` — finance_daily | [Design](pages/workloads.md) | dbt |
| Explore | `/dbt-invocation` — Invocation · inv_0830 | [Design](pages/workloads.md) | dbt-project |
| Explore | `/dbt-model` — fct_sales | [Design](pages/workloads.md) | dbt-project |
| Explore | `/power-bi` — Power BI workloads | [Design](pages/workloads.md) | workloads |
| Explore | `/power-bi-activity` — Activity · pbi_0830 | [Design](pages/workloads.md) | power-bi |
| Explore | `/pipelines` — Native pipelines | [Design](pages/workloads.md) | workloads |
| Explore | `/pipeline-detail` — revenue_refresh | [Design](pages/workloads.md) | pipelines |
| Explore | `/storage` — Storage | [Design](pages/storage.md) | Navigation root |
| Explore | `/storage-detail` — ANALYTICS storage | [Design](pages/storage.md) | storage |
| Explore | `/serverless` — Serverless services | [Design](pages/serverless.md) | Navigation root |
| Explore | `/serverless-detail` — Snowpipe · ingest_events | [Design](pages/serverless.md) | serverless |
| Explore | `/ai` — AI / Cortex | [Design](pages/ai.md) | Navigation root |
| Explore | `/ai-family` — AI functions | [Design](pages/ai.md) | ai |
| Explore | `/ai-execution` — AI execution · ai_042 | [Design](pages/ai.md) | ai-family |
| Explore | `/spcs` — Snowpark Container Services | [Design](pages/spcs.md) | Navigation root |
| Explore | `/spcs-pool` — pool_analytics | [Design](pages/spcs.md) | spcs |
| Allocate | `/tags` — External Tag Studio | [Design](pages/tags.md) | Navigation root |
| Allocate | `/tag-rule` — Rule · Finance ownership | [Design](pages/tags.md) | tags |
| Allocate | `/tag-preview` — Review tagging impact | [Design](pages/tags.md) | tags |
| Allocate | `/allocation` — Allocation Studio | [Design](pages/allocation.md) | Navigation root |
| Allocate | `/allocation-rule` — Rule · Shared idle | [Design](pages/allocation.md) | allocation |
| Allocate | `/allocation-preview` — Allocation simulation | [Design](pages/allocation.md) | allocation |
| Allocate | `/usage-groups` — Usage Groups | [Design](pages/usage-groups.md) | Navigation root |
| Allocate | `/usage-group-detail` — Finance group | [Design](pages/usage-groups.md) | usage-groups |
| Allocate | `/showback` — Showback | [Design](pages/showback.md) | Navigation root |
| Allocate | `/showback-team` — Finance showback | [Design](pages/showback.md) | showback |
| Allocate | `/chargeback` — Chargeback statements | [Design](pages/chargeback.md) | Navigation root |
| Allocate | `/statement` — ST-2026-08-FIN | [Design](pages/chargeback.md) | chargeback |
| Govern | `/reconciliation` — Reconciliation | [Design](pages/reconciliation.md) | Navigation root |
| Govern | `/reconciliation-detail` — Investigate · August difference | [Design](pages/reconciliation.md) | reconciliation |
| Govern | `/budgets` — Budgets | [Design](pages/budgets.md) | Navigation root |
| Govern | `/budget-detail` — September organization plan | [Design](pages/budgets.md) | budgets |
| Govern | `/budget-new` — Create a budget | [Design](pages/budgets.md) | budgets |
| Govern | `/forecast` — Forecast methodology | [Design](pages/budgets.md) | budgets |
| Govern | `/monitors` — Monitors & incidents | [Design](pages/monitors.md) | Navigation root |
| Govern | `/monitor-new` — Create a monitor | [Design](pages/monitors.md) | monitors |
| Govern | `/incident` — Incident · daily warehouse spend | [Design](pages/monitors.md) | monitors |
| Govern | `/reports` — Reports | [Design](pages/reports.md) | Navigation root |
| Govern | `/report-builder` — Executive FinOps report | [Design](pages/reports.md) | reports |
| Govern | `/report-schedule` — Schedule a report | [Design](pages/reports.md) | reports |
| Govern | `/report-history` — Report history | [Design](pages/reports.md) | reports |
| Optimize | `/insights` — Insights | [Design](pages/insights.md) | Navigation root |
| Optimize | `/insight-detail` — Review warehouse scheduling | [Design](pages/insights.md) | insights |
| Optimize | `/actions` — Actions | [Design](pages/actions.md) | Navigation root |
| Optimize | `/action-detail` — Review warehouse schedule | [Design](pages/actions.md) | actions |
| Optimize | `/savings` — Savings, verified | [Design](pages/savings.md) | Navigation root |
| Optimize | `/savings-detail` — Warehouse efficiency verification | [Design](pages/savings.md) | savings |
| Overview | `/dashboards` — Dashboards | [Design](pages/dashboards.md) | Navigation root |
| Overview | `/dashboard-builder` — Executive dashboard | [Design](pages/dashboards.md) | dashboards |
| Platform | `/data-health` — Data Health | [Design](pages/data-health.md) | Navigation root |
| Platform | `/source-detail` — Query history coverage | [Design](pages/data-health.md) | data-health |
| Platform | `/sync-history` — Synchronization history | [Design](pages/data-health.md) | data-health |
| Platform | `/integrations` — Integration Health | [Design](pages/integrations.md) | Navigation root |
| Platform | `/connection-detail` — Acme Snowflake connection | [Design](pages/integrations.md) | integrations |
| Platform | `/onboarding` — Connect your Snowflake organization | [Design](pages/integrations.md) | integrations |
| Settings | `/settings` — Workspace settings | [Design](pages/settings.md) | Navigation root |
| Settings | `/settings-people` — People & teams | [Design](pages/settings.md) | settings |
| Settings | `/settings-security` — Security & SSO | [Design](pages/settings.md) | settings |
| Settings | `/settings-audit` — Audit log | [Design](pages/settings.md) | settings |
| Settings | `/settings-privacy` — Privacy & retention | [Design](pages/settings.md) | settings |
| Settings | `/settings-notifications` — Notification destinations | [Design](pages/settings.md) | settings |
| Settings | `/settings-billing` — Subscription & billing | [Design](pages/settings.md) | settings |
| Settings | `/support` — Help & support | [Design](pages/settings.md) | settings |
| Access | `/sign-in` — Welcome to Bridge | [Design](pages/sign-in.md) | Navigation root |
| Access | `/mfa` — Verify your sign-in | [Design](pages/sign-in.md) | sign-in |
| Explore | `/procedures` — Stored procedures | [Design](pages/workloads.md) | workloads |
| Explore | `/dynamic-tables` — Dynamic tables | [Design](pages/workloads.md) | workloads |
| Explore | `/native-apps` — Native Applications | [Design](pages/workloads.md) | workloads |
| Explore | `/custom-apps` — Custom applications | [Design](pages/workloads.md) | workloads |
| Explore | `/ad-hoc` — Ad hoc activity | [Design](pages/workloads.md) | workloads |
| Explore | `/query-executions` — Execution explorer | [Design](pages/queries.md) | queries |
| Explore | `/warehouse-performance` — Warehouse performance | [Design](pages/warehouses.md) | warehouses |
| Explore | `/ai-search` — Cortex Search | [Design](pages/ai.md) | ai |
| Explore | `/ai-analyst` — Cortex Analyst | [Design](pages/ai.md) | ai |
| Explore | `/spcs-service` — forecast_api service | [Design](pages/spcs.md) | spcs-pool |
| Settings | `/settings-organizations` — Organizations & accounts | [Design](pages/settings.md) | settings |
| Settings | `/settings-roles` — Roles & access scopes | [Design](pages/settings.md) | settings |

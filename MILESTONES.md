# Production-oriented milestones

No implementation milestone is currently passed. The following are acceptance gates for future implementation, not an optimistic calendar.

| ID | Entry criteria | Deliverable and measurable exit criteria |
|---|---|---|
| M0 Engineering foundation | PRD and ownership accepted | Reproducible clean checkout; lockfiles; fixture harness; documentation validation; isolated AWS/Snowflake environment design; CI identities and bootstrap plan verified |
| M1 Secure SaaS control plane | M0 | Private infrastructure; Cognito login/MFA; tenant/org/account model; scoped RBAC; PostgreSQL RLS; migration and connection budgets; audit/outbox; cross-tenant CRUD denial proved |
| M2 Snowflake connectivity | M1 | Per-account WIF positive/negative/revocation tests; org discovery and standalone fallback; capability matrix and least-privilege scripts; source privacy defaults; no persistent credential |
| M3 Durable ingestion | M2 and approved source contracts | Typed streaming → S3 manifest → Snowpipe → accepted RAW; overlap, empty-window, duplicate, crash, schema drift, replay and catch-up tests; fair Dagster execution; truthful coverage UX |
| M4 Canonical FinOps ledger | M3 | Deterministic dbt models; additive service registry; signed adjustments; prices/currencies; numerical golden fixtures; no double counting; available billing-source reconciliation with visible gaps |
| M5 Cost observability | M4 and serving security | Semantic APIs, safe pagination/jobs/cache; Home and all Explore pages; dbt/PBI/task hierarchies; Explain This Number; partial/denied/unknown states; a restricted user sees only permitted data |
| M6 Allocation and accountability | M5 | Versioned Tag Studio and Usage Groups; simulations and conflict handling; conservation per group set; scoped showback; immutable chargeback statements with corrections and evidence |
| M7 Budgets, monitors and reports | M6 and delivery outbox | Forecast validation; generic monitor types; Email/Slack/Teams/Webhook sandbox proofs; suppression/recovery; eight report templates, PDF/PNG/CSV, schedule/DST and permission-revocation tests |
| M8 Insights and verified savings | M5, GOV-005 shared statistics and reliable baselines | Evidence-backed supported insight families; confidence/coverage thresholds; tracked human actions; frozen baselines; normalized savings with overlap controls; no estimated-to-realized relabeling |
| M9 Enterprise operations | M7 and M8 | SLO dashboards; tenant isolation attack suite; privacy deletion/retention; backup restoration; incident drills; load/cost tests; audit verification and no unresolved critical security defect |
| M10 Production readiness | M9 | Rehearsed AWS release and rollback; restore evidence; support runbooks; release candidate signed off; production secrets/identities verified; commercial/legal onboarding pack ready |
| M11 First customer onboarding | M10 and customer authorization | Organization connected, selected accounts validated; requested/available history disclosed; reconciliation signed; ownership, budget, monitor and report exercised; first-value review accepted |
| M12 First production release | M11 and commercial acceptance | Versioned release record; first paying entitlement and payment evidence; production smoke suite; daily first-week and 30-day validation plan assigned; remaining risks and rollback owner recorded |

## Gating rules

- Any cross-tenant disclosure, unresolved additive ledger double count, secret leakage or unrecoverable accepted batch blocks production.
- Missing optional source capability can degrade a feature only when UX, exports and financial coverage disclose it. Missing required billing references block invoice reconciliation claims, not all consumption analysis.
- First customer may use manual commercial invoicing; subscription/entitlement state must still be auditable and idempotent. Never claim payment without evidence.
- One-year synchronization means all source-retained, authorized history in the requested window, with explicit gaps. Snapshot-only metadata begins at enrollment.
- Targets (latency, freshness, recovery, gross margin) are engineering objectives until demonstrated. Legal SLAs require separate approval.

## Milestone evidence package

Each exit record includes task IDs, implementation commit, environment/version manifest, test evidence, outstanding capability gaps, security and finance sign-off, rollback procedure and next milestone authorization. Maintain status durably; never infer completion from merged documentation.

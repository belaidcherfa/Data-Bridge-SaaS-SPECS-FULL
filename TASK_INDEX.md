# Implementation task index

151 tasks;20 domains; all implementation statuses **NOT_STARTED**. This is a stable topological order, not a promise that every task must run serially. A task becomes ready only when all dependencies have accepted implementation evidence. Parallel work may use independent ready tasks while respecting database/schema ownership and release gates.

The [machine index](docs/00-project/task-index.json) owns IDs, hierarchy, dependencies and status. Each domain has one named delivery epic; each listed feature has a concrete user story and independently validated implementation task. Numbered micro-tasks have stable IDs `<task>.<ordinal>` in the machine index; their detailed steps, validation and DoD are in the linked task. Split a task into explicitly indexed children before coding if its independently deployable work exceeds a focused session; never hide extra work in an untracked checklist.

| Order | Task / feature | Epic | Milestone | Dependencies |
|---|---|---|---|---|
| 1 | [FND-001 — Create monorepo boundaries and dependency rules](docs/tasks/FND/FND-001.md) | E-FND-01 | M0 | None |
| 2 | [FND-002 — Resolve and lock the compatible runtime matrix](docs/tasks/FND/FND-002.md) | E-FND-01 | M0 | FND-001 |
| 3 | [FND-003 — Build safe local Compose and developer onboarding](docs/tasks/FND/FND-003.md) | E-FND-01 | M0 | FND-001, FND-002 |
| 4 | [FND-004 — Create golden synthetic tenant and finance fixtures](docs/tasks/FND/FND-004.md) | E-FND-01 | M0 | FND-003 |
| 5 | [FND-005 — Implement validation dispatcher and evidence schema](docs/tasks/FND/FND-005.md) | E-FND-01 | M0 | FND-004 |
| 6 | [FND-006 — Establish CI quality gates and agent working rules](docs/tasks/FND/FND-006.md) | E-FND-01 | M0 | FND-005 |
| 7 | [UX-001 — Create light-theme component system and application shell](docs/tasks/UX/UX-001.md) | E-UX-01 | M0 | FND-003 |
| 8 | [INF-001 — Bootstrap AWS accounts, state and environment guards](docs/tasks/INF/INF-001.md) | E-INF-01 | M1 | FND-006 |
| 9 | [INF-002 — Create VPC, endpoints and controlled egress](docs/tasks/INF/INF-002.md) | E-INF-01 | M1 | INF-001 |
| 10 | [INF-003 — Provision KMS, buckets, queues and retention boundaries](docs/tasks/INF/INF-003.md) | E-INF-01 | M1 | INF-002 |
| 11 | [INF-004 — Provision Aurora and Redis with safe resource budgets](docs/tasks/INF/INF-004.md) | E-INF-01 | M1 | INF-002, INF-003 |
| 12 | [INF-005 — Build ECS base services and role separation](docs/tasks/INF/INF-005.md) | E-INF-01 | M1 | INF-003, INF-004 |
| 13 | [INF-006 — Configure edge, DNS, TLS and private operations access](docs/tasks/INF/INF-006.md) | E-INF-01 | M1 | INF-005 |
| 14 | [INF-007 — Create OIDC deployment pipeline and staged rollback](docs/tasks/INF/INF-007.md) | E-INF-01 | M1 | INF-005, INF-006 |
| 15 | [INF-008 — Provision central Snowflake environments and service roles](docs/tasks/INF/INF-008.md) | E-INF-01 | M1 | INF-007 |
| 16 | [SEC-001 — Model threats and classify sensitive data](docs/tasks/SEC/SEC-001.md) | E-SEC-01 | M1 | INF-002, FND-004 |
| 17 | [SEC-002 — Implement Cognito login, sessions and local MFA](docs/tasks/SEC/SEC-002.md) | E-SEC-01 | M1 | SEC-001, INF-006, UX-001 |
| 18 | [SEC-003 — Add tenant-bound SAML and OIDC SSO](docs/tasks/SEC/SEC-003.md) | E-SEC-01 | M1 | SEC-002, UX-001 |
| 19 | [SEC-004 — Implement scoped RBAC and tenant RLS foundation](docs/tasks/SEC/SEC-004.md) | E-SEC-01 | M1 | SEC-002, INF-004 |
| 20 | [CTL-001 — Extend tenant, organization, account and team schemas](docs/tasks/CTL/CTL-001.md) | E-CTL-01 | M1 | SEC-004 |
| 21 | [CTL-002 — Implement migrations, indexes and bounded connection pools](docs/tasks/CTL/CTL-002.md) | E-CTL-01 | M1 | CTL-001, INF-004 |
| 22 | [SEC-005 — Provision identity-bound Snowflake serving policies](docs/tasks/SEC/SEC-005.md) | E-SEC-01 | M1 | SEC-004, INF-005, INF-008 |
| 23 | [SEC-006 — Enforce revocation across sessions, jobs and cache](docs/tasks/SEC/SEC-006.md) | E-SEC-01 | M1 | SEC-004, SEC-005 |
| 24 | [SEC-007 — Sanitize SQL, tags and errors before persistence](docs/tasks/SEC/SEC-007.md) | E-SEC-01 | M1 | SEC-001, FND-004 |
| 25 | [SEC-008 — Create audit trail and early isolation attack suite](docs/tasks/SEC/SEC-008.md) | E-SEC-01 | M1 | SEC-006, SEC-007 |
| 26 | [CTL-003 — Create scoped CRUD, invitations and optimistic concurrency](docs/tasks/CTL/CTL-003.md) | E-CTL-01 | M1 | CTL-001, SEC-002, SEC-008, UX-001 |
| 27 | [CTL-004 — Implement transactional outbox and fenced job leases](docs/tasks/CTL/CTL-004.md) | E-CTL-01 | M1 | CTL-002, CTL-003 |
| 28 | [CTL-005 — Publish immutable analytical configuration snapshots](docs/tasks/CTL/CTL-005.md) | E-CTL-01 | M1 | CTL-004, INF-003 |
| 29 | [CTL-006 — Implement scoped Redis keys and safe degradation](docs/tasks/CTL/CTL-006.md) | E-CTL-01 | M1 | CTL-004, SEC-006 |
| 30 | [CTL-007 — Add saved views, dashboards and commercial control records](docs/tasks/CTL/CTL-007.md) | E-CTL-01 | M1 | CTL-003, CTL-005, UX-001 |
| 31 | [CON-001 — Register account identities and controlled WIF task roles](docs/tasks/CON/CON-001.md) | E-CON-01 | M2 | CTL-001, INF-008, SEC-004 |
| 32 | [CON-002 — Prove WIF connector and dbt compatibility live](docs/tasks/CON/CON-002.md) | E-CON-01 | M2 | CON-001, FND-002 |
| 33 | [CON-003 — Generate least-privilege installation and revoke scripts](docs/tasks/CON/CON-003.md) | E-CON-01 | M2 | CON-002 |
| 34 | [CON-004 — Discover organizations, accounts and lifecycle changes](docs/tasks/CON/CON-004.md) | E-CON-01 | M2 | CON-003, CTL-001, UX-001 |
| 35 | [CON-005 — Probe capabilities, source schemas and permission gaps](docs/tasks/CON/CON-005.md) | E-CON-01 | M2 | CON-004, SEC-007 |
| 36 | [CON-006 — Build connection wizard, pause, revoke and recovery UX](docs/tasks/CON/CON-006.md) | E-CON-01 | M2 | CON-005, SEC-006, UX-001 |
| 37 | [ING-001 — Create executable source contracts and registry validation](docs/tasks/ING/ING-001.md) | E-ING-01 | M3 | CON-005, FND-004 |
| 38 | [ING-002 — Implement UTC window planning, overlap and source horizons](docs/tasks/ING/ING-002.md) | E-ING-01 | M3 | ING-001, CTL-004 |
| 39 | [ING-003 — Build bounded Arrow extraction with WIF cancellation](docs/tasks/ING/ING-003.md) | E-ING-01 | M3 | ING-002, CON-002, SEC-007 |
| 40 | [ING-004 — Implement typed Parquet schema and size rotation](docs/tasks/ING/ING-004.md) | E-ING-01 | M3 | ING-003 |
| 41 | [ING-005 — Commit S3 batches and validated manifests](docs/tasks/ING/ING-005.md) | E-ING-01 | M3 | ING-004, INF-003 |
| 42 | [ING-006 — Provision typed RAW tables, stages and Snowpipe](docs/tasks/ING/ING-006.md) | E-ING-01 | M3 | ING-005, INF-008 |
| 43 | [ING-007 — Build file receipts and complete-batch acceptance](docs/tasks/ING/ING-007.md) | E-ING-01 | M3 | ING-006, CTL-004 |
| 44 | [ING-008 — Advance fenced checkpoints and deterministic source revisions](docs/tasks/ING/ING-008.md) | E-ING-01 | M3 | ING-007, ING-002 |
| 45 | [ING-009 — Handle schema drift and source BCR changes](docs/tasks/ING/ING-009.md) | E-ING-01 | M3 | ING-008 |
| 46 | [ING-010 — Plan historical backfills and catch-up with fair admission](docs/tasks/ING/ING-010.md) | E-ING-01 | M3 | ING-009, CON-006 |
| 47 | [ING-011 — Implement journal replay and anti-entropy repair](docs/tasks/ING/ING-011.md) | E-ING-01 | M3 | ING-010 |
| 48 | [ING-012 — Add bounded hot history and truthful Data Health UX](docs/tasks/ING/ING-012.md) | E-ING-01 | M3 | ING-011, UX-001 |
| 49 | [OPS-001 — Instrument shared telemetry and operational dashboards](docs/tasks/OPS/OPS-001.md) | E-OPS-01 | M3 | INF-005, CTL-004 |
| 50 | [ORC-001 — Deploy private OSS control services and metadata database](docs/tasks/ORC/ORC-001.md) | E-ORC-01 | M3 | INF-007, CTL-002 |
| 51 | [ORC-002 — Define generic assets and bounded partition catalog](docs/tasks/ORC/ORC-002.md) | E-ORC-01 | M3 | ORC-001, ING-008 |
| 52 | [ORC-003 — Implement fair queues, schedules and idempotent sensors](docs/tasks/ORC/ORC-003.md) | E-ORC-01 | M3 | ORC-002, CTL-004 |
| 53 | [ORC-004 — Integrate dbt assets and Python result dependencies](docs/tasks/ORC/ORC-004.md) | E-ORC-01 | M3 | ORC-003, ING-009, CON-002 |
| 54 | [ORC-005 — Publish coherent datasets and version notifications](docs/tasks/ORC/ORC-005.md) | E-ORC-01 | M3 | ORC-004, CTL-005, CTL-006 |
| 55 | [ORC-006 — Exercise backfill, cancellation and selective recovery](docs/tasks/ORC/ORC-006.md) | E-ORC-01 | M3 | ORC-005, ING-011 |
| 56 | [DBT-001 — Bootstrap dbt Core project, profiles and model contracts](docs/tasks/DBT/DBT-001.md) | E-DBT-01 | M4 | ORC-004, ING-008 |
| 57 | [DBT-002 — Implement staging dedup and complete-partition revisions](docs/tasks/DBT/DBT-002.md) | E-DBT-01 | M4 | DBT-001, ING-008 |
| 58 | [DBT-003 — Resolve resource history, account membership and workload joins](docs/tasks/DBT/DBT-003.md) | E-DBT-01 | M4 | DBT-002, CTL-001 |
| 59 | [DBT-004 — Implement bounded incremental merges and shadow rebuild](docs/tasks/DBT/DBT-004.md) | E-DBT-01 | M4 | DBT-003, ORC-005 |
| 60 | [DBT-005 — Build golden financial tests and tenant-safe CI](docs/tasks/DBT/DBT-005.md) | E-DBT-01 | M4 | DBT-004, FND-005, SEC-008 |
| 61 | [DBT-006 — Build serving partition revisions and explainable lineage](docs/tasks/DBT/DBT-006.md) | E-DBT-01 | M4 | DBT-005, SEC-005 |
| 62 | [FIN-001 — Define charge schema, service authority and exact decimal fixtures](docs/tasks/FIN/FIN-001.md) | E-FIN-01 | M4 | DBT-005, ING-001 |
| 63 | [FIN-002 — Normalize billing, rate sheets and approved pricing](docs/tasks/FIN/FIN-002.md) | E-FIN-01 | M4 | FIN-001, DBT-002 |
| 64 | [FIN-003 — Implement classic warehouse compute, query attribution and idle](docs/tasks/FIN/FIN-003.md) | E-FIN-01 | M4 | FIN-002, DBT-003 |
| 65 | [FIN-004 — Implement Adaptive query-hour compute and maturity](docs/tasks/FIN/FIN-004.md) | E-FIN-01 | M4 | FIN-003 |
| 66 | [FIN-005 — Implement adjusted cloud services and signed billing entries](docs/tasks/FIN/FIN-005.md) | E-FIN-01 | M4 | FIN-002 |
| 67 | [FIN-006 — Implement storage classes, snapshots and billed reconciliation](docs/tasks/FIN/FIN-006.md) | E-FIN-01 | M4 | FIN-002, DBT-003 |
| 68 | [FIN-008 — Implement directional transfer and replication charges](docs/tasks/FIN/FIN-008.md) | E-FIN-01 | M4 | FIN-002, FIN-006 |
| 69 | [FIN-011 — Implement file snowpipe and hidden pipe attribution](docs/tasks/FIN/FIN-011.md) | E-FIN-01 | M4 | FIN-002, DBT-005 |
| 70 | [FIN-012 — Implement snowpipe streaming channel and client components](docs/tasks/FIN/FIN-012.md) | E-FIN-01 | M4 | FIN-002, DBT-005 |
| 71 | [FIN-013 — Implement serverless tasks and alerts](docs/tasks/FIN/FIN-013.md) | E-FIN-01 | M4 | FIN-002, DBT-005 |
| 72 | [FIN-014 — Implement automatic clustering](docs/tasks/FIN/FIN-014.md) | E-FIN-01 | M4 | FIN-002, DBT-005 |
| 73 | [FIN-015 — Implement search optimization](docs/tasks/FIN/FIN-015.md) | E-FIN-01 | M4 | FIN-002, DBT-005 |
| 74 | [FIN-016 — Implement materialized view maintenance](docs/tasks/FIN/FIN-016.md) | E-FIN-01 | M4 | FIN-002, DBT-005 |
| 75 | [FIN-017 — Implement query acceleration](docs/tasks/FIN/FIN-017.md) | E-FIN-01 | M4 | FIN-002, DBT-005 |
| 76 | [FIN-007 — Validate independent serverless service inclusion and totals](docs/tasks/FIN/FIN-007.md) | E-FIN-01 | M4 | FIN-011, FIN-012, FIN-013, FIN-014, FIN-015, FIN-016, FIN-017 |
| 77 | [FIN-018 — Implement current Cortex services and non-overlapping AI attribution](docs/tasks/FIN/FIN-018.md) | E-FIN-01 | M4 | FIN-002, DBT-005 |
| 78 | [FIN-019 — Implement SPCS compute-pool and application attribution](docs/tasks/FIN/FIN-019.md) | E-FIN-01 | M4 | FIN-002, DBT-005 |
| 79 | [FIN-020 — Implement marketplace purchase and native-app cost separation](docs/tasks/FIN/FIN-020.md) | E-FIN-01 | M4 | FIN-002, FIN-019 |
| 80 | [FIN-021 — Cover new billable services, organization fees and unmapped spend](docs/tasks/FIN/FIN-021.md) | E-FIN-01 | M4 | FIN-002 |
| 81 | [FIN-009 — Build reconciliation controls and financial health UX](docs/tasks/FIN/FIN-009.md) | E-FIN-01 | M4 | FIN-004, FIN-005, FIN-006, FIN-007, FIN-008, FIN-018, FIN-019, FIN-020, FIN-021 |
| 82 | [FIN-010 — Implement period close, corrections and financial evidence retention](docs/tasks/FIN/FIN-010.md) | E-FIN-01 | M4 | FIN-009, SEC-006 |
| 83 | [OPS-002 — Implement publication quality gates and financial canaries](docs/tasks/OPS/OPS-002.md) | E-OPS-01 | M4 | DBT-006, FIN-009, OPS-001 |
| 84 | [API-001 — Implement metric and dimension registry with compatibility rules](docs/tasks/API/API-001.md) | E-API-01 | M5 | FIN-009, DBT-006 |
| 85 | [API-002 — Build safe analytical planner and Snowflake query broker](docs/tasks/API/API-002.md) | E-API-01 | M5 | API-001, SEC-005, CTL-006 |
| 86 | [API-003 — Implement response metadata, stable pagination and cache](docs/tasks/API/API-003.md) | E-API-01 | M5 | API-002 |
| 87 | [API-004 — Build asynchronous analysis jobs and cancellation](docs/tasks/API/API-004.md) | E-API-01 | M5 | API-003, CTL-004, ORC-006 |
| 88 | [API-005 — Implement Explain This Number lineage endpoint](docs/tasks/API/API-005.md) | E-API-01 | M5 | API-003, FIN-010 |
| 89 | [API-006 — Add public API credentials, quotas and contract release tests](docs/tasks/API/API-006.md) | E-API-01 | M5 | API-004, API-005, SEC-008 |
| 90 | [UX-002 — Integrate authenticated scope state and semantic query components](docs/tasks/UX/UX-002.md) | E-UX-01 | M5 | UX-001, API-003, SEC-006 |
| 91 | [ONB-001 — Build resumable onboarding checklist and guided progress](docs/tasks/ONB/ONB-001.md) | E-ONB-01 | M5 | CON-006, ING-012, UX-002 |
| 92 | [UX-003 — Build Home and executive drivers experience](docs/tasks/UX/UX-003.md) | E-UX-01 | M5 | UX-002, FIN-009 |
| 93 | [UX-004 — Build Cost Explorer with pivots and saved analyses](docs/tasks/UX/UX-004.md) | E-UX-01 | M5 | UX-003, CTL-007, API-005 |
| 94 | [UX-005 — Build warehouse and query cost deep dives](docs/tasks/UX/UX-005.md) | E-UX-01 | M5 | UX-004, FIN-004 |
| 95 | [UX-006 — Build storage and serverless resource views](docs/tasks/UX/UX-006.md) | E-UX-01 | M5 | UX-004, FIN-006, FIN-007 |
| 96 | [UX-007 — Build AI/Cortex and SPCS analytical experiences](docs/tasks/UX/UX-007.md) | E-UX-01 | M5 | UX-004, FIN-018, FIN-019 |
| 97 | [UX-008 — Validate product states, accessibility and navigation end to end](docs/tasks/UX/UX-008.md) | E-UX-01 | M5 | UX-005, UX-006, UX-007 |
| 98 | [WRK-001 — Implement versioned workload classifier and evidence model](docs/tasks/WRK/WRK-001.md) | E-WRK-01 | M5 | DBT-003, SEC-007, API-001 |
| 99 | [WRK-002 — Build dbt project, invocation and model intelligence](docs/tasks/WRK/WRK-002.md) | E-WRK-01 | M5 | WRK-001, UX-005 |
| 100 | [WRK-003 — Build Power BI activity and mode intelligence](docs/tasks/WRK/WRK-003.md) | E-WRK-01 | M5 | WRK-001, UX-005 |
| 101 | [WRK-004 — Build tasks, procedures and other workload execution graphs](docs/tasks/WRK/WRK-004.md) | E-WRK-01 | M5 | WRK-001, FIN-013, UX-005 |
| 102 | [WRK-005 — Implement workload comparison and on-demand deep evidence](docs/tasks/WRK/WRK-005.md) | E-WRK-01 | M5 | WRK-002, WRK-003, WRK-004, API-004 |
| 103 | [ALC-001 — Create dimension registry and external tag fact model](docs/tasks/ALC/ALC-001.md) | E-ALC-01 | M6 | FIN-009, WRK-001, CTL-005 |
| 104 | [ALC-002 — Implement bounded rule evaluation and deterministic conflicts](docs/tasks/ALC/ALC-002.md) | E-ALC-01 | M6 | ALC-001 |
| 105 | [ALC-003 — Build simulation, review and ruleset publication](docs/tasks/ALC/ALC-003.md) | E-ALC-01 | M6 | ALC-002, API-004 |
| 106 | [ALC-004 — Implement usage group sets and effective hierarchies](docs/tasks/ALC/ALC-004.md) | E-ALC-01 | M6 | ALC-003, CTL-003 |
| 107 | [ALC-005 — Implement allocation methods and conservation](docs/tasks/ALC/ALC-005.md) | E-ALC-01 | M6 | ALC-004, FIN-010 |
| 108 | [ALC-006 — Build allocation studio and quality remediation](docs/tasks/ALC/ALC-006.md) | E-ALC-01 | M6 | ALC-005, UX-004 |
| 109 | [ALC-007 — Build scoped showback portal](docs/tasks/ALC/ALC-007.md) | E-ALC-01 | M6 | ALC-006, UX-003 |
| 110 | [ALC-008 — Implement chargeback statements, rounding and adjustments](docs/tasks/ALC/ALC-008.md) | E-ALC-01 | M6 | ALC-007, FIN-010, API-005 |
| 111 | [GOV-001 — Implement scoped budgets and actuals](docs/tasks/GOV/GOV-001.md) | E-GOV-01 | M7 | ALC-007, API-001 |
| 112 | [GOV-002 — Implement calibrated forecasting and model selection](docs/tasks/GOV/GOV-002.md) | E-GOV-01 | M7 | GOV-001, WRK-005 |
| 113 | [GOV-003 — Define monitor DSL, validation and schedule planner](docs/tasks/GOV/GOV-003.md) | E-GOV-01 | M7 | GOV-001, API-006 |
| 114 | [GOV-004 — Implement partition evaluation, incident state and suppression](docs/tasks/GOV/GOV-004.md) | E-GOV-01 | M7 | GOV-003, GOV-002, ORC-005 |
| 115 | [GOV-005 — Implement robust anomaly candidates and quality gates](docs/tasks/GOV/GOV-005.md) | E-GOV-01 | M7 | GOV-004 |
| 116 | [GOV-006 — Implement Email, Slack, Teams and secure webhook adapters](docs/tasks/GOV/GOV-006.md) | E-GOV-01 | M7 | GOV-004, SEC-008, INF-003 |
| 117 | [GOV-007 — Implement delivery outbox, retries, DLQ and premium alerts](docs/tasks/GOV/GOV-007.md) | E-GOV-01 | M7 | GOV-006, CTL-004 |
| 118 | [GOV-008 — Build incident center and governance E2E acceptance](docs/tasks/GOV/GOV-008.md) | E-GOV-01 | M7 | GOV-007, UX-008 |
| 119 | [RPT-001 — Define report schema and reusable component contracts](docs/tasks/RPT/RPT-001.md) | E-RPT-01 | M7 | API-001, API-004, UX-001 |
| 120 | [RPT-002 — Implement isolated snapshot and render workers](docs/tasks/RPT/RPT-002.md) | E-RPT-01 | M7 | RPT-001, ORC-003, INF-004 |
| 121 | [RPT-003 — Implement and visually qualify eight report templates](docs/tasks/RPT/RPT-003.md) | E-RPT-01 | M7 | RPT-002, ALC-008, GOV-008, WRK-005, UX-007 |
| 122 | [RPT-004 — Implement calendar schedules and report occurrence planning](docs/tasks/RPT/RPT-004.md) | E-RPT-01 | M7 | RPT-003, GOV-007 |
| 123 | [RPT-005 — Implement report history, secure access and retention](docs/tasks/RPT/RPT-005.md) | E-RPT-01 | M7 | RPT-004, SEC-008, CTL-007 |
| 124 | [INS-001 — Build insight registry and evidence publication](docs/tasks/INS/INS-001.md) | E-INS-01 | M8 | WRK-005, API-005, ORC-005, GOV-005 |
| 125 | [INS-002 — Implement warehouse optimization detectors](docs/tasks/INS/INS-002.md) | E-INS-01 | M8 | INS-001, FIN-004, UX-005 |
| 126 | [INS-003 — Implement query and pipeline optimization detectors](docs/tasks/INS/INS-003.md) | E-INS-01 | M8 | INS-001, WRK-002, WRK-004 |
| 127 | [INS-004 — Implement storage and ingestion optimization detectors](docs/tasks/INS/INS-004.md) | E-INS-01 | M8 | INS-001, FIN-006, FIN-011, FIN-012 |
| 128 | [INS-005 — Implement Cortex and container optimization detectors](docs/tasks/INS/INS-005.md) | E-INS-01 | M8 | INS-001, FIN-018, FIN-019, UX-007 |
| 129 | [INS-006 — Implement action workflow and immutable baseline capture](docs/tasks/INS/INS-006.md) | E-INS-01 | M8 | INS-002, INS-003, INS-004, INS-005, CTL-004 |
| 130 | [INS-007 — Measure normalized savings and finish optimization acceptance](docs/tasks/INS/INS-007.md) | E-INS-01 | M8 | INS-006, FIN-009 |
| 131 | [OPS-003 — Qualify SLOs, synthetic probes and alert routing](docs/tasks/OPS/OPS-003.md) | E-OPS-01 | M9 | OPS-001, GOV-007, RPT-005 |
| 132 | [OPS-004 — Run adversarial tenant isolation and security qualification](docs/tasks/OPS/OPS-004.md) | E-OPS-01 | M9 | SEC-006, SEC-008, API-006, RPT-005, GOV-007 |
| 133 | [OPS-005 — Implement retention, deletion and audit verification](docs/tasks/OPS/OPS-005.md) | E-OPS-01 | M9 | SEC-007, SEC-008, RPT-005, CTL-007 |
| 134 | [OPS-006 — Rehearse control-plane backup and recovery](docs/tasks/OPS/OPS-006.md) | E-OPS-01 | M9 | INF-004, INF-003, INF-006, CTL-004, OPS-005 |
| 135 | [OPS-007 — Implement analytical snapshots and replay recovery drill](docs/tasks/OPS/OPS-007.md) | E-OPS-01 | M9 | ING-011, FIN-010, OPS-005 |
| 136 | [OPS-008 — Benchmark concurrency, noisy-neighbor protection and capacity](docs/tasks/OPS/OPS-008.md) | E-OPS-01 | M9 | API-004, ORC-006, OPS-002, RPT-005 |
| 137 | [OPS-009 — Measure Bridge unit economics and internal cost allocation](docs/tasks/OPS/OPS-009.md) | E-OPS-01 | M9 | OPS-008, FIN-002 |
| 138 | [OPS-010 — Publish support runbooks and run incident exercises](docs/tasks/OPS/OPS-010.md) | E-OPS-01 | M9 | OPS-003, OPS-004, OPS-006, OPS-007 |
| 139 | [ONB-002 — Prepare customer and support documentation with rehearsal](docs/tasks/ONB/ONB-002.md) | E-ONB-01 | M9 | ONB-001, OPS-010 |
| 140 | [OPS-011 — Complete cross-product QA and release evidence matrix](docs/tasks/OPS/OPS-011.md) | E-OPS-01 | M9 | OPS-004, OPS-008, OPS-010, INS-007, RPT-005, GOV-008, ALC-008, UX-008 |
| 141 | [REL-001 — Qualify complete CI/CD promotion and schema compatibility](docs/tasks/REL/REL-001.md) | E-REL-01 | M10 | INF-007, OPS-011 |
| 142 | [REL-002 — Rehearse production deployment and rollback](docs/tasks/REL/REL-002.md) | E-REL-01 | M10 | REL-001, OPS-010 |
| 143 | [REL-003 — Assemble operational, commercial and support readiness pack](docs/tasks/REL/REL-003.md) | E-REL-01 | M10 | REL-002, OPS-009 |
| 144 | [LCH-001 — Define plans, entitlements and manual billing workflow](docs/tasks/LCH/LCH-001.md) | E-LCH-01 | M10 | REL-003, CTL-007 |
| 145 | [REL-004 — Approve immutable release candidate and production gate](docs/tasks/REL/REL-004.md) | E-REL-01 | M10 | REL-003 |
| 146 | [ONB-003 — Prepare authorized first-customer environment and identities](docs/tasks/ONB/ONB-003.md) | E-ONB-01 | M11 | REL-004, ONB-002, LCH-001 |
| 147 | [ONB-004 — Complete historical synchronization and customer reconciliation](docs/tasks/ONB/ONB-004.md) | E-ONB-01 | M11 | ONB-003, ING-010, FIN-010 |
| 148 | [ONB-005 — Complete first-value workshop and customer acceptance](docs/tasks/ONB/ONB-005.md) | E-ONB-01 | M11 | ONB-004, ALC-008, GOV-008, INS-007, RPT-005 |
| 149 | [LCH-002 — Verify first customer acceptance and payment evidence](docs/tasks/LCH/LCH-002.md) | E-LCH-01 | M12 | ONB-005, LCH-001 |
| 150 | [LCH-003 — Publish first production release and perform monitored rollout](docs/tasks/LCH/LCH-003.md) | E-LCH-01 | M12 | LCH-002, REL-004 |
| 151 | [LCH-004 — Execute first-week and day30 validation with improvement backlog](docs/tasks/LCH/LCH-004.md) | E-LCH-01 | M12 | LCH-003 |

## Resuming implementation

Read the task's canonical domain contract, exact prerequisites and relevant ADRs. Inspect current repository state before editing. Claim one READY task, record branch/worktree and intended outputs; implement the smallest reversible increment; run the specified local and live gates; record evidence and rollback result. Update the JSON status and human index together. A blocked vendor capability needs a scoped reason and next action, not a fabricated PASS. The first task is FND-001; UX-001 is deliberately an M0 design-system prerequisite even though most UI tasks arrive at M5.

# Requirements and PRD traceability

All59 requested deep dives and all159 numbered sections of the [supplied PRD](PRD.md) have explicit implementation ownership. Coverage here means a reviewed specification and validation requirement exists, not that the product is implemented. The [task index](../../TASK_INDEX.md) gives execution order. Sections146/147 are explicitly future scope: this release preserves safe interfaces and evidence boundaries but does not implement a Copilot or autonomous customer mutations.

## User-requested coverage

| Requirement | Coverage | Task specifications / validation owners |
|---|---|---|
| 1 | Repository/bootstrap and engineering standards | [FND-001](../tasks/FND/FND-001.md), [FND-006](../tasks/FND/FND-006.md) |
| 2 | Local development environment | [FND-002](../tasks/FND/FND-002.md), [FND-003](../tasks/FND/FND-003.md), [FND-005](../tasks/FND/FND-005.md) |
| 3 | AWS accounts/environments and Terraform | [INF-001](../tasks/INF/INF-001.md), [INF-007](../tasks/INF/INF-007.md), [INF-008](../tasks/INF/INF-008.md) |
| 4 | VPC/network/security architecture | [INF-002](../tasks/INF/INF-002.md), [INF-006](../tasks/INF/INF-006.md), [SEC-001](../tasks/SEC/SEC-001.md) |
| 5 | Cognito/SSO/MFA | [SEC-002](../tasks/SEC/SEC-002.md), [SEC-003](../tasks/SEC/SEC-003.md) |
| 6 | Tenant model/users/teams/RBAC/RLS | [CTL-001](../tasks/CTL/CTL-001.md), [CTL-003](../tasks/CTL/CTL-003.md), [SEC-004](../tasks/SEC/SEC-004.md), [SEC-005](../tasks/SEC/SEC-005.md), [SEC-006](../tasks/SEC/SEC-006.md) |
| 7 | PostgreSQL schemas/migrations/indexes/connections | [CTL-002](../tasks/CTL/CTL-002.md), [CTL-005](../tasks/CTL/CTL-005.md) |
| 8 | Redis keys/TTLs/invalidation | [CTL-006](../tasks/CTL/CTL-006.md), [API-003](../tasks/API/API-003.md) |
| 9 | Snowflake WIF onboarding | [CON-001](../tasks/CON/CON-001.md), [CON-002](../tasks/CON/CON-002.md), [CON-003](../tasks/CON/CON-003.md), [CON-006](../tasks/CON/CON-006.md) |
| 10 | Organization/account discovery | [CON-004](../tasks/CON/CON-004.md) |
| 11 | Permission/capability discovery | [CON-005](../tasks/CON/CON-005.md) |
| 12 | Source registry/contracts | [ING-001](../tasks/ING/ING-001.md) |
| 13 | Python extraction framework | [ING-003](../tasks/ING/ING-003.md) |
| 14 | Streaming/Arrow extraction | [ING-003](../tasks/ING/ING-003.md) |
| 15 | Parquet schema/version/compression/sizing | [ING-004](../tasks/ING/ING-004.md), [ING-009](../tasks/ING/ING-009.md) |
| 16 | S3 partitions/manifests/retention/replay | [ING-005](../tasks/ING/ING-005.md), [ING-011](../tasks/ING/ING-011.md), [OPS-005](../tasks/OPS/OPS-005.md), [OPS-007](../tasks/OPS/OPS-007.md) |
| 17 | Snowpipe ingestion | [ING-006](../tasks/ING/ING-006.md), [ING-007](../tasks/ING/ING-007.md) |
| 18 | Watermarks/overlap/late arrivals | [ING-002](../tasks/ING/ING-002.md), [ING-008](../tasks/ING/ING-008.md) |
| 19 | Idempotency/deduplication | [ING-008](../tasks/ING/ING-008.md), [DBT-002](../tasks/DBT/DBT-002.md), [CTL-004](../tasks/CTL/CTL-004.md) |
| 20 | Backfill/catch-up/steady state | [ING-010](../tasks/ING/ING-010.md), [ORC-004](../tasks/ORC/ORC-004.md), [ORC-006](../tasks/ORC/ORC-006.md) |
| 21 | Dagster OSS deployment/assets | [ORC-001](../tasks/ORC/ORC-001.md), [ORC-002](../tasks/ORC/ORC-002.md), [ORC-003](../tasks/ORC/ORC-003.md) |
| 22 | dbt staging/intermediate/ledger/marts/serving | [DBT-001](../tasks/DBT/DBT-001.md), [DBT-002](../tasks/DBT/DBT-002.md), [DBT-003](../tasks/DBT/DBT-003.md), [DBT-004](../tasks/DBT/DBT-004.md), [DBT-005](../tasks/DBT/DBT-005.md), [DBT-006](../tasks/DBT/DBT-006.md) |
| 23 | Python analytical/ML/statistical engines | [ORC-005](../tasks/ORC/ORC-005.md), [GOV-002](../tasks/GOV/GOV-002.md), [GOV-005](../tasks/GOV/GOV-005.md), [INS-001](../tasks/INS/INS-001.md), [INS-007](../tasks/INS/INS-007.md) |
| 24 | Financial ledger by service | [FIN-001](../tasks/FIN/FIN-001.md), [FIN-002](../tasks/FIN/FIN-002.md), [FIN-003](../tasks/FIN/FIN-003.md), [FIN-004](../tasks/FIN/FIN-004.md), [FIN-005](../tasks/FIN/FIN-005.md), [FIN-006](../tasks/FIN/FIN-006.md), [FIN-007](../tasks/FIN/FIN-007.md), [FIN-008](../tasks/FIN/FIN-008.md), [FIN-011](../tasks/FIN/FIN-011.md), [FIN-012](../tasks/FIN/FIN-012.md), [FIN-013](../tasks/FIN/FIN-013.md), [FIN-014](../tasks/FIN/FIN-014.md), [FIN-015](../tasks/FIN/FIN-015.md), [FIN-016](../tasks/FIN/FIN-016.md), [FIN-017](../tasks/FIN/FIN-017.md), [FIN-018](../tasks/FIN/FIN-018.md), [FIN-019](../tasks/FIN/FIN-019.md), [FIN-020](../tasks/FIN/FIN-020.md), [FIN-021](../tasks/FIN/FIN-021.md) |
| 25 | Reconciliation/invariants | [FIN-009](../tasks/FIN/FIN-009.md), [FIN-010](../tasks/FIN/FIN-010.md), [OPS-002](../tasks/OPS/OPS-002.md) |
| 26 | Semantic metric registry | [API-001](../tasks/API/API-001.md) |
| 27 | Serving marts/API query architecture | [DBT-006](../tasks/DBT/DBT-006.md), [API-002](../tasks/API/API-002.md), [API-003](../tasks/API/API-003.md), [API-004](../tasks/API/API-004.md), [API-006](../tasks/API/API-006.md) |
| 28 | Cost Explorer | [UX-004](../tasks/UX/UX-004.md), [API-005](../tasks/API/API-005.md) |
| 29 | Warehouse/query/storage/serverless/Cortex/SPCS/workloads | [UX-005](../tasks/UX/UX-005.md), [UX-006](../tasks/UX/UX-006.md), [UX-007](../tasks/UX/UX-007.md), [WRK-004](../tasks/WRK/WRK-004.md) |
| 30 | dbt and Power BI intelligence | [WRK-001](../tasks/WRK/WRK-001.md), [WRK-002](../tasks/WRK/WRK-002.md), [WRK-003](../tasks/WRK/WRK-003.md), [WRK-005](../tasks/WRK/WRK-005.md) |
| 31 | External Tag Studio | [ALC-001](../tasks/ALC/ALC-001.md), [ALC-002](../tasks/ALC/ALC-002.md), [ALC-003](../tasks/ALC/ALC-003.md) |
| 32 | Allocation engine | [ALC-005](../tasks/ALC/ALC-005.md), [ALC-006](../tasks/ALC/ALC-006.md) |
| 33 | Usage Groups | [ALC-004](../tasks/ALC/ALC-004.md) |
| 34 | Showback | [ALC-007](../tasks/ALC/ALC-007.md) |
| 35 | Chargeback | [ALC-008](../tasks/ALC/ALC-008.md) |
| 36 | Budgets/forecasting | [GOV-001](../tasks/GOV/GOV-001.md), [GOV-002](../tasks/GOV/GOV-002.md) |
| 37 | Monitor engine | [GOV-003](../tasks/GOV/GOV-003.md), [GOV-004](../tasks/GOV/GOV-004.md), [GOV-008](../tasks/GOV/GOV-008.md) |
| 38 | Anomaly detection | [GOV-005](../tasks/GOV/GOV-005.md) |
| 39 | Notification delivery | [GOV-006](../tasks/GOV/GOV-006.md), [GOV-007](../tasks/GOV/GOV-007.md) |
| 40 | Reporting/PDF | [RPT-001](../tasks/RPT/RPT-001.md), [RPT-002](../tasks/RPT/RPT-002.md), [RPT-003](../tasks/RPT/RPT-003.md), [RPT-004](../tasks/RPT/RPT-004.md), [RPT-005](../tasks/RPT/RPT-005.md) |
| 41 | Insights | [INS-001](../tasks/INS/INS-001.md), [INS-002](../tasks/INS/INS-002.md), [INS-003](../tasks/INS/INS-003.md), [INS-004](../tasks/INS/INS-004.md), [INS-005](../tasks/INS/INS-005.md) |
| 42 | Actions/realized savings | [INS-006](../tasks/INS/INS-006.md), [INS-007](../tasks/INS/INS-007.md) |
| 43 | Data Health/sync UX | [ING-012](../tasks/ING/ING-012.md), [ONB-001](../tasks/ONB/ONB-001.md) |
| 44 | SaaS observability | [OPS-001](../tasks/OPS/OPS-001.md), [OPS-003](../tasks/OPS/OPS-003.md) |
| 45 | Data quality | [DBT-005](../tasks/DBT/DBT-005.md), [OPS-002](../tasks/OPS/OPS-002.md) |
| 46 | Security hardening | [SEC-001](../tasks/SEC/SEC-001.md), [OPS-004](../tasks/OPS/OPS-004.md) |
| 47 | Audit logs | [SEC-008](../tasks/SEC/SEC-008.md), [OPS-005](../tasks/OPS/OPS-005.md) |
| 48 | Privacy/query sanitization | [SEC-007](../tasks/SEC/SEC-007.md), [OPS-005](../tasks/OPS/OPS-005.md) |
| 49 | CI/CD | [FND-006](../tasks/FND/FND-006.md), [INF-007](../tasks/INF/INF-007.md), [REL-001](../tasks/REL/REL-001.md) |
| 50 | Testing strategy | [FND-004](../tasks/FND/FND-004.md), [FND-005](../tasks/FND/FND-005.md), [OPS-011](../tasks/OPS/OPS-011.md) |
| 51 | Backup/disaster recovery | [OPS-006](../tasks/OPS/OPS-006.md), [OPS-007](../tasks/OPS/OPS-007.md) |
| 52 | Performance/scaling | [ORC-006](../tasks/ORC/ORC-006.md), [OPS-008](../tasks/OPS/OPS-008.md) |
| 53 | Internal cost attribution/gross margin | [OPS-009](../tasks/OPS/OPS-009.md) |
| 54 | Production readiness | [REL-002](../tasks/REL/REL-002.md), [REL-003](../tasks/REL/REL-003.md), [REL-004](../tasks/REL/REL-004.md) |
| 55 | Documentation | [FND-006](../tasks/FND/FND-006.md), [ONB-002](../tasks/ONB/ONB-002.md), [OPS-010](../tasks/OPS/OPS-010.md) |
| 56 | Customer onboarding | [ONB-001](../tasks/ONB/ONB-001.md), [ONB-003](../tasks/ONB/ONB-003.md), [ONB-004](../tasks/ONB/ONB-004.md), [ONB-005](../tasks/ONB/ONB-005.md) |
| 57 | Support/runbooks | [OPS-010](../tasks/OPS/OPS-010.md), [ONB-002](../tasks/ONB/ONB-002.md) |
| 58 | First production customer | [ONB-005](../tasks/ONB/ONB-005.md), [LCH-001](../tasks/LCH/LCH-001.md), [LCH-002](../tasks/LCH/LCH-002.md), [LCH-003](../tasks/LCH/LCH-003.md) |
| 59 | Post-launch validation | [LCH-004](../tasks/LCH/LCH-004.md) |

## PRD sections

| Section | Requirement | Implementation ownership |
|---|---|---|
| 1 | Product vision | [FND-001](../tasks/FND/FND-001.md), [INF-008](../tasks/INF/INF-008.md), [CTL-001](../tasks/CTL/CTL-001.md), [DBT-001](../tasks/DBT/DBT-001.md) |
| 2 | Fundamental architectural principles | [FND-001](../tasks/FND/FND-001.md), [INF-008](../tasks/INF/INF-008.md), [CTL-001](../tasks/CTL/CTL-001.md), [DBT-001](../tasks/DBT/DBT-001.md) |
| 3 | Target architecture | [FND-001](../tasks/FND/FND-001.md), [INF-008](../tasks/INF/INF-008.md), [CTL-001](../tasks/CTL/CTL-001.md), [DBT-001](../tasks/DBT/DBT-001.md) |
| 4 | Separation of storage responsibilities | [FND-001](../tasks/FND/FND-001.md), [INF-008](../tasks/INF/INF-008.md), [CTL-001](../tasks/CTL/CTL-001.md), [DBT-001](../tasks/DBT/DBT-001.md) |
| 5 | AWS infrastructure | [INF-001](../tasks/INF/INF-001.md), [INF-002](../tasks/INF/INF-002.md), [INF-005](../tasks/INF/INF-005.md), [INF-006](../tasks/INF/INF-006.md) |
| 6 | Network topology | [INF-001](../tasks/INF/INF-001.md), [INF-002](../tasks/INF/INF-002.md), [INF-005](../tasks/INF/INF-005.md), [INF-006](../tasks/INF/INF-006.md) |
| 7 | Tenant hierarchy | [CTL-001](../tasks/CTL/CTL-001.md), [SEC-004](../tasks/SEC/SEC-004.md), [SEC-005](../tasks/SEC/SEC-005.md) |
| 8 | Organization Usage | [CON-001](../tasks/CON/CON-001.md), [CON-003](../tasks/CON/CON-003.md), [CON-004](../tasks/CON/CON-004.md), [CON-005](../tasks/CON/CON-005.md) |
| 9 | Connection model | [CON-001](../tasks/CON/CON-001.md), [CON-003](../tasks/CON/CON-003.md), [CON-004](../tasks/CON/CON-004.md), [CON-005](../tasks/CON/CON-005.md) |
| 10 | Snowflake connection privilege strategy | [CON-001](../tasks/CON/CON-001.md), [CON-003](../tasks/CON/CON-003.md), [CON-004](../tasks/CON/CON-004.md), [CON-005](../tasks/CON/CON-005.md) |
| 11 | Dagster OSS role | [ORC-001](../tasks/ORC/ORC-001.md), [ORC-002](../tasks/ORC/ORC-002.md), [ORC-003](../tasks/ORC/ORC-003.md), [ORC-004](../tasks/ORC/ORC-004.md), [ORC-006](../tasks/ORC/ORC-006.md) |
| 12 | Dagster OSS deployment | [ORC-001](../tasks/ORC/ORC-001.md), [ORC-002](../tasks/ORC/ORC-002.md), [ORC-003](../tasks/ORC/ORC-003.md), [ORC-004](../tasks/ORC/ORC-004.md), [ORC-006](../tasks/ORC/ORC-006.md) |
| 13 | Dagster metadata database | [ORC-001](../tasks/ORC/ORC-001.md), [ORC-002](../tasks/ORC/ORC-002.md), [ORC-003](../tasks/ORC/ORC-003.md), [ORC-004](../tasks/ORC/ORC-004.md), [ORC-006](../tasks/ORC/ORC-006.md) |
| 14 | Dagster code locations | [ORC-001](../tasks/ORC/ORC-001.md), [ORC-002](../tasks/ORC/ORC-002.md), [ORC-003](../tasks/ORC/ORC-003.md), [ORC-004](../tasks/ORC/ORC-004.md), [ORC-006](../tasks/ORC/ORC-006.md) |
| 15 | Dagster run strategy | [ORC-001](../tasks/ORC/ORC-001.md), [ORC-002](../tasks/ORC/ORC-002.md), [ORC-003](../tasks/ORC/ORC-003.md), [ORC-004](../tasks/ORC/ORC-004.md), [ORC-006](../tasks/ORC/ORC-006.md) |
| 16 | Work queues | [ORC-001](../tasks/ORC/ORC-001.md), [ORC-002](../tasks/ORC/ORC-002.md), [ORC-003](../tasks/ORC/ORC-003.md), [ORC-004](../tasks/ORC/ORC-004.md), [ORC-006](../tasks/ORC/ORC-006.md) |
| 17 | Source registry | [ING-001](../tasks/ING/ING-001.md), [ING-002](../tasks/ING/ING-002.md) |
| 18 | Source-specific ingestion strategy | [ING-001](../tasks/ING/ING-001.md), [ING-002](../tasks/ING/ING-002.md) |
| 19 | Extraction engine | [ING-003](../tasks/ING/ING-003.md) |
| 20 | Extraction memory safety | [ING-003](../tasks/ING/ING-003.md) |
| 21 | Parquet choice | [ING-004](../tasks/ING/ING-004.md) |
| 22 | Parquet file sizing | [ING-004](../tasks/ING/ING-004.md) |
| 23 | S3 landing architecture | [ING-005](../tasks/ING/ING-005.md), [ING-007](../tasks/ING/ING-007.md), [ING-011](../tasks/ING/ING-011.md) |
| 24 | Batch manifest | [ING-005](../tasks/ING/ING-005.md), [ING-007](../tasks/ING/ING-007.md), [ING-011](../tasks/ING/ING-011.md) |
| 25 | S3 zones | [ING-005](../tasks/ING/ING-005.md), [ING-007](../tasks/ING/ING-007.md), [ING-011](../tasks/ING/ING-011.md) |
| 26 | Why retain raw Parquet after Snowpipe | [ING-005](../tasks/ING/ING-005.md), [ING-007](../tasks/ING/ING-007.md), [ING-011](../tasks/ING/ING-011.md) |
| 27 | S3 event semantics | [ING-005](../tasks/ING/ING-005.md), [ING-007](../tasks/ING/ING-007.md), [ING-011](../tasks/ING/ING-011.md) |
| 28 | Snowpipe | [ING-006](../tasks/ING/ING-006.md), [ING-007](../tasks/ING/ING-007.md) |
| 29 | Raw Snowflake tables | [ING-006](../tasks/ING/ING-006.md), [ING-007](../tasks/ING/ING-007.md) |
| 30 | Parquet loading | [ING-006](../tasks/ING/ING-006.md), [ING-007](../tasks/ING/ING-007.md) |
| 31 | Schema evolution | [ING-009](../tasks/ING/ING-009.md) |
| 32 | BCR protection | [ING-009](../tasks/ING/ING-009.md) |
| 33 | Watermark model | [ING-002](../tasks/ING/ING-002.md), [ING-008](../tasks/ING/ING-008.md), [DBT-002](../tasks/DBT/DBT-002.md) |
| 34 | Overlapping extraction | [ING-002](../tasks/ING/ING-002.md), [ING-008](../tasks/ING/ING-008.md), [DBT-002](../tasks/DBT/DBT-002.md) |
| 35 | Deduplication | [ING-002](../tasks/ING/ING-002.md), [ING-008](../tasks/ING/ING-008.md), [DBT-002](../tasks/DBT/DBT-002.md) |
| 36 | Provisional vs authoritative state | [FIN-009](../tasks/FIN/FIN-009.md), [FIN-010](../tasks/FIN/FIN-010.md), [API-003](../tasks/API/API-003.md) |
| 37 | Hot-data path | [ING-012](../tasks/ING/ING-012.md) |
| 38 | Backfill lifecycle | [ING-010](../tasks/ING/ING-010.md), [ORC-004](../tasks/ORC/ORC-004.md), [ORC-006](../tasks/ORC/ORC-006.md) |
| 39 | Backfill idempotency | [ING-010](../tasks/ING/ING-010.md), [ORC-004](../tasks/ORC/ORC-004.md), [ORC-006](../tasks/ORC/ORC-006.md) |
| 40 | Catch-up phase | [ING-010](../tasks/ING/ING-010.md), [ORC-004](../tasks/ORC/ORC-004.md), [ORC-006](../tasks/ORC/ORC-006.md) |
| 41 | Steady-state synchronization | [ING-010](../tasks/ING/ING-010.md), [ORC-004](../tasks/ORC/ORC-004.md), [ORC-006](../tasks/ORC/ORC-006.md) |
| 42 | Sync health model | [ING-012](../tasks/ING/ING-012.md), [OPS-001](../tasks/OPS/OPS-001.md), [OPS-003](../tasks/OPS/OPS-003.md) |
| 43 | End-to-end synchronization SLA | [ING-012](../tasks/ING/ING-012.md), [OPS-001](../tasks/OPS/OPS-001.md), [OPS-003](../tasks/OPS/OPS-003.md) |
| 44 | dbt architecture | [DBT-001](../tasks/DBT/DBT-001.md), [DBT-002](../tasks/DBT/DBT-002.md) |
| 45 | dbt staging layer | [DBT-001](../tasks/DBT/DBT-001.md), [DBT-002](../tasks/DBT/DBT-002.md) |
| 46 | Intermediate layer | [DBT-003](../tasks/DBT/DBT-003.md) |
| 47 | Ledger layer | [FIN-001](../tasks/FIN/FIN-001.md), [FIN-002](../tasks/FIN/FIN-002.md), [FIN-007](../tasks/FIN/FIN-007.md), [FIN-021](../tasks/FIN/FIN-021.md) |
| 48 | Ledger canonical contract | [FIN-001](../tasks/FIN/FIN-001.md), [FIN-002](../tasks/FIN/FIN-002.md), [FIN-007](../tasks/FIN/FIN-007.md), [FIN-021](../tasks/FIN/FIN-021.md) |
| 49 | Independent service principle | [FIN-001](../tasks/FIN/FIN-001.md), [FIN-002](../tasks/FIN/FIN-002.md), [FIN-007](../tasks/FIN/FIN-007.md), [FIN-021](../tasks/FIN/FIN-021.md) |
| 50 | dbt incremental strategy | [DBT-004](../tasks/DBT/DBT-004.md), [DBT-006](../tasks/DBT/DBT-006.md) |
| 51 | dbt full rebuild strategy | [DBT-004](../tasks/DBT/DBT-004.md), [DBT-006](../tasks/DBT/DBT-006.md) |
| 52 | dbt tests | [DBT-005](../tasks/DBT/DBT-005.md) |
| 53 | Python analytical layer | [ORC-005](../tasks/ORC/ORC-005.md), [INS-001](../tasks/INS/INS-001.md), [GOV-002](../tasks/GOV/GOV-002.md) |
| 54 | Python output contract | [ORC-005](../tasks/ORC/ORC-005.md), [INS-001](../tasks/INS/INS-001.md), [GOV-002](../tasks/GOV/GOV-002.md) |
| 55 | Example Python/dbt pipeline | [ORC-005](../tasks/ORC/ORC-005.md), [INS-001](../tasks/INS/INS-001.md), [GOV-002](../tasks/GOV/GOV-002.md) |
| 56 | PostgreSQL role | [CTL-001](../tasks/CTL/CTL-001.md), [CTL-002](../tasks/CTL/CTL-002.md) |
| 57 | What PostgreSQL must never contain | [CTL-001](../tasks/CTL/CTL-001.md), [CTL-002](../tasks/CTL/CTL-002.md) |
| 58 | PostgreSQL schemas | [CTL-001](../tasks/CTL/CTL-001.md), [CTL-002](../tasks/CTL/CTL-002.md) |
| 59 | PostgreSQL tenant RLS | [SEC-004](../tasks/SEC/SEC-004.md) |
| 60 | PostgreSQL indexes | [CTL-002](../tasks/CTL/CTL-002.md), [CTL-005](../tasks/CTL/CTL-005.md) |
| 61 | PostgreSQL connection pooling | [CTL-002](../tasks/CTL/CTL-002.md), [CTL-005](../tasks/CTL/CTL-005.md) |
| 62 | PostgreSQL caching | [CTL-006](../tasks/CTL/CTL-006.md), [API-003](../tasks/API/API-003.md) |
| 63 | Three-level query acceleration architecture | [CTL-006](../tasks/CTL/CTL-006.md), [API-003](../tasks/API/API-003.md) |
| 64 | Redis / ElastiCache | [CTL-006](../tasks/CTL/CTL-006.md), [API-003](../tasks/API/API-003.md) |
| 65 | Redis TTL strategy | [CTL-006](../tasks/CTL/CTL-006.md), [API-003](../tasks/API/API-003.md) |
| 66 | Dataset-version cache invalidation | [CTL-006](../tasks/CTL/CTL-006.md), [API-003](../tasks/API/API-003.md) |
| 67 | Snowflake serving layer | [DBT-006](../tasks/DBT/DBT-006.md), [API-002](../tasks/API/API-002.md), [API-004](../tasks/API/API-004.md) |
| 68 | Query routing | [DBT-006](../tasks/DBT/DBT-006.md), [API-002](../tasks/API/API-002.md), [API-004](../tasks/API/API-004.md) |
| 69 | FastAPI layer | [CTL-003](../tasks/CTL/CTL-003.md), [API-002](../tasks/API/API-002.md), [API-003](../tasks/API/API-003.md), [API-006](../tasks/API/API-006.md) |
| 70 | Analytical API contracts | [CTL-003](../tasks/CTL/CTL-003.md), [API-002](../tasks/API/API-002.md), [API-003](../tasks/API/API-003.md), [API-006](../tasks/API/API-006.md) |
| 71 | Semantic registry | [API-001](../tasks/API/API-001.md) |
| 72 | Cost reconciliation | [FIN-009](../tasks/FIN/FIN-009.md), [FIN-010](../tasks/FIN/FIN-010.md), [OPS-002](../tasks/OPS/OPS-002.md) |
| 73 | Financial invariants | [FIN-009](../tasks/FIN/FIN-009.md), [FIN-010](../tasks/FIN/FIN-010.md), [OPS-002](../tasks/OPS/OPS-002.md) |
| 74 | FinOps Cost Explorer | [UX-004](../tasks/UX/UX-004.md) |
| 75 | Warehouse analytics | [UX-005](../tasks/UX/UX-005.md), [FIN-004](../tasks/FIN/FIN-004.md), [FIN-003](../tasks/FIN/FIN-003.md) |
| 76 | Query Cost Explorer | [UX-005](../tasks/UX/UX-005.md), [FIN-004](../tasks/FIN/FIN-004.md), [FIN-003](../tasks/FIN/FIN-003.md) |
| 77 | Workload intelligence | [WRK-001](../tasks/WRK/WRK-001.md), [WRK-003](../tasks/WRK/WRK-003.md), [WRK-004](../tasks/WRK/WRK-004.md), [WRK-005](../tasks/WRK/WRK-005.md) |
| 78 | dbt experience | [WRK-002](../tasks/WRK/WRK-002.md) |
| 79 | Tag Studio | [ALC-001](../tasks/ALC/ALC-001.md), [ALC-002](../tasks/ALC/ALC-002.md) |
| 80 | Sources for virtual tags | [ALC-001](../tasks/ALC/ALC-001.md), [ALC-002](../tasks/ALC/ALC-002.md) |
| 81 | Tag rule lifecycle | [ALC-003](../tasks/ALC/ALC-003.md) |
| 82 | Allocation engine | [ALC-005](../tasks/ALC/ALC-005.md) |
| 83 | Shared warehouse example | [ALC-005](../tasks/ALC/ALC-005.md) |
| 84 | Usage Group Sets | [ALC-004](../tasks/ALC/ALC-004.md) |
| 85 | Showback | [ALC-007](../tasks/ALC/ALC-007.md) |
| 86 | Chargeback | [ALC-008](../tasks/ALC/ALC-008.md) |
| 87 | Explain This Number | [API-005](../tasks/API/API-005.md) |
| 88 | Allocation quality | [ALC-006](../tasks/ALC/ALC-006.md), [OPS-002](../tasks/OPS/OPS-002.md) |
| 89 | Budgets | [GOV-001](../tasks/GOV/GOV-001.md), [GOV-002](../tasks/GOV/GOV-002.md) |
| 90 | Monitor engine | [GOV-003](../tasks/GOV/GOV-003.md), [GOV-004](../tasks/GOV/GOV-004.md), [GOV-005](../tasks/GOV/GOV-005.md) |
| 91 | Monitor types | [GOV-003](../tasks/GOV/GOV-003.md), [GOV-004](../tasks/GOV/GOV-004.md), [GOV-005](../tasks/GOV/GOV-005.md) |
| 92 | Partition monitors | [GOV-003](../tasks/GOV/GOV-003.md), [GOV-004](../tasks/GOV/GOV-004.md), [GOV-005](../tasks/GOV/GOV-005.md) |
| 93 | Monitor processing architecture | [GOV-004](../tasks/GOV/GOV-004.md), [ORC-005](../tasks/ORC/ORC-005.md) |
| 94 | Alert deduplication | [GOV-004](../tasks/GOV/GOV-004.md), [ORC-005](../tasks/ORC/ORC-005.md) |
| 95 | Notification destinations | [GOV-006](../tasks/GOV/GOV-006.md), [GOV-007](../tasks/GOV/GOV-007.md), [GOV-008](../tasks/GOV/GOV-008.md) |
| 96 | Premium alert content | [GOV-006](../tasks/GOV/GOV-006.md), [GOV-007](../tasks/GOV/GOV-007.md), [GOV-008](../tasks/GOV/GOV-008.md) |
| 97 | Insight Engine | [INS-001](../tasks/INS/INS-001.md) |
| 98 | Warehouse insights | [INS-002](../tasks/INS/INS-002.md) |
| 99 | Query insights | [INS-003](../tasks/INS/INS-003.md) |
| 100 | Storage insights | [INS-004](../tasks/INS/INS-004.md) |
| 101 | Pipeline insights | [INS-003](../tasks/INS/INS-003.md) |
| 102 | Snowpipe insights | [INS-004](../tasks/INS/INS-004.md) |
| 103 | Cortex insights | [INS-005](../tasks/INS/INS-005.md) |
| 104 | SPCS insights | [INS-005](../tasks/INS/INS-005.md) |
| 105 | Insight deep dive | [INS-001](../tasks/INS/INS-001.md), [INS-006](../tasks/INS/INS-006.md) |
| 106 | Insight lifecycle | [INS-001](../tasks/INS/INS-001.md), [INS-006](../tasks/INS/INS-006.md) |
| 107 | Action tracking | [INS-006](../tasks/INS/INS-006.md) |
| 108 | Realized savings | [INS-007](../tasks/INS/INS-007.md) |
| 109 | Reporting engine | [RPT-001](../tasks/RPT/RPT-001.md), [RPT-002](../tasks/RPT/RPT-002.md), [RPT-003](../tasks/RPT/RPT-003.md) |
| 110 | Scheduled reporting | [RPT-004](../tasks/RPT/RPT-004.md), [RPT-005](../tasks/RPT/RPT-005.md), [GOV-007](../tasks/GOV/GOV-007.md) |
| 111 | PostgreSQL report configuration | [RPT-001](../tasks/RPT/RPT-001.md), [CTL-002](../tasks/CTL/CTL-002.md) |
| 112 | Home page | [UX-003](../tasks/UX/UX-003.md) |
| 113 | Authentication for SaaS users | [SEC-002](../tasks/SEC/SEC-002.md), [SEC-003](../tasks/SEC/SEC-003.md) |
| 114 | SaaS RBAC | [CTL-003](../tasks/CTL/CTL-003.md), [SEC-004](../tasks/SEC/SEC-004.md) |
| 115 | Analytical RLS | [SEC-005](../tasks/SEC/SEC-005.md), [SEC-006](../tasks/SEC/SEC-006.md) |
| 116 | Redis security | [CTL-006](../tasks/CTL/CTL-006.md), [SEC-006](../tasks/SEC/SEC-006.md) |
| 117 | Query text privacy | [SEC-007](../tasks/SEC/SEC-007.md) |
| 118 | Audit | [SEC-008](../tasks/SEC/SEC-008.md), [OPS-005](../tasks/OPS/OPS-005.md) |
| 119 | Onboarding | [ONB-001](../tasks/ONB/ONB-001.md), [ONB-003](../tasks/ONB/ONB-003.md), [ONB-004](../tasks/ONB/ONB-004.md), [ONB-005](../tasks/ONB/ONB-005.md) |
| 120 | Onboarding progress UX | [ONB-001](../tasks/ONB/ONB-001.md), [ONB-003](../tasks/ONB/ONB-003.md), [ONB-004](../tasks/ONB/ONB-004.md), [ONB-005](../tasks/ONB/ONB-005.md) |
| 121 | Data health center | [ING-012](../tasks/ING/ING-012.md) |
| 122 | Dagster technical observability | [ORC-006](../tasks/ORC/ORC-006.md), [OPS-001](../tasks/OPS/OPS-001.md) |
| 123 | Platform observability | [OPS-001](../tasks/OPS/OPS-001.md), [OPS-003](../tasks/OPS/OPS-003.md) |
| 124 | Data observability | [OPS-002](../tasks/OPS/OPS-002.md), [DBT-005](../tasks/DBT/DBT-005.md) |
| 125 | Failure model | [ING-008](../tasks/ING/ING-008.md), [ING-009](../tasks/ING/ING-009.md), [ING-011](../tasks/ING/ING-011.md), [OPS-006](../tasks/OPS/OPS-006.md), [OPS-007](../tasks/OPS/OPS-007.md) |
| 126 | Exactly-once business semantics | [ING-008](../tasks/ING/ING-008.md), [ING-009](../tasks/ING/ING-009.md), [ING-011](../tasks/ING/ING-011.md), [OPS-006](../tasks/OPS/OPS-006.md), [OPS-007](../tasks/OPS/OPS-007.md) |
| 127 | Replay | [ING-008](../tasks/ING/ING-008.md), [ING-009](../tasks/ING/ING-009.md), [ING-011](../tasks/ING/ING-011.md), [OPS-006](../tasks/OPS/OPS-006.md), [OPS-007](../tasks/OPS/OPS-007.md) |
| 128 | Data retention | [OPS-005](../tasks/OPS/OPS-005.md), [OPS-007](../tasks/OPS/OPS-007.md) |
| 129 | CI/CD | [FND-006](../tasks/FND/FND-006.md), [INF-007](../tasks/INF/INF-007.md), [REL-001](../tasks/REL/REL-001.md), [REL-002](../tasks/REL/REL-002.md) |
| 130 | Deployment pipeline | [FND-006](../tasks/FND/FND-006.md), [INF-007](../tasks/INF/INF-007.md), [REL-001](../tasks/REL/REL-001.md), [REL-002](../tasks/REL/REL-002.md) |
| 131 | dbt CI | [DBT-005](../tasks/DBT/DBT-005.md), [DBT-006](../tasks/DBT/DBT-006.md) |
| 132 | Python testing | [FND-004](../tasks/FND/FND-004.md), [FND-005](../tasks/FND/FND-005.md), [INS-007](../tasks/INS/INS-007.md), [GOV-002](../tasks/GOV/GOV-002.md) |
| 133 | Schema contract testing | [ING-001](../tasks/ING/ING-001.md), [ING-009](../tasks/ING/ING-009.md) |
| 134 | Deployment environments | [INF-001](../tasks/INF/INF-001.md), [INF-008](../tasks/INF/INF-008.md) |
| 135 | Security boundaries | [SEC-001](../tasks/SEC/SEC-001.md), [SEC-006](../tasks/SEC/SEC-006.md), [OPS-004](../tasks/OPS/OPS-004.md) |
| 136 | Encryption | [INF-003](../tasks/INF/INF-003.md), [SEC-008](../tasks/SEC/SEC-008.md) |
| 137 | Secrets Manager | [INF-003](../tasks/INF/INF-003.md), [SEC-008](../tasks/SEC/SEC-008.md) |
| 138 | Cost control of Bridge Data itself | [OPS-009](../tasks/OPS/OPS-009.md) |
| 139 | Workload cost isolation | [ORC-006](../tasks/ORC/ORC-006.md), [OPS-008](../tasks/OPS/OPS-008.md) |
| 140 | Heavy analysis model | [API-004](../tasks/API/API-004.md) |
| 141 | Small interactive analysis | [API-002](../tasks/API/API-002.md), [API-003](../tasks/API/API-003.md) |
| 142 | No PostgreSQL analytical mirror | [CTL-001](../tasks/CTL/CTL-001.md), [CTL-002](../tasks/CTL/CTL-002.md) |
| 143 | Feature navigation | [UX-001](../tasks/UX/UX-001.md), [UX-002](../tasks/UX/UX-002.md), [UX-008](../tasks/UX/UX-008.md) |
| 144 | Product personas | [UX-001](../tasks/UX/UX-001.md), [UX-002](../tasks/UX/UX-002.md), [UX-008](../tasks/UX/UX-008.md) |
| 145 | API-first design | [API-006](../tasks/API/API-006.md) |
| 146 | Future FinOps Copilot — future capability boundary only | [INS-001](../tasks/INS/INS-001.md), [INS-006](../tasks/INS/INS-006.md), [SEC-001](../tasks/SEC/SEC-001.md) |
| 147 | Future automation — future capability boundary only | [INS-001](../tasks/INS/INS-001.md), [INS-006](../tasks/INS/INS-006.md), [SEC-001](../tasks/SEC/SEC-001.md) |
| 148 | Recommended implementation sequence | [FND-005](../tasks/FND/FND-005.md), [REL-004](../tasks/REL/REL-004.md), [LCH-004](../tasks/LCH/LCH-004.md) |
| 149 | Recommended physical repositories | [FND-001](../tasks/FND/FND-001.md) |
| 150 | Dagster project organization | [ORC-002](../tasks/ORC/ORC-002.md) |
| 151 | dbt project organization | [DBT-001](../tasks/DBT/DBT-001.md) |
| 152 | Extraction package | [ING-001](../tasks/ING/ING-001.md), [ING-003](../tasks/ING/ING-003.md) |
| 153 | Source adapter contract | [ING-001](../tasks/ING/ING-001.md), [ING-003](../tasks/ING/ING-003.md) |
| 154 | End-to-end asset lineage example | [ORC-002](../tasks/ORC/ORC-002.md), [API-005](../tasks/API/API-005.md) |
| 155 | Golden rule for transformation ownership | [FND-001](../tasks/FND/FND-001.md), [DBT-001](../tasks/DBT/DBT-001.md), [SEC-001](../tasks/SEC/SEC-001.md), [FIN-001](../tasks/FIN/FIN-001.md) |
| 156 | Anti-patterns explicitly prohibited | [FND-001](../tasks/FND/FND-001.md), [DBT-001](../tasks/DBT/DBT-001.md), [SEC-001](../tasks/SEC/SEC-001.md), [FIN-001](../tasks/FIN/FIN-001.md) |
| 157 | Definition of Done — data platform | [OPS-011](../tasks/OPS/OPS-011.md) |
| 158 | Definition of Done — SaaS | [OPS-011](../tasks/OPS/OPS-011.md), [ONB-005](../tasks/ONB/ONB-005.md), [LCH-004](../tasks/LCH/LCH-004.md) |
| 159 | Final architecture | [INF-008](../tasks/INF/INF-008.md), [ORC-001](../tasks/ORC/ORC-001.md), [DBT-001](../tasks/DBT/DBT-001.md), [API-002](../tasks/API/API-002.md), [UX-002](../tasks/UX/UX-002.md) |

## Important resolved ambiguities

| Topic | Canonical resolution |
|---|---|
| Billing total versus query attribution | Separate additive charges, non-additive resource/query bridges and independent billing references; FIN contract/ADR-002 |
| Provisional/final/reconciled | Data maturity, reconciliation result and period closure are distinct axes; ADR-003 |
| Shared analytical storage | Physical tenant keys plus identity-bound row policies; no trusted client session variable; ADR-005 |
| Snowpipe before manifest | Load may occur early, publication requires complete accepted batch; ADR-006 |
|365-day history | Requested target clamped to actual authorization/retention; snapshots begin at enrollment; CON/ING contracts |
| Retired/new Snowflake services | Capability and authority windows; current Cortex sources; unknown billed services retained once; source catalog/FIN-021 |
| Raw90 versus canonical400 days | Consistent canonical snapshots plus later journal replay; ADR-011 |
| First paying customer | Actual verified settlement separate from trial, connection and first value; ADR-012 |

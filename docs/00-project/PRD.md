# Bridge Data FinOps SaaS

## Master Product & Technical Requirements Document

**Version:** Architecture target  
**Scope:** Snowflake only  
**Cloud:** AWS  
**Orchestration:** Dagster OSS  
**Transformation:** dbt + Python  
**Customer Snowflake authentication:** Workload Identity Federation  
**Landing / transport:** S3 + Apache Parquet  
**Central analytics platform:** Snowflake  
**Transactional control plane:** PostgreSQL  
**Hot API cache:** Redis  
**Data ingestion:** Snowpipe  
**Frontend:** React  
**Backend/API:** FastAPI  
**Deployment:** containers on AWS ECS/Fargate

---

# 1. Product vision

Bridge Data FinOps is not a cost dashboard.

It is a complete Snowflake FinOps operating system capable of following a Snowflake dollar from:

```text
Invoice
   ↓
Snowflake service
   ↓
Account
   ↓
Resource
   ↓
Warehouse / Serverless / Storage / AI
   ↓
Application / Workload
   ↓
Project / Pipeline
   ↓
User / Team / Cost Center
   ↓
Query
   ↓
Root cause
   ↓
Optimization
   ↓
Action
   ↓
Realized saving
```

The application must continuously answer:

1. How much are we spending?
2. Where?
3. Who or what owns the spend?
4. Why did it change?
5. Is it expected?
6. Is it budgeted?
7. Is some of it waste?
8. What caused the waste?
9. What should be changed?
10. Did the change actually save money?

---

# 2. Fundamental architectural principles

The architecture follows several non-negotiable rules.

## 2.1 Snowflake only

No:

- BigQuery;
- Databricks;
- generic AWS FinOps;
- Azure billing;
- GCP billing.

AWS is infrastructure.

Snowflake is the product domain.

---

## 2.2 No persistent Snowflake credentials

Customer connections use:

```text
AWS IAM
   ↓
Snowflake Workload Identity Federation
   ↓
TYPE = SERVICE user
```

No passwords.

No PAT as primary mechanism.

No RSA private key.

Snowflake WIF explicitly supports AWS IAM workloads and avoids storing long-lived authentication secrets; the Python connector supports `WORKLOAD_IDENTITY`.

---

## 2.3 Dagster orchestrates; it does not contain FinOps logic

Dagster is responsible for:

```text
when
what
dependencies
retries
partition
backfill
observability
state
execution
```

It is **not** responsible for implementing:

```text
cost allocation formulas
FinOps SQL
warehouse efficiency calculations
chargeback rules
ledger calculations
business transformations
```

Those belong to dbt/Python.

---

## 2.4 dbt owns deterministic analytical transformations

dbt owns:

```text
RAW → STAGING
STAGING → INTERMEDIATE
INTERMEDIATE → LEDGER
LEDGER → MART
MART → SERVING
```

Examples:

```text
warehouse cost
idle
query attribution
storage ledger
Cortex ledger
chargeback
showback
budget actuals
cost trends
workload marts
```

Dagster's dbt integration can represent individual dbt models as assets and preserve dependencies between dbt assets and Python assets.

No dbt Cloud is required.

---

## 2.5 Python owns extraction and algorithmic processing

Python owns:

### Extraction

```text
Snowflake
→ Python connector
→ Arrow/records
→ Parquet
→ S3
```

### Algorithms

Things that are awkward or inappropriate in SQL:

```text
anomaly detection
forecasting
query parsing
query classification
pattern detection
change detection
confidence scoring
optimization simulation
complex rule evaluation
recommendation scoring
report composition
```

But Python outputs durable results back into Snowflake.

Python must not quietly become another analytical database.

---

# 3. Target architecture

```text
                        CUSTOMER
                           │
                    Snowflake Org
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
      ACC A              ACC B              ACC C
        │                  │                  │
        └──────────── WIF / AWS IAM ──────────┘
                           │
                           ▼
                PYTHON EXTRACTION WORKERS
                     ECS / Fargate
                           │
                 PyArrow / Parquet
                           │
                           ▼
                  S3 LANDING ZONE
                           │
                 event notification
                           │
                           ▼
                       SNOWPIPE
                           │
                           ▼
                CENTRAL SNOWFLAKE
                           │
               ┌───────────┴───────────┐
               │                       │
              dbt                    Python
               │                       │
               └───────────┬───────────┘
                           ▼
                 CANONICAL LEDGER
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
          MARTS         INSIGHTS       SERVING
            │              │              │
            └──────────────┼──────────────┘
                           ▼
                       FastAPI
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
       PostgreSQL        Redis         Snowflake
       Control Plane    Hot Cache     Analytics
            │              │              │
            └──────────────┼──────────────┘
                           ▼
                         React
```

Dagster surrounds the data pipeline:

```text
                        DAGSTER OSS

Discovery
    ↓
Backfill
    ↓
Extract
    ↓
Parquet
    ↓
Snowpipe loaded
    ↓
dbt staging
    ↓
dbt ledger
    ↓
Python intelligence
    ↓
dbt marts
    ↓
Quality checks
    ↓
Reconciliation
    ↓
Cache invalidation
    ↓
Monitors
    ↓
Reports
```

---

# 4. Separation of storage responsibilities

This point is critical.

There are **four different storage systems**, each with a different purpose.

| Storage | Purpose | Must NOT become |
|---|---|---|
| S3 | Immutable ingestion/replay layer | Analytical database |
| Snowflake | Analytical truth + FinOps ledger | Transactional SaaS DB |
| PostgreSQL | SaaS control plane | Query-history warehouse |
| Redis | Ephemeral API/UI cache | Persistent truth |

---

# 5. AWS infrastructure

Target:

```text
Route53
   ↓
CloudFront
   ↓
AWS WAF
   ↓
ALB
   ↓
Private VPC
```

Application services:

```text
ECS Fargate

frontend
api
connector-worker
dagster-webserver
dagster-daemon
dagster-code-location
dagster-run-worker
insight-worker
monitor-worker
report-worker
```

Managed AWS:

```text
S3
Aurora PostgreSQL
ElastiCache Redis
SQS
SNS / EventBridge
SES
KMS
Secrets Manager
CloudWatch
ECR
```

---

# 6. Network topology

Recommended:

```text
PUBLIC
─────────────────────────
CloudFront
WAF
ALB

PRIVATE APPLICATION SUBNETS
─────────────────────────
FastAPI
Dagster
Workers
Reports

PRIVATE DATA SUBNETS
─────────────────────────
Aurora PostgreSQL
Redis

AWS MANAGED
─────────────────────────
S3
SQS
KMS
Secrets Manager
```

No PostgreSQL public endpoint.

No Redis public endpoint.

No Dagster UI exposed publicly.

Dagster UI is:

```text
private
or
admin-only
```

---

# 7. Tenant hierarchy

The architecture is organization-first from Day 1.

```text
TENANT
   │
   └── SNOWFLAKE ORGANIZATION
          │
          ├── ACCOUNT A
          ├── ACCOUNT B
          ├── ACCOUNT C
          └── ACCOUNT ...
```

Every durable analytical fact contains:

```text
tenant_id
organization_id
organization_name
account_id
account_locator
account_name
region
source
event_timestamp
ingested_at
```

Never infer tenant from database name.

`tenant_id` must physically exist in analytical records.

---

# 8. Organization Usage

Organization Usage is used for:

```text
account discovery
high-level consumption
organization-wide reconciliation
cross-account analytics
```

Snowflake exposes organization-wide historical usage through `SNOWFLAKE.ORGANIZATION_USAGE`. Many historical views require bounded time predicates and some have materially higher latency than equivalent account-level information.

Organization Usage therefore complements account-level ingestion.

It does **not** replace it.

---

# 9. Connection model

Each account receives a logical connection object.

```text
connection
├── tenant_id
├── organization_id
├── snowflake_account
├── locator
├── region
├── AWS IAM identity
├── Snowflake service user
├── role
├── status
├── capabilities
└── last_validation
```

Recommended isolation:

```text
customer A / account 1
       ↓
IAM role A1
       ↓
Snowflake service user A1
```

rather than one global credential.

---

# 10. Snowflake connection privilege strategy

Two planes.

## Read plane

Default SaaS installation.

```text
BRIDGE_FINOPS_READER
```

Allows only metadata/usage required by enabled modules.

Examples may use Snowflake database roles such as:

```text
USAGE_VIEWER
GOVERNANCE_VIEWER
OBJECT_VIEWER
```

depending on required views.

---

## Action plane

Future capability.

```text
BRIDGE_FINOPS_OPERATOR
```

Separate:

- IAM role;
- Snowflake identity;
- role;
- permissions;
- audit trail.

Never:

```text
READER → inherits OPERATOR
```

Actions are explicitly enabled per account/resource.

---

# 11. Dagster OSS role

Dagster becomes the **orchestration control system for the data platform**.

Dagster natively models assets, dependencies, lineage and execution state; its dbt integration can expose individual dbt models as assets.

Conceptual asset graph:

```text
snowflake_source
       ↓
extract_batch
       ↓
parquet_batch
       ↓
snowpipe_raw
       ↓
stg_query_history
       ↓
int_query_enriched
       ↓
fct_query_cost
       ↓
mart_workload_cost
       ↓
python_anomaly
       ↓
mart_insight
       ↓
serving_home
```

---

# 12. Dagster OSS deployment

Production deployment:

```text
dagster-webserver
dagster-daemon
dagster-code-location
dagster-run-workers
PostgreSQL metadata store
```

The webserver provides operational visibility.

The daemon runs:

```text
schedules
sensors
automation
queued work
```

Actual workload execution should run in isolated workers rather than inside the webserver.

---

# 13. Dagster metadata database

Dagster gets its own PostgreSQL database/schema.

Example:

```text
Aurora PostgreSQL

bridge_control
dagster_meta
```

with different database users.

Never mix application tables and Dagster internal tables.

Dagster metadata stores:

```text
runs
events
asset materializations
scheduler state
sensor state
backfills
execution metadata
```

It is not the source of truth for customer costs.

---

# 14. Dagster code locations

Suggested split:

```text
bridge_finops_orchestrator/
│
├── extraction/
├── ingestion/
├── dbt_assets/
├── python_assets/
├── monitoring/
├── reporting/
└── maintenance/
```

Avoid one code location per customer.

Multi-tenancy is data/config-driven.

---

# 15. Dagster run strategy

Do not create:

```text
1 permanent DAG
× 1000 customers
× 100 sources
```

as static duplicated definitions.

Instead:

```text
generic source assets/jobs
+
tenant/account/source runtime configuration
+
partition/backfill metadata
```

The customer is data.

Not source code.

---

# 16. Work queues

Separate concurrency domains:

```text
extract_high
extract_standard
backfill
dbt_transform
python_compute
monitor
report
maintenance
```

Example:

```text
backfill concurrency       10
normal extraction          50
dbt runs                    8
heavy Python                4
PDF reports                10
```

Actual values are tuned by load tests.

This prevents a new 365-day customer backfill from starving existing customers.

---

# 17. Source registry

Every Snowflake source gets a formal metadata definition.

Example:

```text
source_name
source_schema
source_view
retention
expected_latency
watermark_column
natural_key
partition_strategy
overlap_window
backfill_chunk
sync_frequency
criticality
enabled
```

Example conceptual entries:

```text
QUERY_HISTORY
WAREHOUSE_METERING_HISTORY
QUERY_ATTRIBUTION_HISTORY
METERING_HISTORY
STORAGE_USAGE
TABLE_STORAGE_METRICS
AUTOMATIC_CLUSTERING_HISTORY
SERVERLESS_TASK_HISTORY
MATERIALIZED_VIEW_REFRESH_HISTORY
DATA_TRANSFER_HISTORY
CORTEX_FUNCTIONS_USAGE_HISTORY
...
```

---

# 18. Source-specific ingestion strategy

Never use one synchronization algorithm for all Snowflake views.

For example:

```text
QUERY_HISTORY
high volume
time partitioned
frequent incremental

STORAGE_USAGE
small
slow-changing
daily

WAREHOUSE_METERING_HISTORY
hourly
moderate

OBJECT METADATA
snapshot / change detection

BILLING
slow arrival
reconciliation oriented
```

Snowflake Account Usage data has source-dependent latency and commonly offers longer retention than Information Schema. `QUERY_HISTORY` exposes one year of history.

---

# 19. Extraction engine

Extraction is implemented in Python.

Responsibilities:

```text
authenticate
calculate extraction window
execute bounded query
stream results
normalize basic transport types
write Parquet
calculate statistics
write manifest
upload S3
update extraction state
```

No FinOps calculations happen here.

---

# 20. Extraction memory safety

Never:

```python
rows = cursor.fetchall()
df = pandas.DataFrame(rows)
```

for multi-million-row histories.

Prefer streaming/batching:

```text
Snowflake result
     ↓
batch
     ↓
Arrow
     ↓
Parquet writer
     ↓
next batch
```

Target:

```text
memory usage ≈ current batch
```

rather than:

```text
memory usage ≈ entire extraction
```

---

# 21. Parquet choice

Parquet is the canonical transport format.

Advantages:

```text
columnar
typed
compressed
efficient Snowflake load
smaller S3 footprint
schema inspection
fast replay
Python/Arrow native
```

Default compression:

```text
ZSTD
```

Transport schemas should be explicit.

No arbitrary:

```text
VARIANT(payload)
```

for everything.

---

# 22. Parquet file sizing

For larger extracts, target approximately:

```text
100–250 MB compressed
```

Snowflake currently recommends roughly this range for efficient loading, including Snowpipe workloads. For low-volume continuous data where waiting to accumulate that size would increase latency excessively, Snowflake recommends balancing latency and file size rather than producing huge numbers of tiny files.

Therefore:

```text
IF batch reaches 128 MB compressed
    close file

OR

IF extraction window complete
    close file
```

For small sources:

```text
one small file/window
```

is preferable to delaying data for hours.

---

# 23. S3 landing architecture

Example:

```text
s3://bridge-finops-ingestion/
  tenant_id=xxx/
    organization_id=xxx/
      account_id=xxx/
        source=query_history/
          extraction_date=2026-09-23/
            hour=08/
              batch_id=UUID/
                part-000.parquet
                part-001.parquet
                manifest.json
```

File names are immutable.

Never overwrite a batch.

---

# 24. Batch manifest

Every extraction creates:

```json
{
  "batch_id": "...",
  "tenant_id": "...",
  "account_id": "...",
  "source": "QUERY_HISTORY",
  "window_start": "...",
  "window_end": "...",
  "extracted_at": "...",
  "row_count": 123456,
  "file_count": 3,
  "schema_version": 7,
  "min_watermark": "...",
  "max_watermark": "...",
  "checksum": "...",
  "extractor_version": "..."
}
```

This is vital.

The manifest allows:

```text
audit
replay
debugging
completeness check
schema evolution
reconciliation
```

---

# 25. S3 zones

Use logical prefixes:

```text
landing/
quarantine/
archive/
```

### landing

Valid extraction waiting/available for ingestion.

### quarantine

Schema or integrity failure.

### archive

Successfully processed immutable source batches.

You do not need medallion transformations in S3.

Actual analytical transformation happens in Snowflake.

---

# 26. Why retain raw Parquet after Snowpipe

S3 provides independent recoverability.

If tomorrow:

```text
dbt model bug
Snowflake table accidentally truncated
schema transformation incorrect
new parsing feature
```

you can replay without reconnecting to every customer.

That makes S3 the **transport journal**.

Not merely temporary storage.

---

# 27. S3 event semantics

S3 event notifications are at-least-once and can therefore generate duplicate notifications.

Consequently the architecture must **never depend on exactly-once event delivery**.

Idempotency is mandatory.

---

# 28. Snowpipe

Flow:

```text
Python worker
    ↓
S3 Parquet
    ↓
S3 event
    ↓
Snowpipe
    ↓
RAW table
```

Snowpipe supports automatic ingestion from cloud storage and maintains file-load metadata to avoid repeatedly loading the same file; file load ordering is not guaranteed.

Therefore:

**Never use file arrival order as business order.**

Always use source timestamps.

---

# 29. Raw Snowflake tables

One logical raw table per source family.

Example:

```text
RAW_QUERY_HISTORY
RAW_WAREHOUSE_METERING
RAW_QUERY_ATTRIBUTION
RAW_STORAGE_USAGE
RAW_CORTEX_USAGE
```

Mandatory technical columns:

```text
tenant_id
organization_id
account_id

source_batch_id
source_file
source_extracted_at
source_window_start
source_window_end

snowpipe_loaded_at
schema_version
row_hash
```

Plus source columns.

---

# 30. Parquet loading

Prefer typed column matching.

For Parquet Snowflake supports column mapping through `MATCH_BY_COLUMN_NAME`.

Conceptually:

```sql
COPY INTO raw_query_history
FROM @stage
FILE_FORMAT = (...)
MATCH_BY_COLUMN_NAME = CASE_SENSITIVE;
```

Avoid wrapping entire records in VARIANT unless there is a specific reason.

---

# 31. Schema evolution

Schema changes are inevitable.

Every source adapter maintains:

```text
source_schema_version
extractor_schema_version
raw_schema_version
```

Classification:

### Compatible

New nullable Snowflake column.

→ extend schema.

### Transformable

Source type changes that can safely normalize.

→ Python adapter handles compatibility.

### Breaking

Removed key / incompatible semantic change.

→ quarantine + alert.

No silent coercion.

---

# 32. BCR protection

Because Snowflake evolves continuously, implement:

```text
source_contract tests
expected column inventory
type inventory
schema diff
```

Daily:

```text
DESCRIBE/metadata
       ↓
compare
       ↓
no change → OK
change → classify
       ↓
alert / compatibility test
```

This integrates naturally with the Snowflake BCR/change monitoring already required for the product.

---

# 33. Watermark model

PostgreSQL stores operational source state:

```text
tenant_id
account_id
source_name

last_requested_from
last_requested_to

last_success_from
last_success_to

last_source_watermark

last_batch_id
last_row_count

status
failure_count
last_error
```

But it does **not** store the analytical dataset.

---

# 34. Overlapping extraction

Never extract:

```text
last_timestamp → now
```

with zero overlap.

Instead:

```text
last_success - safety_window
                ↓
               now
```

Example:

```text
last completed = 08:00

next extraction =
07:00 → 09:00
```

Then deduplicate downstream.

This protects against:

```text
late arriving rows
source corrections
latency variation
network interruption
boundary errors
```

---

# 35. Deduplication

Raw can retain transport duplicates if useful for lineage.

Staging performs deterministic deduplication.

Natural key example:

```text
tenant_id
account_id
query_id
```

with:

```text
ROW_NUMBER()
OVER (
  PARTITION BY tenant_id, account_id, query_id
  ORDER BY source_extracted_at DESC
)
```

The latest authoritative copy wins.

---

# 36. Provisional vs authoritative state

Each fact can expose:

```text
PROVISIONAL
FINAL
RECONCILED
```

Example:

```text
recent query
      ↓
PROVISIONAL

Account Usage arrives
      ↓
FINAL

daily invoice/ledger controls pass
      ↓
RECONCILED
```

This is extremely valuable in the product UI.

---

# 37. Hot-data path

For use cases requiring fresher visibility:

```text
customer account
   ↓
bounded recent source
   ↓
HOT raw dataset
```

This can coexist with authoritative Account Usage.

Logical query:

```text
historical FINAL
UNION
recent PROVISIONAL
```

with deterministic precedence.

Do not pretend recent estimated data is final billing data.

---

# 38. Backfill lifecycle

Customer onboarding triggers:

```text
Discovery
   ↓
Capability scan
   ↓
365-day planning
   ↓
Historical extraction
   ↓
Snowpipe
   ↓
dbt
   ↓
reconciliation
   ↓
catch-up
   ↓
steady state
```

Large sources are partitioned.

Example:

```text
QUERY_HISTORY
365 daily chunks

WAREHOUSE_METERING
weekly chunks

STORAGE
monthly/daily based on source

object metadata
snapshots
```

Backfill and steady-state queues are separate.

---

# 39. Backfill idempotency

Unique logical extraction identity:

```text
tenant
account
source
window_start
window_end
schema_version
```

Repeated runs may produce another batch, but downstream canonical state must remain identical.

This makes retry safe.

---

# 40. Catch-up phase

After historical extraction:

```text
365-day backfill ends at T0
```

time passed during processing.

Dagster therefore executes:

```text
T0 → NOW
```

catch-up before marking source:

```text
HEALTHY
```

---

# 41. Steady-state synchronization

Illustrative classes:

```text
FAST
5–15 min

STANDARD
hourly

DAILY
daily

DISCOVERY
several times/day

RECONCILIATION
daily + monthly
```

Frequency is source-specific.

Do not poll 24-hour-latency data every minute.

---

# 42. Sync health model

Every source receives:

```text
HEALTHY
DELAYED
STALE
FAILING
BACKFILLING
DISABLED
```

Metrics:

```text
source freshness
pipeline latency
rows extracted
files produced
files loaded
raw rows
deduplicated rows
transform duration
reconciliation delta
```

---

# 43. End-to-end synchronization SLA

Measure separately:

```text
source latency
+
extraction latency
+
S3 latency
+
Snowpipe latency
+
dbt latency
+
serving refresh latency
```

The SaaS displays:

```text
Source data current through: 08:42 UTC
Last successful synchronization: 09:02 UTC
Status: Healthy
```

Not merely:

```text
Last sync: OK
```

---

# 44. dbt architecture

Recommended project:

```text
dbt/
├── models/
│   ├── staging/
│   ├── intermediate/
│   ├── ledger/
│   ├── marts/
│   └── serving/
├── macros/
├── tests/
├── seeds/
└── snapshots/
```

---

# 45. dbt staging layer

Purpose:

```text
rename
cast
timezone normalization
deduplication
source schema normalization
technical metadata
```

Example:

```text
stg_query_history
stg_warehouse_metering
stg_query_attribution
```

No business KPI here.

---

# 46. Intermediate layer

Purpose:

```text
relationships
enrichment
temporal alignment
identity resolution
workload resolution
```

Examples:

```text
int_query_session
int_query_workload
int_query_warehouse
int_query_object_access
int_metering_hourly
```

---

# 47. Ledger layer

This is the financial kernel.

Each Snowflake billable service gets a self-contained ledger model.

```text
ledger_warehouse_compute
ledger_warehouse_idle
ledger_query_compute
ledger_cloud_services
ledger_storage
ledger_snowpipe
ledger_tasks
ledger_dynamic_tables
ledger_search_optimization
ledger_auto_clustering
ledger_materialized_views
ledger_data_transfer
ledger_replication
ledger_cortex
ledger_spcs
ledger_native_apps
...
```

Each is independently testable.

---

# 48. Ledger canonical contract

All ledger models converge to:

```text
tenant_id
organization_id
account_id

usage_start
usage_end

service_category
service
sub_service

resource_type
resource_id
resource_name

credits
effective_credits
cost_native
cost_effective
currency

allocation_status
reconciliation_status

source_view
source_key
```

---

# 49. Independent service principle

Avoid:

```text
warehouse ledger
  ↓
serverless ledger
  ↓
AI ledger
```

Each service model should independently source what it needs.

This limits cascading failures.

---

# 50. dbt incremental strategy

Large facts are incremental.

Example:

```text
QUERY_HISTORY
QUERY ATTRIBUTION
MONITOR EVENTS
ALLOCATION FACTS
```

Use deterministic unique keys and bounded reprocessing windows.

Concept:

```text
MERGE latest 2–7 days
```

rather than rebuilding 365 days.

---

# 51. dbt full rebuild strategy

Full refresh remains possible for:

```text
schema migration
critical bug fix
major ledger algorithm change
```

but is not the normal production mechanism.

Dagster must be able to materialize a selected subtree of assets rather than requiring the entire platform to rerun; Dagster supports asset-level selection and dependency-aware materialization.

---

# 52. dbt tests

Every critical financial model gets tests.

Examples:

```text
not_null
unique
relationships
accepted_values
```

plus custom assertions:

```text
cost >= 0
credits >= 0

allocated_cost <= source_cost + tolerance

allocation percentages ≈ 100%

no cross-tenant joins

no duplicate canonical query

daily ledger ≈ billing source
```

---

# 53. Python analytical layer

Python is used only where it creates value.

Example modules:

```text
anomaly_engine
forecast_engine
query_parser
workload_classifier
change_detector
optimization_engine
savings_estimator
insight_ranker
```

---

# 54. Python output contract

Python never leaves important findings only in memory/PostgreSQL.

Outputs:

```text
PY_WORKLOAD_CLASSIFICATION
PY_ANOMALY_CANDIDATE
PY_OPTIMIZATION_CANDIDATE
PY_FORECAST
PY_QUERY_FEATURES
```

stored in Snowflake.

dbt then consumes them into canonical marts.

---

# 55. Example Python/dbt pipeline

```text
RAW_QUERY_HISTORY
      │
      ▼
dbt stg_query_history
      │
      ▼
dbt int_query_enriched
      │
      ▼
Python feature extraction
      │
      ▼
PY_QUERY_FEATURES
      │
      ▼
dbt mart_query_patterns
      │
      ▼
Python anomaly detection
      │
      ▼
PY_ANOMALIES
      │
      ▼
dbt mart_insights
```

This preserves clean responsibilities.

---

# 56. PostgreSQL role

PostgreSQL is the **control plane database**.

It contains:

```text
tenants
users
memberships
teams
RBAC

Snowflake connections
capabilities
sync configuration
watermarks

tag rule definitions
allocation rule definitions
budgets configuration
monitors configuration
destinations

dashboards metadata
saved views
report configuration

insight workflow state
action workflow state

subscriptions
feature flags
audit metadata
```

---

# 57. What PostgreSQL must never contain

Do not put:

```text
500M query history rows
warehouse metering history
daily cost facts
full storage history
Cortex usage history
full allocation ledger
```

into PostgreSQL.

That creates two analytical systems.

Snowflake is built for those workloads.

---

# 58. PostgreSQL schemas

Recommended logical separation:

```text
identity.*
tenant.*
connection.*
sync.*
governance.*
monitor.*
report.*
workflow.*
audit.*
```

Separate database:

```text
dagster_meta
```

for Dagster internals.

---

# 59. PostgreSQL tenant RLS

Every tenant-owned row has:

```text
tenant_id NOT NULL
```

Request:

```text
JWT
 ↓
FastAPI
 ↓
tenant context
 ↓
PostgreSQL session
 ↓
RLS policy
```

Application filtering is not enough.

Use:

```text
WHERE tenant_id = ...
```

plus PostgreSQL RLS as defense in depth.

---

# 60. PostgreSQL indexes

Typical composite indexes:

```text
tenant_id + id

tenant_id + status

tenant_id + account_id

tenant_id + created_at

tenant_id + resource_type + resource_id
```

Never rely on global scans.

---

# 61. PostgreSQL connection pooling

FastAPI should use a pool.

Workers should use separate pool limits.

Example isolation:

```text
API pool
Dagster pool
monitor pool
report pool
```

A report storm cannot consume all control-plane DB connections.

---

# 62. PostgreSQL caching

PostgreSQL is **not the principal cache**.

Small duplicated control-plane derived data is acceptable:

```text
latest sync state
current allocation version
dashboard metadata
current account capability map
```

But analytical result caching belongs elsewhere.

---

# 63. Three-level query acceleration architecture

Use:

```text
L1 React/browser
L2 Redis
L3 Snowflake SERVING marts
```

not:

```text
Snowflake
→ copy everything into PostgreSQL
```

---

# 64. Redis / ElastiCache

Redis stores disposable performance data.

Examples:

```text
dashboard responses
filter options
dimension dictionaries
tenant navigation tree
recent KPI responses
monitor counters
session-adjacent state
rate limits
distributed locks
```

Every cache key includes:

```text
tenant_id
```

Example:

```text
finops:{tenant}:home:{period}:{filters_hash}
```

---

# 65. Redis TTL strategy

Different TTLs:

```text
navigation       10 min
recent KPIs       1–5 min
historical KPI   15–60 min
static metadata   several hours
```

But prefer invalidation over arbitrary long TTL when practical.

---

# 66. Dataset-version cache invalidation

Each serving dataset gets:

```text
dataset_version
materialized_at
```

Redis key:

```text
tenant
dataset
dataset_version
filter_hash
```

When dbt materializes new data:

```text
version increments
```

old cache naturally becomes unreachable.

This is more reliable than trying to delete every affected Redis key.

Dagster can also track asset/data versions for materialized assets.

---

# 67. Snowflake serving layer

The most important analytical cache is actually Snowflake itself.

Create purpose-built serving tables:

```text
serving_home_daily
serving_cost_explorer
serving_warehouse_daily
serving_workload_daily
serving_team_daily
serving_budget_daily
serving_insight_summary
```

The API should not execute enormous joins for every UI click.

---

# 68. Query routing

Backend decides:

### Control request

```text
GET /users
GET /monitors
GET /connections
```

→ PostgreSQL.

### Analytical request

```text
GET /cost
GET /warehouse/...
GET /queries
```

→ Redis → Snowflake.

### Long-running analysis

```text
POST /analysis/deep-dive
```

→ asynchronous job.

---

# 69. FastAPI layer

FastAPI is stateless.

Responsibilities:

```text
authentication
authorization
tenant context
validation
pagination
API contracts
cache lookup
Snowflake query execution
async job submission
audit events
```

No financial business logic hidden in route handlers.

---

# 70. Analytical API contracts

Example:

```text
GET /v1/cost

period
grain
metrics
dimensions
filters
sort
limit
cursor
```

The frontend must not send arbitrary SQL.

Supported dimensions and metrics come from a server-side semantic registry.

---

# 71. Semantic registry

Define canonical metrics once.

Example:

```yaml
metric: warehouse_cost
source: mart_warehouse_cost
aggregation: sum
unit: currency
supports:
  - account
  - warehouse
  - environment
  - team
```

Likewise:

```text
idle_cost
query_cost
credits
budget_variance
potential_savings
```

This prevents KPI definitions drifting between pages.

---

# 72. Cost reconciliation

Every daily period produces:

```text
source billed usage
      ↓
canonical service ledgers
      ↓
allocated ledger
```

KPIs:

```text
billing source cost
ledger cost
difference
difference %
direct attribution %
allocated %
unallocated %
```

State:

```text
PENDING
MATCHED
WARNING
FAILED
```

---

# 73. Financial invariants

Examples:

```text
SUM(service ledgers)
≈ billed total
```

and:

```text
direct
+
allocated
+
shared
+
unallocated
=
100% billed spend
```

Never silently hide unattributed spend.

---

# 74. FinOps Cost Explorer

Global entry point.

```text
Spend
Forecast
Budget
Savings
Allocation Coverage
```

Dimensions:

```text
organization
account
region
service
warehouse
database
schema
object
user
role
application
workload
team
cost center
environment
tag
query hash
dbt project
dbt model
```

---

# 75. Warehouse analytics

Warehouse page:

```text
Spend
Credits
Query-attributed compute
Idle
Utilization
Queries
Queueing
Failures
Workloads
Users
Applications
```

Drill down to query.

---

# 76. Query Cost Explorer

Columns include:

```text
query_id
query_hash
query_parameterized_hash
cost
credits
warehouse
user
role
application
workload
duration
queue
compilation
bytes
spill
tables
query_tag
```

Support:

```text
saved views
filters
grouping
pivot
export
```

---

# 77. Workload intelligence

Native workloads:

```text
dbt
Power BI
Tasks
Stored Procedures
Snowpipe
Dynamic Tables
Native Apps
SPCS
Cortex
Custom Apps
Ad Hoc
```

Each workload exposes:

```text
cost
frequency
performance
owners
resources
budget
anomalies
insights
```

---

# 78. dbt experience

Hierarchy:

```text
dbt
  ↓
project
  ↓
environment
  ↓
invocation
  ↓
model
  ↓
query
```

Metrics:

```text
runs
cost/run
cost/model
frequency
duration
failure
warehouse
query count
regression
```

---

# 79. Tag Studio

Bridge Data owns an external semantic tagging layer.

Dimensions:

```text
business_unit
team
owner
cost_center
product
project
environment
application
customer
domain
workload
SLA
criticality
```

Tagging works even when Snowflake native tags are incomplete.

---

# 80. Sources for virtual tags

Rules can use:

```text
Snowflake tags
warehouse
database
schema
object
user
role
query tag
client application
SQL metadata
dbt project
dbt model
Power BI
query hash
table access
custom metadata
```

---

# 81. Tag rule lifecycle

```text
DRAFT
 ↓
SIMULATE
 ↓
REVIEW
 ↓
PUBLISH
 ↓
VERSIONED
```

Never activate a mass allocation rule without preview.

---

# 82. Allocation engine

Tagging:

```text
"What is this?"
```

Allocation:

```text
"Who pays for this?"
```

Methods:

```text
direct
fixed %
proportional
query-cost based
usage based
weighted
shared pool
residual
manual adjustment
```

---

# 83. Shared warehouse example

```text
WH_SHARED
$100,000

Finance     42%
Marketing   26%
Operations  18%
Data        10%
Idle         4%
```

Idle policy configurable:

```text
owner absorbs idle
or
consumer proportional
or
platform cost center
```

---

# 84. Usage Group Sets

Support parallel classification systems.

```text
Teams
Products
Cost Centers
Environments
Business Units
Customers
```

The same $1 may simultaneously belong to:

```text
Team = Finance
Product = Payments
Environment = Production
Cost Center = CC4210
```

This is essential.

---

# 85. Showback

Business unit portal:

```text
Current spend
Budget
Forecast
MoM
Top workloads
Top warehouses
New spend
Anomalies
Potential savings
```

Showback does not financially transfer costs.

---

# 86. Chargeback

Chargeback produces a financially traceable allocation.

Example:

```text
FINANCE
September

Warehouse compute       $48,320
Idle                      2,014
Storage                   4,811
Serverless                1,520
AI                          822
Transfer                    201
────────────────────────────────
Total                    $57,688
```

Every amount supports:

```text
Explain
```

---

# 87. Explain This Number

Universal feature.

Click:

```text
$57,688
```

returns:

```text
Chargeback
  ↓
Allocation rules
  ↓
Usage groups
  ↓
Resources
  ↓
Canonical ledger
  ↓
Raw Snowflake source
  ↓
source batch/file
```

This should be treated as a platform capability.

---

# 88. Allocation quality

Dashboard:

```text
Coverage              97.8%
Direct attribution    73.1%
Rule attribution      18.2%
Shared                 6.5%
Unallocated            2.2%

Conflicts                 7
Unowned resources        23
```

Clicking a number opens remediation.

---

# 89. Budgets

Budget scope:

```text
organization
account
service
team
usage group
project
warehouse
application
workload
custom filter
```

Metrics:

```text
actual
budget
remaining
forecast
burn rate
variance
days remaining
```

---

# 90. Monitor engine

One generic model:

```text
DATASET
 +
SCOPE
 +
METRIC
 +
AGGREGATION
 +
WINDOW
 +
CONDITION
 +
SCHEDULE
 +
DESTINATION
```

No independent hard-coded alert engine for every product page.

---

# 91. Monitor types

```text
scheduled report
static threshold
relative threshold
results found
period comparison
anomaly
budget breach
forecast breach
new resource
cost regression
missing activity
SLA violation
sync failure
```

---

# 92. Partition monitors

Example:

```text
Metric:
daily query cost

Partition:
dbt_model

Condition:
anomaly HIGH
```

Automatically monitors every model.

Same mechanism supports:

```text
warehouse
team
user
application
account
Cortex model
```

---

# 93. Monitor processing architecture

```text
Dagster schedule
      ↓
monitor planner
      ↓
Snowflake serving mart
      ↓
evaluate deterministic rules
      ↓
Python anomaly engine where required
      ↓
MONITOR_EVENT
      ↓
deduplicate/suppress
      ↓
notification
```

---

# 94. Alert deduplication

Without this the product becomes unusable.

Fingerprint:

```text
tenant
monitor
partition
condition
time bucket
```

States:

```text
OPEN
ACKNOWLEDGED
INVESTIGATING
RESOLVED
```

Repeated events update occurrence count rather than sending infinite incidents.

---

# 95. Notification destinations

P0:

```text
Email
Slack
Teams
Webhook
```

Later:

```text
Jira
PagerDuty
Opsgenie
```

---

# 96. Premium alert content

Never send:

```text
Cost threshold exceeded.
```

Send:

```text
ETL_PRD spend increased 41%

Impact
+$4,281/day

Started
06:00 UTC

Main contributor
dbt project FINANCE

Primary model
daily_transactions

Change
execution count 4.2x

Likely avoidable cost
$2.1K–$3.0K/day

[Investigate]
```

---

# 97. Insight Engine

Insight contract:

```text
insight_id
type
scope
resource

detected_at
first_seen
last_seen

baseline
current

evidence
estimated_savings
confidence
severity
effort

owner
status
recommended_action
```

---

# 98. Warehouse insights

Examples:

```text
idle
auto-suspend
rightsizing
under-utilization
over-provisioned multi-cluster
concurrency mismatch
resume/suspend thrashing
warehouse consolidation
```

---

# 99. Query insights

```text
cost regression
frequency regression
spill
poor pruning
exploding join
high compilation
cloud-services anomaly
retry waste
```

---

# 100. Storage insights

```text
unused table
never read
large time travel
large fail-safe
unexpected growth
```

---

# 101. Pipeline insights

```text
dbt model overscheduled
task overscheduled
low-change/high-frequency execution
failure/retry waste
duplicated pipeline
```

---

# 102. Snowpipe insights

```text
tiny files
high ingestion frequency
low bytes/file
cost regression
```

---

# 103. Cortex insights

```text
model cost spike
expensive model
token/request increase
user concentration
agent anomaly
search anomaly
cost per business transaction increase
```

---

# 104. SPCS insights

```text
compute pool underutilized
idle compute
unexpected scaling
application cost regression
```

---

# 105. Insight deep dive

Every insight opens:

```text
WHAT HAPPENED
WHY
WHEN
FINANCIAL IMPACT
EVIDENCE
HISTORY
ROOT CONTRIBUTORS
AFFECTED RESOURCES
RECOMMENDED ACTION
```

---

# 106. Insight lifecycle

```text
Detected
Reviewed
Assigned
Planned
Implemented
Verifying
Validated
```

Other states:

```text
Dismissed
Accepted Risk
Not Applicable
```

---

# 107. Action tracking

Action object:

```text
action
resource
owner
implemented_at
related_insight
expected_saving
baseline_period
verification_period
realized_saving
confidence
status
```

Examples:

```text
resize warehouse
change autosuspend
change schedule
rewrite query
drop unused object
change Cortex model
```

---

# 108. Realized savings

FinOps must close the loop.

```text
recommendation
      ↓
$8K estimated saving
      ↓
action implemented
      ↓
baseline model frozen
      ↓
post-change observation
      ↓
normalized comparison
      ↓
$7.2K realized
```

Do not count:

```text
estimated savings
```

as:

```text
realized savings
```

---

# 109. Reporting engine

Reports are generated from reusable components.

```text
KPI
Trend
Breakdown
Waterfall
Table
Top N
Budget
Insight
Monitor summary
Allocation summary
Narrative
```

Templates:

```text
Executive FinOps
CFO Monthly
Platform Review
Team Showback
Chargeback Statement
Warehouse Review
dbt Review
AI/Cortex Review
```

---

# 110. Scheduled reporting

Schedules:

```text
daily
weekly
monthly
quarterly
```

Channels:

```text
email
Slack
Teams
secure link
```

Formats:

```text
PDF
PNG
CSV
```

Report generation is a Dagster/report-worker job.

Not inside the API process.

---

# 111. PostgreSQL report configuration

PostgreSQL stores:

```text
report_definition
report_layout
filters
schedule
recipients
template_version
```

Snowflake stores the metrics.

Generated report files go to S3.

---

# 112. Home page

The home page must answer:

```text
How much?
Why?
Who?
Risk?
Opportunity?
What do I do?
```

Example:

```text
Spend                 $214K
Forecast               $231K
Budget                 $225K
Potential savings       $31K

Allocation coverage    97.4%
Budget risks               3
Open anomalies            11
Open insights             34
Realized savings YTD    $91K
```

Below:

```text
Spend drivers
New spend
Anomalies
Budget risks
Unallocated spend
Top insights
Recent actions
```

---

# 113. Authentication for SaaS users

Snowflake WIF does not authenticate web users.

Use a web identity layer such as:

```text
Amazon Cognito
```

supporting:

```text
email/password
MFA
OIDC
SAML
Microsoft Entra
Okta
```

---

# 114. SaaS RBAC

Roles:

```text
Organization Owner
Organization Admin
FinOps Admin
Snowflake Admin
Team Admin
Analyst
Viewer
Auditor
```

Role and scope are independent.

Example:

```text
role = Viewer

scope =
Finance
+
PROD account
```

---

# 115. Analytical RLS

Snowflake serving tables also contain:

```text
tenant_id
organization_id
account_id
usage_group_id
```

Row Access Policies can enforce data access at serving boundaries.

Therefore:

```text
API authorization
+
PostgreSQL RLS
+
Snowflake RLS
```

provides defense in depth.

---

# 116. Redis security

Redis contains no unrestricted cross-tenant cache keys.

Always:

```text
tenant_id
+
permission_scope_hash
```

because two users in the same tenant can have different scopes.

Cache key example:

```text
tenant:abc:
scope:9f21:
dataset:cost:
version:183:
filters:8ac3
```

---

# 117. Query text privacy

Tenant setting:

```text
FULL
SANITIZED
METADATA_ONLY
```

Sanitization occurs as early as possible.

If configured:

```text
SQL text
   ↓
Python sanitizer
   ↓
Parquet
```

Meaning sensitive literals never enter central storage.

---

# 118. Audit

Audit:

```text
login
connection changes
permission changes
users
teams
tag rules
allocation rules
budgets
monitors
reports
insights
actions
exports
API credentials
operator changes
```

Fields:

```text
tenant
actor
action
object
before
after
timestamp
request_id
IP
user_agent
```

---

# 119. Onboarding

## Step 1

Create Bridge Data organization.

## Step 2

Connect Snowflake organization using generated WIF configuration.

## Step 3

Discover Snowflake accounts.

## Step 4

Choose accounts.

## Step 5

Generate account WIF configuration.

## Step 6

Validate privileges/capabilities.

## Step 7

Start initial historical synchronization.

## Step 8

Show live ingestion progress.

## Step 9

Run reconciliation.

## Step 10

Detect ownership/classification.

## Step 11

Simulate allocation.

## Step 12

Create budgets.

## Step 13

Create recommended monitors.

## Step 14

Present first actionable insights.

Onboarding ends at:

```text
FIRST VALUE
```

not:

```text
CONNECTION CREATED
```

---

# 120. Onboarding progress UX

Example:

```text
Accounts                 8 / 8
Metering               365 / 365 days
Queries                 241 / 365 days
Storage                 Complete
Serverless              Complete
Objects                 Complete

Snowpipe loaded          2.4B rows
dbt transformed          2.3B rows

Reconciliation          Pending

Estimated coverage      96%
```

---

# 121. Data health center

Dedicated product page.

```text
ACCOUNT PROD_EU

Connection          Healthy
Extraction          Healthy
S3 landing          Healthy
Snowpipe            Healthy
dbt                 Healthy
Reconciliation      Healthy

Query History
source current      08:42
platform current    08:47
lag                   5m
```

---

# 122. Dagster technical observability

Internal engineering gets:

```text
asset health
asset lineage
materialization status
backfill progress
run failures
retry status
partition state
```

Customer-facing UI receives only product-relevant status.

Do not expose Dagster directly to customers.

---

# 123. Platform observability

CloudWatch/OpenTelemetry metrics:

```text
API latency
API error rate

worker utilization
worker failures

Snowflake connection latency

rows extracted
bytes extracted
Parquet size
S3 files

Snowpipe lag
dbt duration

Redis hit ratio
Postgres connection usage

report duration
monitor evaluation duration
```

---

# 124. Data observability

Three levels.

### Transport checks

```text
file exists
manifest valid
row count
checksum
Snowpipe loaded
```

### Transformation checks

```text
dbt tests
asset checks
freshness
uniqueness
relationships
```

### Financial checks

```text
ledger reconciliation
allocation coverage
invoice difference
```

---

# 125. Failure model

Example:

```text
Snowflake extraction failed
```

Dagster:

```text
retry
↓
backoff
↓
retry
↓
mark account/source degraded
↓
preserve watermark
↓
alert internally
```

Watermark advances **only after durable success**.

---

# 126. Exactly-once business semantics

Infrastructure is not exactly-once.

S3 notifications are at least once. Snowpipe loads are file-based and ordering is not guaranteed.

Therefore exactly-once is achieved logically using:

```text
immutable batch IDs
unique files
natural keys
deduplication
MERGE
watermarks
idempotent transformations
```

---

# 127. Replay

Admin can request:

```text
tenant
account
source
2026-09-01 → 2026-09-07
```

Workflow:

```text
locate S3 batches
       ↓
validate manifests
       ↓
re-ingest/rebuild RAW if needed
       ↓
select dbt assets
       ↓
run downstream Python
       ↓
reconcile
```

No customer Snowflake query required if source Parquet is retained.

---

# 128. Data retention

Separate policies:

```text
S3 raw transport
Snowflake raw
Snowflake canonical
Postgres audit
Reports
Dagster history
```

S3 may transition old source files to cheaper storage after the operational replay period.

Do not couple all retention periods.

---

# 129. CI/CD

Repositories could be:

```text
/apps/web
/apps/api

/services/extractor
/services/orchestrator
/services/reporting

/dbt

/infra/terraform
```

Or mono-repo with equivalent boundaries.

---

# 130. Deployment pipeline

```text
lint
unit tests
Python tests
dbt parse
dbt compile
dbt tests
Dagster definitions validation
API tests
container build
security scan
deploy staging
integration test
deploy production
```

Dagster definitions should be validated before deployment.

---

# 131. dbt CI

Modified dbt models should run against isolated CI schemas.

Financial models additionally require:

```text
golden fixtures
reconciliation fixtures
allocation fixtures
```

A successful SQL compilation is insufficient for ledger code.

---

# 132. Python testing

Unit-test:

```text
window calculator
Parquet serializer
schema converter
WIF connection
query parser
classification
anomaly logic
allocation helper
forecast
savings
```

Integration-test actual Snowflake extraction separately.

---

# 133. Schema contract testing

CI compares Snowflake adapters against a versioned source contract.

Example:

```yaml
QUERY_HISTORY:
  QUERY_ID: string
  START_TIME: timestamp
  WAREHOUSE_NAME: string?
  QUERY_HASH: string?
```

BCR changes trigger controlled adaptation.

---

# 134. Deployment environments

At minimum:

```text
DEV
STAGING
PROD
```

Separate:

```text
AWS accounts
Snowflake databases
Postgres databases
S3 buckets
Redis
IAM roles
KMS keys
```

Production data never copied casually into DEV.

---

# 135. Security boundaries

Five boundaries:

```text
USER PLANE
CONTROL PLANE
CONNECTOR PLANE
DATA PLANE
ACTION PLANE
```

A compromise of one does not automatically grant every capability.

---

# 136. Encryption

Use:

```text
TLS in transit
KMS at rest
S3 encryption
Aurora encryption
Redis encryption
Snowflake encryption
Secrets Manager
```

No secrets in:

```text
Git
Docker image
environment file committed to repo
dbt project
```

---

# 137. Secrets Manager

Contains only necessary application secrets:

```text
Slack credentials
Teams credentials
webhook secrets
email integration secrets
third-party OAuth
```

Not customer Snowflake passwords/private keys.

---

# 138. Cost control of Bridge Data itself

Your own SaaS needs FinOps.

Measure per tenant:

```text
Snowflake compute
Snowpipe
storage
AWS extraction
S3
Redis
Postgres
report generation
egress
```

Create:

```text
tenant_platform_cost
```

to calculate SaaS gross margin.

---

# 139. Workload cost isolation

Every heavy internal Snowflake workload is tagged:

```text
bridge_component=dbt
bridge_job=ledger
bridge_tenant=...
bridge_run_id=...
```

so Bridge Data can understand the cost of processing each customer.

---

# 140. Heavy analysis model

Large interactive request:

```text
Analyze 365 days
by query hash
for 17 accounts
```

must not block an HTTP request.

Use:

```text
API
 ↓
job record
 ↓
Dagster/Python worker
 ↓
Snowflake result table
 ↓
cache
 ↓
completed
```

Frontend polls or receives status.

---

# 141. Small interactive analysis

For common requests:

```text
7 days
team
daily cost
```

query:

```text
Redis
 ↓ miss
Snowflake serving mart
 ↓
Redis
 ↓
UI
```

Target sub-second experience after cache and low-seconds cold response.

---

# 142. No PostgreSQL analytical mirror

Explicit architectural prohibition:

```text
Snowflake
   ↓
sync millions of rows
   ↓
PostgreSQL
   ↓
UI
```

Do not do this.

It introduces:

```text
duplicate truth
sync problems
storage duplication
Postgres maintenance
index tuning
RLS complexity
reconciliation problems
```

Use precomputed Snowflake serving tables instead.

---

# 143. Feature navigation

```text
Home

Explore
 ├─ Cost Explorer
 ├─ Warehouses
 ├─ Queries
 ├─ Workloads
 ├─ Storage
 ├─ Serverless
 ├─ AI / Cortex
 └─ SPCS

Allocate
 ├─ Tag Studio
 ├─ Allocation Studio
 ├─ Usage Groups
 ├─ Showback
 └─ Chargeback

Govern
 ├─ Budgets
 ├─ Monitors
 └─ Reports

Optimize
 ├─ Insights
 ├─ Actions
 └─ Savings

Dashboards

Platform
 ├─ Data Health
 └─ Integration Health

Settings
```

Product story:

```text
EXPLORE
   ↓
UNDERSTAND
   ↓
ALLOCATE
   ↓
GOVERN
   ↓
OPTIMIZE
   ↓
VERIFY
```

---

# 144. Product personas

## FinOps

Focus:

```text
invoice
allocation
showback
chargeback
budget
forecast
saving
```

## Snowflake administrator

```text
warehouse
idle
serverless
storage
anomaly
optimization
```

## Data engineer

```text
workload
dbt
tasks
Snowpipe
pipelines
query regression
```

## Engineering manager

```text
team spend
budget
applications
actions
```

## CFO / management

```text
spend
forecast
budget
business allocation
realized savings
```

---

# 145. API-first design

One API is consumed by:

```text
Bridge UI
customer integrations
future CLI
future Terraform
future MCP
```

Do not build a separate internal UI API and public API.

---

# 146. Future FinOps Copilot

AI comes after deterministic foundations.

It consumes semantic APIs.

Example:

```text
Why did spend increase by $41K?
```

The Copilot queries:

```text
metric registry
cost explorer
change detection
workload attribution
insight evidence
```

and returns citations/deep links.

It does not hallucinate SQL against arbitrary tables.

---

# 147. Future automation

Later:

```text
auto-suspend adjustment
warehouse resizing
cluster configuration
schedule modification
```

Requires:

```text
separate WIF identity
explicit opt-in
allowlist
bounds
approval
rollback
audit
verification
```

---

# 148. Recommended implementation sequence

## Phase 0 — Platform

Build:

```text
AWS network
FastAPI
PostgreSQL
Redis
Cognito
Dagster OSS
central Snowflake
S3
Snowpipe
WIF
```

---

## Phase 1 — Data synchronization

Build first:

```text
source registry
connection discovery
Python extractor
Arrow/Parquet
S3 batch manifest
Snowpipe
RAW
watermarking
replay
data health
```

Before sophisticated dashboards.

---

## Phase 2 — Financial kernel

dbt:

```text
staging
warehouse compute
query attribution
idle
storage
serverless
canonical ledger
reconciliation
```

This is the core IP.

---

## Phase 3 — Cost Explorer

Build:

```text
organization
account
service
warehouse
workload
query
```

with reusable semantic metrics.

---

## Phase 4 — Ownership

Build:

```text
Tag Studio
Usage Groups
Allocation Studio
showback
chargeback
```

---

## Phase 5 — Governance

Build:

```text
budgets
monitor engine
notifications
scheduled reports
```

---

## Phase 6 — Optimization

Build:

```text
insight engine
query insights
warehouse insights
storage insights
workload insights
```

---

## Phase 7 — Actions

Build:

```text
ownership
workflow
verification
realized savings
```

---

# 149. Recommended physical repositories

A clean mono-repo could look like:

```text
bridge-finops/
│
├── apps/
│   ├── web/
│   └── api/
│
├── services/
│   ├── extractor/
│   ├── orchestrator/
│   ├── intelligence/
│   └── reporting/
│
├── data/
│   ├── dbt/
│   ├── contracts/
│   └── fixtures/
│
├── packages/
│   ├── snowflake-client/
│   ├── parquet/
│   ├── semantic-metrics/
│   └── common/
│
├── infra/
│   └── terraform/
│
├── docs/
└── tests/
```

---

# 150. Dagster project organization

```text
services/orchestrator/
├── definitions.py
│
├── assets/
│   ├── extract.py
│   ├── ingest.py
│   ├── dbt.py
│   ├── intelligence.py
│   ├── serving.py
│   └── reports.py
│
├── jobs/
├── schedules/
├── sensors/
├── checks/
├── resources/
└── partitions/
```

---

# 151. dbt project organization

```text
data/dbt/
├── models/
│   ├── staging/
│   │
│   ├── intermediate/
│   │
│   ├── ledger/
│   │   ├── warehouse/
│   │   ├── storage/
│   │   ├── serverless/
│   │   ├── cortex/
│   │   └── transfer/
│   │
│   ├── allocation/
│   ├── marts/
│   └── serving/
│
├── macros/
├── tests/
├── seeds/
└── snapshots/
```

---

# 152. Extraction package

```text
services/extractor/
├── sources/
│   ├── query_history.py
│   ├── warehouse_metering.py
│   ├── storage.py
│   └── ...
│
├── snowflake/
│   ├── wif.py
│   ├── executor.py
│   └── capability.py
│
├── parquet/
│   ├── writer.py
│   ├── schema.py
│   └── manifest.py
│
├── s3/
└── state/
```

Each source adapter has the same interface.

---

# 153. Source adapter contract

Conceptually:

```python
class SourceAdapter:

    def capabilities(...)

    def plan_windows(...)

    def build_query(...)

    def extract(...)

    def normalize(...)

    def validate(...)

    def write_parquet(...)

    def build_manifest(...)
```

Adding a Snowflake service becomes predictable.

---

# 154. End-to-end asset lineage example

```text
customer_snowflake/query_history
              │
              ▼
extract/query_history
              │
              ▼
s3/query_history_parquet
              │
              ▼
raw/query_history
              │
              ▼
stg/query_history
              │
              ▼
int/query_workload
              │
              ├───────────────┐
              ▼               ▼
ledger/query_cost      python/query_features
              │               │
              └───────┬───────┘
                      ▼
               mart/query_cost
                      │
             ┌────────┼────────┐
             ▼        ▼        ▼
           API     Monitor   Insight
```

This graph is visible internally in Dagster.

---

# 155. Golden rule for transformation ownership

Use:

```text
Can this be expressed deterministically and efficiently in SQL?
    YES
      ↓
     dbt

Does it require algorithmic/statistical/text processing?
    YES
      ↓
    Python
```

Dagster only connects them.

---

# 156. Anti-patterns explicitly prohibited

Do not:

```text
put transformations inside Dagster ops
```

Do not:

```text
copy analytical facts into PostgreSQL for performance
```

Do not:

```text
use Redis as durable state
```

Do not:

```text
delete source Parquet immediately after Snowpipe
```

Do not:

```text
assume S3 notifications are exactly once
```

Do not:

```text
advance a watermark before durable batch completion
```

Do not:

```text
mix provisional and reconciled costs silently
```

Do not:

```text
build individual alert systems per page
```

Do not:

```text
create separate cost formulas in frontend/API/dbt
```

Do not:

```text
let customer-specific code enter the orchestration repository
```

---

# 157. Definition of Done — data platform

A source is production-ready only if it supports:

```text
capability discovery
WIF
historical backfill
incremental sync
overlap
Parquet
manifest
Snowpipe
deduplication
schema drift
replay
freshness
dbt tests
Dagster observability
reconciliation where relevant
```

---

# 158. Definition of Done — SaaS

A new customer can:

```text
register
   ↓
connect Snowflake via WIF
   ↓
discover Organization/accounts
   ↓
sync one year
   ↓
see synchronization state
   ↓
reconcile costs
   ↓
explore costs
   ↓
classify ownership
   ↓
simulate allocation
   ↓
create chargeback/showback
   ↓
configure budgets
   ↓
receive monitors
   ↓
receive reports
   ↓
obtain actionable insights
   ↓
assign actions
   ↓
measure realized savings
```

without Bridge Data manually intervening.

---

# 159. Final architecture

The platform can ultimately be summarized as:

```text
              ┌─────────────────────────┐
              │ CUSTOMER SNOWFLAKE      │
              │ Organizations + Accounts│
              └────────────┬────────────┘
                           │ WIF
                           ▼
              ┌─────────────────────────┐
              │ PYTHON EXTRACTION       │
              │ ECS / Fargate           │
              └────────────┬────────────┘
                           │
                     Arrow / Parquet
                           │
                           ▼
              ┌─────────────────────────┐
              │ S3 IMMUTABLE JOURNAL    │
              │ batches + manifests     │
              └────────────┬────────────┘
                           │
                       Snowpipe
                           │
                           ▼
        ┌──────────────────────────────────────┐
        │ CENTRAL SNOWFLAKE                    │
        │                                      │
        │ RAW                                  │
        │  ↓                                   │
        │ dbt STAGING                          │
        │  ↓                                   │
        │ dbt INTERMEDIATE                     │
        │  ↓                                   │
        │ dbt LEDGER                           │
        │  ↓                                   │
        │ Python intelligence                  │
        │  ↓                                   │
        │ dbt MARTS                            │
        │  ↓                                   │
        │ dbt SERVING                          │
        └───────────────────┬──────────────────┘
                            │
                            ▼
                    ┌──────────────┐
                    │ FASTAPI      │
                    └──────┬───────┘
                           │
             ┌─────────────┼─────────────┐
             │             │             │
             ▼             ▼             ▼
       PostgreSQL        Redis       Snowflake
       Control           Cache       Analytics
       Plane                         Truth
             │             │             │
             └─────────────┼─────────────┘
                           │
                           ▼
                         React


        ┌──────────────────────────────────────┐
        │ DAGSTER OSS                          │
        │                                      │
        │ orchestrates                         │
        │ partitions                           │
        │ schedules                            │
        │ sensors                              │
        │ retries                              │
        │ backfills                            │
        │ lineage                              │
        │ quality                              │
        │ dependencies                         │
        └──────────────────────────────────────┘
```

The resulting responsibility matrix is deliberately simple:

```text
CUSTOMER SNOWFLAKE
    source

PYTHON
    extract + complex algorithms

PARQUET / S3
    immutable transport + replay

SNOWPIPE
    ingestion

DBT
    analytical transformation

SNOWFLAKE
    analytical truth

DAGSTER
    orchestration

POSTGRESQL
    SaaS transactional state

REDIS
    acceleration

FASTAPI
    secure product API

REACT
    product experience
```

That separation should remain an architectural invariant as the product grows.

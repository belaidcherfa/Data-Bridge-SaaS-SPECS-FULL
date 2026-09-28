-- contract=snowflake-ops-internal-build-rows version=1 status=DRAFT owner_task=ORC-104 decisions=D-05,D-06 last_changed=2026-09-28
-- Migration block: K9 V0800-V0899 (OPS_INTERNAL). Artifact row "Per-tenant build rows OPS_INTERNAL.BUILD_MODEL_TENANT_ROWS"
-- (replaces ops.processing_ledger; RECONCILIATION U-06, U-25 - the name "processing ledger" stays with ORC-101's BATCH_PROCESSING).
-- Producer: ORC-104-S02 (insert after each validated build, derived from PUBLICATION.PARTITION_REVISION row counts - no extra scan of
-- fact tables); ORC-104-S03 fills BUILD_MODEL_CREDITS from central QUERY_ATTRIBUTION_HISTORY joined to the QUERY_TAG v1 build/model keys.
-- Consumer: OPS-009-S05/S06 transform-cost allocation into BRIDGE_INTERNAL_COST (credits of a (build, model) split by rows_written per
-- tenant; zero-row models by workset partition share; warehouse idle -> UNALLOCATED_IDLE).
-- Golden fixture (ORC G-ORC-12 resolution, arithmetic): model m of build b metered 10 credits; tenant A wrote 700 rows, tenant B 300 rows
--   -> A = 10 x 700 / (700 + 300) = 7 credits, B = 10 x 300 / 1000 = 3 credits; warehouse idle 2 credits -> UNALLOCATED_IDLE 2;
--   allocated 7 + 3 + unallocated 2 = 12 = metered warehouse credits for the window.
-- Access: OPS_INTERNAL is operator-only (ORC-104-S07); no customer, serving or tenant principal has any grant.

create table if not exists bridge.ops_internal.build_model_tenant_rows (
  build_id              varchar(36)      not null comment 'PUBLICATION.BUILD id (ADR-014).',
  lane                  varchar(16)      not null comment 'STEADY | BACKFILL | REPAIR | SIMULATION (ORC-003 lanes; per-tenant repair builds included).',
  model                 varchar(256)     not null comment 'dbt model unique name (QUERY_TAG v1 key "model").',
  layer                 varchar(32)      not null comment 'dbt layer (staging|intermediate|ledger|allocation|serving|mart|checks).',
  dataset_id            varchar(128)     comment 'Dataset id when the model is a revisioned dataset (datasets.yaml); null for views/ephemeral.',
  tenant_id             varchar(36)      not null comment 'Tenant UUID. x-privacy: INTERNAL',
  rows_written          number(38,0)     not null comment 'Sum of PARTITION_REVISION.row_count for (build, model, tenant).',
  partitions_written    number(38,0)     not null comment 'Workset partitions registered for (build, model, tenant), including zero-row partitions.',
  zero_row_partitions   number(38,0)     not null comment 'Partitions registered with row_count = 0 (corrections to empty).',
  build_started_at      timestamp_ntz(9) not null comment 'UTC.',
  build_ended_at        timestamp_ntz(9) not null comment 'UTC.',
  captured_at           timestamp_ntz(9) not null default sysdate() comment 'UTC insert time.',
  constraint build_model_tenant_rows_pk primary key (build_id, model, tenant_id) rely
)
cluster by (build_ended_at)
data_retention_time_in_days = 1
comment = 'ORC-104-S02. Per-tenant rows written per (build, model). Insert-only; one row per (build_id, model, tenant_id). Invariant: SUM(rows_written) over a (build, model) = SUM(PARTITION_REVISION.row_count) for that build and model. Retention 400 days (cost history for OPS-009).';

create table if not exists bridge.ops_internal.build_model_credits (
  build_id                 varchar(36)      not null comment 'PUBLICATION.BUILD id.',
  model                    varchar(256)     not null comment 'dbt model unique name.',
  warehouse_name           varchar(256)     not null comment 'Central warehouse used by the build.',
  usage_date               date             not null comment 'UTC date of query start.',
  query_count              number(38,0)     not null comment 'Queries tagged with (build, model).',
  credits_attributed       number(38,12)    not null comment 'Sum of QUERY_ATTRIBUTION_HISTORY.CREDITS_ATTRIBUTED_COMPUTE (+ QAS) for the tagged queries.',
  credits_source_version   varchar(64)      not null comment 'Source contract version of the central Account Usage view read.',
  collected_at             timestamp_ntz(9) not null default sysdate() comment 'UTC.',
  constraint build_model_credits_pk primary key (build_id, model, warehouse_name, usage_date) rely
)
cluster by (usage_date)
data_retention_time_in_days = 1
comment = 'ORC-104-S03. Central compute credits per (build, model) from Bridge''s own QUERY_ATTRIBUTION_HISTORY (latency TO VERIFY LIVE). Warehouse idle residual = WAREHOUSE_METERING_HISTORY credits - SUM(credits_attributed), allocated to UNALLOCATED_IDLE by OPS-009.';

grant select, insert on table bridge.ops_internal.build_model_tenant_rows to role bridge_orchestrator;
grant select, insert on table bridge.ops_internal.build_model_credits to role bridge_orchestrator;
grant select on table bridge.ops_internal.build_model_tenant_rows to role bridge_cost_loader;
grant select on table bridge.ops_internal.build_model_credits to role bridge_cost_loader;
grant select on table bridge.ops_internal.build_model_tenant_rows to role bridge_ops_reader;
grant select on table bridge.ops_internal.build_model_credits to role bridge_ops_reader;

-- contract=snowflake-ops-meta-processing-ledger version=1 status=DRAFT owner_task=ORC-101 decisions=D-04,D-05,D-06 last_changed=2026-09-28
-- Lane K4 (ORC/DBT), block V0300-V0399. Schema BRIDGE.OPS_META.
-- The D-06 processing ledger (ORC-101-S02; G-ORC-07): which accepted batches are consumed by which build, the
-- exact partition workset of every build, the per-tenant configuration pins (D-04) and the per-(build, dataset)
-- revision allocation. The only dbt variable is build_id; everything else a model needs is read from these tables
-- through the macros in_workset(), accepted_source(), pinned_config() and upstream_for_workset()
-- (data/dbt/macros/materializations/revisioned.md).
--
-- Writers: BRIDGE_PUBLISHER role (planner, gate, status updates, all running in the Dagster dbt code location);
--          BRIDGE_TRANSFORMER updates BUILD_DATASET progress from the revisioned materialization.
-- Readers: BRIDGE_TRANSFORMER, BRIDGE_PUBLISHER, BRIDGE_REVISION_GC, BRIDGE_OPS_READONLY. No customer-facing grants.
-- Idempotent (IF NOT EXISTS). Snowflake does not enforce PRIMARY KEY; writers use INSERT ... WHERE NOT EXISTS / MERGE.
--
-- BATCH_PROCESSING.status lifecycle (ORC-101-S07):
--   (no row) = accepted, never planned (anti-join; gap-safe, never a cursor over accepted_seq)
--   PENDING   -> IN_BUILD   planner includes the batch in build B (accepted_seq <= B.snapshot_seq)
--   IN_BUILD  -> BUILT      build B reached BUILT
--   IN_BUILD  -> PENDING    build B ended FAILED | CANCELLED | ABANDONED | FENCED (planner reset)
--   BUILT     -> PUBLISHED  PUBLISH_BATCH published the tenant (pub_seq = publication) or the tenant was ELIGIBLE with no change (pub_seq = tenant pointer, no_change = TRUE)
--   BUILT     -> GATED      the tenant was REJECTED by the gate (gated_count + 1; 3 consecutive -> PUBLICATION.TENANT_QUARANTINE)
--   GATED     -> IN_BUILD   retry in a later build (reason RETRY)

create table if not exists bridge.ops_meta.batch_processing (
    lane                    varchar(16)   not null comment 'Build lane consuming accepted batches: STEADY',
    batch_id                varchar(36)   not null comment 'CONTROL.ACCEPTED_BATCHES.batch_id (UUIDv7)',
    tenant_id               varchar(36)   not null,
    organization_id         varchar(36),
    account_id              varchar(36)            comment 'NULL for ORG-scope sources',
    source_id               varchar(64)   not null comment 'ING-001 registry source_id',
    accepted_seq            number(38,0)  not null comment 'CONTROL.ACCEPTED_BATCHES.accepted_seq (single-writer acceptance, ORC-101-S01)',
    status                  varchar(16)   not null comment 'PENDING | IN_BUILD | BUILT | PUBLISHED | GATED',
    build_id                varchar(36)            comment 'Build that last planned this batch',
    pub_seq                 number(38,0)           comment 'Publication that made the batch visible (status PUBLISHED)',
    no_change               boolean       not null default false comment 'PUBLISHED without a map change (identical candidate)',
    gated_count             number(38,0)  not null default 0 comment 'Consecutive GATED outcomes; reset to 0 on PUBLISHED',
    first_planned_at        timestamp_ntz(9) not null,
    last_status_at          timestamp_ntz(9) not null,
    constraint pk_batch_processing primary key (lane, batch_id)
)
cluster by (lane, status)
data_retention_time_in_days = 1
comment = 'K4/ORC-101-S02: D-06 processing ledger of accepted batches per build lane';

create table if not exists bridge.ops_meta.build_workset (
    build_id                varchar(36)   not null comment 'PUBLICATION.BUILD.build_id',
    dataset_id              varchar(64)   not null comment 'OPS_META.DATASET.dataset_id',
    tenant_id               varchar(36)   not null,
    scope_kind              varchar(32)   not null comment 'ACCOUNT | ORGANIZATION | TENANT (scope of scope_id)',
    scope_id                varchar(36)   not null comment 'account_id | organization_id | tenant_id',
    partition_start         timestamp_ntz(9) not null comment 'UTC start of the HOUR/DAY/MONTH partition, 1970-01-01 for ALL',
    revision_id             number(38,0)  not null comment 'OPS_META.BUILD_DATASET.revision_id of (build_id, dataset_id)',
    change_kind             varchar(8)    not null default 'BUILD' comment 'BUILD (materialize) | REMOVE (retention expiry / REPUBLISH_PRIOR removal: no rows written, map row closed)',
    reason                  varchar(16)   not null comment 'Highest-priority reason: RESTATEMENT > REPAIR > SHADOW > CONFIG > NEW_DATA > ANTI_ENTROPY > RETRY > RETENTION > SIMULATION > REPUBLISH',
    reasons                 array         not null comment 'All reasons that selected the partition',
    origin_refs             array                  comment 'batch_ids, config versions, repair/recovery plan ids that selected the partition (bounded to 50 entries)',
    planned_at              timestamp_ntz(9) not null,
    constraint pk_build_workset primary key (build_id, dataset_id, tenant_id, scope_id, partition_start)
)
cluster by (build_id, dataset_id)
data_retention_time_in_days = 1
comment = 'K4/ORC-101-S02: exact partitions of every build (steady <= 50,000, repair <= 200,000; a tenant is never split across builds of one lane)';

create table if not exists bridge.ops_meta.build_config_pin (
    build_id                varchar(36)   not null,
    tenant_id               varchar(36)   not null,
    config_kind             varchar(64)   not null comment 'CONFIG.CONFIG_VERSION.config_kind (see data/dbt/models/staging/config/_sources.yml)',
    config_version          number(38,0)  not null comment 'Latest header-complete version <= plan time (ORC-101-S05)',
    content_sha256          varchar(64)   not null comment 'CONFIG_VERSION.content_sha256 at pin time (drift guard)',
    pinned_at               timestamp_ntz(9) not null,
    constraint pk_build_config_pin primary key (build_id, tenant_id, config_kind)
)
cluster by (build_id)
data_retention_time_in_days = 1
comment = 'K4/ORC-101-S05: per-tenant configuration pins of a build (D-04); read by pinned_config()';

create table if not exists bridge.ops_meta.build_dataset (
    build_id                varchar(36)   not null,
    dataset_id              varchar(64)   not null,
    revision_id             number(38,0)  not null comment 'Allocated from PostgreSQL platform.analytics_revision_seq, one per (build, dataset) (DBT-101-S07)',
    model_unique_id         varchar(256)           comment 'dbt unique_id (model.bridge.<name>) or py/<engine>/<output>',
    code_version            varchar(64)   not null comment 'git SHA of the image that built the dataset',
    model_checksum          varchar(64)            comment 'dbt manifest checksum of the model SQL (Dagster code_version)',
    status                  varchar(16)   not null comment 'PLANNED | BUILT | SKIPPED | FAILED',
    workset_partitions      number(38,0)  not null default 0,
    partitions_registered   number(38,0)  not null default 0,
    rows_written            number(38,0)  not null default 0,
    started_at              timestamp_ntz(9),
    ended_at                timestamp_ntz(9),
    error_code              varchar(64)            comment 'DBT_* / ORC_* problem code when FAILED',
    constraint pk_build_dataset primary key (build_id, dataset_id)
)
cluster by (build_id)
data_retention_time_in_days = 1
comment = 'K4/DBT-101: per-(build, dataset) revision allocation and materialization progress';

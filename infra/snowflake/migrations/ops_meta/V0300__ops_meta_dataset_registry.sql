-- contract=snowflake-ops-meta-dataset-registry version=1 status=DRAFT owner_task=DBT-101 decisions=D-05,D-06 last_changed=2026-09-28
-- Lane K4 (ORC/DBT), block V0300-V0399. Schema BRIDGE.OPS_META (created by the K1 baseline).
-- Purpose: machine-readable copies of data/contracts/datasets.yaml and data/contracts/checks.yaml used by
-- set-based SQL (planner closure, PUBLICATION.PREPARE_CANDIDATES gate, GC). The release pipeline syncs them
-- with an idempotent MERGE keyed by the primary keys below (tools/datasets_sync.py, DBT-101-S02);
-- application code never edits them by hand.
-- Idempotent: every object uses IF NOT EXISTS; applying the script twice is a no-op.
-- Snowflake does not enforce PRIMARY KEY/UNIQUE; the sync job and contract tests assert uniqueness.

create table if not exists bridge.ops_meta.dataset (
    dataset_id              varchar(64)   not null comment 'datasets.yaml dataset_id (= dbt model name, or <model>@<n> for versioned relations)',
    registry_version        number(38,0)  not null comment 'datasets.yaml registry_version that produced this row',
    owner_task              varchar(16)   not null,
    domain                  varchar(8)    not null comment 'FIN | ALC | WRK | GOV | INS | DBT | API',
    layer                   varchar(16)   not null comment 'intermediate | ledger | allocation | marts | serving | py_outputs',
    materialization         varchar(16)   not null comment 'revisioned | python_output',
    schema_name             varchar(64)   not null,
    table_name              varchar(128)  not null comment 'physical *_r table',
    scope_kind              varchar(32)   not null comment 'ACCOUNT | ORGANIZATION | ACCOUNT_OR_ORGANIZATION | TENANT',
    granularity             varchar(8)    not null comment 'HOUR | DAY | MONTH | ALL',
    time_column             varchar(64)            comment 'NULL iff granularity = ALL',
    measure_role            varchar(16)   not null,
    retention_class         varchar(24)   not null,
    retention_days          number(38,0)           comment 'NULL = hot_days (plan-configurable, QUERY_GRAIN)',
    rebuild_horizon_days    number(38,0)  not null,
    beyond_horizon          varchar(16)   not null comment 'REFUSE | RE_EXTRACT | CARRY_FORWARD',
    rap_policy              varchar(64)   not null comment 'security.rap_* attached at CREATE time',
    rap_args                array         not null,
    publication_phase       varchar(16)   not null comment 'CORE | INTELLIGENCE',
    homogeneity_required    boolean       not null default true,
    active                  boolean       not null default true,
    synced_at               timestamp_ntz(9) not null,
    constraint pk_dataset primary key (dataset_id)
)
data_retention_time_in_days = 1
comment = 'K4/DBT-101: dataset catalog mirror of data/contracts/datasets.yaml';

create table if not exists bridge.ops_meta.dataset_partition_rule (
    downstream_dataset_id   varchar(64)   not null,
    upstream_kind           varchar(16)   not null comment 'DATASET | SOURCE | CONFIG',
    upstream_ref            varchar(64)   not null comment 'dataset_id, ING-001 source_id or config_kind',
    rule                    varchar(40)   not null comment 'identity | hour_to_day | day_to_month | account_to_org | org_to_accounts | tenant_all_open | scope_all_open | window_hours | window_hours_to_day | window_days | org_day_fanout | snapshot_scope_all | config_version_tenant_open',
    overlap_hours           number(38,0)  not null default 0,
    registry_version        number(38,0)  not null,
    active                  boolean       not null default true,
    synced_at               timestamp_ntz(9) not null,
    constraint pk_dataset_partition_rule primary key (downstream_dataset_id, upstream_kind, upstream_ref)
)
data_retention_time_in_days = 1
comment = 'K4/ORC-101-S02: upstream partition mapping rules (DATASET_PARTITION_RULE); planner topological closure';

create table if not exists bridge.ops_meta.check_registry (
    check_id                varchar(96)   not null comment 'data/contracts/checks.yaml check_id',
    check_version           number(38,0)  not null,
    dataset_id              varchar(64)   not null comment 'dataset whose candidate revision the check evaluates',
    severity                varchar(16)   not null comment 'REQUIRED | ADVISORY',
    scope                   varchar(16)   not null comment 'TENANT (one PASS/FAIL row per tenant in workset) | STRUCTURAL (build-wide)',
    family                  varchar(32)   not null,
    applies_to_build_kinds  array         not null comment 'subset of STEADY, REPAIR, SHADOW, BISECT, SIMULATION, PYTHON, RETENTION, REPUBLISH',
    active                  boolean       not null default true,
    registry_version        number(38,0)  not null,
    synced_at               timestamp_ntz(9) not null,
    constraint pk_check_registry primary key (check_id, check_version, dataset_id)
)
data_retention_time_in_days = 1
comment = 'K4/DBT-005-S01: required/advisory check catalog mirror of data/contracts/checks.yaml read by the publication gate';

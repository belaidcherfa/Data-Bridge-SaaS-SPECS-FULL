-- contract=snowflake-publication-core version=1 status=DRAFT owner_task=DBT-101 decisions=D-05,D-06 last_changed=2026-09-28
-- Lane K4 (ORC/DBT), block V0300-V0399. Schema BRIDGE.PUBLICATION.
-- ADR-014 decision 6 (DBT-101-S03, ORC-005-S01): builds, lane fences, tenant pointers, publications, the SCD2
-- publication map, dataset versions, candidate changes, per-tenant gate results, quarantine and GC policy.
--
-- Invariants (tested by ORC-005 property tests):
--   * only the owner's-rights procedures PREPARE_CANDIDATES / PUBLISH_BATCH / REPUBLISH_PRIOR / ACQUIRE_LANE_FENCE
--     / PIN_* mutate TENANT_POINTER, PUBLICATION, PUBLICATION_TENANT, PUBLICATION_MAP, DATASET_VERSION, LANE_FENCE, PIN;
--     every mutation is DML inside one explicit transaction (DDL auto-commits and never takes part);
--   * pub_seq is global, allocated by the single publisher from PostgreSQL (platform.publication_seq) and strictly
--     increasing; TENANT_POINTER.pub_seq never decreases (rollback = forward REPUBLISH_PRIOR);
--   * for every (tenant, dataset, scope, partition) at most one PUBLICATION_MAP row is open
--     (valid_to_seq = 9223372036854775807); readers pin with valid_from_seq <= :pin AND :pin < valid_to_seq;
--   * readers (tenant serving users/roles) hold NO grant on this schema; serving views read it with owner rights.
-- Idempotent: IF NOT EXISTS / seed INSERT ... WHERE NOT EXISTS.

create table if not exists bridge.publication.build (
    build_id                varchar(36)   not null comment 'UUIDv7 allocated by the planner (PYTHON builds: = algorithm_run_id)',
    lane                    varchar(16)   not null comment 'STEADY | REPAIR | SIMULATION | INTELLIGENCE (one LANE_FENCE row each)',
    kind                    varchar(16)   not null comment 'STEADY | REPAIR | SHADOW | BISECT | RESTATEMENT | RETENTION | REPUBLISH | SIMULATION | PYTHON',
    status                  varchar(16)   not null comment 'contracts/state-machines/build.yaml: PLANNED | RUNNING | BUILT | VALIDATED | PUBLISHED | NO_CHANGE | REJECTED | SIMULATED | FAILED | CANCELLED | ABANDONED | FENCED',
    fence_token             number(38,0)  not null comment 'PostgreSQL lane-lease fencing token; must equal LANE_FENCE.fence_token to publish',
    snapshot_seq            number(38,0)  not null comment 'max(CONTROL.ACCEPTED_BATCHES.accepted_seq) at plan time; staging reads accepted_seq <= snapshot_seq',
    read_pub_seq            number(38,0)  not null comment 'max(PUBLICATION.pub_seq) at plan time; upstream partitions outside the workset are read as published at this pub_seq',
    input_pub_seq           number(38,0)           comment 'PYTHON builds: financial publication P the engines read (two-phase publication)',
    parent_build_id         varchar(36)            comment 'BISECT/RETRY: build whose workset was split',
    recovery_plan_id        varchar(36)            comment 'REPAIR/RESTATEMENT: data/contracts/recovery_plan.json plan_id',
    simulation_id           varchar(36)            comment 'SIMULATION: ALC-003 simulation id (outputs never mapped)',
    approval_ref            varchar(128)           comment 'SHADOW: sha256 of the approved diff report (DBT-004-S08); NULL = not approved',
    republish_target_pub_seq number(38,0)          comment 'REPUBLISH: prior publication whose revisions are re-pointed (RB-07)',
    requested_by            varchar(128)           comment 'REPUBLISH/REPAIR/RESTATEMENT: operator subject id or system:<component>',
    request_reason          varchar(1024)          comment 'INTERNAL free text (no customer data, no SQL text)',
    dagster_run_id          varchar(64),
    code_version            varchar(64)   not null comment 'git SHA of the dbt/engine image',
    dbt_manifest_sha256     varchar(64)            comment 'Image label bridge.dbt_manifest_sha256 (ORC-004-S01)',
    image_digest            varchar(128),
    datasets_registry_version number(38,0) not null comment 'data/contracts/datasets.yaml registry_version',
    serving_schema_version  number(38,0)  not null comment 'REL-103 serving namespace version the build targets',
    tenant_count            number(38,0)  not null default 0,
    partition_count         number(38,0)  not null default 0,
    pub_seq                 number(38,0)           comment 'Publication that published this build (status PUBLISHED)',
    error_class             varchar(24)            comment 'services/orchestrator/admission/error_classes.yaml class',
    error_code              varchar(64)            comment 'ORC_*/DBT_* problem code',
    planned_at              timestamp_ntz(9) not null,
    started_at              timestamp_ntz(9),
    built_at                timestamp_ntz(9),
    validated_at            timestamp_ntz(9),
    ended_at                timestamp_ntz(9),
    status_changed_at       timestamp_ntz(9) not null,
    constraint pk_build primary key (build_id)
)
data_retention_time_in_days = 1
comment = 'K4/ORC-101, ORC-005: one row per build (dbt build, Python run, retention or republish publication source)';

create table if not exists bridge.publication.lane_fence (
    lane                    varchar(16)   not null,
    fence_token             number(38,0)  not null comment 'Monotonic; written only by ACQUIRE_LANE_FENCE with a larger token',
    build_id                varchar(36)            comment 'Build that holds the lane',
    acquired_at             timestamp_ntz(9),
    last_publish_attempt_seq number(38,0)          comment 'Last pub_seq PUBLISH_BATCH attempted under this fence (row lock target)',
    updated_at              timestamp_ntz(9) not null,
    constraint pk_lane_fence primary key (lane)
)
data_retention_time_in_days = 1
comment = 'K4/ORC-005: lane fences mirroring the PostgreSQL lane lease tokens (G-ORC-10)';

insert into bridge.publication.lane_fence (lane, fence_token, build_id, acquired_at, last_publish_attempt_seq, updated_at)
select v.lane, 0, null, null, null, sysdate()
from (select column1 as lane from values ('STEADY'), ('REPAIR'), ('SIMULATION'), ('INTELLIGENCE')) v
where not exists (select 1 from bridge.publication.lane_fence f where f.lane = v.lane);

create table if not exists bridge.publication.tenant_pointer (
    tenant_id               varchar(36)   not null,
    pub_seq                 number(38,0)  not null comment 'Current publication of the tenant; 0 = never published. Never decreases.',
    publication_id          varchar(36)            comment 'PUBLICATION.publication_id of pub_seq',
    previous_pub_seq        number(38,0),
    serving_schema_version  number(38,0)           comment 'Serving namespace of the tenant publication (REL-103)',
    last_build_id           varchar(36),
    advance_count           number(38,0)  not null default 0,
    advanced_at             timestamp_ntz(9),
    constraint pk_tenant_pointer primary key (tenant_id)
)
data_retention_time_in_days = 1
comment = 'K4/ORC-005: per-tenant publication pointer advanced only by PUBLISH_BATCH compare-and-swap';

create table if not exists bridge.publication.publication (
    pub_seq                 number(38,0)  not null comment 'Global monotonic sequence (PostgreSQL platform.publication_seq)',
    publication_id          varchar(36)   not null comment 'UUID_STRING(NS_PUBLICATION, pub_seq) — namespace publication in contracts/common/namespaces.yaml',
    build_id                varchar(36)   not null,
    lane                    varchar(16)   not null,
    kind                    varchar(16)   not null comment 'BUILD.kind of the source build',
    publication_phase       varchar(16)   not null comment 'CORE | INTELLIGENCE',
    input_pub_seq           number(38,0)           comment 'INTELLIGENCE publications: financial publication read by the engines',
    reason                  varchar(24)   not null comment 'BUILD | REPUBLISH_PRIOR | RETENTION | SHADOW_CUTOVER | RESTATEMENT | PYTHON_OUTPUTS',
    status                  varchar(16)   not null comment 'contracts/state-machines/publication.yaml: PUBLISHED | ACKNOWLEDGED | RETIRED',
    tenants_published       number(38,0)  not null,
    datasets_changed        number(38,0)  not null,
    map_rows_inserted       number(38,0)  not null,
    map_rows_closed         number(38,0)  not null,
    snapshot_seq            number(38,0)  not null,
    serving_schema_version  number(38,0)  not null,
    code_version            varchar(64)   not null,
    actor                   varchar(128)           comment 'REPUBLISH_PRIOR: operator subject id (audited in PostgreSQL)',
    actor_reason            varchar(1024)          comment 'REPUBLISH_PRIOR: free-text reason (INTERNAL, no customer data)',
    published_at            timestamp_ntz(9) not null,
    acknowledged_at         timestamp_ntz(9)       comment 'PostgreSQL ack committed (platform.dataset_publication_refs + outbox)',
    retired_at              timestamp_ntz(9)       comment 'No tenant can resolve this pub_seq any more (GC)',
    constraint pk_publication primary key (pub_seq)
)
data_retention_time_in_days = 1
comment = 'K4/ORC-005: one row per committed publication';

create table if not exists bridge.publication.publication_tenant (
    pub_seq                 number(38,0)  not null,
    tenant_id               varchar(36)   not null,
    previous_pub_seq        number(38,0)  not null comment '0 when first publication of the tenant',
    changed_datasets        array         not null comment '[{"dataset_id": str, "dataset_version": pub_seq}] of datasets whose map changed',
    partitions_changed      number(38,0)  not null,
    accepted_seq_min        number(38,0)           comment 'Accepted batches reflected for the first time (NULL for non-batch publications)',
    accepted_seq_max        number(38,0),
    snapshot_seq            number(38,0)  not null,
    source_as_of            variant                comment '[{"source_id", "scope_id", "complete_through"}] (data/contracts/publication.json#/$defs/source_as_of)',
    coverage                variant                comment 'data/contracts/publication.json#/$defs/coverage',
    config_versions         object                 comment '{config_kind: version} pinned for the tenant by the source build (DBT-103-S07)',
    constraint pk_publication_tenant primary key (pub_seq, tenant_id)
)
cluster by (tenant_id)
data_retention_time_in_days = 1
comment = 'K4/ORC-005: per-tenant content of a publication = acknowledgement payload source';

create table if not exists bridge.publication.publication_map (
    tenant_id               varchar(36)   not null,
    dataset_id              varchar(64)   not null,
    scope_id                varchar(36)   not null,
    partition_start         timestamp_ntz(9) not null,
    revision_id             number(38,0)  not null,
    valid_from_seq          number(38,0)  not null comment 'pub_seq at which this revision became current',
    valid_to_seq            number(38,0)  not null comment 'pub_seq at which it stopped being current; 9223372036854775807 = open',
    published_by_build_id   varchar(36)   not null,
    closed_by_build_id      varchar(36),
    published_at            timestamp_ntz(9) not null,
    closed_at               timestamp_ntz(9),
    constraint pk_publication_map primary key (tenant_id, dataset_id, scope_id, partition_start, valid_from_seq)
)
cluster by (tenant_id, dataset_id)
data_retention_time_in_days = 1
comment = 'K4/ORC-005: SCD2 publication map (ADR-014 decision 6); ~4.4M rows for a 365-day hour-grain dataset at 500 accounts';

create table if not exists bridge.publication.dataset_version (
    tenant_id               varchar(36)   not null,
    dataset_id              varchar(64)   not null,
    dataset_version         number(38,0)  not null comment 'pub_seq at which the tenant map of this dataset last changed (cache key component, CTL-006)',
    previous_dataset_version number(38,0),
    changed_at              timestamp_ntz(9) not null,
    constraint pk_dataset_version primary key (tenant_id, dataset_id)
)
data_retention_time_in_days = 1
comment = 'K4/ORC-005: dataset_version per tenant; bumped only for datasets that changed';

create table if not exists bridge.publication.candidate_change (
    build_id                varchar(36)   not null,
    tenant_id               varchar(36)   not null,
    dataset_id              varchar(64)   not null,
    scope_id                varchar(36)   not null,
    partition_start         timestamp_ntz(9) not null,
    change_kind             varchar(8)    not null comment 'UPSERT (new or different revision) | REMOVE (close the open map row, no new row)',
    new_revision_id         number(38,0)           comment 'NULL for REMOVE',
    prior_revision_id       number(38,0)           comment 'Open map revision at evaluation time; NULL for a never-published partition',
    base_pub_seq            number(38,0)  not null comment 'TENANT_POINTER.pub_seq at evaluation (compare-and-swap expected value)',
    new_checksum            number(38,0),
    prior_checksum          number(38,0),
    new_row_count           number(38,0),
    prior_row_count         number(38,0),
    new_snapshot_seq        number(38,0),
    prior_snapshot_seq      number(38,0),
    computed_at             timestamp_ntz(9) not null,
    constraint pk_candidate_change primary key (build_id, tenant_id, dataset_id, scope_id, partition_start)
)
cluster by (build_id)
data_retention_time_in_days = 1
comment = 'K4/ORC-005-S02: partitions whose candidate differs from the published revision (equal checksum and row count => no row)';

create table if not exists bridge.publication.build_tenant_gate (
    build_id                varchar(36)   not null,
    tenant_id               varchar(36)   not null,
    gate_status             varchar(16)   not null comment 'ELIGIBLE | REJECTED',
    primary_reason          varchar(40)   not null comment 'ELIGIBLE | NO_CHANGE | QUARANTINED | STRUCTURAL_CHECK_FAILED | PARTITION_UNREGISTERED | CHECK_MISSING | CHECK_FAILED | STALE_SNAPSHOT | CODE_VERSION_MIXED | SHADOW_NOT_APPROVED | SERVING_SCHEMA_UNSUPPORTED',
    reasons                 array         not null comment 'All failing gate rules (primary first)',
    base_pub_seq            number(38,0)  not null,
    change_count            number(38,0)  not null,
    partitions_in_workset   number(38,0)  not null,
    checks_required         number(38,0)  not null,
    checks_passed           number(38,0)  not null,
    accepted_seq_min        number(38,0),
    accepted_seq_max        number(38,0),
    source_as_of            variant,
    coverage                variant,
    publish_seq             number(38,0)           comment 'Set by PUBLISH_BATCH for the tenants it published (freezes the eligible set inside the transaction)',
    evaluated_at            timestamp_ntz(9) not null,
    constraint pk_build_tenant_gate primary key (build_id, tenant_id)
)
cluster by (build_id)
data_retention_time_in_days = 1
comment = 'K4/ORC-005-S03: per-tenant publication gate (the only eligibility evaluator, RECONCILIATION U-19/C-23)';

create table if not exists bridge.publication.tenant_quarantine (
    quarantine_id           varchar(36)   not null,
    tenant_id               varchar(36)   not null,
    lane                    varchar(16)   not null comment 'STEADY | ALL',
    status                  varchar(16)   not null comment 'ACTIVE | RELEASED',
    reason                  varchar(32)   not null comment 'GATED_3_CONSECUTIVE | BISECT_POISON | OPERATOR',
    build_id                varchar(36)            comment 'Build that triggered the quarantine',
    detail                  varchar(1024)          comment 'INTERNAL diagnostic (no customer data, no SQL text)',
    created_at              timestamp_ntz(9) not null,
    created_by              varchar(128)  not null comment 'system:<component> or operator subject id',
    released_at             timestamp_ntz(9),
    released_by             varchar(128),
    release_reason          varchar(1024),
    constraint pk_tenant_quarantine primary key (quarantine_id)
)
data_retention_time_in_days = 1
comment = 'K4/ORC-004-S06, ORC-101-S07: tenants excluded from the steady lane (RB-07)';

create table if not exists bridge.publication.serving_schema_support (
    serving_schema_version  number(38,0)  not null,
    fleet_supported         boolean       not null comment 'Every deployed API/broker digest supports this namespace (REL-103-S05)',
    release_id              varchar(128),
    updated_at              timestamp_ntz(9) not null,
    constraint pk_serving_schema_support primary key (serving_schema_version)
)
data_retention_time_in_days = 1
comment = 'K4 table maintained by the REL-103 release pipeline; read by the gate (SERVING_SCHEMA_UNSUPPORTED)';

insert into bridge.publication.serving_schema_support (serving_schema_version, fleet_supported, release_id, updated_at)
select 1, true, 'bootstrap', sysdate()
where not exists (select 1 from bridge.publication.serving_schema_support where serving_schema_version = 1);

create table if not exists bridge.publication.gc_policy (
    policy_key              varchar(64)   not null,
    value_number            number(38,0)  not null,
    source                  varchar(256)  not null,
    updated_at              timestamp_ntz(9) not null,
    constraint pk_gc_policy primary key (policy_key)
)
data_retention_time_in_days = 1
comment = 'K4/ORC-105-S03: GC parameters; cursor_ttl_seconds mirrors API-003 config key cursor_ttl_seconds (RECONCILIATION C-07)';

insert into bridge.publication.gc_policy (policy_key, value_number, source, updated_at)
select v.k, v.n, v.s, sysdate()
from (select column1 as k, column2 as n, column3 as s from values
        ('cursor_ttl_seconds', 3600, 'API-003 config key cursor_ttl_seconds (C-07: 1 h)'),
        ('cursor_grace_seconds', 900, 'ORC-105-S03: cursor TTL + 15 min'),
        ('rollback_window_days', 7, 'ORC-105 / RB-07 rollback window'),
        ('orphan_retention_hours', 24, 'ORC-105-S03: CANDIDATE revisions of terminal builds'),
        ('max_rows_per_delete_statement', 10000000, 'ORC-105-S04'),
        ('gc_paused', 0, 'ORC-105-S10 pause switch (1 = paused)')) v
where not exists (select 1 from bridge.publication.gc_policy p where p.policy_key = v.k);

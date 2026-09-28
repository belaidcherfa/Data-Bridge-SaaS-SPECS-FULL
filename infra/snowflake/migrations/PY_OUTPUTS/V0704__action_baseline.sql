-- contract=snowflake-py-outputs-action-baseline version=1 status=DRAFT owner_task=INS-006 decisions=D-05,D-11,D-13 last_changed=2026-09-28
-- Migration V0704 (lane K8) · schema PY_OUTPUTS · immutable frozen baselines (INS-006-S06/S07) and their daily series.
-- Measurement contract: data/contracts/savings-measurement.json (normalizers, windows, rate basis, frozen fields).
-- Each freeze is its own revision partition: scope_id = baseline_id, partition_start = frozen_at day. A baseline is
-- never superseded in the ADR-014 sense (no later revision of the same partition is ever written), so the GC never
-- deletes it while its retention lasts; a re-freeze while PLANNED writes a NEW baseline_id (old one retained).
-- PostgreSQL keeps only baseline_id + baseline_hash (workflow.action / workflow.baseline_freeze).
-- baseline_hash = sha256 over the canonical JSON (RFC 8785) of the frozen record without technical columns; two
-- freezes of identical inputs give the same hash (INS-006-S06 oracle). Restatements never mutate a baseline; they only
-- emit a baseline_restatement_notice (INS-006-S07).

create transient table if not exists py_outputs.action_baseline_landing (
    run_id                        varchar(36)   not null,
    tenant_id                     varchar(36)   not null,
    organization_id               varchar(36),
    account_id                    varchar(36)   not null,
    baseline_id                   varchar(36)   not null,
    action_id                     varchar(36)   not null,
    payload                       variant       not null comment 'full frozen record (see action_baseline_r columns)',
    daily                         variant       not null comment 'array of daily baseline points'
)
data_retention_time_in_days = 0
comment = 'K8 INS-006 · ORC-103 landing for frozen baselines';

create table if not exists py_outputs.action_baseline_r (
    tenant_id                     varchar(36)   not null,
    scope_id                      varchar(64)   not null comment 'baseline_id (one partition per frozen baseline)',
    partition_start               timestamp_ntz(9) not null comment 'frozen_at day 00:00 UTC',
    revision_id                   number(38,0)  not null,
    build_id                      varchar(36)   not null comment 'baseline job run id',
    baseline_id                   varchar(36)   not null,
    action_id                     varchar(36)   not null,
    freeze_id                     varchar(36)   not null comment 'workflow.baseline_freeze.id',
    organization_id               varchar(36),
    account_id                    varchar(36)   not null,
    measurement_contract_version  varchar(16)   not null,
    action_type                   varchar(48)   not null,
    normalizer                    varchar(32)   not null comment 'EXECUTIONS|MIX_ADJUSTED_EXECUTIONS|ACTIVE_GIB_DAYS|GIB_INGESTED|CALENDAR_DAYS|HOURS|REQUESTS',
    scope_pool_key                varchar(512)  not null comment 'cost-pool key of the measured scope',
    population                    variant       not null comment 'resources in scope (warehouse ids, family keys, table ids)',
    window_kind                   varchar(16)   not null comment 'DEFAULT|CUSTOM (custom only while PLANNED)',
    baseline_window_start         date          not null comment 'half-open [start, end)',
    baseline_window_end           date          not null,
    baseline_days                 number(4,0)   not null,
    short_baseline_label          boolean       not null comment 'true when baseline_days < savings.baseline_days (min 14)',
    stabilization_days            number(4,0)   not null,
    rate_basis_amount             number(38,12) comment 'frozen effective rate per native unit (credit, TB-month …)',
    rate_basis_unit               varchar(16)   not null,
    currency                      varchar(3)    not null,
    native_units_total            number(38,12) not null comment 'e.g. credits over the baseline window',
    cost_total                    number(38,12) comment 'native units x frozen rate; null when no rate (NO_PRICE)',
    normalizer_units_total        number(38,12) not null,
    unit_cost                     number(38,12) comment 'cost_total / normalizer_units_total; null on zero denominator',
    mix_weights                   variant       comment 'MIX_ADJUSTED_EXECUTIONS: object family_key -> a_base (baseline attributed credits per execution) and n_base',
    covariates                    variant       comment 'approved covariates (e.g. rows_changed for CALENDAR_DAYS)',
    exclusion_policy              variant       not null comment 'excluded days/resources with reasons',
    input_pub_seq                 number(38,0)  not null,
    input_publication_ids         variant       not null,
    frozen_at                     timestamp_ntz(9) not null,
    frozen_by_membership_id       varchar(36)   comment 'actor membership id (ID only; no personal data)',
    profile_hash                  varchar(64)   not null comment 'D-02 permission profile the job ran under',
    baseline_hash                 varchar(64)   not null comment 'sha256 of canonical JSON of the frozen record',
    constraint pk_action_baseline_r primary key (tenant_id, scope_id, partition_start, revision_id, baseline_id)
)
cluster by (tenant_id, partition_start)
data_retention_time_in_days = 1
change_tracking = false
comment = 'K8 INS-006 · immutable action baselines; insert-only; one partition per baseline';

create table if not exists py_outputs.action_baseline_day_r (
    tenant_id                     varchar(36)   not null,
    scope_id                      varchar(64)   not null comment 'baseline_id',
    partition_start               timestamp_ntz(9) not null,
    revision_id                   number(38,0)  not null,
    build_id                      varchar(36)   not null,
    baseline_id                   varchar(36)   not null,
    organization_id               varchar(36),
    account_id                    varchar(36)   not null,
    usage_date                    date          not null,
    native_units                  number(38,12) not null,
    cost                          number(38,12),
    normalizer_units              number(38,12) not null,
    unit_cost                     number(38,12) comment 'daily unit cost used by the moving-block bootstrap',
    data_status                   varchar(16)   not null,
    excluded                      boolean       not null,
    exclusion_reason              varchar(64),
    constraint pk_action_baseline_day_r primary key (tenant_id, scope_id, partition_start, revision_id, usage_date)
)
cluster by (tenant_id, partition_start)
data_retention_time_in_days = 1
change_tracking = false
comment = 'K8 INS-006/INS-007 · daily baseline series (bootstrap input); insert-only';

alter table py_outputs.action_baseline_r suspend recluster;
alter table py_outputs.action_baseline_day_r suspend recluster;

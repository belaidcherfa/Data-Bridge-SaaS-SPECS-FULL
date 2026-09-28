-- contract=snowflake-py-outputs-savings-measurement version=1 status=DRAFT owner_task=INS-007 decisions=D-05,D-11,D-12,D-13 last_changed=2026-09-28
-- Migration V0705 (lane K8) · schema PY_OUTPUTS · savings observations (INS-007-S03…S10).
-- Measurement contract: data/contracts/savings-measurement.json. Each measurement revision is an immutable record in
-- its own partition (scope_id = measurement_id, partition_start = measured_at day). A restatement creates a NEW
-- measurement_id with measurement_revision + 1 and supersedes_measurement_id → old values stay auditable (INS-007-S09);
-- "latest" is resolved through workflow.savings_measurement.superseded_by (PostgreSQL) or max(measurement_revision)
-- per study. Amounts are signed (−20 is never clamped to 0) and live only here (PostgreSQL stores IDs/statuses).
-- Estimated potential (observations) and realized savings (this table) are never summed together.

create transient table if not exists py_outputs.savings_measurement_landing (
    run_id                        varchar(36)   not null,
    tenant_id                     varchar(36)   not null,
    organization_id               varchar(36),
    account_id                    varchar(36)   not null,
    measurement_id                varchar(36)   not null,
    study_id                      varchar(36)   not null,
    payload                       variant       not null comment 'full measurement record (see savings_measurement_r)',
    daily                         variant       not null comment 'array of post-window daily points'
)
data_retention_time_in_days = 0
comment = 'K8 INS-007 · ORC-103 landing for savings measurements';

create table if not exists py_outputs.savings_measurement_r (
    tenant_id                     varchar(36)   not null,
    scope_id                      varchar(64)   not null comment 'measurement_id (one partition per measurement revision)',
    partition_start               timestamp_ntz(9) not null comment 'measured_at day 00:00 UTC',
    revision_id                   number(38,0)  not null,
    build_id                      varchar(36)   not null,
    measurement_id                varchar(36)   not null,
    study_id                      varchar(36)   not null comment 'workflow.savings_study.id (overlap group)',
    measurement_revision          number(10,0)  not null comment '1, 2, … per study',
    supersedes_measurement_id     varchar(36),
    organization_id               varchar(36),
    account_id                    varchar(36)   not null,
    overlap_group_key             varchar(512)  not null comment 'union scope pool key of the joint measurement',
    action_ids                    array         not null,
    baseline_ids                  array         not null,
    measurement_contract_version  varchar(16)   not null,
    normalizer                    varchar(32)   not null,
    currency                      varchar(3)    not null,
    rate_basis_amount             number(38,12) comment 'frozen baseline effective rate (rate-neutral primary figure)',
    rate_basis_unit               varchar(16)   not null,
    baseline_window_start         date          not null,
    baseline_window_end           date          not null,
    stabilization_days            number(4,0)   not null,
    post_window_start             date          not null,
    post_window_end               date          not null comment 'half-open; truncated at reverted_at on ROLLBACK',
    post_days_expected            number(4,0)   not null,
    post_days_final               number(4,0)   not null comment 'days whose every required source is FINAL (D-13)',
    coverage_complete             boolean       not null,
    normalizer_units_base         number(38,12) not null,
    normalizer_units_post         number(38,12) not null,
    unit_cost_base                number(38,12),
    expected_cost_post            number(38,12) comment 'counterfactual = unit_cost_base x units_post (mix-adjusted for warehouse actions)',
    observed_cost_post            number(38,12),
    realized_saving               number(38,12) comment 'expected − observed, signed, rate-neutral (frozen rate)',
    expected_native_units_post    number(38,12),
    observed_native_units_post    number(38,12),
    realized_saving_native_units  number(38,12) comment 'signed, e.g. credits',
    realized_saving_at_actual_rate number(38,12) comment 'secondary figure priced at actual post rates (RATE_CHANGE confounder)',
    bootstrap_lower               number(38,12) comment '5th percentile of realized saving (moving-block bootstrap)',
    bootstrap_upper               number(38,12) comment '95th percentile',
    bootstrap_b                   number(10,0)  not null,
    bootstrap_block_days          number(4,0)   not null,
    bootstrap_seed_hex            varchar(16)   not null comment 'first 8 bytes of sha256(measurement_id)',
    outcome_class                 varchar(32)   not null comment 'VERIFIED_SAVING|VERIFIED_INCREASE|INCONCLUSIVE|INCONCLUSIVE_COVERAGE',
    confidence_label              varchar(16)   not null comment 'UNCALIBRATED',
    confounder_codes              array         not null comment 'RATE_CHANGE|SIZE_CHANGE|OVERLAPPING_ACTION|VOLUME_SHIFT|MIX_SHIFT|ROLLBACK',
    input_pub_seq                 number(38,0)  not null,
    input_publication_ids         variant       not null,
    measured_at                   timestamp_ntz(9) not null,
    constraint pk_savings_measurement_r primary key (tenant_id, scope_id, partition_start, revision_id, measurement_id)
)
cluster by (tenant_id, partition_start)
data_retention_time_in_days = 1
change_tracking = false
comment = 'K8 INS-007 · savings measurements (signed realized savings); insert-only; one partition per measurement revision';

create table if not exists py_outputs.savings_measurement_day_r (
    tenant_id                     varchar(36)   not null,
    scope_id                      varchar(64)   not null comment 'measurement_id',
    partition_start               timestamp_ntz(9) not null,
    revision_id                   number(38,0)  not null,
    build_id                      varchar(36)   not null,
    measurement_id                varchar(36)   not null,
    organization_id               varchar(36),
    account_id                    varchar(36)   not null,
    usage_date                    date          not null,
    window_role                   varchar(16)   not null comment 'BASELINE|STABILIZATION|POST|EXCLUDED',
    normalizer_units              number(38,12),
    observed_cost                 number(38,12),
    expected_cost                 number(38,12),
    realized_saving               number(38,12) comment 'signed; YTD = Σ over POST days in the UTC calendar year (INS-007-S10)',
    data_status                   varchar(16)   not null,
    is_final                      boolean       not null,
    constraint pk_savings_measurement_day_r primary key (tenant_id, scope_id, partition_start, revision_id, usage_date)
)
cluster by (tenant_id, partition_start)
data_retention_time_in_days = 1
change_tracking = false
comment = 'K8 INS-007 · daily savings series; insert-only';

alter table py_outputs.savings_measurement_r suspend recluster;
alter table py_outputs.savings_measurement_day_r suspend recluster;

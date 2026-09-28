-- contract=snowflake-py-outputs-insight-detector-evaluation version=1 status=DRAFT owner_task=INS-001 decisions=D-05,D-13,D-20 last_changed=2026-09-28
-- Migration V0702 (lane K8) · schema PY_OUTPUTS · per (tenant, account, detector, version, as_of) evaluation summary:
-- evaluated / qualified / suppressed_by_reason / eligible_on (INS-001-S03, INS-004-S06, INS-101-S05).
-- Record contract: data/contracts/detector_evaluation.schema.json. Partition = (tenant_id, detector family, as_of day).
-- A FAILED family run writes no partition: the previous accepted revision stays published (INS-001-S07).

create transient table if not exists py_outputs.insight_detector_evaluation_landing (
    run_id                  varchar(36)   not null,
    tenant_id               varchar(36)   not null,
    organization_id         varchar(36),
    account_id              varchar(36)   not null,
    detector_id             varchar(8)    not null,
    detector_version        varchar(32)   not null,
    detector_family         varchar(16)   not null,
    as_of                   date          not null,
    window_start            timestamp_ntz(9) not null,
    window_end              timestamp_ntz(9) not null,
    run_status              varchar(40)   not null,
    evaluated_count         number(38,0)  not null,
    qualified_count         number(38,0)  not null,
    not_qualified_count     number(38,0)  not null,
    insufficient_count      number(38,0)  not null,
    suppressed_count        number(38,0)  not null,
    suppressed_by_reason    variant       not null,
    not_qualified_by_reason variant       not null,
    eligible_on             date,
    input_pub_seq           number(38,0)  not null,
    config_version          number(38,0)  not null,
    failure_code            varchar(40)
)
data_retention_time_in_days = 0
comment = 'K8 INS-001 · ORC-103 landing for detector evaluation summaries';

create table if not exists py_outputs.insight_detector_evaluation_r (
    tenant_id               varchar(36)   not null,
    scope_id                varchar(64)   not null comment 'detector family',
    partition_start         timestamp_ntz(9) not null comment 'as_of day 00:00 UTC',
    revision_id             number(38,0)  not null,
    build_id                varchar(36)   not null,
    organization_id         varchar(36),
    account_id              varchar(36)   not null,
    detector_id             varchar(8)    not null,
    detector_version        varchar(32)   not null,
    as_of                   date          not null,
    window_start            timestamp_ntz(9) not null,
    window_end              timestamp_ntz(9) not null,
    run_status              varchar(40)   not null comment 'COMPLETED|FAILED|SKIPPED_DISABLED|SKIPPED_NOT_QUALIFIED_FOR_TENANT',
    evaluated_count         number(38,0)  not null,
    qualified_count         number(38,0)  not null,
    not_qualified_count     number(38,0)  not null,
    insufficient_count      number(38,0)  not null,
    suppressed_count        number(38,0)  not null,
    suppressed_by_reason    variant       not null comment 'object reason_code -> count',
    not_qualified_by_reason variant       not null comment 'object reason_code -> count',
    eligible_on             date          comment 'e.g. TSM first_snapshot_date + 13 d',
    input_pub_seq           number(38,0)  not null,
    config_version          number(38,0)  not null,
    failure_code            varchar(40),
    constraint pk_insight_detector_evaluation_r primary key (tenant_id, scope_id, partition_start, revision_id, account_id, detector_id)
)
cluster by (tenant_id, partition_start)
data_retention_time_in_days = 1
change_tracking = false
comment = 'K8 INS-001 · detector evaluation summaries; ADR-014 insert-only revision table';

alter table py_outputs.insight_detector_evaluation_r suspend recluster;

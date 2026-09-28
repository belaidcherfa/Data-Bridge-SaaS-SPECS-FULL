-- contract=snowflake-py-outputs-insight-evidence version=1 status=DRAFT owner_task=INS-001 decisions=D-05,D-06,D-10,D-11 last_changed=2026-09-28
-- Migration V0701 (lane K8) · schema PY_OUTPUTS · bounded evidence rows (≤ 200 per observation, INS-001-S09).
-- Record contract: data/contracts/insight_evidence.schema.json. Same write path and partitioning as V0700
-- (scope_id = detector family, partition_start = as_of day); published in the same Python publication P′ as its
-- observations. Privacy: payload is CUSTOMER_METADATA; query evidence holds query IDs and parameterized hashes only
-- (ADR-009: no SQL text); user identifiers are D-10 HMAC pseudonyms (u1_…), never plaintext.

create transient table if not exists py_outputs.insight_evidence_landing (
    run_id            varchar(36)   not null,
    tenant_id         varchar(36)   not null,
    organization_id   varchar(36),
    account_id        varchar(36)   not null,
    evidence_id       varchar(36)   not null,
    observation_id    varchar(36)   not null,
    detector_family   varchar(16)   not null,
    as_of             date          not null,
    ordinal           number(3,0)   not null,
    evidence_type     varchar(32)   not null,
    sort_cost         number(38,12),
    stable_key        varchar(256)  not null,
    payload           variant       not null
)
data_retention_time_in_days = 0
comment = 'K8 INS-001 · ORC-103 landing for insight evidence';

create table if not exists py_outputs.insight_evidence_r (
    tenant_id         varchar(36)   not null,
    scope_id          varchar(64)   not null comment 'detector family',
    partition_start   timestamp_ntz(9) not null comment 'as_of day 00:00 UTC',
    revision_id       number(38,0)  not null,
    build_id          varchar(36)   not null,
    evidence_id       varchar(36)   not null,
    observation_id    varchar(36)   not null,
    organization_id   varchar(36),
    account_id        varchar(36)   not null,
    as_of             date          not null,
    ordinal           number(3,0)   not null comment '1..200, ordered by sort_cost desc then stable_key',
    evidence_type     varchar(32)   not null comment 'IDLE_HOUR|GAP_SAMPLE|CONFIG_SNAPSHOT|CALIBRATION_DAY|COHORT_SUMMARY|SIZE_MIX|QUERY_SAMPLE|IDENTITY_TUPLE|CS_DAY|CS_CONTRIBUTOR|STORAGE_SNAPSHOT|GENERIC_SERIES_POINT',
    sort_cost         number(38,12),
    stable_key        varchar(256)  not null,
    payload           variant       not null comment 'CUSTOMER_METADATA; typed per evidence_type; decimals as strings; UTC timestamps',
    constraint pk_insight_evidence_r primary key (tenant_id, scope_id, partition_start, revision_id, evidence_id)
)
cluster by (tenant_id, partition_start)
data_retention_time_in_days = 1
change_tracking = false
comment = 'K8 INS-001 · insight evidence; ADR-014 insert-only revision table';

alter table py_outputs.insight_evidence_r suspend recluster;

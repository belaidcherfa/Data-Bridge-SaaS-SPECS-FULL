-- contract=snowflake-py-outputs-insight-opportunity-group version=1 status=DRAFT owner_task=INS-001 decisions=D-05,D-12 last_changed=2026-09-28
-- Migration V0703 (lane K8) · schema PY_OUTPUTS · cost-pool tree DP output per (tenant, account, currency) (INS-001-S10).
-- Record contract: data/contracts/insight_opportunity_group.schema.json. Partition = (tenant_id, scope_id = 'PORTFOLIO',
-- as_of day): computed after all detector families of the day are accepted, pinned to the same input_pub_seq.
-- Portfolio totals (INS-101 summary, Home) = Σ value_30d per currency over root groups; null never sums as 0.

create transient table if not exists py_outputs.insight_opportunity_group_landing (
    run_id                    varchar(36)   not null,
    tenant_id                 varchar(36)   not null,
    organization_id           varchar(36),
    account_id                varchar(36)   not null,
    as_of                     date          not null,
    group_key                 varchar(512)  not null,
    currency                  varchar(3)    not null,
    root_pool_kind            varchar(32)   not null,
    pool_cost_30d             number(38,12),
    ceiling_30d               number(38,12),
    value_30d                 number(38,12),
    member_observation_ids    array         not null,
    estimate_member_count     number(38,0)  not null,
    members_without_estimate  number(38,0)  not null,
    nodes                     variant       not null,
    input_pub_seq             number(38,0)  not null
)
data_retention_time_in_days = 0
comment = 'K8 INS-001 · ORC-103 landing for opportunity groups';

create table if not exists py_outputs.insight_opportunity_group_r (
    tenant_id                 varchar(36)   not null,
    scope_id                  varchar(64)   not null comment 'constant PORTFOLIO',
    partition_start           timestamp_ntz(9) not null comment 'as_of day 00:00 UTC',
    revision_id               number(38,0)  not null,
    build_id                  varchar(36)   not null,
    organization_id           varchar(36),
    account_id                varchar(36)   not null,
    as_of                     date          not null,
    group_key                 varchar(512)  not null comment 'root pool key',
    currency                  varchar(3)    not null comment 'one group per currency; never summed across currencies',
    root_pool_kind            varchar(32)   not null,
    pool_cost_30d             number(38,12),
    ceiling_30d               number(38,12) comment 'up-to amount (min CEILING member impact in the root)',
    value_30d                 number(38,12) comment 'deduplicated potential; null = no estimate in the group',
    member_observation_ids    array         not null,
    estimate_member_count     number(38,0)  not null,
    members_without_estimate  number(38,0)  not null,
    nodes                     variant       not null comment 'array of {pool_key, pool_kind, parent_key, pool_cost_30d, value_30d}',
    input_pub_seq             number(38,0)  not null,
    constraint pk_insight_opportunity_group_r primary key (tenant_id, scope_id, partition_start, revision_id, group_key)
)
cluster by (tenant_id, partition_start)
data_retention_time_in_days = 1
change_tracking = false
comment = 'K8 INS-001 · opportunity groups (cost-pool tree DP); ADR-014 insert-only revision table';

alter table py_outputs.insight_opportunity_group_r suspend recluster;

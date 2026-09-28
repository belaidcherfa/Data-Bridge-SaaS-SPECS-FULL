-- contract=snowflake-py-outputs-insight-observation version=1 status=DRAFT owner_task=INS-001 decisions=D-05,D-06,D-10,D-11,D-13 last_changed=2026-09-28
-- Migration V0700 (lane K8 block V0700–V0799) · schema PY_OUTPUTS · object class: Python-output landing + revision tables.
-- Record contract: data/contracts/insight_observation.schema.json (one row per observation).
-- Write path: ORC-103 writer only (Arrow → Parquet → PUT @stage → COPY INTO …_landing FILES=(…) → row-count/checksum
-- assertion → revisioned INSERT into …_r → PARTITION_REVISION registration) under the central engine identity
-- (role BRIDGE_ENGINE). Customer journal/Snowpipe are never used (RECONCILIATION U-18, C-17).
-- ADR-014: insert-only revisioned partitions; partition = (tenant_id, scope_id = detector family, partition_start =
-- as_of day 00:00 UTC); rows carry revision_id/build_id, never publication_id; readers select the published revision
-- through the SCD2 publication map (K4) behind secure serving views (K6). No UPDATE/DELETE grants (see V0706).
-- Times are UTC in TIMESTAMP_NTZ(9); money NUMBER(38,12); IDs VARCHAR(36) lowercase canonical UUIDs.
-- Privacy (CONVENTIONS §12): resource_native_id, resource_variant, resource_name_at_observation are CUSTOMER_METADATA;
-- no PERSONAL or SQL_TEXT column exists in this table.
-- Idempotent: CREATE … IF NOT EXISTS; applying twice is a no-op.

create transient table if not exists py_outputs.insight_observation_landing (
    run_id                        varchar(36)     not null comment 'ORC-103 run_id; the writer truncates its own run rows before COPY',
    tenant_id                     varchar(36)     not null,
    organization_id               varchar(36),
    account_id                    varchar(36)     not null,
    observation_id                varchar(36)     not null,
    fingerprint                   varchar(64)     not null,
    detector_id                   varchar(8)      not null,
    detector_version              varchar(32)     not null,
    detector_major                number(10,0)    not null,
    detector_family               varchar(16)     not null,
    as_of                         date            not null,
    window_start                  timestamp_ntz(9) not null,
    window_end                    timestamp_ntz(9) not null,
    current_window_start          timestamp_ntz(9) not null,
    current_window_end            timestamp_ntz(9) not null,
    baseline_window_start         timestamp_ntz(9),
    baseline_window_end           timestamp_ntz(9),
    input_pub_seq                 number(38,0)    not null,
    input_publication_ids         variant         not null,
    config_version                number(38,0)    not null,
    parameter_set_sha256          varchar(64)     not null,
    feature_snapshot_hash         varchar(64)     not null,
    eligibility_status            varchar(24)     not null,
    reason_code                   varchar(96),
    metrics                       variant         not null,
    impact_kind                   varchar(24)     not null,
    impact_amount_window          number(38,12),
    impact_amount_30d             number(38,12),
    currency                      varchar(3),
    potential_30d                 number(38,12),
    potential_reason              varchar(96),
    potential_method              varchar(32),
    cost_pool_key                 varchar(512),
    opportunity_group_key         varchar(512),
    sample_count                  number(38,0)    not null,
    confidence_method             varchar(32)     not null,
    severity                      varchar(8)      not null,
    severity_tier                 varchar(8),
    evidence_ids                  array           not null,
    evidence_truncated_count      number(38,0)    not null,
    resource_type                 varchar(32)     not null,
    resource_native_id            varchar(512)    not null,
    resource_variant              varchar(256),
    resource_name_at_observation  varchar(512),
    recommendation_template       varchar(64),
    data_status                   varchar(16)     not null,
    is_trial_account              boolean         not null,
    algorithm_version             varchar(32)     not null,
    seed                          number(38,0)
)
data_retention_time_in_days = 0
comment = 'K8 INS-001 · ORC-103 landing for insight observations; transient, truncated per run after registration';

create table if not exists py_outputs.insight_observation_r (
    tenant_id                     varchar(36)     not null comment 'revision partition key 1',
    scope_id                      varchar(64)     not null comment 'revision partition key 2: detector family (WAREHOUSE|QUERY|STORAGE|PIPELINE|INGESTION|AI|SPCS)',
    partition_start               timestamp_ntz(9) not null comment 'revision partition key 3: as_of day 00:00 UTC',
    revision_id                   number(38,0)    not null comment 'ADR-014 revision (PostgreSQL sequence)',
    build_id                      varchar(36)     not null comment 'ORC-103 run_id that produced the revision',
    observation_id                varchar(36)     not null comment 'UUIDv5(insight_observation namespace, fingerprint, window_end_date, detector_version, sha256(input_publication_ids))',
    organization_id               varchar(36)     comment 'RAP_ACCOUNT_SCOPED argument; null for standalone accounts',
    account_id                    varchar(36)     not null comment 'RAP_ACCOUNT_SCOPED argument',
    fingerprint                   varchar(64)     not null comment 'sha256 hex, G-INS-10; stable across renames, windows and minor versions',
    detector_id                   varchar(8)      not null,
    detector_version              varchar(32)     not null,
    detector_major                number(10,0)    not null,
    detector_family               varchar(16)     not null,
    as_of                         date            not null,
    window_start                  timestamp_ntz(9) not null,
    window_end                    timestamp_ntz(9) not null,
    current_window_start          timestamp_ntz(9) not null,
    current_window_end            timestamp_ntz(9) not null,
    baseline_window_start         timestamp_ntz(9),
    baseline_window_end           timestamp_ntz(9),
    input_pub_seq                 number(38,0)    not null comment 'financial publication P read by the run (two-phase publication)',
    input_publication_ids         variant         not null comment 'object dataset_id -> dataset_version',
    config_version                number(38,0)    not null comment 'CTL-005 INSIGHT_PARAMETERS version pinned',
    parameter_set_sha256          varchar(64)     not null,
    feature_snapshot_hash         varchar(64)     not null,
    eligibility_status            varchar(24)     not null comment 'QUALIFIED|NOT_QUALIFIED|SUPPRESSED|INSUFFICIENT_DATA',
    reason_code                   varchar(96)     comment 'urn:bridge:schema:insights:reason-code:v1; null iff QUALIFIED',
    metrics                       variant         not null comment 'array of {name, value (decimal string), unit, currency?}',
    impact_kind                   varchar(24)     not null comment 'ESTIMATE|CEILING|EXPOSURE|OBSERVED_EXCESS|NONE',
    impact_amount_window          number(38,12),
    impact_amount_30d             number(38,12)   comment 'window amount x 30 / window_days, HALF_EVEN at 12 dp',
    currency                      varchar(3),
    potential_30d                 number(38,12)   comment 'null unless a documented estimate exists (never 0 for unknown)',
    potential_reason              varchar(96),
    potential_method              varchar(32),
    cost_pool_key                 varchar(512),
    opportunity_group_key         varchar(512),
    sample_count                  number(38,0)    not null,
    confidence_method             varchar(32)     not null,
    severity                      varchar(8)      not null,
    severity_tier                 varchar(8),
    evidence_ids                  array           not null comment 'at most 200 ids',
    evidence_truncated_count      number(38,0)    not null,
    resource_type                 varchar(32)     not null,
    resource_native_id            varchar(512)    not null comment 'CUSTOMER_METADATA',
    resource_variant              varchar(256)    comment 'CUSTOMER_METADATA',
    resource_name_at_observation  varchar(512)    comment 'CUSTOMER_METADATA; display only, never in the fingerprint',
    recommendation_template       varchar(64),
    data_status                   varchar(16)     not null comment 'PROVISIONAL|FINAL|RECONCILED (least mature input)',
    is_trial_account              boolean         not null comment 'D-35 demonstration-only account',
    algorithm_version             varchar(32)     not null,
    seed                          number(38,0),
    constraint pk_insight_observation_r primary key (tenant_id, scope_id, partition_start, revision_id, observation_id)
)
cluster by (tenant_id, partition_start)
data_retention_time_in_days = 1
change_tracking = false
comment = 'K8 INS-001 · insight observations; ADR-014 insert-only revision table; dataset_id insight_observation (datasets.yaml, K4)';

alter table py_outputs.insight_observation_r suspend recluster;

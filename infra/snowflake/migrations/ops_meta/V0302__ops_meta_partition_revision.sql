-- contract=snowflake-partition-revision version=1 status=DRAFT owner_task=DBT-101 decisions=D-05,D-06,D-11,D-26 last_changed=2026-09-28
-- Lane K4 (ORC/DBT), block V0300-V0399. Schema BRIDGE.OPS_META.
-- PARTITION_REVISION (DBT-101-S03; ADR-014 decision 2): one row per (tenant, dataset, scope, partition, revision)
-- registered by the revisioned materialization (or the ORC-103 Python writer) for EVERY workset partition,
-- zero-row partitions included, so that a correction to empty removes the old rows at publication.
--
-- status lifecycle:
--   CANDIDATE  -> PUBLISHED   PUBLISH_BATCH inserted a PUBLICATION_MAP row for this revision
--   PUBLISHED  -> SUPERSEDED  a later publication closed that map row (new revision, REMOVE or REPUBLISH_PRIOR)
--   SUPERSEDED -> PUBLISHED   REPUBLISH_PRIOR re-pointed the tenant to this revision (forward publication)
--   CANDIDATE  -> PURGED      orphan of a terminal build, older than 24 h (ORC-105 GC)
--   SUPERSEDED -> PURGED      no pin covers it and the grace window max(cursor_ttl + 15 min, 7 d) elapsed (ORC-105 GC)
-- ORC-105's GC job is the only writer of PURGED and the only physical deleter of *_r rows.
--
-- checksum = HASH_AGG over the partition's business columns (all columns except revision_id and build_id),
-- 0 for zero-row partitions; identical content therefore yields identical checksums and no candidate change.
-- Writers: BRIDGE_TRANSFORMER / BRIDGE_ENGINE (insert CANDIDATE rows), BRIDGE_PUBLISHER through the owner's-rights
-- procedures (status transitions), BRIDGE_REVISION_GC (PURGED). Idempotent (IF NOT EXISTS).

create table if not exists bridge.ops_meta.partition_revision (
    tenant_id               varchar(36)   not null,
    dataset_id              varchar(64)   not null,
    scope_kind              varchar(32)   not null comment 'ACCOUNT | ORGANIZATION | TENANT',
    scope_id                varchar(36)   not null,
    partition_start         timestamp_ntz(9) not null,
    revision_id             number(38,0)  not null,
    build_id                varchar(36)   not null,
    row_count               number(38,0)  not null comment '0 for zero-row partitions (still registered)',
    checksum                number(38,0)  not null comment 'HASH_AGG of business columns; 0 when row_count = 0',
    snapshot_seq            number(38,0)  not null comment 'BUILD.snapshot_seq: accepted input bound of the producing build',
    code_version            varchar(64)   not null comment 'git SHA of the producing image (shadow homogeneity gate)',
    config_versions         object                 comment '{config_kind: config_version} pinned for this tenant (BUILD_CONFIG_PIN)',
    status                  varchar(16)   not null comment 'CANDIDATE | PUBLISHED | SUPERSEDED | PURGED',
    published_pub_seq       number(38,0)           comment 'pub_seq of the latest publication that made it current',
    superseded_pub_seq      number(38,0)           comment 'pub_seq of the latest publication that closed its map row',
    created_at              timestamp_ntz(9) not null,
    status_changed_at       timestamp_ntz(9) not null,
    purged_at               timestamp_ntz(9),
    constraint pk_partition_revision primary key (tenant_id, dataset_id, scope_id, partition_start, revision_id)
)
cluster by (tenant_id, dataset_id, partition_start)
data_retention_time_in_days = 1
comment = 'K4/DBT-101-S03: registry of every partition revision incl. zero-row partitions; source of candidate diffs, GC and read-amplification metrics';

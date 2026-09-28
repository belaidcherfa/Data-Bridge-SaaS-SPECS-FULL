-- contract=snowflake-publication-pin version=1 status=DRAFT owner_task=ORC-105 decisions=D-05,D-11,D-26 last_changed=2026-09-28
-- Lane K4 (ORC/DBT), block V0300-V0399. Schema BRIDGE.PUBLICATION.
-- PIN (ORC-105-S01; ADR-014 decision 9): explicit retention holds created by long-lived holders. Cursors create
-- no pins (grace window instead, RECONCILIATION C-07). A pin covers revision r of (tenant, dataset, partition) iff
--   pin.status = 'ACTIVE' and (pin.expires_at is null or pin.expires_at > now)
--   and pin.tenant_id = r.tenant_id
--   and exists a PUBLICATION_MAP row for r with valid_from_seq <= pin.pub_seq < valid_to_seq
--   and (pin.dataset_ids is null or array_contains(r.dataset_id::variant, pin.dataset_ids))
--   and (pin.period_start is null or r.partition_start <  pin.period_end)
--   and (pin.period_end   is null or r.partition_start >= dateadd(<granularity>, -1, pin.period_start) -- partition overlaps period)
-- Writes only through PUBLICATION.PIN_UPSERT / PIN_RELEASE (V0324); pin_id = UUID_STRING(NS_PUBLICATION_PIN,
-- holder_kind || U+001F || holder_id), so a duplicate create returns the same pin (ORC-105-S02).
-- Idempotent (IF NOT EXISTS).

create table if not exists bridge.publication.pin (
    pin_id                  varchar(36)   not null comment 'UUIDv5(NS_PUBLICATION_PIN, holder_kind, holder_id)',
    holder_kind             varchar(24)   not null comment 'REPORT_JOB | ANALYSIS_JOB | EXPORT_JOB | SIMULATION | STATEMENT | RECOVERY_SNAPSHOT | OPERATOR_HOLD',
    holder_id               varchar(128)  not null comment 'Id of the holder (job id, statement id, recovery manifest id, operator hold id)',
    tenant_id               varchar(36)   not null,
    pub_seq                 number(38,0)  not null comment 'Pinned publication (<= tenant pointer at creation)',
    dataset_ids             array                  comment 'NULL = every dataset of the tenant',
    period_start            timestamp_ntz(9)       comment 'Half-open [period_start, period_end) restriction; NULL = unbounded',
    period_end              timestamp_ntz(9),
    status                  varchar(16)   not null comment 'ACTIVE | RELEASED | EXPIRED',
    reason                  varchar(512)           comment 'INTERNAL (operator holds)',
    created_by              varchar(128)  not null comment 'system:<component> or operator subject id',
    created_at              timestamp_ntz(9) not null,
    extended_at             timestamp_ntz(9),
    expires_at              timestamp_ntz(9)       comment 'NULL = until released (STATEMENT, OPERATOR_HOLD)',
    released_at             timestamp_ntz(9),
    constraint pk_pin primary key (pin_id)
)
cluster by (tenant_id)
data_retention_time_in_days = 1
comment = 'K4/ORC-105-S01: publication pins protecting revisions from GC';

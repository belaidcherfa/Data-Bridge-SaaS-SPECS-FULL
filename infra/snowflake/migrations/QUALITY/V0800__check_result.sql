-- contract=snowflake-quality-check-result version=1 status=DRAFT owner_task=DBT-005 decisions=D-05,D-06,D-12 last_changed=2026-09-28
-- Migration block: K9 V0800-V0899 (QUALITY). Artifact row "DDL QUALITY.CHECK_RESULT" (OPS §3; producing step DBT-005-S01,
-- RECONCILIATION U-19/C-23): the single quality-result store, keyed by candidate revision. `ops.quality_results` is NOT created.
-- Writers: DBT-005 check models / on-run-end hook (transform role), OPS-002 transport checks (Dagster asset checks, orchestrator role).
-- Reader/evaluator: ORC-005-S03 is the only eligibility evaluator (publisher role); OPS-002 dashboards (ops reader role).
-- Gate catalog: data/quality/gate-catalog.yaml (check_id, check_version, severity, scope).
-- Snowflake does not enforce PRIMARY KEY/CHECK on standard tables: key uniqueness and enum membership are asserted by the
-- DBT-005 framework test `chk_check_result_integrity` and by the writers; the constraint is declared (RELY) for the optimizer and docs.
--
-- Eligibility rule (normative for ORC-005-S03, OPS-002):
--   A tenant's candidate of build B is eligible iff for EVERY check in gate-catalog.yaml with severity REQUIRED and applies_to covering
--   the tenant's workset datasets, there is a row with status IN ('PASS','WARN') for:
--     - scope PARTITION:      each workset partition (dataset_id, scope_id, partition_start) with candidate_revision_id = that partition's
--                             revision_id in PUBLICATION.PARTITION_REVISION for build B;
--     - scope TENANT_DATASET: each workset dataset with candidate_revision_id = MAX(revision_id) of the tenant's workset partitions of that
--                             dataset in build B (revision ids come from a PostgreSQL sequence and are never reused, so the maximum identifies
--                             exactly this candidate);
--     - scope TENANT:         candidate_revision_id = MAX(revision_id) over all of the tenant's workset partitions in build B.
--   ERROR or a missing row = FAIL (G-OPS-17). A PASS recorded for revision r1 never authorizes r2 (different candidate_revision_id).
--   WARN (ADVISORY checks, or REQUIRED checks that define a warn band) never blocks. Gating is per tenant (D-06).

create table if not exists bridge.quality.check_result (
  tenant_id               varchar(36)      not null comment 'Tenant UUID (lowercase canonical). x-privacy: INTERNAL',
  build_id                varchar(36)      not null comment 'Candidate build UUID (PUBLICATION.BUILD, ADR-014).',
  candidate_revision_id   number(38,0)     not null comment 'revision_id of the candidate (partition revision, or max workset revision for TENANT_DATASET/TENANT scope).',
  dataset_id              varchar(128)     not null comment 'Dataset id from data/contracts/datasets.yaml; "*" for TENANT-scope checks.',
  check_scope             varchar(16)      not null comment 'PARTITION | TENANT_DATASET | TENANT (gate-catalog.yaml scope).',
  scope_id                varchar(64)      comment 'Partition scope (account/organization id) for PARTITION scope; null otherwise.',
  partition_start         timestamp_ntz(9) comment 'Partition start (UTC) for PARTITION scope; null otherwise.',
  partition_key           varchar(256)     not null comment 'Canonical key: <scope_id>/<partition_start ISO-8601 Z> for PARTITION, "*" otherwise.',
  check_id                varchar(32)      not null comment 'Gate id (T01..T04, X01..X04, F01..F06, S01) or DBT-005 check id (checks.yaml).',
  check_version           number(9,0)      not null comment 'Version of the check definition in the catalog.',
  check_family            varchar(16)      not null comment 'TRANSPORT | TRANSFORMATION | FINANCIAL | SEMANTIC | STRUCTURAL.',
  severity                varchar(10)      not null comment 'REQUIRED | ADVISORY (copied from the catalog version at evaluation time).',
  status                  varchar(8)       not null comment 'PASS | WARN | FAIL | ERROR. ERROR = evaluation crashed; treated as FAIL for gating.',
  failing_rows            number(38,0)     comment 'Rows violating the check (0 on PASS); null when not row-based.',
  observed                variant          comment 'Observed values, e.g. {"currency":"USD","ledger":"540.000000000000","source":"270.000000000000"}. No personal data, no SQL text.',
  expected                variant          comment 'Expected values or tolerance, same shape as observed.',
  evidence_ref            varchar(1024)    comment 'Pointer to evidence (failing-row sample table/query id, S3 key); x-privacy: INTERNAL.',
  run_id                  varchar(128)     not null comment 'dbt invocation id or Dagster run id that evaluated the check.',
  evaluator               varchar(32)      not null comment 'DBT_CHECK_MODEL | DBT_TEST_HOOK | DAGSTER_ASSET_CHECK.',
  evaluated_at            timestamp_ntz(9) not null comment 'UTC evaluation time.',
  inserted_at             timestamp_ntz(9) not null default sysdate() comment 'UTC insert time (sessions run with TIMEZONE=UTC).',
  constraint check_result_pk primary key (tenant_id, build_id, dataset_id, partition_key, candidate_revision_id, check_id, check_version) rely
)
cluster by (tenant_id, build_id)
data_retention_time_in_days = 7
comment = 'Single quality result store keyed by candidate revision (RECONCILIATION U-19). Insert-only; a re-evaluation of the same key inserts nothing new (writers use INSERT ... WHERE NOT EXISTS on the key). Retention: 400 days (OPS-005 matrix, operational evidence), purge by ORC-105 GC.';

-- Insert-only access: writers receive INSERT (no UPDATE/DELETE); the publisher and ops readers receive SELECT.
-- Role names are the K1 grants baseline names requested in contracts/_handoffs/K9.md.
grant select, insert on table bridge.quality.check_result to role bridge_transform;
grant select, insert on table bridge.quality.check_result to role bridge_orchestrator;
grant select on table bridge.quality.check_result to role bridge_publisher;
grant select on table bridge.quality.check_result to role bridge_ops_reader;

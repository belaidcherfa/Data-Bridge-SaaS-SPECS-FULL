-- contract=postgres-privacy version=1 status=DRAFT owner_task=OPS-104,OPS-005 decisions=D-10,D-11,D-25,D-26 last_changed=2026-09-28
-- Contract lane: K9 (Operations, release, onboarding, commercial). Schema file owner: K9 (contracts/README.md).
-- Reference DDL for the PostgreSQL `privacy` schema. Alembic migrations `privacy_0000` (OPS-104-S01) and
-- `privacy_0001` (OPS-005-S01) must converge to this file (schema-diff test, CONVENTIONS §1).
--
-- Tables (backlog name -> contract name; CONVENTIONS §2 singular table nouns):
--   privacy.tombstones          -> privacy.tombstone            OPS-104-S01  single tombstone registry (RECONCILIATION U-11, C-19)
--   privacy.deletion_requests   -> privacy.deletion_request     OPS-005-S01  privacy-request workflow (SUBJECT_ACCESS / SUBJECT_ERASURE / TENANT_DELETION, C-20)
--   privacy.deletion_stages     -> privacy.deletion_stage       OPS-005-S01  per-store stages of a request
--   privacy.legal_holds         -> privacy.legal_hold           OPS-005-S01  legal holds (review_by <= 90 days)
--   privacy.identity_dictionary -> privacy.identity_dictionary  SEC-103      D-10 pseudonym -> display name (ADR-009 amendment §1); placed in
--                                                                           this file because K9 owns the `privacy` schema; design owned by SEC-103.
-- State machine: contracts/state-machines/deletion_request.yaml (status sets below are generated from it).
-- RLS: SEC RLS standard template (K2). Until K2 publishes `app.current_tenant()`, the lane template below is used.
-- Runtime roles referenced (SEC Appendix E.1): bridge_api, bridge_worker, bridge_dispatcher, bridge_retention, bridge_ops_ro;
-- bridge_ops_api (ops-plane service role, CTL-102) is requested from K2 in contracts/_handoffs/K9.md.
-- Privacy classes (CONVENTIONS §12) are stated in COMMENT ON COLUMN for every non-trivial column.

CREATE SCHEMA IF NOT EXISTS privacy;
COMMENT ON SCHEMA privacy IS 'Privacy control plane: tombstone registry (OPS-104), privacy requests and legal holds (OPS-005), D-10 identity dictionary (SEC-103). Owner lane K9.';

-- ---------------------------------------------------------------------------------------------
-- Append-only guard (tombstones, identity-free audit rows). UPDATE/DELETE are also not granted;
-- the trigger is defence in depth against the migration owner acting by mistake.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION privacy.forbid_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'privacy.%: % is forbidden on an append-only table', TG_TABLE_NAME, TG_OP
    USING ERRCODE = '42501';
END;
$$;
COMMENT ON FUNCTION privacy.forbid_mutation() IS 'Raises 42501 on UPDATE/DELETE of append-only privacy tables (OPS-104-S01 oracle: UPDATE by runtime role fails).';

-- =============================================================================================
-- privacy.deletion_request  (OPS-005-S01; state machine deletion_request.yaml)
-- =============================================================================================
CREATE TABLE privacy.deletion_request (
  tenant_id                uuid        NOT NULL,
  id                       uuid        NOT NULL,
  request_type             text        NOT NULL,
  status                   text        NOT NULL DEFAULT 'RECEIVED',
  origin                   text        NOT NULL,
  subject_hmac             text        NULL,
  reason_code              text        NOT NULL,
  ticket_ref               text        NULL,
  requested_by             text        NOT NULL,
  approval_id              uuid        NULL,
  approved_by              text        NULL,
  received_at              timestamptz NOT NULL DEFAULT now(),
  due_at                   timestamptz NOT NULL,
  previewed_at             timestamptz NULL,
  approved_at              timestamptz NULL,
  execute_not_before       timestamptz NULL,
  execution_started_at     timestamptz NULL,
  held_at                  timestamptz NULL,
  verified_at              timestamptz NULL,
  certified_at             timestamptz NULL,
  rejected_at              timestamptz NULL,
  reject_reason_code       text        NULL,
  export_job_id            uuid        NULL,
  export_waived            boolean     NOT NULL DEFAULT false,
  result_artifact_id       uuid        NULL,
  certificate_ref          text        NULL,
  certificate_sha256       text        NULL,
  kms_key_deletion_date    date        NULL,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  revision                 bigint      NOT NULL DEFAULT 1,
  CONSTRAINT deletion_request_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT deletion_request_type_ck CHECK (request_type IN ('SUBJECT_ACCESS','SUBJECT_ERASURE','TENANT_DELETION')),
  CONSTRAINT deletion_request_status_ck CHECK (status IN ('RECEIVED','PREVIEWED','APPROVED','HELD','EXECUTING','VERIFIED','CERTIFIED','REJECTED')),
  CONSTRAINT deletion_request_origin_ck CHECK (origin IN ('TENANT_MEMBER','TENANT_OFFBOARDING','OPERATOR_CONTRACT_END')),
  CONSTRAINT deletion_request_subject_ck CHECK ((request_type IN ('SUBJECT_ACCESS','SUBJECT_ERASURE')) = (subject_hmac IS NOT NULL)),
  CONSTRAINT deletion_request_subject_fmt_ck CHECK (subject_hmac IS NULL OR subject_hmac ~ '^[a-z][0-9]+_[A-Za-z0-9_-]{8,256}$'),
  CONSTRAINT deletion_request_origin_type_ck CHECK (origin = 'TENANT_MEMBER' OR request_type = 'TENANT_DELETION'),
  CONSTRAINT deletion_request_reason_ck CHECK (reason_code IN ('CONTROLLER_INSTRUCTION','SUBJECT_REQUEST_VIA_CONTROLLER','END_OF_SERVICE','CONTRACT_TERMINATION','RETENTION_POLICY')),
  CONSTRAINT deletion_request_actor_ck CHECK (requested_by ~ '^(member|operator|system):[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT deletion_request_approver_ck CHECK (approved_by IS NULL OR (approved_by <> requested_by AND approved_by ~ '^(member|operator):[A-Za-z0-9._:-]{1,128}$')),
  CONSTRAINT deletion_request_due_ck CHECK (due_at > received_at AND due_at <= received_at + interval '31 days'),
  CONSTRAINT deletion_request_approved_ck CHECK (status NOT IN ('APPROVED','HELD','EXECUTING','VERIFIED','CERTIFIED') OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  CONSTRAINT deletion_request_certified_ck CHECK (status <> 'CERTIFIED' OR (certificate_ref IS NOT NULL AND certificate_sha256 ~ '^[0-9a-f]{64}$' AND certified_at IS NOT NULL)),
  CONSTRAINT deletion_request_rejected_ck CHECK ((status = 'REJECTED') = (rejected_at IS NOT NULL AND reject_reason_code IS NOT NULL)),
  CONSTRAINT deletion_request_export_ck CHECK (request_type = 'TENANT_DELETION' OR (export_job_id IS NULL AND export_waived = false)),
  CONSTRAINT deletion_request_access_result_ck CHECK (request_type = 'SUBJECT_ACCESS' OR result_artifact_id IS NULL),
  CONSTRAINT deletion_request_revision_ck CHECK (revision >= 1)
);
CREATE UNIQUE INDEX deletion_request_one_open_tenant_deletion
  ON privacy.deletion_request (tenant_id)
  WHERE request_type = 'TENANT_DELETION' AND status NOT IN ('CERTIFIED','REJECTED');
CREATE INDEX deletion_request_tenant_status_idx ON privacy.deletion_request (tenant_id, status, due_at);
CREATE INDEX deletion_request_due_idx ON privacy.deletion_request (due_at) WHERE status NOT IN ('CERTIFIED','REJECTED');

COMMENT ON TABLE privacy.deletion_request IS 'OPS-005-S01. One privacy request (C-20: /v1/privacy/requests). Intake only from an authenticated tenant Owner/Admin (TENANT_MEMBER), from ONB-102/CTL-102 offboarding (TENANT_OFFBOARDING) or an operator at contract end; requests from data subjects are forwarded to the controller, never executed. Due 30 days after receipt (GDPR Art. 12(3) support).';
COMMENT ON COLUMN privacy.deletion_request.subject_hmac IS 'x-privacy: INTERNAL (keyed D-10 pseudonym, e.g. u1_...; resolvable only through privacy.identity_dictionary while it exists). Required for SUBJECT_* requests. The typed name/e-mail used at intake is never stored.';
COMMENT ON COLUMN privacy.deletion_request.requested_by IS 'x-privacy: INTERNAL. Actor reference member:<membership_id> | operator:<operator_id> | system:<component>.';
COMMENT ON COLUMN privacy.deletion_request.approval_id IS 'SEC-102 approval id (governance approvals, action privacy.erasure.request / tenant deletion); cross-lane reference without FK (see contracts/_handoffs/K9.md).';
COMMENT ON COLUMN privacy.deletion_request.approved_by IS 'x-privacy: INTERNAL. Must differ from requested_by (four-eyes, OPS-005-S01 oracle).';
COMMENT ON COLUMN privacy.deletion_request.execute_not_before IS 'TENANT_DELETION from offboarding: end of the export window (ONB-102); APPROVED -> EXECUTING is refused before it.';
COMMENT ON COLUMN privacy.deletion_request.export_job_id IS 'API-102 tenant export job (ONB-102-S02, export kind TENANT_EXPORT_BUNDLE) completed before stage EXPORT_COMPLETED_OR_WAIVED.';
COMMENT ON COLUMN privacy.deletion_request.result_artifact_id IS 'SUBJECT_ACCESS only: artifact id of the CSV export (downloaded through the SEC-006-S08 broker).';
COMMENT ON COLUMN privacy.deletion_request.certificate_ref IS 'Evidence object key of the deletion certificate JSON (+ PDF) listing residual copies with expiry dates (OPS-005-S10).';
COMMENT ON COLUMN privacy.deletion_request.kms_key_deletion_date IS 'TENANT_DELETION: date the tenant KMS key (D-10 dictionary) becomes deleted after ScheduleKeyDeletion (7..30 day waiting period).';

-- =============================================================================================
-- privacy.legal_hold  (OPS-005-S01, S13)
-- =============================================================================================
CREATE TABLE privacy.legal_hold (
  tenant_id          uuid        NOT NULL,
  id                 uuid        NOT NULL,
  scope_type         text        NOT NULL,
  account_id         uuid        NULL,
  subject_hmac       text        NULL,
  dataset            text        NULL,
  reason_code        text        NOT NULL,
  reason_detail      text        NOT NULL,
  case_ref           text        NULL,
  status             text        NOT NULL DEFAULT 'REQUESTED',
  requested_by       text        NOT NULL,
  approved_by        text        NULL,
  activated_at       timestamptz NULL,
  last_reviewed_at   timestamptz NOT NULL DEFAULT now(),
  review_by          timestamptz NOT NULL,
  released_at        timestamptz NULL,
  released_by        text        NULL,
  release_reason     text        NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  revision           bigint      NOT NULL DEFAULT 1,
  CONSTRAINT legal_hold_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT legal_hold_scope_ck CHECK (scope_type IN ('TENANT','ACCOUNT','SUBJECT','DATASET')),
  CONSTRAINT legal_hold_scope_fields_ck CHECK (
       (scope_type = 'TENANT'  AND account_id IS NULL AND subject_hmac IS NULL AND dataset IS NULL)
    OR (scope_type = 'ACCOUNT' AND account_id IS NOT NULL AND subject_hmac IS NULL)
    OR (scope_type = 'SUBJECT' AND subject_hmac IS NOT NULL AND account_id IS NULL AND dataset IS NULL)
    OR (scope_type = 'DATASET' AND dataset IS NOT NULL AND subject_hmac IS NULL)),
  CONSTRAINT legal_hold_reason_ck CHECK (reason_code IN ('LITIGATION','REGULATORY_INQUIRY','SECURITY_INVESTIGATION','BILLING_DISPUTE','CONTROLLER_INSTRUCTION')),
  CONSTRAINT legal_hold_detail_ck CHECK (char_length(reason_detail) BETWEEN 10 AND 2000),
  CONSTRAINT legal_hold_status_ck CHECK (status IN ('REQUESTED','ACTIVE','REVIEW_OVERDUE','RELEASED','REJECTED')),
  CONSTRAINT legal_hold_actor_ck CHECK (requested_by ~ '^(member|operator):[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT legal_hold_approver_ck CHECK (approved_by IS NULL OR approved_by <> requested_by),
  CONSTRAINT legal_hold_active_ck CHECK (status NOT IN ('ACTIVE','REVIEW_OVERDUE','RELEASED') OR (approved_by IS NOT NULL AND activated_at IS NOT NULL)),
  CONSTRAINT legal_hold_review_window_ck CHECK (review_by > last_reviewed_at AND review_by <= last_reviewed_at + interval '90 days'),
  CONSTRAINT legal_hold_release_ck CHECK ((status = 'RELEASED') = (released_at IS NOT NULL AND released_by IS NOT NULL AND release_reason IS NOT NULL)),
  CONSTRAINT legal_hold_releaser_ck CHECK (released_by IS NULL OR released_by <> requested_by),
  CONSTRAINT legal_hold_revision_ck CHECK (revision >= 1)
);
CREATE INDEX legal_hold_active_idx ON privacy.legal_hold (tenant_id, scope_type) WHERE status IN ('ACTIVE','REVIEW_OVERDUE');
CREATE INDEX legal_hold_review_idx ON privacy.legal_hold (review_by) WHERE status = 'ACTIVE';
COMMENT ON TABLE privacy.legal_hold IS 'OPS-005-S01/S13. A hold blocks exactly the deletion stages overlapping its scope. review_by is at most 90 days after the last review; a passed review_by moves the hold to REVIEW_OVERDUE (ticket + alarm), never releases or extends it silently. Release requires an approver different from the requester.';
COMMENT ON COLUMN privacy.legal_hold.subject_hmac IS 'x-privacy: INTERNAL (keyed D-10 pseudonym).';
COMMENT ON COLUMN privacy.legal_hold.reason_detail IS 'x-privacy: INTERNAL. Free text without personal data (lint in service); case details live in the legal case system referenced by case_ref.';
COMMENT ON COLUMN privacy.legal_hold.dataset IS 'Dataset id from data/contracts/datasets.yaml (DBT-101) or a store key from infra/lifecycle/retention-matrix.yaml.';

-- =============================================================================================
-- privacy.deletion_stage  (OPS-005-S01, S09, S10)
-- Stage keys are the ordered stages of OPS-005-S09 (TENANT_DELETION), S11 (SUBJECT_ACCESS) and S12 (SUBJECT_ERASURE).
-- =============================================================================================
CREATE TABLE privacy.deletion_stage (
  tenant_id            uuid        NOT NULL,
  id                   uuid        NOT NULL,
  request_id           uuid        NOT NULL,
  stage_order          smallint    NOT NULL,
  stage_key            text        NOT NULL,
  store                text        NOT NULL,
  status               text        NOT NULL DEFAULT 'PLANNED',
  expected_count       bigint      NULL,
  deleted_count        bigint      NULL,
  residual_count       bigint      NULL,
  verified_at          timestamptz NULL,
  hold_id              uuid        NULL,
  residual_expires_at  timestamptz NULL,
  attempts             integer     NOT NULL DEFAULT 0,
  started_at           timestamptz NULL,
  completed_at         timestamptz NULL,
  error_class          text        NULL,
  error_detail         text        NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  revision             bigint      NOT NULL DEFAULT 1,
  CONSTRAINT deletion_stage_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT deletion_stage_request_fk FOREIGN KEY (tenant_id, request_id) REFERENCES privacy.deletion_request (tenant_id, id),
  CONSTRAINT deletion_stage_hold_fk FOREIGN KEY (tenant_id, hold_id) REFERENCES privacy.legal_hold (tenant_id, id),
  CONSTRAINT deletion_stage_unique UNIQUE (tenant_id, request_id, stage_key),
  CONSTRAINT deletion_stage_order_unique UNIQUE (tenant_id, request_id, stage_order),
  CONSTRAINT deletion_stage_key_ck CHECK (stage_key IN (
    -- TENANT_DELETION (OPS-005-S09, ordered)
    'TENANT_DELETING','SCHEDULES_PAUSED','IAM_DENY_ATTACHED','EPOCH_BUMPED_SESSIONS_REVOKED','LEASES_FENCED',
    'EXPORT_COMPLETED_OR_WAIVED','SNOWFLAKE_SERVING','SNOWFLAKE_CANONICAL','SNOWFLAKE_RAW','SNOWFLAKE_OPS_FACTS',
    'S3_ALL_VERSIONS','RECOVERY_BUCKET','REDIS','POSTGRESQL','KMS_KEY_DELETION_SCHEDULED',
    -- SUBJECT_ERASURE (OPS-005-S12 via SEC-103 erase_subject)
    'DICTIONARY_ENTRY_DELETED','SUBJECT_TOMBSTONE_RECORDED','AUTHZ_EPOCH_BUMPED','REDIS_SUBJECT_KEYS',
    -- SUBJECT_ACCESS (OPS-005-S11)
    'DICTIONARY_EXPORT','ACTIVITY_EXPORT','EXPORT_ARTIFACT_READY')),
  CONSTRAINT deletion_stage_store_ck CHECK (store IN ('CONTROL','POSTGRESQL','SNOWFLAKE','S3','RECOVERY_BUCKET','REDIS','AWS_IAM','AWS_KMS','ARTIFACT')),
  CONSTRAINT deletion_stage_status_ck CHECK (status IN ('PLANNED','RUNNING','DONE','VERIFIED','HELD','FAILED','SKIPPED')),
  CONSTRAINT deletion_stage_counts_ck CHECK ((expected_count IS NULL OR expected_count >= 0) AND (deleted_count IS NULL OR deleted_count >= 0) AND (residual_count IS NULL OR residual_count >= 0)),
  CONSTRAINT deletion_stage_verified_ck CHECK (status <> 'VERIFIED' OR (verified_at IS NOT NULL AND residual_count = 0)),
  CONSTRAINT deletion_stage_held_ck CHECK ((status = 'HELD') = (hold_id IS NOT NULL)),
  CONSTRAINT deletion_stage_error_ck CHECK (status <> 'FAILED' OR error_class IS NOT NULL),
  CONSTRAINT deletion_stage_error_detail_ck CHECK (error_detail IS NULL OR char_length(error_detail) <= 2000),
  CONSTRAINT deletion_stage_order_ck CHECK (stage_order BETWEEN 1 AND 99),
  CONSTRAINT deletion_stage_revision_ck CHECK (revision >= 1)
);
CREATE INDEX deletion_stage_request_idx ON privacy.deletion_stage (tenant_id, request_id, stage_order);
COMMENT ON TABLE privacy.deletion_stage IS 'OPS-005-S01/S09/S10. One row per ordered stage of a privacy request. Stages are idempotent and resumable; a stage is VERIFIED only when its verification query returns residual_count = 0. HELD stages reference the overlapping privacy.legal_hold; other stages proceed.';
COMMENT ON COLUMN privacy.deletion_stage.expected_count IS 'Preview count (POST /v1/privacy/requests preview) of rows/objects/keys in this store for the request scope.';
COMMENT ON COLUMN privacy.deletion_stage.residual_expires_at IS 'Expiry of residual copies not deletable by Bridge (Aurora PITR +35 d, Snowflake Backups +35 d, Time Travel + 7 d Fail-safe, KMS key waiting period) - copied into the deletion certificate.';
COMMENT ON COLUMN privacy.deletion_stage.error_detail IS 'x-privacy: INTERNAL. Sanitized error text (no SQL, no identifiers other than UUIDs).';
COMMENT ON COLUMN privacy.deletion_stage.error_class IS 'Error class from packages/telemetry/error_taxonomy.py (OPS-001-S02).';

-- =============================================================================================
-- privacy.tombstone  (OPS-104-S01) - append-only, mirrored to S3 (tombstone.v1.json) via the outbox
-- =============================================================================================
CREATE TABLE privacy.tombstone (
  tenant_id       uuid        NOT NULL,
  id              uuid        NOT NULL,
  seq             bigint      GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1 NO CYCLE),
  kind            text        NOT NULL,
  account_id      uuid        NULL,
  connection_id   uuid        NULL,
  subject_hmac    text        NULL,
  dataset         text        NULL,
  range_start     timestamptz NULL,
  range_end       timestamptz NULL,
  effective_at    timestamptz NOT NULL,
  request_id      uuid        NULL,
  legal_basis     text        NOT NULL,
  created_by      text        NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  revision        bigint      NOT NULL DEFAULT 1,
  CONSTRAINT tombstone_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT tombstone_seq_unique UNIQUE (seq),
  CONSTRAINT tombstone_request_fk FOREIGN KEY (tenant_id, request_id) REFERENCES privacy.deletion_request (tenant_id, id),
  CONSTRAINT tombstone_kind_ck CHECK (kind IN ('TENANT','ACCOUNT','CONNECTION','SUBJECT','DATASET_RANGE')),
  CONSTRAINT tombstone_kind_fields_ck CHECK (
       (kind = 'TENANT'        AND account_id IS NULL AND connection_id IS NULL AND subject_hmac IS NULL AND dataset IS NULL AND range_start IS NULL AND range_end IS NULL)
    OR (kind = 'ACCOUNT'       AND account_id IS NOT NULL AND subject_hmac IS NULL AND dataset IS NULL AND range_start IS NULL AND range_end IS NULL)
    OR (kind = 'CONNECTION'    AND connection_id IS NOT NULL AND subject_hmac IS NULL AND dataset IS NULL AND range_start IS NULL AND range_end IS NULL)
    OR (kind = 'SUBJECT'       AND subject_hmac IS NOT NULL AND account_id IS NULL AND connection_id IS NULL AND dataset IS NULL AND range_start IS NULL AND range_end IS NULL)
    OR (kind = 'DATASET_RANGE' AND dataset IS NOT NULL AND range_start IS NOT NULL AND range_end IS NOT NULL AND range_start < range_end AND subject_hmac IS NULL)),
  CONSTRAINT tombstone_subject_fmt_ck CHECK (subject_hmac IS NULL OR subject_hmac ~ '^[a-z][0-9]+_[A-Za-z0-9_-]{8,256}$'),
  CONSTRAINT tombstone_dataset_fmt_ck CHECK (dataset IS NULL OR dataset ~ '^[a-z][a-z0-9_]{1,127}$'),
  CONSTRAINT tombstone_legal_basis_ck CHECK (legal_basis IN ('CONTROLLER_INSTRUCTION','SUBJECT_REQUEST_VIA_CONTROLLER','END_OF_SERVICE','CONTRACT_TERMINATION','RETENTION_POLICY','CUSTOMER_DISCONNECT')),
  CONSTRAINT tombstone_actor_ck CHECK (created_by ~ '^(member|operator|system):[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT tombstone_append_only_ck CHECK (revision = 1)
);
CREATE INDEX tombstone_tenant_kind_idx ON privacy.tombstone (tenant_id, kind, seq);
CREATE INDEX tombstone_subject_idx ON privacy.tombstone (tenant_id, subject_hmac) WHERE kind = 'SUBJECT';
CREATE TRIGGER tombstone_append_only BEFORE UPDATE OR DELETE ON privacy.tombstone
  FOR EACH ROW EXECUTE FUNCTION privacy.forbid_mutation();
COMMENT ON TABLE privacy.tombstone IS 'OPS-104-S01. The only tombstone registry (RECONCILIATION U-11, C-19). INSERT-only; inserted together with outbox event bridge.ops.tombstone.recorded in one transaction; the dispatcher mirrors each row to s3://<tombstone-bucket>/tombstones/seq=<20-digit zero-padded seq>.json (data/contracts/privacy/tombstone.v1.json) in the security/log-archive account, outside every restore scope. Restores replay the S3 log (seq > manifest tombstone_hwm) before enabling traffic. No FK to connection/account tables: tombstones outlive the rows they refer to.';
COMMENT ON COLUMN privacy.tombstone.seq IS 'Monotonic (not necessarily gapless in PG after rolled-back inserts; the S3 loader detects gaps against PG when PG is available - OPS-104-S04 TOMBSTONE_GAP).';
COMMENT ON COLUMN privacy.tombstone.subject_hmac IS 'x-privacy: INTERNAL. Keyed D-10 pseudonym only; tombstones contain no personal data (OPS-104 acceptance).';
COMMENT ON COLUMN privacy.tombstone.dataset IS 'DATASET_RANGE: dataset id (data/contracts/datasets.yaml); range is half-open [range_start, range_end).';
COMMENT ON COLUMN privacy.tombstone.created_by IS 'x-privacy: INTERNAL. member:<membership_id> | operator:<operator_id> | system:<component>.';

-- =============================================================================================
-- privacy.identity_dictionary  (SEC-103; ADR-009 amendment §1, SEC Appendix G.2) - PERSONAL data
-- =============================================================================================
CREATE TABLE privacy.identity_dictionary (
  tenant_id          uuid        NOT NULL,
  id                 uuid        NOT NULL,
  pseudonym          text        NOT NULL,
  kind               text        NOT NULL,
  display_name       text        NOT NULL,
  email_norm         text        NULL,
  source_account_id  uuid        NULL,
  first_seen         timestamptz NOT NULL,
  last_seen          timestamptz NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  revision           bigint      NOT NULL DEFAULT 1,
  CONSTRAINT identity_dictionary_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT identity_dictionary_pseudonym_unique UNIQUE (tenant_id, pseudonym),
  CONSTRAINT identity_dictionary_kind_ck CHECK (kind IN ('USER','EMAIL','TAG_VALUE')),
  CONSTRAINT identity_dictionary_pseudonym_fmt_ck CHECK (pseudonym ~ '^[a-z][0-9]+_[A-Za-z0-9_-]{8,256}$'),
  CONSTRAINT identity_dictionary_seen_ck CHECK (last_seen >= first_seen),
  CONSTRAINT identity_dictionary_name_len_ck CHECK (char_length(display_name) BETWEEN 1 AND 512),
  CONSTRAINT identity_dictionary_revision_ck CHECK (revision >= 1)
);
CREATE INDEX identity_dictionary_email_idx ON privacy.identity_dictionary (tenant_id, email_norm) WHERE email_norm IS NOT NULL;
COMMENT ON TABLE privacy.identity_dictionary IS 'SEC-103 (design owner) / K9 schema file. D-10: pseudonym -> display name. Lives only here (never exported to S3 or Snowflake). Subject erasure = DELETE of the row + SUBJECT tombstone + tenant authz_epoch bump (OPS-005-S12 via SEC-103-S09 erase_subject). The API resolves names after Snowflake returns rows, only for callers holding identity.resolve.';
COMMENT ON COLUMN privacy.identity_dictionary.pseudonym IS 'x-privacy: INTERNAL. HMAC-SHA256 pseudonym with scheme prefix (u1_ user, e1_ e-mail, t1_ tag value).';
COMMENT ON COLUMN privacy.identity_dictionary.display_name IS 'x-privacy: PERSONAL. Snowflake USER_NAME / display value; never logged, never exported outside PostgreSQL.';
COMMENT ON COLUMN privacy.identity_dictionary.email_norm IS 'x-privacy: PERSONAL. Lower-cased e-mail when the source value is an e-mail (used only to locate a subject for SUBJECT_* intake).';

-- =============================================================================================
-- Row level security (SEC RLS standard; lane template until K2 publishes app.current_tenant())
-- =============================================================================================
ALTER TABLE privacy.deletion_request   ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy.deletion_request   FORCE ROW LEVEL SECURITY;
ALTER TABLE privacy.legal_hold         ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy.legal_hold         FORCE ROW LEVEL SECURITY;
ALTER TABLE privacy.deletion_stage     ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy.deletion_stage     FORCE ROW LEVEL SECURITY;
ALTER TABLE privacy.tombstone          ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy.tombstone          FORCE ROW LEVEL SECURITY;
ALTER TABLE privacy.identity_dictionary ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy.identity_dictionary FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON privacy.deletion_request
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON privacy.legal_hold
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON privacy.deletion_stage
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON privacy.tombstone
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON privacy.identity_dictionary
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
-- Allowlisted cross-tenant readers (SEC Appendix E.3(c)): the tombstone mirror (dispatcher) and the
-- privacy request sweeper (due dates, hold reviews) read across tenants; they never write tenant data.
CREATE POLICY tombstone_mirror_read ON privacy.tombstone FOR SELECT TO bridge_dispatcher USING (true);
CREATE POLICY deletion_request_sweeper_read ON privacy.deletion_request FOR SELECT TO bridge_retention USING (true);
CREATE POLICY legal_hold_sweeper_read ON privacy.legal_hold FOR SELECT TO bridge_retention USING (true);

-- =============================================================================================
-- Grants (explicit, no default privileges; SEC Appendix E.1)
-- =============================================================================================
REVOKE ALL ON ALL TABLES IN SCHEMA privacy FROM PUBLIC;
GRANT USAGE ON SCHEMA privacy TO bridge_api, bridge_worker, bridge_dispatcher, bridge_retention, bridge_ops_api;
GRANT SELECT, INSERT, UPDATE ON privacy.deletion_request TO bridge_api, bridge_worker;
GRANT SELECT ON privacy.deletion_request TO bridge_retention, bridge_ops_api;
GRANT SELECT, INSERT, UPDATE ON privacy.deletion_stage TO bridge_worker;
GRANT SELECT ON privacy.deletion_stage TO bridge_api, bridge_ops_api;
GRANT SELECT, INSERT, UPDATE ON privacy.legal_hold TO bridge_ops_api;
GRANT SELECT ON privacy.legal_hold TO bridge_worker, bridge_retention;
GRANT SELECT, INSERT ON privacy.tombstone TO bridge_worker;
GRANT SELECT ON privacy.tombstone TO bridge_dispatcher, bridge_ops_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON privacy.identity_dictionary TO bridge_worker;
GRANT SELECT ON privacy.identity_dictionary TO bridge_api;
-- No role (other than the migration owner) holds UPDATE or DELETE on privacy.tombstone.

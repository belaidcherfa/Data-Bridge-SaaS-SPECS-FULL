-- contract=pg-audit version=1 status=DRAFT owner_task=SEC-008 decisions=D-10,D-25 last_changed=2026-09-28
-- =====================================================================================================
-- Schema `audit`: append-only audit trail, export ledger, signed export batches, user-requested audit exports.
-- Normative sources: SEC backlog Appendix H (fields, export chain, access, retention), G-SEC-17, CTL-101-S07
-- (minimal table + emit_audit), SEC-008-S02..S08/S14. Event payload contract: contracts/audit/audit-event.v1.schema.json;
-- action catalog: contracts/audit/actions.yaml; taxonomy: docs/security/audit-taxonomy.md.
--
-- Naming (CONVENTIONS §10 singular): audit.events -> audit.event; audit.event_exports -> audit.event_export.
-- Table class (d) APPEND-ONLY. audit.event is RANGE-partitioned by month on occurred_at; the partition key must
-- be part of the PK, hence PK (event_id, occurred_at) instead of (tenant_id, id) (allowlisted; tenant_id is NULL
-- for platform events). Runtime roles are granted on the parent only; partitions have no grants.
-- Emission rules: ALLOWED outcomes inside the business transaction; DENIED/FAILED in a separate short transaction
-- after rollback; read denials rate-limited to 1/min per (subject, route). Apply after identity.sql.
-- =====================================================================================================

CREATE SCHEMA audit AUTHORIZATION bridge_owner;
COMMENT ON SCHEMA audit IS 'Append-only audit trail and signed export chain (SEC-008). owner_task=SEC-008';
GRANT USAGE ON SCHEMA audit TO bridge_api, bridge_worker, bridge_dispatcher, bridge_audit_exporter, bridge_retention, bridge_ops_ro;

CREATE TABLE audit.event (
  event_id              uuid        NOT NULL,          -- UUIDv7
  tenant_id             uuid        NULL,              -- NULL only for platform events (operator/platform actions without tenant)
  occurred_at           timestamptz NOT NULL,          -- UTC, microsecond precision
  recorded_at           timestamptz NOT NULL DEFAULT clock_timestamp(),
  actor_type            text        NOT NULL CHECK (actor_type IN ('MEMBER', 'SUPPORT', 'SERVICE', 'OPERATOR', 'ANONYMOUS', 'MACHINE_CLIENT')),
  actor_subject_id      uuid        NULL,
  actor_membership_id   uuid        NULL,
  actor_machine_client_id uuid      NULL,
  actor_service         text        NULL CHECK (actor_service IS NULL OR actor_service ~ '^[a-z0-9-]+$'),
  action                text        NOT NULL CHECK (action ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'),  -- contracts/audit/actions.yaml
  object_type           text        NULL CHECK (object_type IS NULL OR object_type ~ '^[a-z][a-z0-9_]*$'),
  object_id             text        NULL CHECK (object_id IS NULL OR char_length(object_id) <= 128),
  object_version        bigint      NULL,
  outcome               text        NOT NULL CHECK (outcome IN ('ALLOWED', 'DENIED', 'FAILED')),
  reason_code           text        NULL CHECK (reason_code IS NULL OR reason_code ~ '^[A-Z][A-Z0-9_]{1,63}$'),  -- problem code for DENIED/FAILED
  capability            text        NULL,              -- capability checked (contracts/authz/capabilities.yaml)
  request_id            text        NULL CHECK (request_id IS NULL OR char_length(request_id) <= 64),
  correlation_id        text        NULL CHECK (correlation_id IS NULL OR char_length(correlation_id) <= 128),
  session_id_hash       bytea       NULL CHECK (session_id_hash IS NULL OR octet_length(session_id_hash) = 32),  -- sha256(session.id), never the sid
  ip                    inet        NULL,              -- full address, PG only (365 d); exported truncated + encrypted
  user_agent            text        NULL CHECK (user_agent IS NULL OR char_length(user_agent) <= 256),
  object_scope_json     jsonb       NULL,              -- canonical atoms of the object scope; NULL = tenant-level event (H.3)
  before_redacted       jsonb       NULL CHECK (before_redacted IS NULL OR pg_column_size(before_redacted) <= 16384),
  after_redacted        jsonb       NULL CHECK (after_redacted IS NULL OR pg_column_size(after_redacted) <= 16384),
  redaction_schema_version smallint NOT NULL DEFAULT 1,
  approval_id           uuid        NULL,
  support_access_grant_id uuid      NULL,
  CONSTRAINT event_pk PRIMARY KEY (event_id, occurred_at),
  CONSTRAINT event_actor_consistency CHECK (
       (actor_type IN ('MEMBER', 'SUPPORT') AND actor_subject_id IS NOT NULL)
    OR (actor_type = 'OPERATOR' AND actor_subject_id IS NOT NULL)
    OR (actor_type = 'SERVICE' AND actor_service IS NOT NULL)
    OR (actor_type = 'MACHINE_CLIENT' AND actor_machine_client_id IS NOT NULL)
    OR (actor_type = 'ANONYMOUS' AND actor_subject_id IS NULL)),
  CONSTRAINT event_support_consistency CHECK ((actor_type = 'SUPPORT') = (support_access_grant_id IS NOT NULL)),
  CONSTRAINT event_denied_reason CHECK (outcome = 'ALLOWED' OR reason_code IS NOT NULL)
) PARTITION BY RANGE (occurred_at);
ALTER TABLE audit.event OWNER TO bridge_owner;
COMMENT ON TABLE audit.event IS 'Append-only audit log (Appendix H.1). UPDATE/DELETE forbidden for every role (trigger); retention detaches monthly partitions > 365 d only after their export batches are verified (SEC-008-S14). owner_task=SEC-008';
COMMENT ON COLUMN audit.event.ip IS 'x-privacy: PERSONAL (full in PG 365 d; export: /24 or /48 + KMS-encrypted full value)';
COMMENT ON COLUMN audit.event.user_agent IS 'x-privacy: PERSONAL';
COMMENT ON COLUMN audit.event.before_redacted IS 'Redacted per-object field allowlist (packages/audit/diff.py); never secrets, tokens, SQL text or destination URL paths. x-privacy: CUSTOMER_METADATA';
COMMENT ON COLUMN audit.event.after_redacted IS 'See before_redacted. x-privacy: CUSTOMER_METADATA';

-- Initial partitions; audit.ensure_partitions() creates the next months (monthly maintenance job).
CREATE TABLE audit.event_2026_09 PARTITION OF audit.event FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');
CREATE TABLE audit.event_2026_10 PARTITION OF audit.event FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');
CREATE TABLE audit.event_default PARTITION OF audit.event DEFAULT;   -- must stay empty; non-empty pages (maintenance lag)

CREATE INDEX event_tenant_time ON audit.event (tenant_id, occurred_at DESC);
CREATE INDEX event_tenant_actor ON audit.event (tenant_id, actor_subject_id, occurred_at);
CREATE INDEX event_tenant_object ON audit.event (tenant_id, object_type, object_id);
CREATE INDEX event_tenant_action ON audit.event (tenant_id, action, occurred_at DESC);

ALTER TABLE audit.event ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.event FORCE ROW LEVEL SECURITY;
CREATE POLICY producer_insert ON audit.event AS PERMISSIVE FOR INSERT TO bridge_api, bridge_worker, bridge_dispatcher
  WITH CHECK (tenant_id = app.current_tenant() OR (tenant_id IS NULL AND app.is_platform_context()));
CREATE POLICY tenant_read ON audit.event AS PERMISSIVE FOR SELECT TO bridge_api
  USING (tenant_id = app.current_tenant());          -- scope filtering (H.3) is applied by the audit.read predicate on top
CREATE POLICY exporter_read ON audit.event AS PERMISSIVE FOR SELECT TO bridge_audit_exporter USING (true);
GRANT INSERT ON audit.event TO bridge_api, bridge_worker, bridge_dispatcher;
GRANT SELECT ON audit.event TO bridge_api, bridge_audit_exporter;

CREATE FUNCTION audit.forbid_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'AUDIT_APPEND_ONLY';
END $$;
ALTER FUNCTION audit.forbid_mutation() OWNER TO bridge_owner;
CREATE TRIGGER event_append_only BEFORE UPDATE OR DELETE ON audit.event
  FOR EACH ROW EXECUTE FUNCTION audit.forbid_mutation();

-- -----------------------------------------------------------------------------------------------------
-- Export chain (Appendix H.2, SEC-008-S06). chain_key = tenant uuid or 'platform'. Selection of unexported rows
-- uses the export ledger (NOT a time watermark) with a 2-minute settle delay:
--   SELECT e.* FROM audit.event e LEFT JOIN audit.event_export x ON x.event_id = e.event_id
--    WHERE x.event_id IS NULL AND e.recorded_at < now() - interval '2 minutes' AND <chain predicate>
--    ORDER BY e.recorded_at, e.event_id LIMIT 10000;
-- digest_n = sha256(prev_digest || sha256(batch_bytes) || canonical(manifest fields)); manifest signed by KMS
-- ECC_NIST_P256 (kms:Sign only for the exporter role); batches go to the log-archive account bucket, Object Lock
-- GOVERNANCE 365 d.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE audit.export_batch (
  chain_key          text        NOT NULL CHECK (chain_key = 'platform' OR chain_key ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),
  batch_seq          bigint      NOT NULL CHECK (batch_seq >= 1),
  id                 uuid        NOT NULL,
  tenant_id          uuid        NULL,                 -- NULL for chain_key = 'platform'
  event_count        integer     NOT NULL CHECK (event_count BETWEEN 1 AND 100000),
  first_event_id     uuid        NOT NULL,
  last_event_id      uuid        NOT NULL,
  first_recorded_at  timestamptz NOT NULL,
  last_recorded_at   timestamptz NOT NULL,
  batch_sha256       text        NOT NULL CHECK (batch_sha256 ~ '^[0-9a-f]{64}$'),   -- sha256 of the JSONL.gz bytes
  prev_digest        text        NOT NULL CHECK (prev_digest ~ '^[0-9a-f]{64}$'),    -- 64 zeros for batch_seq = 1
  digest             text        NOT NULL CHECK (digest ~ '^[0-9a-f]{64}$'),
  manifest_sha256    text        NOT NULL CHECK (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  signature_b64      text        NOT NULL,                                          -- KMS ECDSA_SHA_256 over manifest bytes
  kms_key_arn        text        NOT NULL,
  s3_bucket          text        NOT NULL,
  s3_key             text        NOT NULL CHECK (s3_key ~ '^audit/v1/(platform|[0-9a-f-]{36})/[0-9]{12}\.jsonl\.gz$'),
  status             text        NOT NULL DEFAULT 'WRITTEN' CHECK (status IN ('WRITTEN', 'VERIFIED', 'VERIFY_FAILED')),
  verified_at        timestamptz NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT export_batch_pk PRIMARY KEY (chain_key, batch_seq),
  CONSTRAINT export_batch_id_uq UNIQUE (id),
  CONSTRAINT export_batch_tenant_consistency CHECK ((chain_key = 'platform') = (tenant_id IS NULL))
);
ALTER TABLE audit.export_batch OWNER TO bridge_owner;
COMMENT ON TABLE audit.export_batch IS 'Signed, hash-chained export batches (manifest: contracts/audit/export-manifest.v1.schema.json). owner_task=SEC-008';
ALTER TABLE audit.export_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.export_batch FORCE ROW LEVEL SECURITY;
CREATE POLICY exporter_rw ON audit.export_batch AS PERMISSIVE FOR ALL TO bridge_audit_exporter USING (true) WITH CHECK (true);
CREATE POLICY ops_read ON audit.export_batch AS PERMISSIVE FOR SELECT TO bridge_ops_ro, bridge_retention USING (true);
GRANT SELECT, INSERT, UPDATE (status, verified_at) ON audit.export_batch TO bridge_audit_exporter;
GRANT SELECT ON audit.export_batch TO bridge_ops_ro, bridge_retention;

CREATE TABLE audit.event_export (
  event_id      uuid        NOT NULL,
  occurred_at   timestamptz NOT NULL,
  chain_key     text        NOT NULL,
  batch_seq     bigint      NOT NULL,
  exported_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_export_pk PRIMARY KEY (event_id),
  CONSTRAINT event_export_batch_fk FOREIGN KEY (chain_key, batch_seq) REFERENCES audit.export_batch (chain_key, batch_seq)
);
ALTER TABLE audit.event_export OWNER TO bridge_owner;
COMMENT ON TABLE audit.event_export IS 'Export ledger: one row per exported event (late commits with older timestamps land in the next batch). owner_task=SEC-008';
CREATE INDEX event_export_batch ON audit.event_export (chain_key, batch_seq);
ALTER TABLE audit.event_export ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.event_export FORCE ROW LEVEL SECURITY;
CREATE POLICY exporter_rw ON audit.event_export AS PERMISSIVE FOR ALL TO bridge_audit_exporter USING (true) WITH CHECK (true);
CREATE POLICY retention_read ON audit.event_export AS PERMISSIVE FOR SELECT TO bridge_retention USING (true);
GRANT SELECT, INSERT ON audit.event_export TO bridge_audit_exporter;
GRANT SELECT ON audit.event_export TO bridge_retention;

-- -----------------------------------------------------------------------------------------------------
-- audit.export_request - customer-requested audit exports (POST /v1/audit/exports, capability audit.export).
-- Async job (D-33 worker); the artifact is downloaded through the SEC-006-S08 artifact broker.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE audit.export_request (
  tenant_id               uuid        NOT NULL,
  id                      uuid        NOT NULL,
  requested_by_membership_id uuid     NOT NULL,
  requested_by_subject_id uuid        NOT NULL,
  filter_json             jsonb       NOT NULL CHECK (jsonb_typeof(filter_json) = 'object'),   -- AuditExportFilter (OpenAPI platform component)
  filter_schema_version   smallint    NOT NULL DEFAULT 1,
  format                  text        NOT NULL DEFAULT 'JSONL' CHECK (format IN ('JSONL', 'CSV')),
  binding_permission_epoch bigint     NOT NULL,        -- revocation binding (Appendix F)
  binding_profile_hash    text        NULL,
  status                  text        NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED', 'RUNNING', 'SUCCEEDED', 'FAILED', 'CANCELLED', 'EXPIRED')),
  row_count               integer     NULL CHECK (row_count IS NULL OR row_count BETWEEN 0 AND 1000000),
  artifact_id             uuid        NULL,            -- artifact broker id (SEC-006-S08)
  error_code              text        NULL,
  requested_at            timestamptz NOT NULL DEFAULT now(),
  started_at              timestamptz NULL,
  completed_at            timestamptz NULL,
  expires_at              timestamptz NULL,            -- artifact availability (7 d)
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  revision                bigint      NOT NULL DEFAULT 1,
  CONSTRAINT export_request_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT export_request_tenant_fk FOREIGN KEY (tenant_id) REFERENCES identity.tenant (id),
  CONSTRAINT export_request_requester_fk FOREIGN KEY (tenant_id, requested_by_membership_id) REFERENCES identity.membership (tenant_id, id)
);
ALTER TABLE audit.export_request OWNER TO bridge_owner;
COMMENT ON TABLE audit.export_request IS 'User audit export jobs; the request itself is audited (audit.export.requested). owner_task=SEC-008';
CREATE INDEX export_request_status ON audit.export_request (tenant_id, status, requested_at);
ALTER TABLE audit.export_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.export_request FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON audit.export_request AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
CREATE POLICY queue_claim ON audit.export_request AS PERMISSIVE FOR SELECT TO bridge_dispatcher USING (true);
GRANT SELECT, INSERT, UPDATE ON audit.export_request TO bridge_api, bridge_worker;
GRANT SELECT (tenant_id, id, status, requested_at) ON audit.export_request TO bridge_dispatcher;

-- Partition maintenance: creates monthly partitions N months ahead. DDL needs owner rights, so it runs monthly in the
-- bridge-migrate task context (bridge_migrator as member of bridge_owner); no runtime role is granted EXECUTE.
-- Partition removal (SEC-008-S14): DETACH + DROP only for months whose events all appear in audit.event_export
-- with batches in status VERIFIED and whose upper bound is older than 365 days.
CREATE FUNCTION audit.ensure_partitions(p_months_ahead integer DEFAULT 3)
  RETURNS integer LANGUAGE plpgsql VOLATILE
  AS $$
DECLARE
  v_start date := date_trunc('month', now() AT TIME ZONE 'UTC')::date;
  v_created integer := 0;
  v_from date; v_to date; v_name text;
BEGIN
  FOR i IN 0..greatest(p_months_ahead, 1) LOOP
    v_from := (v_start + make_interval(months => i))::date;
    v_to   := (v_start + make_interval(months => i + 1))::date;
    v_name := format('event_%s', to_char(v_from, 'YYYY_MM'));
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = 'audit' AND c.relname = v_name) THEN
      EXECUTE format('CREATE TABLE audit.%I PARTITION OF audit.event FOR VALUES FROM (%L) TO (%L)',
                     v_name, v_from::timestamptz, v_to::timestamptz);
      v_created := v_created + 1;
    END IF;
  END LOOP;
  RETURN v_created;
END $$;
ALTER FUNCTION audit.ensure_partitions(integer) OWNER TO bridge_owner;

INSERT INTO app.rls_allowlist (schema_name, object_name, exception, detail, reason, owner_task) VALUES
  ('audit', 'event', 'USING_TRUE_POLICY', 'exporter_read', 'Audit exporter reads all chains (Appendix E.3 d)', 'SEC-008'),
  ('audit', 'event', 'GLOBAL_UNIQUE', 'event_pk', 'Partitioned table: PK must contain the partition key; event_id is server-generated UUIDv7', 'SEC-008'),
  ('audit', 'export_batch', 'USING_TRUE_POLICY', 'exporter_rw', 'Exporter-owned chain metadata (digests, keys; no event content)', 'SEC-008'),
  ('audit', 'export_batch', 'USING_TRUE_POLICY', 'ops_read', 'bridge-admin audit verify / retention', 'SEC-008'),
  ('audit', 'export_batch', 'GLOBAL_UNIQUE', 'export_batch_pk', 'Chain key includes the tenant id', 'SEC-008'),
  ('audit', 'export_batch', 'GLOBAL_UNIQUE', 'export_batch_id_uq', 'Server-generated batch id', 'SEC-008'),
  ('audit', 'event_export', 'USING_TRUE_POLICY', 'exporter_rw', 'Export ledger (ids only)', 'SEC-008'),
  ('audit', 'event_export', 'USING_TRUE_POLICY', 'retention_read', 'Retention verifies exported partitions', 'SEC-008'),
  ('audit', 'event_export', 'NO_TENANT_COLUMN', 'event_export', 'Ledger keyed by event id', 'SEC-008'),
  ('audit', 'export_request', 'USING_TRUE_POLICY', 'queue_claim', 'Worker claim of export jobs (column-restricted grant)', 'SEC-008');

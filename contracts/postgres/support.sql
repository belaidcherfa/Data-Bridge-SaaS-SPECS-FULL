-- contract=postgres-support version=1 status=DRAFT owner_task=SEC-104 decisions=D-02,D-22,D-25 last_changed=2026-09-28
-- Contract lane: K9 (schema file owner per contracts/README.md). Task owner: SEC-104-S01 (RECONCILIATION U-05, C-15),
-- produced from the OPS-106-S01 artifact row "support.access_grants (PG) + ops API". SEC-104's backlog names the table
-- `identity.support_access_grants`; the contracts ownership map places it in the `support` schema. The lead picks one
-- location (see contracts/_handoffs/K9.md); columns follow SEC-104-S01 exactly so either choice is a rename.
--
-- Table: support.access_grants -> support.access_grant (CONVENTIONS §2 singular).
-- State machine: contracts/state-machines/support_access.yaml (status set generated from it).
-- Rules (C-15): default duration 4 h, maximum 8 h; support scopes `health_read`, `analytics_read` only (no `config_write` in R1);
-- read-only synthetic membership kind=SUPPORT (SEC-104-S04) materialised on activation; no impersonation of a real member.

CREATE SCHEMA IF NOT EXISTS support;
COMMENT ON SCHEMA support IS 'Customer-approved, time-bound, read-only support access (SEC-104 / OPS-106). Owner lane K9.';

CREATE TABLE support.access_grant (
  tenant_id                  uuid        NOT NULL,
  id                         uuid        NOT NULL,
  status                     text        NOT NULL DEFAULT 'REQUESTED',
  operator_subject           text        NOT NULL,
  operator_role              text        NOT NULL,
  reason_code                text        NOT NULL,
  case_ref                   text        NOT NULL,
  support_scopes             text[]      NOT NULL,
  capabilities               text[]      NOT NULL,
  data_scope_json            jsonb       NULL,
  data_scope_schema_version  smallint    NULL,
  requested_at               timestamptz NOT NULL DEFAULT now(),
  request_expires_at         timestamptz NOT NULL,
  starts_at                  timestamptz NOT NULL,
  expires_at                 timestamptz NOT NULL,
  approval_mode              text        NULL,
  approved_by_membership_id  uuid        NULL,
  approved_at                timestamptz NULL,
  denied_by_membership_id    uuid        NULL,
  denied_at                  timestamptz NULL,
  activated_at               timestamptz NULL,
  support_membership_id      uuid        NULL,
  revoked_at                 timestamptz NULL,
  revoked_by                 text        NULL,
  revoke_reason_code         text        NULL,
  ended_at                   timestamptz NULL,
  created_at                 timestamptz NOT NULL DEFAULT now(),
  updated_at                 timestamptz NOT NULL DEFAULT now(),
  revision                   bigint      NOT NULL DEFAULT 1,
  CONSTRAINT access_grant_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT access_grant_status_ck CHECK (status IN ('REQUESTED','APPROVED','ACTIVE','DENIED','CANCELLED','REVOKED','EXPIRED')),
  CONSTRAINT access_grant_operator_ck CHECK (operator_subject ~ '^operator:[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT access_grant_operator_role_ck CHECK (operator_role IN ('support_agent','incident_responder')),
  CONSTRAINT access_grant_reason_ck CHECK (reason_code IN ('CUSTOMER_TICKET','INCIDENT','ONBOARDING_ASSISTANCE','DATA_HEALTH_INVESTIGATION','RECONCILIATION_INVESTIGATION')),
  CONSTRAINT access_grant_case_ck CHECK (char_length(case_ref) BETWEEN 3 AND 128),
  CONSTRAINT access_grant_scopes_ck CHECK (cardinality(support_scopes) >= 1 AND support_scopes <@ ARRAY['health_read','analytics_read']::text[]),
  CONSTRAINT access_grant_caps_ck CHECK (cardinality(capabilities) >= 1),
  CONSTRAINT access_grant_data_scope_ck CHECK ((data_scope_json IS NULL) = (data_scope_schema_version IS NULL)),
  CONSTRAINT access_grant_window_ck CHECK (expires_at > starts_at AND expires_at <= starts_at + interval '8 hours'),
  CONSTRAINT access_grant_request_window_ck CHECK (request_expires_at > requested_at AND request_expires_at <= requested_at + interval '24 hours'),
  CONSTRAINT access_grant_approval_mode_ck CHECK (approval_mode IS NULL OR approval_mode IN ('MEMBER','AUTO_POLICY_HEALTH_READ')),
  CONSTRAINT access_grant_auto_ck CHECK (approval_mode IS DISTINCT FROM 'AUTO_POLICY_HEALTH_READ' OR support_scopes = ARRAY['health_read']::text[]),
  CONSTRAINT access_grant_approved_ck CHECK (status NOT IN ('APPROVED','ACTIVE') OR (approved_at IS NOT NULL AND approval_mode IS NOT NULL
      AND (approval_mode = 'AUTO_POLICY_HEALTH_READ' OR approved_by_membership_id IS NOT NULL))),
  CONSTRAINT access_grant_active_ck CHECK (status <> 'ACTIVE' OR (activated_at IS NOT NULL AND support_membership_id IS NOT NULL)),
  CONSTRAINT access_grant_denied_ck CHECK ((status = 'DENIED') = (denied_at IS NOT NULL AND denied_by_membership_id IS NOT NULL)),
  CONSTRAINT access_grant_revoked_ck CHECK ((status = 'REVOKED') = (revoked_at IS NOT NULL AND revoked_by IS NOT NULL AND revoke_reason_code IS NOT NULL)),
  CONSTRAINT access_grant_revoker_ck CHECK (revoked_by IS NULL OR revoked_by ~ '^(member|operator|system):[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT access_grant_revoke_reason_ck CHECK (revoke_reason_code IS NULL OR revoke_reason_code IN ('CUSTOMER_REVOKED','OPERATOR_DONE','SECURITY_CONTAINMENT','TENANT_SUSPENDED','TENANT_OFFBOARDING')),
  CONSTRAINT access_grant_ended_ck CHECK (status NOT IN ('REVOKED','EXPIRED','CANCELLED') OR ended_at IS NOT NULL),
  CONSTRAINT access_grant_revision_ck CHECK (revision >= 1)
);
CREATE INDEX access_grant_tenant_status_idx ON support.access_grant (tenant_id, status, expires_at);
CREATE INDEX access_grant_operator_idx ON support.access_grant (tenant_id, operator_subject, status);
CREATE INDEX access_grant_reaper_idx ON support.access_grant (expires_at) WHERE status IN ('APPROVED','ACTIVE');
CREATE INDEX access_grant_request_reaper_idx ON support.access_grant (request_expires_at) WHERE status = 'REQUESTED';

COMMENT ON TABLE support.access_grant IS 'SEC-104-S01 (C-15, U-05). Operator requests a grant through the ops API (CTL-102 plane, bridge-admin CLI); a tenant member holding support.grant approves it (step-up), or the tenant auto-approve policy approves a health_read-only grant. On starts_at the grant becomes ACTIVE and a read-only synthetic membership kind=SUPPORT with a support profile (sanitized SQL, pseudonymous identities) is created; every request under it carries X-Bridge-Support-Session and is visible in the tenant audit. The expiry reaper ends grants at expires_at (<= starts_at + 8 h).';
COMMENT ON COLUMN support.access_grant.operator_subject IS 'x-privacy: INTERNAL. operator:<IAM Identity Center user id>; never a customer Cognito subject.';
COMMENT ON COLUMN support.access_grant.case_ref IS 'x-privacy: INTERNAL. Support ticket or incident id; no personal data.';
COMMENT ON COLUMN support.access_grant.support_scopes IS 'R1 scopes: health_read (Data Health, coverage, batch/reconciliation diagnostics) and analytics_read (tenant analytics under the support profile). config_write is not a support scope in R1 (C-15).';
COMMENT ON COLUMN support.access_grant.capabilities IS 'Materialized read-only capability set derived from support_scopes (contracts/authz/capabilities.yaml ids, K2); never contains a mutation capability.';
COMMENT ON COLUMN support.access_grant.data_scope_json IS 'Optional SEC-101 scope clause restricting the grant inside the tenant (NULL = whole tenant). Validated by contracts/authz/scope.schema.json version data_scope_schema_version.';
COMMENT ON COLUMN support.access_grant.approved_by_membership_id IS 'Membership (identity schema, K2) of the approving tenant member; cross-lane reference without FK.';
COMMENT ON COLUMN support.access_grant.support_membership_id IS 'Synthetic membership kind=SUPPORT created by SEC-104-S04 on activation and removed at end.';

ALTER TABLE support.access_grant ENABLE ROW LEVEL SECURITY;
ALTER TABLE support.access_grant FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON support.access_grant
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
-- Allowlisted cross-tenant reader: the expiry reaper (bridge_retention) ends grants of every tenant.
CREATE POLICY access_grant_reaper ON support.access_grant FOR SELECT TO bridge_retention USING (true);
CREATE POLICY access_grant_reaper_update ON support.access_grant FOR UPDATE TO bridge_retention
  USING (status IN ('REQUESTED','APPROVED','ACTIVE'))
  WITH CHECK (status IN ('ACTIVE','EXPIRED','CANCELLED'));

REVOKE ALL ON ALL TABLES IN SCHEMA support FROM PUBLIC;
GRANT USAGE ON SCHEMA support TO bridge_api, bridge_ops_api, bridge_retention, bridge_worker;
GRANT SELECT, UPDATE ON support.access_grant TO bridge_api;
GRANT SELECT, INSERT, UPDATE ON support.access_grant TO bridge_ops_api;
GRANT SELECT, UPDATE ON support.access_grant TO bridge_retention, bridge_worker;

-- contract=pg-tenant version=1 status=DRAFT owner_task=CTL-102 decisions=D-02,D-10,D-17,D-23,D-25 last_changed=2026-09-28
-- =====================================================================================================
-- Schema `tenant`: tenant-level configuration and lifecycle records. The tenant ROOT row is identity.tenant
-- (SEC-004-S01, referenced by resolve_session()); this schema holds everything the tenant configures or the
-- operator plane records about it:
--   tenant.setting                  security/session/privacy/support policy (relational, no free-form JSON; SEC-002-S08,
--                                   SEC-003, SEC-007-S11, SEC-104-S03, API-005-S06 disclosure switch)
--   tenant.approval_policy_override tenant overrides of four-eyes defaults within allowed values (SEC-102-S02)
--   tenant.lifecycle_transition     append-only history of tenant state transitions (CTL-102-S01/S08)
--   tenant.provisioning_request     operator provisioning requests, idempotent (CTL-102-S03)
--   tenant.serving_principal        PG view of the Snowflake tenant principal state reported by SEC-105 (CTL-102-S04)
-- Apply after identity.sql. Lifecycle machine: contracts/state-machines/tenant.yaml.
-- =====================================================================================================

CREATE SCHEMA tenant AUTHORIZATION bridge_owner;
COMMENT ON SCHEMA tenant IS 'Tenant configuration, lifecycle history and provisioning records. owner_task=CTL-102';
GRANT USAGE ON SCHEMA tenant TO bridge_api, bridge_worker, bridge_definer, bridge_ops_ro;

-- -----------------------------------------------------------------------------------------------------
-- tenant.setting - one row per tenant, created in the provisioning transaction.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE tenant.setting (
  tenant_id                          uuid        NOT NULL,
  id                                 uuid        NOT NULL,
  -- sessions (SEC-002-S08; Q4 defaults 30 min idle / 12 h absolute; bounds 15-120 min / 1-24 h)
  session_idle_timeout_minutes       integer     NOT NULL DEFAULT 30 CHECK (session_idle_timeout_minutes BETWEEN 15 AND 120),
  session_absolute_timeout_hours     integer     NOT NULL DEFAULT 12 CHECK (session_absolute_timeout_hours BETWEEN 1 AND 24),
  -- MFA (G-SEC-07): local users always require MFA; the flag records the policy explicitly and cannot be false
  local_mfa_required                 boolean     NOT NULL DEFAULT true CHECK (local_mfa_required),
  step_up_max_age_seconds            integer     NOT NULL DEFAULT 600 CHECK (step_up_max_age_seconds BETWEEN 60 AND 600),
  -- SSO (SEC-003): enforcement is identity.identity_provider.status = ENFORCED; this caches it for resolve_session()
  sso_enforced_identity_provider_id  uuid        NULL,
  -- privacy (ADR-009 amendment, SEC-007): FULL requires an executed approval of action privacy.mode.full.enable
  privacy_mode                       text        NOT NULL DEFAULT 'SANITIZED' CHECK (privacy_mode IN ('SANITIZED', 'METADATA_ONLY', 'FULL')),
  privacy_full_approval_id           uuid        NULL,
  sanitizer_lexical_tier_enabled     boolean     NOT NULL DEFAULT true,   -- SEC-007-S02 (tenant may disable)
  hot_days                           integer     NOT NULL DEFAULT 365 CHECK (hot_days BETWEEN 1 AND 365),   -- D-11, plan-configurable
  -- support access (SEC-104-S03, C-15)
  support_health_read_auto_approve   boolean     NOT NULL DEFAULT false,
  support_default_duration_minutes   integer     NOT NULL DEFAULT 240 CHECK (support_default_duration_minutes BETWEEN 15 AND 480),
  -- analytics disclosure switches
  explain_disclose_allocation_denominators boolean NOT NULL DEFAULT false,  -- API-005-S06
  report_external_recipients_allowed boolean     NOT NULL DEFAULT false,    -- RPT R2; capability report.recipients.external still required
  high_sensitivity                   boolean     NOT NULL DEFAULT false,    -- RPT G-RPT-07 brokered-stream downloads
  -- invitations
  invitation_ttl_days                integer     NOT NULL DEFAULT 7 CHECK (invitation_ttl_days BETWEEN 1 AND 14),
  -- presentation defaults (D-18)
  default_locale                     text        NOT NULL DEFAULT 'en' CHECK (default_locale ~ '^[a-z]{2}(-[A-Z]{2})?$'),
  default_display_timezone           text        NOT NULL DEFAULT 'UTC' CHECK (char_length(default_display_timezone) BETWEEN 1 AND 64),  -- IANA name
  created_at                         timestamptz NOT NULL DEFAULT now(),
  updated_at                         timestamptz NOT NULL DEFAULT now(),
  updated_by                         uuid        NULL,
  revision                           bigint      NOT NULL DEFAULT 1,
  CONSTRAINT setting_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT setting_tenant_uq UNIQUE (tenant_id),
  CONSTRAINT setting_tenant_fk FOREIGN KEY (tenant_id) REFERENCES identity.tenant (id),
  CONSTRAINT setting_sso_idp_fk FOREIGN KEY (tenant_id, sso_enforced_identity_provider_id) REFERENCES identity.identity_provider (tenant_id, id),
  CONSTRAINT setting_privacy_full_approval_fk FOREIGN KEY (tenant_id, privacy_full_approval_id) REFERENCES identity.approval (tenant_id, id),
  CONSTRAINT setting_privacy_full_requires_approval CHECK (privacy_mode <> 'FULL' OR privacy_full_approval_id IS NOT NULL)
);
ALTER TABLE tenant.setting OWNER TO bridge_owner;
COMMENT ON TABLE tenant.setting IS 'Tenant policy. Changing privacy_mode bumps identity.tenant.authz_epoch and emits bridge.auth.authz_epoch.bumped (SEC-006-S03). Mutations need security.policy.manage / privacy.mode.manage (step-up). owner_task=CTL-102';

-- -----------------------------------------------------------------------------------------------------
-- tenant.approval_policy_override - tenant relaxations/tightenings of approval_policies within
-- tenant_overridable ranges declared in contracts/authz/capabilities.yaml (e.g. close can never be NONE).
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE tenant.approval_policy_override (
  tenant_id              uuid        NOT NULL,
  id                     uuid        NOT NULL,
  action                 text        NOT NULL CHECK (action ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  four_eyes              text        NOT NULL CHECK (four_eyes IN ('REQUIRED', 'REQUIRED_WITH_FLAGGED_SELF_APPROVAL', 'NONE')),
  owner_acknowledged_by  uuid        NOT NULL,          -- Organization Owner subject who acknowledged (FIN Q3)
  owner_acknowledged_at  timestamptz NOT NULL,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  updated_by             uuid        NULL,
  revision               bigint      NOT NULL DEFAULT 1,
  CONSTRAINT approval_policy_override_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT approval_policy_override_tenant_fk FOREIGN KEY (tenant_id) REFERENCES identity.tenant (id),
  CONSTRAINT approval_policy_override_action_uq UNIQUE (tenant_id, action)
);
ALTER TABLE tenant.approval_policy_override OWNER TO bridge_owner;
COMMENT ON TABLE tenant.approval_policy_override IS 'Allowed values per action are validated by the service against capabilities.yaml approval_policies.<action>.tenant_overridable; a value outside the range is rejected with 422 AUTHZ_APPROVAL_POLICY_NOT_OVERRIDABLE. owner_task=SEC-102';

-- -----------------------------------------------------------------------------------------------------
-- tenant.lifecycle_transition - append-only transition log (tenant.yaml). Written in the same transaction as
-- the identity.tenant status update, with audit and outbox.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE tenant.lifecycle_transition (
  tenant_id            uuid        NOT NULL,
  id                   uuid        NOT NULL,
  from_status          text        NULL CHECK (from_status IS NULL OR from_status IN ('PROVISIONING', 'ACTIVE', 'SUSPENDED', 'OFFBOARDING', 'DELETED')),
  to_status            text        NOT NULL CHECK (to_status IN ('PROVISIONING', 'ACTIVE', 'SUSPENDED', 'OFFBOARDING', 'DELETED')),
  event                text        NOT NULL CHECK (event ~ '^[a-z][a-z_]{2,62}$'),   -- event name from tenant.yaml
  actor_type           text        NOT NULL CHECK (actor_type IN ('OPERATOR', 'SYSTEM', 'MEMBER')),
  actor_subject_id     uuid        NULL,
  actor_component      text        NULL,                -- system:<component>
  reason_code          text        NULL CHECK (reason_code IS NULL OR reason_code IN ('SECURITY_INCIDENT', 'COMMERCIAL', 'CUSTOMER_REQUEST', 'OPERATIONAL', 'PRINCIPAL_ACTIVE', 'DELETION_CERTIFIED', 'PROVISIONING_ABANDONED')),
  case_ref             text        NULL,
  approval_ref         text        NULL,                -- second-operator approval id for OFFBOARDING/DELETED (OPS-005)
  request_id           text        NOT NULL,
  occurred_at          timestamptz NOT NULL DEFAULT now(),
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  revision             bigint      NOT NULL DEFAULT 1,
  CONSTRAINT lifecycle_transition_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT lifecycle_transition_tenant_fk FOREIGN KEY (tenant_id) REFERENCES identity.tenant (id),
  CONSTRAINT lifecycle_transition_actor CHECK ((actor_type = 'SYSTEM') = (actor_component IS NOT NULL) AND (actor_type = 'SYSTEM' OR actor_subject_id IS NOT NULL))
);
ALTER TABLE tenant.lifecycle_transition OWNER TO bridge_owner;
COMMENT ON TABLE tenant.lifecycle_transition IS 'Append-only tenant lifecycle history (UPDATE/DELETE not granted). owner_task=CTL-102';
CREATE INDEX lifecycle_transition_tenant_time ON tenant.lifecycle_transition (tenant_id, occurred_at DESC);

-- -----------------------------------------------------------------------------------------------------
-- tenant.provisioning_request - operator request to create a tenant (CTL-102-S03). Idempotent on
-- (operator, idempotency key). The row is inserted in the provisioning transaction together with
-- identity.tenant (PROVISIONING), tenant.setting, the bootstrap invitation, audit and the outbox event
-- bridge.tenancy.principal.requested.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE tenant.provisioning_request (
  tenant_id                 uuid        NOT NULL,
  id                        uuid        NOT NULL,
  operator_subject_id       uuid        NOT NULL,
  idempotency_key           text        NOT NULL CHECK (idempotency_key ~ '^[A-Za-z0-9_-]{16,128}$'),
  request_sha256            text        NOT NULL CHECK (request_sha256 ~ '^[0-9a-f]{64}$'),
  slug                      text        NOT NULL,
  display_name              text        NOT NULL,
  first_owner_email_norm    text        NOT NULL,
  contract_ref              text        NULL,           -- order form / pilot reference (ONB-003, LCH-001)
  reason_code               text        NOT NULL CHECK (reason_code IN ('NEW_CUSTOMER', 'PILOT', 'INTERNAL_TEST', 'DEMO')),
  case_ref                  text        NULL,
  bootstrap_invitation_id   uuid        NULL,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  revision                  bigint      NOT NULL DEFAULT 1,
  CONSTRAINT provisioning_request_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT provisioning_request_tenant_fk FOREIGN KEY (tenant_id) REFERENCES identity.tenant (id),
  CONSTRAINT provisioning_request_idem_uq UNIQUE (operator_subject_id, idempotency_key),
  CONSTRAINT provisioning_request_invitation_fk FOREIGN KEY (tenant_id, bootstrap_invitation_id) REFERENCES identity.invitation (tenant_id, id)
);
ALTER TABLE tenant.provisioning_request OWNER TO bridge_owner;
COMMENT ON TABLE tenant.provisioning_request IS 'Operator provisioning audit record; same (operator, key) + same hash -> replay; different hash -> 409 IDEMPOTENCY_KEY_REUSED. owner_task=CTL-102';
COMMENT ON COLUMN tenant.provisioning_request.first_owner_email_norm IS 'x-privacy: PERSONAL';
COMMENT ON COLUMN tenant.provisioning_request.display_name IS 'x-privacy: CUSTOMER_METADATA';

-- -----------------------------------------------------------------------------------------------------
-- tenant.serving_principal - PG record of the tenant serving identity (ADR-005 amendment A.1): IAM role from
-- INF-103, Snowflake user from SEC-105 TENANT_ONBOARDER. Source of truth for the user->tenant binding is
-- Snowflake SECURITY.TENANT_PRINCIPAL; this row drives CTL-102 activation and nightly drift reconciliation.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE tenant.serving_principal (
  tenant_id            uuid        NOT NULL,
  id                   uuid        NOT NULL,
  snowflake_user       text        NOT NULL CHECK (snowflake_user ~ '^BRIDGE_(DEV|STAGING|PROD)_T_[A-Z2-7]{12}$'),
  aws_role_arn         text        NULL CHECK (aws_role_arn IS NULL OR aws_role_arn ~ '^arn:aws:iam::[0-9]{12}:role/bridge-(dev|staging|prod)-srv-[0-9a-f]{32}$'),
  status               text        NOT NULL DEFAULT 'REQUESTED' CHECK (status IN ('REQUESTED', 'IAM_READY', 'ACTIVE', 'FAILED', 'DISABLED')),
  attempts             integer     NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  last_error_class     text        NULL,
  requested_at         timestamptz NOT NULL DEFAULT now(),
  activated_at         timestamptz NULL,
  disabled_at          timestamptz NULL,
  last_drift_check_at  timestamptz NULL,
  drift_status         text        NULL CHECK (drift_status IS NULL OR drift_status IN ('IN_SYNC', 'DRIFT_DETECTED')),
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  revision             bigint      NOT NULL DEFAULT 1,
  CONSTRAINT serving_principal_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT serving_principal_tenant_uq UNIQUE (tenant_id),
  CONSTRAINT serving_principal_tenant_fk FOREIGN KEY (tenant_id) REFERENCES identity.tenant (id),
  CONSTRAINT serving_principal_user_uq UNIQUE (snowflake_user),
  CONSTRAINT serving_principal_active_consistency CHECK (status <> 'ACTIVE' OR (activated_at IS NOT NULL AND aws_role_arn IS NOT NULL))
);
ALTER TABLE tenant.serving_principal OWNER TO bridge_owner;
COMMENT ON TABLE tenant.serving_principal IS 'Tenant serving principal state (IAM role bridge-<env>-srv-<uuid32>, Snowflake TYPE=SERVICE user). owner_task=SEC-105';

-- -----------------------------------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------------------------------
ALTER TABLE tenant.setting ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant.setting FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON tenant.setting AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
CREATE POLICY definer_access ON tenant.setting AS PERMISSIVE FOR SELECT TO bridge_definer USING (true);
GRANT SELECT, INSERT, UPDATE ON tenant.setting TO bridge_api;
GRANT SELECT ON tenant.setting TO bridge_worker, bridge_definer;

ALTER TABLE tenant.approval_policy_override ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant.approval_policy_override FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON tenant.approval_policy_override AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
GRANT SELECT, INSERT, UPDATE, DELETE ON tenant.approval_policy_override TO bridge_api;
GRANT SELECT ON tenant.approval_policy_override TO bridge_worker;

ALTER TABLE tenant.lifecycle_transition ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant.lifecycle_transition FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON tenant.lifecycle_transition AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
GRANT SELECT, INSERT ON tenant.lifecycle_transition TO bridge_api, bridge_worker;

ALTER TABLE tenant.provisioning_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant.provisioning_request FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON tenant.provisioning_request AS PERMISSIVE FOR ALL TO bridge_api
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
CREATE POLICY definer_access ON tenant.provisioning_request AS PERMISSIVE FOR SELECT TO bridge_definer USING (true);
GRANT SELECT, INSERT ON tenant.provisioning_request TO bridge_api;
GRANT SELECT ON tenant.provisioning_request TO bridge_definer;

ALTER TABLE tenant.serving_principal ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant.serving_principal FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON tenant.serving_principal AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
CREATE POLICY ops_read ON tenant.serving_principal AS PERMISSIVE FOR SELECT TO bridge_ops_ro USING (true);
GRANT SELECT, INSERT ON tenant.serving_principal TO bridge_api;
GRANT SELECT, INSERT, UPDATE ON tenant.serving_principal TO bridge_worker;
GRANT SELECT ON tenant.serving_principal TO bridge_ops_ro;

-- Idempotent operator retry needs lookup by (operator, key) before the tenant id is known.
CREATE FUNCTION tenant.find_provisioning_request(p_operator_subject_id uuid, p_idempotency_key text)
  RETURNS TABLE (tenant_id uuid, provisioning_request_id uuid, request_sha256 text)
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  SELECT r.tenant_id, r.id, r.request_sha256
    FROM tenant.provisioning_request r
   WHERE r.operator_subject_id = p_operator_subject_id AND r.idempotency_key = p_idempotency_key
$$;
ALTER FUNCTION tenant.find_provisioning_request(uuid, text) OWNER TO bridge_definer;
REVOKE ALL ON FUNCTION tenant.find_provisioning_request(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION tenant.find_provisioning_request(uuid, text) TO bridge_api;

INSERT INTO app.rls_allowlist (schema_name, object_name, exception, detail, reason, owner_task) VALUES
  ('tenant', 'setting', 'USING_TRUE_POLICY', 'definer_access', 'identity.resolve_session() returns session timeouts and SSO enforcement', 'SEC-002'),
  ('tenant', 'provisioning_request', 'USING_TRUE_POLICY', 'definer_access', 'tenant.find_provisioning_request() idempotent operator retry', 'CTL-102'),
  ('tenant', 'provisioning_request', 'GLOBAL_UNIQUE', 'provisioning_request_idem_uq', 'Operator-scoped idempotency key; operators are not tenant users', 'CTL-102'),
  ('tenant', 'serving_principal', 'USING_TRUE_POLICY', 'ops_read', 'Operator drift dashboards (IDs and status only)', 'SEC-105'),
  ('tenant', 'serving_principal', 'GLOBAL_UNIQUE', 'serving_principal_user_uq', 'One Snowflake user per tenant, derived from tenant short code', 'SEC-105'),
  ('tenant', 'find_provisioning_request', 'SECURITY_DEFINER', 'tenant.find_provisioning_request(uuid,text)', 'Lookup by operator idempotency key before tenant context exists', 'CTL-102');

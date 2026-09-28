-- contract=pg-identity version=1 status=DRAFT owner_task=SEC-004 decisions=D-02,D-10,D-17,D-20,D-25 last_changed=2026-09-28
-- =====================================================================================================
-- Schema `identity` (core): subjects, tenants, memberships, grants, permission profiles, teams, identity
-- providers, federated identities, invitations, approvals, support-access grants, machine clients.
-- Sessions/auth transactions and the SECURITY DEFINER resolvers are in identity.auth.sql.
--
-- Normative sources: SEC backlog Appendix B (scope grammar), C (capabilities, delegation, approvals),
-- D.2 (sessions), E (RLS), SEC-004-S01, SEC-003-S01, SEC-102-S01, SEC-104-S01, CTL-003-S04, CTL-003 Appendix E.
-- Status CHECK sets are generated from contracts/state-machines/{membership,invitation,approval,
-- permission_profile,identity_provider}.yaml (support_access_grant statuses: K9 machine `support_access`,
-- see contracts/_handoffs/K2.md).
--
-- Naming (CONVENTIONS §10 singular nouns; backlog names in brackets):
--   identity.subject [subjects], identity.tenant [tenants], identity.membership [memberships],
--   identity.role_grant [grants / role_grants; `grant` is a reserved word], identity.grant_clause [grant_clauses],
--   identity.permission_profile [permission_profiles], identity.team [teams], identity.team_member [team_members],
--   identity.identity_provider [identity_providers], identity.idp_domain [idp_domains],
--   identity.subject_identity [subject_identities], identity.invitation [invitations],
--   identity.approval [governance.approvals, SEC-102-S01 - placed in identity because governance.* is K7's file],
--   identity.support_access_grant [support_access_grants], identity.machine_client [API-006-S01, owner_task API-006].
-- Membership has no INVITED state: an invitation is identity.invitation; the membership row is created at
-- acceptance (bootstrap owner included, via a bootstrap invitation). Refines SEC-004-S01.
-- =====================================================================================================

CREATE SCHEMA identity AUTHORIZATION bridge_owner;
COMMENT ON SCHEMA identity IS 'Subjects, tenants, memberships, grants, profiles, SSO, invitations, approvals, sessions. owner_task=SEC-004';
GRANT USAGE ON SCHEMA identity TO bridge_api, bridge_worker, bridge_broker, bridge_definer, bridge_audit_exporter;

-- -----------------------------------------------------------------------------------------------------
-- identity.subject - global human/operator identity (not tenant-owned). Exposed only through scoped joins.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE identity.subject (
  id                        uuid        NOT NULL,
  issuer                    text        NOT NULL CHECK (issuer ~ '^https://[a-z0-9.-]+(/[A-Za-z0-9._~-]+)*$'),  -- Cognito pool issuer or internal operator IdP
  cognito_sub               text        NOT NULL CHECK (char_length(cognito_sub) BETWEEN 1 AND 128),  -- `sub` claim of the issuer
  subject_kind              text        NOT NULL DEFAULT 'CUSTOMER_USER' CHECK (subject_kind IN ('CUSTOMER_USER', 'OPERATOR')),
  email_norm                text        NULL CHECK (email_norm IS NULL OR (email_norm = lower(email_norm) AND char_length(email_norm) <= 320)),
  email_verified            boolean     NOT NULL DEFAULT false,
  display_name              text        NULL CHECK (display_name IS NULL OR char_length(display_name) <= 200),
  status                    text        NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'DISABLED', 'ERASED')),
  mfa_reset_cooldown_until  timestamptz NULL,        -- SEC-002-S13: 24 h cool-down after an approved MFA reset
  last_login_at             timestamptz NULL,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  revision                  bigint      NOT NULL DEFAULT 1,
  CONSTRAINT subject_pk PRIMARY KEY (id),
  CONSTRAINT subject_issuer_sub_uq UNIQUE (issuer, cognito_sub),
  CONSTRAINT subject_erased_has_no_pii CHECK (status <> 'ERASED' OR (email_norm IS NULL AND display_name IS NULL))
);
ALTER TABLE identity.subject OWNER TO bridge_owner;
COMMENT ON TABLE identity.subject IS 'Global subject: one per (issuer, sub). Federated identities map through identity.subject_identity; email equality never links identities (G-SEC-09). owner_task=SEC-004';
COMMENT ON COLUMN identity.subject.email_norm IS 'NFKC + casefold; updated only from verified sources (SEC-002-S06). x-privacy: PERSONAL';
COMMENT ON COLUMN identity.subject.display_name IS 'x-privacy: PERSONAL';
COMMENT ON COLUMN identity.subject.cognito_sub IS 'x-privacy: INTERNAL (identifier)';
CREATE INDEX subject_email_norm ON identity.subject (email_norm) WHERE email_norm IS NOT NULL;

-- -----------------------------------------------------------------------------------------------------
-- identity.tenant - tenant root (global table; the row's own id is the tenant key). Lifecycle:
-- contracts/state-machines/tenant.yaml (CTL-102). authz_epoch = tenant data-visibility epoch (Appendix F).
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE identity.tenant (
  id                       uuid        NOT NULL,
  slug                     text        NOT NULL CHECK (slug ~ '^[a-z0-9](?:[a-z0-9-]{1,38}[a-z0-9])$'),
  short_code               text        NOT NULL CHECK (short_code ~ '^[A-Z2-7]{12}$'),   -- first 12 chars of base32(tenant uuid bytes); Snowflake TENANT_SHORT
  display_name             text        NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 200),
  status                   text        NOT NULL DEFAULT 'PROVISIONING'
                           CHECK (status IN ('PROVISIONING', 'ACTIVE', 'SUSPENDED', 'OFFBOARDING', 'DELETED')),
  suspension_reason        text        NULL CHECK (suspension_reason IS NULL OR suspension_reason IN ('SECURITY_INCIDENT', 'COMMERCIAL', 'CUSTOMER_REQUEST', 'OPERATIONAL')),
  authz_epoch              bigint      NOT NULL DEFAULT 1 CHECK (authz_epoch >= 1),
  processing_region        text        NOT NULL DEFAULT 'eu-west-1' CHECK (processing_region ~ '^[a-z]{2}-[a-z]+-[0-9]$'),  -- D-23
  is_synthetic             boolean     NOT NULL DEFAULT false,   -- demo/test tenant (LCH G-LCH-03); never satisfies M12
  created_at               timestamptz NOT NULL DEFAULT now(),
  activated_at             timestamptz NULL,
  suspended_at             timestamptz NULL,
  offboarding_started_at   timestamptz NULL,
  deleted_at               timestamptz NULL,
  updated_at               timestamptz NOT NULL DEFAULT now(),
  updated_by               uuid        NULL,             -- subject (customer or operator)
  revision                 bigint      NOT NULL DEFAULT 1,
  CONSTRAINT tenant_pk PRIMARY KEY (id),
  CONSTRAINT tenant_slug_uq UNIQUE (slug),
  CONSTRAINT tenant_short_code_uq UNIQUE (short_code),
  CONSTRAINT tenant_suspension_consistency CHECK ((status = 'SUSPENDED') = (suspended_at IS NOT NULL AND suspension_reason IS NOT NULL)),
  CONSTRAINT tenant_deleted_consistency CHECK ((status = 'DELETED') = (deleted_at IS NOT NULL))
);
ALTER TABLE identity.tenant OWNER TO bridge_owner;
COMMENT ON TABLE identity.tenant IS 'Tenant root. Created only by the operator provisioning transaction (CTL-102-S03, SEC-004-S07). Never physically deleted before OPS-005 certifies deletion; the TENANT tombstone lives in OPS-104. owner_task=SEC-004';
COMMENT ON COLUMN identity.tenant.display_name IS 'x-privacy: CUSTOMER_METADATA';
COMMENT ON COLUMN identity.tenant.authz_epoch IS 'Bumped only by data-visibility events: profile retirement, privacy-mode change, access-relevant group-set publication, subject erasure (Appendix F, D-10). Part of cache keys (CTL-006) and cursor/job bindings.';

-- -----------------------------------------------------------------------------------------------------
-- identity.permission_profile - immutable, content-addressed normalized profile (ADR-005 amendment, Appendix B.2).
-- Snowflake mirror: SECURITY.PROFILE / PROFILE_ENTITLEMENT (SEC-105). Lifecycle: permission_profile.yaml.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE identity.permission_profile (
  tenant_id                 uuid        NOT NULL,
  id                        uuid        NOT NULL,
  profile_hash              text        NOT NULL CHECK (profile_hash ~ '^pf1:[0-9a-f]{64}$'),
  grammar_version           smallint    NOT NULL DEFAULT 1 CHECK (grammar_version = 1),
  sql_text_access           text        NOT NULL CHECK (sql_text_access IN ('NONE', 'SANITIZED', 'FULL')),
  canonical_json            jsonb       NOT NULL,        -- contracts/authz/profile-canonical.schema.json (RFC 8785 serialized for hashing)
  canonical_schema_version  smallint    NOT NULL DEFAULT 1,
  atom_count                integer     NOT NULL CHECK (atom_count BETWEEN 0 AND 2000),
  role_name                 text        NOT NULL CHECK (role_name ~ '^BRIDGE_(DEV|STAGING|PROD)_T_[A-Z2-7]{12}_P_[0-9A-F]{16}$'),
  status                    text        NOT NULL DEFAULT 'PROVISIONING'
                            CHECK (status IN ('PROVISIONING', 'ACTIVE', 'FAILED', 'RETIRING', 'RETIRED')),
  provision_attempts        integer     NOT NULL DEFAULT 0 CHECK (provision_attempts >= 0),
  last_error_class          text        NULL,
  activated_at              timestamptz NULL,
  last_referenced_at        timestamptz NOT NULL DEFAULT now(),   -- GC: unreferenced > 15 min -> RETIRING; > 24 h -> RETIRED (DROP ROLE)
  retiring_at               timestamptz NULL,
  retired_at                timestamptz NULL,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  revision                  bigint      NOT NULL DEFAULT 1,
  CONSTRAINT permission_profile_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT permission_profile_tenant_fk FOREIGN KEY (tenant_id) REFERENCES identity.tenant (id),
  CONSTRAINT permission_profile_hash_uq UNIQUE (tenant_id, profile_hash),
  CONSTRAINT permission_profile_role_uq UNIQUE (tenant_id, role_name),
  CONSTRAINT permission_profile_active_consistency CHECK (status NOT IN ('ACTIVE', 'RETIRING', 'RETIRED') OR activated_at IS NOT NULL)
);
ALTER TABLE identity.permission_profile OWNER TO bridge_owner;
COMMENT ON TABLE identity.permission_profile IS 'Content-addressed profile; content columns immutable (trigger). Admission cap: 200 profiles in PROVISIONING|ACTIVE|RETIRING per tenant (AUTHZ_PROFILE_QUOTA_EXCEEDED). owner_task=SEC-004';
COMMENT ON COLUMN identity.permission_profile.canonical_json IS 'Canonical atoms (organization/account/group-set/group UUIDs and flags). x-privacy: CUSTOMER_METADATA';
CREATE INDEX permission_profile_status ON identity.permission_profile (tenant_id, status, last_referenced_at);

CREATE FUNCTION identity.forbid_profile_content_update() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.tenant_id <> OLD.tenant_id OR NEW.id <> OLD.id OR NEW.profile_hash <> OLD.profile_hash
     OR NEW.grammar_version <> OLD.grammar_version OR NEW.sql_text_access <> OLD.sql_text_access
     OR NEW.canonical_json <> OLD.canonical_json OR NEW.atom_count <> OLD.atom_count OR NEW.role_name <> OLD.role_name THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'PROFILE_CONTENT_IMMUTABLE';
  END IF;
  RETURN NEW;
END $$;
ALTER FUNCTION identity.forbid_profile_content_update() OWNER TO bridge_owner;
CREATE TRIGGER permission_profile_immutable BEFORE UPDATE ON identity.permission_profile
  FOR EACH ROW EXECUTE FUNCTION identity.forbid_profile_content_update();

-- -----------------------------------------------------------------------------------------------------
-- identity.membership - subject x tenant. Lifecycle: membership.yaml. permission_epoch = per-member epoch.
-- profile_id = ACTIVE profile in use; pending_profile_id = broadening target still PROVISIONING (Appendix A.5).
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE identity.membership (
  tenant_id               uuid        NOT NULL,
  id                      uuid        NOT NULL,
  subject_id              uuid        NOT NULL,
  kind                    text        NOT NULL DEFAULT 'MEMBER' CHECK (kind IN ('MEMBER', 'SUPPORT')),
  status                  text        NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED', 'REMOVED')),
  permission_epoch        bigint      NOT NULL DEFAULT 1 CHECK (permission_epoch >= 1),
  profile_id              uuid        NULL,           -- NULL = no analytical access (fail closed, 503 AUTHZ_ACCESS_UPDATING)
  pending_profile_id      uuid        NULL,
  is_break_glass_owner    boolean     NOT NULL DEFAULT false,   -- SEC-003-S10 (max 2 per tenant, passkey MFA required)
  joined_via              text        NOT NULL CHECK (joined_via IN ('INVITATION', 'BOOTSTRAP_INVITATION', 'SSO_JIT', 'SUPPORT_GRANT')),
  invitation_id           uuid        NULL,
  support_access_grant_id uuid        NULL,
  joined_at               timestamptz NOT NULL DEFAULT now(),
  suspended_at            timestamptz NULL,
  removed_at              timestamptz NULL,
  removed_reason          text        NULL CHECK (removed_reason IS NULL OR removed_reason IN ('REMOVED_BY_ADMIN', 'SELF_LEAVE', 'SUPPORT_EXPIRED', 'SUPPORT_REVOKED', 'TENANT_OFFBOARDED', 'SUBJECT_ERASED')),
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  updated_by              uuid        NULL,
  revision                bigint      NOT NULL DEFAULT 1,
  CONSTRAINT membership_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT membership_tenant_fk FOREIGN KEY (tenant_id) REFERENCES identity.tenant (id),
  CONSTRAINT membership_subject_fk FOREIGN KEY (subject_id) REFERENCES identity.subject (id),
  CONSTRAINT membership_tenant_subject_uq UNIQUE (tenant_id, subject_id),
  CONSTRAINT membership_profile_fk FOREIGN KEY (tenant_id, profile_id) REFERENCES identity.permission_profile (tenant_id, id),
  CONSTRAINT membership_pending_profile_fk FOREIGN KEY (tenant_id, pending_profile_id) REFERENCES identity.permission_profile (tenant_id, id),
  CONSTRAINT membership_support_consistency CHECK ((kind = 'SUPPORT') = (support_access_grant_id IS NOT NULL) AND (kind = 'SUPPORT') = (joined_via = 'SUPPORT_GRANT')),
  CONSTRAINT membership_break_glass_member_only CHECK (NOT is_break_glass_owner OR kind = 'MEMBER'),
  CONSTRAINT membership_removed_consistency CHECK ((status = 'REMOVED') = (removed_at IS NOT NULL AND removed_reason IS NOT NULL)),
  CONSTRAINT membership_suspended_consistency CHECK ((status = 'SUSPENDED') = (suspended_at IS NOT NULL))
);
ALTER TABLE identity.membership OWNER TO bridge_owner;
COMMENT ON TABLE identity.membership IS 'Tenant membership. Every grant/membership/status change bumps permission_epoch (UPDATE ... RETURNING) and emits bridge.auth.membership.changed in the same transaction (SEC-004-S09). owner_task=SEC-004';
CREATE INDEX membership_subject ON identity.membership (subject_id, status);
CREATE INDEX membership_tenant_status ON identity.membership (tenant_id, status, kind);
CREATE INDEX membership_profile ON identity.membership (tenant_id, profile_id) WHERE profile_id IS NOT NULL;
CREATE INDEX membership_pending_profile ON identity.membership (tenant_id, pending_profile_id) WHERE pending_profile_id IS NOT NULL;
CREATE INDEX membership_break_glass ON identity.membership (tenant_id) WHERE is_break_glass_owner;  -- count <= 2 per tenant enforced by service (SELECT ... FOR UPDATE) + test

-- -----------------------------------------------------------------------------------------------------
-- identity.role_grant - one row per (membership, role): one of the 8 PRD roles + grantable extras + scope clauses.
-- A member's capability set = union over grants; authorize(ctx, cap) = union of clauses of grants carrying cap.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE identity.role_grant (
  tenant_id              uuid        NOT NULL,
  id                     uuid        NOT NULL,
  membership_id          uuid        NOT NULL,
  role                   text        NOT NULL CHECK (role IN ('ORGANIZATION_OWNER', 'ORGANIZATION_ADMIN', 'FINOPS_ADMIN', 'SNOWFLAKE_ADMIN',
                                                               'TEAM_ADMIN', 'ANALYST', 'VIEWER', 'AUDITOR', 'SUPPORT_READ_ONLY')),
  extra_capabilities     text[]      NOT NULL DEFAULT '{}' CHECK (cardinality(extra_capabilities) <= 64),  -- ids from contracts/authz/capabilities.yaml with grantable roles
  grammar_version        smallint    NOT NULL DEFAULT 1 CHECK (grammar_version = 1),
  scope_sha256           text        NOT NULL CHECK (scope_sha256 ~ '^[0-9a-f]{64}$'),   -- sha256(JCS(normalized clause list of this grant))
  granted_by_membership_id uuid      NULL,           -- NULL for bootstrap/operator/support grants
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  updated_by             uuid        NULL,
  revision               bigint      NOT NULL DEFAULT 1,
  CONSTRAINT role_grant_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT role_grant_membership_fk FOREIGN KEY (tenant_id, membership_id) REFERENCES identity.membership (tenant_id, id),
  CONSTRAINT role_grant_granted_by_fk FOREIGN KEY (tenant_id, granted_by_membership_id) REFERENCES identity.membership (tenant_id, id),
  CONSTRAINT role_grant_membership_role_uq UNIQUE (tenant_id, membership_id, role),
  CONSTRAINT role_grant_no_self_grant CHECK (granted_by_membership_id IS NULL OR granted_by_membership_id <> membership_id)
);
ALTER TABLE identity.role_grant OWNER TO bridge_owner;
COMMENT ON TABLE identity.role_grant IS 'Role grants; SUPPORT_READ_ONLY is reserved for synthetic SUPPORT memberships (SEC-104). Delegation rules: contracts/authz/roles.yaml#delegation. owner_task=SEC-004';
CREATE INDEX role_grant_membership ON identity.role_grant (tenant_id, membership_id);

-- -----------------------------------------------------------------------------------------------------
-- identity.grant_clause - relational form of one scope clause (contracts/authz/scope.schema.json#/$defs/clause).
-- 'ALL' = "*"; every dimension explicit (G-SEC-02). IDs are validated against the tenant catalog (SEC-101-S08)
-- because arrays cannot carry FKs; foreign/unknown IDs -> 422 AUTHZ_SCOPE_REFERENCE_INVALID (non-enumerating).
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE identity.grant_clause (
  tenant_id            uuid        NOT NULL,
  id                   uuid        NOT NULL,
  grant_id             uuid        NOT NULL,
  ordinal              smallint    NOT NULL CHECK (ordinal BETWEEN 0 AND 49),
  org_mode             text        NOT NULL CHECK (org_mode IN ('ALL', 'LIST')),
  org_ids              uuid[]      NULL,
  account_mode         text        NOT NULL CHECK (account_mode IN ('ALL', 'LIST')),
  account_ids          uuid[]      NULL,
  group_mode           text        NOT NULL CHECK (group_mode IN ('ALL', 'GROUP_SET')),
  group_set_id         uuid        NULL,
  groups_mode          text        NULL CHECK (groups_mode IS NULL OR groups_mode IN ('ALL', 'LIST')),
  group_ids            uuid[]      NULL,
  include_descendants  boolean     NULL,
  include_shared       boolean     NOT NULL,
  include_unallocated  boolean     NOT NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  revision             bigint      NOT NULL DEFAULT 1,
  CONSTRAINT grant_clause_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT grant_clause_grant_fk FOREIGN KEY (tenant_id, grant_id) REFERENCES identity.role_grant (tenant_id, id) ON DELETE CASCADE,
  CONSTRAINT grant_clause_ordinal_uq UNIQUE (tenant_id, grant_id, ordinal),
  CONSTRAINT grant_clause_org_dim CHECK ((org_mode = 'ALL' AND org_ids IS NULL) OR (org_mode = 'LIST' AND org_ids IS NOT NULL AND cardinality(org_ids) BETWEEN 1 AND 500)),
  CONSTRAINT grant_clause_account_dim CHECK ((account_mode = 'ALL' AND account_ids IS NULL) OR (account_mode = 'LIST' AND account_ids IS NOT NULL AND cardinality(account_ids) BETWEEN 1 AND 500)),
  CONSTRAINT grant_clause_org_account_conflict CHECK (NOT (org_mode = 'LIST' AND account_mode = 'LIST')),  -- AUTHZ_SCOPE_DIMENSION_CONFLICT
  CONSTRAINT grant_clause_group_dim CHECK (
        (group_mode = 'ALL' AND group_set_id IS NULL AND groups_mode IS NULL AND group_ids IS NULL AND include_descendants IS NULL
           AND include_shared AND include_unallocated)
     OR (group_mode = 'GROUP_SET' AND group_set_id IS NOT NULL AND include_descendants IS NOT NULL
           AND ((groups_mode = 'ALL' AND group_ids IS NULL AND include_descendants)
             OR (groups_mode = 'LIST' AND group_ids IS NOT NULL AND cardinality(group_ids) BETWEEN 1 AND 500))))
);
ALTER TABLE identity.grant_clause OWNER TO bridge_owner;
COMMENT ON TABLE identity.grant_clause IS 'Scope clause rows; the canonical JSON form and profile are derived by packages/authz_scope (SEC-101). owner_task=SEC-101';
COMMENT ON COLUMN identity.grant_clause.account_ids IS 'Customer Snowflake account UUIDs (connection.account.id). x-privacy: INTERNAL';
CREATE INDEX grant_clause_grant ON identity.grant_clause (tenant_id, grant_id);

-- -----------------------------------------------------------------------------------------------------
-- identity.team / team_member - PEOPLE teams (membership administration, notification audiences). Grants never
-- reference teams; the optional link pre-fills invitation scope only (G-SEC-03).
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE identity.team (
  tenant_id            uuid        NOT NULL,
  id                   uuid        NOT NULL,
  name                 text        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
  name_norm            text        NOT NULL CHECK (name_norm = lower(name_norm)),
  description          text        NULL CHECK (description IS NULL OR char_length(description) <= 1000),
  linked_group_set_id  uuid        NULL,
  linked_group_id      uuid        NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  updated_by           uuid        NULL,
  revision             bigint      NOT NULL DEFAULT 1,
  CONSTRAINT team_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT team_tenant_fk FOREIGN KEY (tenant_id) REFERENCES identity.tenant (id),
  CONSTRAINT team_name_uq UNIQUE (tenant_id, name_norm),
  CONSTRAINT team_link_pair CHECK ((linked_group_set_id IS NULL) = (linked_group_id IS NULL))
);
ALTER TABLE identity.team OWNER TO bridge_owner;
COMMENT ON TABLE identity.team IS 'People team. linked_group_* reference governance usage groups (K7) by id; validated by the service (no cross-schema FK). owner_task=CTL-003';
COMMENT ON COLUMN identity.team.name IS 'x-privacy: CUSTOMER_METADATA';

CREATE TABLE identity.team_member (
  tenant_id       uuid        NOT NULL,
  id              uuid        NOT NULL,
  team_id         uuid        NOT NULL,
  membership_id   uuid        NOT NULL,
  is_team_admin   boolean     NOT NULL DEFAULT false,     -- Team Admin of THIS team (role TEAM_ADMIN still required for mutations)
  added_by        uuid        NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  revision        bigint      NOT NULL DEFAULT 1,
  CONSTRAINT team_member_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT team_member_team_fk FOREIGN KEY (tenant_id, team_id) REFERENCES identity.team (tenant_id, id) ON DELETE CASCADE,
  CONSTRAINT team_member_membership_fk FOREIGN KEY (tenant_id, membership_id) REFERENCES identity.membership (tenant_id, id),
  CONSTRAINT team_member_uq UNIQUE (tenant_id, team_id, membership_id)
);
ALTER TABLE identity.team_member OWNER TO bridge_owner;
COMMENT ON TABLE identity.team_member IS 'Team membership. owner_task=CTL-003';
CREATE INDEX team_member_membership ON identity.team_member (tenant_id, membership_id);

-- -----------------------------------------------------------------------------------------------------
-- identity.identity_provider - tenant-bound SAML/OIDC IdP (SEC-003-S01). Lifecycle: identity_provider.yaml.
-- binding_key is GLOBALLY unique (one IdP binds exactly one tenant); a duplicate answers 409
-- AUTH_IDP_ALREADY_BOUND without naming the other tenant.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE identity.identity_provider (
  tenant_id                 uuid        NOT NULL,
  id                        uuid        NOT NULL,
  protocol                  text        NOT NULL CHECK (protocol IN ('SAML', 'OIDC')),
  vendor                    text        NOT NULL CHECK (vendor IN ('ENTRA_ID', 'OKTA', 'GOOGLE_WORKSPACE', 'GENERIC_SAML', 'GENERIC_OIDC')),
  display_name              text        NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 120),
  cognito_pool_id           text        NOT NULL,        -- pool shard (G-SEC-08); one pool per env in R1
  cognito_provider_name     text        NOT NULL CHECK (cognito_provider_name ~ '^t-[a-z2-7]{12}-[0-9]{1,3}$'),  -- t-<tenant_short lower>-<n>
  entity_id                 text        NULL,            -- SAML entity ID
  oidc_issuer               text        NULL CHECK (oidc_issuer IS NULL OR oidc_issuer ~ '^https://'),
  oidc_client_id            text        NULL,
  google_hd                 text        NULL CHECK (google_hd IS NULL OR google_hd ~ '^[a-z0-9.-]+\.[a-z]{2,}$'),  -- verified domain for Google (SEC-003-S17)
  binding_key               text        NOT NULL,        -- SAML: entity_id; OIDC: issuer; Google: issuer|client_id|hd
  metadata_document         text        NULL CHECK (metadata_document IS NULL OR octet_length(metadata_document) <= 262144),  -- SAML metadata XML (public)
  metadata_sha256           text        NOT NULL CHECK (metadata_sha256 ~ '^[0-9a-f]{64}$'),   -- over metadata or OIDC discovery doc + client config
  subject_attribute         text        NOT NULL,        -- 'NameID:persistent' | 'http://schemas.microsoft.com/identity/claims/objectidentifier' | 'user.id' | 'sub'
  attribute_mapping_json    jsonb       NOT NULL CHECK (jsonb_typeof(attribute_mapping_json) = 'object'),
  attribute_mapping_schema_version smallint NOT NULL DEFAULT 1,
  mfa_assertion             text        NOT NULL CHECK (mfa_assertion IN ('REQUIRED_AMR', 'TRUSTED_IDP_POLICY')),
  mfa_accepted_values       text[]      NOT NULL DEFAULT '{}',   -- allowlisted amr values / AuthnContextClassRef URIs when REQUIRED_AMR
  jit_enabled               boolean     NOT NULL DEFAULT false,  -- JIT -> VIEWER with empty scope (SEC-003-S08)
  status                    text        NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'TESTED', 'ENFORCED', 'DISABLED')),
  tested_at                 timestamptz NULL,
  tested_by                 uuid        NULL,
  tested_metadata_sha256    text        NULL CHECK (tested_metadata_sha256 IS NULL OR tested_metadata_sha256 ~ '^[0-9a-f]{64}$'),
  enforced_at               timestamptz NULL,
  enforce_approval_id       uuid        NULL,
  disabled_at               timestamptz NULL,
  signing_cert_not_after    timestamptz NULL,            -- earliest expiry of accepted signing certs (alarms 30/7/1 d)
  pending_metadata_document text        NULL CHECK (pending_metadata_document IS NULL OR octet_length(pending_metadata_document) <= 262144),
  pending_metadata_sha256   text        NULL CHECK (pending_metadata_sha256 IS NULL OR pending_metadata_sha256 ~ '^[0-9a-f]{64}$'),
  pending_tested_at         timestamptz NULL,            -- cert/metadata rotation while ENFORCED: test candidate, then swap atomically (SEC-003-S11)
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  updated_by                uuid        NULL,
  revision                  bigint      NOT NULL DEFAULT 1,
  CONSTRAINT identity_provider_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT identity_provider_tenant_fk FOREIGN KEY (tenant_id) REFERENCES identity.tenant (id),
  CONSTRAINT identity_provider_binding_uq UNIQUE (binding_key),
  CONSTRAINT identity_provider_cognito_name_uq UNIQUE (cognito_pool_id, cognito_provider_name),
  CONSTRAINT identity_provider_protocol_fields CHECK (
       (protocol = 'SAML' AND entity_id IS NOT NULL AND oidc_issuer IS NULL)
    OR (protocol = 'OIDC' AND oidc_issuer IS NOT NULL AND oidc_client_id IS NOT NULL AND entity_id IS NULL)),
  CONSTRAINT identity_provider_google_hd CHECK (vendor <> 'GOOGLE_WORKSPACE' OR (protocol = 'OIDC' AND google_hd IS NOT NULL)),
  CONSTRAINT identity_provider_tested_consistency CHECK (status NOT IN ('TESTED', 'ENFORCED') OR (tested_at IS NOT NULL AND tested_metadata_sha256 = metadata_sha256)),
  CONSTRAINT identity_provider_enforced_consistency CHECK (status <> 'ENFORCED' OR (enforced_at IS NOT NULL AND enforce_approval_id IS NOT NULL)),
  CONSTRAINT identity_provider_disabled_consistency CHECK ((status = 'DISABLED') = (disabled_at IS NOT NULL)),
  CONSTRAINT identity_provider_pending_metadata CHECK ((pending_metadata_sha256 IS NULL) = (pending_metadata_document IS NULL)
                                                      AND (pending_tested_at IS NULL OR pending_metadata_sha256 IS NOT NULL)),
  CONSTRAINT identity_provider_mfa_values CHECK (mfa_assertion <> 'REQUIRED_AMR' OR cardinality(mfa_accepted_values) >= 1)
);
ALTER TABLE identity.identity_provider OWNER TO bridge_owner;
COMMENT ON TABLE identity.identity_provider IS 'Tenant-bound IdP; exactly one tenant per binding_key; admission refused when the pool IdP count >= 90 % of the verified quota (G-SEC-08). owner_task=SEC-003';
COMMENT ON COLUMN identity.identity_provider.display_name IS 'x-privacy: CUSTOMER_METADATA';
CREATE INDEX identity_provider_status ON identity.identity_provider (tenant_id, status);
CREATE UNIQUE INDEX identity_provider_one_enforced ON identity.identity_provider (tenant_id) WHERE status = 'ENFORCED';

CREATE TABLE identity.idp_domain (
  tenant_id                uuid        NOT NULL,
  id                       uuid        NOT NULL,
  identity_provider_id     uuid        NULL,
  domain                   text        NOT NULL CHECK (domain ~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$'),
  verification_token_hash  bytea       NOT NULL CHECK (octet_length(verification_token_hash) = 32),  -- DNS TXT _bridge-verify.<domain>
  status                   text        NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'VERIFIED', 'FAILED', 'EXPIRED')),
  verified_at              timestamptz NULL,
  last_checked_at          timestamptz NULL,
  next_check_at            timestamptz NULL,             -- re-check every 30 days
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  revision                 bigint      NOT NULL DEFAULT 1,
  CONSTRAINT idp_domain_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT idp_domain_idp_fk FOREIGN KEY (tenant_id, identity_provider_id) REFERENCES identity.identity_provider (tenant_id, id),
  CONSTRAINT idp_domain_tenant_domain_uq UNIQUE (tenant_id, domain),
  CONSTRAINT idp_domain_verified_consistency CHECK ((status = 'VERIFIED') = (verified_at IS NOT NULL))
);
ALTER TABLE identity.idp_domain OWNER TO bridge_owner;
COMMENT ON TABLE identity.idp_domain IS 'DNS-verified domains; discovery hints only - never grant membership (G-SEC-09). owner_task=SEC-003';
COMMENT ON COLUMN identity.idp_domain.domain IS 'x-privacy: CUSTOMER_METADATA';
CREATE UNIQUE INDEX idp_domain_verified_global ON identity.idp_domain (domain) WHERE status = 'VERIFIED';

-- -----------------------------------------------------------------------------------------------------
-- identity.subject_identity - federated identity link (provider, provider_subject) -> subject (SEC-003-S03).
-- Linking only via (a) invitation accepted while authenticated by the tenant IdP, (b) owner-approved link,
-- (c) JIT. Never by e-mail equality.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE identity.subject_identity (
  tenant_id              uuid        NOT NULL,       -- tenant of the identity provider
  id                     uuid        NOT NULL,
  subject_id             uuid        NOT NULL,
  identity_provider_id   uuid        NOT NULL,
  provider_subject       text        NOT NULL CHECK (char_length(provider_subject) BETWEEN 1 AND 512),  -- persistent NameID / immutable attr / OIDC sub
  linked_via             text        NOT NULL CHECK (linked_via IN ('INVITATION', 'OWNER_APPROVED_LINK', 'SSO_JIT')),
  linked_at              timestamptz NOT NULL DEFAULT now(),
  last_login_at          timestamptz NULL,
  revoked_at             timestamptz NULL,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  revision               bigint      NOT NULL DEFAULT 1,
  CONSTRAINT subject_identity_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT subject_identity_idp_fk FOREIGN KEY (tenant_id, identity_provider_id) REFERENCES identity.identity_provider (tenant_id, id),
  CONSTRAINT subject_identity_subject_fk FOREIGN KEY (subject_id) REFERENCES identity.subject (id),
  CONSTRAINT subject_identity_provider_subject_uq UNIQUE (tenant_id, identity_provider_id, provider_subject)
);
ALTER TABLE identity.subject_identity OWNER TO bridge_owner;
COMMENT ON TABLE identity.subject_identity IS 'Federated identity binding. owner_task=SEC-003';
COMMENT ON COLUMN identity.subject_identity.provider_subject IS 'x-privacy: PERSONAL (stable identifier at the customer IdP)';
CREATE INDEX subject_identity_subject ON identity.subject_identity (subject_id);

-- -----------------------------------------------------------------------------------------------------
-- identity.invitation (CTL-003-S04, Appendix E). Token = 32 random bytes in the URL FRAGMENT; only SHA-256 stored.
-- Lifecycle: invitation.yaml. Uniform 410 TENANT_INVITE_INVALID for unknown/expired/revoked/rotated tokens.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE identity.invitation (
  tenant_id                 uuid        NOT NULL,
  id                        uuid        NOT NULL,
  email_norm                text        NOT NULL CHECK (email_norm = lower(email_norm) AND char_length(email_norm) BETWEEN 3 AND 320),
  token_hash                bytea       NOT NULL CHECK (octet_length(token_hash) = 32),
  grants_json               jsonb       NOT NULL,        -- contracts/authz/scope.schema.json#/$defs/grant_set
  grants_schema_version     smallint    NOT NULL DEFAULT 1,
  team_ids                  uuid[]      NOT NULL DEFAULT '{}',
  is_bootstrap              boolean     NOT NULL DEFAULT false,   -- first-owner invitation created by operator provisioning
  invited_by_membership_id  uuid        NULL,
  invited_by_operator_subject_id uuid   NULL,
  status                    text        NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACCEPTED', 'REVOKED', 'EXPIRED')),
  expires_at                timestamptz NOT NULL,
  accepted_by_subject_id    uuid        NULL,
  accepted_membership_id    uuid        NULL,
  accepted_at               timestamptz NULL,
  revoked_at                timestamptz NULL,
  revoked_by                uuid        NULL,
  revoke_reason             text        NULL CHECK (revoke_reason IS NULL OR revoke_reason IN ('REVOKED_BY_ADMIN', 'INVITER_LOST_RIGHTS', 'TENANT_OFFBOARDED', 'SUPERSEDED')),
  resend_count              integer     NOT NULL DEFAULT 0 CHECK (resend_count BETWEEN 0 AND 10),
  last_sent_at              timestamptz NULL,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  updated_by                uuid        NULL,
  revision                  bigint      NOT NULL DEFAULT 1,
  CONSTRAINT invitation_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT invitation_tenant_fk FOREIGN KEY (tenant_id) REFERENCES identity.tenant (id),
  CONSTRAINT invitation_token_uq UNIQUE (token_hash),
  CONSTRAINT invitation_inviter_fk FOREIGN KEY (tenant_id, invited_by_membership_id) REFERENCES identity.membership (tenant_id, id),
  CONSTRAINT invitation_accepted_membership_fk FOREIGN KEY (tenant_id, accepted_membership_id) REFERENCES identity.membership (tenant_id, id),
  CONSTRAINT invitation_inviter_present CHECK ((is_bootstrap AND invited_by_operator_subject_id IS NOT NULL AND invited_by_membership_id IS NULL)
                                            OR (NOT is_bootstrap AND invited_by_membership_id IS NOT NULL)),
  CONSTRAINT invitation_ttl CHECK (expires_at > created_at AND expires_at <= coalesce(last_sent_at, created_at) + interval '14 days'),
  CONSTRAINT invitation_accepted_consistency CHECK ((status = 'ACCEPTED') = (accepted_at IS NOT NULL AND accepted_by_subject_id IS NOT NULL AND accepted_membership_id IS NOT NULL)),
  CONSTRAINT invitation_revoked_consistency CHECK ((status = 'REVOKED') = (revoked_at IS NOT NULL AND revoke_reason IS NOT NULL))
);
ALTER TABLE identity.invitation OWNER TO bridge_owner;
COMMENT ON TABLE identity.invitation IS 'Invitations; resend rotates token_hash and extends expires_at by <= 14 d from the resend. owner_task=CTL-003';
COMMENT ON COLUMN identity.invitation.email_norm IS 'NFKC + casefold; no plus-address folding. x-privacy: PERSONAL';
CREATE UNIQUE INDEX invitation_one_pending_per_email ON identity.invitation (tenant_id, email_norm) WHERE status = 'PENDING';
CREATE INDEX invitation_expiry ON identity.invitation (tenant_id, status, expires_at);

-- -----------------------------------------------------------------------------------------------------
-- identity.approval - generic maker-checker approval (SEC-102-S01, Appendix C.4). Lifecycle: approval.yaml.
-- Binds (action, object_type, object_id, object_revision, content_sha256); approver != requester and != last
-- editor; any revision change voids it; expiry 7 d; step-up per contracts/authz/capabilities.yaml#approval_policies.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE identity.approval (
  tenant_id                   uuid        NOT NULL,
  id                          uuid        NOT NULL,
  action                      text        NOT NULL CHECK (action ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),  -- key of approval_policies
  object_type                 text        NOT NULL CHECK (object_type ~ '^[a-z][a-z0-9_]*$'),
  object_id                   uuid        NOT NULL,
  object_revision             bigint      NOT NULL CHECK (object_revision >= 1),
  content_sha256              text        NOT NULL CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),  -- computed server-side from the object snapshot
  object_scope_json           jsonb       NOT NULL,       -- canonical atoms of the object scope (checker must hold capability over all)
  object_scope_schema_version smallint    NOT NULL DEFAULT 1,
  binding_json                jsonb       NULL,           -- action-specific extra bound fields, e.g. {simulation_id, window_fingerprint,
                                                          -- access_impact_digest} (ALC-003), {close_manifest_sha256} (FIN-010)
  binding_schema_version      smallint    NULL,
  requested_by_membership_id  uuid        NOT NULL,
  requested_by_subject_id     uuid        NOT NULL,
  last_editor_subject_id      uuid        NOT NULL,       -- updated_by of the approved revision
  requester_auth_time         timestamptz NULL,
  requested_at                timestamptz NOT NULL DEFAULT now(),
  reason                      text        NULL CHECK (reason IS NULL OR char_length(reason) <= 2000),
  status                      text        NOT NULL DEFAULT 'REQUESTED'
                              CHECK (status IN ('REQUESTED', 'APPROVED', 'REJECTED', 'EXPIRED', 'VOIDED', 'EXECUTED')),
  decided_by_membership_id    uuid        NULL,
  decided_by_subject_id       uuid        NULL,
  decider_auth_time           timestamptz NULL,
  decided_at                  timestamptz NULL,
  decision_reason             text        NULL CHECK (decision_reason IS NULL OR char_length(decision_reason) <= 2000),
  self_approved               boolean     NOT NULL DEFAULT false,
  expires_at                  timestamptz NOT NULL,
  executed_at                 timestamptz NULL,
  executed_by_subject_id      uuid        NULL,
  voided_at                   timestamptz NULL,
  void_reason                 text        NULL CHECK (void_reason IS NULL OR void_reason IN ('OBJECT_REVISED', 'CONTENT_CHANGED', 'APPROVER_LOST_CAPABILITY', 'REQUESTER_LOST_CAPABILITY', 'WITHDRAWN', 'SUPERSEDED')),
  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),
  revision                    bigint      NOT NULL DEFAULT 1,
  CONSTRAINT approval_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT approval_tenant_fk FOREIGN KEY (tenant_id) REFERENCES identity.tenant (id),
  CONSTRAINT approval_requester_fk FOREIGN KEY (tenant_id, requested_by_membership_id) REFERENCES identity.membership (tenant_id, id),
  CONSTRAINT approval_decider_fk FOREIGN KEY (tenant_id, decided_by_membership_id) REFERENCES identity.membership (tenant_id, id),
  CONSTRAINT approval_expiry CHECK (expires_at > requested_at AND expires_at <= requested_at + interval '7 days'),
  CONSTRAINT approval_sod CHECK (self_approved OR decided_by_subject_id IS NULL
                                 OR (decided_by_subject_id <> requested_by_subject_id AND decided_by_subject_id <> last_editor_subject_id)),
  CONSTRAINT approval_decided_consistency CHECK (status NOT IN ('APPROVED', 'REJECTED', 'EXECUTED') OR (decided_at IS NOT NULL AND decided_by_subject_id IS NOT NULL)),
  CONSTRAINT approval_requested_undecided CHECK (status <> 'REQUESTED' OR (decided_at IS NULL AND decided_by_subject_id IS NULL)),
  CONSTRAINT approval_executed_consistency CHECK ((status = 'EXECUTED') = (executed_at IS NOT NULL)),
  CONSTRAINT approval_voided_consistency CHECK ((status = 'VOIDED') = (voided_at IS NOT NULL AND void_reason IS NOT NULL)),
  CONSTRAINT approval_binding_versioned CHECK ((binding_json IS NULL) = (binding_schema_version IS NULL))
);
ALTER TABLE identity.approval OWNER TO bridge_owner;
COMMENT ON TABLE identity.approval IS 'Maker-checker approvals for close, restatement, statement issue, pricing, references, reconciliation explanations, rule publication, access review, FULL privacy, erasure, SSO enforcement, ownership transfer (SEC-102). owner_task=SEC-102';
CREATE UNIQUE INDEX approval_open_uq ON identity.approval (tenant_id, action, object_id, object_revision) WHERE status IN ('REQUESTED', 'APPROVED');
CREATE INDEX approval_inbox ON identity.approval (tenant_id, status, requested_at DESC);
CREATE INDEX approval_expiry ON identity.approval (tenant_id, expires_at) WHERE status IN ('REQUESTED', 'APPROVED');
CREATE INDEX approval_object ON identity.approval (tenant_id, object_type, object_id);

-- -----------------------------------------------------------------------------------------------------
-- identity.support_access_grant (SEC-104-S01; RECONCILIATION U-05, C-15). Default 4 h, max 8 h; support scopes
-- health_read | analytics_read; config_write is not a support scope in R1. Statuses follow K9 machine
-- `support_access` (see handoff). Materializes as a synthetic SUPPORT membership while ACTIVE.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE identity.support_access_grant (
  tenant_id                   uuid        NOT NULL,
  id                          uuid        NOT NULL,
  operator_subject_id         uuid        NOT NULL,       -- identity.subject with subject_kind = OPERATOR
  reason_code                 text        NOT NULL CHECK (reason_code IN ('INCIDENT', 'ONBOARDING_ASSISTANCE', 'DATA_QUALITY_INVESTIGATION', 'CUSTOMER_REQUEST', 'BILLING_QUESTION')),
  case_ref                    text        NOT NULL CHECK (case_ref ~ '^[A-Z]{2,10}-[0-9]{1,10}$'),
  support_scope               text        NOT NULL CHECK (support_scope IN ('health_read', 'analytics_read')),
  capabilities                text[]      NOT NULL CHECK (cardinality(capabilities) BETWEEN 1 AND 16),   -- subset of roles.yaml#support_scopes
  data_scope_json             jsonb       NULL,           -- scope.schema.json#/$defs/scope; required for analytics_read; <= approver scope
  data_scope_schema_version   smallint    NOT NULL DEFAULT 1,
  status                      text        NOT NULL DEFAULT 'REQUESTED'
                              CHECK (status IN ('REQUESTED', 'APPROVED', 'ACTIVE', 'EXPIRED', 'REVOKED', 'REJECTED')),
  requested_at                timestamptz NOT NULL DEFAULT now(),
  requested_duration_minutes  integer     NOT NULL DEFAULT 240 CHECK (requested_duration_minutes BETWEEN 15 AND 480),
  approved_by_membership_id   uuid        NULL,
  approver_auth_time          timestamptz NULL,
  auto_approved               boolean     NOT NULL DEFAULT false,   -- health_read auto-approve tenant policy (OPS-106-S07 absorbed)
  approved_at                 timestamptz NULL,
  starts_at                   timestamptz NULL,
  expires_at                  timestamptz NULL,
  membership_id               uuid        NULL,           -- synthetic SUPPORT membership while ACTIVE
  revoked_at                  timestamptz NULL,
  revoked_by                  uuid        NULL,
  revoke_reason               text        NULL,
  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),
  revision                    bigint      NOT NULL DEFAULT 1,
  CONSTRAINT support_access_grant_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT support_access_grant_tenant_fk FOREIGN KEY (tenant_id) REFERENCES identity.tenant (id),
  CONSTRAINT support_access_grant_operator_fk FOREIGN KEY (operator_subject_id) REFERENCES identity.subject (id),
  CONSTRAINT support_access_grant_approver_fk FOREIGN KEY (tenant_id, approved_by_membership_id) REFERENCES identity.membership (tenant_id, id),
  CONSTRAINT support_access_grant_membership_fk FOREIGN KEY (tenant_id, membership_id) REFERENCES identity.membership (tenant_id, id),
  CONSTRAINT support_access_grant_window CHECK (starts_at IS NULL OR (expires_at > starts_at AND expires_at <= starts_at + interval '8 hours')),
  CONSTRAINT support_access_grant_approval CHECK (status NOT IN ('APPROVED', 'ACTIVE', 'EXPIRED') OR (approved_at IS NOT NULL AND (auto_approved OR approved_by_membership_id IS NOT NULL))),
  CONSTRAINT support_access_grant_auto_health_only CHECK (NOT auto_approved OR support_scope = 'health_read'),
  CONSTRAINT support_access_grant_analytics_scope CHECK (support_scope <> 'analytics_read' OR data_scope_json IS NOT NULL)
);
ALTER TABLE identity.support_access_grant OWNER TO bridge_owner;
COMMENT ON TABLE identity.support_access_grant IS 'Customer-approved, time-bound, read-only support access; sessions carry X-Bridge-Support-Session and every request emits audit support.access.used. owner_task=SEC-104';
COMMENT ON COLUMN identity.support_access_grant.case_ref IS 'Support case reference. x-privacy: INTERNAL';
CREATE INDEX support_access_grant_status ON identity.support_access_grant (tenant_id, status, expires_at);
CREATE INDEX support_access_grant_active_expiry ON identity.support_access_grant (expires_at) WHERE status = 'ACTIVE';

-- -----------------------------------------------------------------------------------------------------
-- identity.machine_client (API-006-S01, owner_task API-006, R2 feature; table reserved here because the
-- identity schema file is K2's). Cognito client-credentials client bound to exactly one tenant.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE identity.machine_client (
  tenant_id              uuid        NOT NULL,
  id                     uuid        NOT NULL,
  cognito_client_id      text        NOT NULL CHECK (cognito_client_id ~ '^[a-z0-9]{20,64}$'),
  name                   text        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
  capabilities           text[]      NOT NULL CHECK (cardinality(capabilities) BETWEEN 1 AND 16),  -- roles.yaml#machine_client_allowlist
  scope_sha256           text        NOT NULL CHECK (scope_sha256 ~ '^[0-9a-f]{64}$'),
  scope_json             jsonb       NOT NULL,        -- scope.schema.json#/$defs/scope; <= creator scope
  scope_schema_version   smallint    NOT NULL DEFAULT 1,
  profile_id             uuid        NULL,
  status                 text        NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'REVOKED', 'EXPIRED')),
  created_by_subject_id  uuid        NOT NULL,
  expires_at             timestamptz NOT NULL,
  predecessor_id         uuid        NULL,
  last_used_at           timestamptz NULL,
  revoked_at             timestamptz NULL,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  revision               bigint      NOT NULL DEFAULT 1,
  CONSTRAINT machine_client_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT machine_client_tenant_fk FOREIGN KEY (tenant_id) REFERENCES identity.tenant (id),
  CONSTRAINT machine_client_cognito_uq UNIQUE (cognito_client_id),
  CONSTRAINT machine_client_profile_fk FOREIGN KEY (tenant_id, profile_id) REFERENCES identity.permission_profile (tenant_id, id),
  CONSTRAINT machine_client_predecessor_fk FOREIGN KEY (tenant_id, predecessor_id) REFERENCES identity.machine_client (tenant_id, id),
  CONSTRAINT machine_client_expiry CHECK (expires_at <= created_at + interval '365 days')
);
ALTER TABLE identity.machine_client OWNER TO bridge_owner;
COMMENT ON TABLE identity.machine_client IS 'Machine API client (API-006). Tenant never taken from a token scope string. owner_task=API-006';
COMMENT ON COLUMN identity.machine_client.name IS 'x-privacy: CUSTOMER_METADATA';

-- -----------------------------------------------------------------------------------------------------
-- RLS (Appendix E.3). Tenant template (a) for tenant tables; subject-scoped (b) for subject/tenant/membership;
-- definer access for identity.auth.sql functions.
-- -----------------------------------------------------------------------------------------------------
ALTER TABLE identity.subject ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.subject FORCE ROW LEVEL SECURITY;
CREATE POLICY subject_self ON identity.subject AS PERMISSIVE FOR SELECT TO bridge_api USING (id = app.current_subject());
CREATE POLICY subject_self_update ON identity.subject AS PERMISSIVE FOR UPDATE TO bridge_api
  USING (id = app.current_subject()) WITH CHECK (id = app.current_subject());
CREATE POLICY subject_tenant_members ON identity.subject AS PERMISSIVE FOR SELECT TO bridge_api, bridge_worker
  USING (EXISTS (SELECT 1 FROM identity.membership m WHERE m.subject_id = subject.id AND m.tenant_id = app.current_tenant()));
CREATE POLICY definer_access ON identity.subject AS PERMISSIVE FOR ALL TO bridge_definer USING (true) WITH CHECK (true);
GRANT SELECT, UPDATE (display_name, updated_at, revision) ON identity.subject TO bridge_api;
GRANT SELECT ON identity.subject TO bridge_worker;
GRANT SELECT, INSERT, UPDATE ON identity.subject TO bridge_definer;

ALTER TABLE identity.tenant ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.tenant FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_self ON identity.tenant AS PERMISSIVE FOR SELECT TO bridge_api, bridge_worker USING (id = app.current_tenant());
CREATE POLICY tenant_self_write ON identity.tenant AS PERMISSIVE FOR UPDATE TO bridge_api, bridge_worker
  USING (id = app.current_tenant()) WITH CHECK (id = app.current_tenant());
CREATE POLICY tenant_bootstrap_insert ON identity.tenant AS PERMISSIVE FOR INSERT TO bridge_api
  WITH CHECK (id = app.current_tenant());           -- operator provisioning transaction sets the new tenant as context
CREATE POLICY tenant_subject_member ON identity.tenant AS PERMISSIVE FOR SELECT TO bridge_api
  USING (EXISTS (SELECT 1 FROM identity.membership m WHERE m.tenant_id = tenant.id AND m.subject_id = app.current_subject() AND m.status = 'ACTIVE'));
CREATE POLICY definer_access ON identity.tenant AS PERMISSIVE FOR SELECT TO bridge_definer USING (true);
GRANT SELECT, INSERT, UPDATE ON identity.tenant TO bridge_api;
GRANT SELECT, UPDATE (status, suspension_reason, authz_epoch, activated_at, suspended_at, offboarding_started_at, deleted_at, updated_at, updated_by, revision) ON identity.tenant TO bridge_worker;
GRANT SELECT ON identity.tenant TO bridge_definer;

ALTER TABLE identity.membership ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.membership FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.membership AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
CREATE POLICY subject_self ON identity.membership AS PERMISSIVE FOR SELECT TO bridge_api USING (subject_id = app.current_subject());
CREATE POLICY definer_access ON identity.membership AS PERMISSIVE FOR SELECT TO bridge_definer USING (true);
GRANT SELECT, INSERT, UPDATE ON identity.membership TO bridge_api, bridge_worker;
GRANT SELECT ON identity.membership TO bridge_definer;

ALTER TABLE identity.permission_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.permission_profile FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.permission_profile AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
CREATE POLICY definer_access ON identity.permission_profile AS PERMISSIVE FOR SELECT TO bridge_definer USING (true);
GRANT SELECT, INSERT, UPDATE ON identity.permission_profile TO bridge_api, bridge_worker;
GRANT SELECT ON identity.permission_profile TO bridge_definer;

ALTER TABLE identity.role_grant ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.role_grant FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.role_grant AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
GRANT SELECT, INSERT, UPDATE, DELETE ON identity.role_grant TO bridge_api, bridge_worker;

ALTER TABLE identity.grant_clause ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.grant_clause FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.grant_clause AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
GRANT SELECT, INSERT, UPDATE, DELETE ON identity.grant_clause TO bridge_api, bridge_worker;

ALTER TABLE identity.team ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.team FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.team AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
GRANT SELECT, INSERT, UPDATE, DELETE ON identity.team TO bridge_api;
GRANT SELECT ON identity.team TO bridge_worker;

ALTER TABLE identity.team_member ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.team_member FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.team_member AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
GRANT SELECT, INSERT, UPDATE, DELETE ON identity.team_member TO bridge_api;
GRANT SELECT ON identity.team_member TO bridge_worker;

ALTER TABLE identity.identity_provider ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.identity_provider FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.identity_provider AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
CREATE POLICY definer_access ON identity.identity_provider AS PERMISSIVE FOR SELECT TO bridge_definer USING (true);
GRANT SELECT, INSERT, UPDATE ON identity.identity_provider TO bridge_api, bridge_worker;
GRANT SELECT ON identity.identity_provider TO bridge_definer;

ALTER TABLE identity.idp_domain ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.idp_domain FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.idp_domain AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
CREATE POLICY definer_access ON identity.idp_domain AS PERMISSIVE FOR SELECT TO bridge_definer USING (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON identity.idp_domain TO bridge_api;
GRANT SELECT, UPDATE ON identity.idp_domain TO bridge_worker;
GRANT SELECT ON identity.idp_domain TO bridge_definer;

ALTER TABLE identity.subject_identity ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.subject_identity FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.subject_identity AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
CREATE POLICY definer_access ON identity.subject_identity AS PERMISSIVE FOR ALL TO bridge_definer USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE ON identity.subject_identity TO bridge_api;
GRANT SELECT, INSERT, UPDATE ON identity.subject_identity TO bridge_definer;

ALTER TABLE identity.invitation ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.invitation FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.invitation AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
CREATE POLICY definer_access ON identity.invitation AS PERMISSIVE FOR SELECT TO bridge_definer USING (true);
GRANT SELECT, INSERT, UPDATE ON identity.invitation TO bridge_api, bridge_worker;
GRANT SELECT ON identity.invitation TO bridge_definer;

ALTER TABLE identity.approval ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.approval FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.approval AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
GRANT SELECT, INSERT, UPDATE ON identity.approval TO bridge_api, bridge_worker;

ALTER TABLE identity.support_access_grant ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.support_access_grant FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.support_access_grant AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
CREATE POLICY definer_access ON identity.support_access_grant AS PERMISSIVE FOR SELECT TO bridge_definer USING (true);
GRANT SELECT, INSERT, UPDATE ON identity.support_access_grant TO bridge_api, bridge_worker;
GRANT SELECT ON identity.support_access_grant TO bridge_definer;

ALTER TABLE identity.machine_client ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.machine_client FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.machine_client AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
CREATE POLICY definer_access ON identity.machine_client AS PERMISSIVE FOR SELECT TO bridge_definer USING (true);
GRANT SELECT, INSERT, UPDATE ON identity.machine_client TO bridge_api, bridge_worker;
GRANT SELECT ON identity.machine_client TO bridge_definer;

GRANT SELECT ON identity.permission_profile, identity.membership, identity.tenant TO bridge_audit_exporter;  -- audit enrichment is ID-only; no PII tables

INSERT INTO app.rls_allowlist (schema_name, object_name, exception, detail, reason, owner_task) VALUES
  ('identity', 'subject', 'USING_TRUE_POLICY', 'definer_access', 'identity.upsert_subject()/resolve_* definer functions only', 'SEC-004'),
  ('identity', 'subject', 'NO_TENANT_COLUMN', 'subject', 'Global subject table (subject-scoped policies)', 'SEC-004'),
  ('identity', 'tenant', 'USING_TRUE_POLICY', 'definer_access', 'identity.resolve_session() reads tenant status/epoch', 'SEC-004'),
  ('identity', 'tenant', 'NO_TENANT_COLUMN', 'tenant', 'Tenant root; key column is id', 'SEC-004'),
  ('identity', 'membership', 'USING_TRUE_POLICY', 'definer_access', 'identity.resolve_session() / list_subject_memberships()', 'SEC-004'),
  ('identity', 'permission_profile', 'USING_TRUE_POLICY', 'definer_access', 'identity.resolve_session() returns profile hash/status', 'SEC-006'),
  ('identity', 'identity_provider', 'USING_TRUE_POLICY', 'definer_access', 'identity.resolve_federated_subject() before tenant context', 'SEC-003'),
  ('identity', 'identity_provider', 'GLOBAL_UNIQUE', 'identity_provider_binding_uq', 'One IdP binds one tenant; conflict -> 409 AUTH_IDP_ALREADY_BOUND without tenant name', 'SEC-003'),
  ('identity', 'identity_provider', 'GLOBAL_UNIQUE', 'identity_provider_cognito_name_uq', 'Cognito provider names are pool-global', 'SEC-003'),
  ('identity', 'idp_domain', 'USING_TRUE_POLICY', 'definer_access', 'POST /v1/auth/discover resolves verified domains before authentication', 'SEC-003'),
  ('identity', 'idp_domain', 'GLOBAL_UNIQUE', 'idp_domain_verified_global', 'A verified domain maps to one tenant IdP; conflict answered generically', 'SEC-003'),
  ('identity', 'subject_identity', 'USING_TRUE_POLICY', 'definer_access', 'Federated login resolves (provider, subject) before tenant context', 'SEC-003'),
  ('identity', 'invitation', 'USING_TRUE_POLICY', 'definer_access', 'identity.lookup_invitation(token_hash) before tenant context', 'CTL-003'),
  ('identity', 'invitation', 'GLOBAL_UNIQUE', 'invitation_token_uq', '256-bit random token hash; collisions infeasible; lookup via definer only', 'CTL-003'),
  ('identity', 'support_access_grant', 'USING_TRUE_POLICY', 'definer_access', 'identity.resolve_session() returns support grant expiry', 'SEC-104'),
  ('identity', 'machine_client', 'USING_TRUE_POLICY', 'definer_access', 'Bearer middleware resolves client_id before tenant context', 'API-006'),
  ('identity', 'machine_client', 'GLOBAL_UNIQUE', 'machine_client_cognito_uq', 'Cognito client ids are pool-global', 'API-006');

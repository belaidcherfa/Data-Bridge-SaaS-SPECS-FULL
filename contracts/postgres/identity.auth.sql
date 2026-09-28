-- contract=pg-identity-auth version=1 status=DRAFT owner_task=SEC-002 decisions=D-02,D-19,D-20,D-22,D-25 last_changed=2026-09-28
-- =====================================================================================================
-- Schema `identity` (part: auth): server-side BFF sessions, OAuth/OIDC auth transactions and the
-- SECURITY DEFINER functions used before (or independently of) a tenant context.
-- Normative sources: SEC backlog Appendix D (session model), Appendix F (revocation: resolve_session in one
-- indexed round trip), G-SEC-06/07/09/12, SEC-002-S02/S05/S07/S08/S10/S11/S12, SEC-003-S06/S07, SEC-006-S02/S11.
-- Revocation contract: docs/security/revocation.md. Session lifecycle: contracts/state-machines/session.yaml.
--
-- Table class (e) DEFINER-ONLY: runtime roles have NO grants on identity.session / identity.auth_transaction;
-- every access goes through the functions below (owned by bridge_definer, fixed search_path, fully qualified
-- names, parameter-bound lookups only). Apply after identity.sql and tenant.sql.
-- =====================================================================================================

-- -----------------------------------------------------------------------------------------------------
-- identity.session (Appendix D.2). Keyed by SHA-256 of the 256-bit opaque cookie __Host-bridge_sid.
-- The row id is stable across sid rotation (login, tenant switch, step-up rotate sid_hash in place) because it
-- is the AAD of the encrypted Cognito refresh token.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE identity.session (
  id                   uuid        NOT NULL,
  sid_hash             bytea       NOT NULL CHECK (octet_length(sid_hash) = 32),
  subject_id           uuid        NOT NULL,
  session_kind         text        NOT NULL DEFAULT 'USER' CHECK (session_kind IN ('USER', 'OPERATOR_SUPPORT')),
  status               text        NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'REVOKED', 'EXPIRED')),
  active_tenant_id     uuid        NULL,          -- UI hint only (last selected tenant); NEVER an authorization input (G-API-13)
  idp_id               uuid        NULL,          -- identity.identity_provider.id for federated sessions
  idp_tenant_id        uuid        NULL,          -- tenant the IdP is bound to (federated sessions may only select it)
  amr                  text[]      NOT NULL DEFAULT '{}',   -- e.g. {pwd,otp} {pwd,webauthn} {fed,mfa}
  auth_time            timestamptz NOT NULL,      -- last primary/step-up authentication (step-up window 600 s)
  created_at           timestamptz NOT NULL DEFAULT now(),
  last_seen_at         timestamptz NOT NULL DEFAULT now(),  -- written at most every 60 s
  idle_timeout_s       integer     NOT NULL DEFAULT 1800 CHECK (idle_timeout_s BETWEEN 900 AND 7200),
  absolute_expires_at  timestamptz NOT NULL,      -- created_at + tenant/default absolute (1-24 h, default 12 h)
  refresh_ciphertext   bytea       NULL,          -- AES-256-GCM(Cognito refresh token), AAD = id; never plaintext
  refresh_key_ref      text        NULL,          -- KMS-encrypted data key reference (envelope)
  refresh_expires_at   timestamptz NULL,
  access_expires_at    timestamptz NULL,          -- Cognito access token expiry (10 min)
  last_refresh_at      timestamptz NULL,
  refresh_lock_owner   text        NULL,          -- single-flight refresh (SEC-002-S10)
  refresh_lock_until   timestamptz NULL,
  user_agent_hash      bytea       NULL CHECK (user_agent_hash IS NULL OR octet_length(user_agent_hash) = 32),
  ip_prefix            inet        NULL,          -- /24 IPv4, /48 IPv6
  revoked_at           timestamptz NULL,
  revoke_reason        text        NULL CHECK (revoke_reason IS NULL OR revoke_reason IN
                         ('LOGOUT', 'LOGOUT_EVERYWHERE', 'USER_REVOKED', 'ADMIN_REVOKED', 'IDP_REVOKED', 'SUBJECT_DISABLED',
                          'SECURITY_KILL_SWITCH', 'EMERGENCY_GLOBAL_LOGOUT', 'MFA_RESET', 'SUPPORT_GRANT_ENDED')),
  expired_at           timestamptz NULL,
  expiry_reason        text        NULL CHECK (expiry_reason IS NULL OR expiry_reason IN ('IDLE', 'ABSOLUTE')),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  revision             bigint      NOT NULL DEFAULT 1,
  CONSTRAINT session_pk PRIMARY KEY (id),
  CONSTRAINT session_sid_hash_uq UNIQUE (sid_hash),
  CONSTRAINT session_subject_fk FOREIGN KEY (subject_id) REFERENCES identity.subject (id),
  CONSTRAINT session_absolute_bound CHECK (absolute_expires_at > created_at AND absolute_expires_at <= created_at + interval '24 hours'),
  CONSTRAINT session_idp_pair CHECK ((idp_id IS NULL) = (idp_tenant_id IS NULL)),
  CONSTRAINT session_revoked_consistency CHECK ((status = 'REVOKED') = (revoked_at IS NOT NULL AND revoke_reason IS NOT NULL)),
  CONSTRAINT session_expired_consistency CHECK ((status = 'EXPIRED') = (expired_at IS NOT NULL AND expiry_reason IS NOT NULL))
);
ALTER TABLE identity.session OWNER TO bridge_owner;
COMMENT ON TABLE identity.session IS 'Server-side BFF session (G-SEC-06). Definer-only access. Revoked/expired rows purged after 30 days. owner_task=SEC-002';
COMMENT ON COLUMN identity.session.refresh_ciphertext IS 'x-privacy: SECRET (encrypted at rest; plaintext never persisted or logged)';
COMMENT ON COLUMN identity.session.ip_prefix IS 'x-privacy: PERSONAL';
CREATE INDEX session_subject_active ON identity.session (subject_id) WHERE status = 'ACTIVE';
CREATE INDEX session_purge ON identity.session (updated_at) WHERE status IN ('REVOKED', 'EXPIRED');

-- -----------------------------------------------------------------------------------------------------
-- identity.auth_transaction (Appendix D.2): state/nonce/PKCE for GET /v1/auth/login -> /v1/auth/callback,
-- SSO test flow and step-up. TTL 10 min; consumed atomically once.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE identity.auth_transaction (
  state_hash                bytea       NOT NULL CHECK (octet_length(state_hash) = 32),
  nonce_hash                bytea       NOT NULL CHECK (octet_length(nonce_hash) = 32),
  binding_hash              bytea       NOT NULL CHECK (octet_length(binding_hash) = 32),  -- sha256 of __Host-bridge_auth cookie
  pkce_verifier_ciphertext  bytea       NOT NULL,
  pkce_key_ref              text        NOT NULL,
  return_to                 text        NOT NULL DEFAULT '/' CHECK (return_to ~ '^/(?!/)[A-Za-z0-9/_\-?=&%.~]*$' AND char_length(return_to) <= 512),
  idp_hint                  text        NULL,       -- cognito_provider_name resolved by discovery
  purpose                   text        NOT NULL CHECK (purpose IN ('LOGIN', 'SSO_TEST', 'STEP_UP')),
  test_tenant_id            uuid        NULL,
  test_identity_provider_id uuid        NULL,
  step_up_session_id        uuid        NULL,
  created_at                timestamptz NOT NULL DEFAULT now(),
  expires_at                timestamptz NOT NULL,
  consumed_at               timestamptz NULL,
  CONSTRAINT auth_transaction_pk PRIMARY KEY (state_hash),
  CONSTRAINT auth_transaction_ttl CHECK (expires_at > created_at AND expires_at <= created_at + interval '10 minutes'),
  CONSTRAINT auth_transaction_test_fields CHECK ((purpose = 'SSO_TEST') = (test_tenant_id IS NOT NULL AND test_identity_provider_id IS NOT NULL)),
  CONSTRAINT auth_transaction_step_up_fields CHECK ((purpose = 'STEP_UP') = (step_up_session_id IS NOT NULL))
);
ALTER TABLE identity.auth_transaction OWNER TO bridge_owner;
COMMENT ON TABLE identity.auth_transaction IS 'Login/test/step-up transaction; second use of a state -> AUTH_STATE_INVALID. Purged 24 h after expiry. owner_task=SEC-002';
CREATE INDEX auth_transaction_purge ON identity.auth_transaction (expires_at);

ALTER TABLE identity.session ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.session FORCE ROW LEVEL SECURITY;
CREATE POLICY definer_access ON identity.session AS PERMISSIVE FOR ALL TO bridge_definer USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON identity.session TO bridge_definer;

ALTER TABLE identity.auth_transaction ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.auth_transaction FORCE ROW LEVEL SECURITY;
CREATE POLICY definer_access ON identity.auth_transaction AS PERMISSIVE FOR ALL TO bridge_definer USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON identity.auth_transaction TO bridge_definer;

-- =====================================================================================================
-- SECURITY DEFINER functions (allowlisted; owner bridge_definer; search_path pinned).
-- =====================================================================================================

-- ---- Subjects -----------------------------------------------------------------------------------------
-- Callback subject resolution (SEC-002-S06): native (issuer, sub). New subject gets zero memberships.
-- e-mail is updated only when p_email_verified is true; e-mail never links identities.
CREATE FUNCTION identity.upsert_subject(p_new_id uuid, p_issuer text, p_cognito_sub text, p_subject_kind text,
                                        p_email_norm text, p_email_verified boolean, p_display_name text)
  RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO identity.subject AS s (id, issuer, cognito_sub, subject_kind, email_norm, email_verified, display_name, last_login_at)
  VALUES (p_new_id, p_issuer, p_cognito_sub, p_subject_kind,
          CASE WHEN p_email_verified THEN p_email_norm END, coalesce(p_email_verified, false), p_display_name, now())
  ON CONFLICT (issuer, cognito_sub) DO UPDATE
     SET email_norm = CASE WHEN p_email_verified THEN p_email_norm ELSE s.email_norm END,
         email_verified = s.email_verified OR coalesce(p_email_verified, false),
         last_login_at = now(), updated_at = now(), revision = s.revision + 1
   WHERE s.status = 'ACTIVE'
  RETURNING s.id INTO v_id;
  RETURN v_id;   -- NULL when the subject exists but is DISABLED/ERASED -> login denied
END $$;
ALTER FUNCTION identity.upsert_subject(uuid, text, text, text, text, boolean, text) OWNER TO bridge_definer;

-- Federated resolution (SEC-003-S03/S07): (Cognito provider name, provider subject) -> existing link.
-- Zero rows = unknown identity (invitation linking or JIT decides next; never e-mail matching).
CREATE FUNCTION identity.resolve_federated_subject(p_cognito_pool_id text, p_cognito_provider_name text, p_provider_subject text)
  RETURNS TABLE (identity_provider_id uuid, idp_tenant_id uuid, idp_status text, jit_enabled boolean,
                 mfa_assertion text, mfa_accepted_values text[], subject_id uuid, link_revoked boolean)
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  SELECT p.id, p.tenant_id, p.status, p.jit_enabled, p.mfa_assertion, p.mfa_accepted_values,
         si.subject_id, (si.revoked_at IS NOT NULL)
    FROM identity.identity_provider p
    LEFT JOIN identity.subject_identity si
           ON si.tenant_id = p.tenant_id AND si.identity_provider_id = p.id AND si.provider_subject = p_provider_subject
   WHERE p.cognito_pool_id = p_cognito_pool_id AND p.cognito_provider_name = p_cognito_provider_name
     AND p.status IN ('TESTED', 'ENFORCED')
$$;
ALTER FUNCTION identity.resolve_federated_subject(text, text, text) OWNER TO bridge_definer;

-- Home-realm discovery (SEC-003-S06): verified domain -> IdP redirect target, else zero rows (generic login).
-- The endpoint pads latency and returns a constant response shape either way.
CREATE FUNCTION identity.discover_identity_provider(p_email_domain text)
  RETURNS TABLE (cognito_pool_id text, cognito_provider_name text)
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  SELECT p.cognito_pool_id, p.cognito_provider_name
    FROM identity.idp_domain d
    JOIN identity.identity_provider p ON p.tenant_id = d.tenant_id
                                      AND p.id = coalesce(d.identity_provider_id, p.id)
   WHERE d.domain = lower(p_email_domain) AND d.status = 'VERIFIED' AND p.status IN ('TESTED', 'ENFORCED')
   ORDER BY (p.status = 'ENFORCED') DESC, p.created_at
   LIMIT 1
$$;
ALTER FUNCTION identity.discover_identity_provider(text) OWNER TO bridge_definer;

-- ---- Auth transactions --------------------------------------------------------------------------------
CREATE FUNCTION identity.begin_auth_transaction(p_state_hash bytea, p_nonce_hash bytea, p_binding_hash bytea,
    p_pkce_verifier_ciphertext bytea, p_pkce_key_ref text, p_return_to text, p_idp_hint text, p_purpose text,
    p_test_tenant_id uuid, p_test_identity_provider_id uuid, p_step_up_session_id uuid)
  RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  INSERT INTO identity.auth_transaction (state_hash, nonce_hash, binding_hash, pkce_verifier_ciphertext, pkce_key_ref,
      return_to, idp_hint, purpose, test_tenant_id, test_identity_provider_id, step_up_session_id, created_at, expires_at)
  VALUES (p_state_hash, p_nonce_hash, p_binding_hash, p_pkce_verifier_ciphertext, p_pkce_key_ref,
      p_return_to, p_idp_hint, p_purpose, p_test_tenant_id, p_test_identity_provider_id, p_step_up_session_id, now(), now() + interval '10 minutes')
$$;
ALTER FUNCTION identity.begin_auth_transaction(bytea, bytea, bytea, bytea, text, text, text, text, uuid, uuid, uuid) OWNER TO bridge_definer;

-- Atomic single use (SEC-002-S05). Zero rows -> AUTH_STATE_INVALID (unknown, replayed, expired or cookie mismatch).
CREATE FUNCTION identity.consume_auth_transaction(p_state_hash bytea, p_binding_hash bytea)
  RETURNS TABLE (nonce_hash bytea, pkce_verifier_ciphertext bytea, pkce_key_ref text, return_to text, idp_hint text,
                 purpose text, test_tenant_id uuid, test_identity_provider_id uuid, step_up_session_id uuid)
  LANGUAGE sql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  UPDATE identity.auth_transaction t
     SET consumed_at = now()
   WHERE t.state_hash = p_state_hash AND t.binding_hash = p_binding_hash
     AND t.consumed_at IS NULL AND t.expires_at > now()
  RETURNING t.nonce_hash, t.pkce_verifier_ciphertext, t.pkce_key_ref, t.return_to, t.idp_hint, t.purpose,
            t.test_tenant_id, t.test_identity_provider_id, t.step_up_session_id
$$;
ALTER FUNCTION identity.consume_auth_transaction(bytea, bytea) OWNER TO bridge_definer;

-- ---- Sessions -----------------------------------------------------------------------------------------
CREATE FUNCTION identity.create_session(p_id uuid, p_sid_hash bytea, p_subject_id uuid, p_session_kind text,
    p_idp_id uuid, p_idp_tenant_id uuid, p_amr text[], p_auth_time timestamptz, p_idle_timeout_s integer,
    p_absolute_expires_at timestamptz, p_refresh_ciphertext bytea, p_refresh_key_ref text, p_refresh_expires_at timestamptz,
    p_access_expires_at timestamptz, p_user_agent_hash bytea, p_ip_prefix inet)
  RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  INSERT INTO identity.session (id, sid_hash, subject_id, session_kind, idp_id, idp_tenant_id, amr, auth_time, idle_timeout_s,
      absolute_expires_at, refresh_ciphertext, refresh_key_ref, refresh_expires_at, access_expires_at, last_refresh_at,
      user_agent_hash, ip_prefix)
  VALUES (p_id, p_sid_hash, p_subject_id, p_session_kind, p_idp_id, p_idp_tenant_id, p_amr, p_auth_time, p_idle_timeout_s,
      p_absolute_expires_at, p_refresh_ciphertext, p_refresh_key_ref, p_refresh_expires_at, p_access_expires_at, now(),
      p_user_agent_hash, p_ip_prefix)
$$;
ALTER FUNCTION identity.create_session(uuid, bytea, uuid, text, uuid, uuid, text[], timestamptz, integer, timestamptz, bytea, text, timestamptz, timestamptz, bytea, inet) OWNER TO bridge_definer;

-- THE per-request resolver (Appendix F, SEC-006-S02): one indexed round trip returning session validity,
-- membership in the requested tenant (header X-Bridge-Tenant), epochs, profile and tenant policy.
-- Zero rows = unknown or revoked session (401). A row with session_state <> 'VALID' = expired (401).
-- tenant_* / membership_* columns are NULL when p_tenant_id is NULL or the subject has no membership there
-- (-> non-enumerating 404 on tenant routes). Nothing here is cached across requests except by epoch.
CREATE FUNCTION identity.resolve_session(p_sid_hash bytea, p_tenant_id uuid)
  RETURNS TABLE (
    session_id uuid, subject_id uuid, subject_status text, session_kind text, session_state text,
    auth_time timestamptz, amr text[], idp_id uuid, idp_tenant_id uuid,
    idle_expires_at timestamptz, absolute_expires_at timestamptz, access_expires_at timestamptz, last_refresh_at timestamptz,
    last_seen_at timestamptz, active_tenant_hint uuid,
    tenant_id uuid, tenant_status text, tenant_authz_epoch bigint,
    tenant_idle_timeout_s integer, tenant_absolute_timeout_s integer, tenant_step_up_max_age_s integer,
    tenant_sso_enforced_idp_id uuid, tenant_privacy_mode text,
    membership_id uuid, membership_status text, membership_kind text, permission_epoch bigint, is_break_glass_owner boolean,
    profile_id uuid, profile_hash text, profile_status text, pending_profile_id uuid,
    support_grant_expires_at timestamptz)
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  SELECT s.id, s.subject_id, sub.status, s.session_kind,
         CASE WHEN sub.status <> 'ACTIVE' THEN 'SUBJECT_DISABLED'
              WHEN now() >= s.absolute_expires_at THEN 'EXPIRED_ABSOLUTE'
              WHEN now() >= s.last_seen_at + make_interval(secs => least(s.idle_timeout_s, coalesce(ts.session_idle_timeout_minutes * 60, s.idle_timeout_s)))
                THEN 'EXPIRED_IDLE'
              ELSE 'VALID' END,
         s.auth_time, s.amr, s.idp_id, s.idp_tenant_id,
         s.last_seen_at + make_interval(secs => least(s.idle_timeout_s, coalesce(ts.session_idle_timeout_minutes * 60, s.idle_timeout_s))),
         least(s.absolute_expires_at, s.created_at + make_interval(hours => coalesce(ts.session_absolute_timeout_hours, 24))),
         s.access_expires_at, s.last_refresh_at, s.last_seen_at, s.active_tenant_id,
         t.id, t.status, t.authz_epoch,
         ts.session_idle_timeout_minutes * 60, ts.session_absolute_timeout_hours * 3600, ts.step_up_max_age_seconds,
         ts.sso_enforced_identity_provider_id, ts.privacy_mode,
         m.id, m.status, m.kind, m.permission_epoch, m.is_break_glass_owner,
         m.profile_id, pp.profile_hash, pp.status, m.pending_profile_id,
         sg.expires_at
    FROM identity.session s
    JOIN identity.subject sub ON sub.id = s.subject_id
    LEFT JOIN identity.membership m ON p_tenant_id IS NOT NULL AND m.tenant_id = p_tenant_id AND m.subject_id = s.subject_id
    LEFT JOIN identity.tenant t ON t.id = m.tenant_id
    LEFT JOIN tenant.setting ts ON ts.tenant_id = m.tenant_id
    LEFT JOIN identity.permission_profile pp ON pp.tenant_id = m.tenant_id AND pp.id = m.profile_id
    LEFT JOIN identity.support_access_grant sg ON sg.tenant_id = m.tenant_id AND sg.id = m.support_access_grant_id
   WHERE s.sid_hash = p_sid_hash AND s.status = 'ACTIVE'
$$;
ALTER FUNCTION identity.resolve_session(bytea, uuid) OWNER TO bridge_definer;
COMMENT ON FUNCTION identity.resolve_session(bytea, uuid) IS 'Per-request authz state (Appendix F). p99 < 2 ms server time at 500 req/s (SEC-006-S02). Used by the API middleware and by the query broker recheck (every 10 s for running statements). owner_task=SEC-006';

-- Machine clients (API-006): bearer middleware resolution, same shape for the tenant part.
CREATE FUNCTION identity.resolve_machine_client(p_cognito_client_id text)
  RETURNS TABLE (machine_client_id uuid, tenant_id uuid, client_status text, expires_at timestamptz, capabilities text[],
                 tenant_status text, tenant_authz_epoch bigint, profile_id uuid, profile_hash text, profile_status text)
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  SELECT mc.id, mc.tenant_id, CASE WHEN mc.status = 'ACTIVE' AND mc.expires_at <= now() THEN 'EXPIRED' ELSE mc.status END,
         mc.expires_at, mc.capabilities, t.status, t.authz_epoch, mc.profile_id, pp.profile_hash, pp.status
    FROM identity.machine_client mc
    JOIN identity.tenant t ON t.id = mc.tenant_id
    LEFT JOIN identity.permission_profile pp ON pp.tenant_id = mc.tenant_id AND pp.id = mc.profile_id
   WHERE mc.cognito_client_id = p_cognito_client_id
$$;
ALTER FUNCTION identity.resolve_machine_client(text) OWNER TO bridge_definer;

-- Throttled activity write (>= 60 s between writes, SEC-002-S08).
CREATE FUNCTION identity.touch_session(p_session_id uuid)
  RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  UPDATE identity.session SET last_seen_at = now()
   WHERE id = p_session_id AND status = 'ACTIVE' AND last_seen_at < now() - interval '60 seconds'
$$;
ALTER FUNCTION identity.touch_session(uuid) OWNER TO bridge_definer;

-- Lazy expiry marker (called by the middleware when resolve_session reports EXPIRED_*; also by the reaper).
CREATE FUNCTION identity.expire_session(p_session_id uuid, p_reason text)
  RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  UPDATE identity.session
     SET status = 'EXPIRED', expired_at = now(), expiry_reason = p_reason, refresh_ciphertext = NULL,
         updated_at = now(), revision = revision + 1
   WHERE id = p_session_id AND status = 'ACTIVE' AND p_reason IN ('IDLE', 'ABSOLUTE')
$$;
ALTER FUNCTION identity.expire_session(uuid, text) OWNER TO bridge_definer;

-- sid rotation on login, tenant switch and step-up (fixation defence). Returns the session id, NULL if the old
-- sid is not an active session. The old cookie stops working at commit.
CREATE FUNCTION identity.rotate_session(p_old_sid_hash bytea, p_new_sid_hash bytea, p_new_auth_time timestamptz,
                                        p_new_amr text[], p_active_tenant_hint uuid)
  RETURNS uuid LANGUAGE sql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  UPDATE identity.session
     SET sid_hash = p_new_sid_hash,
         auth_time = coalesce(p_new_auth_time, auth_time),
         amr = coalesce(p_new_amr, amr),
         active_tenant_id = coalesce(p_active_tenant_hint, active_tenant_id),
         last_seen_at = now(), updated_at = now(), revision = revision + 1
   WHERE sid_hash = p_old_sid_hash AND status = 'ACTIVE'
  RETURNING id
$$;
ALTER FUNCTION identity.rotate_session(bytea, bytea, timestamptz, text[], uuid) OWNER TO bridge_definer;

CREATE FUNCTION identity.revoke_session(p_sid_hash bytea, p_reason text)
  RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  WITH u AS (
    UPDATE identity.session
       SET status = 'REVOKED', revoked_at = now(), revoke_reason = p_reason, refresh_ciphertext = NULL,
           updated_at = now(), revision = revision + 1
     WHERE sid_hash = p_sid_hash AND status = 'ACTIVE'
    RETURNING 1)
  SELECT EXISTS (SELECT 1 FROM u)
$$;
ALTER FUNCTION identity.revoke_session(bytea, text) OWNER TO bridge_definer;

-- DELETE /v1/me/sessions/{id}: own sessions only; a foreign or unknown id returns false -> 404.
CREATE FUNCTION identity.revoke_own_session(p_subject_id uuid, p_session_id uuid)
  RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  WITH u AS (
    UPDATE identity.session
       SET status = 'REVOKED', revoked_at = now(), revoke_reason = 'USER_REVOKED', refresh_ciphertext = NULL,
           updated_at = now(), revision = revision + 1
     WHERE id = p_session_id AND subject_id = p_subject_id AND status = 'ACTIVE'
    RETURNING 1)
  SELECT EXISTS (SELECT 1 FROM u)
$$;
ALTER FUNCTION identity.revoke_own_session(uuid, uuid) OWNER TO bridge_definer;

-- Logout everywhere / MFA reset / subject disable: revoke all active sessions of a subject (optionally keep one).
CREATE FUNCTION identity.revoke_subject_sessions(p_subject_id uuid, p_reason text, p_except_session_id uuid)
  RETURNS integer LANGUAGE sql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  WITH u AS (
    UPDATE identity.session
       SET status = 'REVOKED', revoked_at = now(), revoke_reason = p_reason, refresh_ciphertext = NULL,
           updated_at = now(), revision = revision + 1
     WHERE subject_id = p_subject_id AND status = 'ACTIVE' AND id IS DISTINCT FROM p_except_session_id
    RETURNING 1)
  SELECT count(*)::integer FROM u
$$;
ALTER FUNCTION identity.revoke_subject_sessions(uuid, text, uuid) OWNER TO bridge_definer;

-- GET /v1/me/sessions (own only).
CREATE FUNCTION identity.list_subject_sessions(p_subject_id uuid)
  RETURNS TABLE (session_id uuid, session_kind text, created_at timestamptz, last_seen_at timestamptz, auth_time timestamptz,
                 amr text[], idp_id uuid, ip_prefix inet, absolute_expires_at timestamptz)
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  SELECT id, session_kind, created_at, last_seen_at, auth_time, amr, idp_id, ip_prefix, absolute_expires_at
    FROM identity.session
   WHERE subject_id = p_subject_id AND status = 'ACTIVE'
   ORDER BY last_seen_at DESC
   LIMIT 100
$$;
ALTER FUNCTION identity.list_subject_sessions(uuid) OWNER TO bridge_definer;

-- Single-flight server-side refresh (SEC-002-S10): the first request past the boundary takes a 10 s lock and gets
-- the ciphertext; concurrent requests get zero rows and proceed with the still-valid session (no waiting).
CREATE FUNCTION identity.try_begin_refresh(p_session_id uuid, p_owner text)
  RETURNS TABLE (refresh_ciphertext bytea, refresh_key_ref text)
  LANGUAGE sql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  UPDATE identity.session
     SET refresh_lock_owner = p_owner, refresh_lock_until = now() + interval '10 seconds'
   WHERE id = p_session_id AND status = 'ACTIVE'
     AND access_expires_at < now() + interval '60 seconds'
     AND (last_refresh_at IS NULL OR last_refresh_at < now() - interval '15 minutes' OR access_expires_at < now())
     AND (refresh_lock_until IS NULL OR refresh_lock_until < now())
  RETURNING refresh_ciphertext, refresh_key_ref
$$;
ALTER FUNCTION identity.try_begin_refresh(uuid, text) OWNER TO bridge_definer;

CREATE FUNCTION identity.complete_refresh(p_session_id uuid, p_owner text, p_refresh_ciphertext bytea, p_refresh_key_ref text,
                                          p_refresh_expires_at timestamptz, p_access_expires_at timestamptz)
  RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  WITH u AS (
    UPDATE identity.session
       SET refresh_ciphertext = p_refresh_ciphertext, refresh_key_ref = p_refresh_key_ref,
           refresh_expires_at = p_refresh_expires_at, access_expires_at = p_access_expires_at,
           last_refresh_at = now(), refresh_lock_owner = NULL, refresh_lock_until = NULL,
           updated_at = now(), revision = revision + 1
     WHERE id = p_session_id AND status = 'ACTIVE' AND refresh_lock_owner = p_owner
    RETURNING 1)
  SELECT EXISTS (SELECT 1 FROM u)
$$;
ALTER FUNCTION identity.complete_refresh(uuid, text, bytea, text, timestamptz, timestamptz) OWNER TO bridge_definer;

-- Cognito NotAuthorizedException -> revoke (IDP_REVOKED); transient failure -> release the lock only.
CREATE FUNCTION identity.fail_refresh(p_session_id uuid, p_owner text, p_idp_revoked boolean)
  RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  UPDATE identity.session
     SET status = CASE WHEN p_idp_revoked THEN 'REVOKED' ELSE status END,
         revoked_at = CASE WHEN p_idp_revoked THEN now() ELSE revoked_at END,
         revoke_reason = CASE WHEN p_idp_revoked THEN 'IDP_REVOKED' ELSE revoke_reason END,
         refresh_ciphertext = CASE WHEN p_idp_revoked THEN NULL ELSE refresh_ciphertext END,
         refresh_lock_owner = NULL, refresh_lock_until = NULL, updated_at = now(), revision = revision + 1
   WHERE id = p_session_id AND status = 'ACTIVE' AND refresh_lock_owner = p_owner
$$;
ALTER FUNCTION identity.fail_refresh(uuid, text, boolean) OWNER TO bridge_definer;

-- SEC-006-S11: membership removal clears the UI tenant hint on that subject's sessions (called in the removal tx).
CREATE FUNCTION identity.clear_active_tenant_hint(p_subject_id uuid, p_tenant_id uuid)
  RETURNS integer LANGUAGE sql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  WITH u AS (
    UPDATE identity.session SET active_tenant_id = NULL, updated_at = now(), revision = revision + 1
     WHERE subject_id = p_subject_id AND active_tenant_id = p_tenant_id AND status = 'ACTIVE'
    RETURNING 1)
  SELECT count(*)::integer FROM u
$$;
ALTER FUNCTION identity.clear_active_tenant_hint(uuid, uuid) OWNER TO bridge_definer;

-- GET /v1/auth/session: tenants the subject belongs to (ACTIVE and SUSPENDED memberships, non-DELETED tenants).
CREATE FUNCTION identity.list_subject_memberships(p_subject_id uuid)
  RETURNS TABLE (tenant_id uuid, tenant_slug text, tenant_display_name text, tenant_status text,
                 membership_id uuid, membership_status text, membership_kind text, permission_epoch bigint)
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  SELECT t.id, t.slug, t.display_name, t.status, m.id, m.status, m.kind, m.permission_epoch
    FROM identity.membership m
    JOIN identity.tenant t ON t.id = m.tenant_id
   WHERE m.subject_id = p_subject_id AND m.status IN ('ACTIVE', 'SUSPENDED') AND t.status <> 'DELETED'
   ORDER BY t.display_name
   LIMIT 200
$$;
ALTER FUNCTION identity.list_subject_memberships(uuid) OWNER TO bridge_definer;

-- Invitation lookup by token hash before tenant context (Appendix E step 3 then continues in tenant_transaction).
-- Returns a row only for PENDING, unexpired invitations; everything else -> zero rows -> uniform 410 TENANT_INVITE_INVALID.
CREATE FUNCTION identity.lookup_invitation(p_token_hash bytea)
  RETURNS TABLE (tenant_id uuid, invitation_id uuid, expires_at timestamptz)
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
  SELECT i.tenant_id, i.id, i.expires_at
    FROM identity.invitation i
    JOIN identity.tenant t ON t.id = i.tenant_id
   WHERE i.token_hash = p_token_hash AND i.status = 'PENDING' AND i.expires_at > now()
     AND t.status IN ('PROVISIONING', 'ACTIVE')
$$;
ALTER FUNCTION identity.lookup_invitation(bytea) OWNER TO bridge_definer;

-- Retention (bridge_retention): purge consumed/expired auth transactions after 24 h and revoked/expired sessions after 30 d.
CREATE FUNCTION identity.purge_auth_state()
  RETURNS TABLE (auth_transactions_deleted integer, sessions_deleted integer)
  LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path = pg_catalog, pg_temp
  AS $$
BEGIN
  DELETE FROM identity.auth_transaction WHERE expires_at < now() - interval '24 hours';
  GET DIAGNOSTICS auth_transactions_deleted = ROW_COUNT;
  DELETE FROM identity.session WHERE status IN ('REVOKED', 'EXPIRED') AND updated_at < now() - interval '30 days';
  GET DIAGNOSTICS sessions_deleted = ROW_COUNT;
  RETURN NEXT;
END $$;
ALTER FUNCTION identity.purge_auth_state() OWNER TO bridge_definer;

-- ---- Grants on functions (nothing else on these tables) -------------------------------------------------
REVOKE ALL ON FUNCTION identity.upsert_subject(uuid, text, text, text, text, boolean, text),
  identity.resolve_federated_subject(text, text, text), identity.discover_identity_provider(text),
  identity.begin_auth_transaction(bytea, bytea, bytea, bytea, text, text, text, text, uuid, uuid, uuid),
  identity.consume_auth_transaction(bytea, bytea),
  identity.create_session(uuid, bytea, uuid, text, uuid, uuid, text[], timestamptz, integer, timestamptz, bytea, text, timestamptz, timestamptz, bytea, inet),
  identity.resolve_session(bytea, uuid), identity.resolve_machine_client(text), identity.touch_session(uuid),
  identity.expire_session(uuid, text), identity.rotate_session(bytea, bytea, timestamptz, text[], uuid),
  identity.revoke_session(bytea, text), identity.revoke_own_session(uuid, uuid), identity.revoke_subject_sessions(uuid, text, uuid),
  identity.list_subject_sessions(uuid), identity.try_begin_refresh(uuid, text),
  identity.complete_refresh(uuid, text, bytea, text, timestamptz, timestamptz), identity.fail_refresh(uuid, text, boolean),
  identity.clear_active_tenant_hint(uuid, uuid), identity.list_subject_memberships(uuid), identity.lookup_invitation(bytea),
  identity.purge_auth_state()
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION identity.upsert_subject(uuid, text, text, text, text, boolean, text),
  identity.resolve_federated_subject(text, text, text), identity.discover_identity_provider(text),
  identity.begin_auth_transaction(bytea, bytea, bytea, bytea, text, text, text, text, uuid, uuid, uuid),
  identity.consume_auth_transaction(bytea, bytea),
  identity.create_session(uuid, bytea, uuid, text, uuid, uuid, text[], timestamptz, integer, timestamptz, bytea, text, timestamptz, timestamptz, bytea, inet),
  identity.resolve_session(bytea, uuid), identity.resolve_machine_client(text), identity.touch_session(uuid),
  identity.expire_session(uuid, text), identity.rotate_session(bytea, bytea, timestamptz, text[], uuid),
  identity.revoke_session(bytea, text), identity.revoke_own_session(uuid, uuid), identity.revoke_subject_sessions(uuid, text, uuid),
  identity.list_subject_sessions(uuid), identity.try_begin_refresh(uuid, text),
  identity.complete_refresh(uuid, text, bytea, text, timestamptz, timestamptz), identity.fail_refresh(uuid, text, boolean),
  identity.clear_active_tenant_hint(uuid, uuid), identity.list_subject_memberships(uuid), identity.lookup_invitation(bytea)
  TO bridge_api;
GRANT EXECUTE ON FUNCTION identity.resolve_session(bytea, uuid), identity.resolve_machine_client(text) TO bridge_broker;
GRANT EXECUTE ON FUNCTION identity.revoke_subject_sessions(uuid, text, uuid), identity.expire_session(uuid, text),
  identity.clear_active_tenant_hint(uuid, uuid) TO bridge_worker;
GRANT EXECUTE ON FUNCTION identity.purge_auth_state() TO bridge_retention;

INSERT INTO app.rls_allowlist (schema_name, object_name, exception, detail, reason, owner_task) VALUES
  ('identity', 'session', 'USING_TRUE_POLICY', 'definer_access', 'Definer-only table (class e)', 'SEC-002'),
  ('identity', 'session', 'NO_TENANT_COLUMN', 'session', 'Subject-scoped global session table', 'SEC-002'),
  ('identity', 'auth_transaction', 'USING_TRUE_POLICY', 'definer_access', 'Definer-only table (class e)', 'SEC-002'),
  ('identity', 'auth_transaction', 'NO_TENANT_COLUMN', 'auth_transaction', 'Pre-authentication table', 'SEC-002'),
  ('identity', 'upsert_subject', 'SECURITY_DEFINER', 'identity.upsert_subject', 'Callback subject resolution before tenant context', 'SEC-002'),
  ('identity', 'resolve_federated_subject', 'SECURITY_DEFINER', 'identity.resolve_federated_subject', 'Federated callback before tenant context', 'SEC-003'),
  ('identity', 'discover_identity_provider', 'SECURITY_DEFINER', 'identity.discover_identity_provider', 'Home-realm discovery (constant response shape)', 'SEC-003'),
  ('identity', 'begin_auth_transaction', 'SECURITY_DEFINER', 'identity.begin_auth_transaction', 'Pre-authentication', 'SEC-002'),
  ('identity', 'consume_auth_transaction', 'SECURITY_DEFINER', 'identity.consume_auth_transaction', 'Pre-authentication', 'SEC-002'),
  ('identity', 'create_session', 'SECURITY_DEFINER', 'identity.create_session', 'Definer-only session table', 'SEC-002'),
  ('identity', 'resolve_session', 'SECURITY_DEFINER', 'identity.resolve_session', 'Per-request authz state (Appendix F)', 'SEC-006'),
  ('identity', 'resolve_machine_client', 'SECURITY_DEFINER', 'identity.resolve_machine_client', 'Bearer client resolution (API-006)', 'API-006'),
  ('identity', 'touch_session', 'SECURITY_DEFINER', 'identity.touch_session', 'Definer-only session table', 'SEC-002'),
  ('identity', 'expire_session', 'SECURITY_DEFINER', 'identity.expire_session', 'Definer-only session table', 'SEC-002'),
  ('identity', 'rotate_session', 'SECURITY_DEFINER', 'identity.rotate_session', 'sid rotation', 'SEC-002'),
  ('identity', 'revoke_session', 'SECURITY_DEFINER', 'identity.revoke_session', 'Logout', 'SEC-002'),
  ('identity', 'revoke_own_session', 'SECURITY_DEFINER', 'identity.revoke_own_session', 'DELETE /v1/me/sessions/{id}', 'SEC-002'),
  ('identity', 'revoke_subject_sessions', 'SECURITY_DEFINER', 'identity.revoke_subject_sessions', 'Logout everywhere, MFA reset, subject disable', 'SEC-002'),
  ('identity', 'list_subject_sessions', 'SECURITY_DEFINER', 'identity.list_subject_sessions', 'GET /v1/me/sessions', 'SEC-002'),
  ('identity', 'try_begin_refresh', 'SECURITY_DEFINER', 'identity.try_begin_refresh', 'Single-flight refresh', 'SEC-002'),
  ('identity', 'complete_refresh', 'SECURITY_DEFINER', 'identity.complete_refresh', 'Single-flight refresh', 'SEC-002'),
  ('identity', 'fail_refresh', 'SECURITY_DEFINER', 'identity.fail_refresh', 'Single-flight refresh', 'SEC-002'),
  ('identity', 'clear_active_tenant_hint', 'SECURITY_DEFINER', 'identity.clear_active_tenant_hint', 'SEC-006-S11', 'SEC-006'),
  ('identity', 'list_subject_memberships', 'SECURITY_DEFINER', 'identity.list_subject_memberships', 'List my tenants', 'SEC-004'),
  ('identity', 'lookup_invitation', 'SECURITY_DEFINER', 'identity.lookup_invitation', 'Invitation acceptance before tenant context', 'CTL-003'),
  ('identity', 'purge_auth_state', 'SECURITY_DEFINER', 'identity.purge_auth_state', 'Retention of definer-only tables', 'SEC-002');

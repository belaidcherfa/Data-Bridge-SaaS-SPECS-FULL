-- contract=pg-rls-standard version=1 status=DRAFT owner_task=CTL-101 decisions=D-02,D-25 last_changed=2026-09-28
-- =====================================================================================================
-- PostgreSQL row-level-security standard for the Bridge control plane.
-- Normative source: SEC backlog Appendix E (G-SEC-10), CTL backlog CTL-101-S02..S04, SEC-004-S03.
-- Prose companion: docs/security/rls-standard.md. Template for new tables: contracts/postgres/_tenant_table_template.sql.
--
-- This file is reference DDL. Alembic revision 0001_roles (CTL-101-S02) must converge to it (schema-diff test).
-- It is applied BEFORE every other contracts/postgres/*.sql file because they reference its roles and
-- the app.* context functions. Apply order: _rls_standard.sql, identity.sql, tenant.sql, identity.auth.sql,
-- platform.sql, audit.sql, then other lanes' schemas.
--
-- Key facts this standard is built on (VERIFIED, postgresql.org/docs/current/ddl-rowsecurity.html, 2026-09-28):
--   * Referential-integrity checks (PK, UNIQUE, FK) always bypass row security -> composite keys that
--     include tenant_id everywhere; never a single-column FK or a global UNIQUE index on tenant data unless
--     explicitly designed (listed in app.rls_allowlist with its non-enumerating error mapping).
--   * Table owners bypass RLS unless FORCE ROW LEVEL SECURITY is set -> every table is ENABLE + FORCE.
--   * Policies TO <role> that do not name the current role do not apply -> default deny.
--   * set_config(name, value, true) is transaction-local; with autocommit it lasts one statement, so reads
--     return zero rows (fail closed). Engines with isolation_level="AUTOCOMMIT" are banned by lint anyway.
-- =====================================================================================================

-- -----------------------------------------------------------------------------------------------------
-- 1. Roles (Appendix E.1). All NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB. No runtime role owns objects.
--    Authentication for LOGIN roles: rds_iam (GRANT rds_iam TO <role>), passwords never stored.
--    Migrations make these statements idempotent (CREATE ROLE is guarded by a pg_roles lookup).
-- -----------------------------------------------------------------------------------------------------
CREATE ROLE bridge_owner NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT;
COMMENT ON ROLE bridge_owner IS 'Owns every schema, table, sequence and SECURITY INVOKER function. NOLOGIN. Subject to FORCE RLS like everybody else. owner_task=CTL-101';

CREATE ROLE bridge_definer NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT;
COMMENT ON ROLE bridge_definer IS 'Owns the allowlisted SECURITY DEFINER functions only (identity.resolve_session and friends). NOLOGIN; policies TO bridge_definer USING (true) exist only on the tables those functions read. owner_task=SEC-004';

CREATE ROLE bridge_migrator LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB INHERIT;
COMMENT ON ROLE bridge_migrator IS 'Used only by the one-off bridge-migrate ECS task (CTL-101-S01). Member of bridge_owner and bridge_definer to create/alter objects. Never used by API or workers. owner_task=CTL-101';
GRANT bridge_owner TO bridge_migrator;
GRANT bridge_definer TO bridge_migrator;

CREATE ROLE bridge_api LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT;
COMMENT ON ROLE bridge_api IS 'FastAPI application (tenant-scoped requests through tenant_transaction()). owner_task=CTL-101';
CREATE ROLE bridge_worker LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT;
COMMENT ON ROLE bridge_worker IS 'Control workers (planner, reapers, config-publisher, authz-provisioner, analysis/render workers, monitor evaluator, extraction account-cycle tasks via sync-api). Sets tenant context per unit of work; queue-class policies allow claims across tenants. owner_task=CTL-101';
CREATE ROLE bridge_dispatcher LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT;
COMMENT ON ROLE bridge_dispatcher IS 'Outbox dispatcher (CTL-004). SELECT/UPDATE on platform.outbox across tenants (allowlisted USING (true)); nothing else across tenants. owner_task=CTL-004';
CREATE ROLE bridge_broker LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT;
COMMENT ON ROLE bridge_broker IS 'Query broker authz re-reads (SEC-006-S05): EXECUTE on identity.resolve_session() only. owner_task=SEC-006';
CREATE ROLE bridge_audit_exporter LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT;
COMMENT ON ROLE bridge_audit_exporter IS 'Audit exporter (SEC-008-S06): SELECT audit.event across tenants, INSERT audit.event_export / audit.export_batch. owner_task=SEC-008';
CREATE ROLE bridge_retention LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT;
COMMENT ON ROLE bridge_retention IS 'Retention jobs: DELETE DONE outbox rows (7 d), expired idempotency rows (24 h), consumed_event rows (15 d); detaches verified audit partitions via bridge_owner-owned function. owner_task=CTL-004';
CREATE ROLE bridge_ops_ro LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT;
COMMENT ON ROLE bridge_ops_ro IS 'Read-only operator role for bridge-admin CLI (OPS-106). Sees only platform.* operational tables and catalog lint views; never tenant rows (no tenant policy targets it). owner_task=CTL-101';

-- Role-level GUC defaults (CTL-002-S07). Values are asserted by `SHOW` under each role in CI.
ALTER ROLE bridge_api SET statement_timeout = '5s';
ALTER ROLE bridge_api SET idle_in_transaction_session_timeout = '15s';
ALTER ROLE bridge_api SET lock_timeout = '2s';
ALTER ROLE bridge_worker SET statement_timeout = '60s';
ALTER ROLE bridge_worker SET idle_in_transaction_session_timeout = '15s';
ALTER ROLE bridge_worker SET lock_timeout = '2s';
ALTER ROLE bridge_dispatcher SET statement_timeout = '10s';
ALTER ROLE bridge_dispatcher SET idle_in_transaction_session_timeout = '15s';
ALTER ROLE bridge_dispatcher SET lock_timeout = '2s';
ALTER ROLE bridge_broker SET statement_timeout = '2s';
ALTER ROLE bridge_broker SET idle_in_transaction_session_timeout = '5s';
ALTER ROLE bridge_audit_exporter SET statement_timeout = '120s';
ALTER ROLE bridge_retention SET statement_timeout = '30s';
ALTER ROLE bridge_retention SET lock_timeout = '2s';
ALTER ROLE bridge_ops_ro SET statement_timeout = '30s';
ALTER ROLE bridge_ops_ro SET default_transaction_read_only = 'on';
ALTER ROLE bridge_migrator SET lock_timeout = '3s';   -- C-16: 3 s x 5 retries in the runner

-- No blanket default privileges: every migration grants per table through grant_table() (CTL-101-S02).
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- -----------------------------------------------------------------------------------------------------
-- 2. Context functions (Appendix E.2, E.5). Schema `app` holds only context helpers and lint views.
-- -----------------------------------------------------------------------------------------------------
CREATE SCHEMA app AUTHORIZATION bridge_owner;
COMMENT ON SCHEMA app IS 'Transaction context helpers and RLS catalog lint (SEC Appendix E). owner_task=CTL-101';

-- Tenant selected for this transaction; NULL when absent (-> zero rows). A malformed value raises
-- invalid_text_representation (22P02) which the API maps to 500 AUTHZ_CONTEXT_INVALID.
CREATE FUNCTION app.current_tenant() RETURNS uuid
  LANGUAGE sql STABLE PARALLEL SAFE
  AS $$ SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid $$;
COMMENT ON FUNCTION app.current_tenant() IS 'Tenant of the current transaction from GUC app.tenant_id (transaction-local). Inlined into policies. owner_task=CTL-101';

CREATE FUNCTION app.current_subject() RETURNS uuid
  LANGUAGE sql STABLE PARALLEL SAFE
  AS $$ SELECT NULLIF(current_setting('app.subject_id', true), '')::uuid $$;
COMMENT ON FUNCTION app.current_subject() IS 'Authenticated subject (identity.subject.id) of the current transaction; NULL for system work. owner_task=SEC-004';

CREATE FUNCTION app.current_membership() RETURNS uuid
  LANGUAGE sql STABLE PARALLEL SAFE
  AS $$ SELECT NULLIF(current_setting('app.membership_id', true), '')::uuid $$;
COMMENT ON FUNCTION app.current_membership() IS 'Membership of the subject in app.current_tenant(); NULL for system work. Used by audit and ownership predicates, never as the isolation key. owner_task=SEC-004';

CREATE FUNCTION app.is_platform_context() RETURNS boolean
  LANGUAGE sql STABLE PARALLEL SAFE
  AS $$ SELECT coalesce(current_setting('app.platform', true), '') = 'on' $$;
COMMENT ON FUNCTION app.is_platform_context() IS 'True only inside platform_transaction() (tenant-less platform events, heartbeats). Never true together with a tenant context. owner_task=CTL-101';

-- First statement of every tenant_transaction(): returns the PRIOR values (leak guard, E.5) and sets the new
-- ones transaction-locally. A non-empty prior value means a session-level set_config(..., false) leaked into
-- a pooled connection: the caller logs SECURITY_CONTEXT_LEAK and invalidates the connection.
CREATE FUNCTION app.begin_tenant_context(p_tenant_id uuid, p_subject_id uuid, p_membership_id uuid, p_request_id text)
  RETURNS TABLE (prior_tenant_id text, prior_subject_id text, prior_platform text)
  LANGUAGE plpgsql VOLATILE
  AS $$
BEGIN
  prior_tenant_id  := coalesce(current_setting('app.tenant_id', true), '');
  prior_subject_id := coalesce(current_setting('app.subject_id', true), '');
  prior_platform   := coalesce(current_setting('app.platform', true), '');
  IF p_tenant_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'AUTHZ_CONTEXT_INVALID';
  END IF;
  PERFORM set_config('app.tenant_id', p_tenant_id::text, true);
  PERFORM set_config('app.subject_id', coalesce(p_subject_id::text, ''), true);
  PERFORM set_config('app.membership_id', coalesce(p_membership_id::text, ''), true);
  PERFORM set_config('app.platform', '', true);
  PERFORM set_config('app.request_id', coalesce(left(p_request_id, 64), ''), true);
  RETURN NEXT;
END
$$;
COMMENT ON FUNCTION app.begin_tenant_context(uuid, uuid, uuid, text) IS 'tenant_transaction() entry point (CTL-101-S03). Returns prior GUC values for the leak guard (Appendix E.5). owner_task=CTL-101';

CREATE FUNCTION app.begin_platform_context(p_request_id text)
  RETURNS TABLE (prior_tenant_id text, prior_subject_id text, prior_platform text)
  LANGUAGE plpgsql VOLATILE
  AS $$
BEGIN
  prior_tenant_id  := coalesce(current_setting('app.tenant_id', true), '');
  prior_subject_id := coalesce(current_setting('app.subject_id', true), '');
  prior_platform   := coalesce(current_setting('app.platform', true), '');
  PERFORM set_config('app.tenant_id', '', true);
  PERFORM set_config('app.subject_id', '', true);
  PERFORM set_config('app.membership_id', '', true);
  PERFORM set_config('app.platform', 'on', true);
  PERFORM set_config('app.request_id', coalesce(left(p_request_id, 64), ''), true);
  RETURN NEXT;
END
$$;
COMMENT ON FUNCTION app.begin_platform_context(text) IS 'platform_transaction() entry point for tenant-less work (platform audit events, heartbeats). owner_task=CTL-101';

-- Subject-only context (before a tenant is selected: list-my-tenants, own session list).
CREATE FUNCTION app.begin_subject_context(p_subject_id uuid, p_request_id text)
  RETURNS TABLE (prior_tenant_id text, prior_subject_id text, prior_platform text)
  LANGUAGE plpgsql VOLATILE
  AS $$
BEGIN
  prior_tenant_id  := coalesce(current_setting('app.tenant_id', true), '');
  prior_subject_id := coalesce(current_setting('app.subject_id', true), '');
  prior_platform   := coalesce(current_setting('app.platform', true), '');
  IF p_subject_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'AUTHZ_CONTEXT_INVALID';
  END IF;
  PERFORM set_config('app.tenant_id', '', true);
  PERFORM set_config('app.subject_id', p_subject_id::text, true);
  PERFORM set_config('app.membership_id', '', true);
  PERFORM set_config('app.platform', '', true);
  PERFORM set_config('app.request_id', coalesce(left(p_request_id, 64), ''), true);
  RETURN NEXT;
END
$$;
COMMENT ON FUNCTION app.begin_subject_context(uuid, text) IS 'subject_transaction(): subject-scoped global tables only (Appendix E.3 b). owner_task=SEC-004';

GRANT USAGE ON SCHEMA app TO bridge_api, bridge_worker, bridge_dispatcher, bridge_broker, bridge_audit_exporter, bridge_retention, bridge_ops_ro, bridge_definer;
GRANT EXECUTE ON FUNCTION app.current_tenant(), app.current_subject(), app.current_membership(), app.is_platform_context()
  TO bridge_api, bridge_worker, bridge_dispatcher, bridge_broker, bridge_audit_exporter, bridge_retention, bridge_ops_ro, bridge_definer;
GRANT EXECUTE ON FUNCTION app.begin_tenant_context(uuid, uuid, uuid, text), app.begin_subject_context(uuid, text)
  TO bridge_api, bridge_worker;
GRANT EXECUTE ON FUNCTION app.begin_platform_context(text) TO bridge_api, bridge_worker, bridge_dispatcher, bridge_audit_exporter, bridge_retention;

-- -----------------------------------------------------------------------------------------------------
-- 3. Policy templates per table class (Appendix E.3). Copy verbatim; replace <schema>.<table>.
--    Every template starts with:  ALTER TABLE <t> ENABLE ROW LEVEL SECURITY; ALTER TABLE <t> FORCE ROW LEVEL SECURITY;
--
--  (a) TENANT table (default; tenant_id NOT NULL, PK (tenant_id, id)):
--      CREATE POLICY tenant_isolation ON <t> AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
--        USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
--
--  (b) SUBJECT-SCOPED GLOBAL table (identity.subject, identity.tenant, identity.membership):
--      tenant template (a) plus a SELECT-only policy for "list my tenants":
--      CREATE POLICY subject_self ON <t> AS PERMISSIVE FOR SELECT TO bridge_api
--        USING (subject_id = app.current_subject());
--
--  (c) QUEUE table (platform.outbox, platform.lease, sync.*_jobs, report.report_job, analytics.*_job):
--      tenant template (a) for producers plus role-targeted claim policies, allowlisted in app.rls_allowlist:
--      CREATE POLICY queue_claim ON <t> AS PERMISSIVE FOR SELECT TO bridge_dispatcher USING (true);
--      CREATE POLICY queue_update ON <t> AS PERMISSIVE FOR UPDATE TO bridge_dispatcher USING (true) WITH CHECK (true);
--      A claim returns only IDs/tokens; the handler then opens tenant_transaction(<row.tenant_id>) for the work.
--
--  (d) APPEND-ONLY table (audit.event): INSERT tenant-checked (or platform context for tenant_id NULL),
--      SELECT tenant-checked for bridge_api, SELECT USING (true) TO bridge_audit_exporter; no UPDATE/DELETE
--      grants; trigger audit.forbid_mutation() raises on UPDATE/DELETE for every role.
--
--  (e) DEFINER-ONLY table (identity.session, identity.auth_transaction): no grants to runtime roles;
--      CREATE POLICY definer_access ON <t> AS PERMISSIVE FOR ALL TO bridge_definer USING (true) WITH CHECK (true);
--      accessed exclusively through SECURITY DEFINER functions owned by bridge_definer with
--      SET search_path = pg_catalog, pg_temp and fully qualified names.
--
--  (f) PLATFORM GLOBAL table without tenant data (platform.component_heartbeat, platform.config_kind,
--      platform.backfill_job): explicit per-role policies; listed in app.rls_allowlist with reason.
-- -----------------------------------------------------------------------------------------------------

-- -----------------------------------------------------------------------------------------------------
-- 4. Forbidden patterns (enforced by lint below, semgrep rules in .semgrep/control_db.yml and code review):
--    F1 table in a tenant schema with tenant_id but without ENABLE+FORCE RLS or without a policy
--    F2 runtime role (bridge_api|worker|dispatcher|broker|audit_exporter|retention|ops_ro) owning any object
--    F3 any role with rolbypassrls or rolsuper other than the RDS master (rds_superuser members excluded by name)
--    F4 USING (true) / WITH CHECK (true) policy not listed in app.rls_allowlist
--    F5 FK on a tenant table whose column list does not include tenant_id
--    F6 UNIQUE/PK index on a tenant table not leading with tenant_id, unless allowlisted (designed global keys)
--    F7 SECURITY DEFINER function not owned by bridge_definer, not allowlisted, or without a fixed search_path
--    F8 session-level set_config(..., false) / SET (without LOCAL) of app.* in application code (semgrep)
--    F9 isolation_level="AUTOCOMMIT" engines, AsyncSession( outside packages/control_db/tx.py (semgrep)
--    F10 PostgreSQL ENUM types (use text + CHECK generated from contracts/state-machines/*.yaml)
-- -----------------------------------------------------------------------------------------------------

-- 5. Allowlist of intentional exceptions (F4, F6, F7). Seeded by the owning migrations; reviewed by Security.
CREATE TABLE app.rls_allowlist (
  schema_name   text NOT NULL,
  object_name   text NOT NULL,
  exception     text NOT NULL CHECK (exception IN ('USING_TRUE_POLICY', 'GLOBAL_UNIQUE', 'SECURITY_DEFINER', 'NO_TENANT_COLUMN')),
  detail        text NOT NULL,          -- policy name, index name or function signature
  reason        text NOT NULL,
  owner_task    text NOT NULL CHECK (owner_task ~ '^[A-Z]{2,3}-[0-9]{3}$'),
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT rls_allowlist_pk PRIMARY KEY (schema_name, object_name, exception, detail)
);
ALTER TABLE app.rls_allowlist OWNER TO bridge_owner;
COMMENT ON TABLE app.rls_allowlist IS 'Reviewed exceptions to the RLS lint. Adding a row requires Security review in the PR. owner_task=CTL-101';
GRANT SELECT ON app.rls_allowlist TO bridge_ops_ro;

-- 6. Catalog lint (Appendix E.6). CI runs `SELECT * FROM app.rls_lint_violation` after `alembic upgrade head`;
--    any row fails the build. Nightly the same view runs read-only in production (bridge_ops_ro) and pages.
CREATE VIEW app.rls_lint_violation AS
WITH tenant_schemas AS (
  SELECT unnest(ARRAY['identity','tenant','connection','sync','governance','allocation','finance','monitor','report',
                      'workflow','analytics','onboarding','commercial','privacy','support','audit','platform','ops','saas']) AS nspname
),
tables AS (
  SELECT c.oid, n.nspname, c.relname, c.relrowsecurity, c.relforcerowsecurity, c.relkind,
         pg_get_userbyid(c.relowner) AS owner,
         EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped) AS has_tenant_id
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind IN ('r', 'p') AND n.nspname IN (SELECT nspname FROM tenant_schemas)
    AND NOT c.relispartition
)
SELECT 'F1_RLS_NOT_FORCED'::text AS rule, t.nspname AS schema_name, t.relname AS object_name, 'ENABLE+FORCE RLS missing'::text AS detail
  FROM tables t WHERE NOT (t.relrowsecurity AND t.relforcerowsecurity)
UNION ALL
SELECT 'F1_NO_POLICY', t.nspname, t.relname, 'table has no policy'
  FROM tables t WHERE NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = t.oid)
UNION ALL
SELECT 'F2_RUNTIME_ROLE_OWNS_OBJECT', n.nspname, c.relname, pg_get_userbyid(c.relowner)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE pg_get_userbyid(c.relowner) IN ('bridge_api','bridge_worker','bridge_dispatcher','bridge_broker','bridge_audit_exporter','bridge_retention','bridge_ops_ro','bridge_migrator')
UNION ALL
SELECT 'F3_BYPASSRLS_ROLE', NULL, r.rolname, 'rolbypassrls or rolsuper'
  FROM pg_roles r
 WHERE (r.rolbypassrls OR r.rolsuper) AND r.rolname LIKE 'bridge\_%'
UNION ALL
SELECT 'F4_USING_TRUE_NOT_ALLOWLISTED', t.nspname, t.relname, p.polname
  FROM tables t JOIN pg_policy p ON p.polrelid = t.oid
 WHERE (pg_get_expr(p.polqual, p.polrelid) = 'true' OR pg_get_expr(p.polwithcheck, p.polrelid) = 'true')
   AND NOT EXISTS (SELECT 1 FROM app.rls_allowlist w
                    WHERE w.schema_name = t.nspname AND w.object_name = t.relname
                      AND w.exception = 'USING_TRUE_POLICY' AND w.detail = p.polname)
UNION ALL
SELECT 'F5_FK_WITHOUT_TENANT', t.nspname, t.relname, con.conname
  FROM tables t JOIN pg_constraint con ON con.conrelid = t.oid AND con.contype = 'f'
 WHERE t.has_tenant_id
   -- only FKs that reference another tenant-bearing table; FKs to global tables (identity.subject) are legal
   AND EXISTS (SELECT 1 FROM pg_attribute ra
                WHERE ra.attrelid = con.confrelid AND ra.attname = 'tenant_id' AND NOT ra.attisdropped)
   AND NOT EXISTS (SELECT 1 FROM pg_attribute a
                    WHERE a.attrelid = t.oid AND a.attname = 'tenant_id' AND a.attnum = ANY (con.conkey))
   AND NOT EXISTS (SELECT 1 FROM app.rls_allowlist w
                    WHERE w.schema_name = t.nspname AND w.object_name = t.relname
                      AND w.exception = 'GLOBAL_UNIQUE' AND w.detail = con.conname)
UNION ALL
SELECT 'F6_UNIQUE_NOT_TENANT_LEADING', t.nspname, t.relname, ic.relname
  FROM tables t
  JOIN pg_index i ON i.indrelid = t.oid AND i.indisunique
  JOIN pg_class ic ON ic.oid = i.indexrelid
 WHERE t.has_tenant_id
   AND (SELECT a.attname FROM pg_attribute a WHERE a.attrelid = t.oid AND a.attnum = i.indkey[0]) IS DISTINCT FROM 'tenant_id'
   AND NOT EXISTS (SELECT 1 FROM app.rls_allowlist w
                    WHERE w.schema_name = t.nspname AND w.object_name = t.relname
                      AND w.exception = 'GLOBAL_UNIQUE' AND w.detail = ic.relname)
UNION ALL
SELECT 'F7_SECURITY_DEFINER', n.nspname, p.proname, pg_get_userbyid(p.proowner)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.prosecdef
   AND n.nspname IN (SELECT nspname FROM tenant_schemas UNION SELECT 'app')
   AND (pg_get_userbyid(p.proowner) <> 'bridge_definer'
        OR p.proconfig IS NULL
        OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg LIKE 'search_path=%')
        OR NOT EXISTS (SELECT 1 FROM app.rls_allowlist w
                        WHERE w.schema_name = n.nspname AND w.object_name = p.proname AND w.exception = 'SECURITY_DEFINER'))
UNION ALL
SELECT 'F10_ENUM_TYPE', n.nspname, t.typname, 'PostgreSQL enum type'
  FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
 WHERE t.typtype = 'e' AND n.nspname IN (SELECT nspname FROM tenant_schemas);
ALTER VIEW app.rls_lint_violation OWNER TO bridge_owner;
COMMENT ON VIEW app.rls_lint_violation IS 'RLS catalog lint (Appendix E.6). Zero rows = compliant. Run in CI after migrations and nightly in production. owner_task=CTL-101';
GRANT SELECT ON app.rls_lint_violation TO bridge_ops_ro;

-- -----------------------------------------------------------------------------------------------------
-- 7. Mandatory generated tests per tenant table (Appendix E.7) - implemented in tests/security/rls/test_generated.py:
--   T1 no context:        SELECT count(*) = 0; INSERT -> SQLSTATE 42501
--   T2 context A:         B rows invisible; UPDATE ... WHERE id = <B id> affects 0 rows; DELETE affects 0 rows
--   T3 composite FK to B: 23503 with a message byte-identical to the nonexistent-parent case
--   T4 pool reuse:        pool size 1: tx(A) -> tx(B) -> tx(no context) = A only / B only / 0 rows
--   T5 leak guard:        session-level set_config('app.tenant_id', A, false) is detected by the next
--                         app.begin_tenant_context() (prior value non-empty) -> SECURITY_CONTEXT_LEAK + reconnect
-- -----------------------------------------------------------------------------------------------------

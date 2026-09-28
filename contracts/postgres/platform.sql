-- contract=pg-platform-kernel version=1 status=DRAFT owner_task=CTL-101 decisions=D-04,D-07,D-25 last_changed=2026-09-28
-- =====================================================================================================
-- Schema `platform`: control-DB kernel (CTL-101-S05/S06, CTL-002-S02/S03, CTL-004-S02..S08, CTL-005-S03).
-- Normative sources: CTL backlog Appendix A (outbox, idempotency, leases), Appendix C (heartbeats/backfill),
-- Appendix G (config publication). Owner lane K2. `platform.flags` (feature flags) is K9's (REL-102) and is
-- NOT in this file.
--
-- Naming: CONVENTIONS §10 requires singular table nouns. Backlog names map as follows:
--   platform.idempotency_requests -> platform.idempotency_request
--   platform.leases               -> platform.lease
--   platform.consumed_events      -> platform.consumed_event
--   platform.component_heartbeats -> platform.component_heartbeat
--   platform.backfill_jobs        -> platform.backfill_job
--   governance.config_publications (CTL-005-S03) -> platform.config_publication (config publication tracking is
--     kernel infrastructure owned by K2; governance.* is K7's file)
-- Status CHECK sets are generated from contracts/state-machines/{outbox_event,config_publication}.yaml.
-- Apply after _rls_standard.sql and identity.sql (config_publication references identity.approval).
-- =====================================================================================================

CREATE SCHEMA platform AUTHORIZATION bridge_owner;
COMMENT ON SCHEMA platform IS 'Control-DB kernel: outbox, idempotency, leases, consumed events, heartbeats, backfill jobs, config publication tracking. owner_task=CTL-101';
GRANT USAGE ON SCHEMA platform TO bridge_api, bridge_worker, bridge_dispatcher, bridge_broker, bridge_audit_exporter, bridge_retention, bridge_ops_ro;

-- -----------------------------------------------------------------------------------------------------
-- Sequences
-- -----------------------------------------------------------------------------------------------------
CREATE SEQUENCE platform.lease_token_seq AS bigint START WITH 1 INCREMENT BY 1 NO CYCLE;
ALTER SEQUENCE platform.lease_token_seq OWNER TO bridge_owner;
COMMENT ON SEQUENCE platform.lease_token_seq IS 'Monotonic fencing/lease tokens for outbox leases and platform.lease (Appendix A.2/A.4). Never reset. owner_task=CTL-004';
GRANT USAGE ON SEQUENCE platform.lease_token_seq TO bridge_worker, bridge_dispatcher;

-- -----------------------------------------------------------------------------------------------------
-- platform.aggregate_sequence - per-aggregate monotonic sequence for outbox ordering (aggregate_seq) and the
-- envelope field aggregate_version. One row per aggregate; the UPDATE row lock serializes emitters of one
-- aggregate (they already hold the aggregate's row lock in the business transaction).
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE platform.aggregate_sequence (
  aggregate_type  text        NOT NULL CHECK (aggregate_type ~ '^[a-z][a-z0-9_]{0,62}$'),
  aggregate_id    text        NOT NULL CHECK (char_length(aggregate_id) BETWEEN 1 AND 128),
  tenant_id       uuid        NULL,         -- NULL only for platform aggregates (platform_transaction)
  last_seq        bigint      NOT NULL DEFAULT 0 CHECK (last_seq >= 0),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT aggregate_sequence_pk PRIMARY KEY (aggregate_type, aggregate_id)
);
ALTER TABLE platform.aggregate_sequence OWNER TO bridge_owner;
COMMENT ON TABLE platform.aggregate_sequence IS 'Per-aggregate event sequence (outbox aggregate_seq / envelope aggregate_version). Aggregate IDs are UUIDv7 or deterministic keys (e.g. <tenant_id>:<config_kind>), globally unique, so the PK does not lead with tenant_id (allowlisted). owner_task=CTL-101';
ALTER TABLE platform.aggregate_sequence ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform.aggregate_sequence FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON platform.aggregate_sequence AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant() OR (tenant_id IS NULL AND app.is_platform_context()))
  WITH CHECK (tenant_id = app.current_tenant() OR (tenant_id IS NULL AND app.is_platform_context()));
GRANT SELECT, INSERT, UPDATE ON platform.aggregate_sequence TO bridge_api, bridge_worker;

-- Returns the next aggregate_seq. SECURITY INVOKER: RLS applies (a foreign tenant's aggregate row is invisible,
-- and inserting it fails WITH CHECK).
CREATE FUNCTION platform.next_aggregate_seq(p_aggregate_type text, p_aggregate_id text, p_tenant_id uuid)
  RETURNS bigint LANGUAGE sql VOLATILE
  AS $$
  INSERT INTO platform.aggregate_sequence AS s (aggregate_type, aggregate_id, tenant_id, last_seq, updated_at)
  VALUES (p_aggregate_type, p_aggregate_id, p_tenant_id, 1, now())
  ON CONFLICT (aggregate_type, aggregate_id)
  DO UPDATE SET last_seq = s.last_seq + 1, updated_at = now()
  RETURNING last_seq
$$;
ALTER FUNCTION platform.next_aggregate_seq(text, text, uuid) OWNER TO bridge_owner;
GRANT EXECUTE ON FUNCTION platform.next_aggregate_seq(text, text, uuid) TO bridge_api, bridge_worker;

-- -----------------------------------------------------------------------------------------------------
-- platform.outbox - transactional outbox (Appendix A.1). Rows are written by emit_event() in the business
-- transaction; the envelope published to SQS is rebuilt from these columns (contracts/common/event-envelope).
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE platform.outbox (
  event_id          uuid        NOT NULL,                  -- UUIDv7; envelope event_id; SQS MessageDeduplicationId
  tenant_id         uuid        NULL,                      -- NULL only for platform events (catalog tenant_scoped=false)
  aggregate_type    text        NOT NULL CHECK (aggregate_type ~ '^[a-z][a-z0-9_]{0,62}$'),
  aggregate_id      text        NOT NULL CHECK (char_length(aggregate_id) BETWEEN 1 AND 128),
  aggregate_seq     bigint      NOT NULL CHECK (aggregate_seq >= 1),   -- = envelope aggregate_version
  event_type        text        NOT NULL CHECK (event_type ~ '^bridge\.[a-z_]+\.[a-z_]+\.[a-z_]+$'),
  event_version     smallint    NOT NULL CHECK (event_version >= 1),   -- = envelope schema_version
  ordering          text        NOT NULL CHECK (ordering IN ('AGGREGATE', 'NONE')),
  transport         text        NOT NULL CHECK (transport IN ('SQS_FIFO', 'SQS_STANDARD', 'INTERNAL')),
  destination       text        NOT NULL CHECK (destination ~ '^[a-z][a-z0-9-]{1,62}$'),  -- logical queue from the catalog route
  privacy           text        NOT NULL CHECK (privacy IN ('NONE', 'CUSTOMER_METADATA', 'PERSONAL')),
  producer          text        NOT NULL CHECK (producer ~ '^[a-z0-9-]+@[0-9A-Za-z.+-]+$'),
  occurred_at       timestamptz NOT NULL,
  correlation_id    text        NOT NULL CHECK (char_length(correlation_id) BETWEEN 1 AND 128),
  causation_id      text        NULL CHECK (causation_id IS NULL OR char_length(causation_id) <= 128),
  traceparent       text        NULL CHECK (traceparent IS NULL OR traceparent ~ '^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$'),
  payload           jsonb       NOT NULL CHECK (jsonb_typeof(payload) = 'object' AND pg_column_size(payload) <= 65536),
  created_at        timestamptz NOT NULL DEFAULT now(),
  available_at      timestamptz NOT NULL DEFAULT now(),
  status            text        NOT NULL DEFAULT 'PENDING'
                    CHECK (status IN ('PENDING', 'LEASED', 'DONE', 'DEAD', 'DISCARDED')),
  attempts          integer     NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  max_attempts      integer     NOT NULL DEFAULT 12 CHECK (max_attempts BETWEEN 1 AND 100),
  lease_owner       text        NULL,
  lease_token       bigint      NULL,
  lease_expires_at  timestamptz NULL,
  last_error_class  text        NULL CHECK (last_error_class IS NULL OR last_error_class ~ '^[A-Z][A-Z0-9_]{1,63}$'),
  last_error_at     timestamptz NULL,
  completed_at      timestamptz NULL,
  dead_at           timestamptz NULL,
  redrive_count     integer     NOT NULL DEFAULT 0 CHECK (redrive_count >= 0),
  discarded_at      timestamptz NULL,
  discarded_by      text        NULL,                      -- operator id (two-operator approval, CTL-004-S06)
  discard_reason    text        NULL,
  CONSTRAINT outbox_pk PRIMARY KEY (event_id),
  CONSTRAINT outbox_aggregate_seq_uq UNIQUE (aggregate_type, aggregate_id, aggregate_seq),
  CONSTRAINT outbox_lease_consistency CHECK ((status = 'LEASED') = (lease_token IS NOT NULL AND lease_expires_at IS NOT NULL AND lease_owner IS NOT NULL)),
  CONSTRAINT outbox_done_consistency CHECK ((status = 'DONE') = (completed_at IS NOT NULL)),
  CONSTRAINT outbox_discard_consistency CHECK ((status = 'DISCARDED') = (discarded_at IS NOT NULL AND discarded_by IS NOT NULL AND discard_reason IS NOT NULL)),
  CONSTRAINT outbox_fifo_requires_aggregate_order CHECK (transport <> 'SQS_FIFO' OR ordering = 'AGGREGATE')
);
ALTER TABLE platform.outbox OWNER TO bridge_owner;
COMMENT ON TABLE platform.outbox IS 'Transactional outbox (CTL-101-S05, CTL-004). At-least-once, per-aggregate ordered for ordering=AGGREGATE. Payload = IDs and versions only (<=64 KB), validated against contracts/events/schemas/<type>.v<N>.schema.json before insert. DONE rows deleted after 7 days; DEAD kept until redriven/discarded. owner_task=CTL-101';
COMMENT ON COLUMN platform.outbox.payload IS 'Event payload; privacy per column privacy. PERSONAL payloads only for event types classified PERSONAL in the catalog. x-privacy: per catalog';
COMMENT ON COLUMN platform.outbox.aggregate_seq IS 'From platform.next_aggregate_seq(); head-of-line ordering key for ordering=AGGREGATE (Appendix A.2).';

CREATE INDEX outbox_ready ON platform.outbox (available_at) WHERE status = 'PENDING';
CREATE INDEX outbox_open_aggregate ON platform.outbox (aggregate_type, aggregate_id, aggregate_seq) WHERE status IN ('PENDING', 'LEASED', 'DEAD');
CREATE INDEX outbox_lease_expiry ON platform.outbox (lease_expires_at) WHERE status = 'LEASED';
CREATE INDEX outbox_done_retention ON platform.outbox (completed_at) WHERE status = 'DONE';
CREATE INDEX outbox_dead ON platform.outbox (dead_at) WHERE status = 'DEAD';
CREATE INDEX outbox_tenant_created ON platform.outbox (tenant_id, created_at) WHERE tenant_id IS NOT NULL;

ALTER TABLE platform.outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform.outbox FORCE ROW LEVEL SECURITY;
-- producers: insert only into the current tenant (or platform context for tenant-less events)
CREATE POLICY producer_insert ON platform.outbox AS PERMISSIVE FOR INSERT TO bridge_api, bridge_worker
  WITH CHECK (tenant_id = app.current_tenant() OR (tenant_id IS NULL AND app.is_platform_context()));
-- producers may read their own tenant's rows (test/diagnostics); never other tenants
CREATE POLICY producer_select ON platform.outbox AS PERMISSIVE FOR SELECT TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant());
-- dispatcher: queue class (allowlisted)
CREATE POLICY queue_claim ON platform.outbox AS PERMISSIVE FOR SELECT TO bridge_dispatcher USING (true);
CREATE POLICY queue_update ON platform.outbox AS PERMISSIVE FOR UPDATE TO bridge_dispatcher USING (true) WITH CHECK (true);
-- retention: DONE rows older than 7 days, DISCARDED older than 30 days
CREATE POLICY retention_delete ON platform.outbox AS PERMISSIVE FOR DELETE TO bridge_retention
  USING ((status = 'DONE' AND completed_at < now() - interval '7 days') OR (status = 'DISCARDED' AND discarded_at < now() - interval '30 days'));
CREATE POLICY retention_select ON platform.outbox AS PERMISSIVE FOR SELECT TO bridge_retention
  USING (status IN ('DONE', 'DISCARDED'));
-- operators see backlog metadata only through the view below
GRANT INSERT, SELECT ON platform.outbox TO bridge_api, bridge_worker;
GRANT SELECT, UPDATE ON platform.outbox TO bridge_dispatcher;
GRANT SELECT, DELETE ON platform.outbox TO bridge_retention;

-- Operator visibility without payloads (bridge-admin outbox dead list; RB: outbox backlog): column-level grant
-- (payload excluded) + allowlisted read policy; the view is security_invoker so RLS/privileges of the caller apply.
CREATE POLICY ops_read ON platform.outbox AS PERMISSIVE FOR SELECT TO bridge_ops_ro USING (true);
GRANT SELECT (event_id, tenant_id, aggregate_type, aggregate_id, aggregate_seq, event_type, event_version, ordering,
              transport, destination, status, attempts, max_attempts, created_at, available_at, last_error_class,
              last_error_at, dead_at, redrive_count) ON platform.outbox TO bridge_ops_ro;
CREATE VIEW platform.outbox_ops WITH (security_invoker = true) AS
  SELECT event_id, tenant_id, aggregate_type, aggregate_id, aggregate_seq, event_type, event_version, ordering,
         transport, destination, status, attempts, max_attempts, created_at, available_at, last_error_class,
         last_error_at, dead_at, redrive_count
    FROM platform.outbox;
ALTER VIEW platform.outbox_ops OWNER TO bridge_owner;
COMMENT ON VIEW platform.outbox_ops IS 'Payload-free outbox view for operators (security_invoker; payload column is not granted to bridge_ops_ro). owner_task=CTL-004';
GRANT SELECT ON platform.outbox_ops TO bridge_ops_ro;

-- Claim (Appendix A.2): per-aggregate head-of-line for ordering=AGGREGATE. A lower-seq PENDING row locked by
-- another dispatcher is still visible as PENDING to NOT EXISTS, so its successor cannot be claimed concurrently.
-- A DEAD or LEASED predecessor blocks its aggregate by design (ordering integrity) and pages.
CREATE FUNCTION platform.outbox_claim(p_batch_size integer, p_owner text, p_lease_seconds integer DEFAULT 60)
  RETURNS TABLE (event_id uuid, lease_token bigint, tenant_id uuid, event_type text, event_version smallint,
                 aggregate_type text, aggregate_id text, aggregate_seq bigint, transport text, destination text)
  LANGUAGE sql VOLATILE
  AS $$
  WITH c AS (
    SELECT o.event_id
      FROM platform.outbox o
     WHERE o.status = 'PENDING' AND o.available_at <= now()
       AND (o.ordering = 'NONE' OR NOT EXISTS (
             SELECT 1 FROM platform.outbox p
              WHERE p.aggregate_type = o.aggregate_type AND p.aggregate_id = o.aggregate_id
                AND p.aggregate_seq < o.aggregate_seq AND p.status IN ('PENDING', 'LEASED', 'DEAD')))
     ORDER BY o.available_at, o.aggregate_seq
     LIMIT least(greatest(p_batch_size, 1), 500)
     FOR UPDATE SKIP LOCKED)
  UPDATE platform.outbox o
     SET status = 'LEASED', lease_owner = p_owner, lease_token = nextval('platform.lease_token_seq'),
         lease_expires_at = now() + make_interval(secs => p_lease_seconds), attempts = o.attempts + 1
    FROM c
   WHERE o.event_id = c.event_id
  RETURNING o.event_id, o.lease_token, o.tenant_id, o.event_type, o.event_version, o.aggregate_type, o.aggregate_id,
            o.aggregate_seq, o.transport, o.destination
$$;
ALTER FUNCTION platform.outbox_claim(integer, text, integer) OWNER TO bridge_owner;
GRANT EXECUTE ON FUNCTION platform.outbox_claim(integer, text, integer) TO bridge_dispatcher;

-- Complete: 0 rows = stale lease (log OUTBOX_STALE_LEASE, no-op).
CREATE FUNCTION platform.outbox_complete(p_event_id uuid, p_lease_token bigint)
  RETURNS boolean LANGUAGE sql VOLATILE
  AS $$
  WITH u AS (
    UPDATE platform.outbox
       SET status = 'DONE', completed_at = now(), lease_owner = NULL, lease_token = NULL, lease_expires_at = NULL
     WHERE event_id = p_event_id AND lease_token = p_lease_token AND status = 'LEASED'
    RETURNING 1)
  SELECT EXISTS (SELECT 1 FROM u)
$$;
ALTER FUNCTION platform.outbox_complete(uuid, bigint) OWNER TO bridge_owner;
GRANT EXECUTE ON FUNCTION platform.outbox_complete(uuid, bigint) TO bridge_dispatcher;

-- Fail: backoff min(5 s * 2^attempts, 3600 s) +/-20 % jitter; PERMANENT or attempts >= max -> DEAD.
CREATE FUNCTION platform.outbox_fail(p_event_id uuid, p_lease_token bigint, p_failure_kind text, p_error_class text)
  RETURNS text LANGUAGE sql VOLATILE
  AS $$
  UPDATE platform.outbox
     SET status = CASE WHEN p_failure_kind = 'PERMANENT' OR attempts >= max_attempts THEN 'DEAD' ELSE 'PENDING' END,
         dead_at = CASE WHEN p_failure_kind = 'PERMANENT' OR attempts >= max_attempts THEN now() ELSE NULL END,
         available_at = now() + make_interval(secs => least(5 * power(2, attempts), 3600) * (0.8 + random() * 0.4)),
         last_error_class = p_error_class, last_error_at = now(),
         lease_owner = NULL, lease_token = NULL, lease_expires_at = NULL
   WHERE event_id = p_event_id AND lease_token = p_lease_token AND status = 'LEASED'
     AND p_failure_kind IN ('RETRYABLE', 'PERMANENT')
  RETURNING status
$$;
ALTER FUNCTION platform.outbox_fail(uuid, bigint, text, text) OWNER TO bridge_owner;
GRANT EXECUTE ON FUNCTION platform.outbox_fail(uuid, bigint, text, text) TO bridge_dispatcher;

-- Reap (every 10 s): expired leases return to PENDING (attempt already counted at claim).
CREATE FUNCTION platform.outbox_reap() RETURNS integer LANGUAGE sql VOLATILE
  AS $$
  WITH u AS (
    UPDATE platform.outbox
       SET status = 'PENDING', lease_owner = NULL, lease_token = NULL, lease_expires_at = NULL,
           last_error_class = 'LEASE_EXPIRED', last_error_at = now()
     WHERE status = 'LEASED' AND lease_expires_at < now()
    RETURNING 1)
  SELECT count(*)::integer FROM u
$$;
ALTER FUNCTION platform.outbox_reap() OWNER TO bridge_owner;
GRANT EXECUTE ON FUNCTION platform.outbox_reap() TO bridge_dispatcher;

-- -----------------------------------------------------------------------------------------------------
-- platform.consumed_event - consumer-side deduplication for SQS standard queues (and defensive on FIFO).
-- consume_once(consumer, event_id): INSERT ... ON CONFLICT DO NOTHING in the consumer's own transaction;
-- 0 rows inserted = already processed -> ack and skip.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE platform.consumed_event (
  consumer     text        NOT NULL CHECK (consumer ~ '^[a-z][a-z0-9-]{1,62}$'),
  event_id     uuid        NOT NULL,
  tenant_id    uuid        NULL,
  event_type   text        NOT NULL,
  consumed_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT consumed_event_pk PRIMARY KEY (consumer, event_id)
);
ALTER TABLE platform.consumed_event OWNER TO bridge_owner;
COMMENT ON TABLE platform.consumed_event IS 'Consumer dedup ledger (CONVENTIONS §8; CTL-004-S03). Rows older than 15 days (SQS max retention 14 d + 1 d) are deleted by bridge_retention. owner_task=CTL-004';
CREATE INDEX consumed_event_retention ON platform.consumed_event (consumed_at);
ALTER TABLE platform.consumed_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform.consumed_event FORCE ROW LEVEL SECURITY;
CREATE POLICY consumer_rw ON platform.consumed_event AS PERMISSIVE FOR ALL TO bridge_worker
  USING (tenant_id = app.current_tenant() OR (tenant_id IS NULL AND app.is_platform_context()))
  WITH CHECK (tenant_id = app.current_tenant() OR (tenant_id IS NULL AND app.is_platform_context()));
CREATE POLICY retention_delete ON platform.consumed_event AS PERMISSIVE FOR DELETE TO bridge_retention
  USING (consumed_at < now() - interval '15 days');
CREATE POLICY retention_select ON platform.consumed_event AS PERMISSIVE FOR SELECT TO bridge_retention
  USING (consumed_at < now() - interval '15 days');
GRANT SELECT, INSERT ON platform.consumed_event TO bridge_worker;
GRANT SELECT, DELETE ON platform.consumed_event TO bridge_retention;

-- -----------------------------------------------------------------------------------------------------
-- platform.idempotency_request (Appendix A.3, CTL-101-S06). Written in the SAME transaction as the mutation.
-- Algorithm: lookup by natural key -> same request_sha256: replay stored 2xx with Idempotent-Replayed: true;
-- different hash: 409 IDEMPOTENCY_KEY_REUSED. Otherwise execute + INSERT before commit; a concurrent duplicate
-- blocks on the unique index until the first commits, then re-reads. Only 2xx responses are stored.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE platform.idempotency_request (
  tenant_id        uuid        NOT NULL,
  id               uuid        NOT NULL,
  principal_type   text        NOT NULL CHECK (principal_type IN ('SUBJECT', 'MACHINE_CLIENT', 'OPERATOR')),
  principal_id     uuid        NOT NULL,                  -- identity.subject.id | identity.machine_client id | operator subject
  route_key        text        NOT NULL CHECK (route_key ~ '^(POST|PUT|PATCH|DELETE) /(v1|internal/v1)/[a-z0-9/{}_-]+$'),
  idem_key         text        NOT NULL CHECK (idem_key ~ '^[A-Za-z0-9_-]{16,128}$'),
  request_sha256   bytea       NOT NULL CHECK (octet_length(request_sha256) = 32),  -- sha256(JCS(body) || path params || relevant query)
  response_status  smallint    NOT NULL CHECK (response_status BETWEEN 200 AND 299),
  response_body    jsonb       NOT NULL CHECK (pg_column_size(response_body) <= 32768),
  response_headers jsonb       NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(response_headers) = 'object'),  -- Location, ETag only
  resource_type    text        NULL,
  resource_id      uuid        NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  revision         bigint      NOT NULL DEFAULT 1,
  expires_at       timestamptz NOT NULL,                  -- created_at + 24 h
  CONSTRAINT idempotency_request_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT idempotency_request_key_uq UNIQUE (tenant_id, principal_id, route_key, idem_key),
  CONSTRAINT idempotency_request_ttl CHECK (expires_at > created_at AND expires_at <= created_at + interval '24 hours')
);
ALTER TABLE platform.idempotency_request OWNER TO bridge_owner;
COMMENT ON TABLE platform.idempotency_request IS 'Idempotency records keyed (tenant, principal, route, key); TTL 24 h; stored in the mutation transaction (CTL-101-S06). owner_task=CTL-101';
COMMENT ON COLUMN platform.idempotency_request.response_body IS 'Replayed 2xx body; contains only data the principal already received. x-privacy: CUSTOMER_METADATA';
CREATE INDEX idempotency_request_expiry ON platform.idempotency_request (expires_at);
ALTER TABLE platform.idempotency_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform.idempotency_request FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON platform.idempotency_request AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
CREATE POLICY retention_delete ON platform.idempotency_request AS PERMISSIVE FOR DELETE TO bridge_retention
  USING (expires_at < now());
CREATE POLICY retention_select ON platform.idempotency_request AS PERMISSIVE FOR SELECT TO bridge_retention
  USING (expires_at < now());
GRANT SELECT, INSERT ON platform.idempotency_request TO bridge_api, bridge_worker;
GRANT SELECT, DELETE ON platform.idempotency_request TO bridge_retention;

-- -----------------------------------------------------------------------------------------------------
-- platform.lease - generic fenced leases (Appendix A.4, CTL-004-S08). DB time only; Redis never decides ownership.
-- resource_kind examples: CONFIG_PUBLISHER (key <tenant>:<kind>), ACCOUNT_CYCLE, DBT_LANE, AUDIT_EXPORTER
-- (key <chain_key>), BACKFILL_JOB (key <name>), AUTHZ_PROVISIONER (key <tenant>).
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE platform.lease (
  resource_kind  text        NOT NULL CHECK (resource_kind ~ '^[A-Z][A-Z0-9_]{1,63}$'),
  resource_key   text        NOT NULL CHECK (char_length(resource_key) BETWEEN 1 AND 256),
  tenant_id      uuid        NULL,
  owner_id       text        NOT NULL CHECK (char_length(owner_id) BETWEEN 1 AND 256),   -- <component>/<instance_id>
  fencing_token  bigint      NOT NULL,
  acquired_at    timestamptz NOT NULL,
  renewed_at     timestamptz NOT NULL,
  expires_at     timestamptz NOT NULL,
  CONSTRAINT lease_pk PRIMARY KEY (resource_kind, resource_key),
  CONSTRAINT lease_time_order CHECK (acquired_at <= renewed_at AND renewed_at < expires_at)
);
ALTER TABLE platform.lease OWNER TO bridge_owner;
COMMENT ON TABLE platform.lease IS 'Fenced leases; fencing_token from platform.lease_token_seq, strictly increasing across takeovers. Queue-class table (claims across tenants are allowlisted). owner_task=CTL-004';
CREATE INDEX lease_expiry ON platform.lease (expires_at);
ALTER TABLE platform.lease ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform.lease FORCE ROW LEVEL SECURITY;
CREATE POLICY queue_claim ON platform.lease AS PERMISSIVE FOR ALL TO bridge_worker, bridge_dispatcher, bridge_audit_exporter
  USING (true) WITH CHECK (true);
CREATE POLICY ops_read ON platform.lease AS PERMISSIVE FOR SELECT TO bridge_ops_ro USING (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON platform.lease TO bridge_worker, bridge_dispatcher, bridge_audit_exporter;
GRANT SELECT ON platform.lease TO bridge_ops_ro;

-- acquire: returns the new fencing token, or NULL when held by another owner and unexpired.
CREATE FUNCTION platform.lease_acquire(p_kind text, p_key text, p_tenant_id uuid, p_owner text, p_ttl_seconds integer DEFAULT 60)
  RETURNS bigint LANGUAGE sql VOLATILE
  AS $$
  INSERT INTO platform.lease AS l (resource_kind, resource_key, tenant_id, owner_id, fencing_token, acquired_at, renewed_at, expires_at)
  VALUES (p_kind, p_key, p_tenant_id, p_owner, nextval('platform.lease_token_seq'), now(), now(), now() + make_interval(secs => p_ttl_seconds))
  ON CONFLICT (resource_kind, resource_key) DO UPDATE
     SET owner_id = EXCLUDED.owner_id, fencing_token = EXCLUDED.fencing_token, tenant_id = EXCLUDED.tenant_id,
         acquired_at = now(), renewed_at = now(), expires_at = EXCLUDED.expires_at
   WHERE l.expires_at < now()
  RETURNING fencing_token
$$;
ALTER FUNCTION platform.lease_acquire(text, text, uuid, text, integer) OWNER TO bridge_owner;

-- renew every ttl/3; false = lease lost -> stop work immediately.
CREATE FUNCTION platform.lease_renew(p_kind text, p_key text, p_token bigint, p_ttl_seconds integer DEFAULT 60)
  RETURNS boolean LANGUAGE sql VOLATILE
  AS $$
  WITH u AS (
    UPDATE platform.lease SET renewed_at = now(), expires_at = now() + make_interval(secs => p_ttl_seconds)
     WHERE resource_kind = p_kind AND resource_key = p_key AND fencing_token = p_token AND expires_at > now()
    RETURNING 1)
  SELECT EXISTS (SELECT 1 FROM u)
$$;
ALTER FUNCTION platform.lease_renew(text, text, bigint, integer) OWNER TO bridge_owner;

CREATE FUNCTION platform.lease_release(p_kind text, p_key text, p_token bigint)
  RETURNS boolean LANGUAGE sql VOLATILE
  AS $$
  WITH d AS (
    DELETE FROM platform.lease WHERE resource_kind = p_kind AND resource_key = p_key AND fencing_token = p_token
    RETURNING 1)
  SELECT EXISTS (SELECT 1 FROM d)
$$;
ALTER FUNCTION platform.lease_release(text, text, bigint) OWNER TO bridge_owner;

-- assert_fence: FIRST statement of every protected transaction (checkpoint advance, batch acceptance,
-- publication pointer, config header insert bookkeeping). FOR SHARE makes a concurrent takeover wait until the
-- protected transaction ends. Raises SQLSTATE BL001 / message LEASE_LOST (mapped to problem PLATFORM_LEASE_LOST).
CREATE FUNCTION platform.assert_fence(p_kind text, p_key text, p_token bigint)
  RETURNS void LANGUAGE plpgsql VOLATILE
  AS $$
BEGIN
  PERFORM 1 FROM platform.lease
   WHERE resource_kind = p_kind AND resource_key = p_key AND fencing_token = p_token AND expires_at > now()
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'BL001', MESSAGE = 'LEASE_LOST', DETAIL = p_kind;
  END IF;
END
$$;
ALTER FUNCTION platform.assert_fence(text, text, bigint) OWNER TO bridge_owner;
GRANT EXECUTE ON FUNCTION platform.lease_acquire(text, text, uuid, text, integer), platform.lease_renew(text, text, bigint, integer),
  platform.lease_release(text, text, bigint), platform.assert_fence(text, text, bigint)
  TO bridge_worker, bridge_dispatcher, bridge_audit_exporter;

-- -----------------------------------------------------------------------------------------------------
-- platform.component_heartbeat - generation registry for expand/contract (Appendix C, CTL-002-S02).
-- Every process upserts every 30 s. The migration runner refuses a contract step while any row with
-- last_seen_at > now() - 15 min reports schema_rev_max < the contract's required revision.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE platform.component_heartbeat (
  component       text        NOT NULL CHECK (component ~ '^[a-z][a-z0-9-]{1,62}$'),
  instance_id     text        NOT NULL CHECK (char_length(instance_id) BETWEEN 1 AND 128),  -- ECS task ARN suffix or hostname:pid
  image_digest    text        NOT NULL CHECK (image_digest ~ '^sha256:[0-9a-f]{64}$'),
  git_sha         text        NULL CHECK (git_sha IS NULL OR git_sha ~ '^[0-9a-f]{7,40}$'),
  schema_rev_min  text        NOT NULL,                  -- oldest Alembic revision this build can run on
  schema_rev_max  text        NOT NULL,                  -- newest Alembic revision this build knows
  schema_rev_min_ordinal integer NOT NULL CHECK (schema_rev_min_ordinal >= 0),  -- linear ordinal of revisions (migration linter)
  schema_rev_max_ordinal integer NOT NULL CHECK (schema_rev_max_ordinal >= schema_rev_min_ordinal),
  event_versions  jsonb       NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(event_versions) = 'object'),  -- {event_type: [accepted versions]}
  started_at      timestamptz NOT NULL,
  last_seen_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT component_heartbeat_pk PRIMARY KEY (component, instance_id)
);
ALTER TABLE platform.component_heartbeat OWNER TO bridge_owner;
COMMENT ON TABLE platform.component_heartbeat IS 'Mixed-generation registry (CTL-002-S02); rows older than 24 h are deleted by the runner. owner_task=CTL-002';
CREATE INDEX component_heartbeat_seen ON platform.component_heartbeat (last_seen_at);
ALTER TABLE platform.component_heartbeat ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform.component_heartbeat FORCE ROW LEVEL SECURITY;
CREATE POLICY heartbeat_rw ON platform.component_heartbeat AS PERMISSIVE FOR ALL
  TO bridge_api, bridge_worker, bridge_dispatcher, bridge_broker, bridge_audit_exporter, bridge_retention
  USING (true) WITH CHECK (true);
CREATE POLICY heartbeat_ops ON platform.component_heartbeat AS PERMISSIVE FOR SELECT TO bridge_ops_ro USING (true);
GRANT SELECT, INSERT, UPDATE ON platform.component_heartbeat TO bridge_api, bridge_worker, bridge_dispatcher, bridge_broker, bridge_audit_exporter, bridge_retention;
GRANT SELECT ON platform.component_heartbeat TO bridge_ops_ro;

-- -----------------------------------------------------------------------------------------------------
-- platform.backfill_job - resumable data backfills (CTL-002-S03): 5k rows per batch by PK, SET LOCAL
-- statement_timeout='30s', 200 ms pause, run as a worker job outside the migration transaction.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE platform.backfill_job (
  name            text        NOT NULL CHECK (name ~ '^[a-z][a-z0-9_]{2,62}$'),
  target_table    text        NOT NULL CHECK (target_table ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'),
  migration_rev   text        NOT NULL,                  -- Alembic revision that registered the job (phase: backfill)
  last_key        text        NULL,                      -- last processed PK (tenant_id|id), exclusive lower bound
  batch_size      integer     NOT NULL DEFAULT 5000 CHECK (batch_size BETWEEN 100 AND 50000),
  pause_ms        integer     NOT NULL DEFAULT 200 CHECK (pause_ms BETWEEN 0 AND 10000),
  rows_done       bigint      NOT NULL DEFAULT 0 CHECK (rows_done >= 0),
  status          text        NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'RUNNING', 'PAUSED', 'DONE', 'FAILED')),
  last_error_class text       NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  completed_at    timestamptz NULL,
  revision        bigint      NOT NULL DEFAULT 1,
  CONSTRAINT backfill_job_pk PRIMARY KEY (name)
);
ALTER TABLE platform.backfill_job OWNER TO bridge_owner;
COMMENT ON TABLE platform.backfill_job IS 'Resumable backfill registry; ownership via platform.lease(kind BACKFILL_JOB). Each batch runs in tenant_transaction() of the batch tenant or as the owning worker with the table''s queue policy. owner_task=CTL-002';
ALTER TABLE platform.backfill_job ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform.backfill_job FORCE ROW LEVEL SECURITY;
CREATE POLICY backfill_rw ON platform.backfill_job AS PERMISSIVE FOR ALL TO bridge_worker USING (true) WITH CHECK (true);
CREATE POLICY backfill_ops ON platform.backfill_job AS PERMISSIVE FOR SELECT TO bridge_ops_ro USING (true);
GRANT SELECT, INSERT, UPDATE ON platform.backfill_job TO bridge_worker;
GRANT SELECT ON platform.backfill_job TO bridge_ops_ro;

-- -----------------------------------------------------------------------------------------------------
-- platform.config_kind - registry of configuration kinds published to Snowflake CONFIG (D-04, ADR-007 amendment).
-- Mirrors Snowflake CONFIG.CONFIG_KIND (infra/snowflake/migrations/CONFIG/V0110). Other lanes add kinds with a
-- migration that INSERTs a row (expand-only).
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE platform.config_kind (
  config_kind              text        NOT NULL CHECK (config_kind ~ '^[A-Z][A-Z0-9_]{2,63}$'),
  description              text        NOT NULL,
  snowflake_tables         text[]      NOT NULL CHECK (cardinality(snowflake_tables) >= 1),  -- lowercase CONFIG.<table> names
  payload_schema_version   smallint    NOT NULL CHECK (payload_schema_version >= 1),
  approval_action          text        NULL,          -- contracts/authz/capabilities.yaml approval_policies key; NULL = no approval
  access_relevant          boolean     NOT NULL DEFAULT false,   -- publication may bump tenants.authz_epoch (ALC-003-S05)
  pseudonymized_dimensions text[]      NOT NULL DEFAULT '{}',    -- user-name predicates compiled to pseudonyms (SEC-103-S08)
  owner_task               text        NOT NULL CHECK (owner_task ~ '^[A-Z]{2,3}-[0-9]{3}$'),
  created_at               timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT config_kind_pk PRIMARY KEY (config_kind)
);
ALTER TABLE platform.config_kind OWNER TO bridge_owner;
COMMENT ON TABLE platform.config_kind IS 'Global registry of publishable configuration kinds (no tenant data). owner_task=CTL-005';
ALTER TABLE platform.config_kind ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform.config_kind FORCE ROW LEVEL SECURITY;
CREATE POLICY config_kind_read ON platform.config_kind AS PERMISSIVE FOR SELECT TO bridge_api, bridge_worker, bridge_ops_ro USING (true);
GRANT SELECT ON platform.config_kind TO bridge_api, bridge_worker, bridge_ops_ro;

INSERT INTO platform.config_kind (config_kind, description, snowflake_tables, payload_schema_version, approval_action, access_relevant, pseudonymized_dimensions, owner_task) VALUES
  ('ORG_ACCOUNT',        'Organizations, accounts and effective-dated account->organization membership (CTL-001)', ARRAY['organization','account','account_membership'], 1, NULL, true, '{}', 'CTL-005'),
  ('TAG_RULE',           'Tag rules and predicates (ALC-002, D-16)', ARRAY['cfg_rule','cfg_rule_predicate'], 1, 'rule.publish', true, ARRAY['user'], 'ALC-002'),
  ('ALLOCATION_RULESET', 'Allocation rules, splits, overrides, policies, pools and transfers (ALC-002..ALC-005)', ARRAY['cfg_rule','cfg_rule_predicate','cfg_rule_split','cfg_override','cfg_allocation_policy','cfg_pool','cfg_transfer'], 1, 'rule.publish', true, ARRAY['user'], 'ALC-003'),
  ('GROUP_SET',          'Usage group sets, groups, value mappings and effective-dated closure (ALC-004)', ARRAY['cfg_group_set','cfg_group','cfg_value_mapping','cfg_group_closure'], 1, 'access.review', true, '{}', 'ALC-004'),
  ('PRICE_RATE',         'Approved rate tables / customer-approved rates (FIN-105)', ARRAY['price_rate'], 1, 'finance.pricing.publish', false, '{}', 'FIN-105'),
  ('BILLING_REFERENCE',  'Approved billing references (FIN-101)', ARRAY['billing_reference'], 1, 'finance.reference.activate', false, '{}', 'FIN-101'),
  ('PERIOD_CLOSE',       'Close and restatement records pinned by analytics (FIN-010, FIN-107)', ARRAY['period_close'], 1, 'finance.period.close', false, '{}', 'FIN-010'),
  ('MONITOR_DEFINITION', 'Monitor definitions evaluated by the monitor planner (GOV-003)', ARRAY['monitor_definition'], 1, NULL, false, '{}', 'GOV-003'),
  ('BUDGET',             'Budget definitions (GOV-001)', ARRAY['budget'], 1, NULL, false, '{}', 'GOV-001');

-- -----------------------------------------------------------------------------------------------------
-- platform.config_version_counter - monotonic config_version per (tenant, kind) (CTL-005-S03).
-- allocate: UPDATE ... SET last_version = last_version + 1 RETURNING last_version (insert-on-first-use).
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE platform.config_version_counter (
  tenant_id     uuid        NOT NULL,
  id            uuid        NOT NULL,
  config_kind   text        NOT NULL REFERENCES platform.config_kind (config_kind),
  last_version  bigint      NOT NULL DEFAULT 0 CHECK (last_version >= 0),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  revision      bigint      NOT NULL DEFAULT 1,
  CONSTRAINT config_version_counter_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT config_version_counter_kind_uq UNIQUE (tenant_id, config_kind)
);
ALTER TABLE platform.config_version_counter OWNER TO bridge_owner;
COMMENT ON TABLE platform.config_version_counter IS 'Per-tenant, per-kind config_version allocator; concurrent requests serialize on the row lock and get distinct versions. owner_task=CTL-005';
ALTER TABLE platform.config_version_counter ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform.config_version_counter FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON platform.config_version_counter AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
GRANT SELECT, INSERT, UPDATE ON platform.config_version_counter TO bridge_api, bridge_worker;

-- -----------------------------------------------------------------------------------------------------
-- platform.config_publication - PG tracking of immutable config versions (CTL-005-S03, Appendix G).
-- Lifecycle contracts/state-machines/config_publication.yaml: PENDING_PUBLICATION -> PUBLISHED | FAILED.
-- The API shows PENDING_PUBLICATION until the header row exists in Snowflake and row_count/hash were verified.
-- -----------------------------------------------------------------------------------------------------
CREATE TABLE platform.config_publication (
  tenant_id                   uuid        NOT NULL,
  id                          uuid        NOT NULL,
  config_kind                 text        NOT NULL REFERENCES platform.config_kind (config_kind),
  config_version              bigint      NOT NULL CHECK (config_version >= 1),
  parent_version              bigint      NULL CHECK (parent_version IS NULL OR parent_version < config_version),
  payload_schema_version      smallint    NOT NULL CHECK (payload_schema_version >= 1),
  source_revisions_json       jsonb       NOT NULL CHECK (jsonb_typeof(source_revisions_json) = 'object'),  -- {object_type: {object_id: revision}}
  source_revisions_schema_version smallint NOT NULL DEFAULT 1,
  content_sha256              text        NOT NULL CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
  row_count                   bigint      NOT NULL CHECK (row_count >= 0),
  approval_id                 uuid        NULL,           -- identity.approval (required when config_kind.approval_action is set)
  status                      text        NOT NULL DEFAULT 'PENDING_PUBLICATION'
                              CHECK (status IN ('PENDING_PUBLICATION', 'PUBLISHED', 'FAILED')),
  attempts                    integer     NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  last_error_class            text        NULL CHECK (last_error_class IS NULL OR last_error_class ~ '^[A-Z][A-Z0-9_]{1,63}$'),
  publisher_run_id            uuid        NULL,
  fencing_token               bigint      NULL,           -- platform.lease(CONFIG_PUBLISHER, '<tenant>:<kind>') token used by the attempt
  archive_s3_key              text        NULL CHECK (archive_s3_key IS NULL OR archive_s3_key ~ '^config/(dev|staging|prod)/[0-9a-f-]{36}/[A-Z_]+/[0-9]{1,19}\.json\.gz$'),
  archive_sha256              text        NULL CHECK (archive_sha256 IS NULL OR archive_sha256 ~ '^[0-9a-f]{64}$'),
  requested_by_subject_id     uuid        NULL,           -- NULL for system-triggered publications
  requested_at                timestamptz NOT NULL DEFAULT now(),
  published_at                timestamptz NULL,
  failed_at                   timestamptz NULL,
  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),
  revision                    bigint      NOT NULL DEFAULT 1,
  CONSTRAINT config_publication_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT config_publication_version_uq UNIQUE (tenant_id, config_kind, config_version),
  CONSTRAINT config_publication_approval_fk FOREIGN KEY (tenant_id, approval_id) REFERENCES identity.approval (tenant_id, id),
  CONSTRAINT config_publication_published_consistency CHECK ((status = 'PUBLISHED') = (published_at IS NOT NULL)),
  CONSTRAINT config_publication_failed_consistency CHECK ((status = 'FAILED') = (failed_at IS NOT NULL AND last_error_class IS NOT NULL))
);
ALTER TABLE platform.config_publication OWNER TO bridge_owner;
COMMENT ON TABLE platform.config_publication IS 'Immutable config version tracking (D-04). Content is serialized deterministically (CTL-005-S04); latest published pointer per (tenant, kind) = max(config_version) WHERE status = PUBLISHED. Versions referenced by closed statements are never deleted. owner_task=CTL-005';
CREATE INDEX config_publication_pending ON platform.config_publication (tenant_id, config_kind, requested_at) WHERE status = 'PENDING_PUBLICATION';
CREATE INDEX config_publication_latest ON platform.config_publication (tenant_id, config_kind, config_version DESC) WHERE status = 'PUBLISHED';
ALTER TABLE platform.config_publication ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform.config_publication FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON platform.config_publication AS PERMISSIVE FOR ALL TO bridge_api, bridge_worker
  USING (tenant_id = app.current_tenant()) WITH CHECK (tenant_id = app.current_tenant());
GRANT SELECT, INSERT, UPDATE ON platform.config_publication TO bridge_api, bridge_worker;

-- -----------------------------------------------------------------------------------------------------
-- Allowlist rows for intentional lint exceptions in this schema.
-- -----------------------------------------------------------------------------------------------------
INSERT INTO app.rls_allowlist (schema_name, object_name, exception, detail, reason, owner_task) VALUES
  ('platform', 'outbox', 'USING_TRUE_POLICY', 'queue_claim', 'Dispatcher claims across tenants; returns IDs/tokens; handler opens tenant context per event', 'CTL-004'),
  ('platform', 'outbox', 'USING_TRUE_POLICY', 'queue_update', 'Dispatcher completes/fails leased rows by (event_id, lease_token)', 'CTL-004'),
  ('platform', 'outbox', 'GLOBAL_UNIQUE', 'outbox_pk', 'event_id is a UUIDv7 generated server-side; never a user-supplied key', 'CTL-101'),
  ('platform', 'outbox', 'GLOBAL_UNIQUE', 'outbox_aggregate_seq_uq', 'Ordering key over server-generated aggregate ids; never surfaced to users', 'CTL-101'),
  ('platform', 'outbox', 'USING_TRUE_POLICY', 'ops_read', 'Operator backlog view; payload column not granted to bridge_ops_ro', 'CTL-004'),
  ('platform', 'aggregate_sequence', 'GLOBAL_UNIQUE', 'aggregate_sequence_pk', 'Server-generated aggregate ids; never surfaced', 'CTL-101'),
  ('platform', 'consumed_event', 'GLOBAL_UNIQUE', 'consumed_event_pk', 'Dedup key (consumer, event_id) over server-generated event ids', 'CTL-004'),
  ('platform', 'lease', 'GLOBAL_UNIQUE', 'lease_pk', 'Lease key (resource_kind, resource_key) is infrastructure-level; keys embed tenant ids when tenant-scoped', 'CTL-004'),
  ('platform', 'lease', 'USING_TRUE_POLICY', 'queue_claim', 'Lease ownership is cross-tenant infrastructure; rows carry no tenant data beyond tenant_id', 'CTL-004'),
  ('platform', 'lease', 'USING_TRUE_POLICY', 'ops_read', 'Operator visibility of lease holders', 'CTL-004'),
  ('platform', 'component_heartbeat', 'USING_TRUE_POLICY', 'heartbeat_rw', 'No tenant data (component generations)', 'CTL-002'),
  ('platform', 'component_heartbeat', 'USING_TRUE_POLICY', 'heartbeat_ops', 'No tenant data', 'CTL-002'),
  ('platform', 'component_heartbeat', 'NO_TENANT_COLUMN', 'component_heartbeat', 'Global platform table', 'CTL-002'),
  ('platform', 'backfill_job', 'USING_TRUE_POLICY', 'backfill_rw', 'No tenant data (job registry)', 'CTL-002'),
  ('platform', 'backfill_job', 'USING_TRUE_POLICY', 'backfill_ops', 'No tenant data', 'CTL-002'),
  ('platform', 'backfill_job', 'NO_TENANT_COLUMN', 'backfill_job', 'Global platform table', 'CTL-002'),
  ('platform', 'config_kind', 'USING_TRUE_POLICY', 'config_kind_read', 'Global registry without tenant data', 'CTL-005'),
  ('platform', 'config_kind', 'NO_TENANT_COLUMN', 'config_kind', 'Global registry', 'CTL-005');

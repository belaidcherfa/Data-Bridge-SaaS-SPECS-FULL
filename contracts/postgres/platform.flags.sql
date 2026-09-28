-- contract=postgres-platform-flags version=1 status=DRAFT owner_task=REL-102 decisions=D-07,D-17,D-25 last_changed=2026-09-28
-- Contract lane: K9 owns this part of the `platform` schema (contracts/README.md: platform.flags); the rest of `platform`
-- (outbox, idempotency, leases, consumed events, config publication) is K2's. This file never creates the schema's other objects.
-- Backlog name -> contract name: control.feature_flags -> platform.feature_flag (schema `control` does not exist in CONVENTIONS §10;
-- the flag store lives in `platform`) + platform.feature_flag_definition (closed catalog) + platform.feature_flag_change (audit trail).
-- Catalog and semantics: docs/releases/kill-switches.md. Evaluation library: packages/flags/ (REL-102-S02).
--
-- Rules (REL-102): server-side evaluation AFTER authorization (a flag never widens authorization, REL-102-S05); 30 s cache with revision
-- check; on store error RELEASE flags evaluate OFF and KILL_SWITCH/OPERATIONAL flags keep the last known value; every change carries
-- owner, reason and (kill switches) a ticket, bumps revision, writes platform.feature_flag_change and emits bridge.ops.feature_flag.changed;
-- expected propagation <= 60 s. Release flags expire <= 90 days after their last change (stale-flag lint REL-102-S06).
-- Global tables (no tenant_id, no RLS): listed in the SEC RLS standard as global; tenants never read them (the API evaluates them).

CREATE SCHEMA IF NOT EXISTS platform;

CREATE TABLE platform.feature_flag_definition (
  key                        text        NOT NULL,
  flag_kind                  text        NOT NULL,
  scope_type                 text        NOT NULL,
  default_value              boolean     NOT NULL,
  default_on_error           text        NOT NULL,
  owner                      text        NOT NULL,
  description                text        NOT NULL,
  max_propagation_seconds    integer     NOT NULL DEFAULT 60,
  owner_task                 text        NOT NULL,
  retired_at                 timestamptz NULL,
  created_at                 timestamptz NOT NULL DEFAULT now(),
  updated_at                 timestamptz NOT NULL DEFAULT now(),
  revision                   bigint      NOT NULL DEFAULT 1,
  CONSTRAINT feature_flag_definition_pk PRIMARY KEY (key),
  CONSTRAINT feature_flag_definition_key_ck CHECK (key ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){1,4}$'),
  CONSTRAINT feature_flag_definition_kind_ck CHECK (flag_kind IN ('RELEASE','KILL_SWITCH','OPERATIONAL')),
  CONSTRAINT feature_flag_definition_scope_ck CHECK (scope_type IN ('GLOBAL','TENANT','ACCOUNT','CONNECTION','SOURCE','CHANNEL','ROUTE')),
  CONSTRAINT feature_flag_definition_error_ck CHECK (default_on_error IN ('OFF','LAST_KNOWN')),
  CONSTRAINT feature_flag_definition_error_kind_ck CHECK ((flag_kind = 'RELEASE') = (default_on_error = 'OFF')),
  CONSTRAINT feature_flag_definition_prop_ck CHECK (max_propagation_seconds BETWEEN 1 AND 60),
  CONSTRAINT feature_flag_definition_task_ck CHECK (owner_task ~ '^[A-Z]{2,3}-[0-9]{3}$'),
  CONSTRAINT feature_flag_definition_revision_ck CHECK (revision >= 1)
);
COMMENT ON TABLE platform.feature_flag_definition IS 'REL-102-S01. Closed catalog of flag keys (docs/releases/kill-switches.md). Keys carry no ids: the id is the scope (e.g. backlog notation extraction.tenant.<id>.paused = key extraction.tenant.paused, scope TENANT/<tenant_id>). A key not in this table cannot be set (OPS_FLAG_UNKNOWN_KEY).';

CREATE TABLE platform.feature_flag (
  id            uuid        NOT NULL,
  key           text        NOT NULL,
  scope_type    text        NOT NULL,
  scope_id      text        NULL,
  value         boolean     NOT NULL,
  owner         text        NOT NULL,
  reason        text        NOT NULL,
  ticket_ref    text        NULL,
  expires_at    timestamptz NULL,
  updated_by    text        NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  revision      bigint      NOT NULL DEFAULT 1,
  CONSTRAINT feature_flag_pk PRIMARY KEY (id),
  CONSTRAINT feature_flag_def_fk FOREIGN KEY (key) REFERENCES platform.feature_flag_definition (key),
  CONSTRAINT feature_flag_scope_ck CHECK (scope_type IN ('GLOBAL','TENANT','ACCOUNT','CONNECTION','SOURCE','CHANNEL','ROUTE')),
  CONSTRAINT feature_flag_scope_id_ck CHECK ((scope_type = 'GLOBAL') = (scope_id IS NULL)),
  CONSTRAINT feature_flag_scope_id_fmt_ck CHECK (scope_id IS NULL OR scope_id ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$'),
  CONSTRAINT feature_flag_owner_ck CHECK (owner ~ '^[a-z][a-z0-9_-]{1,63}$'),
  CONSTRAINT feature_flag_reason_ck CHECK (char_length(reason) BETWEEN 10 AND 500),
  CONSTRAINT feature_flag_actor_ck CHECK (updated_by ~ '^(operator|system):[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT feature_flag_expiry_ck CHECK (expires_at IS NULL OR (expires_at > updated_at AND expires_at <= updated_at + interval '90 days')),
  CONSTRAINT feature_flag_revision_ck CHECK (revision >= 1)
);
CREATE UNIQUE INDEX feature_flag_key_scope_unique ON platform.feature_flag (key, scope_type, (COALESCE(scope_id, '')));
CREATE INDEX feature_flag_updated_idx ON platform.feature_flag (updated_at);
COMMENT ON TABLE platform.feature_flag IS 'REL-102-S01. Current value of a flag for one scope. Scope resolution for a request/work item: most specific scope wins (CONNECTION > ACCOUNT > TENANT > GLOBAL for tenant-bound keys); missing row = definition.default_value. Release flags MUST have expires_at (checked by the ops API, OPS_FLAG_EXPIRY_REQUIRED, and by the stale-flag lint); kill switches MUST have ticket_ref (OPS_FLAG_TICKET_REQUIRED). The snapshot hash (sha256 over key|scope_type|scope_id|value|revision sorted) is recorded in the release manifest (feature_flag_snapshot_sha).';
COMMENT ON COLUMN platform.feature_flag.scope_id IS 'x-privacy: INTERNAL. Tenant/account/connection UUID, source registry id, channel type (EMAIL|SLACK|TEAMS|WEBHOOK) or route id (OpenAPI operationId).';
COMMENT ON COLUMN platform.feature_flag.reason IS 'x-privacy: INTERNAL. Why the value was set; no personal data.';
COMMENT ON COLUMN platform.feature_flag.updated_by IS 'x-privacy: INTERNAL. operator:<IAM Identity Center user id> or system:<component>.';

CREATE TABLE platform.feature_flag_change (
  id               uuid        NOT NULL,
  flag_id          uuid        NOT NULL,
  key              text        NOT NULL,
  scope_type       text        NOT NULL,
  scope_id         text        NULL,
  old_value        boolean     NULL,
  new_value        boolean     NOT NULL,
  flag_revision    bigint      NOT NULL,
  reason           text        NOT NULL,
  ticket_ref       text        NULL,
  changed_by       text        NOT NULL,
  changed_at       timestamptz NOT NULL DEFAULT now(),
  request_id       text        NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT feature_flag_change_pk PRIMARY KEY (id),
  CONSTRAINT feature_flag_change_flag_fk FOREIGN KEY (flag_id) REFERENCES platform.feature_flag (id),
  CONSTRAINT feature_flag_change_rev_unique UNIQUE (flag_id, flag_revision),
  CONSTRAINT feature_flag_change_actor_ck CHECK (changed_by ~ '^(operator|system):[A-Za-z0-9._:-]{1,128}$')
);
CREATE INDEX feature_flag_change_key_idx ON platform.feature_flag_change (key, changed_at);
CREATE OR REPLACE FUNCTION platform.forbid_flag_change_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'platform.feature_flag_change is append-only (%)', TG_OP USING ERRCODE = '42501';
END;
$$;
CREATE TRIGGER feature_flag_change_append_only BEFORE UPDATE OR DELETE ON platform.feature_flag_change
  FOR EACH ROW EXECUTE FUNCTION platform.forbid_flag_change_mutation();
COMMENT ON TABLE platform.feature_flag_change IS 'REL-102-S01. Append-only change history (also mirrored to audit.events by the ops API, SEC-008 action ops.feature_flag.changed).';

-- ---------------------------------------------------------------------------------------------
-- Seed: R1 catalog (docs/releases/kill-switches.md is the human-readable form; both must match - CI diff)
-- ---------------------------------------------------------------------------------------------
INSERT INTO platform.feature_flag_definition (key, flag_kind, scope_type, default_value, default_on_error, owner, description, max_propagation_seconds, owner_task) VALUES
  ('signup.enabled',                  'KILL_SWITCH', 'GLOBAL',     false, 'LAST_KNOWN', 'delivery',      'Public self-service sign-up. false until REL-004 GO; NO-GO keeps it false (REL-104-S03, LCH-003-S02).', 60, 'REL-102'),
  ('extraction.tenant.paused',        'KILL_SWITCH', 'TENANT',     false, 'LAST_KNOWN', 'data-platform', 'true stops admission of new account-cycles for the tenant; in-flight cycles finish (RB-09, RB-15).', 60, 'REL-102'),
  ('extraction.account.paused',       'KILL_SWITCH', 'ACCOUNT',    false, 'LAST_KNOWN', 'data-platform', 'true stops new account-cycles for one Snowflake account (RB-01 contain step).', 60, 'REL-102'),
  ('extraction.source.enabled',       'KILL_SWITCH', 'SOURCE',     true,  'LAST_KNOWN', 'data-platform', 'false removes one source registry id from every planned cycle (RB-04 quarantine of a drifting source).', 60, 'REL-102'),
  ('publication.tenant.frozen',       'KILL_SWITCH', 'TENANT',     false, 'LAST_KNOWN', 'data-platform', 'true holds the tenant publication pointer (PUBLISH_BATCH skips the tenant); builds continue (RB-07, LCH-003-S04).', 60, 'REL-102'),
  ('delivery.channel.enabled',        'KILL_SWITCH', 'CHANNEL',    true,  'LAST_KNOWN', 'backend',       'false pauses dispatch for one channel type (EMAIL|SLACK|TEAMS|WEBHOOK); outbox rows stay PENDING (RB-08).', 60, 'REL-102'),
  ('api.route.enabled',               'KILL_SWITCH', 'ROUTE',      true,  'LAST_KNOWN', 'backend',       'false makes one OpenAPI operation answer 503 OPS_ROUTE_DISABLED after authorization (RB-09 containment of a vulnerable path).', 60, 'REL-102'),
  ('reports.dispatch.enabled',        'KILL_SWITCH', 'GLOBAL',     true,  'LAST_KNOWN', 'backend',       'false stops the report scheduler from creating new occurrences (RB-08 storm containment).', 60, 'REL-102'),
  ('analysis_jobs.admission.enabled', 'KILL_SWITCH', 'TENANT',     true,  'LAST_KNOWN', 'sre',           'false refuses new heavy analysis/export jobs for a tenant (RB-15 noisy tenant); interactive reads continue.', 60, 'REL-102'),
  ('ui.history_available_per_source', 'RELEASE',     'GLOBAL',     false, 'OFF',        'frontend',      'Connection wizard shows available history per source once ING-010 supplies it (CON-006-S08).', 60, 'CON-006'),
  ('ui.insight_actions',              'RELEASE',     'GLOBAL',     false, 'OFF',        'frontend',      'Insight review/assign/dismiss dialogs until INS-006 is live (INS-101-S09).', 60, 'INS-101'),
  ('ui.privacy_requests',             'RELEASE',     'GLOBAL',     false, 'OFF',        'frontend',      'Settings > Privacy & retention request flow until OPS-005-S17 is live (UX-102-S05).', 60, 'UX-102'),
  ('ui.explain_export_links',         'RELEASE',     'GLOBAL',     false, 'OFF',        'frontend',      'Explain/export links in the Cost Explorer until API-005/API-102 are ready (UX-104).', 60, 'UX-104'),
  ('ui.operator_evidence_link',       'RELEASE',     'GLOBAL',     false, 'OFF',        'frontend',      'Operator evidence link in query detail (WRK-103, R2).', 60, 'UX-005');

-- Grants: evaluation by services; mutation only through the ops API (bridge_ops_api, REL-102-S04).
REVOKE ALL ON platform.feature_flag_definition, platform.feature_flag, platform.feature_flag_change FROM PUBLIC;
GRANT USAGE ON SCHEMA platform TO bridge_api, bridge_worker, bridge_dispatcher, bridge_broker, bridge_ops_api;
GRANT SELECT ON platform.feature_flag_definition, platform.feature_flag TO bridge_api, bridge_worker, bridge_dispatcher, bridge_broker, bridge_ops_api;
GRANT INSERT, UPDATE ON platform.feature_flag TO bridge_ops_api;
GRANT SELECT, INSERT ON platform.feature_flag_change TO bridge_ops_api;

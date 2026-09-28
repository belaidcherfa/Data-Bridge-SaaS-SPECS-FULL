-- contract=postgres-monitor version=1 status=DRAFT owner_task=GOV-003,GOV-004,GOV-006,GOV-007 decisions=D-02,D-10,D-17,D-20,D-27 last_changed=2026-09-28
-- Reference DDL for the `monitor` schema (lane K7): monitor definitions/versions, the condition-tracker fold,
-- incident workflow, silences, destinations, Slack installations and the delivery outbox.
-- Evaluated analytical observations and evidence live in Snowflake (PY_OUTPUTS.FCT_MONITOR_OBSERVATION); PostgreSQL
-- stores only workflow state, per-window result codes (BREACH/OK/INSUFFICIENT_DATA), bounded counts and IDs.
-- Rules: contracts/CONVENTIONS.md §3, §4, §10. Status CHECK sets generated from
-- contracts/state-machines/{monitor,incident,destination,delivery}.yaml.
-- Secrets (Teams/webhook URLs, whsec_ keys, Slack xoxb- tokens) are NEVER stored here: secret_ref points to
-- AWS Secrets Manager /bridge/{env}/tenant/{tenant_id}/destination/{id} (GOV-102-S08).

CREATE SCHEMA IF NOT EXISTS monitor;
COMMENT ON SCHEMA monitor IS 'Monitors, condition trackers, incidents, silences, destinations and deliveries. Owner lane K7 (GOV).';

-- ============================================================================================================
-- 1. Monitor definitions and versions (GOV-003-S06) — backlog names monitor.definitions, monitor_versions
-- ============================================================================================================
CREATE TABLE monitor.definition (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    name                       text        NOT NULL,
    status                     text        NOT NULL DEFAULT 'DRAFT',
    pause_reason               text        NULL,
    owner_membership_id        uuid        NULL,
    owner_subject_id           uuid        NULL,
    dataset                    text        NOT NULL,
    condition_type             text        NOT NULL,
    severity                   text        NOT NULL DEFAULT 'WARNING',
    current_version_no         integer     NOT NULL DEFAULT 1,
    current_condition_version  integer     NOT NULL DEFAULT 1,
    every_minutes              integer     NOT NULL DEFAULT 60,
    budget_id                  uuid        NULL,
    config_version             bigint      NULL,
    next_due_at                timestamptz NULL,
    last_planned_at            timestamptz NULL,
    insufficient_since         timestamptz NULL,
    deleted_at                 timestamptz NULL,
    created_by                 uuid        NOT NULL,
    updated_by                 uuid        NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT definition_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT definition_budget_fk FOREIGN KEY (tenant_id, budget_id)
        REFERENCES governance.budget (tenant_id, id),
    CONSTRAINT definition_name_len CHECK (char_length(name) BETWEEN 1 AND 120),
    CONSTRAINT definition_status CHECK (status IN ('DRAFT', 'ACTIVE', 'PAUSED', 'PAUSED_AUTH', 'DELETED')),
    CONSTRAINT definition_pause_reason CHECK ((status = 'PAUSED_AUTH') = (pause_reason IS NOT NULL)
        AND (pause_reason IS NULL OR pause_reason IN ('OWNER_REMOVED', 'OWNER_SCOPE_REDUCED'))),
    CONSTRAINT definition_dataset CHECK (dataset IN ('COST', 'ALLOCATION', 'WORKLOAD', 'QUERY', 'BUDGET', 'FORECAST', 'SYNC_OPS', 'SLA_OPS')),
    CONSTRAINT definition_condition_type CHECK (condition_type IN ('static_threshold', 'relative_threshold', 'results_found',
        'period_comparison', 'anomaly', 'budget_breach', 'forecast_breach', 'new_resource', 'cost_regression',
        'missing_activity', 'sla_violation', 'sync_failure')),
    CONSTRAINT definition_severity CHECK (severity IN ('INFO', 'WARNING', 'CRITICAL')),
    CONSTRAINT definition_every_minutes CHECK (every_minutes IN (5, 60, 1440)
        AND (every_minutes <> 5 OR dataset IN ('SYNC_OPS', 'SLA_OPS'))),
    CONSTRAINT definition_budget_ref CHECK ((condition_type IN ('budget_breach', 'forecast_breach')) = (budget_id IS NOT NULL)),
    CONSTRAINT definition_owner_when_active CHECK (status IN ('DRAFT', 'PAUSED_AUTH', 'DELETED') OR owner_membership_id IS NOT NULL),
    CONSTRAINT definition_deleted CHECK ((status = 'DELETED') = (deleted_at IS NOT NULL))
);
CREATE INDEX definition_tenant_status_idx ON monitor.definition (tenant_id, status, updated_at DESC);
CREATE INDEX definition_due_idx ON monitor.definition (next_due_at) WHERE status = 'ACTIVE';
CREATE INDEX definition_owner_idx ON monitor.definition (tenant_id, owner_membership_id);
COMMENT ON TABLE monitor.definition IS 'Monitor header; the definition document lives in monitor.monitor_version (data/contracts/monitor.json). Evaluated as the owner''s current normalized profile role via the query broker JOB class (RECONCILIATION C-09); SYNC_OPS/SLA_OPS from PostgreSQL only. State machine contracts/state-machines/monitor.yaml. owner_task=GOV-003.';
COMMENT ON COLUMN monitor.definition.name IS 'privacy=CUSTOMER_METADATA.';

CREATE TABLE monitor.monitor_version (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    monitor_id                 uuid        NOT NULL,
    version_no                 integer     NOT NULL,
    condition_version          integer     NOT NULL,
    definition_json            jsonb       NOT NULL,
    definition_schema_version  text        NOT NULL DEFAULT 'monitor.v1',
    definition_sha256          text        NOT NULL,
    condition_sha256           text        NOT NULL,
    change_summary             text[]      NOT NULL DEFAULT '{}',
    created_by                 uuid        NOT NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT monitor_version_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT monitor_version_monitor_fk FOREIGN KEY (tenant_id, monitor_id)
        REFERENCES monitor.definition (tenant_id, id),
    CONSTRAINT monitor_version_uq UNIQUE (tenant_id, monitor_id, version_no),
    CONSTRAINT monitor_version_positive CHECK (version_no >= 1 AND condition_version >= 1 AND condition_version <= version_no),
    CONSTRAINT monitor_version_sha CHECK (definition_sha256 ~ '^[0-9a-f]{64}$' AND condition_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT monitor_version_size CHECK (octet_length(definition_json::text) <= 16384)
);
CREATE INDEX monitor_version_condition_idx ON monitor.monitor_version (tenant_id, monitor_id, condition_version);
COMMENT ON TABLE monitor.monitor_version IS 'Immutable monitor version. condition_sha256 = sha256(JCS of {dataset, metric, metric_version, currency, scope, window, condition, partition_by, max_partitions, partition_overflow, coverage_policy, minimum_data_status, breach_evaluations, recovery_evaluations}); condition_version increments iff condition_sha256 changes. owner_task=GOV-003-S06.';
COMMENT ON COLUMN monitor.monitor_version.definition_json IS 'Schema data/contracts/monitor.json (monitor.v1). IDs only in scope and partitions (D-10). privacy=CUSTOMER_METADATA.';

-- ============================================================================================================
-- 2. Planner registry (GOV-003-S08, G-GOV-06): batches and the skip-unchanged registry
-- ============================================================================================================
CREATE TABLE monitor.evaluation_batch (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    batch_key_sha256           text        NOT NULL,
    profile_id                 uuid        NULL,
    dataset                    text        NOT NULL,
    window_start               timestamptz NOT NULL,
    window_end                 timestamptz NOT NULL,
    input_publication_id       text        NULL,
    member_count               integer     NOT NULL,
    partition_count            integer     NULL,
    severity_max               text        NOT NULL,
    fence_token                bigint      NULL,
    planned_at                 timestamptz NOT NULL DEFAULT now(),
    submitted_at               timestamptz NULL,
    completed_at               timestamptz NULL,
    outcome                    text        NULL,
    error_code                 text        NULL,
    snowflake_query_count      smallint    NOT NULL DEFAULT 0,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT evaluation_batch_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT evaluation_batch_key_uq UNIQUE (tenant_id, batch_key_sha256),
    CONSTRAINT evaluation_batch_key_format CHECK (batch_key_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT evaluation_batch_dataset CHECK (dataset IN ('COST', 'ALLOCATION', 'WORKLOAD', 'QUERY', 'BUDGET', 'FORECAST', 'SYNC_OPS', 'SLA_OPS')),
    CONSTRAINT evaluation_batch_pg_datasets CHECK ((dataset IN ('SYNC_OPS', 'SLA_OPS')) = (profile_id IS NULL AND input_publication_id IS NULL)),
    CONSTRAINT evaluation_batch_window CHECK (window_end > window_start),
    CONSTRAINT evaluation_batch_severity CHECK (severity_max IN ('INFO', 'WARNING', 'CRITICAL')),
    CONSTRAINT evaluation_batch_outcome CHECK (outcome IS NULL OR outcome IN ('SUCCEEDED', 'FAILED', 'DEFERRED')),
    CONSTRAINT evaluation_batch_members CHECK (member_count BETWEEN 1 AND 200),
    CONSTRAINT evaluation_batch_query_budget CHECK (snowflake_query_count BETWEEN 0 AND 1)
);
CREATE INDEX evaluation_batch_open_idx ON monitor.evaluation_batch (planned_at) WHERE completed_at IS NULL;
CREATE INDEX evaluation_batch_tenant_hour_idx ON monitor.evaluation_batch (tenant_id, submitted_at);
COMMENT ON TABLE monitor.evaluation_batch IS 'One planner batch = (tenant, profile_role, dataset, window, input_publication); batch_key_sha256 = sha256(JCS of that tuple) is the deterministic Dagster run key. At most one Snowflake query per batch (snowflake_query_count <= 1); SYNC_OPS/SLA_OPS batches issue none. Per-tenant budget 60 submitted Snowflake batches/hour; overflow → outcome DEFERRED (metric monitor_planner_deferred). Spec docs/12-budgets-monitoring/monitor-planner.md. owner_task=GOV-003-S08.';

CREATE TABLE monitor.window_evaluation (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    monitor_id                 uuid        NOT NULL,
    condition_version          integer     NOT NULL,
    window_start               timestamptz NOT NULL,
    window_end                 timestamptz NOT NULL,
    input_publication_id       text        NOT NULL,
    batch_id                   uuid        NOT NULL,
    monitor_version_no         integer     NOT NULL,
    partitions_evaluated       integer     NOT NULL,
    overflow_applied           boolean     NOT NULL DEFAULT false,
    evaluated_at               timestamptz NOT NULL DEFAULT now(),
    first_tick_at              timestamptz NOT NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT window_evaluation_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT window_evaluation_monitor_fk FOREIGN KEY (tenant_id, monitor_id)
        REFERENCES monitor.definition (tenant_id, id),
    CONSTRAINT window_evaluation_batch_fk FOREIGN KEY (tenant_id, batch_id)
        REFERENCES monitor.evaluation_batch (tenant_id, id),
    CONSTRAINT window_evaluation_skip_key_uq UNIQUE (tenant_id, monitor_id, condition_version, window_start, window_end, input_publication_id),
    CONSTRAINT window_evaluation_window CHECK (window_end > window_start),
    CONSTRAINT window_evaluation_partitions CHECK (partitions_evaluated BETWEEN 0 AND 5001)
);
COMMENT ON TABLE monitor.window_evaluation IS 'Skip-unchanged registry: a planner tick whose (monitor, condition_version, window, input_publication) already has a row is skipped with no Snowflake query (G-GOV-01, G-GOV-06). The tick is an attribute (first_tick_at), never identity. For SYNC_OPS/SLA_OPS input_publication_id = ''pg:'' || sync state watermark. owner_task=GOV-003-S08.';

-- ============================================================================================================
-- 3. Condition trackers and per-window results (GOV-004-S05) — backlog name monitor.condition_trackers
-- ============================================================================================================
CREATE TABLE monitor.condition_tracker (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    monitor_id                 uuid        NOT NULL,
    condition_version          integer     NOT NULL,
    partition_key_hash         text        NOT NULL,
    partition_key_json         jsonb       NOT NULL,
    partition_key_schema_version text      NOT NULL DEFAULT 'partition-key.v1',
    is_overflow_partition      boolean     NOT NULL DEFAULT false,
    breach_count               smallint    NOT NULL DEFAULT 0,
    ok_count                   smallint    NOT NULL DEFAULT 0,
    last_result                text        NULL,
    last_window_end            timestamptz NULL,
    last_evaluated_at          timestamptz NULL,
    cooldown_until             timestamptz NULL,
    active_incident_id         uuid        NULL,
    episode_boundary_window_end timestamptz NULL,
    insufficient_since         timestamptz NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT condition_tracker_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT condition_tracker_monitor_fk FOREIGN KEY (tenant_id, monitor_id)
        REFERENCES monitor.definition (tenant_id, id),
    CONSTRAINT condition_tracker_key_uq UNIQUE (tenant_id, monitor_id, condition_version, partition_key_hash),
    CONSTRAINT condition_tracker_hash CHECK (partition_key_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT condition_tracker_counts CHECK (breach_count BETWEEN 0 AND 10 AND ok_count BETWEEN 0 AND 10),
    CONSTRAINT condition_tracker_last_result CHECK (last_result IS NULL OR last_result IN ('BREACH', 'OK', 'INSUFFICIENT_DATA')),
    CONSTRAINT condition_tracker_partition_size CHECK (octet_length(partition_key_json::text) <= 1024)
);
COMMENT ON TABLE monitor.condition_tracker IS 'Tracker per (tenant, monitor, condition_version, partition_key_hash) = incident episode key. Counters are a pure fold over the latest result per distinct window since the last episode boundary (contracts/state-machines/incident.yaml); upserted under SELECT … FOR UPDATE. partition_key_json = canonical JSON of STABLE IDs (resource id, workload id, user pseudonym per D-10), never names; ''__other__'' marks the TOP_N_PLUS_OTHER overflow partition (anomaly disabled on it). owner_task=GOV-004-S05.';
COMMENT ON COLUMN monitor.condition_tracker.partition_key_json IS 'Stable identifiers only (user pseudonyms u1_…, never names). privacy=CUSTOMER_METADATA.';

CREATE TABLE monitor.tracker_window_result (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    tracker_id                 uuid        NOT NULL,
    window_start               timestamptz NOT NULL,
    window_end                 timestamptz NOT NULL,
    input_publication_id       text        NOT NULL,
    observation_id             uuid        NOT NULL,
    result                     text        NOT NULL,
    insufficient_reason        text        NULL,
    superseded_observation_ids uuid[]      NOT NULL DEFAULT '{}',
    first_evaluated_at         timestamptz NOT NULL DEFAULT now(),
    evaluated_at               timestamptz NOT NULL DEFAULT now(),
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT tracker_window_result_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT tracker_window_result_tracker_fk FOREIGN KEY (tenant_id, tracker_id)
        REFERENCES monitor.condition_tracker (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT tracker_window_result_window_uq UNIQUE (tenant_id, tracker_id, window_start, window_end),
    CONSTRAINT tracker_window_result_result CHECK (result IN ('BREACH', 'OK', 'INSUFFICIENT_DATA')),
    CONSTRAINT tracker_window_result_reason CHECK ((result = 'INSUFFICIENT_DATA') = (insufficient_reason IS NOT NULL)
        AND (insufficient_reason IS NULL OR insufficient_reason IN ('COVERAGE_GAP', 'UNPRICED', 'NOT_FINAL', 'STALE_SOURCE',
            'MISSING_BASELINE', 'INSUFFICIENT_HISTORY', 'NO_FORECAST', 'CURRENCY_UNAVAILABLE', 'SOURCE_UNAVAILABLE'))),
    CONSTRAINT tracker_window_result_window CHECK (window_end > window_start)
);
CREATE INDEX tracker_window_result_fold_idx ON monitor.tracker_window_result (tenant_id, tracker_id, window_end);
COMMENT ON TABLE monitor.tracker_window_result IS 'Latest result code per DISTINCT window of a tracker (the fold input). A newer input publication for the same window updates the row (supersede: previous observation id appended to superseded_observation_ids) and triggers a re-fold, never an extra count. Retained for 35 days or since the oldest active episode. Values stay in Snowflake (observation_id). owner_task=GOV-004-S04/S05.';

-- ============================================================================================================
-- 4. Incidents (GOV-004-S06, GOV-008) — backlog names incident_workflow, incident_events
-- ============================================================================================================
CREATE TABLE monitor.incident (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    monitor_id                 uuid        NOT NULL,
    condition_version          integer     NOT NULL,
    partition_key_hash         text        NOT NULL,
    tracker_id                 uuid        NOT NULL,
    status                     text        NOT NULL DEFAULT 'OPEN',
    severity                   text        NOT NULL,
    opened_at                  timestamptz NOT NULL DEFAULT now(),
    opened_by_correction       boolean     NOT NULL DEFAULT false,
    first_window_start         timestamptz NOT NULL,
    last_window_end            timestamptz NOT NULL,
    occurrence_count           integer     NOT NULL DEFAULT 1,
    transition_seq             integer     NOT NULL DEFAULT 1,
    assignee_membership_id     uuid        NULL,
    acknowledged_by            uuid        NULL,
    acknowledged_at            timestamptz NULL,
    investigating_by           uuid        NULL,
    investigating_at           timestamptz NULL,
    resolved_at                timestamptz NULL,
    resolution_kind            text        NULL,
    resolution_reason          text        NULL,
    resolved_by                uuid        NULL,
    last_notified_severity     text        NULL,
    last_reminder_at           timestamptz NULL,
    last_correction_notice_at  timestamptz NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT incident_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT incident_monitor_fk FOREIGN KEY (tenant_id, monitor_id)
        REFERENCES monitor.definition (tenant_id, id),
    CONSTRAINT incident_tracker_fk FOREIGN KEY (tenant_id, tracker_id)
        REFERENCES monitor.condition_tracker (tenant_id, id),
    CONSTRAINT incident_status CHECK (status IN ('OPEN', 'ACKNOWLEDGED', 'INVESTIGATING', 'RESOLVED')),
    CONSTRAINT incident_severity CHECK (severity IN ('INFO', 'WARNING', 'CRITICAL')),
    CONSTRAINT incident_hash CHECK (partition_key_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT incident_occurrence CHECK (occurrence_count BETWEEN 1 AND 10000 AND transition_seq >= 1),
    CONSTRAINT incident_resolution CHECK ((status = 'RESOLVED') = (resolution_kind IS NOT NULL AND resolved_at IS NOT NULL)
        AND (resolution_kind IS NULL OR resolution_kind IN ('OBSERVED_RECOVERY', 'DATA_CORRECTION', 'MANUAL', 'DEFINITION_CHANGED', 'MONITOR_DISABLED'))),
    CONSTRAINT incident_manual_reason CHECK (resolution_kind IS DISTINCT FROM 'MANUAL'
        OR (resolved_by IS NOT NULL AND char_length(resolution_reason) >= 10)),
    CONSTRAINT incident_windows CHECK (last_window_end > first_window_start)
);
CREATE UNIQUE INDEX incident_one_active_episode_uq ON monitor.incident (tenant_id, monitor_id, condition_version, partition_key_hash) WHERE status <> 'RESOLVED';
CREATE INDEX incident_center_idx ON monitor.incident (tenant_id, status, opened_at DESC, id);
CREATE INDEX incident_monitor_idx ON monitor.incident (tenant_id, monitor_id, opened_at DESC);
COMMENT ON TABLE monitor.incident IS 'Incident episode; key (tenant, monitor, condition_version, partition) excludes the moving window and the dataset version. At most one active episode per key (partial unique index). RESOLVED is terminal; a new sustained breach gets a new id. State machine contracts/state-machines/incident.yaml (the G-GOV-08 transition table). owner_task=GOV-004-S06.';
COMMENT ON COLUMN monitor.incident.resolution_reason IS 'Free text by the resolving member (>= 10 chars for MANUAL). privacy=CUSTOMER_METADATA.';

CREATE TABLE monitor.incident_event (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    incident_id                uuid        NOT NULL,
    transition_seq             integer     NOT NULL,
    event_kind                 text        NOT NULL,
    from_status                text        NULL,
    to_status                  text        NOT NULL,
    window_start               timestamptz NULL,
    window_end                 timestamptz NULL,
    observation_id             uuid        NULL,
    input_publication_id       text        NULL,
    actor_kind                 text        NOT NULL,
    actor_subject_id           uuid        NULL,
    note                       text        NULL,
    outbox_event_id            uuid        NULL,
    occurred_at                timestamptz NOT NULL DEFAULT now(),
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT incident_event_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT incident_event_incident_fk FOREIGN KEY (tenant_id, incident_id)
        REFERENCES monitor.incident (tenant_id, id),
    CONSTRAINT incident_event_seq_uq UNIQUE (tenant_id, incident_id, transition_seq),
    CONSTRAINT incident_event_outbox_uq UNIQUE (tenant_id, outbox_event_id),
    CONSTRAINT incident_event_kind CHECK (event_kind IN ('opened', 'breach_observed', 'ok_observed', 'insufficient_data_observed',
        'window_superseded', 'acknowledge', 'investigate', 'assign', 'manual_resolve', 'condition_version_bumped',
        'monitor_disabled', 'owner_scope_lost', 'silence_expired', 'reminder', 'severity_escalated')),
    CONSTRAINT incident_event_status CHECK ((from_status IS NULL OR from_status IN ('OPEN', 'ACKNOWLEDGED', 'INVESTIGATING', 'RESOLVED'))
        AND to_status IN ('OPEN', 'ACKNOWLEDGED', 'INVESTIGATING', 'RESOLVED')),
    CONSTRAINT incident_event_actor CHECK (actor_kind IN ('SYSTEM', 'MEMBER') AND ((actor_kind = 'MEMBER') = (actor_subject_id IS NOT NULL))),
    CONSTRAINT incident_event_note_len CHECK (note IS NULL OR char_length(note) <= 2000)
);
CREATE INDEX incident_event_timeline_idx ON monitor.incident_event (tenant_id, incident_id, transition_seq);
COMMENT ON TABLE monitor.incident_event IS 'Append-only incident timeline (observations, workflow actions, notifications). One row per transition_seq; outbox_event_id = uuid5(NS_incident_transition, incident_id␟transition_seq) for notifying events. owner_task=GOV-004-S08, GOV-008-S04.';
COMMENT ON COLUMN monitor.incident_event.note IS 'privacy=CUSTOMER_METADATA.';

-- ============================================================================================================
-- 5. Silences (GOV-004-S07) — backlog name monitor.silences
-- ============================================================================================================
CREATE TABLE monitor.silence (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    monitor_id                 uuid        NOT NULL,
    partition_key_hash         text        NULL,
    owner_subject_id           uuid        NOT NULL,
    reason                     text        NOT NULL,
    starts_at                  timestamptz NOT NULL DEFAULT now(),
    expires_at                 timestamptz NOT NULL,
    ended_at                   timestamptz NULL,
    ended_by                   uuid        NULL,
    expiry_processed_at        timestamptz NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT silence_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT silence_monitor_fk FOREIGN KEY (tenant_id, monitor_id)
        REFERENCES monitor.definition (tenant_id, id),
    CONSTRAINT silence_hash CHECK (partition_key_hash IS NULL OR partition_key_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT silence_reason_len CHECK (char_length(reason) BETWEEN 1 AND 2000),
    CONSTRAINT silence_expiry_bounds CHECK (expires_at > starts_at AND expires_at <= starts_at + interval '30 days'),
    CONSTRAINT silence_ended CHECK ((ended_at IS NULL) = (ended_by IS NULL))
);
CREATE INDEX silence_active_idx ON monitor.silence (tenant_id, monitor_id, expires_at) WHERE ended_at IS NULL;
CREATE INDEX silence_expiry_idx ON monitor.silence (expires_at) WHERE ended_at IS NULL AND expiry_processed_at IS NULL;
COMMENT ON TABLE monitor.silence IS 'Delivery overlay (never changes incident state). Scope = monitor or monitor+partition; expiry required (API default 24 h, <= 30 days; missing → 422 GOV_SILENCE_EXPIRY_REQUIRED, longer → 422 GOV_SILENCE_EXPIRY_TOO_LONG). On expiry with an incident still active and its last event suppressed, exactly one incident.updated{STILL_ACTIVE}. owner_task=GOV-004-S07.';
COMMENT ON COLUMN monitor.silence.reason IS 'privacy=CUSTOMER_METADATA.';

-- ============================================================================================================
-- 6. Destinations and Slack installations (GOV-006-S01/S05) — backlog name monitor.destinations
-- ============================================================================================================
CREATE TABLE monitor.slack_installation (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    workspace_id               text        NOT NULL,
    workspace_name             text        NOT NULL,
    enterprise_id              text        NULL,
    bot_user_id                text        NOT NULL,
    app_id                     text        NOT NULL,
    scopes                     text[]      NOT NULL,
    secret_ref                 text        NOT NULL,
    installed_by               uuid        NOT NULL,
    installed_at               timestamptz NOT NULL DEFAULT now(),
    revoked_at                 timestamptz NULL,
    revoke_reason              text        NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT slack_installation_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT slack_installation_workspace_format CHECK (workspace_id ~ '^T[A-Z0-9]{2,20}$' AND bot_user_id ~ '^[UB][A-Z0-9]{2,20}$'),
    CONSTRAINT slack_installation_scopes CHECK (scopes <@ ARRAY['chat:write', 'channels:read', 'groups:read']::text[]
        AND scopes @> ARRAY['chat:write']::text[]),
    CONSTRAINT slack_installation_secret_ref CHECK (secret_ref ~ '^/bridge/[a-z0-9-]+/tenant/[0-9a-f-]{36}/slack/[0-9a-f-]{36}$'),
    CONSTRAINT slack_installation_revoked CHECK ((revoked_at IS NULL) = (revoke_reason IS NULL)
        AND (revoke_reason IS NULL OR revoke_reason IN ('TOKENS_REVOKED', 'APP_UNINSTALLED', 'INVALID_AUTH', 'USER_REMOVED')))
);
CREATE UNIQUE INDEX slack_installation_active_uq ON monitor.slack_installation (tenant_id, workspace_id) WHERE revoked_at IS NULL;
COMMENT ON TABLE monitor.slack_installation IS 'Slack app (OAuth v2) installation per (tenant, workspace): one bot token in Secrets Manager (secret_ref), scopes chat:write, channels:read, groups:read only (chat:write.public is not used). tokens_revoked/app_uninstalled events (signed, 5-minute tolerance) set revoked_at and move dependent destinations to REVOKED. owner_task=GOV-006-S05/S06.';
COMMENT ON COLUMN monitor.slack_installation.workspace_name IS 'privacy=CUSTOMER_METADATA.';

CREATE TABLE monitor.slack_oauth_state (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    state_hash                 text        NOT NULL,
    membership_id              uuid        NOT NULL,
    return_path                text        NOT NULL,
    expires_at                 timestamptz NOT NULL,
    consumed_at                timestamptz NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT slack_oauth_state_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT slack_oauth_state_hash_uq UNIQUE (state_hash),
    CONSTRAINT slack_oauth_state_hash CHECK (state_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT slack_oauth_state_return_path CHECK (return_path ~ '^/[^/\\]' AND return_path !~ '://'),
    CONSTRAINT slack_oauth_state_ttl CHECK (expires_at <= created_at + interval '10 minutes')
);
COMMENT ON TABLE monitor.slack_oauth_state IS 'Single-use CSRF state for the Slack OAuth v2 install (sha256 of the random state; 10-minute TTL; bound to tenant and membership; return_path relative only). owner_task=GOV-006-S05.';

CREATE TABLE monitor.destination (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    type                       text        NOT NULL,
    name                       text        NOT NULL,
    status                     text        NOT NULL DEFAULT 'CONFIGURED',
    status_reason              text        NULL,
    version                    integer     NOT NULL DEFAULT 1,
    config_json                jsonb       NOT NULL,
    config_schema_version      text        NOT NULL DEFAULT 'destination.v1',
    secret_ref                 text        NULL,
    secret_rotation_overlap_until timestamptz NULL,
    disclosure_level           text        NOT NULL DEFAULT 'SUMMARY',
    authorized_scope_json      jsonb       NOT NULL,
    authorized_scope_schema_version text   NOT NULL DEFAULT 'scope.v1',
    authorized_by_membership_id uuid       NOT NULL,
    slack_installation_id      uuid        NULL,
    verified_at                timestamptz NULL,
    last_success_at            timestamptz NULL,
    consecutive_transient_failures integer NOT NULL DEFAULT 0,
    test_count_window_start    timestamptz NULL,
    test_count                 smallint    NOT NULL DEFAULT 0,
    deleted_at                 timestamptz NULL,
    created_by                 uuid        NOT NULL,
    updated_by                 uuid        NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT destination_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT destination_slack_fk FOREIGN KEY (tenant_id, slack_installation_id)
        REFERENCES monitor.slack_installation (tenant_id, id),
    CONSTRAINT destination_type CHECK (type IN ('EMAIL', 'SLACK', 'TEAMS', 'WEBHOOK')),
    CONSTRAINT destination_name_len CHECK (char_length(name) BETWEEN 1 AND 120),
    CONSTRAINT destination_status CHECK (status IN ('CONFIGURED', 'VERIFIED', 'DEGRADED', 'PAUSED', 'REVOKED', 'DELETED')),
    CONSTRAINT destination_status_reason CHECK ((status IN ('PAUSED', 'REVOKED')) = (status_reason IS NOT NULL)
        AND (status_reason IS NULL OR status_reason IN ('PERMANENT_4XX', 'WORKFLOW_DISABLED_OR_OWNER_REMOVED', 'REDIRECT_NOT_ALLOWED',
            'ADDRESS_DENIED', 'USER_PAUSED', 'SCOPE_REVOKED', 'TOKENS_REVOKED', 'APP_UNINSTALLED', 'CHANNEL_NOT_FOUND',
            'NOT_IN_CHANNEL', 'INVALID_AUTH', 'RECIPIENTS_UNDELIVERABLE'))),
    CONSTRAINT destination_disclosure CHECK (disclosure_level IN ('SUMMARY', 'STANDARD')),
    CONSTRAINT destination_secret_required CHECK ((type IN ('TEAMS', 'WEBHOOK')) = (secret_ref IS NOT NULL)),
    CONSTRAINT destination_secret_ref_format CHECK (secret_ref IS NULL OR secret_ref ~ '^/bridge/[a-z0-9-]+/tenant/[0-9a-f-]{36}/destination/[0-9a-f-]{36}$'),
    CONSTRAINT destination_slack_ref CHECK ((type = 'SLACK') = (slack_installation_id IS NOT NULL)),
    CONSTRAINT destination_no_secret_in_config CHECK (config_json::text !~ '(xox[abposr]-|whsec_|[?&]sig=|://[^/@"]*@)'),
    CONSTRAINT destination_config_size CHECK (octet_length(config_json::text) <= 8192),
    CONSTRAINT destination_deleted CHECK ((status = 'DELETED') = (deleted_at IS NOT NULL)),
    CONSTRAINT destination_test_count CHECK (test_count BETWEEN 0 AND 5)
);
CREATE INDEX destination_tenant_status_idx ON monitor.destination (tenant_id, status, type);
COMMENT ON TABLE monitor.destination IS 'Notification destination (data/contracts/destination.json). config_json holds non-secret settings only (recipients by subject id, Slack channel id, redacted URL host); the Teams URL, webhook URL and whsec_ signing secrets are in Secrets Manager at secret_ref (write-only via API). authorized_scope = the creator''s scope (revalidated); disclosure_level SUMMARY (no amounts/names) or STANDARD (in-scope amounts and labels); SQL text never included. State machine contracts/state-machines/destination.yaml. owner_task=GOV-006-S01.';
COMMENT ON COLUMN monitor.destination.config_json IS 'Non-secret configuration; CHECK rejects token/secret patterns. privacy=CUSTOMER_METADATA.';
COMMENT ON COLUMN monitor.destination.name IS 'privacy=CUSTOMER_METADATA.';

CREATE TABLE monitor.destination_version (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    destination_id             uuid        NOT NULL,
    version                    integer     NOT NULL,
    config_json                jsonb       NOT NULL,
    config_schema_version      text        NOT NULL,
    disclosure_level           text        NOT NULL,
    authorized_scope_json      jsonb       NOT NULL,
    authorized_scope_schema_version text   NOT NULL,
    secret_version_id          text        NULL,
    created_by                 uuid        NOT NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT destination_version_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT destination_version_destination_fk FOREIGN KEY (tenant_id, destination_id)
        REFERENCES monitor.destination (tenant_id, id),
    CONSTRAINT destination_version_uq UNIQUE (tenant_id, destination_id, version),
    CONSTRAINT destination_version_disclosure CHECK (disclosure_level IN ('SUMMARY', 'STANDARD')),
    CONSTRAINT destination_version_no_secret CHECK (config_json::text !~ '(xox[abposr]-|whsec_|[?&]sig=|://[^/@"]*@)')
);
COMMENT ON TABLE monitor.destination_version IS 'Immutable history of destination versions; deliveries pin destination_version at their first attempt. secret_version_id = Secrets Manager VersionId (not the secret). owner_task=GOV-006-S11.';

-- ============================================================================================================
-- 7. Deliveries (GOV-007-S01) — backlog names notification_outbox / deliveries, delivery_attempts
-- ============================================================================================================
CREATE TABLE monitor.delivery (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    logical_delivery_id        uuid        NOT NULL,
    recipient_key              text        NOT NULL DEFAULT '',
    event_id                   uuid        NOT NULL,
    event_type                 text        NOT NULL,
    message_kind               text        NOT NULL,
    incident_id                uuid        NULL,
    digest_id                  uuid        NULL,
    destination_id             uuid        NOT NULL,
    destination_version        integer     NULL,
    template_id                text        NULL,
    template_version           integer     NULL,
    status                     text        NOT NULL DEFAULT 'PENDING',
    attempt_count              smallint    NOT NULL DEFAULT 0,
    first_attempt_at           timestamptz NULL,
    next_attempt_at            timestamptz NOT NULL DEFAULT now(),
    accepted_at                timestamptz NULL,
    accepted_kind              text        NULL,
    provider_ref               text        NULL,
    last_outcome               text        NULL,
    last_error_code            text        NULL,
    dead_at                    timestamptz NULL,
    dead_reason                text        NULL,
    silence_id                 uuid        NULL,
    replay_count               smallint    NOT NULL DEFAULT 0,
    recipient_subject_id       uuid        NULL,
    payload_sha256             text        NULL,
    is_test                    boolean     NOT NULL DEFAULT false,
    lease_owner                text        NULL,
    fence_token                bigint      NULL,
    lease_expires_at           timestamptz NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT delivery_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT delivery_destination_fk FOREIGN KEY (tenant_id, destination_id)
        REFERENCES monitor.destination (tenant_id, id),
    CONSTRAINT delivery_incident_fk FOREIGN KEY (tenant_id, incident_id)
        REFERENCES monitor.incident (tenant_id, id),
    CONSTRAINT delivery_silence_fk FOREIGN KEY (tenant_id, silence_id)
        REFERENCES monitor.silence (tenant_id, id),
    CONSTRAINT delivery_logical_uq UNIQUE (tenant_id, logical_delivery_id, recipient_key),
    CONSTRAINT delivery_message_kind CHECK (message_kind IN ('INCIDENT_OPENED', 'INCIDENT_UPDATED', 'INCIDENT_RECOVERED',
        'INCIDENT_RESOLVED', 'DIGEST', 'TEST', 'DESTINATION_NOTICE')),
    CONSTRAINT delivery_status CHECK (status IN ('PENDING', 'SENDING', 'RETRY_SCHEDULED', 'ACCEPTED', 'DEAD',
        'SKIPPED_UNAUTHORIZED', 'SUPPRESSED_SILENCE', 'CANCELLED')),
    CONSTRAINT delivery_attempts CHECK (attempt_count BETWEEN 0 AND 8 AND replay_count BETWEEN 0 AND 5),
    CONSTRAINT delivery_accepted CHECK ((status = 'ACCEPTED') = (accepted_at IS NOT NULL AND accepted_kind IS NOT NULL)
        AND (accepted_kind IS NULL OR accepted_kind IN ('ACCEPTED', 'ACCEPTED_BY_PROVIDER'))),
    CONSTRAINT delivery_last_outcome CHECK (last_outcome IS NULL OR last_outcome IN ('ACCEPTED', 'ACCEPTED_BY_PROVIDER',
        'TRANSIENT', 'PERMANENT', 'RATE_LIMITED')),
    CONSTRAINT delivery_dead CHECK ((status = 'DEAD') = (dead_at IS NOT NULL AND dead_reason IS NOT NULL)
        AND (dead_reason IS NULL OR dead_reason IN ('RETRIES_EXHAUSTED', 'PERMANENT', 'DESTINATION_PAUSED', 'DESTINATION_REVOKED'))),
    CONSTRAINT delivery_pinned_after_first_attempt CHECK (attempt_count = 0
        OR (destination_version IS NOT NULL AND template_id IS NOT NULL AND template_version IS NOT NULL AND first_attempt_at IS NOT NULL)),
    CONSTRAINT delivery_recipient CHECK ((recipient_key = '') = (recipient_subject_id IS NULL)),
    CONSTRAINT delivery_subject CHECK (message_kind NOT IN ('INCIDENT_OPENED', 'INCIDENT_UPDATED', 'INCIDENT_RECOVERED', 'INCIDENT_RESOLVED')
        OR incident_id IS NOT NULL),
    CONSTRAINT delivery_payload_sha CHECK (payload_sha256 IS NULL OR payload_sha256 ~ '^[0-9a-f]{64}$')
);
CREATE INDEX delivery_claim_idx ON monitor.delivery (next_attempt_at) WHERE status IN ('PENDING', 'RETRY_SCHEDULED');
CREATE INDEX delivery_dlq_idx ON monitor.delivery (tenant_id, dead_at DESC) WHERE status = 'DEAD';
CREATE INDEX delivery_incident_idx ON monitor.delivery (tenant_id, incident_id, created_at);
CREATE INDEX delivery_destination_idx ON monitor.delivery (tenant_id, destination_id, status);
COMMENT ON TABLE monitor.delivery IS 'Logical delivery (transactional outbox consumer). logical_delivery_id = uuid5(NS_logical_delivery, event_id␟destination_id); recipient_key = subject id for EMAIL (one message per recipient), '''' otherwise. Template and destination versions pinned at the first attempt. Retry: data/contracts/delivery-classification.json (8 attempts / 24 h → DEAD). State machine contracts/state-machines/delivery.yaml. owner_task=GOV-007-S01.';

CREATE TABLE monitor.delivery_attempt (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    delivery_id                uuid        NOT NULL,
    attempt_no                 smallint    NOT NULL,
    started_at                 timestamptz NOT NULL,
    finished_at                timestamptz NULL,
    outcome                    text        NULL,
    http_status                smallint    NULL,
    error_code                 text        NULL,
    provider_error             text        NULL,
    retry_after_ms             integer     NULL,
    provider_ref               text        NULL,
    resolved_ip                inet        NULL,
    duration_ms                integer     NULL,
    worker_id                  text        NOT NULL,
    fence_token                bigint      NOT NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT delivery_attempt_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT delivery_attempt_delivery_fk FOREIGN KEY (tenant_id, delivery_id)
        REFERENCES monitor.delivery (tenant_id, id),
    CONSTRAINT delivery_attempt_uq UNIQUE (tenant_id, delivery_id, attempt_no, fence_token),
    CONSTRAINT delivery_attempt_no CHECK (attempt_no BETWEEN 1 AND 48),
    CONSTRAINT delivery_attempt_outcome CHECK (outcome IS NULL OR outcome IN ('ACCEPTED', 'ACCEPTED_BY_PROVIDER', 'TRANSIENT', 'PERMANENT', 'RATE_LIMITED')),
    CONSTRAINT delivery_attempt_http CHECK (http_status IS NULL OR http_status BETWEEN 100 AND 599),
    CONSTRAINT delivery_attempt_provider_error_len CHECK (provider_error IS NULL OR char_length(provider_error) <= 256),
    CONSTRAINT delivery_attempt_retry_after CHECK (retry_after_ms IS NULL OR retry_after_ms BETWEEN 0 AND 3600000)
);
CREATE INDEX delivery_attempt_delivery_idx ON monitor.delivery_attempt (tenant_id, delivery_id, attempt_no);
COMMENT ON TABLE monitor.delivery_attempt IS 'One provider call. error_code from the classification table (data/contracts/delivery-classification.json) or the SSRF validator (data/contracts/ssrf-deny-list.json); provider_error is a provider error token (e.g. Slack "channel_not_found"), never a response body, URL or secret. resolved_ip is the validated address actually connected to (pinned). Replays after DEAD continue attempt_no numbering (max 8 per replay × 6). owner_task=GOV-007-S03.';

CREATE TABLE monitor.incident_thread (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    incident_id                uuid        NOT NULL,
    destination_id             uuid        NOT NULL,
    provider_thread_ref        text        NOT NULL,
    opening_delivery_id        uuid        NOT NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT incident_thread_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT incident_thread_incident_fk FOREIGN KEY (tenant_id, incident_id)
        REFERENCES monitor.incident (tenant_id, id),
    CONSTRAINT incident_thread_destination_fk FOREIGN KEY (tenant_id, destination_id)
        REFERENCES monitor.destination (tenant_id, id),
    CONSTRAINT incident_thread_uq UNIQUE (tenant_id, incident_id, destination_id)
);
COMMENT ON TABLE monitor.incident_thread IS 'Slack thread_ts (or other provider thread reference) of the opening message per (incident, destination); updates and recoveries are posted into it. owner_task=GOV-006-S05.';

CREATE TABLE monitor.digest (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    evaluation_batch_id        uuid        NULL,
    anomaly_model_version      text        NOT NULL,
    input_publication_id       text        NOT NULL,
    window_start               timestamptz NOT NULL,
    window_end                 timestamptz NOT NULL,
    candidate_count            integer     NOT NULL,
    delivered_count            integer     NOT NULL,
    suppressed_count           integer     NOT NULL,
    candidate_ids              uuid[]      NOT NULL,
    event_id                   uuid        NOT NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT digest_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT digest_batch_fk FOREIGN KEY (tenant_id, evaluation_batch_id)
        REFERENCES monitor.evaluation_batch (tenant_id, id),
    CONSTRAINT digest_counts CHECK (delivered_count BETWEEN 0 AND 10 AND delivered_count + suppressed_count = candidate_count
        AND cardinality(candidate_ids) = delivered_count),
    CONSTRAINT digest_uq UNIQUE (tenant_id, input_publication_id, window_start, window_end, anomaly_model_version)
);
COMMENT ON TABLE monitor.digest IS 'Anomaly digest per tenant evaluation: at most 10 candidates (ranked by absolute monetary impact, grouped by parent resource) are delivered; the rest stay inspectable as suppressed. candidate_ids reference PY_OUTPUTS.PY_ANOMALY_CANDIDATE rows. owner_task=GOV-005-S04.';

CREATE TABLE monitor.recipient_suppression (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    subject_id                 uuid        NOT NULL,
    email_sha256               text        NOT NULL,
    reason                     text        NOT NULL,
    ses_message_id             text        NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    cleared_at                 timestamptz NULL,
    cleared_by                 uuid        NULL,
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT recipient_suppression_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT recipient_suppression_reason CHECK (reason IN ('HARD_BOUNCE', 'COMPLAINT', 'MANUAL_OPT_OUT')),
    CONSTRAINT recipient_suppression_email_hash CHECK (email_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT recipient_suppression_cleared CHECK ((cleared_at IS NULL) = (cleared_by IS NULL))
);
CREATE UNIQUE INDEX recipient_suppression_active_uq ON monitor.recipient_suppression (tenant_id, subject_id, reason) WHERE cleared_at IS NULL;
COMMENT ON TABLE monitor.recipient_suppression IS 'Per-tenant email suppression: hard bounce → UNDELIVERABLE, complaint → opt-out of email for that tenant (G-GOV-12). email_sha256 = sha256 of the normalized address (no plaintext email here). owner_task=GOV-006-S04.';
COMMENT ON COLUMN monitor.recipient_suppression.email_sha256 IS 'Hash of a PERSONAL value; the plaintext address stays in identity.subject. privacy=PERSONAL (pseudonymous).';

CREATE TABLE monitor.ses_event_receipt (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    ses_message_id             text        NOT NULL,
    event_type                 text        NOT NULL,
    delivery_id                uuid        NULL,
    received_at                timestamptz NOT NULL DEFAULT now(),
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT ses_event_receipt_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT ses_event_receipt_uq UNIQUE (tenant_id, ses_message_id, event_type),
    CONSTRAINT ses_event_receipt_type CHECK (event_type IN ('BOUNCE', 'COMPLAINT', 'DELIVERY', 'REJECT', 'DELIVERY_DELAY'))
);
COMMENT ON TABLE monitor.ses_event_receipt IS 'Idempotency ledger of the SES bounce/complaint consumer (SNS → SQS from the INF-006 configuration set): a duplicate SNS message is processed once. owner_task=GOV-006-S04.';

-- ============================================================================================================
-- 8. Row level security (SEC RLS standard template) + dispatcher queue policies (template (c), allowlisted)
-- ============================================================================================================
ALTER TABLE monitor.definition ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.definition FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.definition
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY planner_scan ON monitor.definition FOR SELECT TO bridge_worker
    USING (status = 'ACTIVE');

ALTER TABLE monitor.monitor_version ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.monitor_version FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.monitor_version
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE monitor.evaluation_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.evaluation_batch FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.evaluation_batch
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE monitor.window_evaluation ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.window_evaluation FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.window_evaluation
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE monitor.condition_tracker ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.condition_tracker FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.condition_tracker
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE monitor.tracker_window_result ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.tracker_window_result FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.tracker_window_result
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE monitor.incident ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.incident FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.incident
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE monitor.incident_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.incident_event FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.incident_event
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE monitor.silence ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.silence FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.silence
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY silence_reaper_scan ON monitor.silence FOR SELECT TO bridge_worker
    USING (ended_at IS NULL AND expiry_processed_at IS NULL);

ALTER TABLE monitor.slack_installation ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.slack_installation FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.slack_installation
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE monitor.slack_oauth_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.slack_oauth_state FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.slack_oauth_state
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE monitor.destination ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.destination FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.destination
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE monitor.destination_version ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.destination_version FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.destination_version
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE monitor.delivery ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.delivery FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.delivery
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY dispatcher_claim_select ON monitor.delivery FOR SELECT TO bridge_dispatcher
    USING (status IN ('PENDING', 'SENDING', 'RETRY_SCHEDULED'));
CREATE POLICY dispatcher_claim_update ON monitor.delivery FOR UPDATE TO bridge_dispatcher
    USING (status IN ('PENDING', 'SENDING', 'RETRY_SCHEDULED'))
    WITH CHECK (true);

ALTER TABLE monitor.delivery_attempt ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.delivery_attempt FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.delivery_attempt
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE monitor.incident_thread ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.incident_thread FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.incident_thread
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE monitor.digest ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.digest FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.digest
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE monitor.recipient_suppression ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.recipient_suppression FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.recipient_suppression
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE monitor.ses_event_receipt ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitor.ses_event_receipt FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON monitor.ses_event_receipt
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- ============================================================================================================
-- 9. Cross-lane foreign keys (identity.* from lane K2; see contracts/_handoffs/K7.md)
-- ============================================================================================================
ALTER TABLE monitor.definition ADD CONSTRAINT definition_owner_membership_fk
    FOREIGN KEY (tenant_id, owner_membership_id) REFERENCES identity.membership (tenant_id, id);
ALTER TABLE monitor.destination ADD CONSTRAINT destination_authorized_by_fk
    FOREIGN KEY (tenant_id, authorized_by_membership_id) REFERENCES identity.membership (tenant_id, id);
ALTER TABLE monitor.incident ADD CONSTRAINT incident_assignee_fk
    FOREIGN KEY (tenant_id, assignee_membership_id) REFERENCES identity.membership (tenant_id, id);
ALTER TABLE monitor.slack_oauth_state ADD CONSTRAINT slack_oauth_state_membership_fk
    FOREIGN KEY (tenant_id, membership_id) REFERENCES identity.membership (tenant_id, id);
ALTER TABLE monitor.evaluation_batch ADD CONSTRAINT evaluation_batch_profile_fk
    FOREIGN KEY (tenant_id, profile_id) REFERENCES identity.permission_profile (tenant_id, id);

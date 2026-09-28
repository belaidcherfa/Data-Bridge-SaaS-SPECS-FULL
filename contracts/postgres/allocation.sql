-- contract=postgres-allocation version=1 status=DRAFT owner_task=ALC-003,ALC-005,ALC-006,ALC-101,ALC-103 decisions=D-04,D-05,D-11,D-15,D-33 last_changed=2026-09-28
-- Reference DDL for the `allocation` schema (lane K7). Control-plane state for simulations, access-impact reviews,
-- allocation policy versions, pool disclosure settings and manual transfers. Analytical results (allocation lines,
-- simulation baseline/candidate, access-impact detail) live in Snowflake (ALLOCATION, SIMULATION schemas).
-- Rules: contracts/CONVENTIONS.md §3, §4, §10. Status CHECK sets generated from
-- contracts/state-machines/{simulation,ruleset,allocation_transfer}.yaml.

CREATE SCHEMA IF NOT EXISTS allocation;
COMMENT ON SCHEMA allocation IS 'Allocation control plane: simulations, access-impact reviews, allocation policy versions, pool disclosures, manual transfers. Owner lane K7 (ALC).';

-- ============================================================================================================
-- 1. Simulations (ALC-003) — state machine simulation.yaml
-- ============================================================================================================
CREATE TABLE allocation.simulation (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    subject_type               text        NOT NULL,
    subject_id                 uuid        NOT NULL,
    content_sha256             text        NOT NULL,
    status                     text        NOT NULL DEFAULT 'QUEUED',
    failure_reason             text        NULL,
    window_start               date        NOT NULL,
    window_end                 date        NOT NULL,
    scope_json                 jsonb       NOT NULL,
    scope_schema_version       text        NOT NULL DEFAULT 'simulation-scope.v1',
    input_publication_id       text        NOT NULL,
    publication_pin_id         uuid        NULL,
    baseline_config_versions_json jsonb    NOT NULL,
    baseline_config_versions_schema_version text NOT NULL DEFAULT 'config-versions.v1',
    window_fingerprint         text        NULL,
    dependency_versions_json   jsonb       NULL,
    dependency_versions_schema_version text NULL,
    analysis_job_id            uuid        NULL,
    dagster_run_id             text        NULL,
    idempotency_key            text        NULL,
    conflict_count             integer     NULL,
    changed_subject_count      integer     NULL,
    unallocated_delta_sign     smallint    NULL,
    untested_day_count         integer     NULL,
    access_relevant            boolean     NULL,
    requested_by               uuid        NOT NULL,
    queued_at                  timestamptz NOT NULL DEFAULT now(),
    started_at                 timestamptz NULL,
    finished_at                timestamptz NULL,
    expires_at                 timestamptz NOT NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT simulation_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT simulation_subject_type CHECK (subject_type IN ('RULESET', 'HIERARCHY', 'ALLOCATION_POLICY')),
    CONSTRAINT simulation_status CHECK (status IN ('QUEUED', 'INPUT_PUBLISHING', 'RUNNING', 'SUCCEEDED', 'FAILED', 'CANCELLED', 'EXPIRED')),
    CONSTRAINT simulation_failure_reason CHECK ((status = 'FAILED') = (failure_reason IS NOT NULL)
        AND (failure_reason IS NULL OR failure_reason IN ('TIMEOUT', 'BUILD_ERROR', 'INPUT_PUBLISH_FAILED', 'WORKER_LOST', 'PUBLICATION_RETIRED'))),
    CONSTRAINT simulation_window CHECK (window_end > window_start AND window_end - window_start <= 365),
    CONSTRAINT simulation_sha CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT simulation_fingerprint CHECK (window_fingerprint IS NULL OR window_fingerprint ~ '^[0-9a-f]{64}$'),
    CONSTRAINT simulation_succeeded_has_fingerprint CHECK (status <> 'SUCCEEDED' OR (window_fingerprint IS NOT NULL AND dependency_versions_json IS NOT NULL)),
    CONSTRAINT simulation_deps_versioned CHECK ((dependency_versions_json IS NULL) = (dependency_versions_schema_version IS NULL)),
    CONSTRAINT simulation_times CHECK ((started_at IS NULL OR started_at >= queued_at) AND (finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at))
);
CREATE UNIQUE INDEX simulation_one_running_per_tenant ON allocation.simulation (tenant_id) WHERE status IN ('INPUT_PUBLISHING', 'RUNNING');
CREATE UNIQUE INDEX simulation_idempotency_uq ON allocation.simulation (tenant_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX simulation_subject_idx ON allocation.simulation (tenant_id, subject_type, subject_id, queued_at DESC);
CREATE INDEX simulation_queue_idx ON allocation.simulation (queued_at) WHERE status = 'QUEUED';
CREATE INDEX simulation_expiry_idx ON allocation.simulation (expires_at) WHERE status IN ('SUCCEEDED', 'FAILED', 'CANCELLED');
CREATE INDEX simulation_daily_quota_idx ON allocation.simulation (tenant_id, queued_at);
COMMENT ON TABLE allocation.simulation IS 'Allocation simulation pinned to (input_publication_id, [window_start, window_end), scope, content_sha256). Executed as a Dagster dbt job (allocation_sim selector, transform identity; RECONCILIATION C-05); analysis_job_id links the API-004 job record used for status/cancel. Results: Snowflake SIMULATION.* keyed by simulation_id, TTL 14 days. Window default 90 days, max hot_days (365 by default, D-11). Quota 30/tenant/UTC day. owner_task=ALC-003.';
COMMENT ON COLUMN allocation.simulation.scope_json IS 'Versioned scope {account_ids?, organization_ids?} (IDs only); empty = every account of the tenant. privacy=CUSTOMER_METADATA.';
COMMENT ON COLUMN allocation.simulation.window_fingerprint IS 'sha256 hex of the ordered (charge_id, charge_revision) list of charges in window∩scope at input_publication_id (G-ALC-07).';

-- Queue-claim policy for the simulation scheduler (cross-tenant claim of QUEUED rows; SEC RLS standard template (c)).
-- The scheduler runs as bridge_worker; see contracts/_handoffs/K7.md (role names owned by K2).

-- ============================================================================================================
-- 2. Access-impact reviews (ALC-003-S05, ALC-101) — bounded counts + digest; detail rows in SIMULATION.SIM_ACCESS_IMPACT
-- ============================================================================================================
CREATE TABLE allocation.access_impact_review (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    simulation_id              uuid        NOT NULL,
    subject_type               text        NOT NULL,
    subject_id                 uuid        NOT NULL,
    computed_for               text        NOT NULL,
    grants_digest              text        NOT NULL,
    impact_digest              text        NOT NULL,
    access_relevant            boolean     NOT NULL,
    affected_group_count       integer     NOT NULL,
    affected_profile_count     integer     NOT NULL,
    affected_member_count      integer     NOT NULL,
    widened_member_count       integer     NOT NULL,
    entering_subject_count     bigint      NOT NULL,
    leaving_subject_count      bigint      NOT NULL,
    computed_at                timestamptz NOT NULL DEFAULT now(),
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT access_impact_review_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT access_impact_review_simulation_fk FOREIGN KEY (tenant_id, simulation_id)
        REFERENCES allocation.simulation (tenant_id, id),
    CONSTRAINT access_impact_review_subject_type CHECK (subject_type IN ('RULESET', 'HIERARCHY', 'ALLOCATION_POLICY', 'POOL_DISCLOSURE')),
    CONSTRAINT access_impact_review_computed_for CHECK (computed_for IN ('SIMULATION', 'APPROVAL_RECHECK', 'PUBLISH_RECHECK')),
    CONSTRAINT access_impact_review_digests CHECK (grants_digest ~ '^[0-9a-f]{64}$' AND impact_digest ~ '^[0-9a-f]{64}$'),
    CONSTRAINT access_impact_review_relevant CHECK (access_relevant = (entering_subject_count > 0)),
    CONSTRAINT access_impact_review_counts CHECK (affected_group_count >= 0 AND affected_profile_count >= 0 AND affected_member_count >= 0
        AND widened_member_count >= 0 AND entering_subject_count >= 0 AND leaving_subject_count >= 0)
);
CREATE INDEX access_impact_review_subject_idx ON allocation.access_impact_review (tenant_id, subject_type, subject_id, computed_at DESC);
COMMENT ON TABLE allocation.access_impact_review IS 'Access impact of a candidate vs the published baseline for every (group_set, group) referenced by an active grant clause (ancestors via closure): subjects/charges/amount entering and leaving, affected profiles and members whose visible scope widens. access_relevant iff any entering set is non-empty. Recomputed at approval and at publish (PUBLISH_RECHECK); a digest differing from the ACCESS approval binding → 409 ALLOC_ACCESS_REVIEW_STALE. Spec docs/11-allocation/alc-access-impact-and-disclosure.md. owner_task=ALC-003-S05.';

CREATE TABLE allocation.access_impact_profile (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    review_id                  uuid        NOT NULL,
    profile_id                 uuid        NOT NULL,
    group_set_id               uuid        NOT NULL,
    group_id                   uuid        NOT NULL,
    member_count               integer     NOT NULL,
    entering_subject_count     bigint      NOT NULL,
    leaving_subject_count      bigint      NOT NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT access_impact_profile_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT access_impact_profile_review_fk FOREIGN KEY (tenant_id, review_id)
        REFERENCES allocation.access_impact_review (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT access_impact_profile_group_fk FOREIGN KEY (tenant_id, group_set_id, group_id)
        REFERENCES governance.usage_group (tenant_id, group_set_id, id),
    CONSTRAINT access_impact_profile_uq UNIQUE (tenant_id, review_id, profile_id, group_id)
);
COMMENT ON TABLE allocation.access_impact_profile IS 'Affected permission profiles per granted group of an access-impact review (bounded: <= 200 active profiles per tenant). owner_task=ALC-003-S05.';

-- ============================================================================================================
-- 3. Allocation policy versions (ALC-005-S02, ALC-006-S03) — state machine ruleset.yaml; book_id = group_set id
-- ============================================================================================================
CREATE TABLE allocation.policy_version (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    book_id                    uuid        NOT NULL,
    version_no                 integer     NOT NULL,
    status                     text        NOT NULL DEFAULT 'DRAFT',
    based_on_version_id        uuid        NULL,
    rollback_of_version_id     uuid        NULL,
    effective_from             date        NOT NULL,
    apply_from                 text        NOT NULL DEFAULT 'AS_REQUESTED',
    content_json               jsonb       NOT NULL,
    content_schema_version     text        NOT NULL DEFAULT 'allocation-policy.v1',
    content_sha256             text        NULL,
    min_valid_from             date        NULL,
    seed_version               text        NULL,
    access_relevant            boolean     NULL,
    simulation_id              uuid        NULL,
    window_fingerprint         text        NULL,
    dependency_versions_json   jsonb       NULL,
    dependency_versions_schema_version text NULL,
    config_version             bigint      NULL,
    publication_requested_at   timestamptz NULL,
    published_at               timestamptz NULL,
    superseded_at              timestamptz NULL,
    superseded_by_version_id   uuid        NULL,
    failure_code               text        NULL,
    created_by                 uuid        NOT NULL,
    updated_by                 uuid        NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT policy_version_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT policy_version_book_fk FOREIGN KEY (tenant_id, book_id)
        REFERENCES governance.usage_group_set (tenant_id, id),
    CONSTRAINT policy_version_based_on_fk FOREIGN KEY (tenant_id, based_on_version_id)
        REFERENCES allocation.policy_version (tenant_id, id),
    CONSTRAINT policy_version_rollback_of_fk FOREIGN KEY (tenant_id, rollback_of_version_id)
        REFERENCES allocation.policy_version (tenant_id, id),
    CONSTRAINT policy_version_uq UNIQUE (tenant_id, book_id, version_no),
    CONSTRAINT policy_version_status CHECK (status IN ('DRAFT', 'SIMULATING', 'SIMULATION_FAILED', 'REVIEWABLE',
        'APPROVED', 'STALE', 'PUBLISHING', 'PUBLISH_FAILED', 'PUBLISHED', 'SUPERSEDED', 'DISCARDED')),
    CONSTRAINT policy_version_apply_from CHECK (apply_from IN ('AS_REQUESTED', 'FIRST_OPEN_PERIOD')),
    CONSTRAINT policy_version_hash_frozen CHECK (status = 'DRAFT' OR status = 'DISCARDED' OR content_sha256 IS NOT NULL),
    CONSTRAINT policy_version_hash_format CHECK (content_sha256 IS NULL OR content_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT policy_version_seed CHECK (seed_version IS NULL OR seed_version ~ '^default_book_v[0-9]+$'),
    CONSTRAINT policy_version_size CHECK (octet_length(content_json::text) <= 262144),
    CONSTRAINT policy_version_published_has_config CHECK (status NOT IN ('PUBLISHING', 'PUBLISHED', 'SUPERSEDED') OR config_version IS NOT NULL),
    CONSTRAINT policy_version_deps_versioned CHECK ((dependency_versions_json IS NULL) = (dependency_versions_schema_version IS NULL))
);
CREATE UNIQUE INDEX policy_version_one_published_uq ON allocation.policy_version (tenant_id, book_id) WHERE status = 'PUBLISHED';
CREATE UNIQUE INDEX policy_version_one_publishing_uq ON allocation.policy_version (tenant_id, book_id) WHERE status = 'PUBLISHING';
CREATE INDEX policy_version_tenant_status_idx ON allocation.policy_version (tenant_id, status, updated_at DESC);
COMMENT ON TABLE allocation.policy_version IS 'Allocation policy of a book (data/contracts/allocation-policy.json): family selector → component → method → params → fallback chain; pools; residual. Exactly one PUBLISHED version per book; the published CONFIG.cfg_allocation_policy snapshot carries the full effective-dated timeline of published versions (bitemporal). Content immutable once status <> DRAFT (trigger). owner_task=ALC-005-S02 (contract), ALC-006-S03 (API).';

CREATE OR REPLACE FUNCTION allocation.tg_policy_content_immutable() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status <> 'DRAFT' AND (NEW.content_json IS DISTINCT FROM OLD.content_json
        OR NEW.content_sha256 IS DISTINCT FROM OLD.content_sha256
        OR NEW.effective_from IS DISTINCT FROM OLD.effective_from
        OR NEW.book_id IS DISTINCT FROM OLD.book_id) THEN
        RAISE EXCEPTION 'content of policy version % is immutable in status %', OLD.id, OLD.status USING ERRCODE = 'BL701';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER policy_version_content_immutable BEFORE UPDATE ON allocation.policy_version
    FOR EACH ROW EXECUTE FUNCTION allocation.tg_policy_content_immutable();

-- ============================================================================================================
-- 4. Pool / idle disclosure settings (ALC-101-S05, G-ALC-03)
-- ============================================================================================================
CREATE TABLE allocation.pool_disclosure (
    tenant_id                  uuid        NOT NULL,
    id                         uuid        NOT NULL,
    book_id                    uuid        NOT NULL,
    pool_kind                  text        NOT NULL,
    pool_ref                   text        NOT NULL,
    disclosure_level           text        NOT NULL DEFAULT 'CONCEALED',
    acknowledged_by            uuid        NULL,
    acknowledged_at            timestamptz NULL,
    acknowledgement_text_version text      NULL,
    consumer_count_at_ack      integer     NULL,
    small_consumer_warning_shown boolean   NOT NULL DEFAULT false,
    effective_from             timestamptz NOT NULL DEFAULT now(),
    superseded_at              timestamptz NULL,
    config_version             bigint      NULL,
    created_by                 uuid        NOT NULL,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    revision                   bigint      NOT NULL DEFAULT 1,
    CONSTRAINT pool_disclosure_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT pool_disclosure_book_fk FOREIGN KEY (tenant_id, book_id)
        REFERENCES governance.usage_group_set (tenant_id, id),
    CONSTRAINT pool_disclosure_kind CHECK (pool_kind IN ('IDLE', 'SHARED_POOL', 'HOUR_RESIDUAL')),
    CONSTRAINT pool_disclosure_ref CHECK (pool_ref = '*' OR pool_ref ~ '^[A-Za-z0-9_.:-]{1,128}$'),
    CONSTRAINT pool_disclosure_level CHECK (disclosure_level IN ('CONCEALED', 'DISCLOSED')),
    CONSTRAINT pool_disclosure_ack CHECK (disclosure_level = 'CONCEALED'
        OR (acknowledged_by IS NOT NULL AND acknowledged_at IS NOT NULL AND acknowledgement_text_version IS NOT NULL)),
    CONSTRAINT pool_disclosure_small_k_warning CHECK (disclosure_level = 'CONCEALED' OR consumer_count_at_ack IS NULL
        OR consumer_count_at_ack > 2 OR small_consumer_warning_shown)
);
CREATE UNIQUE INDEX pool_disclosure_current_uq ON allocation.pool_disclosure (tenant_id, book_id, pool_kind, pool_ref) WHERE superseded_at IS NULL;
COMMENT ON TABLE allocation.pool_disclosure IS 'Per-pool / idle disclosure: CONCEALED (default; team readers see only their own allocated amount and the policy text) or DISCLOSED (pool total visible to consuming groups; requires an Organization Admin/Owner acknowledgement recorded here; when the pool has <= 2 consumers the UI must show the "others identifies one group" warning first). pool_ref = warehouse subject id (IDLE/HOUR_RESIDUAL), pool_key (SHARED_POOL) or ''*'' (all pools of that kind in the book). Changing it is access-relevant: permission_epoch bump via SEC-006. Published as CONFIG.cfg_pool_disclosure. owner_task=ALC-101-S05.';

-- ============================================================================================================
-- 5. Manual transfers (ALC-103-S04/S05) — state machine allocation_transfer.yaml
-- ============================================================================================================
CREATE TABLE allocation.transfer (
    tenant_id                  uuid          NOT NULL,
    id                         uuid          NOT NULL,
    book_id                    uuid          NOT NULL,
    from_group_id              uuid          NOT NULL,
    to_group_id                uuid          NOT NULL,
    amount                     numeric(38,12) NOT NULL,
    currency                   char(3)       NOT NULL,
    accounting_period          text          NOT NULL,
    target_period              text          NULL,
    clamped_from_period        text          NULL,
    reason                     text          NOT NULL,
    status                     text          NOT NULL DEFAULT 'REQUESTED',
    reverses_transfer_id       uuid          NULL,
    requested_by               uuid          NOT NULL,
    approval_id                uuid          NULL,
    config_version             bigint        NULL,
    published_at               timestamptz   NULL,
    failure_code               text          NULL,
    idempotency_key            text          NULL,
    created_at                 timestamptz   NOT NULL DEFAULT now(),
    updated_at                 timestamptz   NOT NULL DEFAULT now(),
    revision                   bigint        NOT NULL DEFAULT 1,
    CONSTRAINT transfer_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT transfer_book_fk FOREIGN KEY (tenant_id, book_id)
        REFERENCES governance.usage_group_set (tenant_id, id),
    CONSTRAINT transfer_from_fk FOREIGN KEY (tenant_id, book_id, from_group_id)
        REFERENCES governance.usage_group (tenant_id, group_set_id, id),
    CONSTRAINT transfer_to_fk FOREIGN KEY (tenant_id, book_id, to_group_id)
        REFERENCES governance.usage_group (tenant_id, group_set_id, id),
    CONSTRAINT transfer_reverses_fk FOREIGN KEY (tenant_id, reverses_transfer_id)
        REFERENCES allocation.transfer (tenant_id, id),
    CONSTRAINT transfer_distinct_groups CHECK (from_group_id <> to_group_id),
    CONSTRAINT transfer_amount_positive CHECK (amount > 0),
    CONSTRAINT transfer_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT transfer_periods CHECK (accounting_period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
        AND (target_period IS NULL OR target_period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$')
        AND (clamped_from_period IS NULL OR clamped_from_period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$')),
    CONSTRAINT transfer_reason_len CHECK (char_length(reason) BETWEEN 10 AND 2000),
    CONSTRAINT transfer_status CHECK (status IN ('REQUESTED', 'APPROVED', 'PUBLISHING', 'PUBLISHED', 'REJECTED', 'CANCELLED')),
    CONSTRAINT transfer_published CHECK ((status = 'PUBLISHED') = (published_at IS NOT NULL)),
    CONSTRAINT transfer_target_period_when_approved CHECK (status IN ('REQUESTED', 'REJECTED', 'CANCELLED') OR target_period IS NOT NULL)
);
CREATE UNIQUE INDEX transfer_idempotency_uq ON allocation.transfer (tenant_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX transfer_one_reversal_uq ON allocation.transfer (tenant_id, reverses_transfer_id) WHERE reverses_transfer_id IS NOT NULL AND status NOT IN ('REJECTED', 'CANCELLED');
CREATE INDEX transfer_book_period_idx ON allocation.transfer (tenant_id, book_id, target_period, status);
COMMENT ON TABLE allocation.transfer IS 'Approved book-level manual transfer (from, to, amount, period, currency) → two allocation lines ±amount with charge_id NULL, method MANUAL_TRANSFER. Σ transfer lines = 0 per book × period × currency; charges are never altered. Closed period → clamped to the next open period (clamped_from_period). Reversal = new opposite transfer. owner_task=ALC-103-S04.';
COMMENT ON COLUMN allocation.transfer.amount IS 'Positive transfer amount (NUMERIC(38,12)); configuration, not an analytical mirror. privacy=INTERNAL.';
COMMENT ON COLUMN allocation.transfer.reason IS 'privacy=CUSTOMER_METADATA.';

-- ============================================================================================================
-- 6. Row level security (SEC RLS standard template)
-- ============================================================================================================
ALTER TABLE allocation.simulation ENABLE ROW LEVEL SECURITY;
ALTER TABLE allocation.simulation FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON allocation.simulation
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
-- Queue template (c): the simulation scheduler claims QUEUED rows across tenants (allowlisted in the RLS lint).
CREATE POLICY scheduler_claim_select ON allocation.simulation FOR SELECT TO bridge_worker
    USING (status IN ('QUEUED', 'INPUT_PUBLISHING', 'RUNNING'));
CREATE POLICY scheduler_claim_update ON allocation.simulation FOR UPDATE TO bridge_worker
    USING (status IN ('QUEUED', 'INPUT_PUBLISHING', 'RUNNING'))
    WITH CHECK (true);

ALTER TABLE allocation.access_impact_review ENABLE ROW LEVEL SECURITY;
ALTER TABLE allocation.access_impact_review FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON allocation.access_impact_review
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE allocation.access_impact_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE allocation.access_impact_profile FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON allocation.access_impact_profile
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE allocation.policy_version ENABLE ROW LEVEL SECURITY;
ALTER TABLE allocation.policy_version FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON allocation.policy_version
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE allocation.pool_disclosure ENABLE ROW LEVEL SECURITY;
ALTER TABLE allocation.pool_disclosure FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON allocation.pool_disclosure
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE allocation.transfer ENABLE ROW LEVEL SECURITY;
ALTER TABLE allocation.transfer FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON allocation.transfer
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- ============================================================================================================
-- 7. Cross-lane foreign keys (identity.* from lane K2; see contracts/_handoffs/K7.md)
-- ============================================================================================================
ALTER TABLE allocation.access_impact_profile ADD CONSTRAINT access_impact_profile_profile_fk
    FOREIGN KEY (tenant_id, profile_id) REFERENCES identity.permission_profile (tenant_id, id);

-- contract=postgres-onboarding version=1 status=DRAFT owner_task=ONB-001 decisions=D-08,D-09,D-13,D-17,D-35,D-38 last_changed=2026-09-28
-- Contract lane: K9. Schema file owner: K9 (contracts/README.md). Alembic migration `onboarding_0001` (ONB-001-S02) converges to this file.
--
-- Design (G-ONB-01): onboarding step status is a PROJECTION of domain facts plus an append-only acknowledgement
-- ledger; no analytical totals are stored here (PRD §57). Tables (backlog name -> contract name):
--   runs                  -> onboarding.run                   ONB-001-S02  resumable run; one ACTIVE/PAUSED run per tenant
--   step_acknowledgements -> onboarding.step_acknowledgement  ONB-001-S02  INSERT-only, bound to an exact domain revision
--   step_projection       -> onboarding.step_projection       ONB-001-S02  cached projection with the source versions it was computed from
--   manual_interventions  -> onboarding.manual_intervention   ONB-001-S14  operator actions during onboarding (G-ONB-05, D-38)
--   (new)                 -> onboarding.estimate              ONB-101-S01  immutable estimate documents; consent binds to (estimate id, inputs sha)
-- State machine: contracts/state-machines/onboarding.yaml; step statuses/keys: docs/onboarding/state-machine.md.

CREATE SCHEMA IF NOT EXISTS onboarding;
COMMENT ON SCHEMA onboarding IS 'Guided onboarding as a projection of domain state (ONB-001/ONB-101). Owner lane K9.';

CREATE OR REPLACE FUNCTION onboarding.forbid_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'onboarding.%: % is forbidden on an append-only table', TG_TABLE_NAME, TG_OP
    USING ERRCODE = '42501';
END;
$$;

-- =============================================================================================
-- onboarding.run
-- =============================================================================================
CREATE TABLE onboarding.run (
  tenant_id             uuid        NOT NULL,
  id                    uuid        NOT NULL,
  status                text        NOT NULL DEFAULT 'ACTIVE',
  created_by            uuid        NOT NULL,
  started_at            timestamptz NOT NULL DEFAULT now(),
  paused_at             timestamptz NULL,
  pause_reason_code     text        NULL,
  resumed_at            timestamptz NULL,
  demonstration_only    boolean     NOT NULL DEFAULT false,
  fv1_accepted_at       timestamptz NULL,
  fv1_decision          text        NULL,
  fv1_acceptance_ref    text        NULL,
  fv2_review_due_on     date        NULL,
  abandoned_at          timestamptz NULL,
  abandon_reason_code   text        NULL,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  revision              bigint      NOT NULL DEFAULT 1,
  CONSTRAINT run_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT run_status_ck CHECK (status IN ('ACTIVE','PAUSED','FV1_ACCEPTED','ABANDONED')),
  CONSTRAINT run_paused_ck CHECK ((status = 'PAUSED') = (paused_at IS NOT NULL AND pause_reason_code IS NOT NULL)),
  CONSTRAINT run_pause_reason_ck CHECK (pause_reason_code IS NULL OR pause_reason_code IN ('CUSTOMER_REQUEST','CUSTOMER_CHANGE_WINDOW','BUDGET_REVIEW','SUBSCRIPTION_SUSPENDED','OPERATOR_HOLD')),
  CONSTRAINT run_fv1_ck CHECK ((status = 'FV1_ACCEPTED') = (fv1_accepted_at IS NOT NULL AND fv1_decision IS NOT NULL AND fv1_acceptance_ref IS NOT NULL)),
  CONSTRAINT run_fv1_decision_ck CHECK (fv1_decision IS NULL OR fv1_decision IN ('ACCEPTED','ACCEPTED_WITH_DISCLOSED_LIMITS')),
  CONSTRAINT run_fv1_not_demo_ck CHECK (NOT (status = 'FV1_ACCEPTED' AND demonstration_only)),
  CONSTRAINT run_abandoned_ck CHECK ((status = 'ABANDONED') = (abandoned_at IS NOT NULL AND abandon_reason_code IS NOT NULL)),
  CONSTRAINT run_abandon_reason_ck CHECK (abandon_reason_code IS NULL OR abandon_reason_code IN ('CUSTOMER_WITHDREW','TENANT_OFFBOARDING','REPLACED_BY_NEW_RUN','PILOT_NOT_CONVERTED')),
  CONSTRAINT run_revision_ck CHECK (revision >= 1)
);
CREATE UNIQUE INDEX run_one_open_per_tenant ON onboarding.run (tenant_id) WHERE status IN ('ACTIVE','PAUSED');
CREATE INDEX run_tenant_status_idx ON onboarding.run (tenant_id, status, started_at);
COMMENT ON TABLE onboarding.run IS 'ONB-001. Resumable onboarding run. POST /v1/onboarding/runs is idempotent (Idempotency-Key) and at most one ACTIVE or PAUSED run exists per tenant. PAUSED delegates to sync pause (CON-006/ING-010); it never deletes coverage.';
COMMENT ON COLUMN onboarding.run.created_by IS 'x-privacy: INTERNAL. Membership id (identity schema, K2) of the member who started the run.';
COMMENT ON COLUMN onboarding.run.demonstration_only IS 'D-35: true while every connected account of the tenant is a Snowflake trial account (TRUE or unattested UNKNOWN); such a run can never reach FV1_ACCEPTED.';
COMMENT ON COLUMN onboarding.run.fv1_acceptance_ref IS 'x-privacy: INTERNAL. Reference of the signed FV-1 acceptance record kept in the private customer system (ONB-005-S07); no customer data here.';
COMMENT ON COLUMN onboarding.run.fv2_review_due_on IS 'First full post-enrollment month end + 5 days (G-ONB-03); reviewed by LCH-004.';

-- =============================================================================================
-- onboarding.estimate  (ONB-101) - immutable
-- =============================================================================================
CREATE TABLE onboarding.estimate (
  tenant_id                uuid        NOT NULL,
  id                       uuid        NOT NULL,
  run_id                   uuid        NULL,
  estimate_json            jsonb       NOT NULL,
  estimate_schema_version  smallint    NOT NULL DEFAULT 1,
  inputs_sha256            text        NOT NULL,
  coefficients_version     text        NOT NULL,
  estimator_version        text        NOT NULL,
  entitlement_id           uuid        NULL,
  entitlement_version      integer     NULL,
  created_by               uuid        NOT NULL,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  revision                 bigint      NOT NULL DEFAULT 1,
  CONSTRAINT estimate_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT estimate_run_fk FOREIGN KEY (tenant_id, run_id) REFERENCES onboarding.run (tenant_id, id),
  CONSTRAINT estimate_schema_ck CHECK (estimate_schema_version = 1),
  CONSTRAINT estimate_sha_ck CHECK (inputs_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT estimate_obj_ck CHECK (jsonb_typeof(estimate_json) = 'object'),
  CONSTRAINT estimate_append_only_ck CHECK (revision = 1)
);
CREATE INDEX estimate_run_idx ON onboarding.estimate (tenant_id, run_id, created_at);
CREATE TRIGGER estimate_append_only BEFORE UPDATE OR DELETE ON onboarding.estimate
  FOR EACH ROW EXECUTE FUNCTION onboarding.forbid_mutation();
COMMENT ON TABLE onboarding.estimate IS 'ONB-101-S01. Immutable pre-consent estimate (data/estimates/onboarding-estimate.v1.json). Credit ranges come from the CON-101-S01 estimator, backfill coefficients from OPS-105-S06. A consent acknowledgement binds to (estimate id, inputs_sha256); a changed selection produces a new estimate and invalidates the consent.';
COMMENT ON COLUMN onboarding.estimate.estimate_json IS 'x-privacy: CUSTOMER_METADATA. Document validated by onboarding-estimate.v1.json (account ids, source ids, ranges, volumes; no names).';

-- =============================================================================================
-- onboarding.step_acknowledgement  (INSERT-only)
-- =============================================================================================
CREATE TABLE onboarding.step_acknowledgement (
  tenant_id            uuid        NOT NULL,
  id                   uuid        NOT NULL,
  run_id               uuid        NOT NULL,
  step_key             text        NOT NULL,
  account_id           uuid        NULL,
  ack_type             text        NOT NULL,
  bound_ref_type       text        NOT NULL,
  bound_ref            uuid        NOT NULL,
  bound_revision       bigint      NOT NULL,
  entitlement_id       uuid        NULL,
  entitlement_version  integer     NULL,
  reason_code          text        NULL,
  payload_sha256       text        NOT NULL,
  actor_membership_id  uuid        NOT NULL,
  actor_capability     text        NOT NULL,
  idempotency_key      text        NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  revision             bigint      NOT NULL DEFAULT 1,
  CONSTRAINT step_ack_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT step_ack_run_fk FOREIGN KEY (tenant_id, run_id) REFERENCES onboarding.run (tenant_id, id),
  CONSTRAINT step_ack_step_ck CHECK (step_key IN ('ORG_CREATED','SNOWFLAKE_ORG_CONNECTED','ACCOUNTS_DISCOVERED','ACCOUNTS_SELECTED','ACCOUNT_WIF_INSTALLED',
      'CAPABILITIES_VERIFIED','HISTORY_PLAN_ACCEPTED','HISTORY_SYNCED','RECONCILED','OWNERSHIP_CLASSIFIED','ALLOCATION_SIMULATED',
      'BUDGET_CREATED','MONITORS_CREATED','INSIGHT_REVIEWED','FIRST_VALUE_PACK')),
  CONSTRAINT step_ack_type_ck CHECK (ack_type IN ('OPTIONAL_SKIP','CAPABILITY_DIFFERENCES_ACCEPTED','GAP_ACCEPTANCE','BACKFILL_CONSENT',
      'LIMITATION_ACCEPTANCE','TRIAL_PAID_ATTESTATION','NO_INSIGHT_CANDIDATE','FIRST_VALUE_ACCEPTANCE')),
  CONSTRAINT step_ack_ref_type_ck CHECK (bound_ref_type IN ('ONBOARDING_RUN','CONNECTION','CAPABILITY_PROBE','BACKFILL_PLAN','ONBOARDING_ESTIMATE',
      'RECONCILIATION_RUN','INSIGHT_REVIEW')),
  -- ack type -> step and bound reference (docs/onboarding/state-machine.md §4)
  CONSTRAINT step_ack_binding_ck CHECK (
       (ack_type = 'OPTIONAL_SKIP'                   AND step_key IN ('SNOWFLAKE_ORG_CONNECTED','OWNERSHIP_CLASSIFIED','INSIGHT_REVIEWED') AND bound_ref_type = 'ONBOARDING_RUN' AND reason_code IS NOT NULL)
    OR (ack_type = 'CAPABILITY_DIFFERENCES_ACCEPTED' AND step_key = 'CAPABILITIES_VERIFIED' AND bound_ref_type = 'CAPABILITY_PROBE' AND account_id IS NOT NULL)
    OR (ack_type = 'TRIAL_PAID_ATTESTATION'          AND step_key = 'CAPABILITIES_VERIFIED' AND bound_ref_type = 'CAPABILITY_PROBE' AND account_id IS NOT NULL)
    OR (ack_type = 'GAP_ACCEPTANCE'                  AND step_key = 'HISTORY_PLAN_ACCEPTED' AND bound_ref_type = 'BACKFILL_PLAN')
    OR (ack_type = 'BACKFILL_CONSENT'                AND step_key = 'HISTORY_PLAN_ACCEPTED' AND bound_ref_type = 'ONBOARDING_ESTIMATE' AND entitlement_id IS NOT NULL AND entitlement_version IS NOT NULL)
    OR (ack_type = 'LIMITATION_ACCEPTANCE'           AND step_key = 'RECONCILED' AND bound_ref_type = 'RECONCILIATION_RUN')
    OR (ack_type = 'NO_INSIGHT_CANDIDATE'            AND step_key = 'INSIGHT_REVIEWED' AND bound_ref_type = 'INSIGHT_REVIEW')
    OR (ack_type = 'FIRST_VALUE_ACCEPTANCE'          AND step_key = 'FIRST_VALUE_PACK' AND bound_ref_type = 'ONBOARDING_RUN')),
  CONSTRAINT step_ack_skip_reason_ck CHECK (reason_code IS NULL OR reason_code IN ('STANDALONE_ACCOUNTS_ONLY','ORG_ACCESS_UNAVAILABLE','NO_OWNERSHIP_DIMENSION_YET',
      'NO_ELIGIBLE_INSIGHT','CUSTOMER_DEFERRED')),
  CONSTRAINT step_ack_revision_bound_ck CHECK (bound_revision >= 1),
  CONSTRAINT step_ack_sha_ck CHECK (payload_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT step_ack_append_only_ck CHECK (revision = 1)
);
CREATE INDEX step_ack_lookup_idx ON onboarding.step_acknowledgement (tenant_id, run_id, step_key, account_id, created_at DESC);
CREATE UNIQUE INDEX step_ack_idempotency ON onboarding.step_acknowledgement (tenant_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE TRIGGER step_ack_append_only BEFORE UPDATE OR DELETE ON onboarding.step_acknowledgement
  FOR EACH ROW EXECUTE FUNCTION onboarding.forbid_mutation();
COMMENT ON TABLE onboarding.step_acknowledgement IS 'ONB-001-S02/S05. Append-only ledger of human decisions, each bound to the exact domain revision it acknowledges (bound_ref_type, bound_ref, bound_revision). The projection honours an acknowledgement only while bound_revision equals the current revision of bound_ref; a new backfill plan revision, estimate, probe or reconciliation run silently invalidates older acknowledgements (no UPDATE ever).';
COMMENT ON COLUMN onboarding.step_acknowledgement.actor_membership_id IS 'x-privacy: INTERNAL. Membership id of the acknowledging member (K2 identity schema).';
COMMENT ON COLUMN onboarding.step_acknowledgement.actor_capability IS 'Capability the actor held when acknowledging (docs/onboarding/state-machine.md §4), e.g. onboarding.consent for BACKFILL_CONSENT, onboarding.limitation.accept for LIMITATION_ACCEPTANCE.';
COMMENT ON COLUMN onboarding.step_acknowledgement.payload_sha256 IS 'sha256 of the canonical JSON of the acknowledgement request body (RFC 8785 JCS) - proves what was shown and accepted.';
COMMENT ON COLUMN onboarding.step_acknowledgement.entitlement_version IS 'BACKFILL_CONSENT: entitlement snapshot (commercial.tenant_entitlement) the consent was given under.';

-- =============================================================================================
-- onboarding.step_projection  (cached projection; recomputed on domain events + 10-minute sweep)
-- =============================================================================================
CREATE TABLE onboarding.step_projection (
  tenant_id                        uuid        NOT NULL,
  id                               uuid        NOT NULL,
  run_id                           uuid        NOT NULL,
  step_key                         text        NOT NULL,
  account_id                       uuid        NULL,
  status                           text        NOT NULL,
  status_code                      text        NULL,
  status_text                      text        NULL,
  progress_done                    integer     NULL,
  progress_total                   integer     NULL,
  source_versions_json             jsonb       NOT NULL,
  source_versions_schema_version   smallint    NOT NULL DEFAULT 1,
  projection_engine_version        text        NOT NULL,
  computed_at                      timestamptz NOT NULL,
  status_since                     timestamptz NOT NULL,
  created_at                       timestamptz NOT NULL DEFAULT now(),
  updated_at                       timestamptz NOT NULL DEFAULT now(),
  revision                         bigint      NOT NULL DEFAULT 1,
  CONSTRAINT step_proj_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT step_proj_run_fk FOREIGN KEY (tenant_id, run_id) REFERENCES onboarding.run (tenant_id, id),
  CONSTRAINT step_proj_step_ck CHECK (step_key IN ('ORG_CREATED','SNOWFLAKE_ORG_CONNECTED','ACCOUNTS_DISCOVERED','ACCOUNTS_SELECTED','ACCOUNT_WIF_INSTALLED',
      'CAPABILITIES_VERIFIED','HISTORY_PLAN_ACCEPTED','HISTORY_SYNCED','RECONCILED','OWNERSHIP_CLASSIFIED','ALLOCATION_SIMULATED',
      'BUDGET_CREATED','MONITORS_CREATED','INSIGHT_REVIEWED','FIRST_VALUE_PACK')),
  CONSTRAINT step_proj_per_account_ck CHECK (account_id IS NULL OR step_key IN ('ACCOUNT_WIF_INSTALLED','CAPABILITIES_VERIFIED','HISTORY_SYNCED','RECONCILED')),
  CONSTRAINT step_proj_status_ck CHECK (status IN ('BLOCKED_BY_PREREQ','READY','IN_PROGRESS','WAITING_ON_CUSTOMER','WAITING_ON_SYSTEM','COMPLETED',
      'COMPLETED_WITH_LIMITATIONS','FAILED','BLOCKED','SKIPPED_OPTIONAL')),
  CONSTRAINT step_proj_code_ck CHECK (CASE WHEN status IN ('BLOCKED','FAILED','COMPLETED_WITH_LIMITATIONS') THEN status_code IS NOT NULL
                                             WHEN status IN ('COMPLETED','READY','IN_PROGRESS','BLOCKED_BY_PREREQ') THEN status_code IS NULL
                                             ELSE true END),
  CONSTRAINT step_proj_code_fmt_ck CHECK (status_code IS NULL OR status_code ~ '^[A-Z][A-Z0-9_]{2,63}$'),
  CONSTRAINT step_proj_progress_ck CHECK ((progress_done IS NULL) = (progress_total IS NULL) AND (progress_total IS NULL OR (progress_total >= 0 AND progress_done BETWEEN 0 AND progress_total))),
  CONSTRAINT step_proj_versions_ck CHECK (jsonb_typeof(source_versions_json) = 'object'),
  CONSTRAINT step_proj_text_ck CHECK (status_text IS NULL OR char_length(status_text) <= 500),
  CONSTRAINT step_proj_revision_ck CHECK (revision >= 1)
);
CREATE UNIQUE INDEX step_proj_unique ON onboarding.step_projection (tenant_id, run_id, step_key, (COALESCE(account_id, '00000000-0000-0000-0000-000000000000'::uuid)));
CREATE INDEX step_proj_status_idx ON onboarding.step_projection (tenant_id, run_id, status);
CREATE INDEX step_proj_sweep_idx ON onboarding.step_projection (computed_at);
COMMENT ON TABLE onboarding.step_projection IS 'ONB-001-S03/S04. Cached output of the pure projection function (domain snapshots + acknowledgements -> statuses). Recomputed on domain outbox events and by a 10-minute sweep; never edited by hand. status_code carries the blocker code (docs/onboarding/blockers.yaml) for BLOCKED/FAILED and the limitation code for COMPLETED_WITH_LIMITATIONS.';
COMMENT ON COLUMN onboarding.step_projection.source_versions_json IS 'x-privacy: INTERNAL. {"<domain object type>": {"id": "<uuid>", "revision": <int>}, ...} - the exact domain versions (connection revision, probe id, backfill plan revision, reconciliation run id, publication pub_seq, ...) the status was computed from. Schema: docs/onboarding/state-machine.md §6.';
COMMENT ON COLUMN onboarding.step_projection.status_text IS 'x-privacy: INTERNAL. Server-rendered status text preserving the domain status verbatim (e.g. "FAILED (-1.00 USD)"); no names.';
COMMENT ON COLUMN onboarding.step_projection.progress_done IS 'Counts, never percentages (G-ONB-04): e.g. 7 of 8 accounts published.';

-- =============================================================================================
-- onboarding.manual_intervention  (ONB-001-S14; append-only except backlog_item_ref)
-- =============================================================================================
CREATE TABLE onboarding.manual_intervention (
  tenant_id          uuid        NOT NULL,
  id                 uuid        NOT NULL,
  run_id             uuid        NOT NULL,
  step_key           text        NULL,
  operator_subject   text        NOT NULL,
  reason_code        text        NOT NULL,
  ops_call_id        text        NOT NULL,
  ops_operation_id   text        NOT NULL,
  backlog_item_ref   text        NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  revision           bigint      NOT NULL DEFAULT 1,
  CONSTRAINT intervention_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT intervention_run_fk FOREIGN KEY (tenant_id, run_id) REFERENCES onboarding.run (tenant_id, id),
  CONSTRAINT intervention_call_unique UNIQUE (tenant_id, ops_call_id),
  CONSTRAINT intervention_step_ck CHECK (step_key IS NULL OR step_key IN ('ORG_CREATED','SNOWFLAKE_ORG_CONNECTED','ACCOUNTS_DISCOVERED','ACCOUNTS_SELECTED','ACCOUNT_WIF_INSTALLED',
      'CAPABILITIES_VERIFIED','HISTORY_PLAN_ACCEPTED','HISTORY_SYNCED','RECONCILED','OWNERSHIP_CLASSIFIED','ALLOCATION_SIMULATED',
      'BUDGET_CREATED','MONITORS_CREATED','INSIGHT_REVIEWED','FIRST_VALUE_PACK')),
  CONSTRAINT intervention_operator_ck CHECK (operator_subject ~ '^operator:[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT intervention_reason_ck CHECK (reason_code IN ('GRANT_FIX_ASSISTANCE','SCRIPT_EXECUTION_SUPPORT','NETWORK_ALLOWLIST_SUPPORT','BACKFILL_REPLAN',
      'REPLAY','RECONCILIATION_INVESTIGATION','CONFIGURATION_ON_BEHALF','ENTITLEMENT_ADJUSTMENT','OTHER')),
  CONSTRAINT intervention_revision_ck CHECK (revision >= 1)
);
CREATE INDEX intervention_run_idx ON onboarding.manual_intervention (tenant_id, run_id, created_at);
COMMENT ON TABLE onboarding.manual_intervention IS 'ONB-001-S14 (G-ONB-05, D-38). Every ops-API call carrying X-Bridge-Onboarding-Run-Id during an ACTIVE/PAUSED run records one row; each row becomes a product backlog item (ONB-003-S10, ONB-005-S10). Only backlog_item_ref may be updated.';
COMMENT ON COLUMN onboarding.manual_intervention.operator_subject IS 'x-privacy: INTERNAL. operator:<IAM Identity Center user id>.';
COMMENT ON COLUMN onboarding.manual_intervention.ops_call_id IS 'request_id of the ops API call (contracts/openapi/paths/ops.yaml) that performed the intervention.';

-- =============================================================================================
-- RLS and grants
-- =============================================================================================
ALTER TABLE onboarding.run ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboarding.run FORCE ROW LEVEL SECURITY;
ALTER TABLE onboarding.estimate ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboarding.estimate FORCE ROW LEVEL SECURITY;
ALTER TABLE onboarding.step_acknowledgement ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboarding.step_acknowledgement FORCE ROW LEVEL SECURITY;
ALTER TABLE onboarding.step_projection ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboarding.step_projection FORCE ROW LEVEL SECURITY;
ALTER TABLE onboarding.manual_intervention ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboarding.manual_intervention FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON onboarding.run
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON onboarding.estimate
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON onboarding.step_acknowledgement
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON onboarding.step_projection
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON onboarding.manual_intervention
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
-- Allowlisted cross-tenant reader: the 10-minute projection sweep lists stale projections of all tenants
-- and then recomputes each tenant inside its own tenant transaction.
CREATE POLICY step_projection_sweep_read ON onboarding.step_projection FOR SELECT TO bridge_retention USING (true);

REVOKE ALL ON ALL TABLES IN SCHEMA onboarding FROM PUBLIC;
GRANT USAGE ON SCHEMA onboarding TO bridge_api, bridge_worker, bridge_ops_api, bridge_retention;
GRANT SELECT, INSERT, UPDATE ON onboarding.run TO bridge_api, bridge_worker;
GRANT SELECT, INSERT ON onboarding.estimate TO bridge_api, bridge_worker;
GRANT SELECT, INSERT ON onboarding.step_acknowledgement TO bridge_api;
GRANT SELECT ON onboarding.step_acknowledgement TO bridge_worker;
GRANT SELECT, INSERT, UPDATE ON onboarding.step_projection TO bridge_worker;
GRANT SELECT ON onboarding.step_projection TO bridge_api, bridge_retention;
GRANT SELECT, INSERT ON onboarding.manual_intervention TO bridge_ops_api;
GRANT UPDATE (backlog_item_ref, updated_at, revision) ON onboarding.manual_intervention TO bridge_ops_api;
GRANT SELECT ON onboarding.manual_intervention TO bridge_api;
GRANT SELECT ON onboarding.run TO bridge_ops_api;

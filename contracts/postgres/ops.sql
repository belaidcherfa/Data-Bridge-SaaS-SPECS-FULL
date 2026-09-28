-- contract=postgres-ops version=1 status=DRAFT owner_task=REL-001,REL-002,REL-004 decisions=D-19,D-21,D-25 last_changed=2026-09-28
-- Contract lane: K9 owns `ops` except ops.serving_* (K6: ops.serving_partition_stats, ops.serving_dimension_ndv).
-- Operational facts with tenant or batch detail (batch timeline, SLI events, task usage, processing/build rows, cost) live in the
-- central Snowflake OPS_INTERNAL schema and BRIDGE_INTERNAL_COST database, never in PostgreSQL (PRD §57, G-OPS-18).
-- This file holds the release control records used by the ops API and the release pipeline:
--   ops.release           release candidate lifecycle (state machine contracts/state-machines/release.yaml)
--   ops.release_approval  four approvals of the release-candidate gate (REL-004-S03)
--   ops.deployment        deployment records (docs/releases/deployment-record.v1.json, REL-002-S13)
-- Global tables (no tenant_id, no RLS): written only by bridge_ops_api (release pipeline via SigV4 CI role, release approvers via
-- the ops console); readable by bridge_ops_ro. Listed as global tables in the SEC RLS standard (hand-off to K2).

CREATE SCHEMA IF NOT EXISTS ops;

CREATE TABLE ops.release (
  id                      uuid        NOT NULL,
  version                 text        NOT NULL,
  commit_sha              text        NOT NULL,
  manifest_sha256         text        NOT NULL,
  manifest_ref            text        NOT NULL,
  status                  text        NOT NULL DEFAULT 'BUILT',
  go_live_candidate       boolean     NOT NULL DEFAULT false,
  serving_schema_version  integer     NOT NULL,
  migration_head          text        NOT NULL,
  feature_flag_snapshot_sha text      NOT NULL,
  evidence_matrix_ref     text        NULL,
  go_no_go_ref            text        NULL,
  rollback_owner          text        NULL,
  status_reason           text        NULL,
  superseded_by           uuid        NULL,
  created_by              text        NOT NULL,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  revision                bigint      NOT NULL DEFAULT 1,
  CONSTRAINT release_pk PRIMARY KEY (id),
  CONSTRAINT release_version_unique UNIQUE (version),
  CONSTRAINT release_manifest_unique UNIQUE (manifest_sha256),
  CONSTRAINT release_superseded_fk FOREIGN KEY (superseded_by) REFERENCES ops.release (id),
  CONSTRAINT release_version_ck CHECK (version ~ '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(rc|build)\.[1-9][0-9]*)?$'),
  CONSTRAINT release_commit_ck CHECK (commit_sha ~ '^[0-9a-f]{40}$'),
  CONSTRAINT release_manifest_ck CHECK (manifest_sha256 ~ '^[0-9a-f]{64}$' AND feature_flag_snapshot_sha ~ '^[0-9a-f]{64}$'),
  CONSTRAINT release_status_ck CHECK (status IN ('BUILT','STAGING','VERIFIED','REJECTED','CANDIDATE','NO_GO','APPROVED_FOR_PRODUCTION','PRODUCTION','ROLLED_BACK','SUPERSEDED')),
  CONSTRAINT release_candidate_ck CHECK (status NOT IN ('CANDIDATE','NO_GO') OR (go_live_candidate AND version ~ '-rc\.[1-9][0-9]*$')),
  CONSTRAINT release_go_ck CHECK (NOT go_live_candidate OR status NOT IN ('APPROVED_FOR_PRODUCTION','PRODUCTION') OR (go_no_go_ref IS NOT NULL AND rollback_owner IS NOT NULL)),
  CONSTRAINT release_superseded_ck CHECK ((status = 'SUPERSEDED') = (superseded_by IS NOT NULL)),
  CONSTRAINT release_reason_ck CHECK (status NOT IN ('REJECTED','NO_GO','ROLLED_BACK') OR status_reason IS NOT NULL),
  CONSTRAINT release_serving_ck CHECK (serving_schema_version >= 1),
  CONSTRAINT release_actor_ck CHECK (created_by ~ '^(operator|system):[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT release_revision_ck CHECK (revision >= 1)
);
CREATE INDEX release_status_idx ON ops.release (status, created_at);
COMMENT ON TABLE ops.release IS 'REL-001/REL-002/REL-004. One row per built release manifest (docs/releases/release-manifest.v1.json, immutable, sha recorded). Weekly trains go BUILT -> STAGING -> VERIFIED -> APPROVED_FOR_PRODUCTION -> PRODUCTION (dark production with signup.enabled=false until go-live, REL-104); the go-live candidate additionally passes CANDIDATE -> GO (APPROVED_FOR_PRODUCTION with go_no_go_ref) or NO_GO through docs/production/go-no-go.yaml.';
COMMENT ON COLUMN ops.release.manifest_ref IS 'Object key of the frozen manifest in the evidence bucket (docs/releases/rc-manifest/ for rc tags).';
COMMENT ON COLUMN ops.release.rollback_owner IS 'x-privacy: INTERNAL. operator:<id> named in the go/no-go record (REL-004 acceptance).';
COMMENT ON COLUMN ops.release.status_reason IS 'x-privacy: INTERNAL. Machine reason code + short text (e.g. EVIDENCE_STALE: live Snowflake suite older than 7 days).';

CREATE TABLE ops.release_approval (
  id              uuid        NOT NULL,
  release_id      uuid        NOT NULL,
  approval_role   text        NOT NULL,
  decision        text        NOT NULL,
  approver        text        NOT NULL,
  evidence_ref    text        NOT NULL,
  comment         text        NULL,
  decided_at      timestamptz NOT NULL DEFAULT now(),
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT release_approval_pk PRIMARY KEY (id),
  CONSTRAINT release_approval_release_fk FOREIGN KEY (release_id) REFERENCES ops.release (id),
  CONSTRAINT release_approval_unique UNIQUE (release_id, approval_role),
  CONSTRAINT release_approval_role_ck CHECK (approval_role IN ('ENGINEERING','SECURITY','FINOPS','OPERATIONS')),
  CONSTRAINT release_approval_decision_ck CHECK (decision IN ('APPROVE','REJECT')),
  CONSTRAINT release_approval_actor_ck CHECK (approver ~ '^operator:[A-Za-z0-9._:-]{1,128}$')
);
CREATE UNIQUE INDEX release_approval_distinct_people ON ops.release_approval (release_id, approver);
COMMENT ON TABLE ops.release_approval IS 'REL-004-S03. Engineering, security, FinOps and operations approvals of a go-live candidate, each with an evidence link; four distinct people (D-19: human reviewers approve). The security approver is not the implementer of the security suite (checked by the ops API against the evidence matrix, OPS_RELEASE_APPROVAL_CONFLICT).';

CREATE TABLE ops.deployment (
  id                        uuid        NOT NULL,
  release_id                uuid        NOT NULL,
  env                       text        NOT NULL,
  decision                  text        NOT NULL DEFAULT 'IN_PROGRESS',
  old_manifest_sha256       text        NULL,
  new_manifest_sha256       text        NOT NULL,
  started_at                timestamptz NOT NULL,
  ended_at                  timestamptz NULL,
  duration_s                integer     NULL,
  operator                  text        NOT NULL,
  alarms_triggered_count    integer     NOT NULL DEFAULT 0,
  record_json               jsonb       NOT NULL,
  record_schema_version     smallint    NOT NULL DEFAULT 1,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  revision                  bigint      NOT NULL DEFAULT 1,
  CONSTRAINT deployment_pk PRIMARY KEY (id),
  CONSTRAINT deployment_release_fk FOREIGN KEY (release_id) REFERENCES ops.release (id),
  CONSTRAINT deployment_env_ck CHECK (env IN ('dev','staging','production')),
  CONSTRAINT deployment_decision_ck CHECK (decision IN ('IN_PROGRESS','COMPLETED','ROLLED_BACK','FORWARD_FIXED')),
  CONSTRAINT deployment_sha_ck CHECK (new_manifest_sha256 ~ '^[0-9a-f]{64}$' AND (old_manifest_sha256 IS NULL OR old_manifest_sha256 ~ '^[0-9a-f]{64}$')),
  CONSTRAINT deployment_end_ck CHECK ((decision = 'IN_PROGRESS') = (ended_at IS NULL) AND (ended_at IS NULL OR (ended_at >= started_at AND duration_s >= 0))),
  CONSTRAINT deployment_actor_ck CHECK (operator ~ '^(operator|system):[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT deployment_alarms_ck CHECK (alarms_triggered_count >= 0),
  CONSTRAINT deployment_record_ck CHECK (jsonb_typeof(record_json) = 'object' AND record_schema_version = 1),
  CONSTRAINT deployment_revision_ck CHECK (revision >= 1)
);
CREATE UNIQUE INDEX deployment_one_in_progress_per_env ON ops.deployment (env) WHERE decision = 'IN_PROGRESS';
CREATE INDEX deployment_release_idx ON ops.deployment (release_id, env, started_at);
COMMENT ON TABLE ops.deployment IS 'REL-002-S13. Deployment record per environment rollout; record_json validates against docs/releases/deployment-record.v1.json and is also written to the evidence bucket (OPS-108-S03 change-management evidence). At most one IN_PROGRESS deployment per environment.';
COMMENT ON COLUMN ops.deployment.operator IS 'x-privacy: INTERNAL. operator:<id> (manual approval) or system:release-pipeline.';

REVOKE ALL ON ops.release, ops.release_approval, ops.deployment FROM PUBLIC;
GRANT USAGE ON SCHEMA ops TO bridge_ops_api, bridge_ops_ro;
GRANT SELECT, INSERT, UPDATE ON ops.release, ops.deployment TO bridge_ops_api;
GRANT SELECT, INSERT ON ops.release_approval TO bridge_ops_api;
GRANT SELECT ON ops.release, ops.release_approval, ops.deployment TO bridge_ops_ro;

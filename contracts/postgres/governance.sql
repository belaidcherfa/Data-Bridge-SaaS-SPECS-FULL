-- contract=postgres-governance version=1 status=DRAFT owner_task=ALC-001,ALC-002,ALC-004,ALC-008,GOV-001 decisions=D-04,D-05,D-12,D-15,D-16,D-17 last_changed=2026-09-28
-- Reference DDL for the `governance` schema (lane K7 owns this file; contracts/README.md).
-- Alembic migrations of ALC-001-S02, ALC-002-S06, ALC-004-S02, ALC-008-S01, GOV-001-S02 (and the tables authored
-- here on behalf of SEC-102 and CTL-005, see contracts/_handoffs/K7.md) must converge to this file (schema-diff test).
-- Rules: contracts/CONVENTIONS.md §3, §4, §10. Singular table names (backlog plural names noted per table).
-- Status CHECK sets are generated from contracts/state-machines/{ruleset,budget,chargeback_statement}.yaml.
-- RLS: SEC RLS standard template (tenant_isolation on app.tenant_id); ENABLE + FORCE on every tenant table.
-- No analytical fact mirror: amounts stored here are configuration (budget amounts, transfer amounts) or
-- statement header digests; allocation lines and statement lines live in Snowflake.

CREATE SCHEMA IF NOT EXISTS governance;
COMMENT ON SCHEMA governance IS 'Allocation configuration (dimensions, tag rules, usage groups), budgets, chargeback statement headers, maker-checker approvals and config publications. Owner lane K7 (ALC, GOV); approvals SEC-102; config publications CTL-005.';

-- Required for the EXCLUDE constraints on effective-dated rows (uuid/text equality inside GiST).
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ============================================================================================================
-- 1. Tag dimensions (ALC-001) — backlog name governance.dimension_definitions
-- ============================================================================================================
CREATE TABLE governance.dimension_definition (
    tenant_id        uuid        NOT NULL,
    id               uuid        NOT NULL,
    key              text        NOT NULL,
    label            text        NOT NULL,
    description      text        NULL,
    value_type       text        NOT NULL DEFAULT 'STRING',
    is_builtin       boolean     NOT NULL DEFAULT false,
    archived_at      timestamptz NULL,
    archived_by      uuid        NULL,
    created_by       uuid        NULL,
    updated_by       uuid        NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    revision         bigint      NOT NULL DEFAULT 1,
    CONSTRAINT dimension_definition_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT dimension_definition_key_format CHECK (key ~ '^[a-z][a-z0-9_]{1,62}$'),
    CONSTRAINT dimension_definition_key_not_reserved CHECK (key NOT IN (
        'tenant_id', 'tenant', 'organization_id', 'organization', 'account_id', 'account', 'account_locator',
        'book', 'book_id', 'group', 'group_id', 'group_set', 'group_set_id', 'usage_group', 'currency', 'amount',
        'cost', 'spend', 'charge_id', 'publication_id', 'revision_id', 'build_id', 'usage_date', 'period',
        'data_status', 'price_basis', 'scope_kind', 'service_type', 'service_family', 'service_category',
        'method', 'status', 'id', 'key', 'value', 'user', 'user_name', 'role', 'query_id', 'unassigned',
        'unallocated', 'platform', 'shared')),
    CONSTRAINT dimension_definition_label_len CHECK (char_length(label) BETWEEN 1 AND 120),
    CONSTRAINT dimension_definition_value_type CHECK (value_type IN ('STRING', 'ENUM')),
    CONSTRAINT dimension_definition_archive_consistent CHECK (archived_by IS NULL OR archived_at IS NOT NULL)
);
CREATE UNIQUE INDEX dimension_definition_tenant_key_uq ON governance.dimension_definition (tenant_id, lower(key));
CREATE INDEX dimension_definition_tenant_active_idx ON governance.dimension_definition (tenant_id) WHERE archived_at IS NULL;
COMMENT ON TABLE governance.dimension_definition IS 'Tag dimension registry per tenant (13 built-ins seeded idempotently at tenant creation + typed tenant-defined dimensions). Key immutable; label renamable; archive is soft and refused (409 ALLOC_DIMENSION_IN_USE) while an active ruleset or group set references it; archived dimensions stay resolvable for issued statements. owner_task=ALC-001. Schema: data/contracts/tags.json.';
COMMENT ON COLUMN governance.dimension_definition.key IS 'Immutable snake_case key ^[a-z][a-z0-9_]{1,62}$, reserved keys rejected (422 ALLOC_RESERVED_KEY). privacy=CUSTOMER_METADATA.';
COMMENT ON COLUMN governance.dimension_definition.label IS 'Display label. privacy=CUSTOMER_METADATA.';

CREATE TABLE governance.dimension_allowed_value (
    tenant_id        uuid        NOT NULL,
    id               uuid        NOT NULL,
    dimension_id     uuid        NOT NULL,
    value            text        NOT NULL,
    label            text        NULL,
    archived_at      timestamptz NULL,
    created_by       uuid        NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    revision         bigint      NOT NULL DEFAULT 1,
    CONSTRAINT dimension_allowed_value_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT dimension_allowed_value_dimension_fk FOREIGN KEY (tenant_id, dimension_id)
        REFERENCES governance.dimension_definition (tenant_id, id),
    CONSTRAINT dimension_allowed_value_value_len CHECK (char_length(value) BETWEEN 1 AND 256),
    CONSTRAINT dimension_allowed_value_uq UNIQUE (tenant_id, dimension_id, value)
);
CREATE INDEX dimension_allowed_value_dim_idx ON governance.dimension_allowed_value (tenant_id, dimension_id) WHERE archived_at IS NULL;
COMMENT ON TABLE governance.dimension_allowed_value IS 'Allowed values of ENUM dimensions (<= 5,000 active values per dimension, enforced by the API). A rule assigning a value outside the list → 422 ALLOC_VALUE_NOT_ALLOWED. owner_task=ALC-001.';
COMMENT ON COLUMN governance.dimension_allowed_value.value IS 'privacy=CUSTOMER_METADATA.';

-- ============================================================================================================
-- 2. Tag rulesets (ALC-002, ALC-003) — backlog names governance.ruleset_versions, tag_rules, rule_overrides
--    One ruleset line per (tenant, dimension); each row of ruleset_version is one immutable version of it.
--    API resource /v1/rulesets/{ruleset_id} = one ruleset_version row.
-- ============================================================================================================
CREATE TABLE governance.ruleset_version (
    tenant_id                 uuid        NOT NULL,
    id                        uuid        NOT NULL,
    dimension_id              uuid        NOT NULL,
    version_no                integer     NOT NULL,
    status                    text        NOT NULL DEFAULT 'DRAFT',
    based_on_version_id       uuid        NULL,
    rollback_of_version_id    uuid        NULL,
    content_schema_version    text        NOT NULL DEFAULT 'rule-ast.v1',
    content_sha256            text        NULL,
    rule_count                integer     NOT NULL DEFAULT 0,
    override_count            integer     NOT NULL DEFAULT 0,
    min_valid_from            date        NULL,
    apply_from                text        NOT NULL DEFAULT 'AS_REQUESTED',
    access_relevant           boolean     NULL,
    simulation_id             uuid        NULL,
    window_fingerprint        text        NULL,
    dependency_versions_json  jsonb       NULL,
    dependency_versions_schema_version text NULL,
    config_version            bigint      NULL,
    publication_requested_at  timestamptz NULL,
    published_at              timestamptz NULL,
    superseded_at             timestamptz NULL,
    superseded_by_version_id  uuid        NULL,
    failure_code              text        NULL,
    created_by                uuid        NOT NULL,
    updated_by                uuid        NULL,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    revision                  bigint      NOT NULL DEFAULT 1,
    CONSTRAINT ruleset_version_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT ruleset_version_dimension_fk FOREIGN KEY (tenant_id, dimension_id)
        REFERENCES governance.dimension_definition (tenant_id, id),
    CONSTRAINT ruleset_version_based_on_fk FOREIGN KEY (tenant_id, based_on_version_id)
        REFERENCES governance.ruleset_version (tenant_id, id),
    CONSTRAINT ruleset_version_rollback_of_fk FOREIGN KEY (tenant_id, rollback_of_version_id)
        REFERENCES governance.ruleset_version (tenant_id, id),
    CONSTRAINT ruleset_version_uq UNIQUE (tenant_id, dimension_id, version_no),
    CONSTRAINT ruleset_version_status CHECK (status IN ('DRAFT', 'SIMULATING', 'SIMULATION_FAILED', 'REVIEWABLE',
        'APPROVED', 'STALE', 'PUBLISHING', 'PUBLISH_FAILED', 'PUBLISHED', 'SUPERSEDED', 'DISCARDED')),
    CONSTRAINT ruleset_version_apply_from CHECK (apply_from IN ('AS_REQUESTED', 'FIRST_OPEN_PERIOD')),
    CONSTRAINT ruleset_version_hash_frozen CHECK (status = 'DRAFT' OR status = 'DISCARDED' OR content_sha256 IS NOT NULL),
    CONSTRAINT ruleset_version_hash_format CHECK (content_sha256 IS NULL OR content_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ruleset_version_fingerprint_format CHECK (window_fingerprint IS NULL OR window_fingerprint ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ruleset_version_limits CHECK (rule_count BETWEEN 0 AND 2000 AND override_count BETWEEN 0 AND 10000),
    CONSTRAINT ruleset_version_published_has_config CHECK (status NOT IN ('PUBLISHING', 'PUBLISHED', 'SUPERSEDED') OR config_version IS NOT NULL),
    CONSTRAINT ruleset_version_deps_versioned CHECK ((dependency_versions_json IS NULL) = (dependency_versions_schema_version IS NULL))
);
CREATE UNIQUE INDEX ruleset_version_one_published_uq ON governance.ruleset_version (tenant_id, dimension_id) WHERE status = 'PUBLISHED';
CREATE UNIQUE INDEX ruleset_version_one_publishing_uq ON governance.ruleset_version (tenant_id, dimension_id) WHERE status = 'PUBLISHING';
CREATE INDEX ruleset_version_tenant_status_idx ON governance.ruleset_version (tenant_id, status, updated_at DESC);
COMMENT ON TABLE governance.ruleset_version IS 'Versioned tag ruleset per (tenant, dimension). Content (tag_rule + rule_override rows) immutable once status <> DRAFT; content_sha256 = sha256 of the RFC 8785 canonical JSON of the ruleset document (data/contracts/rule-ast.json#/$defs/ruleset). State machine contracts/state-machines/ruleset.yaml. owner_task=ALC-002 (DDL), ALC-003 (lifecycle).';
COMMENT ON COLUMN governance.ruleset_version.window_fingerprint IS 'sha256 hex over the ordered (charge_id, charge_revision) of charges in the simulated window∩scope at the pinned publication (G-ALC-07).';
COMMENT ON COLUMN governance.ruleset_version.dependency_versions_json IS 'Versioned document {dimension_definitions_revision, group_set_hierarchy_config_version, policy_config_version, base_published_version_id}; schema data/contracts/allocation-policy.json#/$defs/dependency_versions.';

CREATE TABLE governance.tag_rule (
    tenant_id                 uuid        NOT NULL,
    id                        uuid        NOT NULL,
    ruleset_version_id        uuid        NOT NULL,
    rule_key                  text        NOT NULL,
    name                      text        NOT NULL,
    description               text        NULL,
    subject_kind              text        NOT NULL,
    priority                  integer     NOT NULL,
    ordinal                   integer     NOT NULL,
    match_json                jsonb       NOT NULL,
    assign_json               jsonb       NOT NULL,
    rule_schema_version       text        NOT NULL DEFAULT 'rule-ast.v1',
    valid_from                date        NOT NULL,
    valid_to                  date        NULL,
    enabled                   boolean     NOT NULL DEFAULT true,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    revision                  bigint      NOT NULL DEFAULT 1,
    CONSTRAINT tag_rule_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT tag_rule_ruleset_fk FOREIGN KEY (tenant_id, ruleset_version_id)
        REFERENCES governance.ruleset_version (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT tag_rule_key_uq UNIQUE (tenant_id, ruleset_version_id, rule_key),
    CONSTRAINT tag_rule_key_format CHECK (rule_key ~ '^[a-z0-9][a-z0-9_-]{0,63}$'),
    CONSTRAINT tag_rule_name_len CHECK (char_length(name) BETWEEN 1 AND 120),
    CONSTRAINT tag_rule_subject_kind CHECK (subject_kind IN ('QUERY', 'TASK_RUN', 'CORTEX_CALL', 'WAREHOUSE', 'TABLE',
        'PIPE', 'TASK', 'MATERIALIZED_VIEW', 'DYNAMIC_TABLE', 'COMPUTE_POOL', 'SPCS_SERVICE', 'STAGE',
        'REPLICATION_GROUP', 'SCHEMA', 'DATABASE', 'ACCOUNT')),
    CONSTRAINT tag_rule_priority_range CHECK (priority BETWEEN 0 AND 1000000),
    CONSTRAINT tag_rule_validity CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT tag_rule_match_size CHECK (octet_length(match_json::text) <= 32768),
    CONSTRAINT tag_rule_assign_size CHECK (octet_length(assign_json::text) <= 4096)
);
CREATE INDEX tag_rule_ruleset_idx ON governance.tag_rule (tenant_id, ruleset_version_id, priority DESC, ordinal);
COMMENT ON TABLE governance.tag_rule IS 'One DNF rule of a ruleset version (data/contracts/rule-ast.json#/$defs/rule). match_json = {any_of:[{all_of:[predicate…]}]}; assign_json = {value} or {split:[{value, weight}]} with weights <= 6 dp summing exactly to 1. Immutable once the parent version leaves DRAFT. owner_task=ALC-002.';
COMMENT ON COLUMN governance.tag_rule.match_json IS 'Schema rule-ast.v1 (#/$defs/match). User-name predicates are stored as entered in PG (eq/in only) and compiled to pseudonyms before leaving PostgreSQL (D-10). privacy=CUSTOMER_METADATA (may contain PERSONAL user names in user predicates).';

CREATE TABLE governance.rule_override (
    tenant_id                 uuid        NOT NULL,
    id                        uuid        NOT NULL,
    ruleset_version_id        uuid        NOT NULL,
    override_key              text        NOT NULL,
    subject_kind              text        NOT NULL,
    subject_ref               text        NOT NULL,
    assign_json               jsonb       NOT NULL,
    rule_schema_version       text        NOT NULL DEFAULT 'rule-ast.v1',
    reason                    text        NOT NULL,
    valid_from                date        NOT NULL,
    valid_to                  date        NULL,
    created_by                uuid        NOT NULL,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    revision                  bigint      NOT NULL DEFAULT 1,
    CONSTRAINT rule_override_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT rule_override_ruleset_fk FOREIGN KEY (tenant_id, ruleset_version_id)
        REFERENCES governance.ruleset_version (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT rule_override_key_uq UNIQUE (tenant_id, ruleset_version_id, override_key),
    CONSTRAINT rule_override_key_format CHECK (override_key ~ '^[a-z0-9][a-z0-9_-]{0,63}$'),
    CONSTRAINT rule_override_subject_kind CHECK (subject_kind IN ('WAREHOUSE', 'TABLE', 'PIPE', 'TASK', 'MATERIALIZED_VIEW',
        'DYNAMIC_TABLE', 'COMPUTE_POOL', 'SPCS_SERVICE', 'STAGE', 'REPLICATION_GROUP', 'SCHEMA', 'DATABASE', 'ACCOUNT',
        'QUERY_FAMILY', 'WORKLOAD')),
    CONSTRAINT rule_override_subject_ref_len CHECK (char_length(subject_ref) BETWEEN 1 AND 256),
    CONSTRAINT rule_override_reason_len CHECK (char_length(reason) BETWEEN 10 AND 2000),
    CONSTRAINT rule_override_validity CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT rule_override_no_overlap EXCLUDE USING gist (
        tenant_id WITH =, ruleset_version_id WITH =, subject_kind WITH =, subject_ref WITH =,
        daterange(valid_from, valid_to, '[)') WITH &&)
);
COMMENT ON TABLE governance.rule_override IS 'Manual override (level OVERRIDE) on a STABLE subject only: resource id, query parameterized hash (QUERY_FAMILY) or workload id — never a single query_id (422 ALLOC_OVERRIDE_SUBJECT_UNSTABLE). Reason >= 10 chars; effective-dated; expiry falls back at the UTC day boundary. Overlapping validity for the same subject → 422 ALLOC_EFFECTIVE_OVERLAP. owner_task=ALC-002-S11.';
COMMENT ON COLUMN governance.rule_override.reason IS 'Free text written by the author. privacy=CUSTOMER_METADATA.';

-- ============================================================================================================
-- 3. Usage group sets and hierarchies (ALC-004) — backlog names usage_group_sets, usage_groups,
--    group_value_mappings, hierarchy_versions. book_id = usage_group_set.id (G-ALC-13).
-- ============================================================================================================
CREATE TABLE governance.usage_group_set (
    tenant_id        uuid        NOT NULL,
    id               uuid        NOT NULL,
    name             text        NOT NULL,
    description      text        NULL,
    dimension_id     uuid        NOT NULL,
    is_default_book  boolean     NOT NULL DEFAULT false,
    seed_version     text        NULL,
    archived_at      timestamptz NULL,
    created_by       uuid        NULL,
    updated_by       uuid        NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    revision         bigint      NOT NULL DEFAULT 1,
    CONSTRAINT usage_group_set_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT usage_group_set_dimension_fk FOREIGN KEY (tenant_id, dimension_id)
        REFERENCES governance.dimension_definition (tenant_id, id),
    CONSTRAINT usage_group_set_name_len CHECK (char_length(name) BETWEEN 1 AND 120),
    CONSTRAINT usage_group_set_seed_version CHECK (seed_version IS NULL OR seed_version ~ '^default_book_v[0-9]+$')
);
CREATE UNIQUE INDEX usage_group_set_dimension_uq ON governance.usage_group_set (tenant_id, dimension_id) WHERE archived_at IS NULL;
CREATE UNIQUE INDEX usage_group_set_name_uq ON governance.usage_group_set (tenant_id, lower(name)) WHERE archived_at IS NULL;
CREATE UNIQUE INDEX usage_group_set_one_default_uq ON governance.usage_group_set (tenant_id) WHERE is_default_book AND archived_at IS NULL;
COMMENT ON TABLE governance.usage_group_set IS 'Usage group set = allocation book (book_id = id). Bound 1:1 to a tag dimension. Books are never additive (422 ALLOC_NON_ADDITIVE_BOOKS). The D-15 default book "Teams (default)" bound to dimension team is seeded idempotently at onboarding (seed_version=default_book_v1). owner_task=ALC-004.';
COMMENT ON COLUMN governance.usage_group_set.name IS 'privacy=CUSTOMER_METADATA.';

CREATE TABLE governance.usage_group (
    tenant_id        uuid        NOT NULL,
    id               uuid        NOT NULL,
    group_set_id     uuid        NOT NULL,
    name             text        NOT NULL,
    description      text        NULL,
    system_kind      text        NOT NULL DEFAULT 'NONE',
    archived_at      timestamptz NULL,
    created_by       uuid        NULL,
    updated_by       uuid        NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    revision         bigint      NOT NULL DEFAULT 1,
    CONSTRAINT usage_group_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT usage_group_set_scoped_uq UNIQUE (tenant_id, group_set_id, id),
    CONSTRAINT usage_group_set_fk FOREIGN KEY (tenant_id, group_set_id)
        REFERENCES governance.usage_group_set (tenant_id, id),
    CONSTRAINT usage_group_name_len CHECK (char_length(name) BETWEEN 1 AND 120),
    CONSTRAINT usage_group_system_kind CHECK (system_kind IN ('NONE', 'UNASSIGNED', 'PLATFORM')),
    CONSTRAINT usage_group_unassigned_not_archived CHECK (system_kind <> 'UNASSIGNED' OR archived_at IS NULL)
);
CREATE UNIQUE INDEX usage_group_name_uq ON governance.usage_group (tenant_id, group_set_id, lower(name)) WHERE archived_at IS NULL;
CREATE UNIQUE INDEX usage_group_one_unassigned_uq ON governance.usage_group (tenant_id, group_set_id) WHERE system_kind = 'UNASSIGNED';
CREATE UNIQUE INDEX usage_group_one_platform_uq ON governance.usage_group (tenant_id, group_set_id) WHERE system_kind = 'PLATFORM' AND archived_at IS NULL;
COMMENT ON TABLE governance.usage_group IS 'Group of a set. Every set has exactly one non-deletable UNASSIGNED leaf (auto-created) and at most one PLATFORM group. Parents are versioned in governance.hierarchy_edge. A group referenced by a published allocation or statement is archive-only (409 ALLOC_GROUP_IN_USE); rename keeps id. owner_task=ALC-004.';
COMMENT ON COLUMN governance.usage_group.name IS 'privacy=CUSTOMER_METADATA.';

CREATE TABLE governance.hierarchy_version (
    tenant_id                 uuid        NOT NULL,
    id                        uuid        NOT NULL,
    group_set_id              uuid        NOT NULL,
    version_no                integer     NOT NULL,
    status                    text        NOT NULL DEFAULT 'DRAFT',
    based_on_version_id       uuid        NULL,
    rollback_of_version_id    uuid        NULL,
    content_schema_version    text        NOT NULL DEFAULT 'usage-groups.v1',
    content_sha256            text        NULL,
    edge_count                integer     NOT NULL DEFAULT 0,
    mapping_count             integer     NOT NULL DEFAULT 0,
    max_depth                 smallint    NULL,
    min_valid_from            date        NULL,
    apply_from                text        NOT NULL DEFAULT 'AS_REQUESTED',
    access_relevant           boolean     NULL,
    simulation_id             uuid        NULL,
    window_fingerprint        text        NULL,
    dependency_versions_json  jsonb       NULL,
    dependency_versions_schema_version text NULL,
    config_version            bigint      NULL,
    publication_requested_at  timestamptz NULL,
    published_at              timestamptz NULL,
    superseded_at             timestamptz NULL,
    superseded_by_version_id  uuid        NULL,
    failure_code              text        NULL,
    created_by                uuid        NOT NULL,
    updated_by                uuid        NULL,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    revision                  bigint      NOT NULL DEFAULT 1,
    CONSTRAINT hierarchy_version_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT hierarchy_version_set_fk FOREIGN KEY (tenant_id, group_set_id)
        REFERENCES governance.usage_group_set (tenant_id, id),
    CONSTRAINT hierarchy_version_based_on_fk FOREIGN KEY (tenant_id, based_on_version_id)
        REFERENCES governance.hierarchy_version (tenant_id, id),
    CONSTRAINT hierarchy_version_rollback_of_fk FOREIGN KEY (tenant_id, rollback_of_version_id)
        REFERENCES governance.hierarchy_version (tenant_id, id),
    CONSTRAINT hierarchy_version_uq UNIQUE (tenant_id, group_set_id, version_no),
    CONSTRAINT hierarchy_version_set_scoped_uq UNIQUE (tenant_id, group_set_id, id),
    CONSTRAINT hierarchy_version_status CHECK (status IN ('DRAFT', 'SIMULATING', 'SIMULATION_FAILED', 'REVIEWABLE',
        'APPROVED', 'STALE', 'PUBLISHING', 'PUBLISH_FAILED', 'PUBLISHED', 'SUPERSEDED', 'DISCARDED')),
    CONSTRAINT hierarchy_version_apply_from CHECK (apply_from IN ('AS_REQUESTED', 'FIRST_OPEN_PERIOD')),
    CONSTRAINT hierarchy_version_hash_frozen CHECK (status = 'DRAFT' OR status = 'DISCARDED' OR content_sha256 IS NOT NULL),
    CONSTRAINT hierarchy_version_hash_format CHECK (content_sha256 IS NULL OR content_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT hierarchy_version_depth CHECK (max_depth IS NULL OR max_depth BETWEEN 0 AND 8),
    CONSTRAINT hierarchy_version_limits CHECK (edge_count BETWEEN 0 AND 5000 AND mapping_count BETWEEN 0 AND 100000),
    CONSTRAINT hierarchy_version_published_has_config CHECK (status NOT IN ('PUBLISHING', 'PUBLISHED', 'SUPERSEDED') OR config_version IS NOT NULL),
    CONSTRAINT hierarchy_version_deps_versioned CHECK ((dependency_versions_json IS NULL) = (dependency_versions_schema_version IS NULL))
);
CREATE UNIQUE INDEX hierarchy_version_one_published_uq ON governance.hierarchy_version (tenant_id, group_set_id) WHERE status = 'PUBLISHED';
CREATE UNIQUE INDEX hierarchy_version_one_publishing_uq ON governance.hierarchy_version (tenant_id, group_set_id) WHERE status = 'PUBLISHING';
COMMENT ON TABLE governance.hierarchy_version IS 'Versioned hierarchy (edges + value mappings) of a group set, published through the ALC-003 machinery (state machine ruleset.yaml). Effective-dated moves create a new version; prior versions remain resolvable for old allocations and statements. owner_task=ALC-004.';

CREATE TABLE governance.hierarchy_edge (
    tenant_id                 uuid        NOT NULL,
    id                        uuid        NOT NULL,
    hierarchy_version_id      uuid        NOT NULL,
    group_set_id              uuid        NOT NULL,
    group_id                  uuid        NOT NULL,
    parent_group_id           uuid        NULL,
    valid_from                date        NOT NULL,
    valid_to                  date        NULL,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    revision                  bigint      NOT NULL DEFAULT 1,
    CONSTRAINT hierarchy_edge_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT hierarchy_edge_version_fk FOREIGN KEY (tenant_id, group_set_id, hierarchy_version_id)
        REFERENCES governance.hierarchy_version (tenant_id, group_set_id, id) ON DELETE CASCADE,
    CONSTRAINT hierarchy_edge_group_fk FOREIGN KEY (tenant_id, group_set_id, group_id)
        REFERENCES governance.usage_group (tenant_id, group_set_id, id),
    CONSTRAINT hierarchy_edge_parent_same_set_fk FOREIGN KEY (tenant_id, group_set_id, parent_group_id)
        REFERENCES governance.usage_group (tenant_id, group_set_id, id),
    CONSTRAINT hierarchy_edge_not_self CHECK (parent_group_id IS NULL OR parent_group_id <> group_id),
    CONSTRAINT hierarchy_edge_validity CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT hierarchy_edge_one_parent_per_day EXCLUDE USING gist (
        tenant_id WITH =, hierarchy_version_id WITH =, group_id WITH =,
        daterange(valid_from, valid_to, '[)') WITH &&)
);
COMMENT ON TABLE governance.hierarchy_edge IS 'Parent of a group over [valid_from, valid_to) (UTC dates) within one hierarchy version. The composite FKs make a cross-set parent impossible (422 ALLOC_CROSS_SET_PARENT is raised by the API before the DB). Acyclicity (DFS, 422 ALLOC_HIERARCHY_CYCLE), depth <= 8 (422 ALLOC_HIERARCHY_TOO_DEEP) and no orphan are validated by apps/api/usage_groups/validate.py. owner_task=ALC-004-S03/S04.';

CREATE TABLE governance.group_value_mapping (
    tenant_id                 uuid        NOT NULL,
    id                        uuid        NOT NULL,
    hierarchy_version_id      uuid        NOT NULL,
    group_set_id              uuid        NOT NULL,
    group_id                  uuid        NOT NULL,
    dimension_value           text        NOT NULL,
    valid_from                date        NOT NULL,
    valid_to                  date        NULL,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    revision                  bigint      NOT NULL DEFAULT 1,
    CONSTRAINT group_value_mapping_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT group_value_mapping_version_fk FOREIGN KEY (tenant_id, group_set_id, hierarchy_version_id)
        REFERENCES governance.hierarchy_version (tenant_id, group_set_id, id) ON DELETE CASCADE,
    CONSTRAINT group_value_mapping_group_fk FOREIGN KEY (tenant_id, group_set_id, group_id)
        REFERENCES governance.usage_group (tenant_id, group_set_id, id),
    CONSTRAINT group_value_mapping_value_len CHECK (char_length(dimension_value) BETWEEN 1 AND 256),
    CONSTRAINT group_value_mapping_validity CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT group_value_mapping_value_once EXCLUDE USING gist (
        tenant_id WITH =, hierarchy_version_id WITH =, dimension_value WITH =,
        daterange(valid_from, valid_to, '[)') WITH &&)
);
COMMENT ON TABLE governance.group_value_mapping IS 'Dimension value → group, effective-dated. One group per dimension value per interval (EXCLUDE; API maps the violation to 422 ALLOC_VALUE_MAPPED_TWICE). Values with no mapping resolve to the UNASSIGNED leaf. owner_task=ALC-004.';
COMMENT ON COLUMN governance.group_value_mapping.dimension_value IS 'privacy=CUSTOMER_METADATA.';

-- ============================================================================================================
-- 4. Budgets (GOV-001) — backlog names governance.budgets, budget_revisions
-- ============================================================================================================
CREATE TABLE governance.budget (
    tenant_id                       uuid          NOT NULL,
    id                              uuid          NOT NULL,
    name                            text          NOT NULL,
    status                          text          NOT NULL DEFAULT 'DRAFT',
    pause_reason                    text          NULL,
    owner_membership_id             uuid          NULL,
    owner_subject_id                uuid          NULL,
    metric_id                       text          NOT NULL,
    metric_version                  integer       NOT NULL,
    book_id                         uuid          NULL,
    allocation_version_policy       text          NOT NULL DEFAULT 'FLOATING_LATEST_PUBLISHED',
    pinned_allocation_publication_id text         NULL,
    currency                        char(3)       NOT NULL,
    calendar_kind                   text          NOT NULL DEFAULT 'MONTH',
    fiscal_year_start_month         smallint      NOT NULL DEFAULT 1,
    recurrence                      text          NOT NULL DEFAULT 'RECURRING',
    start_date                      date          NOT NULL,
    end_date                        date          NULL,
    amount                          numeric(38,12) NOT NULL,
    scope_json                      jsonb         NOT NULL,
    scope_schema_version            text          NOT NULL DEFAULT 'budget-scope.v1',
    scope_sha256                    text          NOT NULL,
    thresholds_json                 jsonb         NOT NULL DEFAULT '[]'::jsonb,
    thresholds_schema_version       text          NOT NULL DEFAULT 'budget-thresholds.v1',
    cost_basis                      text          NOT NULL DEFAULT 'NET_SIGNED',
    minimum_data_status             text          NOT NULL DEFAULT 'PROVISIONAL',
    current_revision_no             integer       NOT NULL DEFAULT 1,
    config_version                  bigint        NULL,
    archived_at                     timestamptz   NULL,
    created_by                      uuid          NOT NULL,
    updated_by                      uuid          NULL,
    created_at                      timestamptz   NOT NULL DEFAULT now(),
    updated_at                      timestamptz   NOT NULL DEFAULT now(),
    revision                        bigint        NOT NULL DEFAULT 1,
    CONSTRAINT budget_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT budget_book_fk FOREIGN KEY (tenant_id, book_id)
        REFERENCES governance.usage_group_set (tenant_id, id),
    CONSTRAINT budget_name_len CHECK (char_length(name) BETWEEN 1 AND 120),
    CONSTRAINT budget_status CHECK (status IN ('DRAFT', 'ACTIVE', 'PAUSED_AUTH', 'ARCHIVED')),
    CONSTRAINT budget_pause_reason CHECK ((status = 'PAUSED_AUTH') = (pause_reason IS NOT NULL)
        AND (pause_reason IS NULL OR pause_reason IN ('OWNER_REMOVED', 'OWNER_SCOPE_REDUCED'))),
    CONSTRAINT budget_metric CHECK (metric_id IN ('spend', 'allocated_spend') AND metric_version >= 1),
    CONSTRAINT budget_book_iff_allocated CHECK ((metric_id = 'allocated_spend') = (book_id IS NOT NULL)),
    CONSTRAINT budget_allocation_policy CHECK (allocation_version_policy IN ('FLOATING_LATEST_PUBLISHED', 'PINNED')
        AND ((allocation_version_policy = 'PINNED') = (pinned_allocation_publication_id IS NOT NULL))
        AND (metric_id = 'allocated_spend' OR allocation_version_policy = 'FLOATING_LATEST_PUBLISHED')),
    CONSTRAINT budget_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT budget_calendar CHECK (calendar_kind IN ('MONTH', 'QUARTER', 'YEAR') AND fiscal_year_start_month BETWEEN 1 AND 12),
    CONSTRAINT budget_recurrence CHECK (recurrence IN ('RECURRING', 'SINGLE_PERIOD')),
    CONSTRAINT budget_dates CHECK (end_date IS NULL OR end_date > start_date),
    CONSTRAINT budget_single_period_has_end CHECK (recurrence = 'RECURRING' OR end_date IS NOT NULL),
    CONSTRAINT budget_amount_nonnegative CHECK (amount >= 0),
    CONSTRAINT budget_cost_basis CHECK (cost_basis = 'NET_SIGNED'),
    CONSTRAINT budget_min_status CHECK (minimum_data_status IN ('PROVISIONAL', 'FINAL')),
    CONSTRAINT budget_scope_sha CHECK (scope_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT budget_owner_present CHECK (status IN ('DRAFT', 'ARCHIVED', 'PAUSED_AUTH') OR owner_membership_id IS NOT NULL),
    CONSTRAINT budget_scope_size CHECK (octet_length(scope_json::text) <= 16384)
);
CREATE INDEX budget_tenant_status_idx ON governance.budget (tenant_id, status, updated_at DESC);
CREATE INDEX budget_owner_idx ON governance.budget (tenant_id, owner_membership_id);
CREATE INDEX budget_paused_queue_idx ON governance.budget (tenant_id, updated_at) WHERE status = 'PAUSED_AUTH';
COMMENT ON TABLE governance.budget IS 'Budget definition (data/contracts/budget.json). Actual = the same signed net metric as the Explorer: spend v1, or allocated_spend v1 on one book for team/group scopes. Overlapping budgets are independent; nothing sums across budgets. State machine contracts/state-machines/budget.yaml. owner_task=GOV-001.';
COMMENT ON COLUMN governance.budget.amount IS 'Budget amount per period in currency, >= 0, exact NUMERIC(38,12); zero allowed (variance_pct null). privacy=INTERNAL.';
COMMENT ON COLUMN governance.budget.scope_json IS 'Semantic filter document (data/contracts/budget.json#/$defs/scope); IDs only, never names. privacy=CUSTOMER_METADATA.';
COMMENT ON COLUMN governance.budget.name IS 'privacy=CUSTOMER_METADATA.';

CREATE TABLE governance.budget_revision (
    tenant_id                  uuid          NOT NULL,
    id                         uuid          NOT NULL,
    budget_id                  uuid          NOT NULL,
    revision_no                integer       NOT NULL,
    effective_from             timestamptz   NOT NULL,
    amount                     numeric(38,12) NOT NULL,
    metric_id                  text          NOT NULL,
    metric_version             integer       NOT NULL,
    book_id                    uuid          NULL,
    scope_json                 jsonb         NOT NULL,
    scope_schema_version       text          NOT NULL,
    scope_sha256               text          NOT NULL,
    thresholds_json            jsonb         NOT NULL,
    thresholds_schema_version  text          NOT NULL,
    owner_membership_id        uuid          NULL,
    change_kind                text          NOT NULL,
    change_reason              text          NULL,
    changed_by                 uuid          NOT NULL,
    created_at                 timestamptz   NOT NULL DEFAULT now(),
    updated_at                 timestamptz   NOT NULL DEFAULT now(),
    revision                   bigint        NOT NULL DEFAULT 1,
    CONSTRAINT budget_revision_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT budget_revision_budget_fk FOREIGN KEY (tenant_id, budget_id)
        REFERENCES governance.budget (tenant_id, id),
    CONSTRAINT budget_revision_uq UNIQUE (tenant_id, budget_id, revision_no),
    CONSTRAINT budget_revision_amount_nonnegative CHECK (amount >= 0),
    CONSTRAINT budget_revision_change_kind CHECK (change_kind IN ('CREATED', 'AMOUNT', 'SCOPE', 'THRESHOLDS', 'METRIC', 'OWNER', 'MULTIPLE')),
    CONSTRAINT budget_revision_scope_sha CHECK (scope_sha256 ~ '^[0-9a-f]{64}$')
);
CREATE INDEX budget_revision_budget_idx ON governance.budget_revision (tenant_id, budget_id, effective_from DESC);
COMMENT ON TABLE governance.budget_revision IS 'Append-only revision history of a budget; a revision is effective immediately (effective_from = commit time). Evaluations record the revision_no used. owner_task=GOV-001-S02.';

-- ============================================================================================================
-- 5. Chargeback statements (ALC-008) — backlog name governance.chargeback_statements.
--    Statement approvals are rows of governance.approval (action statement.issue, object_type CHARGEBACK_STATEMENT).
-- ============================================================================================================
CREATE TABLE governance.chargeback_preparation (
    tenant_id                  uuid          NOT NULL,
    id                         uuid          NOT NULL,
    book_id                    uuid          NOT NULL,
    period                     text          NOT NULL,
    currency                   char(3)       NOT NULL,
    prepare_seq                integer       NOT NULL,
    allocation_publication_id  text          NOT NULL,
    close_record_id            uuid          NULL,
    correction_kind            text          NOT NULL DEFAULT 'ORIGINAL',
    exact_book_total           numeric(38,12) NULL,
    rounded_book_total         numeric(38,12) NULL,
    minor_unit                 numeric(38,12) NOT NULL,
    statement_count            integer       NULL,
    line_count                 integer       NULL,
    lines_sha256               text          NULL,
    rounding_algorithm_version text          NOT NULL DEFAULT 'round_statement_lines.v1',
    requested_by               uuid          NOT NULL,
    completed_at               timestamptz   NULL,
    failure_code               text          NULL,
    created_at                 timestamptz   NOT NULL DEFAULT now(),
    updated_at                 timestamptz   NOT NULL DEFAULT now(),
    revision                   bigint        NOT NULL DEFAULT 1,
    CONSTRAINT chargeback_preparation_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT chargeback_preparation_book_fk FOREIGN KEY (tenant_id, book_id)
        REFERENCES governance.usage_group_set (tenant_id, id),
    CONSTRAINT chargeback_preparation_seq_uq UNIQUE (tenant_id, book_id, period, currency, prepare_seq),
    CONSTRAINT chargeback_preparation_period CHECK (period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
    CONSTRAINT chargeback_preparation_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT chargeback_preparation_correction CHECK (correction_kind IN ('ORIGINAL', 'NEXT_PERIOD_ADJUSTMENT', 'RESTATEMENT')),
    CONSTRAINT chargeback_preparation_minor_unit CHECK (minor_unit > 0),
    CONSTRAINT chargeback_preparation_sha CHECK (lines_sha256 IS NULL OR lines_sha256 ~ '^[0-9a-f]{64}$')
);
COMMENT ON TABLE governance.chargeback_preparation IS 'One computation of all target statements of a (book, period, currency) at a pinned allocation publication: book total → targets → lines hierarchical signed largest remainder (docs/11-allocation/alc-rounding.md). Stores the book-level digest only; frozen lines are in Snowflake bridge.allocation.fct_chargeback_statement_line. owner_task=ALC-008-S02.';
COMMENT ON COLUMN governance.chargeback_preparation.exact_book_total IS 'Header digest value (Σ exact allocated amount at 12 dp for the book, period and currency); not an analytical mirror. privacy=INTERNAL.';

CREATE TABLE governance.chargeback_statement (
    tenant_id                   uuid          NOT NULL,
    id                          uuid          NOT NULL,
    book_id                     uuid          NOT NULL,
    target_group_id             uuid          NOT NULL,
    period                      text          NOT NULL,
    currency                    char(3)       NOT NULL,
    version_no                  integer       NOT NULL DEFAULT 1,
    status                      text          NOT NULL DEFAULT 'DRAFT',
    correction_kind             text          NOT NULL DEFAULT 'ORIGINAL',
    predecessor_statement_id    uuid          NULL,
    preparation_id              uuid          NULL,
    prepare_seq                 integer       NULL,
    allocation_publication_id   text          NULL,
    close_record_id             uuid          NULL,
    price_basis                 text          NULL,
    exact_total                 numeric(38,12) NULL,
    rounded_total               numeric(38,12) NULL,
    rounding_delta_total        numeric(38,12) NULL,
    line_count                  integer       NULL,
    lines_sha256                text          NULL,
    precondition_results_json   jsonb         NULL,
    precondition_schema_version text          NULL,
    exception_approval_ids      uuid[]        NOT NULL DEFAULT '{}',
    prepared_by                 uuid          NULL,
    prepared_at                 timestamptz   NULL,
    reviewed_by                 uuid          NULL,
    reviewed_at                 timestamptz   NULL,
    approval_id                 uuid          NULL,
    issued_by                   uuid          NULL,
    issued_at                   timestamptz   NULL,
    issue_idempotency_key       text          NULL,
    pdf_status                  text          NOT NULL DEFAULT 'NOT_REQUESTED',
    pdf_object_key              text          NULL,
    pdf_sha256                  text          NULL,
    pdf_retention_class         text          NOT NULL DEFAULT 'RECORD',
    pdf_retain_until            date          NULL,
    superseded_by_statement_id  uuid          NULL,
    superseded_at               timestamptz   NULL,
    voided_reason               text          NULL,
    failure_code                text          NULL,
    created_by                  uuid          NOT NULL,
    created_at                  timestamptz   NOT NULL DEFAULT now(),
    updated_at                  timestamptz   NOT NULL DEFAULT now(),
    revision                    bigint        NOT NULL DEFAULT 1,
    CONSTRAINT chargeback_statement_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT chargeback_statement_book_fk FOREIGN KEY (tenant_id, book_id)
        REFERENCES governance.usage_group_set (tenant_id, id),
    CONSTRAINT chargeback_statement_target_fk FOREIGN KEY (tenant_id, book_id, target_group_id)
        REFERENCES governance.usage_group (tenant_id, group_set_id, id),
    CONSTRAINT chargeback_statement_predecessor_fk FOREIGN KEY (tenant_id, predecessor_statement_id)
        REFERENCES governance.chargeback_statement (tenant_id, id),
    CONSTRAINT chargeback_statement_successor_fk FOREIGN KEY (tenant_id, superseded_by_statement_id)
        REFERENCES governance.chargeback_statement (tenant_id, id),
    CONSTRAINT chargeback_statement_preparation_fk FOREIGN KEY (tenant_id, preparation_id)
        REFERENCES governance.chargeback_preparation (tenant_id, id),
    CONSTRAINT chargeback_statement_uq UNIQUE (tenant_id, book_id, target_group_id, period, currency, version_no),
    CONSTRAINT chargeback_statement_status CHECK (status IN ('DRAFT', 'PREPARING', 'PREPARED', 'REVIEWED', 'APPROVED',
        'ISSUED', 'SUPERSEDED', 'VOIDED_DRAFT')),
    CONSTRAINT chargeback_statement_period CHECK (period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
    CONSTRAINT chargeback_statement_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT chargeback_statement_version CHECK (version_no >= 1),
    CONSTRAINT chargeback_statement_correction CHECK (correction_kind IN ('ORIGINAL', 'RESTATEMENT')
        AND ((correction_kind = 'RESTATEMENT') = (predecessor_statement_id IS NOT NULL))
        AND ((version_no = 1) = (predecessor_statement_id IS NULL))),
    CONSTRAINT chargeback_statement_price_basis CHECK (price_basis IS NULL OR price_basis IN ('BILLED_SOURCE',
        'CONTRACT_RATE_ESTIMATE', 'CUSTOMER_APPROVED_RATE', 'UNKNOWN', 'MIXED')),
    CONSTRAINT chargeback_statement_digest_when_prepared CHECK (status IN ('DRAFT', 'PREPARING', 'VOIDED_DRAFT')
        OR (lines_sha256 IS NOT NULL AND line_count IS NOT NULL AND rounded_total IS NOT NULL AND exact_total IS NOT NULL
            AND allocation_publication_id IS NOT NULL AND prepare_seq IS NOT NULL)),
    CONSTRAINT chargeback_statement_sha CHECK (lines_sha256 IS NULL OR lines_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT chargeback_statement_issue_fields CHECK ((status IN ('ISSUED', 'SUPERSEDED')) = (issued_at IS NOT NULL)),
    CONSTRAINT chargeback_statement_pdf_status CHECK (pdf_status IN ('NOT_REQUESTED', 'PENDING', 'READY', 'FAILED')
        AND (pdf_status <> 'READY' OR (pdf_object_key IS NOT NULL AND pdf_sha256 ~ '^[0-9a-f]{64}$' AND pdf_retain_until IS NOT NULL))),
    CONSTRAINT chargeback_statement_retention CHECK (pdf_retention_class = 'RECORD'),
    CONSTRAINT chargeback_statement_superseded CHECK ((status = 'SUPERSEDED') = (superseded_by_statement_id IS NOT NULL)),
    CONSTRAINT chargeback_statement_precond_versioned CHECK ((precondition_results_json IS NULL) = (precondition_schema_version IS NULL))
);
CREATE UNIQUE INDEX chargeback_statement_one_issued_uq ON governance.chargeback_statement (tenant_id, book_id, target_group_id, period, currency) WHERE status = 'ISSUED';
CREATE UNIQUE INDEX chargeback_statement_one_preparing_uq ON governance.chargeback_statement (tenant_id, book_id, target_group_id, period, currency) WHERE status = 'PREPARING';
CREATE UNIQUE INDEX chargeback_statement_issue_key_uq ON governance.chargeback_statement (tenant_id, issue_idempotency_key) WHERE issue_idempotency_key IS NOT NULL;
CREATE INDEX chargeback_statement_list_idx ON governance.chargeback_statement (tenant_id, book_id, period DESC, status);
CREATE INDEX chargeback_statement_target_idx ON governance.chargeback_statement (tenant_id, target_group_id, period DESC) WHERE status IN ('ISSUED', 'SUPERSEDED');
COMMENT ON TABLE governance.chargeback_statement IS 'Internal chargeback statement header (not a tax invoice). Unique (tenant, book, target_group, period, currency, version_no). After ISSUED only status→SUPERSEDED and pdf_* may change (trigger). Issued PDF: S3 Object Lock GOVERNANCE, retention class RECORD = max(400 days, contract). State machine contracts/state-machines/chargeback_statement.yaml. owner_task=ALC-008-S01.';
COMMENT ON COLUMN governance.chargeback_statement.rounded_total IS 'Statement total in minor units after hierarchical signed largest remainder; digest value. privacy=INTERNAL.';
COMMENT ON COLUMN governance.chargeback_statement.precondition_results_json IS 'Versioned list [{code: PERIOD_CLOSED|MONTH_STABLE|CONTROLS_RECONCILED|PRICE_BASIS_BILLED|SINGLE_BOOK_CURRENCY|FOUR_EYES|TRIAL_ACCOUNT_EXCLUDED, result: PASS|FAIL|EXCEPTED, exception_approval_id?}].';

-- ============================================================================================================
-- 6. Maker-checker approvals (authored in this schema file on behalf of SEC-102; SEC backlog Appendix C.4).
--    State machine `approval` is owned by lane K2 (contracts/state-machines/approval.yaml); regenerate the CHECK
--    from it. ALC uses actions rule.publish (FINANCIAL), access.review (ACCESS), statement.issue,
--    allocation.transfer, allocation.pool_disclosure, statement.precondition_exception.
-- ============================================================================================================
CREATE TABLE governance.approval (
    tenant_id          uuid        NOT NULL,
    id                 uuid        NOT NULL,
    action             text        NOT NULL,
    object_type        text        NOT NULL,
    object_id          uuid        NOT NULL,
    object_revision    bigint      NOT NULL,
    content_sha256     text        NOT NULL,
    approval_kind      text        NULL,
    binding_json       jsonb       NULL,
    binding_schema_version text    NULL,
    requested_by       uuid        NOT NULL,
    requested_at       timestamptz NOT NULL DEFAULT now(),
    reason             text        NULL,
    state              text        NOT NULL DEFAULT 'REQUESTED',
    decided_by         uuid        NULL,
    decided_at         timestamptz NULL,
    decision_reason    text        NULL,
    self_approved      boolean     NOT NULL DEFAULT false,
    expires_at         timestamptz NOT NULL,
    executed_at        timestamptz NULL,
    voided_at          timestamptz NULL,
    void_reason        text        NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    revision           bigint      NOT NULL DEFAULT 1,
    CONSTRAINT approval_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT approval_state CHECK (state IN ('REQUESTED', 'APPROVED', 'REJECTED', 'EXPIRED', 'VOIDED', 'EXECUTED')),
    CONSTRAINT approval_kind CHECK (approval_kind IS NULL OR approval_kind IN ('FINANCIAL', 'ACCESS')),
    CONSTRAINT approval_sha CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT approval_decided CHECK ((state IN ('APPROVED', 'REJECTED', 'EXECUTED')) = (decided_by IS NOT NULL AND decided_at IS NOT NULL)),
    CONSTRAINT approval_sod CHECK (decided_by IS NULL OR self_approved OR decided_by <> requested_by),
    CONSTRAINT approval_expiry CHECK (expires_at <= requested_at + interval '7 days'),
    CONSTRAINT approval_binding_versioned CHECK ((binding_json IS NULL) = (binding_schema_version IS NULL))
);
CREATE UNIQUE INDEX approval_open_uq ON governance.approval (tenant_id, action, object_id, object_revision, coalesce(approval_kind, '-')) WHERE state IN ('REQUESTED', 'APPROVED');
CREATE INDEX approval_object_idx ON governance.approval (tenant_id, object_type, object_id, state);
CREATE INDEX approval_inbox_idx ON governance.approval (tenant_id, state, requested_at DESC) WHERE state = 'REQUESTED';
COMMENT ON TABLE governance.approval IS 'Generic maker-checker approval (SEC-102, SEC Appendix C.4). Binds (action, object_type, object_id, object_revision, content_sha256); approver <> requester and <> last editor; 7-day expiry; any revision change voids it. ALC ruleset approvals add approval_kind FINANCIAL|ACCESS and binding_json {simulation_id, window_fingerprint, access_impact_digest}. owner_task=SEC-102 (authored in K7 schema file).';
COMMENT ON COLUMN governance.approval.reason IS 'privacy=CUSTOMER_METADATA.';

-- ============================================================================================================
-- 7. Config publications (authored in this schema file on behalf of CTL-005; CTL backlog CTL-005-S03, Appendix G).
-- ============================================================================================================
CREATE TABLE governance.config_publication (
    tenant_id              uuid        NOT NULL,
    id                     uuid        NOT NULL,
    config_kind            text        NOT NULL,
    config_version         bigint      NOT NULL,
    parent_version         bigint      NULL,
    source_revisions_json  jsonb       NOT NULL,
    source_revisions_schema_version text NOT NULL DEFAULT 'config-source-revisions.v1',
    content_sha256         text        NOT NULL,
    row_count              bigint      NOT NULL,
    approval_id            uuid        NULL,
    status                 text        NOT NULL DEFAULT 'PENDING_PUBLICATION',
    attempts               integer     NOT NULL DEFAULT 0,
    failure_code           text        NULL,
    published_at           timestamptz NULL,
    archive_object_key     text        NULL,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    revision               bigint      NOT NULL DEFAULT 1,
    CONSTRAINT config_publication_pk PRIMARY KEY (tenant_id, id),
    CONSTRAINT config_publication_version_uq UNIQUE (tenant_id, config_kind, config_version),
    CONSTRAINT config_publication_kind CHECK (config_kind IN ('TAG_DIMENSION', 'TAG_RULESET', 'GROUP_HIERARCHY',
        'ALLOCATION_POLICY', 'ALLOCATION_TRANSFER', 'POOL_DISCLOSURE', 'BUDGET', 'MONITOR',
        'PRICE_RATE', 'BILLING_REFERENCE', 'CLOSE_RECORD', 'ACCOUNT_MEMBERSHIP', 'ORGANIZATION', 'TEAM')),
    CONSTRAINT config_publication_status CHECK (status IN ('PENDING_PUBLICATION', 'PUBLISHED', 'FAILED')),
    CONSTRAINT config_publication_sha CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT config_publication_published CHECK ((status = 'PUBLISHED') = (published_at IS NOT NULL))
);
CREATE INDEX config_publication_pending_idx ON governance.config_publication (tenant_id, config_kind, config_version) WHERE status = 'PENDING_PUBLICATION';
COMMENT ON TABLE governance.config_publication IS 'PostgreSQL side of the D-04 config publisher: one immutable config_version per (tenant, config_kind), allocated monotonically; PENDING_PUBLICATION → PUBLISHED | FAILED (CONFIG_VERSION_CONFLICT). The K7 kinds TAG_DIMENSION, TAG_RULESET, GROUP_HIERARCHY, ALLOCATION_POLICY, ALLOCATION_TRANSFER, POOL_DISCLOSURE, BUDGET, MONITOR map to CONFIG.cfg_* tables of infra/snowflake/migrations/CONFIG/V0600..V0603. owner_task=CTL-005 (authored in K7 schema file; kind list shared with K2/K5).';

-- ============================================================================================================
-- 8. Triggers: immutability of frozen configuration and issued statements; UNASSIGNED protection.
-- ============================================================================================================
CREATE OR REPLACE FUNCTION governance.tg_version_content_immutable() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status <> 'DRAFT' AND (NEW.content_sha256 IS DISTINCT FROM OLD.content_sha256
        OR NEW.content_schema_version IS DISTINCT FROM OLD.content_schema_version
        OR NEW.min_valid_from IS DISTINCT FROM OLD.min_valid_from) THEN
        RAISE EXCEPTION 'content of % % is immutable in status %', TG_TABLE_NAME, OLD.id, OLD.status
            USING ERRCODE = 'BL701';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER ruleset_version_content_immutable BEFORE UPDATE ON governance.ruleset_version
    FOR EACH ROW EXECUTE FUNCTION governance.tg_version_content_immutable();
CREATE TRIGGER hierarchy_version_content_immutable BEFORE UPDATE ON governance.hierarchy_version
    FOR EACH ROW EXECUTE FUNCTION governance.tg_version_content_immutable();

CREATE OR REPLACE FUNCTION governance.tg_child_of_frozen_version() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    parent_status text;
    parent_id uuid;
    r record;
BEGIN
    IF TG_OP = 'DELETE' THEN r := OLD; ELSE r := NEW; END IF;
    IF TG_TABLE_NAME IN ('tag_rule', 'rule_override') THEN
        SELECT status INTO parent_status FROM governance.ruleset_version
         WHERE tenant_id = r.tenant_id AND id = r.ruleset_version_id;
    ELSE
        SELECT status INTO parent_status FROM governance.hierarchy_version
         WHERE tenant_id = r.tenant_id AND id = r.hierarchy_version_id;
    END IF;
    IF parent_status IS DISTINCT FROM 'DRAFT' THEN
        RAISE EXCEPTION '% rows of a non-DRAFT version are immutable', TG_TABLE_NAME USING ERRCODE = 'BL701';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER tag_rule_frozen BEFORE INSERT OR UPDATE OR DELETE ON governance.tag_rule
    FOR EACH ROW EXECUTE FUNCTION governance.tg_child_of_frozen_version();
CREATE TRIGGER rule_override_frozen BEFORE INSERT OR UPDATE OR DELETE ON governance.rule_override
    FOR EACH ROW EXECUTE FUNCTION governance.tg_child_of_frozen_version();
CREATE TRIGGER hierarchy_edge_frozen BEFORE INSERT OR UPDATE OR DELETE ON governance.hierarchy_edge
    FOR EACH ROW EXECUTE FUNCTION governance.tg_child_of_frozen_version();
CREATE TRIGGER group_value_mapping_frozen BEFORE INSERT OR UPDATE OR DELETE ON governance.group_value_mapping
    FOR EACH ROW EXECUTE FUNCTION governance.tg_child_of_frozen_version();

CREATE OR REPLACE FUNCTION governance.tg_usage_group_protect_unassigned() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.system_kind = 'UNASSIGNED' THEN
        IF TG_OP = 'DELETE' THEN
            RAISE EXCEPTION 'the UNASSIGNED group cannot be deleted' USING ERRCODE = 'BL702';
        END IF;
        IF NEW.system_kind <> 'UNASSIGNED' OR NEW.archived_at IS NOT NULL OR NEW.group_set_id <> OLD.group_set_id THEN
            RAISE EXCEPTION 'the UNASSIGNED group cannot be archived or changed' USING ERRCODE = 'BL702';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER usage_group_protect_unassigned BEFORE UPDATE OR DELETE ON governance.usage_group
    FOR EACH ROW EXECUTE FUNCTION governance.tg_usage_group_protect_unassigned();

CREATE OR REPLACE FUNCTION governance.tg_chargeback_statement_immutable() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' AND OLD.status IN ('ISSUED', 'SUPERSEDED') THEN
        RAISE EXCEPTION 'issued statements cannot be deleted' USING ERRCODE = 'BL703';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.status = 'SUPERSEDED' THEN
        IF (to_jsonb(NEW) - ARRAY['pdf_status', 'pdf_object_key', 'pdf_sha256', 'pdf_retain_until', 'updated_at', 'revision'])
           IS DISTINCT FROM
           (to_jsonb(OLD) - ARRAY['pdf_status', 'pdf_object_key', 'pdf_sha256', 'pdf_retain_until', 'updated_at', 'revision']) THEN
            RAISE EXCEPTION 'superseded statement % is immutable (only pdf_* allowed)', OLD.id USING ERRCODE = 'BL703';
        END IF;
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.status = 'ISSUED' THEN
        IF (to_jsonb(NEW) - ARRAY['status', 'superseded_by_statement_id', 'superseded_at', 'pdf_status', 'pdf_object_key',
                                  'pdf_sha256', 'pdf_retain_until', 'updated_at', 'revision'])
           IS DISTINCT FROM
           (to_jsonb(OLD) - ARRAY['status', 'superseded_by_statement_id', 'superseded_at', 'pdf_status', 'pdf_object_key',
                                  'pdf_sha256', 'pdf_retain_until', 'updated_at', 'revision'])
           OR NEW.status NOT IN ('ISSUED', 'SUPERSEDED') THEN
            RAISE EXCEPTION 'issued statement % is immutable (only ISSUED→SUPERSEDED and pdf_* allowed)', OLD.id
                USING ERRCODE = 'BL703';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER chargeback_statement_immutable BEFORE UPDATE OR DELETE ON governance.chargeback_statement
    FOR EACH ROW EXECUTE FUNCTION governance.tg_chargeback_statement_immutable();

-- ============================================================================================================
-- 9. Row level security (SEC RLS standard template; ENABLE + FORCE on every tenant table)
-- ============================================================================================================
ALTER TABLE governance.dimension_definition ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.dimension_definition FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.dimension_definition
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE governance.dimension_allowed_value ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.dimension_allowed_value FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.dimension_allowed_value
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE governance.ruleset_version ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.ruleset_version FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.ruleset_version
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE governance.tag_rule ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.tag_rule FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.tag_rule
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE governance.rule_override ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.rule_override FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.rule_override
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE governance.usage_group_set ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.usage_group_set FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.usage_group_set
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE governance.usage_group ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.usage_group FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.usage_group
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE governance.hierarchy_version ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.hierarchy_version FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.hierarchy_version
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE governance.hierarchy_edge ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.hierarchy_edge FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.hierarchy_edge
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE governance.group_value_mapping ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.group_value_mapping FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.group_value_mapping
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE governance.budget ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.budget FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.budget
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE governance.budget_revision ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.budget_revision FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.budget_revision
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE governance.chargeback_preparation ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.chargeback_preparation FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.chargeback_preparation
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE governance.chargeback_statement ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.chargeback_statement FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.chargeback_statement
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE governance.approval ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.approval FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.approval
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

ALTER TABLE governance.config_publication ENABLE ROW LEVEL SECURITY;
ALTER TABLE governance.config_publication FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON governance.config_publication
    USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);

-- ============================================================================================================
-- 10. Cross-lane foreign keys (require identity.* from lane K2; expected names recorded in contracts/_handoffs/K7.md).
-- ============================================================================================================
ALTER TABLE governance.budget ADD CONSTRAINT budget_owner_membership_fk
    FOREIGN KEY (tenant_id, owner_membership_id) REFERENCES identity.membership (tenant_id, id);
ALTER TABLE governance.budget_revision ADD CONSTRAINT budget_revision_owner_membership_fk
    FOREIGN KEY (tenant_id, owner_membership_id) REFERENCES identity.membership (tenant_id, id);

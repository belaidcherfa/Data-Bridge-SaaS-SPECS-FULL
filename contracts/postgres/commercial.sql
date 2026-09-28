-- contract=postgres-commercial version=1 status=DRAFT owner_task=LCH-101,LCH-001,LCH-103,LCH-105 decisions=D-11,D-17,D-25,D-30,D-35,D-36 last_changed=2026-09-28
-- Contract lane: K9. Schema file owner: K9 (contracts/README.md). Alembic migrations converge to this file:
--   commercial_0001 (LCH-101-S01)  plans, plan bands, entitlements, overrides
--   commercial_0002 (LCH-001-S02)  subscriptions, subscription events, change requests (four-eyes)
--   commercial_0002b (LCH-001-S04) invoice references, payment events, payment allocations; billing profile (LCH-103-S04)
--   commercial_0003 (LCH-105-S01)  spend band assignments and per-currency totals
-- Backlog name -> contract name (CONVENTIONS §2 singular; relational data normalized instead of JSONB, CONVENTIONS §10):
--   commercial.plans                      -> commercial.plan + commercial.plan_band + commercial.plan_band_threshold
--                                            (backlog JSONB spend_bands {<currency>: [{band_id, rank, lower_inclusive, upper_exclusive, band_fee_usd}]}
--                                             is split into band definition (rank, USD fee) and per-spend-currency thresholds, so a band has
--                                             one fee whatever the spend currency and ranks are comparable across currencies - D-17 "no FX")
--   commercial.tenant_entitlements        -> commercial.tenant_entitlement + commercial.entitlement_override (backlog overrides JSONB)
--   commercial.subscriptions / _events    -> commercial.subscription / commercial.subscription_event
--   commercial.invoice_refs               -> commercial.invoice_ref
--   commercial.payment_events             -> commercial.payment_event + commercial.payment_allocation (backlog allocations JSONB)
--   commercial.spend_band_assignments     -> commercial.spend_band_assignment + commercial.spend_band_total (backlog per_currency_totals JSONB)
--   (LCH-103-S04)                         -> commercial.billing_profile
--   (LCH-001-S10, LCH-101-S08 four-eyes)  -> commercial.change_request
-- State machine: contracts/state-machines/subscription.yaml. PostgreSQL stores plans, entitlements, subscription state and
-- invoice/payment REFERENCES only: no invoice rendering, no card data, no e-invoicing-platform fields in R1 (D-30; R2 own ADR).
-- Money: invoice/payment amounts are numeric(18,2) in currencies with 2 minor digits (R1: USD, EUR, GBP, CHF; others rejected
-- with COMM_CURRENCY_UNSUPPORTED); managed spend totals are exact numeric(38,12) (CONVENTIONS §5).

CREATE SCHEMA IF NOT EXISTS commercial;
COMMENT ON SCHEMA commercial IS 'Plans, entitlements, subscription state, invoice and payment references, managed-spend bands (LCH-001/101/103/105). Owner lane K9.';

CREATE OR REPLACE FUNCTION commercial.forbid_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'commercial.%: % is forbidden on an append-only table', TG_TABLE_NAME, TG_OP
    USING ERRCODE = '42501';
END;
$$;

-- =============================================================================================
-- Global plan catalog (no tenant_id; global table listed in the RLS standard: readable by bridge_api/bridge_worker,
-- writable only by bridge_ops_api under finance_operator + owner approval). PUBLISHED plan versions are immutable.
-- =============================================================================================
CREATE TABLE commercial.plan (
  id                      uuid          NOT NULL,
  version                 integer       NOT NULL,
  plan_key                text          NOT NULL,
  name                    text          NOT NULL,
  kind                    text          NOT NULL,
  status                  text          NOT NULL DEFAULT 'DRAFT',
  platform_fee            numeric(18,2) NOT NULL,
  platform_fee_currency   char(3)       NOT NULL DEFAULT 'USD',
  fee_period              text          NOT NULL DEFAULT 'MONTH',
  limit_connected_accounts   integer    NOT NULL,
  limit_demo_trial_accounts  integer    NOT NULL DEFAULT 1,
  limit_users                integer    NOT NULL,
  limit_history_days         integer    NOT NULL,
  limit_query_detail_days    integer    NOT NULL DEFAULT 365,
  limit_report_schedules     integer    NOT NULL,
  limit_api_clients          integer    NOT NULL,
  limit_heavy_jobs_concurrent integer   NOT NULL,
  limit_backfills_concurrent integer    NOT NULL,
  features                text[]        NOT NULL DEFAULT '{}',
  effective_from          timestamptz   NOT NULL,
  retired_at              timestamptz   NULL,
  approved_by             text          NULL,
  created_by              text          NOT NULL,
  created_at              timestamptz   NOT NULL DEFAULT now(),
  updated_at              timestamptz   NOT NULL DEFAULT now(),
  revision                bigint        NOT NULL DEFAULT 1,
  CONSTRAINT plan_pk PRIMARY KEY (id, version),
  CONSTRAINT plan_key_version_unique UNIQUE (plan_key, version),
  CONSTRAINT plan_key_fmt_ck CHECK (plan_key ~ '^[A-Z][A-Z0-9_]{2,63}$'),
  CONSTRAINT plan_version_ck CHECK (version >= 1),
  CONSTRAINT plan_kind_ck CHECK (kind IN ('PILOT','COMMERCIAL')),
  CONSTRAINT plan_status_ck CHECK (status IN ('DRAFT','PUBLISHED','RETIRED')),
  CONSTRAINT plan_fee_ck CHECK (platform_fee >= 0),
  CONSTRAINT plan_fee_currency_ck CHECK (platform_fee_currency = 'USD'),
  CONSTRAINT plan_fee_period_ck CHECK (fee_period = 'MONTH'),
  CONSTRAINT plan_limits_ck CHECK (limit_connected_accounts >= 0 AND limit_demo_trial_accounts >= 0 AND limit_users >= 1
      AND limit_history_days BETWEEN 0 AND 400 AND limit_query_detail_days BETWEEN 0 AND 365 AND limit_report_schedules >= 0
      AND limit_api_clients >= 0 AND limit_heavy_jobs_concurrent >= 0 AND limit_backfills_concurrent >= 0),
  CONSTRAINT plan_published_ck CHECK (status = 'DRAFT' OR approved_by IS NOT NULL),
  CONSTRAINT plan_approver_ck CHECK (approved_by IS NULL OR approved_by <> created_by),
  CONSTRAINT plan_retired_ck CHECK ((status = 'RETIRED') = (retired_at IS NOT NULL)),
  CONSTRAINT plan_revision_ck CHECK (revision >= 1)
);
COMMENT ON TABLE commercial.plan IS 'LCH-101-S01, LCH-001-S01 (D-17). Versioned plan catalog: USD platform fee per month plus a band of managed Snowflake spend (commercial.plan_band*). kind PILOT = contracted, possibly discounted pilot (never a free trial). Limits are the plan-agnostic quota vector enforced by entitlements.check() at admission (LCH-101-S03). A PUBLISHED version is immutable; changes create version + 1.';
COMMENT ON COLUMN commercial.plan.platform_fee IS 'x-privacy: INTERNAL. Monthly platform fee in USD (D-17).';
COMMENT ON COLUMN commercial.plan.limit_query_detail_days IS 'query_detail_days = hot_days (D-11): default 365, bounded by Account Usage retention.';
COMMENT ON COLUMN commercial.plan.limit_demo_trial_accounts IS 'D-35: separate quota for Snowflake trial (demonstration-only) connections; never counted in connected_accounts.';
COMMENT ON COLUMN commercial.plan.features IS 'Feature keys enabled by the plan (lower snake case, e.g. sso_federation, full_sql_mode, api_clients). Evaluated by entitlements.check(capability=feature:<key>).';
COMMENT ON COLUMN commercial.plan.approved_by IS 'x-privacy: INTERNAL. operator:<id> or owner reference approving the published version (LCH-001-S01 owner approval).';

CREATE TABLE commercial.plan_band (
  plan_id        uuid          NOT NULL,
  plan_version   integer       NOT NULL,
  band_id        text          NOT NULL,
  rank           smallint      NOT NULL,
  band_fee_usd   numeric(18,2) NOT NULL,
  created_at     timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT plan_band_pk PRIMARY KEY (plan_id, plan_version, band_id),
  CONSTRAINT plan_band_rank_unique UNIQUE (plan_id, plan_version, rank),
  CONSTRAINT plan_band_plan_fk FOREIGN KEY (plan_id, plan_version) REFERENCES commercial.plan (id, version),
  CONSTRAINT plan_band_id_fmt_ck CHECK (band_id ~ '^B[0-9]{1,2}$'),
  CONSTRAINT plan_band_rank_ck CHECK (rank BETWEEN 1 AND 99),
  CONSTRAINT plan_band_fee_ck CHECK (band_fee_usd >= 0)
);
COMMENT ON TABLE commercial.plan_band IS 'LCH-101-S01 (D-17). Bands of managed Snowflake spend with their monthly USD fee. Ranks 1..n are contiguous; the assigned band of a multi-currency tenant is the highest rank reached across its spend currencies (docs/commercial/spend-bands.md).';

CREATE TABLE commercial.plan_band_threshold (
  plan_id           uuid           NOT NULL,
  plan_version      integer        NOT NULL,
  spend_currency    char(3)        NOT NULL,
  band_id           text           NOT NULL,
  lower_inclusive   numeric(38,12) NOT NULL,
  upper_exclusive   numeric(38,12) NULL,
  created_at        timestamptz    NOT NULL DEFAULT now(),
  CONSTRAINT plan_band_threshold_pk PRIMARY KEY (plan_id, plan_version, spend_currency, band_id),
  CONSTRAINT plan_band_threshold_band_fk FOREIGN KEY (plan_id, plan_version, band_id) REFERENCES commercial.plan_band (plan_id, plan_version, band_id),
  CONSTRAINT plan_band_threshold_currency_ck CHECK (spend_currency ~ '^[A-Z]{3}$'),
  CONSTRAINT plan_band_threshold_bounds_ck CHECK (lower_inclusive >= 0 AND (upper_exclusive IS NULL OR upper_exclusive > lower_inclusive))
);
CREATE UNIQUE INDEX plan_band_threshold_lower_unique ON commercial.plan_band_threshold (plan_id, plan_version, spend_currency, lower_inclusive);
COMMENT ON TABLE commercial.plan_band_threshold IS 'LCH-101-S01, LCH-105-S01. Half-open thresholds [lower_inclusive, upper_exclusive) per spend currency (a total equal to a boundary belongs to the higher band). Publication-time validation (plan DRAFT -> PUBLISHED, COMM_PLAN_BANDS_INVALID): for every spend currency the thresholds cover every band of the plan, start at 0, are contiguous (upper of rank r = lower of rank r+1) and only the top band has upper_exclusive NULL.';

-- =============================================================================================
-- Tenant entitlements (LCH-101)
-- =============================================================================================
CREATE TABLE commercial.tenant_entitlement (
  tenant_id            uuid        NOT NULL,
  id                   uuid        NOT NULL,
  entitlement_version  integer     NOT NULL,
  plan_id              uuid        NOT NULL,
  plan_version         integer     NOT NULL,
  status               text        NOT NULL DEFAULT 'PENDING_APPROVAL',
  effective_from       timestamptz NOT NULL,
  superseded_at        timestamptz NULL,
  set_by               text        NOT NULL,
  approved_by          text        NULL,
  change_request_id    uuid        NULL,
  reason_code          text        NOT NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  revision             bigint      NOT NULL DEFAULT 1,
  CONSTRAINT tenant_entitlement_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT tenant_entitlement_version_unique UNIQUE (tenant_id, entitlement_version),
  CONSTRAINT tenant_entitlement_plan_fk FOREIGN KEY (plan_id, plan_version) REFERENCES commercial.plan (id, version),
  CONSTRAINT tenant_entitlement_status_ck CHECK (status IN ('PENDING_APPROVAL','ACTIVE','SUPERSEDED','REJECTED')),
  CONSTRAINT tenant_entitlement_version_ck CHECK (entitlement_version >= 1),
  CONSTRAINT tenant_entitlement_actor_ck CHECK (set_by ~ '^(operator|system):[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT tenant_entitlement_approver_ck CHECK (approved_by IS NULL OR approved_by <> set_by),
  CONSTRAINT tenant_entitlement_superseded_ck CHECK ((status = 'SUPERSEDED') = (superseded_at IS NOT NULL)),
  CONSTRAINT tenant_entitlement_reason_ck CHECK (reason_code IN ('TENANT_PROVISIONED','PILOT_ORDER','COMMERCIAL_ORDER','PLAN_CHANGE','OVERRIDE','CAPACITY_QUOTA_UPDATE','CORRECTION')),
  CONSTRAINT tenant_entitlement_revision_ck CHECK (revision >= 1)
);
CREATE UNIQUE INDEX tenant_entitlement_one_active ON commercial.tenant_entitlement (tenant_id) WHERE status = 'ACTIVE';
COMMENT ON TABLE commercial.tenant_entitlement IS 'LCH-101-S01/S02. Entitlement history of a tenant: plan version + approved overrides. Exactly one ACTIVE row per tenant; a change inserts entitlement_version + 1 and supersedes the previous row in the same transaction. effective_entitlements(tenant, at) = plan limits (+) ACTIVE overrides (+) subscription state effects (docs/commercial/subscription-state-machine.md). An override above the plan limit needs approved_by <> set_by (change_request kind ENTITLEMENT_OVERRIDE_ABOVE_PLAN).';
COMMENT ON COLUMN commercial.tenant_entitlement.set_by IS 'x-privacy: INTERNAL. operator:<id> (finance_operator / ops_provisioner) or system:<component>.';

CREATE TABLE commercial.entitlement_override (
  tenant_id        uuid        NOT NULL,
  id               uuid        NOT NULL,
  entitlement_id   uuid        NOT NULL,
  quota_key        text        NOT NULL,
  limit_value      integer     NOT NULL,
  exceeds_plan     boolean     NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  revision         bigint      NOT NULL DEFAULT 1,
  CONSTRAINT entitlement_override_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT entitlement_override_unique UNIQUE (tenant_id, entitlement_id, quota_key),
  CONSTRAINT entitlement_override_ent_fk FOREIGN KEY (tenant_id, entitlement_id) REFERENCES commercial.tenant_entitlement (tenant_id, id),
  CONSTRAINT entitlement_override_key_ck CHECK (quota_key IN ('connected_accounts','demo_trial_accounts','users','history_days','query_detail_days',
      'report_schedules','api_clients','heavy_jobs_concurrent','backfills_concurrent')),
  CONSTRAINT entitlement_override_value_ck CHECK (limit_value >= 0),
  CONSTRAINT entitlement_override_revision_ck CHECK (revision = 1)
);
CREATE TRIGGER entitlement_override_append_only BEFORE UPDATE OR DELETE ON commercial.entitlement_override
  FOR EACH ROW EXECUTE FUNCTION commercial.forbid_mutation();
COMMENT ON TABLE commercial.entitlement_override IS 'LCH-101-S01. Per-quota overrides attached to one immutable entitlement version (backlog overrides JSONB, normalized).';

-- =============================================================================================
-- Subscriptions (LCH-001-S02; state machine subscription.yaml)
-- =============================================================================================
CREATE TABLE commercial.subscription (
  tenant_id            uuid        NOT NULL,
  id                   uuid        NOT NULL,
  plan_id              uuid        NOT NULL,
  plan_version         integer     NOT NULL,
  state                text        NOT NULL,
  state_effective_at   timestamptz NOT NULL,
  contract_kind        text        NOT NULL,
  contract_ref         text        NOT NULL,
  term_start           date        NOT NULL,
  term_end             date        NOT NULL,
  grace_days           integer     NOT NULL DEFAULT 30,
  grace_until          timestamptz NULL,
  export_window_days   integer     NOT NULL DEFAULT 30,
  export_window_until  timestamptz NULL,
  cancelled_at         timestamptz NULL,
  created_by           text        NOT NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  revision             bigint      NOT NULL DEFAULT 1,
  CONSTRAINT subscription_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT subscription_plan_fk FOREIGN KEY (plan_id, plan_version) REFERENCES commercial.plan (id, version),
  CONSTRAINT subscription_state_ck CHECK (state IN ('PILOT','ACTIVE_PENDING_PAYMENT','ACTIVE_PAID','PAST_DUE','SUSPENDED','CANCELLED')),
  CONSTRAINT subscription_contract_kind_ck CHECK (contract_kind IN ('PILOT_ORDER','COMMERCIAL_ORDER')),
  CONSTRAINT subscription_pilot_contract_ck CHECK (state <> 'PILOT' OR contract_kind = 'PILOT_ORDER'),
  CONSTRAINT subscription_contract_ref_ck CHECK (char_length(contract_ref) BETWEEN 3 AND 128),
  CONSTRAINT subscription_term_ck CHECK (term_end > term_start),
  CONSTRAINT subscription_grace_ck CHECK (grace_days BETWEEN 0 AND 90 AND export_window_days BETWEEN 0 AND 90),
  CONSTRAINT subscription_past_due_ck CHECK (state <> 'PAST_DUE' OR grace_until IS NOT NULL),
  CONSTRAINT subscription_cancelled_ck CHECK ((state = 'CANCELLED') = (cancelled_at IS NOT NULL AND export_window_until IS NOT NULL)),
  CONSTRAINT subscription_actor_ck CHECK (created_by ~ '^(operator|system):[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT subscription_revision_ck CHECK (revision >= 1)
);
CREATE UNIQUE INDEX subscription_one_current ON commercial.subscription (tenant_id) WHERE state <> 'CANCELLED';
CREATE INDEX subscription_state_idx ON commercial.subscription (state, grace_until);
COMMENT ON TABLE commercial.subscription IS 'LCH-001-S02 (C-08, D-17). The only subscription state machine: PILOT -> ACTIVE_PENDING_PAYMENT -> ACTIVE_PAID; PAST_DUE, SUSPENDED, CANCELLED. No TRIAL state and no free trial; a PILOT needs a signed pilot order (contract_ref). A synthetic demo tenant is a tenant flag (is_synthetic, K2), never a state. State changes never delete data (retention is independent, OPS-005). Every change inserts a commercial.subscription_event in the same transaction.';
COMMENT ON COLUMN commercial.subscription.contract_ref IS 'x-privacy: INTERNAL. Reference of the signed pilot/commercial order in the private contract system.';
COMMENT ON COLUMN commercial.subscription.grace_until IS 'PAST_DUE: due date of the oldest overdue invoice + grace_days (default 30, LCH Q3). SUSPENDED requires now() >= grace_until and a second finance operator.';
COMMENT ON COLUMN commercial.subscription.export_window_until IS 'CANCELLED: Owner-only export window end (default 30 days).';

CREATE TABLE commercial.subscription_event (
  tenant_id            uuid        NOT NULL,
  id                   uuid        NOT NULL,
  subscription_id      uuid        NOT NULL,
  seq                  integer     NOT NULL,
  from_state           text        NULL,
  to_state             text        NOT NULL,
  event                text        NOT NULL,
  reason_code          text        NOT NULL,
  reason_detail        text        NULL,
  actor                text        NOT NULL,
  approved_by          text        NULL,
  change_request_id    uuid        NULL,
  invoice_ref_id       uuid        NULL,
  payment_event_id     uuid        NULL,
  effective_at         timestamptz NOT NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  revision             bigint      NOT NULL DEFAULT 1,
  CONSTRAINT subscription_event_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT subscription_event_seq_unique UNIQUE (tenant_id, subscription_id, seq),
  CONSTRAINT subscription_event_sub_fk FOREIGN KEY (tenant_id, subscription_id) REFERENCES commercial.subscription (tenant_id, id),
  CONSTRAINT subscription_event_states_ck CHECK ((from_state IS NULL OR from_state IN ('PILOT','ACTIVE_PENDING_PAYMENT','ACTIVE_PAID','PAST_DUE','SUSPENDED','CANCELLED'))
      AND to_state IN ('PILOT','ACTIVE_PENDING_PAYMENT','ACTIVE_PAID','PAST_DUE','SUSPENDED','CANCELLED')),
  CONSTRAINT subscription_event_event_ck CHECK (event IN ('pilot_order_recorded','commercial_order_recorded','invoice_settled','renewal_invoice_recorded',
      'payment_overdue','payment_reversed','overdue_cleared_by_credit_note','suspension_approved','pilot_expired','resumption_approved','cancellation_approved')),
  CONSTRAINT subscription_event_seq_ck CHECK (seq >= 1),
  CONSTRAINT subscription_event_actor_ck CHECK (actor ~ '^(operator|system):[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT subscription_event_approver_ck CHECK (approved_by IS NULL OR approved_by <> actor),
  CONSTRAINT subscription_event_four_eyes_ck CHECK (event NOT IN ('suspension_approved','cancellation_approved') OR (approved_by IS NOT NULL AND change_request_id IS NOT NULL)),
  CONSTRAINT subscription_event_append_only_ck CHECK (revision = 1)
);
CREATE TRIGGER subscription_event_append_only BEFORE UPDATE OR DELETE ON commercial.subscription_event
  FOR EACH ROW EXECUTE FUNCTION commercial.forbid_mutation();
COMMENT ON TABLE commercial.subscription_event IS 'LCH-001-S02. Append-only transition log of commercial.subscription (event names = subscription.yaml events). seq equals the subscription aggregate version after the transition (outbox aggregate_version).';
COMMENT ON COLUMN commercial.subscription_event.reason_detail IS 'x-privacy: INTERNAL. Operator note without personal data.';

-- =============================================================================================
-- Four-eyes operator change requests (LCH-001-S10, LCH-101-S08)
-- =============================================================================================
CREATE TABLE commercial.change_request (
  tenant_id               uuid        NOT NULL,
  id                      uuid        NOT NULL,
  kind                    text        NOT NULL,
  target_id               uuid        NOT NULL,
  target_revision         bigint      NOT NULL,
  payload_json            jsonb       NOT NULL,
  payload_schema_version  smallint    NOT NULL DEFAULT 1,
  status                  text        NOT NULL DEFAULT 'REQUESTED',
  reason_code             text        NOT NULL,
  requested_by            text        NOT NULL,
  requested_at            timestamptz NOT NULL DEFAULT now(),
  decided_by              text        NULL,
  decided_at              timestamptz NULL,
  executed_at             timestamptz NULL,
  effective_at            timestamptz NULL,
  expires_at              timestamptz NOT NULL,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  revision                bigint      NOT NULL DEFAULT 1,
  CONSTRAINT change_request_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT change_request_kind_ck CHECK (kind IN ('SUBSCRIPTION_SUSPEND','SUBSCRIPTION_CANCEL','ENTITLEMENT_OVERRIDE_ABOVE_PLAN','PLAN_CHANGE')),
  CONSTRAINT change_request_status_ck CHECK (status IN ('REQUESTED','APPROVED','REJECTED','EXECUTED','EXPIRED')),
  CONSTRAINT change_request_reason_ck CHECK (reason_code IN ('NON_PAYMENT','CONTRACT_TERMINATION','CUSTOMER_REQUEST','TERM_END','SECURITY','CAPACITY','COMMERCIAL_AGREEMENT')),
  CONSTRAINT change_request_actor_ck CHECK (requested_by ~ '^(member|operator):[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT change_request_decider_ck CHECK (decided_by IS NULL OR (decided_by <> requested_by AND decided_by ~ '^operator:[A-Za-z0-9._:-]{1,128}$')),
  CONSTRAINT change_request_decided_ck CHECK ((status IN ('APPROVED','REJECTED','EXECUTED')) = (decided_by IS NOT NULL AND decided_at IS NOT NULL)),
  CONSTRAINT change_request_executed_ck CHECK ((status = 'EXECUTED') = (executed_at IS NOT NULL)),
  CONSTRAINT change_request_expiry_ck CHECK (expires_at > requested_at AND expires_at <= requested_at + interval '7 days'),
  CONSTRAINT change_request_payload_ck CHECK (jsonb_typeof(payload_json) = 'object'),
  CONSTRAINT change_request_revision_ck CHECK (revision >= 1)
);
CREATE INDEX change_request_open_idx ON commercial.change_request (tenant_id, status, expires_at);
COMMENT ON TABLE commercial.change_request IS 'LCH-001-S10, LCH-101-S08. Maker-checker for operator actions: suspension, cancellation, entitlement override above plan, plan change (a PLAN_CHANGE may be requested by a tenant Owner with subscription.manage). decided_by must differ from requested_by; an approval binds target_revision and expires after 7 days; a changed target revision voids execution (409 PRECONDITION_FAILED).';
COMMENT ON COLUMN commercial.change_request.payload_json IS 'x-privacy: INTERNAL. Versioned document per kind: {effective_at, plan_id, plan_version} | {overrides:[{quota_key, limit_value}]} | {cancellation_effective_on}; schema in contracts/openapi/components/commercial.yaml (ChangeRequestPayload).';

-- =============================================================================================
-- Billing profile (LCH-103-S04)
-- =============================================================================================
CREATE TABLE commercial.billing_profile (
  tenant_id       uuid        NOT NULL,
  id              uuid        NOT NULL,
  legal_name      text        NOT NULL,
  address_line1   text        NOT NULL,
  address_line2   text        NULL,
  postal_code     text        NOT NULL,
  city            text        NOT NULL,
  country_code    char(2)     NOT NULL,
  vat_id          text        NULL,
  siren           text        NULL,
  po_number       text        NULL,
  billing_email   text        NOT NULL,
  is_business     boolean     NOT NULL DEFAULT true,
  updated_by      text        NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  revision        bigint      NOT NULL DEFAULT 1,
  CONSTRAINT billing_profile_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT billing_profile_one_per_tenant UNIQUE (tenant_id),
  CONSTRAINT billing_profile_country_ck CHECK (country_code ~ '^[A-Z]{2}$'),
  CONSTRAINT billing_profile_vat_ck CHECK (vat_id IS NULL OR vat_id ~ '^[A-Z]{2}[A-Za-z0-9+*]{2,13}$'),
  CONSTRAINT billing_profile_siren_ck CHECK (siren IS NULL OR siren ~ '^[0-9]{9}$'),
  CONSTRAINT billing_profile_email_ck CHECK (billing_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  CONSTRAINT billing_profile_revision_ck CHECK (revision >= 1)
);
COMMENT ON TABLE commercial.billing_profile IS 'LCH-103-S04. Customer billing identity used by the finance operator when issuing invoices outside the product (D-30). A French B2B customer without SIREN is flagged (COMM_BILLING_PROFILE_INCOMPLETE warning), an EU B2B reverse-charge invoice needs vat_id (VIES-checked by the operator).';
COMMENT ON COLUMN commercial.billing_profile.legal_name IS 'x-privacy: CUSTOMER_METADATA.';
COMMENT ON COLUMN commercial.billing_profile.billing_email IS 'x-privacy: PERSONAL (may be a named contact mailbox). Never logged.';
COMMENT ON COLUMN commercial.billing_profile.po_number IS 'x-privacy: CUSTOMER_METADATA.';

-- =============================================================================================
-- Invoice references (LCH-001-S04, S06, S08) - issued invoices are never edited; corrections are credit notes
-- =============================================================================================
CREATE TABLE commercial.invoice_ref (
  tenant_id               uuid          NOT NULL,
  id                      uuid          NOT NULL,
  issuer_entity           text          NOT NULL,
  invoice_number          text          NOT NULL,
  document_kind           text          NOT NULL DEFAULT 'INVOICE',
  credit_note_of          uuid          NULL,
  subscription_id         uuid          NULL,
  issued_on               date          NOT NULL,
  due_on                  date          NOT NULL,
  currency                char(3)       NOT NULL,
  amount_excl_tax         numeric(18,2) NOT NULL,
  tax_amount              numeric(18,2) NOT NULL,
  amount_incl_tax         numeric(18,2) NOT NULL,
  platform_fee_amount     numeric(18,2) NULL,
  band_fee_amount         numeric(18,2) NULL,
  spend_band_assignment_id uuid         NULL,
  vat_treatment           text          NOT NULL,
  customer_vat_id         text          NULL,
  customer_siren          text          NULL,
  service_period_start    date          NOT NULL,
  service_period_end      date          NOT NULL,
  collection_channel      text          NOT NULL,
  stripe_payment_link_id  text          NULL,
  status                  text          NOT NULL DEFAULT 'ISSUED',
  source                  text          NOT NULL,
  import_batch_ref        text          NULL,
  recorded_by             text          NOT NULL,
  created_at              timestamptz   NOT NULL DEFAULT now(),
  updated_at              timestamptz   NOT NULL DEFAULT now(),
  revision                bigint        NOT NULL DEFAULT 1,
  CONSTRAINT invoice_ref_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT invoice_ref_credit_fk FOREIGN KEY (tenant_id, credit_note_of) REFERENCES commercial.invoice_ref (tenant_id, id),
  CONSTRAINT invoice_ref_sub_fk FOREIGN KEY (tenant_id, subscription_id) REFERENCES commercial.subscription (tenant_id, id),
  CONSTRAINT invoice_ref_issuer_ck CHECK (issuer_entity ~ '^[A-Z][A-Z0-9_]{1,31}$'),
  CONSTRAINT invoice_ref_number_ck CHECK (char_length(invoice_number) BETWEEN 1 AND 64),
  CONSTRAINT invoice_ref_kind_ck CHECK (document_kind IN ('INVOICE','CREDIT_NOTE')),
  CONSTRAINT invoice_ref_credit_ck CHECK ((document_kind = 'CREDIT_NOTE') = (credit_note_of IS NOT NULL)),
  CONSTRAINT invoice_ref_dates_ck CHECK (due_on >= issued_on AND service_period_end > service_period_start),
  CONSTRAINT invoice_ref_currency_ck CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT invoice_ref_amounts_ck CHECK (amount_excl_tax >= 0 AND tax_amount >= 0 AND amount_incl_tax = amount_excl_tax + tax_amount),
  CONSTRAINT invoice_ref_split_ck CHECK (platform_fee_amount IS NULL OR band_fee_amount IS NULL OR platform_fee_amount + band_fee_amount = amount_excl_tax),
  CONSTRAINT invoice_ref_vat_ck CHECK (vat_treatment IN ('DOMESTIC_STANDARD','EU_B2B_REVERSE_CHARGE','NON_EU_OUT_OF_SCOPE')),
  CONSTRAINT invoice_ref_reverse_charge_ck CHECK (vat_treatment <> 'EU_B2B_REVERSE_CHARGE' OR (customer_vat_id IS NOT NULL AND tax_amount = 0)),
  CONSTRAINT invoice_ref_out_of_scope_ck CHECK (vat_treatment <> 'NON_EU_OUT_OF_SCOPE' OR tax_amount = 0),
  CONSTRAINT invoice_ref_vat_id_fmt_ck CHECK (customer_vat_id IS NULL OR customer_vat_id ~ '^[A-Z]{2}[A-Za-z0-9+*]{2,13}$'),
  CONSTRAINT invoice_ref_siren_ck CHECK (customer_siren IS NULL OR customer_siren ~ '^[0-9]{9}$'),
  CONSTRAINT invoice_ref_channel_ck CHECK (collection_channel IN ('BANK_TRANSFER','STRIPE_PAYMENT_LINK')),
  CONSTRAINT invoice_ref_stripe_ck CHECK ((collection_channel = 'STRIPE_PAYMENT_LINK') = (stripe_payment_link_id IS NOT NULL)),
  CONSTRAINT invoice_ref_stripe_fmt_ck CHECK (stripe_payment_link_id IS NULL OR stripe_payment_link_id ~ '^plink_[A-Za-z0-9]{6,64}$'),
  CONSTRAINT invoice_ref_status_ck CHECK (status IN ('ISSUED','CANCELLED_BY_CREDIT_NOTE')),
  CONSTRAINT invoice_ref_credit_status_ck CHECK (document_kind = 'INVOICE' OR status = 'ISSUED'),
  CONSTRAINT invoice_ref_source_ck CHECK (source IN ('MANUAL','CSV_IMPORT')),
  CONSTRAINT invoice_ref_import_ck CHECK ((source = 'CSV_IMPORT') = (import_batch_ref IS NOT NULL)),
  CONSTRAINT invoice_ref_actor_ck CHECK (recorded_by ~ '^operator:[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT invoice_ref_revision_ck CHECK (revision >= 1)
);
-- Designed global uniqueness (SEC Appendix E.4 exception): an issuer's invoice numbering series is global across tenants.
-- A duplicate answers 409 COMM_INVOICE_NUMBER_DUPLICATE without revealing the other tenant.
CREATE UNIQUE INDEX invoice_ref_issuer_number_unique ON commercial.invoice_ref (issuer_entity, invoice_number);
CREATE INDEX invoice_ref_tenant_idx ON commercial.invoice_ref (tenant_id, subscription_id, due_on);
CREATE INDEX invoice_ref_credit_idx ON commercial.invoice_ref (tenant_id, credit_note_of) WHERE credit_note_of IS NOT NULL;

CREATE OR REPLACE FUNCTION commercial.guard_invoice_ref_update() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'commercial.invoice_ref: DELETE is forbidden (issued documents are corrected by credit notes)' USING ERRCODE = '42501';
  END IF;
  IF (NEW.tenant_id, NEW.id, NEW.issuer_entity, NEW.invoice_number, NEW.document_kind, NEW.credit_note_of, NEW.subscription_id,
      NEW.issued_on, NEW.due_on, NEW.currency, NEW.amount_excl_tax, NEW.tax_amount, NEW.amount_incl_tax, NEW.vat_treatment,
      NEW.customer_vat_id, NEW.customer_siren, NEW.service_period_start, NEW.service_period_end, NEW.collection_channel,
      NEW.stripe_payment_link_id, NEW.source, NEW.recorded_by, NEW.created_at)
     IS DISTINCT FROM
     (OLD.tenant_id, OLD.id, OLD.issuer_entity, OLD.invoice_number, OLD.document_kind, OLD.credit_note_of, OLD.subscription_id,
      OLD.issued_on, OLD.due_on, OLD.currency, OLD.amount_excl_tax, OLD.tax_amount, OLD.amount_incl_tax, OLD.vat_treatment,
      OLD.customer_vat_id, OLD.customer_siren, OLD.service_period_start, OLD.service_period_end, OLD.collection_channel,
      OLD.stripe_payment_link_id, OLD.source, OLD.recorded_by, OLD.created_at) THEN
    RAISE EXCEPTION 'commercial.invoice_ref: issued invoice % is immutable (only status may change)', OLD.invoice_number USING ERRCODE = '42501';
  END IF;
  IF NOT (OLD.status = 'ISSUED' AND NEW.status IN ('ISSUED','CANCELLED_BY_CREDIT_NOTE')) THEN
    RAISE EXCEPTION 'commercial.invoice_ref: status % -> % is not allowed', OLD.status, NEW.status USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER invoice_ref_immutable BEFORE UPDATE OR DELETE ON commercial.invoice_ref
  FOR EACH ROW EXECUTE FUNCTION commercial.guard_invoice_ref_update();
COMMENT ON TABLE commercial.invoice_ref IS 'LCH-001-S04/S06/S08 (D-30, D-36; RECONCILIATION U-25: distinct from finance.billing_references, never joined). Reference of an invoice or credit note issued by the French entity outside the product (accounting tool or Stripe payment link). Bridge validates uniqueness of (issuer_entity, invoice_number) only; numbering, mandatory mentions, VAT and e-invoicing duties belong to the issuing tool (docs/commercial/vat-and-invoicing.md). Amount due of an invoice = amount_incl_tax - sum(credit notes referencing it); a credit note equal to the full amount sets the invoice CANCELLED_BY_CREDIT_NOTE.';
COMMENT ON COLUMN commercial.invoice_ref.customer_vat_id IS 'x-privacy: CUSTOMER_METADATA. Required for EU_B2B_REVERSE_CHARGE (Art. 196 Directive 2006/112/EC mention on the invoice).';
COMMENT ON COLUMN commercial.invoice_ref.customer_siren IS 'x-privacy: CUSTOMER_METADATA. French B2B customers (mandatory invoice mention since 2026-09-01; accountant confirmation).';
COMMENT ON COLUMN commercial.invoice_ref.platform_fee_amount IS 'x-privacy: INTERNAL. Optional split used by OPS-009-S08 revenue estimates (platform fee vs managed-spend band fee, D-17).';

-- =============================================================================================
-- Payment evidence (LCH-001-S04, S07, S08) - idempotent by (channel, external_ref); VERIFIED needs a second operator
-- =============================================================================================
CREATE TABLE commercial.payment_event (
  tenant_id        uuid          NOT NULL,
  id               uuid          NOT NULL,
  event_kind       text          NOT NULL DEFAULT 'PAYMENT',
  channel          text          NOT NULL,
  external_ref     text          NOT NULL,
  amount           numeric(18,2) NOT NULL,
  currency         char(3)       NOT NULL,
  value_date       date          NOT NULL,
  status           text          NOT NULL DEFAULT 'RECORDED',
  reversal_of      uuid          NULL,
  recorded_by      text          NOT NULL,
  recorded_at      timestamptz   NOT NULL DEFAULT now(),
  verified_by      text          NULL,
  verified_at      timestamptz   NULL,
  evidence_ref     text          NULL,
  created_at       timestamptz   NOT NULL DEFAULT now(),
  updated_at       timestamptz   NOT NULL DEFAULT now(),
  revision         bigint        NOT NULL DEFAULT 1,
  CONSTRAINT payment_event_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT payment_event_reversal_fk FOREIGN KEY (tenant_id, reversal_of) REFERENCES commercial.payment_event (tenant_id, id),
  CONSTRAINT payment_event_kind_ck CHECK (event_kind IN ('PAYMENT','REVERSAL')),
  CONSTRAINT payment_event_reversal_ck CHECK ((event_kind = 'REVERSAL') = (reversal_of IS NOT NULL)),
  CONSTRAINT payment_event_channel_ck CHECK (channel IN ('BANK_TRANSFER','STRIPE')),
  CONSTRAINT payment_event_ref_ck CHECK (char_length(external_ref) BETWEEN 4 AND 128),
  CONSTRAINT payment_event_stripe_ref_ck CHECK (channel <> 'STRIPE' OR external_ref ~ '^(ch|py|pi|cs|plink|re|dp)_[A-Za-z0-9]{6,128}$'),
  CONSTRAINT payment_event_no_pan_ck CHECK (external_ref !~ '(^|[^0-9])[0-9]{13,19}([^0-9]|$)'),
  CONSTRAINT payment_event_amount_ck CHECK (amount > 0),
  CONSTRAINT payment_event_currency_ck CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT payment_event_status_ck CHECK (status IN ('RECORDED','VERIFIED','REVERSED')),
  CONSTRAINT payment_event_reversal_status_ck CHECK (event_kind = 'PAYMENT' OR status IN ('RECORDED','VERIFIED')),
  CONSTRAINT payment_event_actor_ck CHECK (recorded_by ~ '^operator:[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT payment_event_four_eyes_ck CHECK (verified_by IS NULL OR (verified_by <> recorded_by AND verified_by ~ '^operator:[A-Za-z0-9._:-]{1,128}$')),
  CONSTRAINT payment_event_verified_ck CHECK ((status <> 'RECORDED' OR verified_by IS NULL) AND (status <> 'VERIFIED' OR verified_by IS NOT NULL)
      AND ((verified_by IS NULL) = (verified_at IS NULL))),
  CONSTRAINT payment_event_revision_ck CHECK (revision >= 1)
);
-- Designed global uniqueness: one external reference per channel (duplicate entry never activates twice, LCH-001-S07).
CREATE UNIQUE INDEX payment_event_channel_ref_unique ON commercial.payment_event (channel, external_ref);
CREATE UNIQUE INDEX payment_event_one_reversal ON commercial.payment_event (tenant_id, reversal_of) WHERE reversal_of IS NOT NULL;
CREATE INDEX payment_event_tenant_idx ON commercial.payment_event (tenant_id, status, value_date);
COMMENT ON TABLE commercial.payment_event IS 'LCH-001-S04/S07/S08 (D-30, G-LCH-10). Payment evidence entered by an authorized finance operator: bank-transfer reference or Stripe charge / payment-intent / payment-link id. No card data (a 13-19 digit run is rejected), no Stripe API integration in R1. VERIFIED requires verified_by <> recorded_by for every payment. A reversal is a new REVERSAL row referencing the payment, itself verified by a second operator; when the REVERSAL becomes VERIFIED the original payment becomes REVERSED in the same transaction and the subscription state is recomputed. An unverified (RECORDED) payment that is wrong is voided the same way.';
COMMENT ON COLUMN commercial.payment_event.external_ref IS 'x-privacy: INTERNAL. Bank transfer reference or Stripe object id; never a card number or IBAN.';
COMMENT ON COLUMN commercial.payment_event.evidence_ref IS 'x-privacy: INTERNAL. Evidence bucket key of the remittance/bank statement extract (redacted) used for verification.';

CREATE TABLE commercial.payment_allocation (
  tenant_id          uuid          NOT NULL,
  id                 uuid          NOT NULL,
  payment_event_id   uuid          NOT NULL,
  invoice_ref_id     uuid          NOT NULL,
  amount             numeric(18,2) NOT NULL,
  created_at         timestamptz   NOT NULL DEFAULT now(),
  updated_at         timestamptz   NOT NULL DEFAULT now(),
  revision           bigint        NOT NULL DEFAULT 1,
  CONSTRAINT payment_allocation_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT payment_allocation_unique UNIQUE (tenant_id, payment_event_id, invoice_ref_id),
  CONSTRAINT payment_allocation_payment_fk FOREIGN KEY (tenant_id, payment_event_id) REFERENCES commercial.payment_event (tenant_id, id),
  CONSTRAINT payment_allocation_invoice_fk FOREIGN KEY (tenant_id, invoice_ref_id) REFERENCES commercial.invoice_ref (tenant_id, id),
  CONSTRAINT payment_allocation_amount_ck CHECK (amount > 0),
  CONSTRAINT payment_allocation_append_only_ck CHECK (revision = 1)
);
CREATE TRIGGER payment_allocation_append_only BEFORE UPDATE OR DELETE ON commercial.payment_allocation
  FOR EACH ROW EXECUTE FUNCTION commercial.forbid_mutation();
COMMENT ON TABLE commercial.payment_allocation IS 'LCH-001-S07. Allocation of a payment to invoices (partial allowed). Service invariants (checked in the recording transaction, COMM_PAYMENT_ALLOCATION_EXCEEDS): sum(allocations of a payment) <= payment amount; sum(VERIFIED, non-REVERSED allocations of an invoice) <= invoice amount due; payment currency = invoice currency. An invoice is settled when VERIFIED allocations cover its amount due.';

-- =============================================================================================
-- Managed-spend band assignment (LCH-105) - insert-only revisions
-- =============================================================================================
CREATE TABLE commercial.spend_band_assignment (
  tenant_id                uuid        NOT NULL,
  id                       uuid        NOT NULL,
  period                   char(7)     NOT NULL,
  assignment_revision      integer     NOT NULL,
  supersedes               uuid        NULL,
  plan_id                  uuid        NOT NULL,
  plan_version             integer     NOT NULL,
  band_id                  text        NOT NULL,
  band_rank                smallint    NOT NULL,
  source                   text        NOT NULL,
  source_ref               text        NOT NULL,
  excluded_trial_accounts  integer     NOT NULL DEFAULT 0,
  flag                     text        NULL,
  flag_acknowledged_by     text        NULL,
  flag_acknowledged_at     timestamptz NULL,
  run_id                   uuid        NOT NULL,
  computed_at              timestamptz NOT NULL,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  revision                 bigint      NOT NULL DEFAULT 1,
  CONSTRAINT spend_band_assignment_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT spend_band_assignment_source_unique UNIQUE (tenant_id, period, source_ref),
  CONSTRAINT spend_band_assignment_rev_unique UNIQUE (tenant_id, period, assignment_revision),
  CONSTRAINT spend_band_assignment_supersedes_fk FOREIGN KEY (tenant_id, supersedes) REFERENCES commercial.spend_band_assignment (tenant_id, id),
  CONSTRAINT spend_band_assignment_band_fk FOREIGN KEY (plan_id, plan_version, band_id) REFERENCES commercial.plan_band (plan_id, plan_version, band_id),
  CONSTRAINT spend_band_assignment_period_ck CHECK (period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  CONSTRAINT spend_band_assignment_rev_ck CHECK (assignment_revision >= 1 AND ((assignment_revision = 1) = (supersedes IS NULL))),
  CONSTRAINT spend_band_assignment_source_ck CHECK (source IN ('CLOSED_STATEMENT','MONTH_STABLE_LEDGER')),
  CONSTRAINT spend_band_assignment_flag_ck CHECK (flag IS NULL OR flag = 'BAND_CHANGED_AFTER_INVOICE'),
  CONSTRAINT spend_band_assignment_ack_ck CHECK ((flag_acknowledged_by IS NULL) = (flag_acknowledged_at IS NULL) AND (flag IS NOT NULL OR flag_acknowledged_by IS NULL)),
  CONSTRAINT spend_band_assignment_trial_ck CHECK (excluded_trial_accounts >= 0),
  CONSTRAINT spend_band_assignment_revision_ck CHECK (revision >= 1)
);
CREATE INDEX spend_band_assignment_period_idx ON commercial.spend_band_assignment (tenant_id, period, assignment_revision DESC);
CREATE INDEX spend_band_assignment_flag_idx ON commercial.spend_band_assignment (flag) WHERE flag IS NOT NULL AND flag_acknowledged_at IS NULL;
COMMENT ON TABLE commercial.spend_band_assignment IS 'LCH-105-S01..S04 (D-17, D-13, D-35). Monthly band assignment from stable ledger totals only: CLOSED_STATEMENT (FIN-010 closed period) or MONTH_STABLE_LEDGER (FIN-104 period_stability = STABLE, read through the broker JOB class); never PROVISIONAL data. Deterministic key (tenant_id, period, source_ref): an identical re-run inserts nothing. A restated month inserts assignment_revision + 1 with supersedes; if an invoice reference exists for the period and the band changed, flag BAND_CHANGED_AFTER_INVOICE is raised for the finance operator (no automatic invoice change, D-30). Only flag_acknowledged_* may be updated.';
COMMENT ON COLUMN commercial.spend_band_assignment.source_ref IS 'x-privacy: INTERNAL. statement:<statement_id>@<revision> or publication:<pub_seq> - the exact pinned ledger state read.';

CREATE TABLE commercial.spend_band_total (
  tenant_id        uuid           NOT NULL,
  id               uuid           NOT NULL,
  assignment_id    uuid           NOT NULL,
  currency         char(3)        NOT NULL,
  managed_spend    numeric(38,12) NOT NULL,
  band_id          text           NOT NULL,
  band_rank        smallint       NOT NULL,
  created_at       timestamptz    NOT NULL DEFAULT now(),
  updated_at       timestamptz    NOT NULL DEFAULT now(),
  revision         bigint         NOT NULL DEFAULT 1,
  CONSTRAINT spend_band_total_pk PRIMARY KEY (tenant_id, id),
  CONSTRAINT spend_band_total_unique UNIQUE (tenant_id, assignment_id, currency),
  CONSTRAINT spend_band_total_assignment_fk FOREIGN KEY (tenant_id, assignment_id) REFERENCES commercial.spend_band_assignment (tenant_id, id),
  CONSTRAINT spend_band_total_currency_ck CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT spend_band_total_revision_ck CHECK (revision = 1)
);
CREATE TRIGGER spend_band_total_append_only BEFORE UPDATE OR DELETE ON commercial.spend_band_total
  FOR EACH ROW EXECUTE FUNCTION commercial.forbid_mutation();
COMMENT ON TABLE commercial.spend_band_total IS 'LCH-105-S01. Managed spend per spend currency for one assignment (backlog per_currency_totals JSONB, normalized) and the band reached in that currency''s own threshold table. The assignment band = the highest band_rank across currencies (no FX). Aggregate totals only (bounded rows per tenant-month); no analytical fact mirror.';
COMMENT ON COLUMN commercial.spend_band_total.managed_spend IS 'x-privacy: INTERNAL. Published ledger total at billed rates incl. signed adjustments, excluding TRIAL_ACCOUNT connections (D-35); exact NUMBER(38,12) decimal (may be negative after credits).';

-- =============================================================================================
-- RLS (tenant tables) and grants. Tenants READ their own commercial records through the API (bridge_api);
-- WRITES happen only on the ops plane (bridge_ops_api, finance_operator) or by commercial workers (bridge_worker).
-- =============================================================================================
ALTER TABLE commercial.tenant_entitlement    ENABLE ROW LEVEL SECURITY;
ALTER TABLE commercial.tenant_entitlement    FORCE ROW LEVEL SECURITY;
ALTER TABLE commercial.entitlement_override  ENABLE ROW LEVEL SECURITY;
ALTER TABLE commercial.entitlement_override  FORCE ROW LEVEL SECURITY;
ALTER TABLE commercial.subscription          ENABLE ROW LEVEL SECURITY;
ALTER TABLE commercial.subscription          FORCE ROW LEVEL SECURITY;
ALTER TABLE commercial.subscription_event    ENABLE ROW LEVEL SECURITY;
ALTER TABLE commercial.subscription_event    FORCE ROW LEVEL SECURITY;
ALTER TABLE commercial.change_request        ENABLE ROW LEVEL SECURITY;
ALTER TABLE commercial.change_request        FORCE ROW LEVEL SECURITY;
ALTER TABLE commercial.billing_profile       ENABLE ROW LEVEL SECURITY;
ALTER TABLE commercial.billing_profile       FORCE ROW LEVEL SECURITY;
ALTER TABLE commercial.invoice_ref           ENABLE ROW LEVEL SECURITY;
ALTER TABLE commercial.invoice_ref           FORCE ROW LEVEL SECURITY;
ALTER TABLE commercial.payment_event         ENABLE ROW LEVEL SECURITY;
ALTER TABLE commercial.payment_event         FORCE ROW LEVEL SECURITY;
ALTER TABLE commercial.payment_allocation    ENABLE ROW LEVEL SECURITY;
ALTER TABLE commercial.payment_allocation    FORCE ROW LEVEL SECURITY;
ALTER TABLE commercial.spend_band_assignment ENABLE ROW LEVEL SECURITY;
ALTER TABLE commercial.spend_band_assignment FORCE ROW LEVEL SECURITY;
ALTER TABLE commercial.spend_band_total      ENABLE ROW LEVEL SECURITY;
ALTER TABLE commercial.spend_band_total      FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON commercial.tenant_entitlement
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON commercial.entitlement_override
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON commercial.subscription
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON commercial.subscription_event
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON commercial.change_request
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON commercial.billing_profile
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON commercial.invoice_ref
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON commercial.payment_event
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON commercial.payment_allocation
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON commercial.spend_band_assignment
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
CREATE POLICY tenant_isolation ON commercial.spend_band_total
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
-- Allowlisted cross-tenant readers: the daily dunning job (PAST_DUE) and the monthly spend-metering job list candidates
-- across tenants, then act per tenant inside a tenant transaction.
CREATE POLICY subscription_scheduler_read ON commercial.subscription FOR SELECT TO bridge_retention USING (true);
CREATE POLICY invoice_ref_scheduler_read ON commercial.invoice_ref FOR SELECT TO bridge_retention USING (true);

REVOKE ALL ON ALL TABLES IN SCHEMA commercial FROM PUBLIC;
GRANT USAGE ON SCHEMA commercial TO bridge_api, bridge_worker, bridge_ops_api, bridge_retention;
-- global catalog
GRANT SELECT ON commercial.plan, commercial.plan_band, commercial.plan_band_threshold TO bridge_api, bridge_worker, bridge_ops_api;
GRANT INSERT, UPDATE ON commercial.plan TO bridge_ops_api;
GRANT INSERT ON commercial.plan_band, commercial.plan_band_threshold TO bridge_ops_api;
-- tenant reads (API) - never writes except the Owner's plan-change request and billing profile
GRANT SELECT ON commercial.tenant_entitlement, commercial.entitlement_override, commercial.subscription, commercial.subscription_event,
  commercial.invoice_ref, commercial.payment_event, commercial.payment_allocation, commercial.spend_band_assignment,
  commercial.spend_band_total, commercial.billing_profile, commercial.change_request TO bridge_api;
GRANT INSERT ON commercial.change_request TO bridge_api;
GRANT INSERT, UPDATE ON commercial.billing_profile TO bridge_api;
-- finance operator path (ops plane)
GRANT SELECT, INSERT, UPDATE ON commercial.tenant_entitlement, commercial.subscription, commercial.change_request,
  commercial.billing_profile, commercial.invoice_ref, commercial.payment_event TO bridge_ops_api;
GRANT SELECT, INSERT ON commercial.entitlement_override, commercial.subscription_event, commercial.payment_allocation TO bridge_ops_api;
GRANT SELECT ON commercial.spend_band_assignment, commercial.spend_band_total TO bridge_ops_api;
GRANT UPDATE (flag_acknowledged_by, flag_acknowledged_at, updated_at, revision) ON commercial.spend_band_assignment TO bridge_ops_api;
-- workers (dunning, subscription recompute, spend metering, entitlement usage counters)
GRANT SELECT, UPDATE ON commercial.subscription TO bridge_worker;
GRANT SELECT, INSERT ON commercial.subscription_event TO bridge_worker;
GRANT SELECT ON commercial.tenant_entitlement, commercial.entitlement_override, commercial.invoice_ref, commercial.payment_event,
  commercial.payment_allocation, commercial.change_request TO bridge_worker;
GRANT SELECT, INSERT ON commercial.spend_band_assignment, commercial.spend_band_total TO bridge_worker;
GRANT SELECT ON commercial.subscription, commercial.invoice_ref TO bridge_retention;

-- contract=snowflake-internal-cost version=1 status=DRAFT owner_task=OPS-009 decisions=D-02,D-06,D-08,D-11,D-17 last_changed=2026-09-28
-- Migration block: K9 V0800-V0899 (database BRIDGE_INTERNAL_COST, CONVENTIONS §11). Artifact row "DDL internal_cost.*" (OPS-009-S01).
-- Separate database with NO customer, serving, transform or tenant grants: only the internal FinOps reader and the cost loader.
-- The database itself is created by K1's baseline (V0001-V0099); this migration creates schema INTERNAL_COST and its tables.
-- Allocation rules (normative, G-OPS-12 / OPS-009-S05..S06): serving compute exact by tenant WIF serving user (D-02) + serving idle pro rata;
-- transform compute per (build, model) split by OPS_INTERNAL.BUILD_MODEL_TENANT_ROWS.rows_written; Snowpipe by manifest bytes per tenant
-- (0.0037 credits/GB); storage by tenant row share (labelled estimate, incl. 365 days of query-level facts, D-11); AWS by CUR `component`
-- tag, ECS task-seconds per tenant, NAT extracted bytes; shared services by declared drivers with an explicit unallocated residual.
-- Conservation (every provider, month, currency): SUM(tenant_platform_cost.amount) + SUM(unallocated_cost.amount) = SUM(cost_source_line.amount)
-- exactly; cents by sign-normalized largest remainder only at reporting boundaries (FIN-106). Customer-side extraction credits (D-08) are
-- customer_borne_cost, never COGS. Snowflake billed through AWS Marketplace appears in CUR and is excluded from the AWS side (OPS-009-S14).
-- Fixtures: gross margin revenue 1000.00, COGS 100.00 + 120.00 + 80.00 = 300.00 -> (1000 - 300) / 1000 = 0.70; revenue 0 -> margin NULL.
--           control totals: invoice 1000.00 vs lines 999.40 -> delta = 999.40 - 1000.00 = -0.60 (shown, never plugged).

create schema if not exists bridge_internal_cost.internal_cost with managed access
  comment = 'Bridge unit economics (OPS-009). Internal only: no customer-facing grants.';

create table if not exists bridge_internal_cost.internal_cost.cost_source_line (
  line_id              varchar(128)     not null comment 'Provider line identity (CUR line_item id + bill period, or Snowflake view natural key hash).',
  provider             varchar(16)      not null comment 'AWS | SNOWFLAKE | VENDOR.',
  provider_account     varchar(64)      not null comment 'AWS account id or Snowflake account locator of Bridge''s own estate. x-privacy: INTERNAL',
  environment          varchar(16)      not null comment 'production | staging | dev | canary | shared (COGS scope per docs/operations/cogs-policy.md).',
  service              varchar(128)     not null comment 'Provider service/product code.',
  component            varchar(64)      not null comment 'Bridge component from the INF-105 `component` tag or central warehouse/pipe mapping.',
  usage_start          timestamp_ntz(9) not null comment 'UTC, half-open [usage_start, usage_end).',
  usage_end            timestamp_ntz(9) not null comment 'UTC.',
  amount               number(38,12)    not null comment 'Signed amount in currency (credits converted at the billed rate for SNOWFLAKE).',
  currency             varchar(3)       not null comment 'ISO 4217.',
  is_marketplace_snowflake boolean      not null default false comment 'CUR line for Snowflake billed via AWS Marketplace; excluded from AWS totals (counted once on the SNOWFLAKE side).',
  month_state          varchar(12)      not null comment 'PROVISIONAL | FINAL (FINAL after month end + 5 days and CUR finalization).',
  source_ref           varchar(512)     not null comment 'Export object key / view name + query id.',
  source_version       varchar(64)      not null comment 'CUR schema version or Snowflake source contract version.',
  loaded_at            timestamp_ntz(9) not null default sysdate() comment 'UTC.',
  constraint cost_source_line_pk primary key (provider, line_id, source_version) rely
)
cluster by (usage_start)
comment = 'OPS-009-S02/S03. Provider cost lines: AWS CUR 2.0 Data Export (INF-105-S05) and Bridge''s own Snowflake usage (METERING_DAILY_HISTORY, WAREHOUSE_METERING_HISTORY, QUERY_ATTRIBUTION_HISTORY, PIPE_USAGE_HISTORY, TABLE_STORAGE_METRICS, USAGE_IN_CURRENCY_DAILY).';

create table if not exists bridge_internal_cost.internal_cost.control_totals (
  period_month         date             not null comment 'First day of the UTC month.',
  provider             varchar(16)      not null comment 'AWS | SNOWFLAKE | VENDOR.',
  currency             varchar(3)       not null comment 'ISO 4217.',
  invoice_total        number(38,12)    comment 'Provider invoice total (null until the invoice is available).',
  lines_total          number(38,12)    not null comment 'SUM(cost_source_line.amount) for the provider/month/currency.',
  delta                number(38,12)    comment 'lines_total - invoice_total (signed; never plugged).',
  invoice_ref          varchar(256)     comment 'Provider invoice reference. x-privacy: INTERNAL',
  computed_at          timestamp_ntz(9) not null default sysdate() comment 'UTC.',
  constraint control_totals_pk primary key (period_month, provider, currency) rely
)
comment = 'OPS-009-S04. Provider control totals with signed delta; fixture 999.40 - 1000.00 = -0.60.';

create table if not exists bridge_internal_cost.internal_cost.allocation_method (
  allocation_version   varchar(32)      not null comment 'Semantic version of the allocation method set.',
  component            varchar(64)      not null comment 'Cost component.',
  driver               varchar(32)      not null comment 'Driver used for the component (see cost_driver_fact.driver).',
  method               varchar(32)      not null comment 'DIRECT | PRO_RATA_DRIVER | ESTIMATE_ROW_SHARE | UNALLOCATED.',
  is_estimate          boolean          not null comment 'true when the allocation is a labelled estimate (storage row share).',
  effective_from       date             not null comment 'First month the method applies.',
  approved_by          varchar(128)     not null comment 'Finance approver. x-privacy: INTERNAL',
  constraint allocation_method_pk primary key (allocation_version, component) rely
)
comment = 'OPS-009-S06. Versioned allocation method per component; every allocated row records its allocation_version.';

create table if not exists bridge_internal_cost.internal_cost.cost_driver_fact (
  period_month         date             not null comment 'First day of the UTC month.',
  usage_date           date             not null comment 'UTC date of the driver observation.',
  driver               varchar(32)      not null comment 'SERVING_CREDITS | TRANSFORM_ROWS_WRITTEN | SNOWPIPE_BYTES | STORAGE_ROW_SHARE | ECS_TASK_SECONDS | NAT_EXTRACTED_BYTES | API_REQUESTS | ACTIVE_USERS.',
  component            varchar(64)      not null comment 'Cost component the driver allocates.',
  tenant_id            varchar(36)      not null comment 'Tenant UUID, or UNALLOCATED when the driver has no tenant (never NULL). x-privacy: INTERNAL',
  quantity             number(38,12)    not null comment 'Driver quantity (>= 0).',
  unit                 varchar(16)      not null comment 'CREDIT | ROW | BYTE | SECOND | REQUEST | USER.',
  source_ref           varchar(512)     not null comment 'Source query / table (e.g. bridge.ops_internal.build_model_tenant_rows).',
  loaded_at            timestamp_ntz(9) not null default sysdate() comment 'UTC.',
  constraint cost_driver_fact_pk primary key (usage_date, driver, component, tenant_id) rely
)
cluster by (period_month)
comment = 'OPS-009-S05. Driver facts per tenant; every driver has a source query and unit; tenant UNALLOCATED is explicit.';

create table if not exists bridge_internal_cost.internal_cost.tenant_platform_cost (
  period_month         date             not null comment 'First day of the UTC month.',
  tenant_id            varchar(36)      not null comment 'Tenant UUID. x-privacy: INTERNAL',
  component            varchar(64)      not null comment 'Cost component.',
  amount               number(38,12)    not null comment 'Allocated cost (exact decimal).',
  currency             varchar(3)       not null comment 'ISO 4217 (never summed across currencies).',
  allocation_version   varchar(32)      not null comment 'allocation_method.allocation_version.',
  method               varchar(32)      not null comment 'DIRECT | PRO_RATA_DRIVER | ESTIMATE_ROW_SHARE.',
  is_estimate          boolean          not null comment 'Labelled estimate flag.',
  month_state          varchar(12)      not null comment 'PROVISIONAL until month end + 5 days and CUR finalization, then FINAL (OPS-009-S07).',
  computed_at          timestamp_ntz(9) not null default sysdate() comment 'UTC.',
  constraint tenant_platform_cost_pk primary key (period_month, tenant_id, component, currency, allocation_version) rely
)
comment = 'OPS-009-S06. Bridge COGS per tenant and component (production + canary + production share of observability; staging/dev are R&D and never appear here).';

create table if not exists bridge_internal_cost.internal_cost.unallocated_cost (
  period_month         date             not null comment 'First day of the UTC month.',
  component            varchar(64)      not null comment 'Cost component.',
  reason               varchar(32)      not null comment 'UNALLOCATED_IDLE | NO_DRIVER | SHARED_RESIDUAL | ROUNDING_RESIDUAL.',
  amount               number(38,12)    not null comment 'Unallocated residual (signed).',
  currency             varchar(3)       not null comment 'ISO 4217.',
  allocation_version   varchar(32)      not null comment 'allocation_method.allocation_version.',
  computed_at          timestamp_ntz(9) not null default sysdate() comment 'UTC.',
  constraint unallocated_cost_pk primary key (period_month, component, reason, currency, allocation_version) rely
)
comment = 'OPS-009-S06. Explicit unallocated bucket: allocated + unallocated = provider total exactly.';

create table if not exists bridge_internal_cost.internal_cost.customer_borne_cost (
  period_month         date             not null comment 'First day of the UTC month.',
  tenant_id            varchar(36)      not null comment 'Tenant UUID. x-privacy: INTERNAL',
  account_id           varchar(36)      not null comment 'Customer Snowflake account UUID (Bridge id).',
  credits              number(38,12)    not null comment 'Customer-side Bridge overhead credits (BRIDGE_FINOPS_WH / QUERY_TAG bridge_finops:*) from the customer''s own ledger.',
  source_publication   number(38,0)     not null comment 'pub_seq of the tenant publication read.',
  computed_at          timestamp_ntz(9) not null default sysdate() comment 'UTC.',
  constraint customer_borne_cost_pk primary key (period_month, tenant_id, account_id) rely
)
comment = 'OPS-009-S11 (D-08). Disclosed customer cost, excluded from COGS (fixture: 12 credits of overhead leave COGS unchanged).';

create table if not exists bridge_internal_cost.internal_cost.revenue_estimate (
  period_month         date             not null comment 'First day of the UTC month.',
  tenant_id            varchar(36)      not null comment 'Tenant UUID. x-privacy: INTERNAL',
  invoice_ref_id       varchar(36)      not null comment 'commercial.invoice_ref id (LCH-001-S04) read through the internal export.',
  revenue_kind         varchar(16)      not null comment 'PLATFORM_FEE | BAND_FEE | UNSPLIT (D-17).',
  amount               number(38,12)    not null comment 'Straight-line share of the invoice excl. tax recognized in the month.',
  currency             varchar(3)       not null comment 'ISO 4217.',
  method               varchar(32)      not null comment 'STRAIGHT_LINE_SERVICE_PERIOD.',
  label                varchar(64)      not null default 'estimate - finance approval required' comment 'Mandatory label (operations.md).',
  computed_at          timestamp_ntz(9) not null default sysdate() comment 'UTC.',
  constraint revenue_estimate_pk primary key (period_month, tenant_id, invoice_ref_id, revenue_kind) rely
)
comment = 'OPS-009-S08. Revenue estimate from invoice references: annual invoice 12,000.00 over 12 months -> 1,000.00 per month.';

create table if not exists bridge_internal_cost.internal_cost.gross_margin (
  period_month         date             not null comment 'First day of the UTC month.',
  tenant_id            varchar(36)      not null comment 'Tenant UUID, or PLATFORM for the platform total. x-privacy: INTERNAL',
  currency             varchar(3)       not null comment 'ISO 4217.',
  revenue              number(38,12)    not null comment 'SUM(revenue_estimate.amount).',
  cogs                 number(38,12)    not null comment 'SUM(tenant_platform_cost.amount) (+ allocated support staff cost entered by finance).',
  margin_ratio         number(38,12)    comment '(revenue - cogs) / revenue; NULL when revenue = 0.',
  month_state          varchar(12)      not null comment 'PROVISIONAL | FINAL.',
  computed_at          timestamp_ntz(9) not null default sysdate() comment 'UTC.',
  constraint gross_margin_pk primary key (period_month, tenant_id, currency) rely
)
comment = 'OPS-009-S09. Fixture: revenue 1000, COGS 300 -> 0.700000000000; revenue 0 -> NULL.';

-- Grants: only the internal FinOps reader and the cost loader (OPS-009-S01 oracle: SHOW GRANTS ON DATABASE lists only these two roles
-- besides the owner). Future grants keep new tables private.
grant usage on schema bridge_internal_cost.internal_cost to role bridge_finops_internal;
grant usage on schema bridge_internal_cost.internal_cost to role bridge_cost_loader;
grant select on all tables in schema bridge_internal_cost.internal_cost to role bridge_finops_internal;
grant select, insert, delete on all tables in schema bridge_internal_cost.internal_cost to role bridge_cost_loader;
grant select on future tables in schema bridge_internal_cost.internal_cost to role bridge_finops_internal;
grant select, insert, delete on future tables in schema bridge_internal_cost.internal_cost to role bridge_cost_loader;

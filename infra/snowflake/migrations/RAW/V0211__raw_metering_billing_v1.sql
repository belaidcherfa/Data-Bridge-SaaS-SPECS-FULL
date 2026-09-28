-- contract=snowflake-migration:RAW/V0211__raw_metering_billing_v1.sql version=1 status=DRAFT owner_task=ING-006 decisions=D-03,D-26 last_changed=2026-09-28
-- Metering and billing family (ING-102): typed RAW tables, auto-ingest stages and pipes, one set per source x schema major.
-- Generated content mirrors data/contracts/sources/<source>.v1.yaml exactly (ING-006-S01 generator must reproduce it byte-for-byte).
-- Columns: technical columns (NOT NULL; account_id nullable only for ORGANIZATION scope) + extractor columns + typed projection
-- (key/partition/snapshot-key columns NOT NULL) + LOADER_* metadata columns (NOT NULL), so a schema-mismatched file is skipped
-- whole (ON_ERROR = SKIP_FILE) instead of loading NULL rows (G-ING-03). No unreviewed schema evolution.
-- Placeholders resolved by the INF-104 migration runner from config/environments/<env>.yaml (SnowSQL/Snowflake CLI
-- variable substitution): &{landing_bucket}, &{landing_sns_topic_arn}. Role: bridge_ingest_owner (object owner).
-- TO VERIFY LIVE (ING-006-S08): PATTERN is matched against the path relative to the stage URL; TIMESTAMP_NTZ(9) targets
-- receive UTC wall-clock values from Parquet timestamp[us, tz=UTC] with USE_LOGICAL_TYPE = TRUE.
-- Sources whose projection is TO_VERIFY_LIVE are corrected in this file (never applied) before their first activation;
-- after the first apply any change is a new migration (ADDITIVE: ALTER TABLE ADD COLUMN; BREAKING: new major).
USE ROLE bridge_ingest_owner;
USE SCHEMA bridge.raw;

-- AU_WAREHOUSE_METERING_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_warehouse_metering_history_v1 (
  tenant_id VARCHAR(36) NOT NULL,
  organization_id VARCHAR(36) NOT NULL,
  account_id VARCHAR(36) NOT NULL,
  source_batch_id VARCHAR(36) NOT NULL,
  logical_window_id VARCHAR(36) NOT NULL,
  source_window_start TIMESTAMP_NTZ(9) NOT NULL,
  source_window_end TIMESTAMP_NTZ(9) NOT NULL,
  source_extracted_at TIMESTAMP_NTZ(9) NOT NULL,
  source_schema_version NUMBER(10,0) NOT NULL,
  transport_schema_version VARCHAR(16) NOT NULL,
  privacy_policy_version NUMBER(10,0) NOT NULL,
  row_hash VARCHAR(64) NOT NULL,
  start_time TIMESTAMP_NTZ(9) NOT NULL,
  end_time TIMESTAMP_NTZ(9),
  warehouse_id NUMBER(38,0),
  warehouse_name VARCHAR,
  credits_used NUMBER(38,9),
  credits_used_compute NUMBER(38,9),
  credits_used_cloud_services NUMBER(38,9),
  credits_attributed_compute_queries NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_WAREHOUSE_METERING_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=50ddc733c0141bae9b115653cd1ee0c1e6173d47a6a97fc51b40e0f67bfe9efa retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_warehouse_metering_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_WAREHOUSE_METERING_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_WAREHOUSE_METERING_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_warehouse_metering_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_WAREHOUSE_METERING_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_warehouse_metering_history_v1
  FROM @raw.stg_au_warehouse_metering_history_v1
  FILE_FORMAT = (FORMAT_NAME = 'raw.bridge_parquet_v1')
  MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
  INCLUDE_METADATA = (
    loader_filename = METADATA$FILENAME,
    loader_file_row_number = METADATA$FILE_ROW_NUMBER,
    loader_start_scan_time = METADATA$START_SCAN_TIME,
    loader_file_last_modified = METADATA$FILE_LAST_MODIFIED,
    loader_file_content_key = METADATA$FILE_CONTENT_KEY)
  ON_ERROR = SKIP_FILE
  PATTERN = 'tenant_id=[0-9a-f-]{36}/organization_id=[0-9a-f-]{36}/account_id=([0-9a-f-]{36}|org)/extraction_date=[0-9]{4}-[0-9]{2}-[0-9]{2}/batch_id=[0-9a-f-]{36}/part-[0-9]{5}[.]parquet';

-- AU_METERING_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_metering_history_v1 (
  tenant_id VARCHAR(36) NOT NULL,
  organization_id VARCHAR(36) NOT NULL,
  account_id VARCHAR(36) NOT NULL,
  source_batch_id VARCHAR(36) NOT NULL,
  logical_window_id VARCHAR(36) NOT NULL,
  source_window_start TIMESTAMP_NTZ(9) NOT NULL,
  source_window_end TIMESTAMP_NTZ(9) NOT NULL,
  source_extracted_at TIMESTAMP_NTZ(9) NOT NULL,
  source_schema_version NUMBER(10,0) NOT NULL,
  transport_schema_version VARCHAR(16) NOT NULL,
  privacy_policy_version NUMBER(10,0) NOT NULL,
  row_hash VARCHAR(64) NOT NULL,
  service_type VARCHAR,
  start_time TIMESTAMP_NTZ(9) NOT NULL,
  end_time TIMESTAMP_NTZ(9),
  entity_id NUMBER(38,0),
  entity_type VARCHAR,
  name VARCHAR,
  database_id NUMBER(38,0),
  database_name VARCHAR,
  schema_id NUMBER(38,0),
  schema_name VARCHAR,
  credits_used_compute NUMBER(38,9),
  credits_used_cloud_services NUMBER(38,9),
  credits_used NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_METERING_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=46e6e02e9336bd3c276e6be141f178aa7b5037e35fd3a917d7c6089424f006e0 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_metering_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_METERING_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_METERING_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_metering_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_METERING_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_metering_history_v1
  FROM @raw.stg_au_metering_history_v1
  FILE_FORMAT = (FORMAT_NAME = 'raw.bridge_parquet_v1')
  MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
  INCLUDE_METADATA = (
    loader_filename = METADATA$FILENAME,
    loader_file_row_number = METADATA$FILE_ROW_NUMBER,
    loader_start_scan_time = METADATA$START_SCAN_TIME,
    loader_file_last_modified = METADATA$FILE_LAST_MODIFIED,
    loader_file_content_key = METADATA$FILE_CONTENT_KEY)
  ON_ERROR = SKIP_FILE
  PATTERN = 'tenant_id=[0-9a-f-]{36}/organization_id=[0-9a-f-]{36}/account_id=([0-9a-f-]{36}|org)/extraction_date=[0-9]{4}-[0-9]{2}-[0-9]{2}/batch_id=[0-9a-f-]{36}/part-[0-9]{5}[.]parquet';

-- AU_METERING_DAILY_HISTORY v1.0.0 (COMPLETE_PARTITION, DATE_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_metering_daily_history_v1 (
  tenant_id VARCHAR(36) NOT NULL,
  organization_id VARCHAR(36) NOT NULL,
  account_id VARCHAR(36) NOT NULL,
  source_batch_id VARCHAR(36) NOT NULL,
  logical_window_id VARCHAR(36) NOT NULL,
  source_window_start TIMESTAMP_NTZ(9) NOT NULL,
  source_window_end TIMESTAMP_NTZ(9) NOT NULL,
  source_extracted_at TIMESTAMP_NTZ(9) NOT NULL,
  source_schema_version NUMBER(10,0) NOT NULL,
  transport_schema_version VARCHAR(16) NOT NULL,
  privacy_policy_version NUMBER(10,0) NOT NULL,
  row_hash VARCHAR(64) NOT NULL,
  service_type VARCHAR,
  usage_date DATE NOT NULL,
  credits_used_compute NUMBER(38,9),
  credits_used_cloud_services NUMBER(38,9),
  credits_used NUMBER(38,9),
  credits_adjustment_cloud_services NUMBER(38,9),
  credits_billed NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_METERING_DAILY_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=6d723f22c3e63aa365fc4e0f67716177a78b8cf4e829543e7fa0607d25837492 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_metering_daily_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_METERING_DAILY_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_METERING_DAILY_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_metering_daily_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_METERING_DAILY_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_metering_daily_history_v1
  FROM @raw.stg_au_metering_daily_history_v1
  FILE_FORMAT = (FORMAT_NAME = 'raw.bridge_parquet_v1')
  MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
  INCLUDE_METADATA = (
    loader_filename = METADATA$FILENAME,
    loader_file_row_number = METADATA$FILE_ROW_NUMBER,
    loader_start_scan_time = METADATA$START_SCAN_TIME,
    loader_file_last_modified = METADATA$FILE_LAST_MODIFIED,
    loader_file_content_key = METADATA$FILE_CONTENT_KEY)
  ON_ERROR = SKIP_FILE
  PATTERN = 'tenant_id=[0-9a-f-]{36}/organization_id=[0-9a-f-]{36}/account_id=([0-9a-f-]{36}|org)/extraction_date=[0-9]{4}-[0-9]{2}-[0-9]{2}/batch_id=[0-9a-f-]{36}/part-[0-9]{5}[.]parquet';

-- OU_USAGE_IN_CURRENCY_DAILY v1.0.0 (COMPLETE_PARTITION, DATE_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.ou_usage_in_currency_daily_v1 (
  tenant_id VARCHAR(36) NOT NULL,
  organization_id VARCHAR(36) NOT NULL,
  account_id VARCHAR(36),
  source_batch_id VARCHAR(36) NOT NULL,
  logical_window_id VARCHAR(36) NOT NULL,
  source_window_start TIMESTAMP_NTZ(9) NOT NULL,
  source_window_end TIMESTAMP_NTZ(9) NOT NULL,
  source_extracted_at TIMESTAMP_NTZ(9) NOT NULL,
  source_schema_version NUMBER(10,0) NOT NULL,
  transport_schema_version VARCHAR(16) NOT NULL,
  privacy_policy_version NUMBER(10,0) NOT NULL,
  row_hash VARCHAR(64) NOT NULL,
  organization_name VARCHAR,
  contract_number NUMBER(38,0),
  account_name VARCHAR,
  account_locator VARCHAR,
  region VARCHAR,
  service_level VARCHAR,
  usage_date DATE NOT NULL,
  usage_type VARCHAR,
  currency VARCHAR,
  usage NUMBER(38,9),
  usage_in_currency NUMBER(38,9),
  balance_source VARCHAR,
  billing_type VARCHAR,
  rating_type VARCHAR,
  service_type VARCHAR,
  is_adjustment BOOLEAN,
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=OU_USAGE_IN_CURRENCY_DAILY contract_version=1.0.0 transport=1.0 fingerprint=0e7a36c91c50920b7ae8dc09c5711f45eefca32789ad18d908c373a350a6a5aa retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_ou_usage_in_currency_daily_v1
  URL = 's3://&{landing_bucket}/landing/source=OU_USAGE_IN_CURRENCY_DAILY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for OU_USAGE_IN_CURRENCY_DAILY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_ou_usage_in_currency_daily_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for OU_USAGE_IN_CURRENCY_DAILY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.ou_usage_in_currency_daily_v1
  FROM @raw.stg_ou_usage_in_currency_daily_v1
  FILE_FORMAT = (FORMAT_NAME = 'raw.bridge_parquet_v1')
  MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
  INCLUDE_METADATA = (
    loader_filename = METADATA$FILENAME,
    loader_file_row_number = METADATA$FILE_ROW_NUMBER,
    loader_start_scan_time = METADATA$START_SCAN_TIME,
    loader_file_last_modified = METADATA$FILE_LAST_MODIFIED,
    loader_file_content_key = METADATA$FILE_CONTENT_KEY)
  ON_ERROR = SKIP_FILE
  PATTERN = 'tenant_id=[0-9a-f-]{36}/organization_id=[0-9a-f-]{36}/account_id=([0-9a-f-]{36}|org)/extraction_date=[0-9]{4}-[0-9]{2}-[0-9]{2}/batch_id=[0-9a-f-]{36}/part-[0-9]{5}[.]parquet';

-- OU_RATE_SHEET_DAILY v1.0.0 (COMPLETE_PARTITION, DATE_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.ou_rate_sheet_daily_v1 (
  tenant_id VARCHAR(36) NOT NULL,
  organization_id VARCHAR(36) NOT NULL,
  account_id VARCHAR(36),
  source_batch_id VARCHAR(36) NOT NULL,
  logical_window_id VARCHAR(36) NOT NULL,
  source_window_start TIMESTAMP_NTZ(9) NOT NULL,
  source_window_end TIMESTAMP_NTZ(9) NOT NULL,
  source_extracted_at TIMESTAMP_NTZ(9) NOT NULL,
  source_schema_version NUMBER(10,0) NOT NULL,
  transport_schema_version VARCHAR(16) NOT NULL,
  privacy_policy_version NUMBER(10,0) NOT NULL,
  row_hash VARCHAR(64) NOT NULL,
  date DATE NOT NULL,
  organization_name VARCHAR,
  contract_number NUMBER(38,0),
  account_name VARCHAR,
  account_locator VARCHAR,
  region VARCHAR,
  service_level VARCHAR,
  usage_type VARCHAR,
  currency VARCHAR,
  effective_rate NUMBER(38,9),
  service_type VARCHAR,
  rating_type VARCHAR,
  billing_type VARCHAR,
  is_adjustment BOOLEAN,
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=OU_RATE_SHEET_DAILY contract_version=1.0.0 transport=1.0 fingerprint=3de460dc6d0603fa4f4c72972b378343fde948babce57e0fc50596e8d6f17709 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_ou_rate_sheet_daily_v1
  URL = 's3://&{landing_bucket}/landing/source=OU_RATE_SHEET_DAILY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for OU_RATE_SHEET_DAILY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_ou_rate_sheet_daily_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for OU_RATE_SHEET_DAILY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.ou_rate_sheet_daily_v1
  FROM @raw.stg_ou_rate_sheet_daily_v1
  FILE_FORMAT = (FORMAT_NAME = 'raw.bridge_parquet_v1')
  MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
  INCLUDE_METADATA = (
    loader_filename = METADATA$FILENAME,
    loader_file_row_number = METADATA$FILE_ROW_NUMBER,
    loader_start_scan_time = METADATA$START_SCAN_TIME,
    loader_file_last_modified = METADATA$FILE_LAST_MODIFIED,
    loader_file_content_key = METADATA$FILE_CONTENT_KEY)
  ON_ERROR = SKIP_FILE
  PATTERN = 'tenant_id=[0-9a-f-]{36}/organization_id=[0-9a-f-]{36}/account_id=([0-9a-f-]{36}|org)/extraction_date=[0-9]{4}-[0-9]{2}-[0-9]{2}/batch_id=[0-9a-f-]{36}/part-[0-9]{5}[.]parquet';

-- contract=snowflake-migration:RAW/V0215__raw_ai_marketplace_v1.sql version=1 status=DRAFT owner_task=ING-006 decisions=D-03,D-26 last_changed=2026-09-28
-- AI services and marketplace family (ING-105 R1 part): typed RAW tables, auto-ingest stages and pipes, one set per source x schema major.
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

-- AU_CORTEX_AI_FUNCTIONS_USAGE_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_cortex_ai_functions_usage_history_v1 (
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
  function_name VARCHAR,
  model_name VARCHAR,
  warehouse_id NUMBER(38,0),
  query_id VARCHAR,
  tokens NUMBER(38,0),
  credits NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_CORTEX_AI_FUNCTIONS_USAGE_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=fda7c59f1158c430c3cb7e1e4d730f28215541a9d9072f4102206213e6fe132a retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_cortex_ai_functions_usage_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_CORTEX_AI_FUNCTIONS_USAGE_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_CORTEX_AI_FUNCTIONS_USAGE_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_cortex_ai_functions_usage_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_CORTEX_AI_FUNCTIONS_USAGE_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_cortex_ai_functions_usage_history_v1
  FROM @raw.stg_au_cortex_ai_functions_usage_history_v1
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

-- AU_CORTEX_AISQL_USAGE_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_cortex_aisql_usage_history_v1 (
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
  usage_time TIMESTAMP_NTZ(9) NOT NULL,
  query_id VARCHAR,
  warehouse_id NUMBER(38,0),
  function_name VARCHAR,
  model_name VARCHAR,
  tokens NUMBER(38,0),
  token_credits NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_CORTEX_AISQL_USAGE_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=b2fae69ffcc0bc1092b038a8c4f0fdcaac5a8d0abb58d322761ad5a56dbaaa30 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_cortex_aisql_usage_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_CORTEX_AISQL_USAGE_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_CORTEX_AISQL_USAGE_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_cortex_aisql_usage_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_CORTEX_AISQL_USAGE_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_cortex_aisql_usage_history_v1
  FROM @raw.stg_au_cortex_aisql_usage_history_v1
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

-- AU_CORTEX_FUNCTIONS_USAGE_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_cortex_functions_usage_history_v1 (
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
  function_name VARCHAR,
  model_name VARCHAR,
  warehouse_id NUMBER(38,0),
  tokens NUMBER(38,0),
  token_credits NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_CORTEX_FUNCTIONS_USAGE_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=5020b9e6e817ec58841849f42a4fc028e9a8edefa59e9d803744cd3181f5e1ec retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_cortex_functions_usage_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_CORTEX_FUNCTIONS_USAGE_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_CORTEX_FUNCTIONS_USAGE_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_cortex_functions_usage_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_CORTEX_FUNCTIONS_USAGE_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_cortex_functions_usage_history_v1
  FROM @raw.stg_au_cortex_functions_usage_history_v1
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

-- AU_CORTEX_SEARCH_SERVING_USAGE_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_cortex_search_serving_usage_history_v1 (
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
  database_name VARCHAR,
  schema_name VARCHAR,
  service_name VARCHAR,
  service_id NUMBER(38,0),
  credits NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_CORTEX_SEARCH_SERVING_USAGE_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=3fbc2e4a360a9da208d057ad0b8cdeaf091d83f620c7c69d39def88edc346c19 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_cortex_search_serving_usage_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_CORTEX_SEARCH_SERVING_USAGE_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_CORTEX_SEARCH_SERVING_USAGE_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_cortex_search_serving_usage_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_CORTEX_SEARCH_SERVING_USAGE_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_cortex_search_serving_usage_history_v1
  FROM @raw.stg_au_cortex_search_serving_usage_history_v1
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

-- AU_CORTEX_ANALYST_USAGE_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_cortex_analyst_usage_history_v1 (
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
  user_name_pseudonym VARCHAR,
  credits NUMBER(38,9),
  request_count NUMBER(38,0),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_CORTEX_ANALYST_USAGE_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=b860d53644238de49921c437772062b9c9ee1702b5d62d0f4f8d40a70d396d1f retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_cortex_analyst_usage_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_CORTEX_ANALYST_USAGE_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_CORTEX_ANALYST_USAGE_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_cortex_analyst_usage_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_CORTEX_ANALYST_USAGE_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_cortex_analyst_usage_history_v1
  FROM @raw.stg_au_cortex_analyst_usage_history_v1
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

-- AU_CORTEX_AGENT_USAGE_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_cortex_agent_usage_history_v1 (
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
  agent_name VARCHAR,
  database_name VARCHAR,
  schema_name VARCHAR,
  credits NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_CORTEX_AGENT_USAGE_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=b77dbfd65d8cbb0c1e1e8fdf1a1b1b7a42553aea907e0baac599698a84460e33 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_cortex_agent_usage_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_CORTEX_AGENT_USAGE_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_CORTEX_AGENT_USAGE_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_cortex_agent_usage_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_CORTEX_AGENT_USAGE_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_cortex_agent_usage_history_v1
  FROM @raw.stg_au_cortex_agent_usage_history_v1
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

-- DSU_MARKETPLACE_PAID_USAGE_DAILY v1.0.0 (COMPLETE_PARTITION, DATE_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.dsu_marketplace_paid_usage_daily_v1 (
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
  usage_date DATE NOT NULL,
  report_date DATE,
  listing_global_name VARCHAR,
  listing_display_name VARCHAR,
  provider_name VARCHAR,
  charge_type VARCHAR,
  currency VARCHAR,
  charge NUMBER(38,9),
  units NUMBER(38,9),
  unit_price NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=DSU_MARKETPLACE_PAID_USAGE_DAILY contract_version=1.0.0 transport=1.0 fingerprint=b96a02be233aeb2c596ea7b0312f94c1fb53e4edab69b999fd01e8b20e4e2883 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_dsu_marketplace_paid_usage_daily_v1
  URL = 's3://&{landing_bucket}/landing/source=DSU_MARKETPLACE_PAID_USAGE_DAILY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for DSU_MARKETPLACE_PAID_USAGE_DAILY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_dsu_marketplace_paid_usage_daily_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for DSU_MARKETPLACE_PAID_USAGE_DAILY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.dsu_marketplace_paid_usage_daily_v1
  FROM @raw.stg_dsu_marketplace_paid_usage_daily_v1
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

-- AU_APPLICATION_DAILY_USAGE_HISTORY v1.0.0 (COMPLETE_PARTITION, DATE_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_application_daily_usage_history_v1 (
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
  application_name VARCHAR,
  application_id NUMBER(38,0),
  listing_global_name VARCHAR,
  usage_date DATE NOT NULL,
  credits_used NUMBER(38,9),
  credits_used_breakdown VARCHAR,
  storage_bytes NUMBER(38,0),
  storage_bytes_breakdown VARCHAR,
  data_transfer_bytes NUMBER(38,0),
  data_transfer_breakdown VARCHAR,
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_APPLICATION_DAILY_USAGE_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=ab05e8e5d05f01bd1dd27d0b1aba63f0cfa14a2f9cdae7d741727e6e6747b1ca retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_application_daily_usage_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_APPLICATION_DAILY_USAGE_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_APPLICATION_DAILY_USAGE_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_application_daily_usage_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_APPLICATION_DAILY_USAGE_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_application_daily_usage_history_v1
  FROM @raw.stg_au_application_daily_usage_history_v1
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

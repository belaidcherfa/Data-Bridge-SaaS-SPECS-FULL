-- contract=snowflake-migration:RAW/V0212__raw_storage_inventory_v1.sql version=1 status=DRAFT owner_task=ING-006 decisions=D-03,D-26 last_changed=2026-09-28
-- Storage and inventory family (ING-103, CON-004, INS-102, ING-105): typed RAW tables, auto-ingest stages and pipes, one set per source x schema major.
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

-- AU_STORAGE_USAGE v1.0.0 (COMPLETE_PARTITION, DATE_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_storage_usage_v1 (
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
  storage_bytes NUMBER(38,0),
  stage_bytes NUMBER(38,0),
  failsafe_bytes NUMBER(38,0),
  hybrid_table_storage_bytes NUMBER(38,0),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_STORAGE_USAGE contract_version=1.0.0 transport=1.0 fingerprint=1234d4c5a638692f89d3712ce1618466c4b32c3b09837149b9c26fb089221cac retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_storage_usage_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_STORAGE_USAGE/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_STORAGE_USAGE major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_storage_usage_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_STORAGE_USAGE major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_storage_usage_v1
  FROM @raw.stg_au_storage_usage_v1
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

-- AU_DATABASE_STORAGE_USAGE_HISTORY v1.0.0 (COMPLETE_PARTITION, DATE_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_database_storage_usage_history_v1 (
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
  database_id NUMBER(38,0),
  database_name VARCHAR,
  deleted TIMESTAMP_NTZ(9),
  average_database_bytes FLOAT,
  average_failsafe_bytes FLOAT,
  average_hybrid_table_storage_bytes FLOAT,
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_DATABASE_STORAGE_USAGE_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=3e0842969a3f46e277e17097eb4a8654936814b17e262d0784007888ecaf1b95 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_database_storage_usage_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_DATABASE_STORAGE_USAGE_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_DATABASE_STORAGE_USAGE_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_database_storage_usage_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_DATABASE_STORAGE_USAGE_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_database_storage_usage_history_v1
  FROM @raw.stg_au_database_storage_usage_history_v1
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

-- AU_STAGE_STORAGE_USAGE_HISTORY v1.0.0 (COMPLETE_PARTITION, DATE_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_stage_storage_usage_history_v1 (
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
  average_stage_bytes FLOAT,
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_STAGE_STORAGE_USAGE_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=a5b655b76bb67d0d5dd621b69ee4a89916de9785e3e6e4be6131076efdc80984 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_stage_storage_usage_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_STAGE_STORAGE_USAGE_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_STAGE_STORAGE_USAGE_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_stage_storage_usage_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_STAGE_STORAGE_USAGE_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_stage_storage_usage_history_v1
  FROM @raw.stg_au_stage_storage_usage_history_v1
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

-- AU_DATABASES v1.0.0 (SNAPSHOT, SNAPSHOT, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_databases_v1 (
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
  database_id NUMBER(38,0) NOT NULL,
  database_name VARCHAR,
  database_owner VARCHAR,
  is_transient VARCHAR,
  created TIMESTAMP_NTZ(9),
  last_altered TIMESTAMP_NTZ(9),
  deleted TIMESTAMP_NTZ(9),
  retention_time NUMBER(38,0),
  type VARCHAR,
  owner_role_type VARCHAR,
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_DATABASES contract_version=1.0.0 transport=1.0 fingerprint=d7ab2e0df36c2e63c12ed082197dfb15f39dfa21ed645330a23770ae984524c1 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_databases_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_DATABASES/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_DATABASES major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_databases_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_DATABASES major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_databases_v1
  FROM @raw.stg_au_databases_v1
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

-- AU_TABLE_STORAGE_METRICS v1.0.0 (SNAPSHOT, SNAPSHOT, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_table_storage_metrics_v1 (
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
  id NUMBER(38,0) NOT NULL,
  table_name VARCHAR,
  table_schema VARCHAR,
  table_catalog VARCHAR,
  table_schema_id NUMBER(38,0),
  table_catalog_id NUMBER(38,0),
  clone_group_id NUMBER(38,0),
  is_transient VARCHAR,
  active_bytes NUMBER(38,0),
  time_travel_bytes NUMBER(38,0),
  failsafe_bytes NUMBER(38,0),
  retained_for_clone_bytes NUMBER(38,0),
  deleted BOOLEAN,
  table_created TIMESTAMP_NTZ(9),
  table_dropped TIMESTAMP_NTZ(9),
  table_entered_failsafe TIMESTAMP_NTZ(9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_TABLE_STORAGE_METRICS contract_version=1.0.0 transport=1.0 fingerprint=a8bdb7d08e3690473053df05049ca99feda2b807d58370bf157e7399223056e1 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_table_storage_metrics_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_TABLE_STORAGE_METRICS/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_TABLE_STORAGE_METRICS major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_table_storage_metrics_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_TABLE_STORAGE_METRICS major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_table_storage_metrics_v1
  FROM @raw.stg_au_table_storage_metrics_v1
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

-- AU_TAG_REFERENCES v1.0.0 (SNAPSHOT, SNAPSHOT, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_tag_references_v1 (
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
  tag_database VARCHAR,
  tag_schema VARCHAR,
  tag_id NUMBER(38,0) NOT NULL,
  tag_name VARCHAR,
  tag_value_sanitized VARCHAR,
  object_database VARCHAR,
  object_schema VARCHAR,
  object_id NUMBER(38,0) NOT NULL,
  object_name VARCHAR,
  object_deleted TIMESTAMP_NTZ(9),
  domain VARCHAR NOT NULL,
  column_id NUMBER(38,0),
  column_name VARCHAR,
  column_id_key NUMBER(38,0) NOT NULL,
  apply_method VARCHAR,
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_TAG_REFERENCES contract_version=1.0.0 transport=1.0 fingerprint=0d3a61bbee0cd7b4033e1c91f50669ca309e419fa34e8c461e65420c14279630 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_tag_references_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_TAG_REFERENCES/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_TAG_REFERENCES major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_tag_references_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_TAG_REFERENCES major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_tag_references_v1
  FROM @raw.stg_au_tag_references_v1
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

-- OU_ACCOUNTS v1.0.0 (SNAPSHOT, SNAPSHOT, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.ou_accounts_v1 (
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
  account_name VARCHAR,
  account_locator VARCHAR NOT NULL,
  region VARCHAR NOT NULL,
  region_group VARCHAR,
  edition VARCHAR,
  account_url VARCHAR,
  created_on TIMESTAMP_NTZ(9),
  deleted_on TIMESTAMP_NTZ(9),
  is_org_admin BOOLEAN,
  is_organization_account BOOLEAN,
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=OU_ACCOUNTS contract_version=1.0.0 transport=1.0 fingerprint=1143ec007dab7413410587906fc0abbed194578c07c653545b42208fd021ed6f retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_ou_accounts_v1
  URL = 's3://&{landing_bucket}/landing/source=OU_ACCOUNTS/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for OU_ACCOUNTS major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_ou_accounts_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for OU_ACCOUNTS major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.ou_accounts_v1
  FROM @raw.stg_ou_accounts_v1
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

-- OU_STORAGE_DAILY_HISTORY v1.0.0 (COMPLETE_PARTITION, DATE_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.ou_storage_daily_history_v1 (
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
  usage_date DATE NOT NULL,
  organization_name VARCHAR,
  account_name VARCHAR,
  account_locator VARCHAR,
  region VARCHAR,
  service_type VARCHAR,
  average_bytes FLOAT,
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=OU_STORAGE_DAILY_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=6745f0ca6fceff5d07b55d734a743749855d62d587bd9c1c2b6cc3bfa4fa65e6 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_ou_storage_daily_history_v1
  URL = 's3://&{landing_bucket}/landing/source=OU_STORAGE_DAILY_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for OU_STORAGE_DAILY_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_ou_storage_daily_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for OU_STORAGE_DAILY_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.ou_storage_daily_history_v1
  FROM @raw.stg_ou_storage_daily_history_v1
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

-- SHOW_WAREHOUSES v1.0.0 (SNAPSHOT, SNAPSHOT, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.show_warehouses_v1 (
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
  warehouse_name VARCHAR NOT NULL,
  state VARCHAR,
  warehouse_type VARCHAR,
  warehouse_size VARCHAR,
  min_cluster_count NUMBER(38,0),
  max_cluster_count NUMBER(38,0),
  auto_suspend NUMBER(38,0),
  auto_resume VARCHAR,
  scaling_policy VARCHAR,
  resource_monitor VARCHAR,
  enable_query_acceleration VARCHAR,
  query_acceleration_max_scale_factor NUMBER(38,0),
  owner_role VARCHAR,
  warehouse_created_on TIMESTAMP_NTZ(9),
  resumed_on TIMESTAMP_NTZ(9),
  updated_on TIMESTAMP_NTZ(9),
  generation VARCHAR,
  resource_constraint VARCHAR,
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=SHOW_WAREHOUSES contract_version=1.0.0 transport=1.0 fingerprint=1721ca172058e24f47de28f9dc993b390d25895041db396834f6a823add5ff87 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_show_warehouses_v1
  URL = 's3://&{landing_bucket}/landing/source=SHOW_WAREHOUSES/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for SHOW_WAREHOUSES major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_show_warehouses_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for SHOW_WAREHOUSES major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.show_warehouses_v1
  FROM @raw.stg_show_warehouses_v1
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

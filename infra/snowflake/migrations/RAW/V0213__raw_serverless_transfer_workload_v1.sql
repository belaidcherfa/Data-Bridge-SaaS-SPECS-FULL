-- contract=snowflake-migration:RAW/V0213__raw_serverless_transfer_workload_v1.sql version=1 status=DRAFT owner_task=ING-006 decisions=D-03,D-26 last_changed=2026-09-28
-- Serverless, transfer and workload-execution family (ING-104): typed RAW tables, auto-ingest stages and pipes, one set per source x schema major.
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

-- AU_AUTOMATIC_CLUSTERING_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_automatic_clustering_history_v1 (
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
  table_id NUMBER(38,0),
  table_name VARCHAR,
  schema_id NUMBER(38,0),
  schema_name VARCHAR,
  database_id NUMBER(38,0),
  database_name VARCHAR,
  credits_used NUMBER(38,9),
  num_bytes_reclustered NUMBER(38,0),
  num_rows_reclustered NUMBER(38,0),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_AUTOMATIC_CLUSTERING_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=829b6c6b79349fc8a12e54bf2b5caa1ace34e20b7a6065bb07308a38920e3f80 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_automatic_clustering_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_AUTOMATIC_CLUSTERING_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_AUTOMATIC_CLUSTERING_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_automatic_clustering_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_AUTOMATIC_CLUSTERING_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_automatic_clustering_history_v1
  FROM @raw.stg_au_automatic_clustering_history_v1
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

-- AU_SERVERLESS_TASK_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_serverless_task_history_v1 (
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
  task_id NUMBER(38,0),
  task_name VARCHAR,
  schema_id NUMBER(38,0),
  schema_name VARCHAR,
  database_id NUMBER(38,0),
  database_name VARCHAR,
  instance_id NUMBER(38,0),
  credits_used VARCHAR,
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_SERVERLESS_TASK_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=7cb0988e4d390b584ebe972a94b89e68987cd7c39c54504a0fa0068efdb1f261 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_serverless_task_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_SERVERLESS_TASK_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_SERVERLESS_TASK_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_serverless_task_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_SERVERLESS_TASK_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_serverless_task_history_v1
  FROM @raw.stg_au_serverless_task_history_v1
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

-- AU_PIPE_USAGE_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_pipe_usage_history_v1 (
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
  pipe_id NUMBER(38,0),
  pipe_name VARCHAR,
  start_time TIMESTAMP_NTZ(9) NOT NULL,
  end_time TIMESTAMP_NTZ(9),
  credits_used NUMBER(38,9),
  bytes_inserted FLOAT,
  files_inserted NUMBER(38,0),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_PIPE_USAGE_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=4cd30e1bf92f6f25fc48d6a1065ae2676377ef5dff64191180b13816b628ad29 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_pipe_usage_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_PIPE_USAGE_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_PIPE_USAGE_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_pipe_usage_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_PIPE_USAGE_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_pipe_usage_history_v1
  FROM @raw.stg_au_pipe_usage_history_v1
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

-- AU_DATA_TRANSFER_HISTORY v1.0.0 (COMPLETE_PARTITION, DATE_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_data_transfer_history_v1 (
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
  source_cloud VARCHAR,
  source_region VARCHAR,
  target_cloud VARCHAR,
  target_region VARCHAR,
  bytes_transferred VARCHAR,
  transfer_type VARCHAR,
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_DATA_TRANSFER_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=fbcb8ff34188a2454c76b07f3c4dc75115ba0bc0d35e79c2f2171693f65468e9 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_data_transfer_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_DATA_TRANSFER_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_DATA_TRANSFER_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_data_transfer_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_DATA_TRANSFER_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_data_transfer_history_v1
  FROM @raw.stg_au_data_transfer_history_v1
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

-- AU_TASK_HISTORY v1.0.0 (EVENT_UPSERT, END_TIME_SWEEP, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_task_history_v1 (
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
  query_id VARCHAR,
  name VARCHAR NOT NULL,
  database_name VARCHAR NOT NULL,
  schema_name VARCHAR NOT NULL,
  root_task_id VARCHAR,
  graph_run_group_id VARCHAR,
  run_id NUMBER(38,0),
  state VARCHAR,
  error_code VARCHAR,
  scheduled_time TIMESTAMP_NTZ(9) NOT NULL,
  query_start_time TIMESTAMP_NTZ(9),
  completed_time TIMESTAMP_NTZ(9),
  attempt_number NUMBER(38,0) NOT NULL,
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_TASK_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=8e410ea4643d73845a758689f7f15a947584a9c7c335eda415b84a376c8140fb retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_task_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_TASK_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_TASK_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_task_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_TASK_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_task_history_v1
  FROM @raw.stg_au_task_history_v1
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

-- AU_DYNAMIC_TABLE_REFRESH_HISTORY v1.0.0 (EVENT_UPSERT, END_TIME_SWEEP, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_dynamic_table_refresh_history_v1 (
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
  qualified_name VARCHAR NOT NULL,
  name VARCHAR,
  schema_name VARCHAR,
  database_name VARCHAR,
  query_id VARCHAR,
  state VARCHAR,
  state_code VARCHAR,
  refresh_action VARCHAR,
  refresh_trigger VARCHAR,
  data_timestamp TIMESTAMP_NTZ(9) NOT NULL,
  refresh_start_time TIMESTAMP_NTZ(9) NOT NULL,
  refresh_end_time TIMESTAMP_NTZ(9),
  target_lag_sec NUMBER(38,0),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_DYNAMIC_TABLE_REFRESH_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=8408260dc1f5d1e0fa760dabacbc4873077248dffb386e3b7f2f0e42e4f4c887 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_dynamic_table_refresh_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_DYNAMIC_TABLE_REFRESH_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_DYNAMIC_TABLE_REFRESH_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_dynamic_table_refresh_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_DYNAMIC_TABLE_REFRESH_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_dynamic_table_refresh_history_v1
  FROM @raw.stg_au_dynamic_table_refresh_history_v1
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

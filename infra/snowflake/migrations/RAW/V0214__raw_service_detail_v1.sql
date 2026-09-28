-- contract=snowflake-migration:RAW/V0214__raw_service_detail_v1.sql version=1 status=DRAFT owner_task=ING-006 decisions=D-03,D-26 last_changed=2026-09-28
-- Service-detail family (ING-105 R1 part): typed RAW tables, auto-ingest stages and pipes, one set per source x schema major.
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

-- AU_MATERIALIZED_VIEW_REFRESH_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_materialized_view_refresh_history_v1 (
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
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_MATERIALIZED_VIEW_REFRESH_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=cc1a748c105a0df744bbba38749f683578dbef231a6c4d00ab81cb65fec17384 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_materialized_view_refresh_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_MATERIALIZED_VIEW_REFRESH_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_MATERIALIZED_VIEW_REFRESH_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_materialized_view_refresh_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_MATERIALIZED_VIEW_REFRESH_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_materialized_view_refresh_history_v1
  FROM @raw.stg_au_materialized_view_refresh_history_v1
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

-- AU_SEARCH_OPTIMIZATION_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_search_optimization_history_v1 (
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
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_SEARCH_OPTIMIZATION_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=cc1a748c105a0df744bbba38749f683578dbef231a6c4d00ab81cb65fec17384 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_search_optimization_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_SEARCH_OPTIMIZATION_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_SEARCH_OPTIMIZATION_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_search_optimization_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_SEARCH_OPTIMIZATION_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_search_optimization_history_v1
  FROM @raw.stg_au_search_optimization_history_v1
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

-- AU_QUERY_ACCELERATION_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_query_acceleration_history_v1 (
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
  num_files_scanned NUMBER(38,0),
  num_bytes_scanned NUMBER(38,0),
  credits_used NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_QUERY_ACCELERATION_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=40cfbebdde76100e073d02160a7c35800313a36175b5b54c7940c3d26294647c retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_query_acceleration_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_QUERY_ACCELERATION_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_QUERY_ACCELERATION_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_query_acceleration_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_QUERY_ACCELERATION_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_query_acceleration_history_v1
  FROM @raw.stg_au_query_acceleration_history_v1
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

-- AU_REPLICATION_GROUP_USAGE_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_replication_group_usage_history_v1 (
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
  replication_group_name VARCHAR,
  replication_group_id NUMBER(38,0),
  bytes_transferred NUMBER(38,0),
  credits_used NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_REPLICATION_GROUP_USAGE_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=8a92aa76fac3e4c53f70aa9c3bf61083d98c2e9bf92ba7db3f42bb22bde58896 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_replication_group_usage_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_REPLICATION_GROUP_USAGE_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_REPLICATION_GROUP_USAGE_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_replication_group_usage_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_REPLICATION_GROUP_USAGE_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_replication_group_usage_history_v1
  FROM @raw.stg_au_replication_group_usage_history_v1
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

-- AU_REPLICATION_USAGE_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_replication_usage_history_v1 (
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
  database_id NUMBER(38,0),
  bytes_transferred NUMBER(38,0),
  credits_used NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_REPLICATION_USAGE_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=cb9a698a0cd7b6e8c49a38d085de1e7ab023db2f61c4b89c269c3cadbc73eb68 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_replication_usage_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_REPLICATION_USAGE_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_REPLICATION_USAGE_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_replication_usage_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_REPLICATION_USAGE_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_replication_usage_history_v1
  FROM @raw.stg_au_replication_usage_history_v1
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

-- AU_SNOWPARK_CONTAINER_SERVICES_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_snowpark_container_services_history_v1 (
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
  compute_pool_name VARCHAR,
  compute_pool_id NUMBER(38,0),
  is_exclusive BOOLEAN,
  application_name VARCHAR,
  application_id VARCHAR,
  credits_used NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_SNOWPARK_CONTAINER_SERVICES_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=7b68c2e02bf9ccb6f45b9da0df73215e9b0ddfc363e0bd1b41aa939b8d579c04 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_snowpark_container_services_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_SNOWPARK_CONTAINER_SERVICES_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_SNOWPARK_CONTAINER_SERVICES_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_snowpark_container_services_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_SNOWPARK_CONTAINER_SERVICES_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_snowpark_container_services_history_v1
  FROM @raw.stg_au_snowpark_container_services_history_v1
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

-- AU_SNOWPIPE_STREAMING_CLIENT_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_snowpipe_streaming_client_history_v1 (
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
  client_name VARCHAR,
  snowflake_provided_id VARCHAR,
  event_timestamp TIMESTAMP_NTZ(9),
  credits_used NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_SNOWPIPE_STREAMING_CLIENT_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=19b78cc7f76a53bae7c0e10d5d1fb5daff81ba2b145ad0d588cf8c4630378746 retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_snowpipe_streaming_client_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_SNOWPIPE_STREAMING_CLIENT_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_SNOWPIPE_STREAMING_CLIENT_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_snowpipe_streaming_client_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_SNOWPIPE_STREAMING_CLIENT_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_snowpipe_streaming_client_history_v1
  FROM @raw.stg_au_snowpipe_streaming_client_history_v1
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

-- AU_SNOWPIPE_STREAMING_CHANNEL_HISTORY v1.0.0 (COMPLETE_PARTITION, HOUR_PARTITION, retention_class=FINANCIAL, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_snowpipe_streaming_channel_history_v1 (
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
  channel_name VARCHAR,
  pipe_name VARCHAR,
  table_name VARCHAR,
  database_name VARCHAR,
  schema_name VARCHAR,
  uncompressed_bytes_ingested NUMBER(38,0),
  credits_used NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_SNOWPIPE_STREAMING_CHANNEL_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=59c40d4fc3fc3375b2bfb485a9187d0c74b605dc8f5eef45ceb3ec4efd25172f retention_class=FINANCIAL raw_retention_days=400 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_snowpipe_streaming_channel_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_SNOWPIPE_STREAMING_CHANNEL_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_SNOWPIPE_STREAMING_CHANNEL_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_snowpipe_streaming_channel_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_SNOWPIPE_STREAMING_CHANNEL_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_snowpipe_streaming_channel_history_v1
  FROM @raw.stg_au_snowpipe_streaming_channel_history_v1
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

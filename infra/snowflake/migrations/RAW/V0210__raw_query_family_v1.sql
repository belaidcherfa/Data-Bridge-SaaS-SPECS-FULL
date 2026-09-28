-- contract=snowflake-migration:RAW/V0210__raw_query_family_v1.sql version=1 status=DRAFT owner_task=ING-006 decisions=D-03,D-26 last_changed=2026-09-28
-- Query family (ING-101): typed RAW tables, auto-ingest stages and pipes, one set per source x schema major.
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

-- AU_QUERY_HISTORY v1.0.0 (EVENT_UPSERT, END_TIME_SWEEP, retention_class=QUERY_GRAIN, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_query_history_v1 (
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
  is_bridge_overhead BOOLEAN NOT NULL,
  query_text_mode VARCHAR(16) NOT NULL,
  query_id VARCHAR NOT NULL,
  start_time TIMESTAMP_NTZ(9),
  end_time TIMESTAMP_NTZ(9),
  warehouse_id NUMBER(38,0),
  warehouse_name VARCHAR,
  warehouse_size VARCHAR,
  warehouse_type VARCHAR,
  cluster_number NUMBER(38,0),
  user_name_pseudonym VARCHAR,
  role_name VARCHAR,
  session_id NUMBER(38,0),
  database_id NUMBER(38,0),
  database_name VARCHAR,
  schema_id NUMBER(38,0),
  schema_name VARCHAR,
  query_type VARCHAR,
  execution_status VARCHAR,
  error_code VARCHAR,
  total_elapsed_time NUMBER(38,0),
  execution_time NUMBER(38,0),
  compilation_time NUMBER(38,0),
  queued_overload_time NUMBER(38,0),
  queued_provisioning_time NUMBER(38,0),
  bytes_spilled_to_local_storage NUMBER(38,0),
  bytes_spilled_to_remote_storage NUMBER(38,0),
  partitions_scanned NUMBER(38,0),
  partitions_total NUMBER(38,0),
  rows_inserted NUMBER(38,0),
  rows_updated NUMBER(38,0),
  rows_deleted NUMBER(38,0),
  credits_used_cloud_services NUMBER(38,9),
  query_hash VARCHAR,
  query_hash_version NUMBER(38,0),
  query_parameterized_hash VARCHAR,
  query_parameterized_hash_version NUMBER(38,0),
  query_tag_sanitized VARCHAR,
  query_text_sanitized VARCHAR,
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_QUERY_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=a3d9fb66b9d1963e96f7b5444d60ad7ce8bb2a3b206230d682ad58c664ee3075 retention_class=QUERY_GRAIN raw_retention_days=90 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_query_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_QUERY_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_QUERY_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_query_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_QUERY_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_query_history_v1
  FROM @raw.stg_au_query_history_v1
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

-- AU_QUERY_ATTRIBUTION_HISTORY v1.0.0 (EVENT_UPSERT, END_TIME_SWEEP, retention_class=QUERY_GRAIN, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_query_attribution_history_v1 (
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
  is_bridge_overhead BOOLEAN NOT NULL,
  query_id VARCHAR NOT NULL,
  parent_query_id VARCHAR,
  root_query_id VARCHAR,
  warehouse_id NUMBER(38,0),
  warehouse_name VARCHAR,
  query_hash VARCHAR,
  query_parameterized_hash VARCHAR,
  start_time TIMESTAMP_NTZ(9),
  end_time TIMESTAMP_NTZ(9),
  credits_attributed_compute NUMBER(38,9),
  credits_used_query_acceleration NUMBER(38,9),
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_QUERY_ATTRIBUTION_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=f0eae9424bb98bef7e520692b6ab7679da596302f633eab5980b1f6270508b2f retention_class=QUERY_GRAIN raw_retention_days=90 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_query_attribution_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_QUERY_ATTRIBUTION_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_QUERY_ATTRIBUTION_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_query_attribution_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_QUERY_ATTRIBUTION_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_query_attribution_history_v1
  FROM @raw.stg_au_query_attribution_history_v1
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

-- AU_QUERY_METERING_HISTORY v1.0.0 (EVENT_UPSERT, PENDING_REFRESH, retention_class=QUERY_GRAIN, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_query_metering_history_v1 (
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
  query_id VARCHAR NOT NULL,
  warehouse_id NUMBER(38,0),
  query_metering_hour TIMESTAMP_NTZ(9) NOT NULL,
  query_start_time TIMESTAMP_NTZ(9),
  query_end_time TIMESTAMP_NTZ(9),
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
  COMMENT = 'source_contract=AU_QUERY_METERING_HISTORY contract_version=1.0.0 transport=1.0 fingerprint=9e3f6c288b261b68f2ef511d0edc783c4166c5ec4c2154b34c88d2602da31a5d retention_class=QUERY_GRAIN raw_retention_days=90 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_query_metering_history_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_QUERY_METERING_HISTORY/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_QUERY_METERING_HISTORY major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_query_metering_history_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_QUERY_METERING_HISTORY major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_query_metering_history_v1
  FROM @raw.stg_au_query_metering_history_v1
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

-- AU_SESSIONS v1.0.0 (EVENT_UPSERT, START_TIME_INTERVAL, retention_class=QUERY_GRAIN, activation=DRAFT)
CREATE TABLE IF NOT EXISTS raw.au_sessions_v1 (
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
  session_id NUMBER(38,0) NOT NULL,
  created_on TIMESTAMP_NTZ(9),
  user_name_pseudonym VARCHAR,
  client_application_id VARCHAR,
  client_application_version VARCHAR,
  client_environment_application VARCHAR,
  loader_filename VARCHAR NOT NULL,
  loader_file_row_number NUMBER(38,0) NOT NULL,
  loader_start_scan_time TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_last_modified TIMESTAMP_LTZ(9) NOT NULL,
  loader_file_content_key VARCHAR NOT NULL
)
  DATA_RETENTION_TIME_IN_DAYS = 1
  ENABLE_SCHEMA_EVOLUTION = FALSE
  COMMENT = 'source_contract=AU_SESSIONS contract_version=1.0.0 transport=1.0 fingerprint=e9f4fce87eb64d923171c20131488071fff9d4a25e436038538dc578dbdaa66e retention_class=QUERY_GRAIN raw_retention_days=90 owner_task=ING-006';

CREATE STAGE IF NOT EXISTS raw.stg_au_sessions_v1
  URL = 's3://&{landing_bucket}/landing/source=AU_SESSIONS/schema_major=1/'
  STORAGE_INTEGRATION = bridge_landing_s3
  FILE_FORMAT = raw.bridge_parquet_v1
  COMMENT = 'Auto-ingest stage for AU_SESSIONS major 1; manifests/ and probes/ are outside the integration allowed locations (ING-006-S02).';

CREATE PIPE IF NOT EXISTS raw.pipe_au_sessions_v1
  AUTO_INGEST = TRUE
  AWS_SNS_TOPIC = '&{landing_sns_topic_arn}'
  COMMENT = 'Steady-state auto-ingest for AU_SESSIONS major 1 (D-03); never ALTERed while active (ING-006-S11).'
  AS COPY INTO raw.au_sessions_v1
  FROM @raw.stg_au_sessions_v1
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

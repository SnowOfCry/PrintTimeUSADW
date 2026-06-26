# Audit Data Dictionary

PrintTimeUSA Data Warehouse | Audit schema. The `audit` schema holds governance/control tables that are cross-cutting over the medallion layers (bronze/silver/gold) — they are **not** part of the dimensional model. Two tables: `audit.etl_batch_control` (ETL watermark/batch control) and `audit.audit_log` (generic insert-only audit trail).

Tables: 2.

---

## audit.etl_batch_control

- **Purpose:** One row per ETL batch (any layer). Drives incremental watermarks and records load outcome/statistics.
- **Primary key:** batch_key (identity)
- **Unique:** batch_id

| Column | Data Type | Nullable | Default | Description |
|---|---|---|---|---|
| batch_key | INTEGER | NOT NULL | identity | Surrogate key. PK. |
| batch_id | VARCHAR(50) | NOT NULL | — | External batch identifier. **UNIQUE**; referenced by `etl_batch_id` across layers. |
| source_system | VARCHAR(50) | NULL | — | Source system for the batch. |
| target_table | VARCHAR(100) | NULL | — | Table the batch loaded. |
| load_type | VARCHAR(20) | NULL | — | Load strategy (incremental_append, incremental_merge, full…). |
| watermark_column | VARCHAR(100) | NULL | — | Column used as the incremental watermark. |
| watermark_value_start | VARCHAR(100) | NULL | — | Watermark window start (text). |
| watermark_value_end | VARCHAR(100) | NULL | — | Watermark window end (text). |
| batch_status | VARCHAR(20) | NULL | — | Run status (running, succeeded, failed…). |
| batch_start_timestamp | TIMESTAMP | NULL | — | Batch start time. |
| batch_end_timestamp | TIMESTAMP | NULL | — | Batch end time. |
| rows_extracted | INTEGER | NULL | — | Rows read from source. |
| rows_inserted | INTEGER | NULL | — | Rows inserted into target. |
| rows_updated | INTEGER | NULL | — | Rows updated in target. |
| rows_deleted | INTEGER | NULL | — | Rows deleted/soft-deleted. |
| rows_rejected | INTEGER | NULL | — | Rows rejected/quarantined. |
| error_message | VARCHAR(2000) | NULL | — | Error detail on failure. |
| retry_count | INTEGER | NOT NULL | 0 | Number of retries for the batch. |
| initiated_by | VARCHAR(100) | NULL | — | User/process that started the batch. |
| etl_load_timestamp | TIMESTAMP | NOT NULL | clock_timestamp() | When this control row was written. |

---

## audit.audit_log

- **Purpose:** Generic, **insert-only** audit trail of row-level changes (INSERT/UPDATE/DELETE) with before/after JSONB snapshots. Never updated or deleted.
- **Primary key:** audit_id (identity)

| Column | Data Type | Nullable | Default | Description |
|---|---|---|---|---|
| audit_id | BIGINT | NOT NULL | identity | Surrogate key. PK. |
| table_name | VARCHAR(100) | NOT NULL | — | Table whose row changed. |
| operation_type | VARCHAR(10) | NOT NULL | — | Change type: INSERT / UPDATE / DELETE. |
| record_key | VARCHAR(100) | NULL | — | Business/primary key of the changed row. |
| old_row | JSONB | NULL | — | Row image before the change. |
| new_row | JSONB | NULL | — | Row image after the change. |
| changed_columns | JSONB | NULL | — | List of columns that changed (UPDATE). |
| change_reason | VARCHAR(500) | NULL | — | Optional reason/context for the change. |
| changed_by_app_user | VARCHAR(100) | NULL | — | Application user responsible. |
| changed_by_db_user | VARCHAR(100) | NULL | current_user | Database user responsible. |
| changed_at | TIMESTAMP | NOT NULL | clock_timestamp() | When the change was recorded. |
| etl_batch_id | VARCHAR(50) | NULL | — | Batch id (joins audit.etl_batch_control.batch_id). |
| source_system | VARCHAR(50) | NULL | — | Source system of the change. |

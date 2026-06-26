# Bronze Incremental Append Strategy

PrintTimeUSA Data Warehouse | Bronze landing layer.

## Why Bronze is append-only

Bronze is the raw landing layer in the medallion architecture (bronze -> silver -> gold). Its job is to preserve an immutable, auditable history of exactly what arrived from each source on each extract. We never run `UPDATE`, `DELETE`, or `MERGE` against Bronze. Every extract performs `INSERT` only:

```sql
INSERT INTO bronze.oltp_invoice ( ... )
SELECT ...
FROM   oltp.invoice
WHERE  source_updated_at > :last_watermark;
```

If a source row changes, the changed version is **inserted as a new Bronze row** alongside the older versions. This gives Silver and Gold a complete change feed to build SCD Type 2 dimensions, audit fact changes, and reprocess history without re-extracting the source.

## How batch IDs work

Every load runs under a single ETL batch tracked in `control.etl_batch_control`. The batch's `batch_id` is stamped onto every row it inserts via `bronze_batch_id`. Because Bronze is append-only:

- A batch can be identified, counted, and (if it failed midway) quarantined or superseded by a later batch without mutating prior rows.
- Lineage questions ("which load produced this row?") are answered by joining `bronze_batch_id` back to `control.etl_batch_control`.
- `bronze_loaded_at_timestamp` records when the row landed; `bronze_extracted_at_timestamp` records when the extractor read it from the source.

## How row hashes work

`bronze_row_hash` is a deterministic hash (e.g. MD5/SHA-256) computed over the **business column values** of the row (not the metadata). It lets downstream layers:

- Detect whether a newly appended source-row version is actually different from the last one seen for that source id.
- Deduplicate no-op extracts (same business values re-extracted) when building Silver.
- Drive change detection for SCD2 in Gold without comparing every column individually.

The hash is stored, never used to filter inserts — Bronze still appends every extracted row; the hash is a downstream convenience and an audit checksum.

## How watermarks work

Each Bronze table declares a recommended watermark column (see the mapping doc). The ETL reads the high-water mark of the last successful batch from `control.etl_batch_control.watermark_value_end` for that target, then extracts only source rows beyond it:

1. Read `watermark_value_end` for the target table (e.g. the max `source_updated_at` already loaded).
2. Extract source rows where the source watermark column is greater than that value.
3. Append them to Bronze.
4. Record the new max watermark in `watermark_value_end` for the batch.

Watermark column selection rules used in this project:

- Prefer the source `source_updated_at` (standardized in Bronze as `updated_at_source_timestamp`).
- If the source table only has `updated_at`, use it as `updated_at_source_timestamp`.
- For insert-only history tables (invoice_status_history, customer_status_history) use the event time `changed_at` as `changed_at_source_timestamp`.
- For tiny static reference tables with no reliable timestamp, fall back to a full extract appended under a new batch id (append-only full snapshot).
- For file/CSV/manual sources, use the file modified timestamp plus `bronze_source_file_name` / `bronze_source_row_number` for per-row lineage.

## How changed source records are captured

Because the load filters on the source watermark and inserts (never updates), any source row whose `updated_at` advances past the watermark is re-extracted and appended as a new Bronze version. The combination of (`source id`, `source_row_version`, `updated_at_source_timestamp`, `bronze_row_hash`, `bronze_batch_id`) on the appended rows fully describes the change history for that source record.

## Why source IDs are not primary keys in Bronze

The same business row legitimately appears many times in Bronze — once per extract in which it changed. Using `invoice_id` as the primary key of `bronze.oltp_invoice` would reject the second and later versions of invoice 1001 and destroy the very history Bronze exists to keep. Instead:

- `bronze_record_id BIGSERIAL` is the technical primary key (always unique, append-safe).
- The source id (e.g. `invoice_id`) is a plain, indexed business column that can repeat.

## How invoice status changes are preserved

Invoice status changes are a core business requirement. Example:

| Load day | invoice_number | invoice_status | bronze_batch_id | bronze_record_id |
|---|---|---|---|---|
| Monday  | 1001 | OPEN    | 10401 | 5567 |
| Tuesday | 1001 | PARTIAL | 10428 | 9912 |
| Friday  | 1001 | PAID    | 10455 | 14820 |

All three rows coexist in `bronze.oltp_invoice`. Nothing is overwritten. Silver/Gold can reconstruct the full OPEN -> PARTIAL -> PAID timeline, build SCD2 `dim_invoice` versions, and audit when each fact-affecting change happened. The companion `bronze.oltp_invoice_status_history` table captures the same transitions from the source's own change log as an authoritative cross-check.

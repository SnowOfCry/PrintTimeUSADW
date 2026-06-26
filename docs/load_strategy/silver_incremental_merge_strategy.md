# Silver Incremental Merge Strategy

PrintTimeUSA Data Warehouse | Silver layer.

## Why Silver uses incremental merge

Bronze is append-only: it keeps every extracted version of every source row. Silver's job is to present **one clean, current row per business entity** (e.g. one row per `invoice_id`). So Silver uses an upsert (`INSERT ... ON CONFLICT ... DO UPDATE`) keyed on the business key, updating an existing row only when something actually changed. This keeps Silver small, query-friendly, and trustworthy for Gold, while Bronze retains full history.

## How Bronze append-only records are deduplicated

Each merge reads only new Bronze rows (`bronze_batch_id > :last_bronze_batch_id`), then collapses them to the latest version per business key with a window function:

```
ROW_NUMBER() OVER (
    PARTITION BY <source_business_id>
    ORDER BY updated_at_source_timestamp DESC NULLS LAST,
             created_at_source_timestamp DESC NULLS LAST,
             bronze_loaded_at_timestamp DESC,
             bronze_record_id DESC
) AS rn
... WHERE rn = 1
```

For the history tables (`invoice_status_history`, `customer_status_history`) the ordering uses `changed_at_source_timestamp` because those Bronze rows have no created/updated timestamps.

## How the latest record is selected

After partitioning, `WHERE rn = 1` keeps the freshest Bronze row per key. Freshness prefers the source updated timestamp, then source created timestamp, then Bronze load time, then the Bronze surrogate id as a final tiebreaker (monotonic, so it always breaks ties deterministically).

## How row hashes detect changes

Silver computes `silver_row_hash = md5(<standardized business columns>)` over the **cleaned** values (not the raw Bronze values). On merge:

- If the business key is new, the row is inserted.
- If the key exists, the row is updated **only when** `silver_row_hash IS DISTINCT FROM EXCLUDED.silver_row_hash`.

Hashing the standardized values means cosmetic source noise (extra spaces, casing) that cleans to the same value does not cause spurious updates.

## How inserts and updates work

```
INSERT INTO silver.<entity> (...business..., ...lineage..., silver_batch_id, silver_row_hash)
SELECT ... FROM hashed
ON CONFLICT (silver_<entity>_id) DO UPDATE SET
    <business cols> = EXCLUDED.<...>,
    silver_updated_at_timestamp = CURRENT_TIMESTAMP,
    silver_row_hash = EXCLUDED.silver_row_hash,
    ...
WHERE silver.<entity>.silver_row_hash IS DISTINCT FROM EXCLUDED.silver_row_hash;
```

`silver_created_at_timestamp` is set once on insert; `silver_updated_at_timestamp` advances on every real update.

## How unchanged rows are skipped

The `WHERE ... IS DISTINCT FROM ...` predicate on the `DO UPDATE` means a conflicting row whose hash matches is left untouched — no write, no `silver_updated_at_timestamp` bump. This keeps update churn (and downstream Gold change detection) limited to true changes.

## How invoice status changes flow from Bronze to Silver

Bronze holds every extracted invoice version:

```
invoice_id 1001  status pending      bronze_batch_id 1
invoice_id 1001  status partial_paid bronze_batch_id 2
invoice_id 1001  status paid         bronze_batch_id 3
```

The merge dedups these to the latest (paid), standardizes the status value, and upserts a single Silver row:

```
silver_invoice_id 1001  silver_invoice_status paid  silver_batch_id 3
```

Because the status value changed, the hash differs and the row updates. Lineage columns (`silver_bronze_record_id`, `silver_bronze_batch_id`, `silver_source_record_id`) point to the winning Bronze row. The full transition history remains available in Bronze and, in standardized form, in `silver.invoice_status_history`.

## Why Silver keeps the current clean version instead of raw history

Gold dimensions and facts need conformed, deduplicated, current data — not raw multi-version history. Keeping one clean row per key makes Gold loads simple and fast. History is not lost: Bronze is the immutable system of record, and the two `*_status_history` Silver tables expose standardized transitions for SCD2/audit use in Gold.

## How Silver lineage links back to Bronze

Every Silver row carries:

- `silver_bronze_record_id` — the exact Bronze row that created/last-updated it.
- `silver_bronze_batch_id` — the Bronze batch that produced the winning row.
- `silver_source_system`, `silver_source_table_name`, `silver_source_record_id` — original source identity.

This answers: which Bronze row produced this Silver row, which batch loaded it, which source system and original record it came from.

## Standardized status values

Invoice status: `pending`, `partial_paid`, `paid`, `cancelled`, `void`, `refunded`
(source OPEN -> pending, PARTIAL -> partial_paid, PAID -> paid, VOID -> void).

Payment status: `pending`, `completed`, `failed`, `refunded`, `void`.

Customer status: `active`, `inactive`.

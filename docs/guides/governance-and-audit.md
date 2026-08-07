# Data Governance & Audit — How It Works

How PrintTimeUSA answers the governance questions an auditor actually asks: **who can touch the
data, what does each dataset mean, where did a value come from, what changed, when, and by which
run** — and where the boundaries of that answer are.

**Related:** [ADR-008](../adr/008-consolidate-etl-control-into-audit-schema.md) (audit schema),
[ADR-013](../adr/013-data-governance-and-pii.md) (governance & PII),
[ADR-019](../adr/019-least-privilege-database-roles.md) (RBAC),
[`docs/data_dictionary/`](../data_dictionary/), [`docs/backlog.md`](../backlog.md),
[CDC guide](cdc.md), [SCD guide](scd.md).

---

## 1. The `audit` schema — the single source of ETL truth

All control and lineage state lives in one schema (ADR-008), not scattered across the layers:

| Table | Purpose |
|---|---|
| **`audit.etl_batch_control`** | one row per (table, batch): `source_system`, `target_table`, `load_type`, `batch_status`, `rows_extracted/inserted/updated/deleted`, `watermark_value_start/end`, `batch_start/end_timestamp`, `error_message`, `initiated_by`. The **run registry** + the **watermark store**. |
| **`audit.audit_log`** | insert-only **row-level change trail** for the delete+insert facts: `operation_type`, `record_key`, `old_row`/`new_row` (JSONB), `changed_columns`, `change_reason`, `etl_batch_id`, `source_system`, `changed_by_app_user`. |

## 2. Provenance — "which run changed this, and when"

Every gold dimension and fact row carries **`etl_batch_id`**, which joins to
`audit.etl_batch_control.batch_id`. That's the durable link from any row back to the run that wrote
it:

```sql
SELECT d.row_version, d.valid_from, b.initiated_by, b.load_type, b.batch_start_timestamp
FROM   gold.dim_customer d
JOIN   audit.etl_batch_control b ON b.batch_id = d.etl_batch_id
WHERE  d.source_record_id = '1'
ORDER  BY d.row_version;
```

- **Dimensions** are self-documenting: the SCD2 version history *is* the change log (see the
  [SCD guide](scd.md) §8). No separate audit row is needed — the old version is retained in-table.
- **Facts** are delete+insert, so their old values would be lost on reload — `audit.audit_log`
  captures the before/after image of every replaced row (a pre-hook stages the before-image; a
  post-hook writes one complete insert-only row per change, pairing old→new by `source_record_id`).
  A row with no surviving fact = a `DELETE`; a rewrite with no business-column change gets a NULL
  `changed_columns` (it was reloaded as collateral of its invoice, unchanged).

## 3. Lineage — source to consumer

Row-level lineage columns exist at **every hop**, and every hop has a mapping doc
([`docs/source_to_dw_mapping/`](../source_to_dw_mapping/)):

```
OLTP.updated_at/source_updated_at
  → bronze.oltp_*  (bronze_batch_id, bronze_row_hash, bronze_raw_payload_jsonb)
    → silver.*     (silver_batch_id, silver_row_hash, silver_source_updated_at_timestamp)
      → gold.*     (etl_batch_id, record_hash, valid_from/valid_to)
        → gold.bi_* serving views
```

A gold metric is traceable back to the source column via the mapping docs + the dbt DAG
(`ref()`/`source()` dependencies).

## 4. Access control — least privilege (ADR-019)

No shared superuser for day-to-day work. Three **purpose-scoped roles** (`sql/security/001_…`):

| Role | Can | Cannot |
|---|---|---|
| `pt_ingestion` | write bronze + audit | touch silver/gold |
| `pt_dbt` | own/build silver + gold, read bronze | write bronze, TRUNCATE ingestion-owned tables |
| `pt_bi_reader` | read gold (+ BI views) | write anything, read raw bronze |

`warehouse_user` remains the break-glass superuser (admin / pgAdmin / backups only). This means a
compromised BI credential can't mutate the warehouse, and the ingestion job can't corrupt gold.

## 5. Metadata, definitions & decisions

| Artifact | What it governs |
|---|---|
| [`docs/data_dictionary/`](../data_dictionary/) | every column's meaning, allowed values, sensitivity (bronze/silver/gold/audit) |
| [`docs/adr/`](../adr/README.md) | 19 Architecture Decision Records — every significant choice, its alternatives, and accepted costs |
| [`docs/fix/fix_log.md`](../fix/fix_log.md) | bugs that bit us, root cause, and the *class of mistake* — so the same shape is recognizable next time |
| [`docs/backlog.md`](../backlog.md) | consciously deferred work + external limitations, each with a trigger-to-act |
| [`docs/audit/`](../audit/) | three independent external audits + a score trajectory |

## 6. PII & sensitivity (ADR-013)

Customer/employee `email` and `phone` are identified as CCPA-relevant PII in the gold dictionary and
ADR-013. **Identification is done; enforcement (masking / column grants / retention) is deferred**
(backlog #4, audit AUDIT-003-M3) — a documented gap, not an unknown one.

## 7. Observability — can we diagnose a failure?

`audit.etl_batch_control` answers *what failed, when, why, how many rows, and can we safely rerun*
(status + `error_message` + row counts + watermark). The current gap is **active** alerting: a
failure is visible in the audit table and the Airflow UI but nobody is paged (`email_on_failure =
false`; backlog / audit AUDIT-003-M1).

## 8. Known governance boundaries (documented, not hidden)

Good governance is also being honest about limits:

- **End-user ("who") attribution on dimensions is bounded by the source** (backlog #12). The DW
  attributes every change to the ETL run, and captures a *human* actor where the source records one
  (`*_status_history.changed_by`, `invoice_adjustment.adjusted_by`, `refund.refunded_by`). But the
  OLTP `customer`/`invoice` base tables have **no `updated_by` column**, so a generic field edit
  (name, total) can't be tied to a person — an **external, source-system** limitation the warehouse
  cannot solve alone.
- **PII masking, a secret manager, and a scheduled restore drill** are identified and deferred, not
  overlooked (see the [audit index](../audit/README.md)).

## 9. Quick governance queries

```sql
-- every run, newest first: what ran, when, status, rows, errors
SELECT source_system, target_table, load_type, batch_status,
       rows_inserted, batch_start_timestamp, error_message
FROM   audit.etl_batch_control
ORDER  BY batch_start_timestamp DESC LIMIT 20;

-- fact-level change trail: what changed, old→new, which batch, why
SELECT table_name, operation_type, record_key, changed_columns,
       change_reason, etl_batch_id, changed_at
FROM   audit.audit_log
ORDER  BY changed_at DESC LIMIT 20;
```

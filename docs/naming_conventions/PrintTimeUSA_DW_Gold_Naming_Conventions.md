# PrintTimeUSA Data Warehouse

## Gold Layer Naming Conventions and Dimensional Standards

| Field | Value |
|---|---|
| Document purpose | Editable standard for the Gold (curated dimensional) layer |
| Scope | Gold schema, table, column, key, and view naming conventions |
| Architecture | Medallion architecture (bronze → silver → **gold**) |
| Status | Working document |

### How to use this document

Use this as the official naming standard for the **Gold** layer. It extends the General, Bronze, and Silver standards in `PrintTimeUSA_DW_Naming_Conventions_Bronze_Silver.docx`. The General Naming Conventions (snake_case, English, singular entities, standard suffixes) still apply here — this document only documents what is **specific to Gold**.

> **Key difference from Silver:** Gold does **not** use a layer column prefix. Silver prefixes every column with `silver_`; Gold columns are **unprefixed** and follow Kimball dimensional conventions instead (`dim_`/`fact_` tables, `_key` surrogate keys, `_id` natural keys, role-playing `vw_` date views).

---

## 1. Gold Layer Purpose

| Gold Rule | Standard |
|---|---|
| Main purpose | Serve a curated, query-friendly **Kimball star schema** for analytics and BI. |
| Business logic level | Full dimensional modeling: surrogate keys, conformed dimensions, facts, derived measures. |
| Naming style | Kimball conventions: `dim_` / `fact_` table prefixes, unprefixed business columns. |
| Source dependency | Gold dimensions and facts are built from **Silver** tables. |
| Change tracking | SCD2 on dimensions (except static Type-1 lookups); facts are insert/refresh, no SCD2. |

---

## 2. Gold Table Naming Format

Gold tables use a Kimball type prefix plus a clean business entity name. No source-system prefix (`oltp_`, `csv_`) and no `silver_`/`gold_` prefix.

```
gold.dim_<entity>      -- dimension
gold.fact_<process>    -- fact (business process / event)
gold.vw_<role>_date    -- role-playing date view over dim_date
```

| Prefix | Meaning | Example |
|---|---|---|
| `dim_` | Dimension (descriptive context) | `gold.dim_customer`, `gold.dim_product` |
| `fact_` | Fact (measurements of a business process) | `gold.fact_retail_sales`, `gold.fact_payments` |
| `vw_` | Role-playing **view** over `dim_date` | `gold.vw_first_order_date` |

| Good Gold Table Name | Avoid | Reason |
|---|---|---|
| `gold.dim_customer` | `gold.gold_customer` | Gold uses Kimball prefixes, not a layer prefix. |
| `gold.fact_retail_sales` | `gold.retail_sales_fact` | Type prefix comes first (`fact_`), not as a suffix. |
| `gold.dim_date` | `gold.date_dim` | Prefix-first, singular entity. |

### 2.1 Tables in this project

**Dimensions (8):** `dim_date`, `dim_cashier`, `dim_product`, `dim_customer`, `dim_store`, `dim_invoice`, `dim_payment_method`, `dim_payment_type`
**Facts (3):** `fact_retail_sales` (grain: invoice line), `fact_payments` (grain: payment), `fact_customer_behavior_snapshot` (grain: customer × snapshot date)
**Role-playing date views (3):** `vw_first_order_date`, `vw_snapshot_date`, `vw_last_order_date`

---

## 3. Gold Key Naming

| Key Type | Gold Naming Standard | Example |
|---|---|---|
| Surrogate key (warehouse-generated) | `<entity>_key` | `customer_key`, `product_key`, `sales_line_key` |
| Natural / business key (from source) | `<entity>_id`, `*_code`, `*_number` | `customer_id`, `method_code`, `invoice_number` |
| Role-playing date key | `<role>_date_key` | `first_order_date_key`, `snapshot_date_key` |
| Degenerate dimension | business identifier carried on the fact | `invoice_number` on `fact_retail_sales` |

Rules:

- **Surrogate keys** end in `_key` and are `INTEGER GENERATED ALWAYS AS IDENTITY`, declared as the table `PRIMARY KEY`. They are meaningless integers owned by the warehouse.
- **`dim_date.date_key` is the exception**: a *smart* surrogate key in `YYYYMMDD` integer format (e.g. `20260115`), not identity-generated, so date roles and facts can derive it deterministically.
- **Natural/business keys** keep the source identifier and end in `_id` (or `_code` / `_number` where the business uses those terms). They are *not* the primary key in Gold.
- **Degenerate dimensions** (e.g. `invoice_number`) are business identifiers stored directly on a fact with no separate dimension row.
- **Facts reference dimensions** by the dimension's surrogate `_key` (e.g. `fact_payments.customer_key` → `dim_customer.customer_key`). These are logical foreign keys (indexed, not enforced with FK constraints, per warehouse load practice).

---

## 4. Gold Column Suffixes

Gold reuses the project-wide standard suffixes (no `gold_` prefix on any column):

| Meaning | Suffix | Example |
|---|---|---|
| Warehouse surrogate key | `_key` | `customer_key` |
| Source/business identifier | `_id` | `customer_id`, `store_id` |
| Date only | `_date` | `invoice_date`, `open_date` |
| Timestamp | `_timestamp` | `etl_load_timestamp` |
| Money | `_amount` | `sales_amount`, `payment_amount` |
| Quantity | `_qty` | `sales_qty` |
| Count | `_count` | `lifetime_order_count`, `open_invoice_count` |
| Percentage | `_pct` | (markup is `NUMERIC(8,4)`; `_pct` used where applicable) |
| Code value | `_code` | `method_code`, `type_code` |
| Name / label | `_name` | `customer_name`, `store_name` |
| Description | `_description` | `product_description`, `category_description` |
| Business number | `_number` | `invoice_number`, `sku_number`, `department_number` |
| Indicator (text Y/N or label) | `_indicator` | `weekday_indicator`, `local_made_indicator` |
| Hash value | `_hash` | `record_hash` |
| Boolean flag | `is_…` / `_flag` | `is_current`, `is_deleted`, `dq_issue_flag` |

> Note: a few descriptive **indicator** columns inherited from the source model are stored as short `VARCHAR` text (e.g. `last_day_in_month_indicator VARCHAR(3)`, `is_active VARCHAR(3)` on `dim_cashier`) rather than `BOOLEAN`. True/false governance columns use `BOOLEAN` (`is_current`, `is_deleted`, `dq_issue_flag`, etc.).

---

## 5. Standard Column Blocks (every dim/fact)

Every dimension and fact carries the following standard blocks **after** its business attributes, in this order. Individual exceptions are listed in Section 6.

### 5.1 Audit / lineage block
| Column | Type | Purpose |
|---|---|---|
| `source_system` | `VARCHAR(50)` | Originating source system. |
| `source_record_id` | `VARCHAR(100)` | Source business/record id, as text, for lineage. |
| `etl_batch_id` | `VARCHAR(50)` | Batch that created/updated the row (joins `audit.etl_batch_control.batch_id`). |
| `etl_load_timestamp` | `TIMESTAMP` | When the row was first loaded into Gold. |
| `etl_updated_timestamp` | `TIMESTAMP` | When the row was last updated in Gold. |

### 5.2 Record hash
| Column | Type | Purpose |
|---|---|---|
| `record_hash` | `CHAR(64)` | **SHA-256** hex digest of the dimension's tracked attributes. Drives SCD2 change detection. Fixed 64-char length = SHA-256. |

### 5.3 SCD2 block (dimensions only)
| Column | Type | Purpose |
|---|---|---|
| `valid_from` | `DATE` | Start of the row's validity window. |
| `valid_to` | `DATE` | End of the row's validity window (open = far-future / NULL). |
| `is_current` | `BOOLEAN` | `TRUE` for the active version of the business key. |
| `row_version` | `INTEGER` | Incrementing version number per business key (starts at 1). |

### 5.4 Data-quality (DQ) block
| Column | Type | Purpose |
|---|---|---|
| `is_complete` | `BOOLEAN` | All required attributes present. |
| `is_validated` | `BOOLEAN` | Passed validation rules. |
| `dq_issue_flag` | `BOOLEAN` | A data-quality issue was detected. |
| `dq_issue_description` | `VARCHAR(500)` | Human-readable issue description. |

### 5.5 Soft-delete block (dimensions only)
| Column | Type | Purpose |
|---|---|---|
| `is_deleted` | `BOOLEAN` | Logical delete marker. |
| `deleted_timestamp` | `TIMESTAMP` | When the row was logically deleted. |

### 5.6 Default value conventions
| Situation | Convention |
|---|---|
| Unknown / missing text attribute | `'Unknown'` |
| Unknown / missing dimension key (fact → dim) | `-1` (the "Unknown" dimension member) |
| `is_current` default | `TRUE` |
| `row_version` default | `1` |
| `is_deleted`, `is_validated`, `dq_issue_flag` defaults | `FALSE` |
| `is_complete` default | `TRUE` |
| `etl_load_timestamp`, `etl_updated_timestamp` defaults | `CURRENT_TIMESTAMP` |

---

## 6. Exceptions

These tables deliberately deviate from the standard blocks in Section 5:

| Table | Exception |
|---|---|
| `gold.dim_payment_type` | **Static Type-1 lookup.** No SCD2 block, no `record_hash`, no DQ block, and no audit block beyond `etl_load_timestamp` / `etl_updated_timestamp`. Carries only `is_deleted` for soft removal. Overwrite-in-place. |
| `gold.dim_date` | **Conformed calendar.** No `record_hash`, no SCD2 block, no soft-delete block, no `source_*` / `etl_batch_id`. Only `etl_load_timestamp` / `etl_updated_timestamp`. `date_key` is a `YYYYMMDD` smart key (not identity). |
| All `fact_` tables | **No SCD2 block and no soft-delete block.** Facts are insert/refresh by grain. They keep the audit block and the DQ block, but not `record_hash`, `valid_from/valid_to`, `is_current`, `row_version`, `is_deleted`, or `deleted_timestamp`. |

---

## 7. Role-Playing Date Views

`dim_date` is referenced multiple times in different roles. Instead of duplicating the calendar, each role is exposed as a **view** over `gold.dim_date` with role-prefixed column names.

| View | Role | Consumed by |
|---|---|---|
| `gold.vw_first_order_date` | First order date | `dim_customer.first_order_date_key` |
| `gold.vw_snapshot_date` | Snapshot date | `fact_customer_behavior_snapshot.snapshot_date_key` |
| `gold.vw_last_order_date` | Last order date | `fact_customer_behavior_snapshot.last_order_date_key` |

Each view re-labels every business calendar column with the role prefix (e.g. `date_key` → `first_order_date_key`, `calendar_year` → `first_order_calendar_year`). The two ETL timestamp columns are **not** re-exposed in the views.

---

## 8. Gold Layer Rules

| Gold can do | Gold should not do |
|---|---|
| Create final dimensions and facts | Land raw or lightly-cleaned source rows (that is Bronze) |
| Assign surrogate keys (`_key`) | Re-clean/standardize source values (that is Silver) |
| Apply SCD Type 2 on dimensions | Apply SCD2 to facts |
| Compute derived measures (e.g. `gross_profit`) | Store source-system prefixes in names |
| Build conformed `dim_date` + role-playing views | Mix governance/control tables into the Gold schema (use the `audit` schema) |
| Carry degenerate dimensions on facts (`invoice_number`) | Enforce hard FK constraints that block warehouse loads |

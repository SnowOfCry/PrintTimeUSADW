# Gold Data Dictionary

PrintTimeUSA Data Warehouse | Gold layer. Every column of every Gold table is documented. Gold uses Kimball conventions: `dim_`/`fact_` tables, surrogate keys (`_key`, identity), natural keys (`_id`/`_code`/`_number`), and **no** layer column prefix. See `docs/naming_conventions/PrintTimeUSA_DW_Gold_Naming_Conventions.md`.

**Classification legend:** `surrogate key` · `natural key` · `degenerate dimension` · `attribute` · `measure` · `governance` (audit/lineage + record_hash) · `SCD2` · `DQ` · `soft-delete`.

Tables: 8 dimensions + 3 facts (+ 3 role-playing date views over `dim_date`).

---

## gold.dim_date

- **Type:** conformed calendar dimension
- **Grain:** one row per calendar date
- **Source:** generated calendar
- **Notes:** `date_key` is a YYYYMMDD smart key; no `record_hash`/SCD2/soft-delete.

| Column | Data Type | Nullable | Default | Description | Classification |
|---|---|---|---|---|---|
| date_key | INTEGER | NOT NULL | — | YYYYMMDD smart surrogate key (e.g. 20260115). PK. | surrogate key |
| date | DATE | NOT NULL | — | Calendar date. | natural key |
| full_date_description | VARCHAR(50) | NULL | — | Full readable date (e.g. "January 15, 2026"). | attribute |
| day_of_week | VARCHAR(10) | NULL | — | Day name. | attribute |
| day_number_in_calendar_month | SMALLINT | NULL | — | Day of month (1–31). | attribute |
| last_day_in_month_indicator | VARCHAR(3) | NULL | — | 'Yes'/'No' last day of month. | attribute |
| calendar_week_ending_date | DATE | NULL | — | Week-ending date. | attribute |
| calendar_month_name | VARCHAR(10) | NULL | — | Month name. | attribute |
| calendar_month_number_in_year | SMALLINT | NULL | — | Month number (1–12). | attribute |
| calendar_quarter | SMALLINT | NULL | — | Quarter (1–4). | attribute |
| calendar_year_quarter | VARCHAR(7) | NULL | — | Year-quarter (e.g. "2026-Q1"). | attribute |
| calendar_year | SMALLINT | NULL | — | Year. | attribute |
| calendar_year_month | VARCHAR(7) | NULL | — | Year-month (e.g. "2026-01"). | attribute |
| holiday_indicator | VARCHAR(20) | NULL | — | Holiday label / 'None'. | attribute |
| weekday_indicator | VARCHAR(10) | NULL | — | 'Weekday'/'Weekend'. | attribute |
| etl_load_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | When the row was loaded. | governance |
| etl_updated_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | When the row was last updated. | governance |

## gold.dim_cashier

- **Type:** SCD2 dimension
- **Grain:** one row per cashier version
- **Source:** silver.employee (+ silver.store)
- **Natural key:** cashier_id

| Column | Data Type | Nullable | Default | Description | Classification |
|---|---|---|---|---|---|
| cashier_key | INTEGER | NOT NULL | identity | Surrogate key. PK. | surrogate key |
| cashier_id | VARCHAR(30) | NOT NULL | — | Cashier business key (employee code). | natural key |
| cashier_first_name | VARCHAR(50) | NULL | — | First name. | attribute |
| cashier_last_name | VARCHAR(50) | NULL | — | Last name. | attribute |
| cashier_full_name | VARCHAR(100) | NULL | — | Full name. | attribute |
| is_active | VARCHAR(3) | NULL | — | 'Yes'/'No' active indicator (text). | attribute |
| store_id | VARCHAR(30) | NULL | — | Home store business code. | attribute |
| store_name | VARCHAR(100) | NULL | — | Home store name. | attribute |
| record_hash | CHAR(64) | NULL | — | SHA-256 of tracked attributes (SCD2 change detection). | governance |
| source_system | VARCHAR(50) | NULL | — | Originating source system. | governance |
| source_record_id | VARCHAR(100) | NULL | — | Source record id (text). | governance |
| etl_batch_id | VARCHAR(50) | NULL | — | Load batch id. | governance |
| etl_load_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | First-load timestamp. | governance |
| etl_updated_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | Last-update timestamp. | governance |
| valid_from | DATE | NULL | — | SCD2 validity start. | SCD2 |
| valid_to | DATE | NULL | — | SCD2 validity end. | SCD2 |
| is_current | BOOLEAN | NOT NULL | TRUE | Current-version flag. | SCD2 |
| row_version | INTEGER | NOT NULL | 1 | Version number per business key. | SCD2 |
| is_complete | BOOLEAN | NOT NULL | TRUE | All required attributes present. | DQ |
| is_validated | BOOLEAN | NOT NULL | FALSE | Passed validation. | DQ |
| dq_issue_flag | BOOLEAN | NOT NULL | FALSE | DQ issue detected. | DQ |
| dq_issue_description | VARCHAR(500) | NULL | — | DQ issue description. | DQ |
| is_deleted | BOOLEAN | NOT NULL | FALSE | Logical delete marker. | soft-delete |
| deleted_timestamp | TIMESTAMP | NULL | — | Logical delete time. | soft-delete |

## gold.dim_product

- **Type:** SCD2 dimension
- **Grain:** one row per product version
- **Source:** silver.product (+ silver.product_category, silver.department)
- **Natural key:** sku_number

| Column | Data Type | Nullable | Default | Description | Classification |
|---|---|---|---|---|---|
| product_key | INTEGER | NOT NULL | identity | Surrogate key. PK. | surrogate key |
| sku_number | VARCHAR(50) | NOT NULL | — | Product SKU (business key). | natural key |
| product_description | VARCHAR(200) | NULL | — | Product description. | attribute |
| brand_description | VARCHAR(100) | NULL | — | Brand name. | attribute |
| category_description | VARCHAR(100) | NULL | — | Category description (lookup). | attribute |
| department_number | VARCHAR(20) | NULL | — | Department code (lookup). | attribute |
| department_description | VARCHAR(100) | NULL | — | Department description (lookup). | attribute |
| markup | NUMERIC(8,4) | NULL | — | Markup factor/percentage. | attribute |
| standard_price | NUMERIC(12,2) | NULL | — | Standard selling price. | attribute |
| local_made_indicator | VARCHAR(20) | NULL | — | Local-made label. | attribute |
| record_hash | CHAR(64) | NULL | — | SHA-256 of tracked attributes. | governance |
| source_system | VARCHAR(50) | NULL | — | Source system. | governance |
| source_record_id | VARCHAR(100) | NULL | — | Source record id (text). | governance |
| etl_batch_id | VARCHAR(50) | NULL | — | Load batch id. | governance |
| etl_load_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | First-load timestamp. | governance |
| etl_updated_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | Last-update timestamp. | governance |
| valid_from | DATE | NULL | — | SCD2 validity start. | SCD2 |
| valid_to | DATE | NULL | — | SCD2 validity end. | SCD2 |
| is_current | BOOLEAN | NOT NULL | TRUE | Current-version flag. | SCD2 |
| row_version | INTEGER | NOT NULL | 1 | Version number. | SCD2 |
| is_complete | BOOLEAN | NOT NULL | TRUE | Completeness flag. | DQ |
| is_validated | BOOLEAN | NOT NULL | FALSE | Validation flag. | DQ |
| dq_issue_flag | BOOLEAN | NOT NULL | FALSE | DQ issue flag. | DQ |
| dq_issue_description | VARCHAR(500) | NULL | — | DQ issue description. | DQ |
| is_deleted | BOOLEAN | NOT NULL | FALSE | Logical delete marker. | soft-delete |
| deleted_timestamp | TIMESTAMP | NULL | — | Logical delete time. | soft-delete |

## gold.dim_customer

- **Type:** SCD2 dimension
- **Grain:** one row per customer version
- **Source:** silver.customer (+ silver.customer_address, silver.state, gold.dim_date)
- **Natural key:** customer_id

| Column | Data Type | Nullable | Default | Description | Classification |
|---|---|---|---|---|---|
| customer_key | INTEGER | NOT NULL | identity | Surrogate key. PK. | surrogate key |
| customer_id | VARCHAR(30) | NOT NULL | — | Customer account number (business key). | natural key |
| customer_name | VARCHAR(100) | NULL | — | Display name. | attribute |
| customer_street_address | VARCHAR(200) | NULL | — | Primary street address (lookup). | attribute |
| customer_city | VARCHAR(100) | NULL | — | City (lookup). | attribute |
| customer_county | VARCHAR(100) | NULL | — | County. **No source — defaults to 'Not Provided' (gap).** | attribute |
| customer_state | VARCHAR(50) | NULL | — | State name (lookup). | attribute |
| customer_city_state | VARCHAR(150) | NULL | — | "City, ST" derived label. | attribute |
| first_order_date_key | INTEGER | NULL | — | Role-playing FK to dim_date (first order). | natural key |
| record_hash | CHAR(64) | NULL | — | SHA-256 of tracked attributes. | governance |
| source_system | VARCHAR(50) | NULL | — | Source system. | governance |
| source_record_id | VARCHAR(100) | NULL | — | Source record id (text). | governance |
| etl_batch_id | VARCHAR(50) | NULL | — | Load batch id. | governance |
| etl_load_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | First-load timestamp. | governance |
| etl_updated_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | Last-update timestamp. | governance |
| valid_from | DATE | NULL | — | SCD2 validity start. | SCD2 |
| valid_to | DATE | NULL | — | SCD2 validity end. | SCD2 |
| is_current | BOOLEAN | NOT NULL | TRUE | Current-version flag. | SCD2 |
| row_version | INTEGER | NOT NULL | 1 | Version number. | SCD2 |
| is_complete | BOOLEAN | NOT NULL | TRUE | Completeness flag. | DQ |
| is_validated | BOOLEAN | NOT NULL | FALSE | Validation flag. | DQ |
| dq_issue_flag | BOOLEAN | NOT NULL | FALSE | DQ issue flag. | DQ |
| dq_issue_description | VARCHAR(500) | NULL | — | DQ issue description. | DQ |
| is_deleted | BOOLEAN | NOT NULL | FALSE | Logical delete marker. | soft-delete |
| deleted_timestamp | TIMESTAMP | NULL | — | Logical delete time. | soft-delete |

## gold.dim_store

- **Type:** SCD2 dimension
- **Grain:** one row per store version
- **Source:** silver.store (+ silver.state)
- **Natural key:** store_id

| Column | Data Type | Nullable | Default | Description | Classification |
|---|---|---|---|---|---|
| store_key | INTEGER | NOT NULL | identity | Surrogate key. PK. | surrogate key |
| store_id | VARCHAR(30) | NOT NULL | — | Store business code. | natural key |
| store_name | VARCHAR(100) | NULL | — | Store name. | attribute |
| store_city | VARCHAR(100) | NULL | — | City. | attribute |
| store_state | VARCHAR(50) | NULL | — | State name (lookup). | attribute |
| store_region | VARCHAR(50) | NULL | — | Region. | attribute |
| store_type | VARCHAR(50) | NULL | — | Store type. | attribute |
| open_date | DATE | NULL | — | Store open date. | attribute |
| record_hash | CHAR(64) | NULL | — | SHA-256 of tracked attributes. | governance |
| source_system | VARCHAR(50) | NULL | — | Source system. | governance |
| source_record_id | VARCHAR(100) | NULL | — | Source record id (text). | governance |
| etl_batch_id | VARCHAR(50) | NULL | — | Load batch id. | governance |
| etl_load_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | First-load timestamp. | governance |
| etl_updated_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | Last-update timestamp. | governance |
| valid_from | DATE | NULL | — | SCD2 validity start. | SCD2 |
| valid_to | DATE | NULL | — | SCD2 validity end. | SCD2 |
| is_current | BOOLEAN | NOT NULL | TRUE | Current-version flag. | SCD2 |
| row_version | INTEGER | NOT NULL | 1 | Version number. | SCD2 |
| is_complete | BOOLEAN | NOT NULL | TRUE | Completeness flag. | DQ |
| is_validated | BOOLEAN | NOT NULL | FALSE | Validation flag. | DQ |
| dq_issue_flag | BOOLEAN | NOT NULL | FALSE | DQ issue flag. | DQ |
| dq_issue_description | VARCHAR(500) | NULL | — | DQ issue description. | DQ |
| is_deleted | BOOLEAN | NOT NULL | FALSE | Logical delete marker. | soft-delete |
| deleted_timestamp | TIMESTAMP | NULL | — | Logical delete time. | soft-delete |

## gold.dim_invoice

- **Type:** SCD2 dimension
- **Grain:** one row per invoice version
- **Source:** silver.invoice (+ silver.customer, silver.store)
- **Natural key:** invoice_number

| Column | Data Type | Nullable | Default | Description | Classification |
|---|---|---|---|---|---|
| invoice_key | INTEGER | NOT NULL | identity | Surrogate key. PK. | surrogate key |
| invoice_number | VARCHAR(30) | NOT NULL | — | Invoice number (business key). | natural key |
| invoice_date | DATE | NULL | — | Invoice date. | attribute |
| invoice_status | VARCHAR(20) | NULL | — | Invoice status. | attribute |
| invoice_total | NUMERIC(12,2) | NULL | — | Invoice total amount. | attribute |
| customer_id | VARCHAR(30) | NULL | — | Customer business key (lookup). | attribute |
| customer_name | VARCHAR(100) | NULL | — | Customer name (lookup). | attribute |
| store_id | VARCHAR(30) | NULL | — | Store code (lookup). | attribute |
| store_name | VARCHAR(100) | NULL | — | Store name (lookup). | attribute |
| record_hash | CHAR(64) | NULL | — | SHA-256 of tracked attributes. | governance |
| source_system | VARCHAR(50) | NULL | — | Source system. | governance |
| source_record_id | VARCHAR(100) | NULL | — | Source record id (text). | governance |
| etl_batch_id | VARCHAR(50) | NULL | — | Load batch id. | governance |
| etl_load_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | First-load timestamp. | governance |
| etl_updated_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | Last-update timestamp. | governance |
| valid_from | DATE | NULL | — | SCD2 validity start. | SCD2 |
| valid_to | DATE | NULL | — | SCD2 validity end. | SCD2 |
| is_current | BOOLEAN | NOT NULL | TRUE | Current-version flag. | SCD2 |
| row_version | INTEGER | NOT NULL | 1 | Version number. | SCD2 |
| is_complete | BOOLEAN | NOT NULL | TRUE | Completeness flag. | DQ |
| is_validated | BOOLEAN | NOT NULL | FALSE | Validation flag. | DQ |
| dq_issue_flag | BOOLEAN | NOT NULL | FALSE | DQ issue flag. | DQ |
| dq_issue_description | VARCHAR(500) | NULL | — | DQ issue description. | DQ |
| is_deleted | BOOLEAN | NOT NULL | FALSE | Logical delete marker. | soft-delete |
| deleted_timestamp | TIMESTAMP | NULL | — | Logical delete time. | soft-delete |

## gold.dim_payment_method

- **Type:** SCD2 dimension
- **Grain:** one row per payment method version
- **Source:** silver.payment_method
- **Natural key:** method_code

| Column | Data Type | Nullable | Default | Description | Classification |
|---|---|---|---|---|---|
| payment_method_key | INTEGER | NOT NULL | identity | Surrogate key. PK. | surrogate key |
| method_code | VARCHAR(20) | NOT NULL | — | Method code (business key). | natural key |
| method_name | VARCHAR(50) | NULL | — | Method name. | attribute |
| method_type | VARCHAR(30) | NULL | — | Method type (CASH/CARD/…). | attribute |
| is_active | BOOLEAN | NULL | — | Active flag. | attribute |
| record_hash | CHAR(64) | NULL | — | SHA-256 of tracked attributes. | governance |
| source_system | VARCHAR(50) | NULL | — | Source system. | governance |
| source_record_id | VARCHAR(100) | NULL | — | Source record id (text). | governance |
| etl_batch_id | VARCHAR(50) | NULL | — | Load batch id. | governance |
| etl_load_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | First-load timestamp. | governance |
| etl_updated_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | Last-update timestamp. | governance |
| valid_from | DATE | NULL | — | SCD2 validity start. | SCD2 |
| valid_to | DATE | NULL | — | SCD2 validity end. | SCD2 |
| is_current | BOOLEAN | NOT NULL | TRUE | Current-version flag. | SCD2 |
| row_version | INTEGER | NOT NULL | 1 | Version number. | SCD2 |
| is_complete | BOOLEAN | NOT NULL | TRUE | Completeness flag. | DQ |
| is_validated | BOOLEAN | NOT NULL | FALSE | Validation flag. | DQ |
| dq_issue_flag | BOOLEAN | NOT NULL | FALSE | DQ issue flag. | DQ |
| dq_issue_description | VARCHAR(500) | NULL | — | DQ issue description. | DQ |
| is_deleted | BOOLEAN | NOT NULL | FALSE | Logical delete marker. | soft-delete |
| deleted_timestamp | TIMESTAMP | NULL | — | Logical delete time. | soft-delete |

## gold.dim_payment_type

- **Type:** static Type-1 lookup dimension (no SCD2 / record_hash / DQ block)
- **Grain:** one row per payment type
- **Source:** silver.payment_type
- **Natural key:** type_code

| Column | Data Type | Nullable | Default | Description | Classification |
|---|---|---|---|---|---|
| payment_type_key | INTEGER | NOT NULL | identity | Surrogate key. PK. | surrogate key |
| type_code | VARCHAR(20) | NOT NULL | — | Type code (business key). | natural key |
| type_name | VARCHAR(50) | NULL | — | Type name. | attribute |
| description | VARCHAR(200) | NULL | — | Type description. | attribute |
| etl_load_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | First-load timestamp. | governance |
| etl_updated_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | Last-update timestamp. | governance |
| is_deleted | BOOLEAN | NOT NULL | FALSE | Logical delete marker. | soft-delete |

## gold.fact_retail_sales

- **Type:** transaction fact (no SCD2)
- **Grain:** one row per invoice line
- **Source:** silver.invoice_line (+ silver.invoice)

| Column | Data Type | Nullable | Default | Description | Classification |
|---|---|---|---|---|---|
| sales_line_key | INTEGER | NOT NULL | identity | Surrogate key. PK. | surrogate key |
| date_key | INTEGER | NULL | — | FK → dim_date (invoice date). | natural key |
| cashier_key | INTEGER | NULL | — | FK → dim_cashier. | natural key |
| product_key | INTEGER | NULL | — | FK → dim_product. | natural key |
| customer_key | INTEGER | NULL | — | FK → dim_customer. | natural key |
| store_key | INTEGER | NULL | — | FK → dim_store. | natural key |
| invoice_key | INTEGER | NULL | — | FK → dim_invoice. | natural key |
| invoice_number | VARCHAR(30) | NULL | — | Invoice number carried on the fact. | degenerate dimension |
| sales_qty | INTEGER | NULL | — | Quantity sold. | measure |
| unit_price | NUMERIC(12,2) | NULL | — | Unit price. | measure |
| unit_cost | NUMERIC(12,2) | NULL | — | Unit cost. | measure |
| sales_amount | NUMERIC(12,2) | NULL | — | Line sales amount. | measure |
| sales_cost | NUMERIC(12,2) | NULL | — | Line cost (qty × unit_cost). | measure |
| gross_profit | NUMERIC(12,2) | NULL | — | sales_amount − sales_cost. | measure |
| source_system | VARCHAR(50) | NULL | — | Source system. | governance |
| source_record_id | VARCHAR(100) | NULL | — | Source record id (text). | governance |
| etl_batch_id | VARCHAR(50) | NULL | — | Load batch id. | governance |
| etl_load_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | First-load timestamp. | governance |
| etl_updated_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | Last-update timestamp. | governance |
| is_complete | BOOLEAN | NOT NULL | TRUE | Completeness flag. | DQ |
| is_validated | BOOLEAN | NOT NULL | FALSE | Validation flag. | DQ |
| dq_issue_flag | BOOLEAN | NOT NULL | FALSE | DQ issue flag. | DQ |
| dq_issue_description | VARCHAR(500) | NULL | — | DQ issue description. | DQ |

## gold.fact_payments

- **Type:** transaction fact (no SCD2)
- **Grain:** one row per payment
- **Source:** silver.payment

| Column | Data Type | Nullable | Default | Description | Classification |
|---|---|---|---|---|---|
| payment_key | INTEGER | NOT NULL | identity | Surrogate key. PK. | surrogate key |
| invoice_key | INTEGER | NULL | — | FK → dim_invoice. | natural key |
| customer_key | INTEGER | NULL | — | FK → dim_customer. | natural key |
| payment_method_key | INTEGER | NULL | — | FK → dim_payment_method. | natural key |
| date_key | INTEGER | NULL | — | FK → dim_date (payment date). | natural key |
| payment_type_key | INTEGER | NULL | — | FK → dim_payment_type. | natural key |
| cashier_key | INTEGER | NULL | — | FK → dim_cashier. | natural key |
| store_key | INTEGER | NULL | — | FK → dim_store. | natural key |
| parent_payment_key | INTEGER | NULL | — | Self-FK → fact_payments (original payment). | natural key |
| payment_sequence_num | SMALLINT | NULL | — | Payment sequence (1=deposit, 2=balance…). | attribute |
| payment_amount | NUMERIC(12,2) | NULL | — | Gross payment amount. | measure |
| tax_amount | NUMERIC(12,2) | NULL | — | Tax portion. | measure |
| fee_amount | NUMERIC(12,2) | NULL | — | Fee portion. | measure |
| net_amount | NUMERIC(12,2) | NULL | — | Net amount applied. | measure |
| source_system | VARCHAR(50) | NULL | — | Source system. | governance |
| source_record_id | VARCHAR(100) | NULL | — | Source record id (text). | governance |
| etl_batch_id | VARCHAR(50) | NULL | — | Load batch id. | governance |
| etl_load_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | First-load timestamp. | governance |
| etl_updated_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | Last-update timestamp. | governance |
| is_complete | BOOLEAN | NOT NULL | TRUE | Completeness flag. | DQ |
| is_validated | BOOLEAN | NOT NULL | FALSE | Validation flag. | DQ |
| dq_issue_flag | BOOLEAN | NOT NULL | FALSE | DQ issue flag. | DQ |
| dq_issue_description | VARCHAR(500) | NULL | — | DQ issue description. | DQ |

## gold.fact_customer_behavior_snapshot

- **Type:** periodic snapshot fact (no SCD2)
- **Grain:** one row per customer per snapshot date
- **Source:** silver.customer + invoice/payment aggregates

| Column | Data Type | Nullable | Default | Description | Classification |
|---|---|---|---|---|---|
| snapshot_key | INTEGER | NOT NULL | identity | Surrogate key. PK. | surrogate key |
| snapshot_date_key | INTEGER | NULL | — | FK → dim_date (snapshot date). | natural key |
| customer_key | INTEGER | NULL | — | FK → dim_customer. | natural key |
| last_order_date_key | INTEGER | NULL | — | FK → dim_date (last order date). | natural key |
| lifetime_order_count | INTEGER | NULL | — | Lifetime order count. | measure |
| lifetime_sales_amount | NUMERIC(14,2) | NULL | — | Lifetime sales amount. | measure |
| orders_last_30_days | INTEGER | NULL | — | Orders in the last 30 days. | measure |
| avg_days_to_full_payment | NUMERIC(8,2) | NULL | — | Avg days to full payment. | measure |
| open_invoice_count | INTEGER | NULL | — | Open invoice count. | measure |
| open_invoice_total | NUMERIC(14,2) | NULL | — | Open invoice total. | measure |
| is_active_customer | BOOLEAN | NULL | — | Active customer flag (as of snapshot). | attribute |
| customer_status | VARCHAR(20) | NULL | — | Customer status. | attribute |
| source_system | VARCHAR(50) | NULL | — | Source system. | governance |
| source_record_id | VARCHAR(100) | NULL | — | Source record id (text). | governance |
| etl_batch_id | VARCHAR(50) | NULL | — | Load batch id. | governance |
| etl_load_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | First-load timestamp. | governance |
| etl_updated_timestamp | TIMESTAMP | NOT NULL | CURRENT_TIMESTAMP | Last-update timestamp. | governance |
| is_complete | BOOLEAN | NOT NULL | TRUE | Completeness flag. | DQ |
| is_validated | BOOLEAN | NOT NULL | FALSE | Validation flag. | DQ |
| dq_issue_flag | BOOLEAN | NOT NULL | FALSE | DQ issue flag. | DQ |
| dq_issue_description | VARCHAR(500) | NULL | — | DQ issue description. | DQ |

---

## Role-playing date views

These views re-label `gold.dim_date` (business calendar columns only) for each date role. Columns mirror `dim_date` with a role prefix.

| View | Key column | Role |
|---|---|---|
| gold.vw_first_order_date | first_order_date_key | First order date (dim_customer). |
| gold.vw_snapshot_date | snapshot_date_key | Snapshot date (fact_customer_behavior_snapshot). |
| gold.vw_last_order_date | last_order_date_key | Last order date (fact_customer_behavior_snapshot). |

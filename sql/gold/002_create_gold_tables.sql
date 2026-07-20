-- =====================================================================
-- PrintTimeUSA Data Warehouse | Gold Layer
-- 002_create_gold_tables.sql
-- Dimensions (dim_), facts (fact_), conformed dim_date, and role-playing
-- date views (vw_). Surrogate keys = <entity>_key (plain INTEGER, assigned by
-- dbt at load time — NOT a DB identity; see ADR-015 / decision #7. dbt owns
-- table creation, so the model generates the key: existing keys are preserved
-- from the current table, new rows get max(key)+offset. The -1 "Not Provided"
-- member is a literal row in the model, not a DB-seeded identity insert.)
-- Natural/business keys = <entity>_id / *_code / *_number.
-- Standard column blocks: audit, record_hash (SHA-256), SCD2, DQ, soft-delete.
-- Exceptions: dim_date has no record_hash/SCD2/soft-delete; dim_payment_type
-- is a static Type-1 lookup (no SCD2); facts carry no SCD2 columns.
-- =====================================================================

SET search_path = gold, public;


-- ---------------------------------------------------------------------
-- gold.dim_date
-- Source: generated (calendar), referenced via vw_ role-playing views.
-- Grain: one row per calendar date. date_key is a smart key (YYYYMMDD).
-- No record_hash / SCD2 / soft-delete (static conformed calendar).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gold.dim_date (
    date_key INTEGER NOT NULL,
    date DATE NOT NULL,
    full_date_description VARCHAR(50),
    day_of_week VARCHAR(10),
    day_number_in_calendar_month SMALLINT,
    last_day_in_month_indicator VARCHAR(3),
    calendar_week_ending_date DATE,
    calendar_month_name VARCHAR(10),
    calendar_month_number_in_year SMALLINT,
    calendar_quarter SMALLINT,
    calendar_year_quarter VARCHAR(7),
    calendar_year SMALLINT,
    calendar_year_month VARCHAR(7),
    holiday_indicator VARCHAR(20),
    weekday_indicator VARCHAR(10),
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    etl_updated_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_dim_date PRIMARY KEY (date_key)
);
COMMENT ON TABLE gold.dim_date IS 'Conformed calendar dimension. Grain: one row per date. date_key is a YYYYMMDD smart key. Referenced directly and through role-playing date views.';
COMMENT ON COLUMN gold.dim_date.date_key IS 'Smart surrogate key in YYYYMMDD format (e.g. 20260115).';
COMMENT ON COLUMN gold.dim_date.date IS 'Calendar date (natural key).';

-- ---------------------------------------------------------------------
-- gold.dim_cashier
-- Source: silver.employee (+ silver.store labels).
-- SCD2 dimension. Natural key: cashier_id.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gold.dim_cashier (
    cashier_key INTEGER,
    cashier_id VARCHAR(30) NOT NULL,
    cashier_first_name VARCHAR(50),
    cashier_last_name VARCHAR(50),
    cashier_full_name VARCHAR(100),
    is_active VARCHAR(3),
    store_id VARCHAR(30),
    store_name VARCHAR(100),
    record_hash CHAR(64),
    source_system VARCHAR(50),
    source_record_id VARCHAR(100),
    etl_batch_id VARCHAR(50),
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    etl_updated_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_from DATE,
    valid_to DATE,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    row_version INTEGER NOT NULL DEFAULT 1,
    is_complete BOOLEAN NOT NULL DEFAULT TRUE,
    is_validated BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_flag BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_description VARCHAR(500),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_timestamp TIMESTAMP,
    CONSTRAINT pk_dim_cashier PRIMARY KEY (cashier_key)
);
COMMENT ON TABLE gold.dim_cashier IS 'Cashier/sales-rep dimension (SCD2). Built from silver.employee with store labels from silver.store.';
COMMENT ON COLUMN gold.dim_cashier.cashier_key IS 'Surrogate key (dbt-managed integer; see ADR-015).';
COMMENT ON COLUMN gold.dim_cashier.cashier_id IS 'Natural/business key from source (employee_code).';
COMMENT ON COLUMN gold.dim_cashier.record_hash IS 'SHA-256 of tracked attributes; drives SCD2 change detection.';

-- ---------------------------------------------------------------------
-- gold.dim_product
-- Source: silver.product (+ silver.product_category, silver.department).
-- SCD2 dimension. Natural key: sku_number.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gold.dim_product (
    product_key INTEGER,
    sku_number VARCHAR(50) NOT NULL,
    product_description VARCHAR(200),
    brand_description VARCHAR(100),
    category_description VARCHAR(100),
    department_number VARCHAR(20),
    department_description VARCHAR(100),
    markup NUMERIC(8,4),
    standard_price NUMERIC(12,2),
    local_made_indicator VARCHAR(20),
    record_hash CHAR(64),
    source_system VARCHAR(50),
    source_record_id VARCHAR(100),
    etl_batch_id VARCHAR(50),
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    etl_updated_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_from DATE,
    valid_to DATE,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    row_version INTEGER NOT NULL DEFAULT 1,
    is_complete BOOLEAN NOT NULL DEFAULT TRUE,
    is_validated BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_flag BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_description VARCHAR(500),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_timestamp TIMESTAMP,
    CONSTRAINT pk_dim_product PRIMARY KEY (product_key)
);
COMMENT ON TABLE gold.dim_product IS 'Product dimension (SCD2). Built from silver.product enriched with category and department descriptions.';
COMMENT ON COLUMN gold.dim_product.product_key IS 'Surrogate key (dbt-managed integer; see ADR-015).';
COMMENT ON COLUMN gold.dim_product.sku_number IS 'Natural/business key from source (product SKU).';
COMMENT ON COLUMN gold.dim_product.record_hash IS 'SHA-256 of tracked attributes; drives SCD2 change detection.';

-- ---------------------------------------------------------------------
-- gold.dim_customer
-- Source: silver.customer (+ silver.customer_address, silver.state).
-- SCD2 dimension. Natural key: customer_id.
-- NOTE: customer_county has no OLTP/Bronze/Silver source (gap; see mapping).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gold.dim_customer (
    customer_key INTEGER,
    customer_id VARCHAR(30) NOT NULL,
    customer_name VARCHAR(100),
    customer_street_address VARCHAR(200),
    customer_city VARCHAR(100),
    customer_county VARCHAR(100),
    customer_state VARCHAR(50),
    customer_city_state VARCHAR(150),
    first_order_date_key INTEGER,
    record_hash CHAR(64),
    source_system VARCHAR(50),
    source_record_id VARCHAR(100),
    etl_batch_id VARCHAR(50),
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    etl_updated_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_from DATE,
    valid_to DATE,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    row_version INTEGER NOT NULL DEFAULT 1,
    is_complete BOOLEAN NOT NULL DEFAULT TRUE,
    is_validated BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_flag BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_description VARCHAR(500),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_timestamp TIMESTAMP,
    CONSTRAINT pk_dim_customer PRIMARY KEY (customer_key)
);
COMMENT ON TABLE gold.dim_customer IS 'Customer dimension (SCD2). Built from silver.customer with address/state enrichment. customer_county currently has no source (gap).';
COMMENT ON COLUMN gold.dim_customer.customer_key IS 'Surrogate key (dbt-managed integer; see ADR-015).';
COMMENT ON COLUMN gold.dim_customer.customer_id IS 'Natural/business key from source (customer_account_no).';
COMMENT ON COLUMN gold.dim_customer.customer_county IS 'County of customer. No source in OLTP/Bronze/Silver; populated as Unknown until a source is added.';
COMMENT ON COLUMN gold.dim_customer.first_order_date_key IS 'Role-playing FK to dim_date (first order date).';
COMMENT ON COLUMN gold.dim_customer.record_hash IS 'SHA-256 of tracked attributes; drives SCD2 change detection.';

-- ---------------------------------------------------------------------
-- gold.dim_store
-- Source: silver.store (+ silver.state).
-- SCD2 dimension. Natural key: store_id.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gold.dim_store (
    store_key INTEGER,
    store_id VARCHAR(30) NOT NULL,
    store_name VARCHAR(100),
    store_city VARCHAR(100),
    store_state VARCHAR(50),
    store_region VARCHAR(50),
    store_type VARCHAR(50),
    open_date DATE,
    record_hash CHAR(64),
    source_system VARCHAR(50),
    source_record_id VARCHAR(100),
    etl_batch_id VARCHAR(50),
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    etl_updated_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_from DATE,
    valid_to DATE,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    row_version INTEGER NOT NULL DEFAULT 1,
    is_complete BOOLEAN NOT NULL DEFAULT TRUE,
    is_validated BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_flag BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_description VARCHAR(500),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_timestamp TIMESTAMP,
    CONSTRAINT pk_dim_store PRIMARY KEY (store_key)
);
COMMENT ON TABLE gold.dim_store IS 'Store/location dimension (SCD2). Built from silver.store with state enrichment.';
COMMENT ON COLUMN gold.dim_store.store_key IS 'Surrogate key (dbt-managed integer; see ADR-015).';
COMMENT ON COLUMN gold.dim_store.store_id IS 'Natural/business key from source (store_code).';
COMMENT ON COLUMN gold.dim_store.record_hash IS 'SHA-256 of tracked attributes; drives SCD2 change detection.';

-- ---------------------------------------------------------------------
-- gold.dim_invoice
-- Source: silver.invoice (+ silver.customer, silver.store labels).
-- SCD2 dimension. Natural key: invoice_number.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gold.dim_invoice (
    invoice_key INTEGER,
    invoice_number VARCHAR(30) NOT NULL,
    invoice_date DATE,
    invoice_status VARCHAR(20),
    invoice_total NUMERIC(12,2),
    customer_id VARCHAR(30),
    customer_name VARCHAR(100),
    store_id VARCHAR(30),
    store_name VARCHAR(100),
    record_hash CHAR(64),
    source_system VARCHAR(50),
    source_record_id VARCHAR(100),
    etl_batch_id VARCHAR(50),
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    etl_updated_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_from DATE,
    valid_to DATE,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    row_version INTEGER NOT NULL DEFAULT 1,
    is_complete BOOLEAN NOT NULL DEFAULT TRUE,
    is_validated BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_flag BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_description VARCHAR(500),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_timestamp TIMESTAMP,
    CONSTRAINT pk_dim_invoice PRIMARY KEY (invoice_key)
);
COMMENT ON TABLE gold.dim_invoice IS 'Invoice dimension (SCD2). Built from silver.invoice with customer/store labels. Header-grain attributes for the sales/payments facts.';
COMMENT ON COLUMN gold.dim_invoice.invoice_key IS 'Surrogate key (dbt-managed integer; see ADR-015).';
COMMENT ON COLUMN gold.dim_invoice.invoice_number IS 'Natural/business key from source (invoice number).';
COMMENT ON COLUMN gold.dim_invoice.record_hash IS 'SHA-256 of tracked attributes; drives SCD2 change detection.';

-- ---------------------------------------------------------------------
-- gold.dim_payment_method
-- Source: silver.payment_method.
-- SCD2 dimension. Natural key: method_code.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gold.dim_payment_method (
    payment_method_key INTEGER,
    method_code VARCHAR(20) NOT NULL,
    method_name VARCHAR(50),
    method_type VARCHAR(30),
    is_active BOOLEAN,
    record_hash CHAR(64),
    source_system VARCHAR(50),
    source_record_id VARCHAR(100),
    etl_batch_id VARCHAR(50),
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    etl_updated_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_from DATE,
    valid_to DATE,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    row_version INTEGER NOT NULL DEFAULT 1,
    is_complete BOOLEAN NOT NULL DEFAULT TRUE,
    is_validated BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_flag BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_description VARCHAR(500),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_timestamp TIMESTAMP,
    CONSTRAINT pk_dim_payment_method PRIMARY KEY (payment_method_key)
);
COMMENT ON TABLE gold.dim_payment_method IS 'Payment method dimension (SCD2). Built from silver.payment_method.';
COMMENT ON COLUMN gold.dim_payment_method.payment_method_key IS 'Surrogate key (dbt-managed integer; see ADR-015).';
COMMENT ON COLUMN gold.dim_payment_method.method_code IS 'Natural/business key from source (method code).';
COMMENT ON COLUMN gold.dim_payment_method.record_hash IS 'SHA-256 of tracked attributes; drives SCD2 change detection.';

-- ---------------------------------------------------------------------
-- gold.dim_payment_type
-- Source: silver.payment_type.
-- STATIC TYPE-1 lookup: no SCD2, no record_hash, no DQ block, no soft-delete
-- beyond is_deleted. Natural key: type_code.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gold.dim_payment_type (
    payment_type_key INTEGER,
    type_code VARCHAR(20) NOT NULL,
    type_name VARCHAR(50),
    description VARCHAR(200),
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    etl_updated_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_dim_payment_type PRIMARY KEY (payment_type_key)
);
COMMENT ON TABLE gold.dim_payment_type IS 'Payment type dimension. Static Type-1 lookup (overwrite-in-place); no SCD2/record_hash/DQ block by design.';
COMMENT ON COLUMN gold.dim_payment_type.payment_type_key IS 'Surrogate key (dbt-managed integer; see ADR-015).';
COMMENT ON COLUMN gold.dim_payment_type.type_code IS 'Natural/business key from source (type code).';

-- ---------------------------------------------------------------------
-- gold.fact_retail_sales
-- Grain: one row per invoice line. Source: silver.invoice_line (+ invoice).
-- No SCD2 columns. invoice_number is a degenerate dimension.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gold.fact_retail_sales (
    sales_line_key INTEGER,
    date_key INTEGER,
    cashier_key INTEGER,
    product_key INTEGER,
    customer_key INTEGER,
    store_key INTEGER,
    invoice_key INTEGER,
    invoice_number VARCHAR(30),
    sales_qty INTEGER,
    unit_price NUMERIC(12,2),
    unit_cost NUMERIC(12,2),
    sales_amount NUMERIC(12,2),
    sales_cost NUMERIC(12,2),
    gross_profit NUMERIC(12,2),
    source_system VARCHAR(50),
    source_record_id VARCHAR(100),
    etl_batch_id VARCHAR(50),
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    etl_updated_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_complete BOOLEAN NOT NULL DEFAULT TRUE,
    is_validated BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_flag BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_description VARCHAR(500),
    CONSTRAINT pk_fact_retail_sales PRIMARY KEY (sales_line_key)
);
COMMENT ON TABLE gold.fact_retail_sales IS 'Retail sales fact. Grain: one row per invoice line. Built from silver.invoice_line. invoice_number is a degenerate dimension.';
COMMENT ON COLUMN gold.fact_retail_sales.sales_line_key IS 'Surrogate key (dbt-managed integer; see ADR-015).';
COMMENT ON COLUMN gold.fact_retail_sales.invoice_number IS 'Degenerate dimension (invoice number carried on the fact).';
COMMENT ON COLUMN gold.fact_retail_sales.gross_profit IS 'Derived measure: sales_amount - sales_cost.';

-- ---------------------------------------------------------------------
-- gold.fact_payments
-- Grain: one row per payment. Source: silver.payment (+ refund chain).
-- No SCD2 columns. parent_payment_key self-references the fact.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gold.fact_payments (
    payment_key INTEGER,
    invoice_key INTEGER,
    customer_key INTEGER,
    payment_method_key INTEGER,
    date_key INTEGER,
    payment_type_key INTEGER,
    cashier_key INTEGER,
    store_key INTEGER,
    parent_payment_key INTEGER,
    payment_sequence_num SMALLINT,
    payment_amount NUMERIC(12,2),
    tax_amount NUMERIC(12,2),
    fee_amount NUMERIC(12,2),
    net_amount NUMERIC(12,2),
    source_system VARCHAR(50),
    source_record_id VARCHAR(100),
    etl_batch_id VARCHAR(50),
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    etl_updated_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_complete BOOLEAN NOT NULL DEFAULT TRUE,
    is_validated BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_flag BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_description VARCHAR(500),
    CONSTRAINT pk_fact_payments PRIMARY KEY (payment_key)
);
COMMENT ON TABLE gold.fact_payments IS 'Payments fact. Grain: one row per payment. Built from silver.payment. parent_payment_key links refunds/adjustments to the original payment.';
COMMENT ON COLUMN gold.fact_payments.payment_key IS 'Surrogate key (dbt-managed integer; see ADR-015).';
COMMENT ON COLUMN gold.fact_payments.parent_payment_key IS 'Self-referencing FK to fact_payments.payment_key (original payment for a refund/adjustment).';

-- ---------------------------------------------------------------------
-- gold.fact_customer_behavior_snapshot
-- Grain: one row per customer per snapshot date (periodic snapshot).
-- Source: silver.customer + invoice/payment aggregates.
-- No SCD2 columns.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gold.fact_customer_behavior_snapshot (
    snapshot_key INTEGER,
    snapshot_date_key INTEGER,
    customer_key INTEGER,
    last_order_date_key INTEGER,
    lifetime_order_count INTEGER,
    lifetime_sales_amount NUMERIC(14,2),
    orders_last_30_days INTEGER,
    avg_days_to_full_payment NUMERIC(8,2),
    open_invoice_count INTEGER,
    open_invoice_total NUMERIC(14,2),
    is_active_customer BOOLEAN,
    customer_status VARCHAR(20),
    source_system VARCHAR(50),
    source_record_id VARCHAR(100),
    etl_batch_id VARCHAR(50),
    etl_load_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    etl_updated_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_complete BOOLEAN NOT NULL DEFAULT TRUE,
    is_validated BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_flag BOOLEAN NOT NULL DEFAULT FALSE,
    dq_issue_description VARCHAR(500),
    CONSTRAINT pk_fact_customer_behavior_snapshot PRIMARY KEY (snapshot_key)
);
COMMENT ON TABLE gold.fact_customer_behavior_snapshot IS 'Customer behavior periodic-snapshot fact. Grain: one row per customer per snapshot date. Derived from silver.customer plus invoice/payment aggregates.';
COMMENT ON COLUMN gold.fact_customer_behavior_snapshot.snapshot_key IS 'Surrogate key (dbt-managed integer; see ADR-015).';
COMMENT ON COLUMN gold.fact_customer_behavior_snapshot.snapshot_date_key IS 'Role-playing FK to dim_date (snapshot date).';
COMMENT ON COLUMN gold.fact_customer_behavior_snapshot.last_order_date_key IS 'Role-playing FK to dim_date (last order date).';


-- =====================================================================
-- Role-playing date views over gold.dim_date
-- Each view re-labels dim_date for a specific date role used by the model.
-- (Business calendar columns only; ETL timestamps are not re-exposed.)
-- =====================================================================

-- gold.vw_first_order_date — first order date role (used by dim_customer)
CREATE OR REPLACE VIEW gold.vw_first_order_date AS
SELECT
    date_key                      AS first_order_date_key,
    date                          AS first_order_date,
    full_date_description         AS first_order_full_date_description,
    day_of_week                   AS first_order_day_of_week,
    day_number_in_calendar_month  AS first_order_day_number_in_calendar_month,
    last_day_in_month_indicator   AS first_order_last_day_in_month_indicator,
    calendar_week_ending_date     AS first_order_calendar_week_ending_date,
    calendar_month_name           AS first_order_calendar_month_name,
    calendar_month_number_in_year AS first_order_calendar_month_number_in_year,
    calendar_quarter              AS first_order_calendar_quarter,
    calendar_year_quarter         AS first_order_calendar_year_quarter,
    calendar_year                 AS first_order_calendar_year,
    calendar_year_month           AS first_order_calendar_year_month,
    holiday_indicator             AS first_order_holiday_indicator,
    weekday_indicator             AS first_order_weekday_indicator
FROM gold.dim_date;
COMMENT ON VIEW gold.vw_first_order_date IS 'Role-playing date view: first order date. Re-labels gold.dim_date.';

-- gold.vw_snapshot_date — snapshot date role (used by fact_customer_behavior_snapshot)
CREATE OR REPLACE VIEW gold.vw_snapshot_date AS
SELECT
    date_key                      AS snapshot_date_key,
    date                          AS snapshot_date,
    full_date_description         AS snapshot_full_date_description,
    day_of_week                   AS snapshot_day_of_week,
    day_number_in_calendar_month  AS snapshot_day_number_in_calendar_month,
    last_day_in_month_indicator   AS snapshot_last_day_in_month_indicator,
    calendar_week_ending_date     AS snapshot_calendar_week_ending_date,
    calendar_month_name           AS snapshot_calendar_month_name,
    calendar_month_number_in_year AS snapshot_calendar_month_number_in_year,
    calendar_quarter              AS snapshot_calendar_quarter,
    calendar_year_quarter         AS snapshot_calendar_year_quarter,
    calendar_year                 AS snapshot_calendar_year,
    calendar_year_month           AS snapshot_calendar_year_month,
    holiday_indicator             AS snapshot_holiday_indicator,
    weekday_indicator             AS snapshot_weekday_indicator
FROM gold.dim_date;
COMMENT ON VIEW gold.vw_snapshot_date IS 'Role-playing date view: snapshot date. Re-labels gold.dim_date.';

-- gold.vw_last_order_date — last order date role (used by fact_customer_behavior_snapshot)
CREATE OR REPLACE VIEW gold.vw_last_order_date AS
SELECT
    date_key                      AS last_order_date_key,
    date                          AS last_order_date,
    full_date_description         AS last_order_full_date_description,
    day_of_week                   AS last_order_day_of_week,
    day_number_in_calendar_month  AS last_order_day_number_in_calendar_month,
    last_day_in_month_indicator   AS last_order_last_day_in_month_indicator,
    calendar_week_ending_date     AS last_order_calendar_week_ending_date,
    calendar_month_name           AS last_order_calendar_month_name,
    calendar_month_number_in_year AS last_order_calendar_month_number_in_year,
    calendar_quarter              AS last_order_calendar_quarter,
    calendar_year_quarter         AS last_order_calendar_year_quarter,
    calendar_year                 AS last_order_calendar_year,
    calendar_year_month           AS last_order_calendar_year_month,
    holiday_indicator             AS last_order_holiday_indicator,
    weekday_indicator             AS last_order_weekday_indicator
FROM gold.dim_date;
COMMENT ON VIEW gold.vw_last_order_date IS 'Role-playing date view: last order date. Re-labels gold.dim_date.';

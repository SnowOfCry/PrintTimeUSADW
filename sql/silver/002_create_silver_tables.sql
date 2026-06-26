-- =====================================================================
-- PrintTimeUSA Data Warehouse | Silver Layer
-- 002_create_silver_tables.sql
-- Business key = silver_<entity>_id (PK / merge key). All columns silver_-prefixed.
-- =====================================================================

SET search_path = silver, public;


-- ---------------------------------------------------------------------
-- silver.customer
-- Source: bronze.oltp_customer
-- Purpose: Clean current version of each customer. Feeds gold.dim_customer and customer attributes for fact_customer_behavior_snapshot.
-- Business key: silver_customer_id
-- Load: incremental_merge
-- Supports: gold.dim_customer, gold.fact_customer_behavior_snapshot
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.customer (
    silver_customer_id BIGINT NOT NULL,
    silver_customer_account_no VARCHAR(30),
    silver_business_name VARCHAR(255),
    silver_first_name VARCHAR(100),
    silver_last_name VARCHAR(100),
    silver_customer_name VARCHAR(255),
    silver_email VARCHAR(255),
    silver_phone_number VARCHAR(50),
    silver_customer_status VARCHAR(20),
    silver_is_active_flag BOOLEAN,
    silver_default_tax_rate_id BIGINT,
    silver_home_store_id BIGINT,
    silver_first_order_date DATE,
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_customer PRIMARY KEY (silver_customer_id)
);
COMMENT ON TABLE silver.customer IS 'Clean current version of each customer. Feeds gold.dim_customer and customer attributes for fact_customer_behavior_snapshot.';
COMMENT ON COLUMN silver.customer.silver_customer_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.customer.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.customer_address
-- Source: bronze.oltp_customer_address
-- Purpose: Clean current version of each customer address. Supplies address enrichment to gold.dim_customer.
-- Business key: silver_address_id
-- Load: incremental_merge
-- Supports: gold.dim_customer
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.customer_address (
    silver_address_id BIGINT NOT NULL,
    silver_customer_id BIGINT,
    silver_address_type VARCHAR(20),
    silver_street_address_line_1 VARCHAR(200),
    silver_street_address_line_2 VARCHAR(100),
    silver_city VARCHAR(100),
    silver_state_code VARCHAR(2),
    silver_zip_code VARCHAR(10),
    silver_is_primary_flag BOOLEAN,
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_customer_address PRIMARY KEY (silver_address_id)
);
COMMENT ON TABLE silver.customer_address IS 'Clean current version of each customer address. Supplies address enrichment to gold.dim_customer.';
COMMENT ON COLUMN silver.customer_address.silver_address_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.customer_address.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.product
-- Source: bronze.oltp_product
-- Purpose: Clean current version of each product. Feeds gold.dim_product and product attributes for fact_retail_sales.
-- Business key: silver_product_id
-- Load: incremental_merge
-- Supports: gold.dim_product, gold.fact_retail_sales
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.product (
    silver_product_id BIGINT NOT NULL,
    silver_product_sku VARCHAR(50),
    silver_product_name VARCHAR(255),
    silver_product_description TEXT,
    silver_department_id BIGINT,
    silver_category_id BIGINT,
    silver_brand_name VARCHAR(100),
    silver_standard_cost_amount NUMERIC(18,2),
    silver_markup_pct NUMERIC(8,4),
    silver_standard_price_amount NUMERIC(18,2),
    silver_is_local_made_flag BOOLEAN,
    silver_is_active_flag BOOLEAN,
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_product PRIMARY KEY (silver_product_id)
);
COMMENT ON TABLE silver.product IS 'Clean current version of each product. Feeds gold.dim_product and product attributes for fact_retail_sales.';
COMMENT ON COLUMN silver.product.silver_product_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.product.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.product_category
-- Source: bronze.oltp_product_category
-- Purpose: Clean product category lookup. Supplies category_description and department link for gold.dim_product.
-- Business key: silver_category_id
-- Load: incremental_merge
-- Supports: gold.dim_product
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.product_category (
    silver_category_id BIGINT NOT NULL,
    silver_department_id BIGINT,
    silver_category_code VARCHAR(40),
    silver_category_name VARCHAR(100),
    silver_category_description VARCHAR(200),
    silver_is_active_flag BOOLEAN,
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_product_category PRIMARY KEY (silver_category_id)
);
COMMENT ON TABLE silver.product_category IS 'Clean product category lookup. Supplies category_description and department link for gold.dim_product.';
COMMENT ON COLUMN silver.product_category.silver_category_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.product_category.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.department
-- Source: bronze.oltp_department
-- Purpose: Clean department lookup (SIGNS, EMB, DTF, PRINT). Supplies department number/description for gold.dim_product.
-- Business key: silver_department_id
-- Load: incremental_merge
-- Supports: gold.dim_product
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.department (
    silver_department_id BIGINT NOT NULL,
    silver_department_code VARCHAR(20),
    silver_department_name VARCHAR(100),
    silver_department_description VARCHAR(200),
    silver_is_active_flag BOOLEAN,
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_department PRIMARY KEY (silver_department_id)
);
COMMENT ON TABLE silver.department IS 'Clean department lookup (SIGNS, EMB, DTF, PRINT). Supplies department number/description for gold.dim_product.';
COMMENT ON COLUMN silver.department.silver_department_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.department.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.employee
-- Source: bronze.oltp_employee
-- Purpose: Clean current version of each employee. Feeds gold.dim_cashier.
-- Business key: silver_employee_id
-- Load: incremental_merge
-- Supports: gold.dim_cashier
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.employee (
    silver_employee_id BIGINT NOT NULL,
    silver_employee_code VARCHAR(30),
    silver_first_name VARCHAR(100),
    silver_last_name VARCHAR(100),
    silver_full_name VARCHAR(200),
    silver_email VARCHAR(255),
    silver_phone_number VARCHAR(50),
    silver_role VARCHAR(30),
    silver_store_id BIGINT,
    silver_hire_date DATE,
    silver_is_active_flag BOOLEAN,
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_employee PRIMARY KEY (silver_employee_id)
);
COMMENT ON TABLE silver.employee IS 'Clean current version of each employee. Feeds gold.dim_cashier.';
COMMENT ON COLUMN silver.employee.silver_employee_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.employee.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.store
-- Source: bronze.oltp_store
-- Purpose: Clean current version of each store/location. Feeds gold.dim_store and store labels in dim_cashier/dim_invoice.
-- Business key: silver_store_id
-- Load: incremental_merge
-- Supports: gold.dim_store, gold.dim_cashier, gold.dim_invoice
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.store (
    silver_store_id BIGINT NOT NULL,
    silver_store_code VARCHAR(30),
    silver_store_name VARCHAR(100),
    silver_street_address VARCHAR(200),
    silver_city VARCHAR(100),
    silver_state_code VARCHAR(2),
    silver_zip_code VARCHAR(10),
    silver_phone_number VARCHAR(50),
    silver_region VARCHAR(50),
    silver_store_type VARCHAR(50),
    silver_open_date DATE,
    silver_is_active_flag BOOLEAN,
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_store PRIMARY KEY (silver_store_id)
);
COMMENT ON TABLE silver.store IS 'Clean current version of each store/location. Feeds gold.dim_store and store labels in dim_cashier/dim_invoice.';
COMMENT ON COLUMN silver.store.silver_store_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.store.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.invoice
-- Source: bronze.oltp_invoice
-- Purpose: Clean current state of each invoice (latest status). Feeds gold.dim_invoice, fact_retail_sales, fact_payments. Status changes flow via merge while Bronze keeps history.
-- Business key: silver_invoice_id
-- Load: incremental_merge
-- Supports: gold.dim_invoice, gold.fact_retail_sales, gold.fact_payments
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.invoice (
    silver_invoice_id BIGINT NOT NULL,
    silver_invoice_number VARCHAR(30),
    silver_customer_id BIGINT,
    silver_store_id BIGINT,
    silver_employee_id BIGINT,
    silver_billing_address_id BIGINT,
    silver_shipping_address_id BIGINT,
    silver_po_number VARCHAR(50),
    silver_invoice_date DATE,
    silver_invoice_due_date DATE,
    silver_invoice_status VARCHAR(20),
    silver_tax_rate_id BIGINT,
    silver_subtotal_amount NUMERIC(18,2),
    silver_discount_amount NUMERIC(18,2),
    silver_tax_amount NUMERIC(18,2),
    silver_fee_amount NUMERIC(18,2),
    silver_total_amount NUMERIC(18,2),
    silver_paid_amount NUMERIC(18,2),
    silver_balance_due_amount NUMERIC(18,2),
    silver_has_balance_due_flag BOOLEAN,
    silver_paid_in_full_flag BOOLEAN,
    silver_notes VARCHAR(1000),
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_invoice PRIMARY KEY (silver_invoice_id)
);
COMMENT ON TABLE silver.invoice IS 'Clean current state of each invoice (latest status). Feeds gold.dim_invoice, fact_retail_sales, fact_payments. Status changes flow via merge while Bronze keeps history.';
COMMENT ON COLUMN silver.invoice.silver_invoice_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.invoice.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.invoice_line
-- Source: bronze.oltp_invoice_line
-- Purpose: Clean current version of each invoice line. Grain source for gold.fact_retail_sales.
-- Business key: silver_invoice_line_id
-- Load: incremental_merge
-- Supports: gold.fact_retail_sales
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.invoice_line (
    silver_invoice_line_id BIGINT NOT NULL,
    silver_invoice_id BIGINT,
    silver_line_number SMALLINT,
    silver_product_id BIGINT,
    silver_variant_id BIGINT,
    silver_line_description VARCHAR(300),
    silver_color VARCHAR(40),
    silver_order_qty INTEGER,
    silver_unit_price_amount NUMERIC(18,2),
    silver_unit_cost_amount NUMERIC(18,2),
    silver_discount_amount NUMERIC(18,2),
    silver_line_total_amount NUMERIC(18,2),
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_invoice_line PRIMARY KEY (silver_invoice_line_id)
);
COMMENT ON TABLE silver.invoice_line IS 'Clean current version of each invoice line. Grain source for gold.fact_retail_sales.';
COMMENT ON COLUMN silver.invoice_line.silver_invoice_line_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.invoice_line.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.payment
-- Source: bronze.oltp_payment
-- Purpose: Clean current version of each payment. Grain source for gold.fact_payments.
-- Business key: silver_payment_id
-- Load: incremental_merge
-- Supports: gold.fact_payments
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.payment (
    silver_payment_id BIGINT NOT NULL,
    silver_invoice_id BIGINT,
    silver_customer_id BIGINT,
    silver_payment_method_id BIGINT,
    silver_payment_type_id BIGINT,
    silver_employee_id BIGINT,
    silver_store_id BIGINT,
    silver_parent_payment_id BIGINT,
    silver_payment_sequence_num SMALLINT,
    silver_payment_status VARCHAR(20),
    silver_payment_date DATE,
    silver_payment_amount NUMERIC(18,2),
    silver_tax_amount NUMERIC(18,2),
    silver_fee_amount NUMERIC(18,2),
    silver_net_amount NUMERIC(18,2),
    silver_reference_no VARCHAR(60),
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_payment PRIMARY KEY (silver_payment_id)
);
COMMENT ON TABLE silver.payment IS 'Clean current version of each payment. Grain source for gold.fact_payments.';
COMMENT ON COLUMN silver.payment.silver_payment_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.payment.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.refund
-- Source: bronze.oltp_refund
-- Purpose: Clean current version of each refund, chained to payments. Supports refund analysis in gold.fact_payments.
-- Business key: silver_refund_id
-- Load: incremental_merge
-- Supports: gold.fact_payments
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.refund (
    silver_refund_id BIGINT NOT NULL,
    silver_payment_id BIGINT,
    silver_invoice_id BIGINT,
    silver_refund_amount NUMERIC(18,2),
    silver_refund_date DATE,
    silver_refund_reason VARCHAR(200),
    silver_refunded_by_employee_id BIGINT,
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_refund PRIMARY KEY (silver_refund_id)
);
COMMENT ON TABLE silver.refund IS 'Clean current version of each refund, chained to payments. Supports refund analysis in gold.fact_payments.';
COMMENT ON COLUMN silver.refund.silver_refund_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.refund.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.invoice_adjustment
-- Source: bronze.oltp_invoice_adjustment
-- Purpose: Clean current version of each invoice adjustment. Supports total reconciliation for gold.dim_invoice and fact_payments.
-- Business key: silver_adjustment_id
-- Load: incremental_merge
-- Supports: gold.dim_invoice, gold.fact_payments
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.invoice_adjustment (
    silver_adjustment_id BIGINT NOT NULL,
    silver_invoice_id BIGINT,
    silver_adjustment_type VARCHAR(20),
    silver_adjustment_amount NUMERIC(18,2),
    silver_adjustment_reason VARCHAR(200),
    silver_adjusted_by_employee_id BIGINT,
    silver_adjustment_date DATE,
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_invoice_adjustment PRIMARY KEY (silver_adjustment_id)
);
COMMENT ON TABLE silver.invoice_adjustment IS 'Clean current version of each invoice adjustment. Supports total reconciliation for gold.dim_invoice and fact_payments.';
COMMENT ON COLUMN silver.invoice_adjustment.silver_adjustment_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.invoice_adjustment.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.invoice_status_history
-- Source: bronze.oltp_invoice_status_history
-- Purpose: Clean invoice status transitions. Intentionally history-tracked (one row per transition) to support audit and SCD2 dim_invoice in Gold.
-- Business key: silver_status_history_id
-- Load: incremental_merge (history-tracked: keeps all transitions)
-- Supports: gold.dim_invoice
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.invoice_status_history (
    silver_status_history_id BIGINT NOT NULL,
    silver_invoice_id BIGINT,
    silver_old_status VARCHAR(20),
    silver_new_status VARCHAR(20),
    silver_changed_at_timestamp TIMESTAMP,
    silver_changed_by_employee_id BIGINT,
    silver_change_note VARCHAR(200),
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_invoice_status_history PRIMARY KEY (silver_status_history_id)
);
COMMENT ON TABLE silver.invoice_status_history IS 'Clean invoice status transitions. Intentionally history-tracked (one row per transition) to support audit and SCD2 dim_invoice in Gold.';
COMMENT ON COLUMN silver.invoice_status_history.silver_status_history_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.invoice_status_history.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.customer_status_history
-- Source: bronze.oltp_customer_status_history
-- Purpose: Clean customer status transitions. History-tracked; supports customer_status history for fact_customer_behavior_snapshot.
-- Business key: silver_status_history_id
-- Load: incremental_merge (history-tracked: keeps all transitions)
-- Supports: gold.fact_customer_behavior_snapshot
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.customer_status_history (
    silver_status_history_id BIGINT NOT NULL,
    silver_customer_id BIGINT,
    silver_old_status VARCHAR(20),
    silver_new_status VARCHAR(20),
    silver_changed_at_timestamp TIMESTAMP,
    silver_changed_by_employee_id BIGINT,
    silver_change_reason VARCHAR(200),
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_customer_status_history PRIMARY KEY (silver_status_history_id)
);
COMMENT ON TABLE silver.customer_status_history IS 'Clean customer status transitions. History-tracked; supports customer_status history for fact_customer_behavior_snapshot.';
COMMENT ON COLUMN silver.customer_status_history.silver_status_history_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.customer_status_history.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.payment_method
-- Source: bronze.ref_payment_method
-- Purpose: Clean payment method lookup. Feeds gold.dim_payment_method.
-- Business key: silver_payment_method_id
-- Load: incremental_merge
-- Supports: gold.dim_payment_method
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.payment_method (
    silver_payment_method_id BIGINT NOT NULL,
    silver_method_code VARCHAR(20),
    silver_method_name VARCHAR(50),
    silver_method_type VARCHAR(30),
    silver_is_card_flag BOOLEAN,
    silver_is_active_flag BOOLEAN,
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_payment_method PRIMARY KEY (silver_payment_method_id)
);
COMMENT ON TABLE silver.payment_method IS 'Clean payment method lookup. Feeds gold.dim_payment_method.';
COMMENT ON COLUMN silver.payment_method.silver_payment_method_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.payment_method.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.payment_type
-- Source: bronze.ref_payment_type
-- Purpose: Clean payment type lookup. Feeds gold.dim_payment_type.
-- Business key: silver_payment_type_id
-- Load: incremental_merge
-- Supports: gold.dim_payment_type
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.payment_type (
    silver_payment_type_id BIGINT NOT NULL,
    silver_type_code VARCHAR(20),
    silver_type_name VARCHAR(50),
    silver_type_description VARCHAR(200),
    silver_affects_balance_flag BOOLEAN,
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_payment_type PRIMARY KEY (silver_payment_type_id)
);
COMMENT ON TABLE silver.payment_type IS 'Clean payment type lookup. Feeds gold.dim_payment_type.';
COMMENT ON COLUMN silver.payment_type.silver_payment_type_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.payment_type.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.tax_rate
-- Source: bronze.ref_tax_rate
-- Purpose: Clean tax rate lookup. Supports tax reconciliation for gold.dim_invoice and fact_payments.
-- Business key: silver_tax_rate_id
-- Load: incremental_merge
-- Supports: gold.dim_invoice, gold.fact_payments
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.tax_rate (
    silver_tax_rate_id BIGINT NOT NULL,
    silver_tax_code VARCHAR(20),
    silver_tax_description VARCHAR(100),
    silver_rate_pct NUMERIC(6,4),
    silver_effective_from_date DATE,
    silver_effective_to_date DATE,
    silver_is_active_flag BOOLEAN,
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_tax_rate PRIMARY KEY (silver_tax_rate_id)
);
COMMENT ON TABLE silver.tax_rate IS 'Clean tax rate lookup. Supports tax reconciliation for gold.dim_invoice and fact_payments.';
COMMENT ON COLUMN silver.tax_rate.silver_tax_rate_id IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.tax_rate.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.state
-- Source: bronze.ref_state
-- Purpose: Clean state lookup (CA, AZ, TX). Standardizes state for gold.dim_customer and dim_store.
-- Business key: silver_state_code
-- Load: incremental_merge
-- Supports: gold.dim_customer, gold.dim_store
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.state (
    silver_state_code VARCHAR(2) NOT NULL,
    silver_state_name VARCHAR(50),
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_state PRIMARY KEY (silver_state_code)
);
COMMENT ON TABLE silver.state IS 'Clean state lookup (CA, AZ, TX). Standardizes state for gold.dim_customer and dim_store.';
COMMENT ON COLUMN silver.state.silver_state_code IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.state.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.invoice_status
-- Source: bronze.ref_invoice_status
-- Purpose: Clean invoice status lookup. Standardizes invoice status values for gold.dim_invoice.
-- Business key: silver_status_code
-- Load: incremental_merge
-- Supports: gold.dim_invoice
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.invoice_status (
    silver_status_code VARCHAR(20) NOT NULL,
    silver_status_name VARCHAR(50),
    silver_is_terminal_flag BOOLEAN,
    silver_sort_order SMALLINT,
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_invoice_status PRIMARY KEY (silver_status_code)
);
COMMENT ON TABLE silver.invoice_status IS 'Clean invoice status lookup. Standardizes invoice status values for gold.dim_invoice.';
COMMENT ON COLUMN silver.invoice_status.silver_status_code IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.invoice_status.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- ---------------------------------------------------------------------
-- silver.payment_status
-- Source: bronze.ref_payment_status
-- Purpose: Clean payment status lookup. Standardizes payment status values for gold.fact_payments.
-- Business key: silver_status_code
-- Load: incremental_merge
-- Supports: gold.fact_payments
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.payment_status (
    silver_status_code VARCHAR(20) NOT NULL,
    silver_status_name VARCHAR(50),
    silver_source_system VARCHAR(100) NOT NULL,
    silver_source_table_name VARCHAR(150),
    silver_source_record_id TEXT,
    silver_source_created_at_timestamp TIMESTAMP,
    silver_source_updated_at_timestamp TIMESTAMP,
    silver_bronze_record_id BIGINT,
    silver_bronze_batch_id BIGINT,
    silver_batch_id BIGINT NOT NULL,
    silver_created_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_updated_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    silver_row_hash TEXT NOT NULL,
    silver_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_payment_status PRIMARY KEY (silver_status_code)
);
COMMENT ON TABLE silver.payment_status IS 'Clean payment status lookup. Standardizes payment status values for gold.fact_payments.';
COMMENT ON COLUMN silver.payment_status.silver_status_code IS 'Business key; merge match column.';
COMMENT ON COLUMN silver.payment_status.silver_row_hash IS 'Hash of standardized business columns; update only when it changes.';

-- =====================================================================
-- PrintTimeUSA Data Warehouse | Bronze Layer
-- 002_create_bronze_tables.sql
-- Append-only landing tables. Technical PK = bronze_record_id (BIGSERIAL).
-- The source business id is intentionally NOT the primary key, because the
-- same source row can be appended many times across batches.
-- =====================================================================

SET search_path = bronze, public;


-- ---------------------------------------------------------------------
-- bronze.oltp_customer
-- Source: oltp :: customer
-- Purpose: Raw customer master records. Feeds dim_customer (SCD2 in Gold) and supplies customer attributes referenced by fact_customer_behavior_snapshot.
-- Supports DW: dim_customer, fact_customer_behavior_snapshot
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.oltp_customer (
    bronze_record_id BIGSERIAL,
    customer_id BIGINT NOT NULL,
    customer_account_no VARCHAR(30) NULL,
    business_name VARCHAR(150) NULL,
    first_name VARCHAR(50) NULL,
    last_name VARCHAR(50) NULL,
    full_name VARCHAR(101) NULL,
    email VARCHAR(150) NULL,
    phone VARCHAR(20) NULL,
    customer_status VARCHAR(20) NULL,
    default_tax_rate_id BIGINT NULL,
    home_store_id BIGINT NULL,
    first_order_date DATE NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    source_row_version INTEGER NULL,
    is_deleted_source_flag BOOLEAN NULL,
    deleted_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_oltp_customer PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.oltp_customer IS 'Raw customer master records. Feeds dim_customer (SCD2 in Gold) and supplies customer attributes referenced by fact_customer_behavior_snapshot.';
COMMENT ON COLUMN bronze.oltp_customer.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.oltp_customer.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.oltp_customer.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.oltp_customer_address
-- Source: oltp :: customer_address
-- Purpose: Raw customer address records (billing/shipping). Provides street/city/state/county enrichment for dim_customer.
-- Supports DW: dim_customer
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.oltp_customer_address (
    bronze_record_id BIGSERIAL,
    address_id BIGINT NOT NULL,
    customer_id BIGINT NULL,
    address_type VARCHAR(20) NULL,
    street_address VARCHAR(200) NULL,
    street_address2 VARCHAR(100) NULL,
    city VARCHAR(100) NULL,
    state_code VARCHAR(2) NULL,
    zip_code VARCHAR(10) NULL,
    is_primary_flag BOOLEAN NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    is_deleted_source_flag BOOLEAN NULL,
    deleted_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_oltp_customer_address PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.oltp_customer_address IS 'Raw customer address records (billing/shipping). Provides street/city/state/county enrichment for dim_customer.';
COMMENT ON COLUMN bronze.oltp_customer_address.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.oltp_customer_address.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.oltp_customer_address.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.oltp_product
-- Source: oltp :: product
-- Purpose: Raw product master. Feeds dim_product (SCD2) with price, markup, brand, and department/category links.
-- Supports DW: dim_product, fact_retail_sales
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.oltp_product (
    bronze_record_id BIGSERIAL,
    product_id BIGINT NOT NULL,
    sku VARCHAR(50) NULL,
    product_name VARCHAR(200) NULL,
    description VARCHAR(500) NULL,
    department_id BIGINT NULL,
    category_id BIGINT NULL,
    brand VARCHAR(100) NULL,
    unit_cost_amount NUMERIC(12,2) NULL,
    markup_pct NUMERIC(8,4) NULL,
    standard_price_amount NUMERIC(12,2) NULL,
    is_local_made_flag BOOLEAN NULL,
    is_active_flag BOOLEAN NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    source_row_version INTEGER NULL,
    is_deleted_source_flag BOOLEAN NULL,
    deleted_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_oltp_product PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.oltp_product IS 'Raw product master. Feeds dim_product (SCD2) with price, markup, brand, and department/category links.';
COMMENT ON COLUMN bronze.oltp_product.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.oltp_product.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.oltp_product.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.oltp_product_category
-- Source: oltp :: product_category
-- Purpose: Raw product category lookup. Supplies category_description and links category to department for dim_product.
-- Supports DW: dim_product
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.oltp_product_category (
    bronze_record_id BIGSERIAL,
    category_id BIGINT NOT NULL,
    department_id BIGINT NULL,
    category_code VARCHAR(40) NULL,
    category_name VARCHAR(100) NULL,
    description VARCHAR(200) NULL,
    is_active_flag BOOLEAN NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    is_deleted_source_flag BOOLEAN NULL,
    deleted_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_oltp_product_category PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.oltp_product_category IS 'Raw product category lookup. Supplies category_description and links category to department for dim_product.';
COMMENT ON COLUMN bronze.oltp_product_category.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.oltp_product_category.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.oltp_product_category.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.oltp_department
-- Source: oltp :: department
-- Purpose: Raw department lookup (SIGNS, EMB, DTF, PRINT). Supplies department_number and department_description for dim_product.
-- Supports DW: dim_product
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.oltp_department (
    bronze_record_id BIGSERIAL,
    department_id BIGINT NOT NULL,
    department_code VARCHAR(20) NULL,
    department_name VARCHAR(100) NULL,
    description VARCHAR(200) NULL,
    is_active_flag BOOLEAN NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    is_deleted_source_flag BOOLEAN NULL,
    deleted_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_oltp_department PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.oltp_department IS 'Raw department lookup (SIGNS, EMB, DTF, PRINT). Supplies department_number and department_description for dim_product.';
COMMENT ON COLUMN bronze.oltp_department.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.oltp_department.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.oltp_department.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.oltp_employee
-- Source: oltp :: employee
-- Purpose: Raw employee master. Feeds dim_cashier (SCD2) with name, active status, and store assignment.
-- Supports DW: dim_cashier
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.oltp_employee (
    bronze_record_id BIGSERIAL,
    employee_id BIGINT NOT NULL,
    employee_code VARCHAR(30) NULL,
    first_name VARCHAR(50) NULL,
    last_name VARCHAR(50) NULL,
    full_name VARCHAR(101) NULL,
    email VARCHAR(150) NULL,
    phone VARCHAR(20) NULL,
    role VARCHAR(30) NULL,
    store_id BIGINT NULL,
    hire_date DATE NULL,
    is_active_flag BOOLEAN NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    source_row_version INTEGER NULL,
    is_deleted_source_flag BOOLEAN NULL,
    deleted_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_oltp_employee PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.oltp_employee IS 'Raw employee master. Feeds dim_cashier (SCD2) with name, active status, and store assignment.';
COMMENT ON COLUMN bronze.oltp_employee.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.oltp_employee.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.oltp_employee.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.oltp_store
-- Source: oltp :: store
-- Purpose: Raw store master. Feeds dim_store (SCD2) and supplies store labels denormalized into dim_cashier and dim_invoice.
-- Supports DW: dim_store, dim_cashier, dim_invoice
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.oltp_store (
    bronze_record_id BIGSERIAL,
    store_id BIGINT NOT NULL,
    store_code VARCHAR(30) NULL,
    store_name VARCHAR(100) NULL,
    street_address VARCHAR(200) NULL,
    city VARCHAR(100) NULL,
    state_code VARCHAR(2) NULL,
    zip_code VARCHAR(10) NULL,
    phone VARCHAR(20) NULL,
    region VARCHAR(50) NULL,
    store_type VARCHAR(50) NULL,
    open_date DATE NULL,
    is_active_flag BOOLEAN NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    source_row_version INTEGER NULL,
    is_deleted_source_flag BOOLEAN NULL,
    deleted_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_oltp_store PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.oltp_store IS 'Raw store master. Feeds dim_store (SCD2) and supplies store labels denormalized into dim_cashier and dim_invoice.';
COMMENT ON COLUMN bronze.oltp_store.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.oltp_store.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.oltp_store.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.oltp_invoice
-- Source: oltp :: invoice
-- Purpose: Raw invoice headers. Feeds dim_invoice (SCD2 on status/total) and supplies header context to fact_retail_sales, fact_payments, and fact_customer_behavior_snapshot. Status changes are preserved as appended versions.
-- Supports DW: dim_invoice, fact_retail_sales, fact_payments, fact_customer_behavior_snapshot
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.oltp_invoice (
    bronze_record_id BIGSERIAL,
    invoice_id BIGINT NOT NULL,
    invoice_number VARCHAR(30) NULL,
    customer_id BIGINT NULL,
    store_id BIGINT NULL,
    employee_id BIGINT NULL,
    billing_address_id BIGINT NULL,
    shipping_address_id BIGINT NULL,
    po_number VARCHAR(50) NULL,
    invoice_date DATE NULL,
    invoice_due_date DATE NULL,
    invoice_status VARCHAR(20) NULL,
    tax_rate_id BIGINT NULL,
    subtotal_amount NUMERIC(12,2) NULL,
    discount_amount NUMERIC(12,2) NULL,
    tax_amount NUMERIC(12,2) NULL,
    fee_amount NUMERIC(12,2) NULL,
    total_amount NUMERIC(12,2) NULL,
    paid_amount NUMERIC(12,2) NULL,
    balance_due_amount NUMERIC(12,2) NULL,
    notes VARCHAR(1000) NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    source_row_version INTEGER NULL,
    is_deleted_source_flag BOOLEAN NULL,
    deleted_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_oltp_invoice PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.oltp_invoice IS 'Raw invoice headers. Feeds dim_invoice (SCD2 on status/total) and supplies header context to fact_retail_sales, fact_payments, and fact_customer_behavior_snapshot. Status changes are preserved as appended versions.';
COMMENT ON COLUMN bronze.oltp_invoice.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.oltp_invoice.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.oltp_invoice.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.oltp_invoice_line
-- Source: oltp :: invoice_line
-- Purpose: Raw invoice line items. The grain source for fact_retail_sales (qty, price, cost, extended amount).
-- Supports DW: fact_retail_sales
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.oltp_invoice_line (
    bronze_record_id BIGSERIAL,
    invoice_line_id BIGINT NOT NULL,
    invoice_id BIGINT NULL,
    line_number SMALLINT NULL,
    product_id BIGINT NULL,
    variant_id BIGINT NULL,
    line_description VARCHAR(300) NULL,
    color VARCHAR(40) NULL,
    order_qty INTEGER NULL,
    unit_price_amount NUMERIC(12,2) NULL,
    unit_cost_amount NUMERIC(12,2) NULL,
    discount_amount NUMERIC(12,2) NULL,
    line_total_amount NUMERIC(12,2) NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    is_deleted_source_flag BOOLEAN NULL,
    deleted_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_oltp_invoice_line PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.oltp_invoice_line IS 'Raw invoice line items. The grain source for fact_retail_sales (qty, price, cost, extended amount).';
COMMENT ON COLUMN bronze.oltp_invoice_line.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.oltp_invoice_line.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.oltp_invoice_line.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.oltp_payment
-- Source: oltp :: payment
-- Purpose: Raw payment transactions (deposits, balances, full payments, refunds, adjustments). The grain source for fact_payments.
-- Supports DW: fact_payments
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.oltp_payment (
    bronze_record_id BIGSERIAL,
    payment_id BIGINT NOT NULL,
    invoice_id BIGINT NULL,
    customer_id BIGINT NULL,
    payment_method_id BIGINT NULL,
    payment_type_id BIGINT NULL,
    employee_id BIGINT NULL,
    store_id BIGINT NULL,
    parent_payment_id BIGINT NULL,
    payment_sequence_num SMALLINT NULL,
    payment_status VARCHAR(20) NULL,
    payment_date DATE NULL,
    gross_amount NUMERIC(12,2) NULL,
    tax_amount NUMERIC(12,2) NULL,
    fee_amount NUMERIC(12,2) NULL,
    net_amount NUMERIC(12,2) NULL,
    reference_no VARCHAR(60) NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    source_row_version INTEGER NULL,
    is_deleted_source_flag BOOLEAN NULL,
    deleted_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_oltp_payment PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.oltp_payment IS 'Raw payment transactions (deposits, balances, full payments, refunds, adjustments). The grain source for fact_payments.';
COMMENT ON COLUMN bronze.oltp_payment.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.oltp_payment.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.oltp_payment.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.oltp_invoice_status_history
-- Source: oltp :: invoice_status_history
-- Purpose: Raw invoice status change log. Gives Silver/Gold the authoritative status-change timeline for SCD2 dim_invoice, complementing appended invoice versions.
-- Supports DW: dim_invoice
-- Recommended watermark: changed_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.oltp_invoice_status_history (
    bronze_record_id BIGSERIAL,
    status_history_id BIGINT NOT NULL,
    invoice_id BIGINT NULL,
    old_status VARCHAR(20) NULL,
    new_status VARCHAR(20) NULL,
    changed_at_source_timestamp TIMESTAMP NULL,
    changed_by BIGINT NULL,
    note VARCHAR(200) NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_oltp_invoice_status_history PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.oltp_invoice_status_history IS 'Raw invoice status change log. Gives Silver/Gold the authoritative status-change timeline for SCD2 dim_invoice, complementing appended invoice versions.';
COMMENT ON COLUMN bronze.oltp_invoice_status_history.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.oltp_invoice_status_history.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.oltp_invoice_status_history.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.oltp_customer_status_history
-- Source: oltp :: customer_status_history
-- Purpose: Raw customer status change log. Supports customer_status history for fact_customer_behavior_snapshot and audit of active/inactive transitions.
-- Supports DW: fact_customer_behavior_snapshot
-- Recommended watermark: changed_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.oltp_customer_status_history (
    bronze_record_id BIGSERIAL,
    status_history_id BIGINT NOT NULL,
    customer_id BIGINT NULL,
    old_status VARCHAR(20) NULL,
    new_status VARCHAR(20) NULL,
    changed_at_source_timestamp TIMESTAMP NULL,
    changed_by BIGINT NULL,
    reason VARCHAR(200) NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_oltp_customer_status_history PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.oltp_customer_status_history IS 'Raw customer status change log. Supports customer_status history for fact_customer_behavior_snapshot and audit of active/inactive transitions.';
COMMENT ON COLUMN bronze.oltp_customer_status_history.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.oltp_customer_status_history.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.oltp_customer_status_history.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.oltp_refund
-- Source: oltp :: refund
-- Purpose: Raw refund records chained to payments. Supplements fact_payments refund analysis and reconciliation.
-- Supports DW: fact_payments
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.oltp_refund (
    bronze_record_id BIGSERIAL,
    refund_id BIGINT NOT NULL,
    payment_id BIGINT NULL,
    invoice_id BIGINT NULL,
    refund_amount NUMERIC(12,2) NULL,
    refund_date DATE NULL,
    reason VARCHAR(200) NULL,
    refunded_by BIGINT NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    is_deleted_source_flag BOOLEAN NULL,
    deleted_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_oltp_refund PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.oltp_refund IS 'Raw refund records chained to payments. Supplements fact_payments refund analysis and reconciliation.';
COMMENT ON COLUMN bronze.oltp_refund.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.oltp_refund.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.oltp_refund.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.oltp_invoice_adjustment
-- Source: oltp :: invoice_adjustment
-- Purpose: Raw invoice adjustments (credits/debits). Supports reconciliation of invoice totals feeding dim_invoice and fact_payments.
-- Supports DW: dim_invoice, fact_payments
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.oltp_invoice_adjustment (
    bronze_record_id BIGSERIAL,
    adjustment_id BIGINT NOT NULL,
    invoice_id BIGINT NULL,
    adjustment_type VARCHAR(20) NULL,
    amount NUMERIC(12,2) NULL,
    reason VARCHAR(200) NULL,
    adjusted_by BIGINT NULL,
    adjustment_date DATE NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    is_deleted_source_flag BOOLEAN NULL,
    deleted_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_oltp_invoice_adjustment PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.oltp_invoice_adjustment IS 'Raw invoice adjustments (credits/debits). Supports reconciliation of invoice totals feeding dim_invoice and fact_payments.';
COMMENT ON COLUMN bronze.oltp_invoice_adjustment.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.oltp_invoice_adjustment.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.oltp_invoice_adjustment.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.ref_payment_method
-- Source: ref :: payment_method
-- Purpose: Reference payment method lookup. Feeds dim_payment_method (method code/name/type/active).
-- Supports DW: dim_payment_method
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.ref_payment_method (
    bronze_record_id BIGSERIAL,
    payment_method_id BIGINT NOT NULL,
    method_code VARCHAR(20) NULL,
    method_name VARCHAR(50) NULL,
    method_type VARCHAR(30) NULL,
    is_card_flag BOOLEAN NULL,
    is_active_flag BOOLEAN NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    source_row_version INTEGER NULL,
    is_deleted_source_flag BOOLEAN NULL,
    deleted_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_ref_payment_method PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.ref_payment_method IS 'Reference payment method lookup. Feeds dim_payment_method (method code/name/type/active).';
COMMENT ON COLUMN bronze.ref_payment_method.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.ref_payment_method.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.ref_payment_method.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.ref_payment_type
-- Source: ref :: payment_type
-- Purpose: Reference payment type lookup. Feeds dim_payment_type (DEPOSIT, BALANCE, FULL, REFUND, ADJUSTMENT).
-- Supports DW: dim_payment_type
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.ref_payment_type (
    bronze_record_id BIGSERIAL,
    payment_type_id BIGINT NOT NULL,
    type_code VARCHAR(20) NULL,
    type_name VARCHAR(50) NULL,
    description VARCHAR(200) NULL,
    affects_balance_flag BOOLEAN NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    is_deleted_source_flag BOOLEAN NULL,
    deleted_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_ref_payment_type PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.ref_payment_type IS 'Reference payment type lookup. Feeds dim_payment_type (DEPOSIT, BALANCE, FULL, REFUND, ADJUSTMENT).';
COMMENT ON COLUMN bronze.ref_payment_type.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.ref_payment_type.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.ref_payment_type.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.ref_tax_rate
-- Source: ref :: tax_rate
-- Purpose: Reference tax rate lookup. Supports tax reconciliation for dim_invoice / fact_payments (tax_amount validation).
-- Supports DW: dim_invoice, fact_payments
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.ref_tax_rate (
    bronze_record_id BIGSERIAL,
    tax_rate_id BIGINT NOT NULL,
    tax_code VARCHAR(20) NULL,
    description VARCHAR(100) NULL,
    rate_pct NUMERIC(6,4) NULL,
    effective_from DATE NULL,
    effective_to DATE NULL,
    is_active_flag BOOLEAN NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_ref_tax_rate PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.ref_tax_rate IS 'Reference tax rate lookup. Supports tax reconciliation for dim_invoice / fact_payments (tax_amount validation).';
COMMENT ON COLUMN bronze.ref_tax_rate.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.ref_tax_rate.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.ref_tax_rate.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.ref_state
-- Source: ref :: ref_state
-- Purpose: Reference state lookup (CA, AZ, TX). Supports state/region standardization for dim_customer and dim_store.
-- Supports DW: dim_customer, dim_store
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.ref_state (
    bronze_record_id BIGSERIAL,
    state_code VARCHAR(2) NOT NULL,
    state_name VARCHAR(50) NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_ref_state PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.ref_state IS 'Reference state lookup (CA, AZ, TX). Supports state/region standardization for dim_customer and dim_store.';
COMMENT ON COLUMN bronze.ref_state.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.ref_state.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.ref_state.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.ref_invoice_status
-- Source: ref :: ref_invoice_status
-- Purpose: Reference invoice status lookup (OPEN, PARTIAL, PAID, VOID). Standardizes invoice_status values for dim_invoice.
-- Supports DW: dim_invoice
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.ref_invoice_status (
    bronze_record_id BIGSERIAL,
    status_code VARCHAR(20) NOT NULL,
    status_name VARCHAR(50) NULL,
    is_terminal_flag BOOLEAN NULL,
    sort_order SMALLINT NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_ref_invoice_status PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.ref_invoice_status IS 'Reference invoice status lookup (OPEN, PARTIAL, PAID, VOID). Standardizes invoice_status values for dim_invoice.';
COMMENT ON COLUMN bronze.ref_invoice_status.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.ref_invoice_status.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.ref_invoice_status.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

-- ---------------------------------------------------------------------
-- bronze.ref_payment_status
-- Source: ref :: ref_payment_status
-- Purpose: Reference payment status lookup. Standardizes payment_status values feeding fact_payments.
-- Supports DW: fact_payments
-- Recommended watermark: updated_at_source_timestamp
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.ref_payment_status (
    bronze_record_id BIGSERIAL,
    status_code VARCHAR(20) NOT NULL,
    status_name VARCHAR(50) NULL,
    created_at_source_timestamp TIMESTAMP NULL,
    updated_at_source_timestamp TIMESTAMP NULL,
    bronze_batch_id BIGINT NOT NULL,
    bronze_loaded_at_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bronze_extracted_at_timestamp TIMESTAMP NULL,
    bronze_source_system VARCHAR(100) NOT NULL,
    bronze_source_table_name VARCHAR(150) NULL,
    bronze_source_file_name VARCHAR(255) NULL,
    bronze_source_row_number BIGINT NULL,
    bronze_row_hash TEXT NOT NULL,
    bronze_is_deleted_flag BOOLEAN NOT NULL DEFAULT FALSE,
    bronze_raw_payload_jsonb JSONB NULL,
    CONSTRAINT pk_ref_payment_status PRIMARY KEY (bronze_record_id)
);
COMMENT ON TABLE bronze.ref_payment_status IS 'Reference payment status lookup. Standardizes payment_status values feeding fact_payments.';
COMMENT ON COLUMN bronze.ref_payment_status.bronze_record_id IS 'Technical surrogate PK. Append-only; source id may repeat across batches.';
COMMENT ON COLUMN bronze.ref_payment_status.bronze_row_hash IS 'Hash of business columns; used to detect changed source rows between batches.';
COMMENT ON COLUMN bronze.ref_payment_status.bronze_batch_id IS 'ETL batch id; joins to audit.etl_batch_control (batch_key).';

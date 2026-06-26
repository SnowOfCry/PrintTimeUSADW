-- =====================================================================
-- PrintTimeUSA Data Warehouse | Bronze Layer
-- 003_create_bronze_indexes.sql
-- Indexes for incremental loading, change detection, and lineage.
-- Standard set per table:
--   source PK column, bronze_batch_id, bronze_loaded_at_timestamp,
--   bronze_row_hash, and the source updated/changed watermark (if present).
-- =====================================================================

SET search_path = bronze, public;


-- oltp_customer
CREATE INDEX IF NOT EXISTS idx_oltp_customer_customer_id ON bronze.oltp_customer (customer_id);
CREATE INDEX IF NOT EXISTS idx_oltp_customer_bronze_batch_id ON bronze.oltp_customer (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_oltp_customer_bronze_loaded_at_timestamp ON bronze.oltp_customer (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_oltp_customer_bronze_row_hash ON bronze.oltp_customer (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_oltp_customer_updated_at_source_timestamp ON bronze.oltp_customer (updated_at_source_timestamp);

-- oltp_customer_address
CREATE INDEX IF NOT EXISTS idx_oltp_customer_address_address_id ON bronze.oltp_customer_address (address_id);
CREATE INDEX IF NOT EXISTS idx_oltp_customer_address_bronze_batch_id ON bronze.oltp_customer_address (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_oltp_customer_address_bronze_loaded_at_timestamp ON bronze.oltp_customer_address (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_oltp_customer_address_bronze_row_hash ON bronze.oltp_customer_address (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_oltp_customer_address_updated_at_source_timestamp ON bronze.oltp_customer_address (updated_at_source_timestamp);

-- oltp_product
CREATE INDEX IF NOT EXISTS idx_oltp_product_product_id ON bronze.oltp_product (product_id);
CREATE INDEX IF NOT EXISTS idx_oltp_product_bronze_batch_id ON bronze.oltp_product (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_oltp_product_bronze_loaded_at_timestamp ON bronze.oltp_product (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_oltp_product_bronze_row_hash ON bronze.oltp_product (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_oltp_product_updated_at_source_timestamp ON bronze.oltp_product (updated_at_source_timestamp);

-- oltp_product_category
CREATE INDEX IF NOT EXISTS idx_oltp_product_category_category_id ON bronze.oltp_product_category (category_id);
CREATE INDEX IF NOT EXISTS idx_oltp_product_category_bronze_batch_id ON bronze.oltp_product_category (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_oltp_product_category_bronze_loaded_at_timestamp ON bronze.oltp_product_category (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_oltp_product_category_bronze_row_hash ON bronze.oltp_product_category (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_oltp_product_category_updated_at_source_timestamp ON bronze.oltp_product_category (updated_at_source_timestamp);

-- oltp_department
CREATE INDEX IF NOT EXISTS idx_oltp_department_department_id ON bronze.oltp_department (department_id);
CREATE INDEX IF NOT EXISTS idx_oltp_department_bronze_batch_id ON bronze.oltp_department (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_oltp_department_bronze_loaded_at_timestamp ON bronze.oltp_department (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_oltp_department_bronze_row_hash ON bronze.oltp_department (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_oltp_department_updated_at_source_timestamp ON bronze.oltp_department (updated_at_source_timestamp);

-- oltp_employee
CREATE INDEX IF NOT EXISTS idx_oltp_employee_employee_id ON bronze.oltp_employee (employee_id);
CREATE INDEX IF NOT EXISTS idx_oltp_employee_bronze_batch_id ON bronze.oltp_employee (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_oltp_employee_bronze_loaded_at_timestamp ON bronze.oltp_employee (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_oltp_employee_bronze_row_hash ON bronze.oltp_employee (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_oltp_employee_updated_at_source_timestamp ON bronze.oltp_employee (updated_at_source_timestamp);

-- oltp_store
CREATE INDEX IF NOT EXISTS idx_oltp_store_store_id ON bronze.oltp_store (store_id);
CREATE INDEX IF NOT EXISTS idx_oltp_store_bronze_batch_id ON bronze.oltp_store (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_oltp_store_bronze_loaded_at_timestamp ON bronze.oltp_store (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_oltp_store_bronze_row_hash ON bronze.oltp_store (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_oltp_store_updated_at_source_timestamp ON bronze.oltp_store (updated_at_source_timestamp);

-- oltp_invoice
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_invoice_id ON bronze.oltp_invoice (invoice_id);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_bronze_batch_id ON bronze.oltp_invoice (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_bronze_loaded_at_timestamp ON bronze.oltp_invoice (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_bronze_row_hash ON bronze.oltp_invoice (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_updated_at_source_timestamp ON bronze.oltp_invoice (updated_at_source_timestamp);

-- oltp_invoice_line
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_line_invoice_line_id ON bronze.oltp_invoice_line (invoice_line_id);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_line_bronze_batch_id ON bronze.oltp_invoice_line (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_line_bronze_loaded_at_timestamp ON bronze.oltp_invoice_line (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_line_bronze_row_hash ON bronze.oltp_invoice_line (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_line_updated_at_source_timestamp ON bronze.oltp_invoice_line (updated_at_source_timestamp);

-- oltp_payment
CREATE INDEX IF NOT EXISTS idx_oltp_payment_payment_id ON bronze.oltp_payment (payment_id);
CREATE INDEX IF NOT EXISTS idx_oltp_payment_bronze_batch_id ON bronze.oltp_payment (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_oltp_payment_bronze_loaded_at_timestamp ON bronze.oltp_payment (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_oltp_payment_bronze_row_hash ON bronze.oltp_payment (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_oltp_payment_updated_at_source_timestamp ON bronze.oltp_payment (updated_at_source_timestamp);

-- oltp_invoice_status_history
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_status_history_status_history_id ON bronze.oltp_invoice_status_history (status_history_id);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_status_history_bronze_batch_id ON bronze.oltp_invoice_status_history (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_status_history_bronze_loaded_at_timestamp ON bronze.oltp_invoice_status_history (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_status_history_bronze_row_hash ON bronze.oltp_invoice_status_history (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_status_history_changed_at_source_timestamp ON bronze.oltp_invoice_status_history (changed_at_source_timestamp);

-- oltp_customer_status_history
CREATE INDEX IF NOT EXISTS idx_oltp_customer_status_history_status_history_id ON bronze.oltp_customer_status_history (status_history_id);
CREATE INDEX IF NOT EXISTS idx_oltp_customer_status_history_bronze_batch_id ON bronze.oltp_customer_status_history (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_oltp_customer_status_history_bronze_loaded_at_timestamp ON bronze.oltp_customer_status_history (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_oltp_customer_status_history_bronze_row_hash ON bronze.oltp_customer_status_history (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_oltp_customer_status_history_changed_at_source_timestamp ON bronze.oltp_customer_status_history (changed_at_source_timestamp);

-- oltp_refund
CREATE INDEX IF NOT EXISTS idx_oltp_refund_refund_id ON bronze.oltp_refund (refund_id);
CREATE INDEX IF NOT EXISTS idx_oltp_refund_bronze_batch_id ON bronze.oltp_refund (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_oltp_refund_bronze_loaded_at_timestamp ON bronze.oltp_refund (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_oltp_refund_bronze_row_hash ON bronze.oltp_refund (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_oltp_refund_updated_at_source_timestamp ON bronze.oltp_refund (updated_at_source_timestamp);

-- oltp_invoice_adjustment
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_adjustment_adjustment_id ON bronze.oltp_invoice_adjustment (adjustment_id);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_adjustment_bronze_batch_id ON bronze.oltp_invoice_adjustment (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_adjustment_bronze_loaded_at_timestamp ON bronze.oltp_invoice_adjustment (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_adjustment_bronze_row_hash ON bronze.oltp_invoice_adjustment (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_oltp_invoice_adjustment_updated_at_source_timestamp ON bronze.oltp_invoice_adjustment (updated_at_source_timestamp);

-- ref_payment_method
CREATE INDEX IF NOT EXISTS idx_ref_payment_method_payment_method_id ON bronze.ref_payment_method (payment_method_id);
CREATE INDEX IF NOT EXISTS idx_ref_payment_method_bronze_batch_id ON bronze.ref_payment_method (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_ref_payment_method_bronze_loaded_at_timestamp ON bronze.ref_payment_method (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_ref_payment_method_bronze_row_hash ON bronze.ref_payment_method (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_ref_payment_method_updated_at_source_timestamp ON bronze.ref_payment_method (updated_at_source_timestamp);

-- ref_payment_type
CREATE INDEX IF NOT EXISTS idx_ref_payment_type_payment_type_id ON bronze.ref_payment_type (payment_type_id);
CREATE INDEX IF NOT EXISTS idx_ref_payment_type_bronze_batch_id ON bronze.ref_payment_type (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_ref_payment_type_bronze_loaded_at_timestamp ON bronze.ref_payment_type (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_ref_payment_type_bronze_row_hash ON bronze.ref_payment_type (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_ref_payment_type_updated_at_source_timestamp ON bronze.ref_payment_type (updated_at_source_timestamp);

-- ref_tax_rate
CREATE INDEX IF NOT EXISTS idx_ref_tax_rate_tax_rate_id ON bronze.ref_tax_rate (tax_rate_id);
CREATE INDEX IF NOT EXISTS idx_ref_tax_rate_bronze_batch_id ON bronze.ref_tax_rate (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_ref_tax_rate_bronze_loaded_at_timestamp ON bronze.ref_tax_rate (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_ref_tax_rate_bronze_row_hash ON bronze.ref_tax_rate (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_ref_tax_rate_updated_at_source_timestamp ON bronze.ref_tax_rate (updated_at_source_timestamp);

-- ref_state
CREATE INDEX IF NOT EXISTS idx_ref_state_state_code ON bronze.ref_state (state_code);
CREATE INDEX IF NOT EXISTS idx_ref_state_bronze_batch_id ON bronze.ref_state (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_ref_state_bronze_loaded_at_timestamp ON bronze.ref_state (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_ref_state_bronze_row_hash ON bronze.ref_state (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_ref_state_updated_at_source_timestamp ON bronze.ref_state (updated_at_source_timestamp);

-- ref_invoice_status
CREATE INDEX IF NOT EXISTS idx_ref_invoice_status_status_code ON bronze.ref_invoice_status (status_code);
CREATE INDEX IF NOT EXISTS idx_ref_invoice_status_bronze_batch_id ON bronze.ref_invoice_status (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_ref_invoice_status_bronze_loaded_at_timestamp ON bronze.ref_invoice_status (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_ref_invoice_status_bronze_row_hash ON bronze.ref_invoice_status (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_ref_invoice_status_updated_at_source_timestamp ON bronze.ref_invoice_status (updated_at_source_timestamp);

-- ref_payment_status
CREATE INDEX IF NOT EXISTS idx_ref_payment_status_status_code ON bronze.ref_payment_status (status_code);
CREATE INDEX IF NOT EXISTS idx_ref_payment_status_bronze_batch_id ON bronze.ref_payment_status (bronze_batch_id);
CREATE INDEX IF NOT EXISTS idx_ref_payment_status_bronze_loaded_at_timestamp ON bronze.ref_payment_status (bronze_loaded_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_ref_payment_status_bronze_row_hash ON bronze.ref_payment_status (bronze_row_hash);
CREATE INDEX IF NOT EXISTS idx_ref_payment_status_updated_at_source_timestamp ON bronze.ref_payment_status (updated_at_source_timestamp);

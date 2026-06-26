-- =====================================================================
-- PrintTimeUSA Data Warehouse | Silver Layer
-- 003_create_silver_indexes.sql
-- Per table: business key, silver_batch_id, silver_updated_at_timestamp,
-- silver_row_hash, silver_is_deleted_flag, plus Gold-facing reference ids.
-- =====================================================================

SET search_path = silver, public;


-- customer
CREATE INDEX IF NOT EXISTS idx_customer_silver_customer_id ON silver.customer (silver_customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_silver_batch_id ON silver.customer (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_customer_silver_updated_at_timestamp ON silver.customer (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_customer_silver_row_hash ON silver.customer (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_customer_silver_is_deleted_flag ON silver.customer (silver_is_deleted_flag);
CREATE INDEX IF NOT EXISTS idx_customer_silver_home_store_id ON silver.customer (silver_home_store_id);

-- customer_address
CREATE INDEX IF NOT EXISTS idx_customer_address_silver_address_id ON silver.customer_address (silver_address_id);
CREATE INDEX IF NOT EXISTS idx_customer_address_silver_batch_id ON silver.customer_address (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_customer_address_silver_updated_at_timestamp ON silver.customer_address (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_customer_address_silver_row_hash ON silver.customer_address (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_customer_address_silver_is_deleted_flag ON silver.customer_address (silver_is_deleted_flag);
CREATE INDEX IF NOT EXISTS idx_customer_address_silver_customer_id ON silver.customer_address (silver_customer_id);

-- product
CREATE INDEX IF NOT EXISTS idx_product_silver_product_id ON silver.product (silver_product_id);
CREATE INDEX IF NOT EXISTS idx_product_silver_batch_id ON silver.product (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_product_silver_updated_at_timestamp ON silver.product (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_product_silver_row_hash ON silver.product (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_product_silver_is_deleted_flag ON silver.product (silver_is_deleted_flag);
CREATE INDEX IF NOT EXISTS idx_product_silver_department_id ON silver.product (silver_department_id);
CREATE INDEX IF NOT EXISTS idx_product_silver_category_id ON silver.product (silver_category_id);

-- product_category
CREATE INDEX IF NOT EXISTS idx_product_category_silver_category_id ON silver.product_category (silver_category_id);
CREATE INDEX IF NOT EXISTS idx_product_category_silver_batch_id ON silver.product_category (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_product_category_silver_updated_at_timestamp ON silver.product_category (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_product_category_silver_row_hash ON silver.product_category (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_product_category_silver_is_deleted_flag ON silver.product_category (silver_is_deleted_flag);
CREATE INDEX IF NOT EXISTS idx_product_category_silver_department_id ON silver.product_category (silver_department_id);

-- department
CREATE INDEX IF NOT EXISTS idx_department_silver_department_id ON silver.department (silver_department_id);
CREATE INDEX IF NOT EXISTS idx_department_silver_batch_id ON silver.department (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_department_silver_updated_at_timestamp ON silver.department (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_department_silver_row_hash ON silver.department (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_department_silver_is_deleted_flag ON silver.department (silver_is_deleted_flag);

-- employee
CREATE INDEX IF NOT EXISTS idx_employee_silver_employee_id ON silver.employee (silver_employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_silver_batch_id ON silver.employee (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_employee_silver_updated_at_timestamp ON silver.employee (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_employee_silver_row_hash ON silver.employee (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_employee_silver_is_deleted_flag ON silver.employee (silver_is_deleted_flag);
CREATE INDEX IF NOT EXISTS idx_employee_silver_store_id ON silver.employee (silver_store_id);

-- store
CREATE INDEX IF NOT EXISTS idx_store_silver_store_id ON silver.store (silver_store_id);
CREATE INDEX IF NOT EXISTS idx_store_silver_batch_id ON silver.store (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_store_silver_updated_at_timestamp ON silver.store (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_store_silver_row_hash ON silver.store (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_store_silver_is_deleted_flag ON silver.store (silver_is_deleted_flag);
CREATE INDEX IF NOT EXISTS idx_store_silver_state_code ON silver.store (silver_state_code);

-- invoice
CREATE INDEX IF NOT EXISTS idx_invoice_silver_invoice_id ON silver.invoice (silver_invoice_id);
CREATE INDEX IF NOT EXISTS idx_invoice_silver_batch_id ON silver.invoice (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_invoice_silver_updated_at_timestamp ON silver.invoice (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_invoice_silver_row_hash ON silver.invoice (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_invoice_silver_is_deleted_flag ON silver.invoice (silver_is_deleted_flag);
CREATE INDEX IF NOT EXISTS idx_invoice_silver_customer_id ON silver.invoice (silver_customer_id);
CREATE INDEX IF NOT EXISTS idx_invoice_silver_store_id ON silver.invoice (silver_store_id);
CREATE INDEX IF NOT EXISTS idx_invoice_silver_employee_id ON silver.invoice (silver_employee_id);

-- invoice_line
CREATE INDEX IF NOT EXISTS idx_invoice_line_silver_invoice_line_id ON silver.invoice_line (silver_invoice_line_id);
CREATE INDEX IF NOT EXISTS idx_invoice_line_silver_batch_id ON silver.invoice_line (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_invoice_line_silver_updated_at_timestamp ON silver.invoice_line (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_invoice_line_silver_row_hash ON silver.invoice_line (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_invoice_line_silver_is_deleted_flag ON silver.invoice_line (silver_is_deleted_flag);
CREATE INDEX IF NOT EXISTS idx_invoice_line_silver_invoice_id ON silver.invoice_line (silver_invoice_id);
CREATE INDEX IF NOT EXISTS idx_invoice_line_silver_product_id ON silver.invoice_line (silver_product_id);

-- payment
CREATE INDEX IF NOT EXISTS idx_payment_silver_payment_id ON silver.payment (silver_payment_id);
CREATE INDEX IF NOT EXISTS idx_payment_silver_batch_id ON silver.payment (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_payment_silver_updated_at_timestamp ON silver.payment (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_payment_silver_row_hash ON silver.payment (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_payment_silver_is_deleted_flag ON silver.payment (silver_is_deleted_flag);
CREATE INDEX IF NOT EXISTS idx_payment_silver_invoice_id ON silver.payment (silver_invoice_id);
CREATE INDEX IF NOT EXISTS idx_payment_silver_customer_id ON silver.payment (silver_customer_id);
CREATE INDEX IF NOT EXISTS idx_payment_silver_payment_method_id ON silver.payment (silver_payment_method_id);

-- refund
CREATE INDEX IF NOT EXISTS idx_refund_silver_refund_id ON silver.refund (silver_refund_id);
CREATE INDEX IF NOT EXISTS idx_refund_silver_batch_id ON silver.refund (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_refund_silver_updated_at_timestamp ON silver.refund (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_refund_silver_row_hash ON silver.refund (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_refund_silver_is_deleted_flag ON silver.refund (silver_is_deleted_flag);
CREATE INDEX IF NOT EXISTS idx_refund_silver_payment_id ON silver.refund (silver_payment_id);
CREATE INDEX IF NOT EXISTS idx_refund_silver_invoice_id ON silver.refund (silver_invoice_id);

-- invoice_adjustment
CREATE INDEX IF NOT EXISTS idx_invoice_adjustment_silver_adjustment_id ON silver.invoice_adjustment (silver_adjustment_id);
CREATE INDEX IF NOT EXISTS idx_invoice_adjustment_silver_batch_id ON silver.invoice_adjustment (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_invoice_adjustment_silver_updated_at_timestamp ON silver.invoice_adjustment (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_invoice_adjustment_silver_row_hash ON silver.invoice_adjustment (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_invoice_adjustment_silver_is_deleted_flag ON silver.invoice_adjustment (silver_is_deleted_flag);
CREATE INDEX IF NOT EXISTS idx_invoice_adjustment_silver_invoice_id ON silver.invoice_adjustment (silver_invoice_id);

-- invoice_status_history
CREATE INDEX IF NOT EXISTS idx_invoice_status_history_silver_status_history_id ON silver.invoice_status_history (silver_status_history_id);
CREATE INDEX IF NOT EXISTS idx_invoice_status_history_silver_batch_id ON silver.invoice_status_history (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_invoice_status_history_silver_updated_at_timestamp ON silver.invoice_status_history (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_invoice_status_history_silver_row_hash ON silver.invoice_status_history (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_invoice_status_history_silver_is_deleted_flag ON silver.invoice_status_history (silver_is_deleted_flag);
CREATE INDEX IF NOT EXISTS idx_invoice_status_history_silver_invoice_id ON silver.invoice_status_history (silver_invoice_id);

-- customer_status_history
CREATE INDEX IF NOT EXISTS idx_customer_status_history_silver_status_history_id ON silver.customer_status_history (silver_status_history_id);
CREATE INDEX IF NOT EXISTS idx_customer_status_history_silver_batch_id ON silver.customer_status_history (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_customer_status_history_silver_updated_at_timestamp ON silver.customer_status_history (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_customer_status_history_silver_row_hash ON silver.customer_status_history (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_customer_status_history_silver_is_deleted_flag ON silver.customer_status_history (silver_is_deleted_flag);
CREATE INDEX IF NOT EXISTS idx_customer_status_history_silver_customer_id ON silver.customer_status_history (silver_customer_id);

-- payment_method
CREATE INDEX IF NOT EXISTS idx_payment_method_silver_payment_method_id ON silver.payment_method (silver_payment_method_id);
CREATE INDEX IF NOT EXISTS idx_payment_method_silver_batch_id ON silver.payment_method (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_payment_method_silver_updated_at_timestamp ON silver.payment_method (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_payment_method_silver_row_hash ON silver.payment_method (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_payment_method_silver_is_deleted_flag ON silver.payment_method (silver_is_deleted_flag);

-- payment_type
CREATE INDEX IF NOT EXISTS idx_payment_type_silver_payment_type_id ON silver.payment_type (silver_payment_type_id);
CREATE INDEX IF NOT EXISTS idx_payment_type_silver_batch_id ON silver.payment_type (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_payment_type_silver_updated_at_timestamp ON silver.payment_type (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_payment_type_silver_row_hash ON silver.payment_type (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_payment_type_silver_is_deleted_flag ON silver.payment_type (silver_is_deleted_flag);

-- tax_rate
CREATE INDEX IF NOT EXISTS idx_tax_rate_silver_tax_rate_id ON silver.tax_rate (silver_tax_rate_id);
CREATE INDEX IF NOT EXISTS idx_tax_rate_silver_batch_id ON silver.tax_rate (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_tax_rate_silver_updated_at_timestamp ON silver.tax_rate (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_tax_rate_silver_row_hash ON silver.tax_rate (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_tax_rate_silver_is_deleted_flag ON silver.tax_rate (silver_is_deleted_flag);

-- state
CREATE INDEX IF NOT EXISTS idx_state_silver_state_code ON silver.state (silver_state_code);
CREATE INDEX IF NOT EXISTS idx_state_silver_batch_id ON silver.state (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_state_silver_updated_at_timestamp ON silver.state (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_state_silver_row_hash ON silver.state (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_state_silver_is_deleted_flag ON silver.state (silver_is_deleted_flag);

-- invoice_status
CREATE INDEX IF NOT EXISTS idx_invoice_status_silver_status_code ON silver.invoice_status (silver_status_code);
CREATE INDEX IF NOT EXISTS idx_invoice_status_silver_batch_id ON silver.invoice_status (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_invoice_status_silver_updated_at_timestamp ON silver.invoice_status (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_invoice_status_silver_row_hash ON silver.invoice_status (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_invoice_status_silver_is_deleted_flag ON silver.invoice_status (silver_is_deleted_flag);

-- payment_status
CREATE INDEX IF NOT EXISTS idx_payment_status_silver_status_code ON silver.payment_status (silver_status_code);
CREATE INDEX IF NOT EXISTS idx_payment_status_silver_batch_id ON silver.payment_status (silver_batch_id);
CREATE INDEX IF NOT EXISTS idx_payment_status_silver_updated_at_timestamp ON silver.payment_status (silver_updated_at_timestamp);
CREATE INDEX IF NOT EXISTS idx_payment_status_silver_row_hash ON silver.payment_status (silver_row_hash);
CREATE INDEX IF NOT EXISTS idx_payment_status_silver_is_deleted_flag ON silver.payment_status (silver_is_deleted_flag);

-- =====================================================================
-- PrintTimeUSA Data Warehouse | Gold Layer
-- 003_create_gold_indexes.sql
-- Dimensions: natural key + is_current (current-version lookup) and
-- valid_from/valid_to (as-of lookup). Facts: one index per FK key.
-- dim_date: calendar lookup indexes.
-- =====================================================================

SET search_path = gold, public;


-- ---------------------------------------------------------------------
-- Dimension indexes (SCD2: natural key + is_current, plus valid range)
-- ---------------------------------------------------------------------

-- dim_date (conformed calendar)
CREATE INDEX IF NOT EXISTS idx_dim_date_date ON gold.dim_date (date);
CREATE INDEX IF NOT EXISTS idx_dim_date_calendar_year_month ON gold.dim_date (calendar_year_month);

-- dim_cashier
CREATE INDEX IF NOT EXISTS idx_dim_cashier_cashier_id_is_current ON gold.dim_cashier (cashier_id, is_current);
CREATE INDEX IF NOT EXISTS idx_dim_cashier_valid_from_valid_to ON gold.dim_cashier (valid_from, valid_to);

-- dim_product
CREATE INDEX IF NOT EXISTS idx_dim_product_sku_number_is_current ON gold.dim_product (sku_number, is_current);
CREATE INDEX IF NOT EXISTS idx_dim_product_valid_from_valid_to ON gold.dim_product (valid_from, valid_to);

-- dim_customer
CREATE INDEX IF NOT EXISTS idx_dim_customer_customer_id_is_current ON gold.dim_customer (customer_id, is_current);
CREATE INDEX IF NOT EXISTS idx_dim_customer_valid_from_valid_to ON gold.dim_customer (valid_from, valid_to);
CREATE INDEX IF NOT EXISTS idx_dim_customer_first_order_date_key ON gold.dim_customer (first_order_date_key);

-- dim_store
CREATE INDEX IF NOT EXISTS idx_dim_store_store_id_is_current ON gold.dim_store (store_id, is_current);
CREATE INDEX IF NOT EXISTS idx_dim_store_valid_from_valid_to ON gold.dim_store (valid_from, valid_to);

-- dim_invoice
CREATE INDEX IF NOT EXISTS idx_dim_invoice_invoice_number_is_current ON gold.dim_invoice (invoice_number, is_current);
CREATE INDEX IF NOT EXISTS idx_dim_invoice_valid_from_valid_to ON gold.dim_invoice (valid_from, valid_to);

-- dim_payment_method
CREATE INDEX IF NOT EXISTS idx_dim_payment_method_method_code_is_current ON gold.dim_payment_method (method_code, is_current);
CREATE INDEX IF NOT EXISTS idx_dim_payment_method_valid_from_valid_to ON gold.dim_payment_method (valid_from, valid_to);

-- dim_payment_type (static Type-1: natural key only)
CREATE INDEX IF NOT EXISTS idx_dim_payment_type_type_code ON gold.dim_payment_type (type_code);


-- ---------------------------------------------------------------------
-- Fact indexes (one per foreign key)
-- ---------------------------------------------------------------------

-- fact_retail_sales
CREATE INDEX IF NOT EXISTS idx_fact_retail_sales_date_key ON gold.fact_retail_sales (date_key);
CREATE INDEX IF NOT EXISTS idx_fact_retail_sales_cashier_key ON gold.fact_retail_sales (cashier_key);
CREATE INDEX IF NOT EXISTS idx_fact_retail_sales_product_key ON gold.fact_retail_sales (product_key);
CREATE INDEX IF NOT EXISTS idx_fact_retail_sales_customer_key ON gold.fact_retail_sales (customer_key);
CREATE INDEX IF NOT EXISTS idx_fact_retail_sales_store_key ON gold.fact_retail_sales (store_key);
CREATE INDEX IF NOT EXISTS idx_fact_retail_sales_invoice_key ON gold.fact_retail_sales (invoice_key);

-- fact_payments
CREATE INDEX IF NOT EXISTS idx_fact_payments_invoice_key ON gold.fact_payments (invoice_key);
CREATE INDEX IF NOT EXISTS idx_fact_payments_customer_key ON gold.fact_payments (customer_key);
CREATE INDEX IF NOT EXISTS idx_fact_payments_payment_method_key ON gold.fact_payments (payment_method_key);
CREATE INDEX IF NOT EXISTS idx_fact_payments_date_key ON gold.fact_payments (date_key);
CREATE INDEX IF NOT EXISTS idx_fact_payments_payment_type_key ON gold.fact_payments (payment_type_key);
CREATE INDEX IF NOT EXISTS idx_fact_payments_cashier_key ON gold.fact_payments (cashier_key);
CREATE INDEX IF NOT EXISTS idx_fact_payments_store_key ON gold.fact_payments (store_key);
CREATE INDEX IF NOT EXISTS idx_fact_payments_parent_payment_key ON gold.fact_payments (parent_payment_key);

-- fact_customer_behavior_snapshot
CREATE INDEX IF NOT EXISTS idx_fact_customer_behavior_snapshot_snapshot_date_key ON gold.fact_customer_behavior_snapshot (snapshot_date_key);
CREATE INDEX IF NOT EXISTS idx_fact_customer_behavior_snapshot_customer_key ON gold.fact_customer_behavior_snapshot (customer_key);
CREATE INDEX IF NOT EXISTS idx_fact_customer_behavior_snapshot_last_order_date_key ON gold.fact_customer_behavior_snapshot (last_order_date_key);

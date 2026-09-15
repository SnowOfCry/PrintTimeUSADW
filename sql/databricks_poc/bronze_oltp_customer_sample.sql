-- =============================================================================
-- bronze_oltp_customer_sample.sql  (Databricks / Unity Catalog — POC seed)
-- -----------------------------------------------------------------------------
-- Creates and populates a SMALL sample of bronze.oltp_customer directly in
-- Databricks so the silver.customer model can be built and tested WITHOUT the
-- (offline) local OLTP source. Rows are hand-crafted to exercise the silver
-- cleaning logic: business vs person names, messy whitespace, mixed-case email,
-- formatted phone, and the active/inactive/unknown status vocabulary.
--
-- Run this in the Databricks SQL editor (warehouse = your serverless one).
-- Postgres types translated to Databricks: VARCHAR(n)->STRING, JSONB->STRING,
-- BIGSERIAL->BIGINT (explicit ids), TIMESTAMP/DATE/BOOLEAN unchanged.
-- =============================================================================

CREATE TABLE IF NOT EXISTS printtime_dw.bronze.oltp_customer (
    bronze_record_id                BIGINT,
    customer_id                     BIGINT,
    customer_account_no             STRING,
    business_name                   STRING,
    first_name                      STRING,
    last_name                       STRING,
    full_name                       STRING,
    email                           STRING,
    phone                           STRING,
    customer_status                 STRING,
    default_tax_rate_id             BIGINT,
    home_store_id                   BIGINT,
    first_order_date                DATE,
    created_at_source_timestamp     TIMESTAMP,
    updated_at_source_timestamp     TIMESTAMP,
    source_row_version              INT,
    is_deleted_source_flag          BOOLEAN,
    deleted_at_source_timestamp     TIMESTAMP,
    bronze_batch_id                 BIGINT,
    bronze_loaded_at_timestamp      TIMESTAMP,
    bronze_extracted_at_timestamp   TIMESTAMP,
    bronze_source_system            STRING,
    bronze_source_table_name        STRING,
    bronze_source_file_name         STRING,
    bronze_source_row_number        BIGINT,
    bronze_row_hash                 STRING,
    bronze_is_deleted_flag          BOOLEAN,
    bronze_raw_payload_jsonb        STRING
);

-- Start clean each time you run this seed (POC only).
TRUNCATE TABLE printtime_dw.bronze.oltp_customer;

INSERT INTO printtime_dw.bronze.oltp_customer
    (bronze_record_id, customer_id, customer_account_no, business_name, first_name, last_name,
     full_name, email, phone, customer_status, default_tax_rate_id, home_store_id, first_order_date,
     created_at_source_timestamp, updated_at_source_timestamp, source_row_version,
     is_deleted_source_flag, deleted_at_source_timestamp, bronze_batch_id,
     bronze_loaded_at_timestamp, bronze_extracted_at_timestamp, bronze_source_system,
     bronze_source_table_name, bronze_source_file_name, bronze_source_row_number,
     bronze_row_hash, bronze_is_deleted_flag, bronze_raw_payload_jsonb)
VALUES
    -- 1. Business customer, messy whitespace in name, formatted phone, mixed-case email, active
    (1, 101, 'ACC-101', '  Acme   Printing   LLC ', 'john', 'doe', 'John Doe',
     '  John.DOE@Acme.com ', '(555) 123-4567', 'active', 10, 1, DATE'2023-01-15',
     TIMESTAMP'2023-01-15 09:00:00', TIMESTAMP'2024-02-01 11:30:00', 2,
     false, NULL, 1, current_timestamp(), TIMESTAMP'2024-02-01 12:00:00', 'oltp',
     'customer', NULL, 1, 'hash_row_1', false, '{"customer_id":101}'),

    -- 2. Person customer (no business name), active
    (2, 102, 'ACC-102', NULL, '  maria ', ' garcia  ', 'Maria Garcia',
     'maria.garcia@example.com', '555.222.3333', 'active', 10, 2, DATE'2023-03-20',
     TIMESTAMP'2023-03-20 10:00:00', TIMESTAMP'2023-03-20 10:00:00', 1,
     false, NULL, 1, current_timestamp(), TIMESTAMP'2023-03-20 10:05:00', 'oltp',
     'customer', NULL, 2, 'hash_row_2', false, '{"customer_id":102}'),

    -- 3. Inactive customer
    (3, 103, 'ACC-103', 'Bright Signs Co', NULL, NULL, NULL,
     'info@brightsigns.com', '5559998888', 'inactive', 20, 1, DATE'2022-11-01',
     TIMESTAMP'2022-11-01 08:00:00', TIMESTAMP'2023-12-15 14:00:00', 3,
     false, NULL, 1, current_timestamp(), TIMESTAMP'2023-12-15 14:10:00', 'oltp',
     'customer', NULL, 3, 'hash_row_3', false, '{"customer_id":103}'),

    -- 4. Status with caps + trailing space -> should normalize to 'active'
    (4, 104, 'ACC-104', NULL, 'Bob', 'Smith', 'Bob Smith',
     'BOB@smith.io', '1 (555) 444-0000', 'Active ', NULL, 3, DATE'2024-05-10',
     TIMESTAMP'2024-05-10 07:30:00', TIMESTAMP'2024-05-10 07:30:00', 1,
     false, NULL, 1, current_timestamp(), TIMESTAMP'2024-05-10 07:35:00', 'oltp',
     'customer', NULL, 4, 'hash_row_4', false, '{"customer_id":104}'),

    -- 5. Unknown status ('suspended') -> should become NULL, is_active_flag false
    (5, 105, 'ACC-105', 'Old Town Press', NULL, NULL, NULL,
     'contact@oldtownpress.com', '555-777-1212', 'suspended', 10, 2, NULL,
     TIMESTAMP'2021-06-01 09:00:00', TIMESTAMP'2023-01-01 09:00:00', 5,
     false, NULL, 1, current_timestamp(), TIMESTAMP'2023-01-01 09:05:00', 'oltp',
     'customer', NULL, 5, 'hash_row_5', false, '{"customer_id":105}'),

    -- 6. Duplicate customer_id 101 with a NEWER updated_at -> dedup should keep THIS row
    (6, 101, 'ACC-101', 'Acme Printing LLC', 'john', 'doe', 'John Doe',
     'john.doe@acme.com', '(555) 123-4567', 'active', 10, 1, DATE'2023-01-15',
     TIMESTAMP'2023-01-15 09:00:00', TIMESTAMP'2024-06-01 08:00:00', 3,
     false, NULL, 1, current_timestamp(), TIMESTAMP'2024-06-01 08:05:00', 'oltp',
     'customer', NULL, 6, 'hash_row_6', false, '{"customer_id":101}');

-- Quick check
SELECT customer_id, business_name, customer_status, updated_at_source_timestamp
FROM printtime_dw.bronze.oltp_customer
ORDER BY customer_id, updated_at_source_timestamp;

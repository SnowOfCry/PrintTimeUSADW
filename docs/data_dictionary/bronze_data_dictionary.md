# Bronze Data Dictionary

PrintTimeUSA Data Warehouse | Bronze landing layer. Every column of every Bronze table is documented below. Each table carries the same standard metadata block; it is documented in full for the first table and referenced thereafter, but the columns physically exist on every table.

Tables: 20

## bronze.oltp_customer

- **Source system:** oltp
- **Source table/file:** customer
- **Source PK:** customer_id
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** dim_customer, fact_customer_behavior_snapshot

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| customer_id | BIGINT | NOT NULL | Source surrogate id of the customer. | customer.customer_id | 4821 |
| customer_account_no | VARCHAR(30) | NULL | Customer account number (natural business key used by dim_customer). | customer.customer_account_no | ACCT-027612 |
| business_name | VARCHAR(150) | NULL | Customer business/company name. | customer.business_name | Bronco Winery |
| first_name | VARCHAR(50) | NULL | Contact first name. | customer.first_name | Luis |
| last_name | VARCHAR(50) | NULL | Contact last name. | customer.last_name | Lopez |
| full_name | VARCHAR(101) | NULL | Source-provided full name. | customer.full_name | Luis Lopez |
| email | VARCHAR(150) | NULL | Customer email address. | customer.email | luis@example.com |
| phone | VARCHAR(20) | NULL | Customer phone number. | customer.phone | 209-555-0142 |
| customer_status | VARCHAR(20) | NULL | Source status of the customer (e.g. ACTIVE, INACTIVE). | customer.customer_status | ACTIVE |
| default_tax_rate_id | BIGINT | NULL | FK to the customer's default tax rate (raw, not enforced in Bronze). | customer.default_tax_rate_id | 1 |
| home_store_id | BIGINT | NULL | FK to the customer's home store (raw). | customer.home_store_id | 1 |
| first_order_date | DATE | NULL | Date of the customer's first order as recorded in the source. | customer.first_order_date | 2024-03-11 |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | customer.created_at | 2024-03-11 10:02:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; primary incremental watermark. | customer.source_updated_at (fallback updated_at) | 2026-06-01 14:30:00 |
| source_row_version | INTEGER | NULL | Source row_version counter for change tracking. | customer.row_version | 3 |
| is_deleted_source_flag | BOOLEAN | NULL | Source soft-delete flag as extracted. | customer.is_deleted | false |
| deleted_at_source_timestamp | TIMESTAMP | NULL | Source soft-delete timestamp. | customer.deleted_at | NULL |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | customer |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.oltp_customer_address

- **Source system:** oltp
- **Source table/file:** customer_address
- **Source PK:** address_id
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** dim_customer

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| address_id | BIGINT | NOT NULL | Source surrogate id of the address. | customer_address.address_id | 9931 |
| customer_id | BIGINT | NULL | FK to the owning customer (raw). | customer_address.customer_id | 4821 |
| address_type | VARCHAR(20) | NULL | Address type such as BILLING or SHIPPING. | customer_address.address_type | BILLING |
| street_address | VARCHAR(200) | NULL | Primary street address line. | customer_address.street_address | 1225 H St |
| street_address2 | VARCHAR(100) | NULL | Secondary street address line. | customer_address.street_address2 | Suite 200 |
| city | VARCHAR(100) | NULL | City. | customer_address.city | Modesto |
| state_code | VARCHAR(2) | NULL | Two-letter state code. | customer_address.state_code | CA |
| zip_code | VARCHAR(10) | NULL | ZIP / postal code. | customer_address.zip_code | 95354 |
| is_primary_flag | BOOLEAN | NULL | Whether this is the customer's primary address. | customer_address.is_primary | true |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | customer_address.created_at | 2024-03-11 10:02:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | customer_address.updated_at | 2026-05-20 08:00:00 |
| is_deleted_source_flag | BOOLEAN | NULL | Source soft-delete flag. | customer_address.is_deleted | false |
| deleted_at_source_timestamp | TIMESTAMP | NULL | Source soft-delete timestamp. | customer_address.deleted_at | NULL |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | customer_address |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.oltp_product

- **Source system:** oltp
- **Source table/file:** product
- **Source PK:** product_id
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** dim_product, fact_retail_sales

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| product_id | BIGINT | NOT NULL | Source surrogate id of the product. | product.product_id | 512 |
| sku | VARCHAR(50) | NULL | Stock keeping unit (natural key for dim_product). | product.sku | BC-14PT-UV |
| product_name | VARCHAR(200) | NULL | Product name. | product.product_name | Business Cards 14pt UV |
| description | VARCHAR(500) | NULL | Product description. | product.description | Full color 14pt gloss UV |
| department_id | BIGINT | NULL | FK to department (raw). | product.department_id | 4 |
| category_id | BIGINT | NULL | FK to product_category (raw). | product.category_id | 21 |
| brand | VARCHAR(100) | NULL | Brand name. | product.brand | 4over |
| unit_cost_amount | NUMERIC(12,2) | NULL | Unit cost. | product.unit_cost | 12.50 |
| markup_pct | NUMERIC(8,4) | NULL | Markup percentage applied to cost. | product.markup_pct | 200.0000 |
| standard_price_amount | NUMERIC(12,2) | NULL | Standard selling price. | product.standard_price | 37.50 |
| is_local_made_flag | BOOLEAN | NULL | Whether the product is locally made. | product.is_local_made | true |
| is_active_flag | BOOLEAN | NULL | Whether the product is active. | product.is_active | true |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | product.created_at | 2024-01-05 09:00:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | product.source_updated_at (fallback updated_at) | 2026-04-02 11:15:00 |
| source_row_version | INTEGER | NULL | Source row_version counter. | product.row_version | 2 |
| is_deleted_source_flag | BOOLEAN | NULL | Source soft-delete flag. | product.is_deleted | false |
| deleted_at_source_timestamp | TIMESTAMP | NULL | Source soft-delete timestamp. | product.deleted_at | NULL |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | product |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.oltp_product_category

- **Source system:** oltp
- **Source table/file:** product_category
- **Source PK:** category_id
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** dim_product

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| category_id | BIGINT | NOT NULL | Source surrogate id of the category. | product_category.category_id | 21 |
| department_id | BIGINT | NULL | FK to the owning department (raw). | product_category.department_id | 4 |
| category_code | VARCHAR(40) | NULL | Category code. | product_category.category_code | BUS_CARDS |
| category_name | VARCHAR(100) | NULL | Category display name. | product_category.category_name | Business Cards |
| description | VARCHAR(200) | NULL | Category description. | product_category.description | Standard printed business cards |
| is_active_flag | BOOLEAN | NULL | Whether the category is active. | product_category.is_active | true |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | product_category.created_at | 2024-01-05 09:00:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | product_category.updated_at | 2025-12-01 10:00:00 |
| is_deleted_source_flag | BOOLEAN | NULL | Source soft-delete flag. | product_category.is_deleted | false |
| deleted_at_source_timestamp | TIMESTAMP | NULL | Source soft-delete timestamp. | product_category.deleted_at | NULL |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | product_category |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.oltp_department

- **Source system:** oltp
- **Source table/file:** department
- **Source PK:** department_id
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** dim_product

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| department_id | BIGINT | NOT NULL | Source surrogate id of the department. | department.department_id | 4 |
| department_code | VARCHAR(20) | NULL | Department code. | department.department_code | PRINT |
| department_name | VARCHAR(100) | NULL | Department display name. | department.department_name | Printing |
| description | VARCHAR(200) | NULL | Department description. | department.description | Offset and digital printing |
| is_active_flag | BOOLEAN | NULL | Whether the department is active. | department.is_active | true |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | department.created_at | 2024-01-01 09:00:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | department.updated_at | 2024-01-01 09:00:00 |
| is_deleted_source_flag | BOOLEAN | NULL | Source soft-delete flag. | department.is_deleted | false |
| deleted_at_source_timestamp | TIMESTAMP | NULL | Source soft-delete timestamp. | department.deleted_at | NULL |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | department |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.oltp_employee

- **Source system:** oltp
- **Source table/file:** employee
- **Source PK:** employee_id
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** dim_cashier

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| employee_id | BIGINT | NOT NULL | Source surrogate id of the employee. | employee.employee_id | 17 |
| employee_code | VARCHAR(30) | NULL | Employee code (natural key for dim_cashier). | employee.employee_code | EMP-017 |
| first_name | VARCHAR(50) | NULL | Employee first name. | employee.first_name | Maria |
| last_name | VARCHAR(50) | NULL | Employee last name. | employee.last_name | Santos |
| full_name | VARCHAR(101) | NULL | Source-provided full name. | employee.full_name | Maria Santos |
| email | VARCHAR(150) | NULL | Employee email. | employee.email | maria@printtime.example |
| phone | VARCHAR(20) | NULL | Employee phone. | employee.phone | 209-555-0190 |
| role | VARCHAR(30) | NULL | Employee role (e.g. CASHIER, MANAGER). | employee.role | CASHIER |
| store_id | BIGINT | NULL | FK to the employee's store (raw). | employee.store_id | 1 |
| hire_date | DATE | NULL | Hire date. | employee.hire_date | 2023-09-01 |
| is_active_flag | BOOLEAN | NULL | Whether the employee is active. | employee.is_active | true |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | employee.created_at | 2023-09-01 08:00:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | employee.source_updated_at (fallback updated_at) | 2026-02-10 09:30:00 |
| source_row_version | INTEGER | NULL | Source row_version counter. | employee.row_version | 2 |
| is_deleted_source_flag | BOOLEAN | NULL | Source soft-delete flag. | employee.is_deleted | false |
| deleted_at_source_timestamp | TIMESTAMP | NULL | Source soft-delete timestamp. | employee.deleted_at | NULL |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | employee |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.oltp_store

- **Source system:** oltp
- **Source table/file:** store
- **Source PK:** store_id
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** dim_store, dim_cashier, dim_invoice

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| store_id | BIGINT | NOT NULL | Source surrogate id of the store. | store.store_id | 1 |
| store_code | VARCHAR(30) | NULL | Store code (natural key for dim_store). | store.store_code | ST-MOD |
| store_name | VARCHAR(100) | NULL | Store display name. | store.store_name | PrintTime Modesto |
| street_address | VARCHAR(200) | NULL | Store street address. | store.street_address | 1225 H St |
| city | VARCHAR(100) | NULL | Store city. | store.city | Modesto |
| state_code | VARCHAR(2) | NULL | Store state code. | store.state_code | CA |
| zip_code | VARCHAR(10) | NULL | Store ZIP code. | store.zip_code | 95354 |
| phone | VARCHAR(20) | NULL | Store phone. | store.phone | 209-529-9850 |
| region | VARCHAR(50) | NULL | Store region. | store.region | Central Valley |
| store_type | VARCHAR(50) | NULL | Store type (e.g. FLAGSHIP, SATELLITE). | store.store_type | FLAGSHIP |
| open_date | DATE | NULL | Store open date. | store.open_date | 2018-05-01 |
| is_active_flag | BOOLEAN | NULL | Whether the store is active. | store.is_active | true |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | store.created_at | 2018-05-01 08:00:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | store.source_updated_at (fallback updated_at) | 2025-11-01 12:00:00 |
| source_row_version | INTEGER | NULL | Source row_version counter. | store.row_version | 1 |
| is_deleted_source_flag | BOOLEAN | NULL | Source soft-delete flag. | store.is_deleted | false |
| deleted_at_source_timestamp | TIMESTAMP | NULL | Source soft-delete timestamp. | store.deleted_at | NULL |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | store |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.oltp_invoice

- **Source system:** oltp
- **Source table/file:** invoice
- **Source PK:** invoice_id
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** dim_invoice, fact_retail_sales, fact_payments, fact_customer_behavior_snapshot

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| invoice_id | BIGINT | NOT NULL | Source surrogate id of the invoice. | invoice.invoice_id | 1001 |
| invoice_number | VARCHAR(30) | NULL | Invoice number (natural key for dim_invoice). | invoice.invoice_number | 32390 |
| customer_id | BIGINT | NULL | FK to the customer (raw). | invoice.customer_id | 4821 |
| store_id | BIGINT | NULL | FK to the store (raw). | invoice.store_id | 1 |
| employee_id | BIGINT | NULL | FK to the employee/cashier (raw). | invoice.employee_id | 17 |
| billing_address_id | BIGINT | NULL | FK to the billing address (raw). | invoice.billing_address_id | 9931 |
| shipping_address_id | BIGINT | NULL | FK to the shipping address (raw). | invoice.shipping_address_id | 9932 |
| po_number | VARCHAR(50) | NULL | Customer purchase order number. | invoice.po_number | PO-55821 |
| invoice_date | DATE | NULL | Invoice date. | invoice.invoice_date | 2025-11-14 |
| invoice_due_date | DATE | NULL | Payment due date. | invoice.due_date | 2025-12-14 |
| invoice_status | VARCHAR(20) | NULL | Invoice status (OPEN, PARTIAL, PAID, VOID). Each change is captured as a new appended Bronze row. | invoice.status_code | PAID |
| tax_rate_id | BIGINT | NULL | FK to the applied tax rate (raw). | invoice.tax_rate_id | 1 |
| subtotal_amount | NUMERIC(12,2) | NULL | Sum of line extended amounts before tax/fee. | invoice.subtotal_amount | 450.00 |
| discount_amount | NUMERIC(12,2) | NULL | Header-level discount. | invoice.discount_amount | 0.00 |
| tax_amount | NUMERIC(12,2) | NULL | Tax charged. | invoice.tax_amount | 39.94 |
| fee_amount | NUMERIC(12,2) | NULL | Card processing fee. | invoice.fee_amount | 14.70 |
| total_amount | NUMERIC(12,2) | NULL | Invoice total (subtotal - discount + tax + fee). | invoice.total_amount | 504.64 |
| paid_amount | NUMERIC(12,2) | NULL | Amount paid so far. | invoice.paid_amount | 504.64 |
| balance_due_amount | NUMERIC(12,2) | NULL | Outstanding balance. | invoice.balance_due | 0.00 |
| notes | VARCHAR(1000) | NULL | Free-text invoice notes. | invoice.notes | Embroidery - Bronco/Bivio logo |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | invoice.created_at | 2025-11-14 10:30:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; primary incremental watermark and the trigger that captures status changes. | invoice.source_updated_at (fallback updated_at) | 2025-11-20 16:45:00 |
| source_row_version | INTEGER | NULL | Source row_version counter. | invoice.row_version | 4 |
| is_deleted_source_flag | BOOLEAN | NULL | Source soft-delete flag. | invoice.is_deleted | false |
| deleted_at_source_timestamp | TIMESTAMP | NULL | Source soft-delete timestamp. | invoice.deleted_at | NULL |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | invoice |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.oltp_invoice_line

- **Source system:** oltp
- **Source table/file:** invoice_line
- **Source PK:** invoice_line_id
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** fact_retail_sales

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| invoice_line_id | BIGINT | NOT NULL | Source surrogate id of the line. | invoice_line.invoice_line_id | 880231 |
| invoice_id | BIGINT | NULL | FK to the parent invoice (raw). | invoice_line.invoice_id | 1001 |
| line_number | SMALLINT | NULL | Line sequence within the invoice. | invoice_line.line_number | 1 |
| product_id | BIGINT | NULL | FK to the product (raw). | invoice_line.product_id | 512 |
| variant_id | BIGINT | NULL | FK to the product variant (raw). | invoice_line.variant_id | 77 |
| line_description | VARCHAR(300) | NULL | Line description. | invoice_line.description | Nike polo embroidery |
| color | VARCHAR(40) | NULL | Color attribute for the line. | invoice_line.color | Navy |
| order_qty | INTEGER | NULL | Quantity ordered on the line. | invoice_line.quantity | 12 |
| unit_price_amount | NUMERIC(12,2) | NULL | Unit selling price. | invoice_line.unit_price | 37.50 |
| unit_cost_amount | NUMERIC(12,2) | NULL | Unit cost. | invoice_line.unit_cost | 12.50 |
| discount_amount | NUMERIC(12,2) | NULL | Line-level discount. | invoice_line.discount_amount | 0.00 |
| line_total_amount | NUMERIC(12,2) | NULL | Extended amount (qty*price - discount). | invoice_line.extended_amount | 450.00 |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | invoice_line.created_at | 2025-11-14 10:30:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | invoice_line.updated_at | 2025-11-14 10:30:00 |
| is_deleted_source_flag | BOOLEAN | NULL | Source soft-delete flag. | invoice_line.is_deleted | false |
| deleted_at_source_timestamp | TIMESTAMP | NULL | Source soft-delete timestamp. | invoice_line.deleted_at | NULL |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | invoice_line |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.oltp_payment

- **Source system:** oltp
- **Source table/file:** payment
- **Source PK:** payment_id
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** fact_payments

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| payment_id | BIGINT | NOT NULL | Source surrogate id of the payment. | payment.payment_id | 660014 |
| invoice_id | BIGINT | NULL | FK to the paid invoice (raw). | payment.invoice_id | 1001 |
| customer_id | BIGINT | NULL | FK to the customer (raw). | payment.customer_id | 4821 |
| payment_method_id | BIGINT | NULL | FK to the payment method (raw). | payment.payment_method_id | 2 |
| payment_type_id | BIGINT | NULL | FK to the payment type (raw). | payment.payment_type_id | 1 |
| employee_id | BIGINT | NULL | FK to the employee/cashier (raw). | payment.employee_id | 17 |
| store_id | BIGINT | NULL | FK to the store (raw). | payment.store_id | 1 |
| parent_payment_id | BIGINT | NULL | Self-reference to the originating payment (set on refunds). | payment.parent_payment_id | 660010 |
| payment_sequence_num | SMALLINT | NULL | Sequence of the payment for the invoice (1=deposit, 2=balance, ...). | payment.payment_sequence | 2 |
| payment_status | VARCHAR(20) | NULL | Payment status. | payment.payment_status | COMPLETED |
| payment_date | DATE | NULL | Payment date. | payment.payment_date | 2025-11-20 |
| gross_amount | NUMERIC(12,2) | NULL | Gross payment amount (negative for refunds). | payment.gross_amount | 252.32 |
| tax_amount | NUMERIC(12,2) | NULL | Tax portion of the payment. | payment.tax_amount | 19.97 |
| fee_amount | NUMERIC(12,2) | NULL | Card processing fee portion. | payment.fee_amount | 7.35 |
| net_amount | NUMERIC(12,2) | NULL | Net cash impact (gross - fee). | payment.net_amount | 244.97 |
| reference_no | VARCHAR(60) | NULL | External payment reference (auth code, check no). | payment.reference_no | AUTH-99213 |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | payment.created_at | 2025-11-20 16:45:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | payment.source_updated_at (fallback updated_at) | 2025-11-20 16:45:00 |
| source_row_version | INTEGER | NULL | Source row_version counter. | payment.row_version | 1 |
| is_deleted_source_flag | BOOLEAN | NULL | Source soft-delete flag. | payment.is_deleted | false |
| deleted_at_source_timestamp | TIMESTAMP | NULL | Source soft-delete timestamp. | payment.deleted_at | NULL |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | payment |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.oltp_invoice_status_history

- **Source system:** oltp
- **Source table/file:** invoice_status_history
- **Source PK:** status_history_id
- **Watermark column:** changed_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** dim_invoice

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| status_history_id | BIGINT | NOT NULL | Source surrogate id of the status change. | invoice_status_history.status_history_id | 300551 |
| invoice_id | BIGINT | NULL | FK to the invoice (raw). | invoice_status_history.invoice_id | 1001 |
| old_status | VARCHAR(20) | NULL | Status before the change. | invoice_status_history.old_status | PARTIAL |
| new_status | VARCHAR(20) | NULL | Status after the change. | invoice_status_history.new_status | PAID |
| changed_at_source_timestamp | TIMESTAMP | NULL | When the status change occurred; incremental watermark. | invoice_status_history.changed_at | 2025-11-20 16:45:00 |
| changed_by | BIGINT | NULL | Employee id that made the change (raw). | invoice_status_history.changed_by | 17 |
| note | VARCHAR(200) | NULL | Free-text note about the change. | invoice_status_history.note | Balance paid in full |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | invoice_status_history |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.oltp_customer_status_history

- **Source system:** oltp
- **Source table/file:** customer_status_history
- **Source PK:** status_history_id
- **Watermark column:** changed_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** fact_customer_behavior_snapshot

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| status_history_id | BIGINT | NOT NULL | Source surrogate id of the status change. | customer_status_history.status_history_id | 12055 |
| customer_id | BIGINT | NULL | FK to the customer (raw). | customer_status_history.customer_id | 4821 |
| old_status | VARCHAR(20) | NULL | Status before the change. | customer_status_history.old_status | ACTIVE |
| new_status | VARCHAR(20) | NULL | Status after the change. | customer_status_history.new_status | INACTIVE |
| changed_at_source_timestamp | TIMESTAMP | NULL | When the status change occurred; incremental watermark. | customer_status_history.changed_at | 2026-01-15 09:00:00 |
| changed_by | BIGINT | NULL | Employee id that made the change (raw). | customer_status_history.changed_by | 17 |
| reason | VARCHAR(200) | NULL | Reason for the status change. | customer_status_history.reason | No orders in 12 months |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | customer_status_history |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.oltp_refund

- **Source system:** oltp
- **Source table/file:** refund
- **Source PK:** refund_id
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** fact_payments

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| refund_id | BIGINT | NOT NULL | Source surrogate id of the refund. | refund.refund_id | 4401 |
| payment_id | BIGINT | NULL | FK to the original payment (raw). | refund.payment_id | 660010 |
| invoice_id | BIGINT | NULL | FK to the invoice (raw). | refund.invoice_id | 1001 |
| refund_amount | NUMERIC(12,2) | NULL | Refunded amount. | refund.refund_amount | 50.00 |
| refund_date | DATE | NULL | Refund date. | refund.refund_date | 2025-12-01 |
| reason | VARCHAR(200) | NULL | Reason for the refund. | refund.reason | Damaged item |
| refunded_by | BIGINT | NULL | Employee id that issued the refund (raw). | refund.refunded_by | 17 |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | refund.created_at | 2025-12-01 11:00:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | refund.updated_at | 2025-12-01 11:00:00 |
| is_deleted_source_flag | BOOLEAN | NULL | Source soft-delete flag. | refund.is_deleted | false |
| deleted_at_source_timestamp | TIMESTAMP | NULL | Source soft-delete timestamp. | refund.deleted_at | NULL |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | refund |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.oltp_invoice_adjustment

- **Source system:** oltp
- **Source table/file:** invoice_adjustment
- **Source PK:** adjustment_id
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** dim_invoice, fact_payments

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| adjustment_id | BIGINT | NOT NULL | Source surrogate id of the adjustment. | invoice_adjustment.adjustment_id | 7701 |
| invoice_id | BIGINT | NULL | FK to the invoice (raw). | invoice_adjustment.invoice_id | 1001 |
| adjustment_type | VARCHAR(20) | NULL | Adjustment type (CREDIT/DEBIT). | invoice_adjustment.adjustment_type | CREDIT |
| amount | NUMERIC(12,2) | NULL | Adjustment amount. | invoice_adjustment.amount | 25.00 |
| reason | VARCHAR(200) | NULL | Reason for the adjustment. | invoice_adjustment.reason | Goodwill credit |
| adjusted_by | BIGINT | NULL | Employee id that made the adjustment (raw). | invoice_adjustment.adjusted_by | 17 |
| adjustment_date | DATE | NULL | Adjustment date. | invoice_adjustment.adjustment_date | 2025-11-25 |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | invoice_adjustment.created_at | 2025-11-25 10:00:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | invoice_adjustment.updated_at | 2025-11-25 10:00:00 |
| is_deleted_source_flag | BOOLEAN | NULL | Source soft-delete flag. | invoice_adjustment.is_deleted | false |
| deleted_at_source_timestamp | TIMESTAMP | NULL | Source soft-delete timestamp. | invoice_adjustment.deleted_at | NULL |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | invoice_adjustment |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.ref_payment_method

- **Source system:** ref
- **Source table/file:** payment_method
- **Source PK:** payment_method_id
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** dim_payment_method

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| payment_method_id | BIGINT | NOT NULL | Source surrogate id of the payment method. | payment_method.payment_method_id | 2 |
| method_code | VARCHAR(20) | NULL | Method code (natural key for dim_payment_method). | payment_method.method_code | VISA |
| method_name | VARCHAR(50) | NULL | Method display name. | payment_method.method_name | Visa Credit Card |
| method_type | VARCHAR(30) | NULL | Method type (CARD/CASH/CHECK/ACH). | payment_method.method_type | CARD |
| is_card_flag | BOOLEAN | NULL | Whether the method is a card (drives the 3% fee). | payment_method.is_card | true |
| is_active_flag | BOOLEAN | NULL | Whether the method is active. | payment_method.is_active | true |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | payment_method.created_at | 2024-01-01 09:00:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | payment_method.source_updated_at (fallback updated_at) | 2024-01-01 09:00:00 |
| source_row_version | INTEGER | NULL | Source row_version counter. | payment_method.row_version | 1 |
| is_deleted_source_flag | BOOLEAN | NULL | Source soft-delete flag. | payment_method.is_deleted | false |
| deleted_at_source_timestamp | TIMESTAMP | NULL | Source soft-delete timestamp. | payment_method.deleted_at | NULL |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | payment_method |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.ref_payment_type

- **Source system:** ref
- **Source table/file:** payment_type
- **Source PK:** payment_type_id
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** dim_payment_type

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| payment_type_id | BIGINT | NOT NULL | Source surrogate id of the payment type. | payment_type.payment_type_id | 1 |
| type_code | VARCHAR(20) | NULL | Type code (natural key for dim_payment_type). | payment_type.type_code | DEPOSIT |
| type_name | VARCHAR(50) | NULL | Type display name. | payment_type.type_name | Deposit |
| description | VARCHAR(200) | NULL | Type description. | payment_type.description | Initial deposit payment |
| affects_balance_flag | BOOLEAN | NULL | Whether the type affects invoice balance. | payment_type.affects_balance | true |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | payment_type.created_at | 2024-01-01 09:00:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | payment_type.updated_at | 2024-01-01 09:00:00 |
| is_deleted_source_flag | BOOLEAN | NULL | Source soft-delete flag. | payment_type.is_deleted | false |
| deleted_at_source_timestamp | TIMESTAMP | NULL | Source soft-delete timestamp. | payment_type.deleted_at | NULL |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | payment_type |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.ref_tax_rate

- **Source system:** ref
- **Source table/file:** tax_rate
- **Source PK:** tax_rate_id
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** dim_invoice, fact_payments

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| tax_rate_id | BIGINT | NOT NULL | Source surrogate id of the tax rate. | tax_rate.tax_rate_id | 1 |
| tax_code | VARCHAR(20) | NULL | Tax code. | tax_rate.tax_code | STD |
| description | VARCHAR(100) | NULL | Tax rate description. | tax_rate.description | Modesto standard rate |
| rate_pct | NUMERIC(6,4) | NULL | Tax rate percentage. | tax_rate.rate_pct | 8.8750 |
| effective_from | DATE | NULL | Date the rate becomes effective. | tax_rate.effective_from | 2024-01-01 |
| effective_to | DATE | NULL | Date the rate stops being effective. | tax_rate.effective_to | NULL |
| is_active_flag | BOOLEAN | NULL | Whether the rate is active. | tax_rate.is_active | true |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | tax_rate.created_at | 2024-01-01 09:00:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | tax_rate.updated_at | 2024-01-01 09:00:00 |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | tax_rate |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.ref_state

- **Source system:** ref
- **Source table/file:** ref_state
- **Source PK:** state_code
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** dim_customer, dim_store

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| state_code | VARCHAR(2) | NOT NULL | Two-letter state code (natural key). | ref_state.state_code | CA |
| state_name | VARCHAR(50) | NULL | Full state name. | ref_state.state_name | California |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | ref_state.created_at | 2024-01-01 09:00:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | ref_state.updated_at | 2024-01-01 09:00:00 |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | ref_state |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.ref_invoice_status

- **Source system:** ref
- **Source table/file:** ref_invoice_status
- **Source PK:** status_code
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** dim_invoice

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| status_code | VARCHAR(20) | NOT NULL | Status code (natural key). | ref_invoice_status.status_code | PAID |
| status_name | VARCHAR(50) | NULL | Status display name. | ref_invoice_status.status_name | Paid |
| is_terminal_flag | BOOLEAN | NULL | Whether the status is terminal. | ref_invoice_status.is_terminal | true |
| sort_order | SMALLINT | NULL | Display/sort order. | ref_invoice_status.sort_order | 3 |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | ref_invoice_status.created_at | 2024-01-01 09:00:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | ref_invoice_status.updated_at | 2024-01-01 09:00:00 |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | ref_invoice_status |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |

## bronze.ref_payment_status

- **Source system:** ref
- **Source table/file:** ref_payment_status
- **Source PK:** status_code
- **Watermark column:** updated_at_source_timestamp
- **Load strategy:** incremental_append
- **Supports DW tables:** fact_payments

| Column | Data Type | Nullable | Description | Source / Origin | Example |
|---|---|---|---|---|---|
| bronze_record_id | BIGSERIAL | NOT NULL | Technical surrogate primary key for the Bronze row. Append-only; the source id may repeat across batches. | ETL metadata (generated) | 1 |
| status_code | VARCHAR(20) | NOT NULL | Status code (natural key). | ref_payment_status.status_code | COMPLETED |
| status_name | VARCHAR(50) | NULL | Status display name. | ref_payment_status.status_name | Completed |
| created_at_source_timestamp | TIMESTAMP | NULL | Source row creation timestamp. | ref_payment_status.created_at | 2024-01-01 09:00:00 |
| updated_at_source_timestamp | TIMESTAMP | NULL | Source last-updated timestamp; incremental watermark. | ref_payment_status.updated_at | 2024-01-01 09:00:00 |
| bronze_batch_id | BIGINT | NOT NULL | Identifies the ETL batch that loaded this row. Joins to audit.etl_batch_control.batch_key. | ETL metadata | 10427 |
| bronze_loaded_at_timestamp | TIMESTAMP | NOT NULL | Timestamp when the row was written into Bronze (load time). | ETL metadata (DEFAULT CURRENT_TIMESTAMP) | 2026-06-18 09:14:22 |
| bronze_extracted_at_timestamp | TIMESTAMP | NULL | Timestamp when the extractor pulled the row from the source. | ETL metadata | 2026-06-18 09:14:01 |
| bronze_source_system | VARCHAR(100) | NOT NULL | Source system identifier (e.g. oltp, 4over_csv, manual_file, reference). | ETL metadata | oltp |
| bronze_source_table_name | VARCHAR(150) | NULL | Original source table or entity name the row came from. | ETL metadata | ref_payment_status |
| bronze_source_file_name | VARCHAR(255) | NULL | Source file name when the row originates from a CSV/manual/file extract; NULL for DB sources. | ETL metadata | NULL |
| bronze_source_row_number | BIGINT | NULL | Original row number within a file or extract, for file-based lineage. | ETL metadata | 1542 |
| bronze_row_hash | TEXT | NOT NULL | Deterministic hash of the business column values, used to detect changed rows across batches. | derived (hash of business columns) | a3f9c1e8... |
| bronze_is_deleted_flag | BOOLEAN | NOT NULL | Marks a row that the source reports as deleted (soft-delete capture); does not remove the Bronze row. | ETL metadata (DEFAULT FALSE) | false |
| bronze_raw_payload_jsonb | JSONB | NULL | Full raw source row stored as JSONB for complete traceability back to the exact extracted record. | ETL metadata | {"invoice_id": 1001, ...} |


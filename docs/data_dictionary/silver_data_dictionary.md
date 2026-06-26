# Silver Data Dictionary

PrintTimeUSA Data Warehouse | Silver layer. Every column of every Silver table is documented. All columns are `silver_`-prefixed per the naming standard. Each table carries the standard Silver metadata block (documented per table).

Tables: 20

## silver.customer

- **Source Bronze:** bronze.oltp_customer
- **Business key:** silver_customer_id
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id  (alt: bronze_loaded_at_timestamp)
- **Supports Gold:** gold.dim_customer, gold.fact_customer_behavior_snapshot

| Column                             | Data Type    | Nullable | Description                                                           | Source / Origin                          | Cleaning / Transformation             | Example          |
| ---------------------------------- | ------------ | -------- | --------------------------------------------------------------------- | ---------------------------------------- | ------------------------------------- | ---------------- |
| silver_customer_id                 | BIGINT       | NOT NULL | Source customer id (business key).                                    | bronze.oltp_customer.customer_id         | cast bigint; required                 | 4821             |
| silver_customer_account_no         | VARCHAR(30)  | NULL     | Customer account number (natural key in Gold).                        | bronze.oltp_customer.customer_account_no | trim; '' -> NULL                      | ACCT-027612      |
| silver_business_name               | VARCHAR(255) | NULL     | Customer business/company name.                                       | bronze.oltp_customer.business_name       | trim; collapse spaces; '' -> NULL     | Bronco Winery    |
| silver_first_name                  | VARCHAR(100) | NULL     | Contact first name.                                                   | bronze.oltp_customer.first_name          | trim; collapse spaces; '' -> NULL     | Luis             |
| silver_last_name                   | VARCHAR(100) | NULL     | Contact last name.                                                    | bronze.oltp_customer.last_name           | trim; collapse spaces; '' -> NULL     | Lopez            |
| silver_customer_name               | VARCHAR(255) | NULL     | Display name: business name else person name.                         | derived                                  | coalesce; trim                        | Bronco Winery    |
| silver_email                       | VARCHAR(255) | NULL     | Cleaned, lowercased email.                                            | bronze.oltp_customer.email               | trim; lower; '' -> NULL               | luis@example.com |
| silver_phone_number                | VARCHAR(50)  | NULL     | Cleaned phone number.                                                 | bronze.oltp_customer.phone               | trim; collapse spaces; '' -> NULL     | 209-555-0142     |
| silver_customer_status             | VARCHAR(20)  | NULL     | Standardized customer status.                                         | bronze.oltp_customer.customer_status     | trim; lower; map to {active,inactive} | active           |
| silver_is_active_flag              | BOOLEAN      | NULL     | True when customer status is active.                                  | derived                                  | derive from status                    | true             |
| silver_default_tax_rate_id         | BIGINT       | NULL     | Default tax rate reference id.                                        | bronze.oltp_customer.default_tax_rate_id | cast bigint                           | 1                |
| silver_home_store_id               | BIGINT       | NULL     | Home store reference id.                                              | bronze.oltp_customer.home_store_id       | cast bigint                           | 1                |
| silver_first_order_date            | DATE         | NULL     | First order date from source.                                         | bronze.oltp_customer.first_order_date    | cast date                             | 2024-03-11       |
| silver_source_system               | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze).                      | ETL / lineage                            | carried from Bronze / set by load     | -                |
| silver_source_table_name           | VARCHAR(150) | NULL     | Original source table name (carried from Bronze).                     | ETL / lineage                            | carried from Bronze / set by load     | -                |
| silver_source_record_id            | TEXT         | NULL     | Source business id as text, for lineage.                              | ETL / lineage                            | carried from Bronze / set by load     | -                |
| silver_source_created_at_timestamp | TIMESTAMP    | NULL     | Source row creation time (from Bronze).                               | ETL / lineage                            | carried from Bronze / set by load     | -                |
| silver_source_updated_at_timestamp | TIMESTAMP    | NULL     | Source last-updated time (from Bronze); freshness for dedup.          | ETL / lineage                            | carried from Bronze / set by load     | -                |
| silver_bronze_record_id            | BIGINT       | NULL     | Bronze row that created/last-updated this Silver row.                 | ETL / lineage                            | carried from Bronze / set by load     | -                |
| silver_bronze_batch_id             | BIGINT       | NULL     | Bronze batch that produced the winning row.                           | ETL / lineage                            | carried from Bronze / set by load     | -                |
| silver_batch_id                    | BIGINT       | NOT NULL | Silver ETL batch that created/updated this row.                       | ETL / lineage                            | carried from Bronze / set by load     | -                |
| silver_created_at_timestamp        | TIMESTAMP    | NOT NULL | When the Silver row was first created.                                | ETL / lineage                            | carried from Bronze / set by load     | -                |
| silver_updated_at_timestamp        | TIMESTAMP    | NOT NULL | When the Silver row was last updated.                                 | ETL / lineage                            | carried from Bronze / set by load     | -                |
| silver_row_hash                    | TEXT         | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage                            | carried from Bronze / set by load     | -                |
| silver_is_deleted_flag             | BOOLEAN      | NOT NULL | Logical delete carried/standardized from the source.                  | ETL / lineage                            | carried from Bronze / set by load     | -                |

## silver.customer_address

- **Source Bronze:** bronze.oltp_customer_address
- **Business key:** silver_address_id
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.dim_customer

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_address_id | BIGINT | NOT NULL | Source address id (business key). | bronze.oltp_customer_address.address_id | cast bigint; required | 9931 |
| silver_customer_id | BIGINT | NULL | Owning customer id. | bronze.oltp_customer_address.customer_id | cast bigint | 4821 |
| silver_address_type | VARCHAR(20) | NULL | Address type. | bronze.oltp_customer_address.address_type | trim; lower; map {billing,shipping} | billing |
| silver_street_address_line_1 | VARCHAR(200) | NULL | Primary street line. | bronze.oltp_customer_address.street_address | trim; '' -> NULL | 1225 H St |
| silver_street_address_line_2 | VARCHAR(100) | NULL | Secondary street line. | bronze.oltp_customer_address.street_address2 | trim; '' -> NULL | Suite 200 |
| silver_city | VARCHAR(100) | NULL | City. | bronze.oltp_customer_address.city | trim; collapse spaces; '' -> NULL | Modesto |
| silver_state_code | VARCHAR(2) | NULL | Two-letter state code. | bronze.oltp_customer_address.state_code | trim; upper | CA |
| silver_zip_code | VARCHAR(10) | NULL | ZIP code. | bronze.oltp_customer_address.zip_code | trim; '' -> NULL | 95354 |
| silver_is_primary_flag | BOOLEAN | NULL | Whether this is the primary address. | bronze.oltp_customer_address.is_primary_flag | cast boolean | true |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.product

- **Source Bronze:** bronze.oltp_product
- **Business key:** silver_product_id
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.dim_product, gold.fact_retail_sales

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_product_id | BIGINT | NOT NULL | Source product id (business key). | bronze.oltp_product.product_id | cast bigint; required | 512 |
| silver_product_sku | VARCHAR(50) | NULL | Product SKU (natural key in Gold). | bronze.oltp_product.sku | trim; upper | BC-14PT-UV |
| silver_product_name | VARCHAR(255) | NULL | Product name. | bronze.oltp_product.product_name | trim; '' -> NULL | Business Cards 14pt UV |
| silver_product_description | TEXT | NULL | Product description. | bronze.oltp_product.description | trim; '' -> NULL | Full color 14pt gloss UV |
| silver_department_id | BIGINT | NULL | Department reference id. | bronze.oltp_product.department_id | cast bigint | 4 |
| silver_category_id | BIGINT | NULL | Category reference id. | bronze.oltp_product.category_id | cast bigint | 21 |
| silver_brand_name | VARCHAR(100) | NULL | Brand name. | bronze.oltp_product.brand | trim; '' -> NULL | 4over |
| silver_standard_cost_amount | NUMERIC(18,2) | NULL | Standard unit cost. | bronze.oltp_product.unit_cost_amount | cast NUMERIC(18,2) | 12.50 |
| silver_markup_pct | NUMERIC(8,4) | NULL | Markup percentage. | bronze.oltp_product.markup_pct | cast numeric | 200.0000 |
| silver_standard_price_amount | NUMERIC(18,2) | NULL | Standard selling price. | bronze.oltp_product.standard_price_amount | cast NUMERIC(18,2) | 37.50 |
| silver_is_local_made_flag | BOOLEAN | NULL | Locally made flag. | bronze.oltp_product.is_local_made_flag | cast boolean | true |
| silver_is_active_flag | BOOLEAN | NULL | Active flag. | bronze.oltp_product.is_active_flag | cast boolean | true |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.product_category

- **Source Bronze:** bronze.oltp_product_category
- **Business key:** silver_category_id
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.dim_product

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_category_id | BIGINT | NOT NULL | Source category id (business key). | bronze.oltp_product_category.category_id | cast bigint; required | 21 |
| silver_department_id | BIGINT | NULL | Owning department id. | bronze.oltp_product_category.department_id | cast bigint | 4 |
| silver_category_code | VARCHAR(40) | NULL | Category code. | bronze.oltp_product_category.category_code | trim; upper | BUS_CARDS |
| silver_category_name | VARCHAR(100) | NULL | Category display name. | bronze.oltp_product_category.category_name | trim; '' -> NULL | Business Cards |
| silver_category_description | VARCHAR(200) | NULL | Category description. | bronze.oltp_product_category.description | trim; '' -> NULL | Standard business cards |
| silver_is_active_flag | BOOLEAN | NULL | Active flag. | bronze.oltp_product_category.is_active_flag | cast boolean | true |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.department

- **Source Bronze:** bronze.oltp_department
- **Business key:** silver_department_id
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.dim_product

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_department_id | BIGINT | NOT NULL | Source department id (business key). | bronze.oltp_department.department_id | cast bigint; required | 4 |
| silver_department_code | VARCHAR(20) | NULL | Department code. | bronze.oltp_department.department_code | trim; upper | PRINT |
| silver_department_name | VARCHAR(100) | NULL | Department display name. | bronze.oltp_department.department_name | trim; '' -> NULL | Printing |
| silver_department_description | VARCHAR(200) | NULL | Department description. | bronze.oltp_department.description | trim; '' -> NULL | Offset and digital printing |
| silver_is_active_flag | BOOLEAN | NULL | Active flag. | bronze.oltp_department.is_active_flag | cast boolean | true |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.employee

- **Source Bronze:** bronze.oltp_employee
- **Business key:** silver_employee_id
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.dim_cashier

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_employee_id | BIGINT | NOT NULL | Source employee id (business key). | bronze.oltp_employee.employee_id | cast bigint; required | 17 |
| silver_employee_code | VARCHAR(30) | NULL | Employee code (natural key in Gold). | bronze.oltp_employee.employee_code | trim; upper | EMP-017 |
| silver_first_name | VARCHAR(100) | NULL | First name. | bronze.oltp_employee.first_name | trim; collapse spaces; '' -> NULL | Maria |
| silver_last_name | VARCHAR(100) | NULL | Last name. | bronze.oltp_employee.last_name | trim; collapse spaces; '' -> NULL | Santos |
| silver_full_name | VARCHAR(200) | NULL | Full name. | derived | coalesce; trim | Maria Santos |
| silver_email | VARCHAR(255) | NULL | Cleaned email. | bronze.oltp_employee.email | trim; lower; '' -> NULL | maria@printtime.example |
| silver_phone_number | VARCHAR(50) | NULL | Cleaned phone. | bronze.oltp_employee.phone | trim; collapse spaces; '' -> NULL | 209-555-0190 |
| silver_role | VARCHAR(30) | NULL | Employee role. | bronze.oltp_employee.role | trim; lower | cashier |
| silver_store_id | BIGINT | NULL | Assigned store id. | bronze.oltp_employee.store_id | cast bigint | 1 |
| silver_hire_date | DATE | NULL | Hire date. | bronze.oltp_employee.hire_date | cast date | 2023-09-01 |
| silver_is_active_flag | BOOLEAN | NULL | Active flag. | bronze.oltp_employee.is_active_flag | cast boolean | true |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.store

- **Source Bronze:** bronze.oltp_store
- **Business key:** silver_store_id
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.dim_store, gold.dim_cashier, gold.dim_invoice

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_store_id | BIGINT | NOT NULL | Source store id (business key). | bronze.oltp_store.store_id | cast bigint; required | 1 |
| silver_store_code | VARCHAR(30) | NULL | Store code (natural key in Gold). | bronze.oltp_store.store_code | trim; upper | ST-MOD |
| silver_store_name | VARCHAR(100) | NULL | Store name. | bronze.oltp_store.store_name | trim; '' -> NULL | PrintTime Modesto |
| silver_street_address | VARCHAR(200) | NULL | Street address. | bronze.oltp_store.street_address | trim; '' -> NULL | 1225 H St |
| silver_city | VARCHAR(100) | NULL | City. | bronze.oltp_store.city | trim; collapse spaces; '' -> NULL | Modesto |
| silver_state_code | VARCHAR(2) | NULL | State code. | bronze.oltp_store.state_code | trim; upper | CA |
| silver_zip_code | VARCHAR(10) | NULL | ZIP code. | bronze.oltp_store.zip_code | trim; '' -> NULL | 95354 |
| silver_phone_number | VARCHAR(50) | NULL | Phone. | bronze.oltp_store.phone | trim; collapse spaces; '' -> NULL | 209-529-9850 |
| silver_region | VARCHAR(50) | NULL | Region. | bronze.oltp_store.region | trim; '' -> NULL | Central Valley |
| silver_store_type | VARCHAR(50) | NULL | Store type. | bronze.oltp_store.store_type | trim | FLAGSHIP |
| silver_open_date | DATE | NULL | Open date. | bronze.oltp_store.open_date | cast date | 2018-05-01 |
| silver_is_active_flag | BOOLEAN | NULL | Active flag. | bronze.oltp_store.is_active_flag | cast boolean | true |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.invoice

- **Source Bronze:** bronze.oltp_invoice
- **Business key:** silver_invoice_id
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.dim_invoice, gold.fact_retail_sales, gold.fact_payments

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_invoice_id | BIGINT | NOT NULL | Source invoice id (business key). | bronze.oltp_invoice.invoice_id | cast bigint; required | 1001 |
| silver_invoice_number | VARCHAR(30) | NULL | Invoice number (natural key in Gold). | bronze.oltp_invoice.invoice_number | trim | 32390 |
| silver_customer_id | BIGINT | NULL | Customer id. | bronze.oltp_invoice.customer_id | cast bigint | 4821 |
| silver_store_id | BIGINT | NULL | Store id. | bronze.oltp_invoice.store_id | cast bigint | 1 |
| silver_employee_id | BIGINT | NULL | Employee/cashier id. | bronze.oltp_invoice.employee_id | cast bigint | 17 |
| silver_billing_address_id | BIGINT | NULL | Billing address id. | bronze.oltp_invoice.billing_address_id | cast bigint | 9931 |
| silver_shipping_address_id | BIGINT | NULL | Shipping address id. | bronze.oltp_invoice.shipping_address_id | cast bigint | 9932 |
| silver_po_number | VARCHAR(50) | NULL | Customer PO number. | bronze.oltp_invoice.po_number | trim | PO-55821 |
| silver_invoice_date | DATE | NULL | Invoice date. | bronze.oltp_invoice.invoice_date | cast date | 2025-11-14 |
| silver_invoice_due_date | DATE | NULL | Due date. | bronze.oltp_invoice.invoice_due_date | cast date | 2025-12-14 |
| silver_invoice_status | VARCHAR(20) | NULL | Standardized invoice status. | bronze.oltp_invoice.invoice_status | trim; lower; map to {pending,partial_paid,paid,cancelled,void,refunded} | paid |
| silver_tax_rate_id | BIGINT | NULL | Applied tax rate id. | bronze.oltp_invoice.tax_rate_id | cast bigint | 1 |
| silver_subtotal_amount | NUMERIC(18,2) | NULL | Subtotal before tax/fee. | bronze.oltp_invoice.subtotal_amount | cast NUMERIC(18,2) | 450.00 |
| silver_discount_amount | NUMERIC(18,2) | NULL | Header discount. | bronze.oltp_invoice.discount_amount | cast NUMERIC(18,2) | 0.00 |
| silver_tax_amount | NUMERIC(18,2) | NULL | Tax charged. | bronze.oltp_invoice.tax_amount | cast NUMERIC(18,2) | 39.94 |
| silver_fee_amount | NUMERIC(18,2) | NULL | Card processing fee. | bronze.oltp_invoice.fee_amount | cast NUMERIC(18,2) | 14.70 |
| silver_total_amount | NUMERIC(18,2) | NULL | Invoice total. | bronze.oltp_invoice.total_amount | cast NUMERIC(18,2) | 504.64 |
| silver_paid_amount | NUMERIC(18,2) | NULL | Amount paid. | bronze.oltp_invoice.paid_amount | cast NUMERIC(18,2) | 504.64 |
| silver_balance_due_amount | NUMERIC(18,2) | NULL | Outstanding balance. | bronze.oltp_invoice.balance_due_amount | cast NUMERIC(18,2) | 0.00 |
| silver_has_balance_due_flag | BOOLEAN | NULL | True when balance remains. | derived | derive | false |
| silver_paid_in_full_flag | BOOLEAN | NULL | True when fully paid. | derived | derive | true |
| silver_notes | VARCHAR(1000) | NULL | Invoice notes. | bronze.oltp_invoice.notes | trim; '' -> NULL | Embroidery - Bronco/Bivio logo |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.invoice_line

- **Source Bronze:** bronze.oltp_invoice_line
- **Business key:** silver_invoice_line_id
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.fact_retail_sales

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_invoice_line_id | BIGINT | NOT NULL | Source line id (business key). | bronze.oltp_invoice_line.invoice_line_id | cast bigint; required | 880231 |
| silver_invoice_id | BIGINT | NULL | Parent invoice id. | bronze.oltp_invoice_line.invoice_id | cast bigint | 1001 |
| silver_line_number | SMALLINT | NULL | Line sequence. | bronze.oltp_invoice_line.line_number | cast smallint | 1 |
| silver_product_id | BIGINT | NULL | Product id. | bronze.oltp_invoice_line.product_id | cast bigint | 512 |
| silver_variant_id | BIGINT | NULL | Product variant id. | bronze.oltp_invoice_line.variant_id | cast bigint | 77 |
| silver_line_description | VARCHAR(300) | NULL | Line description. | bronze.oltp_invoice_line.line_description | trim; '' -> NULL | Nike polo embroidery |
| silver_color | VARCHAR(40) | NULL | Color attribute. | bronze.oltp_invoice_line.color | trim; '' -> NULL | Navy |
| silver_order_qty | INTEGER | NULL | Quantity ordered. | bronze.oltp_invoice_line.order_qty | cast integer; >=0 | 12 |
| silver_unit_price_amount | NUMERIC(18,2) | NULL | Unit selling price. | bronze.oltp_invoice_line.unit_price_amount | cast NUMERIC(18,2) | 37.50 |
| silver_unit_cost_amount | NUMERIC(18,2) | NULL | Unit cost. | bronze.oltp_invoice_line.unit_cost_amount | cast NUMERIC(18,2) | 12.50 |
| silver_discount_amount | NUMERIC(18,2) | NULL | Line discount. | bronze.oltp_invoice_line.discount_amount | cast NUMERIC(18,2) | 0.00 |
| silver_line_total_amount | NUMERIC(18,2) | NULL | Extended amount. | bronze.oltp_invoice_line.line_total_amount | cast NUMERIC(18,2) | 450.00 |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.payment

- **Source Bronze:** bronze.oltp_payment
- **Business key:** silver_payment_id
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.fact_payments

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_payment_id | BIGINT | NOT NULL | Source payment id (business key). | bronze.oltp_payment.payment_id | cast bigint; required | 660014 |
| silver_invoice_id | BIGINT | NULL | Invoice id. | bronze.oltp_payment.invoice_id | cast bigint | 1001 |
| silver_customer_id | BIGINT | NULL | Customer id. | bronze.oltp_payment.customer_id | cast bigint | 4821 |
| silver_payment_method_id | BIGINT | NULL | Payment method id. | bronze.oltp_payment.payment_method_id | cast bigint | 2 |
| silver_payment_type_id | BIGINT | NULL | Payment type id. | bronze.oltp_payment.payment_type_id | cast bigint | 1 |
| silver_employee_id | BIGINT | NULL | Employee id. | bronze.oltp_payment.employee_id | cast bigint | 17 |
| silver_store_id | BIGINT | NULL | Store id. | bronze.oltp_payment.store_id | cast bigint | 1 |
| silver_parent_payment_id | BIGINT | NULL | Parent payment id (refund chain). | bronze.oltp_payment.parent_payment_id | cast bigint | 660010 |
| silver_payment_sequence_num | SMALLINT | NULL | Payment sequence. | bronze.oltp_payment.payment_sequence_num | cast smallint | 2 |
| silver_payment_status | VARCHAR(20) | NULL | Standardized payment status. | bronze.oltp_payment.payment_status | trim; lower; map to {pending,completed,failed,refunded,void} | completed |
| silver_payment_date | DATE | NULL | Payment date. | bronze.oltp_payment.payment_date | cast date | 2025-11-20 |
| silver_payment_amount | NUMERIC(18,2) | NULL | Gross payment amount (negative for refunds). | bronze.oltp_payment.gross_amount | cast NUMERIC(18,2) | 252.32 |
| silver_tax_amount | NUMERIC(18,2) | NULL | Tax portion. | bronze.oltp_payment.tax_amount | cast NUMERIC(18,2) | 19.97 |
| silver_fee_amount | NUMERIC(18,2) | NULL | Card fee portion. | bronze.oltp_payment.fee_amount | cast NUMERIC(18,2) | 7.35 |
| silver_net_amount | NUMERIC(18,2) | NULL | Net cash impact. | bronze.oltp_payment.net_amount | cast NUMERIC(18,2) | 244.97 |
| silver_reference_no | VARCHAR(60) | NULL | External reference. | bronze.oltp_payment.reference_no | trim | AUTH-99213 |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.refund

- **Source Bronze:** bronze.oltp_refund
- **Business key:** silver_refund_id
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.fact_payments

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_refund_id | BIGINT | NOT NULL | Source refund id (business key). | bronze.oltp_refund.refund_id | cast bigint; required | 4401 |
| silver_payment_id | BIGINT | NULL | Original payment id. | bronze.oltp_refund.payment_id | cast bigint | 660010 |
| silver_invoice_id | BIGINT | NULL | Invoice id. | bronze.oltp_refund.invoice_id | cast bigint | 1001 |
| silver_refund_amount | NUMERIC(18,2) | NULL | Refunded amount. | bronze.oltp_refund.refund_amount | cast NUMERIC(18,2) | 50.00 |
| silver_refund_date | DATE | NULL | Refund date. | bronze.oltp_refund.refund_date | cast date | 2025-12-01 |
| silver_refund_reason | VARCHAR(200) | NULL | Refund reason. | bronze.oltp_refund.reason | trim; '' -> NULL | Damaged item |
| silver_refunded_by_employee_id | BIGINT | NULL | Employee who issued refund. | bronze.oltp_refund.refunded_by | cast bigint | 17 |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.invoice_adjustment

- **Source Bronze:** bronze.oltp_invoice_adjustment
- **Business key:** silver_adjustment_id
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.dim_invoice, gold.fact_payments

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_adjustment_id | BIGINT | NOT NULL | Source adjustment id (business key). | bronze.oltp_invoice_adjustment.adjustment_id | cast bigint; required | 7701 |
| silver_invoice_id | BIGINT | NULL | Invoice id. | bronze.oltp_invoice_adjustment.invoice_id | cast bigint | 1001 |
| silver_adjustment_type | VARCHAR(20) | NULL | Adjustment type. | bronze.oltp_invoice_adjustment.adjustment_type | trim; lower | credit |
| silver_adjustment_amount | NUMERIC(18,2) | NULL | Adjustment amount. | bronze.oltp_invoice_adjustment.amount | cast NUMERIC(18,2) | 25.00 |
| silver_adjustment_reason | VARCHAR(200) | NULL | Reason. | bronze.oltp_invoice_adjustment.reason | trim; '' -> NULL | Goodwill credit |
| silver_adjusted_by_employee_id | BIGINT | NULL | Employee who adjusted. | bronze.oltp_invoice_adjustment.adjusted_by | cast bigint | 17 |
| silver_adjustment_date | DATE | NULL | Adjustment date. | bronze.oltp_invoice_adjustment.adjustment_date | cast date | 2025-11-25 |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.invoice_status_history

- **Source Bronze:** bronze.oltp_invoice_status_history
- **Business key:** silver_status_history_id
- **Load strategy:** incremental_merge (history-tracked)
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.dim_invoice

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_status_history_id | BIGINT | NOT NULL | Source status change id (business key). | bronze.oltp_invoice_status_history.status_history_id | cast bigint; required | 300551 |
| silver_invoice_id | BIGINT | NULL | Invoice id. | bronze.oltp_invoice_status_history.invoice_id | cast bigint | 1001 |
| silver_old_status | VARCHAR(20) | NULL | Status before change. | bronze.oltp_invoice_status_history.old_status | trim; lower; map to {pending,partial_paid,paid,cancelled,void,refunded} | partial_paid |
| silver_new_status | VARCHAR(20) | NULL | Status after change. | bronze.oltp_invoice_status_history.new_status | trim; lower; map to {pending,partial_paid,paid,cancelled,void,refunded} | paid |
| silver_changed_at_timestamp | TIMESTAMP | NULL | When the change occurred. | bronze.oltp_invoice_status_history.changed_at_source_timestamp | cast timestamp | 2025-11-20 16:45:00 |
| silver_changed_by_employee_id | BIGINT | NULL | Employee who changed it. | bronze.oltp_invoice_status_history.changed_by | cast bigint | 17 |
| silver_change_note | VARCHAR(200) | NULL | Note about the change. | bronze.oltp_invoice_status_history.note | trim; '' -> NULL | Balance paid in full |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.customer_status_history

- **Source Bronze:** bronze.oltp_customer_status_history
- **Business key:** silver_status_history_id
- **Load strategy:** incremental_merge (history-tracked)
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.fact_customer_behavior_snapshot

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_status_history_id | BIGINT | NOT NULL | Source status change id (business key). | bronze.oltp_customer_status_history.status_history_id | cast bigint; required | 12055 |
| silver_customer_id | BIGINT | NULL | Customer id. | bronze.oltp_customer_status_history.customer_id | cast bigint | 4821 |
| silver_old_status | VARCHAR(20) | NULL | Status before change. | bronze.oltp_customer_status_history.old_status | trim; lower; map {active,inactive} | active |
| silver_new_status | VARCHAR(20) | NULL | Status after change. | bronze.oltp_customer_status_history.new_status | trim; lower; map {active,inactive} | inactive |
| silver_changed_at_timestamp | TIMESTAMP | NULL | When the change occurred. | bronze.oltp_customer_status_history.changed_at_source_timestamp | cast timestamp | 2026-01-15 09:00:00 |
| silver_changed_by_employee_id | BIGINT | NULL | Employee who changed it. | bronze.oltp_customer_status_history.changed_by | cast bigint | 17 |
| silver_change_reason | VARCHAR(200) | NULL | Reason for change. | bronze.oltp_customer_status_history.reason | trim; '' -> NULL | No orders in 12 months |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.payment_method

- **Source Bronze:** bronze.ref_payment_method
- **Business key:** silver_payment_method_id
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.dim_payment_method

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_payment_method_id | BIGINT | NOT NULL | Source method id (business key). | bronze.ref_payment_method.payment_method_id | cast bigint; required | 2 |
| silver_method_code | VARCHAR(20) | NULL | Method code (natural key in Gold). | bronze.ref_payment_method.method_code | trim; upper | VISA |
| silver_method_name | VARCHAR(50) | NULL | Method display name. | bronze.ref_payment_method.method_name | trim; '' -> NULL | Visa Credit Card |
| silver_method_type | VARCHAR(30) | NULL | Method type. | bronze.ref_payment_method.method_type | trim; upper | CARD |
| silver_is_card_flag | BOOLEAN | NULL | Card flag (drives fee). | bronze.ref_payment_method.is_card_flag | cast boolean | true |
| silver_is_active_flag | BOOLEAN | NULL | Active flag. | bronze.ref_payment_method.is_active_flag | cast boolean | true |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.payment_type

- **Source Bronze:** bronze.ref_payment_type
- **Business key:** silver_payment_type_id
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.dim_payment_type

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_payment_type_id | BIGINT | NOT NULL | Source type id (business key). | bronze.ref_payment_type.payment_type_id | cast bigint; required | 1 |
| silver_type_code | VARCHAR(20) | NULL | Type code (natural key in Gold). | bronze.ref_payment_type.type_code | trim; upper | DEPOSIT |
| silver_type_name | VARCHAR(50) | NULL | Type display name. | bronze.ref_payment_type.type_name | trim; '' -> NULL | Deposit |
| silver_type_description | VARCHAR(200) | NULL | Type description. | bronze.ref_payment_type.description | trim; '' -> NULL | Initial deposit payment |
| silver_affects_balance_flag | BOOLEAN | NULL | Affects invoice balance. | bronze.ref_payment_type.affects_balance_flag | cast boolean | true |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.tax_rate

- **Source Bronze:** bronze.ref_tax_rate
- **Business key:** silver_tax_rate_id
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.dim_invoice, gold.fact_payments

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_tax_rate_id | BIGINT | NOT NULL | Source tax rate id (business key). | bronze.ref_tax_rate.tax_rate_id | cast bigint; required | 1 |
| silver_tax_code | VARCHAR(20) | NULL | Tax code. | bronze.ref_tax_rate.tax_code | trim; upper | STD |
| silver_tax_description | VARCHAR(100) | NULL | Description. | bronze.ref_tax_rate.description | trim; '' -> NULL | Modesto standard rate |
| silver_rate_pct | NUMERIC(6,4) | NULL | Tax rate percentage. | bronze.ref_tax_rate.rate_pct | cast numeric | 8.8750 |
| silver_effective_from_date | DATE | NULL | Effective from. | bronze.ref_tax_rate.effective_from | cast date | 2024-01-01 |
| silver_effective_to_date | DATE | NULL | Effective to. | bronze.ref_tax_rate.effective_to | cast date | NULL |
| silver_is_active_flag | BOOLEAN | NULL | Active flag. | bronze.ref_tax_rate.is_active_flag | cast boolean | true |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.state

- **Source Bronze:** bronze.ref_state
- **Business key:** silver_state_code
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.dim_customer, gold.dim_store

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_state_code | VARCHAR(2) | NOT NULL | State code (business key). | bronze.ref_state.state_code | trim; upper; required | CA |
| silver_state_name | VARCHAR(50) | NULL | State name. | bronze.ref_state.state_name | trim; '' -> NULL | California |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.invoice_status

- **Source Bronze:** bronze.ref_invoice_status
- **Business key:** silver_status_code
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.dim_invoice

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_status_code | VARCHAR(20) | NOT NULL | Status code (business key). | bronze.ref_invoice_status.status_code | trim; lower; required | paid |
| silver_status_name | VARCHAR(50) | NULL | Status display name. | bronze.ref_invoice_status.status_name | trim; '' -> NULL | Paid |
| silver_is_terminal_flag | BOOLEAN | NULL | Terminal status flag. | bronze.ref_invoice_status.is_terminal_flag | cast boolean | true |
| silver_sort_order | SMALLINT | NULL | Display order. | bronze.ref_invoice_status.sort_order | cast smallint | 3 |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |

## silver.payment_status

- **Source Bronze:** bronze.ref_payment_status
- **Business key:** silver_status_code
- **Load strategy:** incremental_merge
- **Incremental filter:** bronze_batch_id > :last_successful_bronze_batch_id
- **Supports Gold:** gold.fact_payments

| Column | Data Type | Nullable | Description | Source / Origin | Cleaning / Transformation | Example |
|---|---|---|---|---|---|---|
| silver_status_code | VARCHAR(20) | NOT NULL | Status code (business key). | bronze.ref_payment_status.status_code | trim; lower; required | completed |
| silver_status_name | VARCHAR(50) | NULL | Status display name. | bronze.ref_payment_status.status_name | trim; '' -> NULL | Completed |
| silver_source_system | VARCHAR(100) | NOT NULL | Originating source system (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_table_name | VARCHAR(150) | NULL | Original source table name (carried from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_record_id | TEXT | NULL | Source business id as text, for lineage. | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_created_at_timestamp | TIMESTAMP | NULL | Source row creation time (from Bronze). | ETL / lineage | carried from Bronze / set by load | - |
| silver_source_updated_at_timestamp | TIMESTAMP | NULL | Source last-updated time (from Bronze); freshness for dedup. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_record_id | BIGINT | NULL | Bronze row that created/last-updated this Silver row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_bronze_batch_id | BIGINT | NULL | Bronze batch that produced the winning row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_batch_id | BIGINT | NOT NULL | Silver ETL batch that created/updated this row. | ETL / lineage | carried from Bronze / set by load | - |
| silver_created_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was first created. | ETL / lineage | carried from Bronze / set by load | - |
| silver_updated_at_timestamp | TIMESTAMP | NOT NULL | When the Silver row was last updated. | ETL / lineage | carried from Bronze / set by load | - |
| silver_row_hash | TEXT | NOT NULL | Hash of standardized business columns; drives merge change detection. | ETL / lineage | carried from Bronze / set by load | - |
| silver_is_deleted_flag | BOOLEAN | NOT NULL | Logical delete carried/standardized from the source. | ETL / lineage | carried from Bronze / set by load | - |


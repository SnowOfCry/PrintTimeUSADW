# Silver Source-to-Table Mapping

PrintTimeUSA Data Warehouse | Silver layer. Load strategy is **incremental_merge** (upsert on the business key; update only when `silver_row_hash` changes). Bronze append-only history is deduplicated to the latest version per business key before merge.

| Silver Table                   | Source Bronze Table(s)              | Business Key             | Incremental Filter                                                                    | Load Strategy                       | Supports Gold Tables                                         |
| ------------------------------ | ----------------------------------- | ------------------------ | ------------------------------------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------------ |
| silver.customer                | bronze.oltp_customer                | silver_customer_id       | bronze_batch_id > :last_successful_bronze_batch_id  (alt: bronze_loaded_at_timestamp) | incremental_merge                   | gold.dim_customer, gold.fact_customer_behavior_snapshot      |
| silver.customer_address        | bronze.oltp_customer_address        | silver_address_id        | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.dim_customer                                            |
| silver.product                 | bronze.oltp_product                 | silver_product_id        | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.dim_product, gold.fact_retail_sales                     |
| silver.product_category        | bronze.oltp_product_category        | silver_category_id       | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.dim_product                                             |
| silver.department              | bronze.oltp_department              | silver_department_id     | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.dim_product                                             |
| silver.employee                | bronze.oltp_employee                | silver_employee_id       | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.dim_cashier                                             |
| silver.store                   | bronze.oltp_store                   | silver_store_id          | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.dim_store, gold.dim_cashier, gold.dim_invoice           |
| silver.invoice                 | bronze.oltp_invoice                 | silver_invoice_id        | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.dim_invoice, gold.fact_retail_sales, gold.fact_payments |
| silver.invoice_line            | bronze.oltp_invoice_line            | silver_invoice_line_id   | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.fact_retail_sales                                       |
| silver.payment                 | bronze.oltp_payment                 | silver_payment_id        | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.fact_payments                                           |
| silver.refund                  | bronze.oltp_refund                  | silver_refund_id         | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.fact_payments                                           |
| silver.invoice_adjustment      | bronze.oltp_invoice_adjustment      | silver_adjustment_id     | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.dim_invoice, gold.fact_payments                         |
| silver.invoice_status_history  | bronze.oltp_invoice_status_history  | silver_status_history_id | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge (history-tracked) | gold.dim_invoice                                             |
| silver.customer_status_history | bronze.oltp_customer_status_history | silver_status_history_id | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge (history-tracked) | gold.fact_customer_behavior_snapshot                         |
| silver.payment_method          | bronze.ref_payment_method           | silver_payment_method_id | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.dim_payment_method                                      |
| silver.payment_type            | bronze.ref_payment_type             | silver_payment_type_id   | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.dim_payment_type                                        |
| silver.tax_rate                | bronze.ref_tax_rate                 | silver_tax_rate_id       | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.dim_invoice, gold.fact_payments                         |
| silver.state                   | bronze.ref_state                    | silver_state_code        | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.dim_customer, gold.dim_store                            |
| silver.invoice_status          | bronze.ref_invoice_status           | silver_status_code       | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.dim_invoice                                             |
| silver.payment_status          | bronze.ref_payment_status           | silver_status_code       | bronze_batch_id > :last_successful_bronze_batch_id                                    | incremental_merge                   | gold.fact_payments                                           |

## Purpose by table

- **silver.customer** — Clean current version of each customer. Feeds gold.dim_customer and customer attributes for fact_customer_behavior_snapshot.
- **silver.customer_address** — Clean current version of each customer address. Supplies address enrichment to gold.dim_customer.
- **silver.product** — Clean current version of each product. Feeds gold.dim_product and product attributes for fact_retail_sales.
- **silver.product_category** — Clean product category lookup. Supplies category_description and department link for gold.dim_product.
- **silver.department** — Clean department lookup (SIGNS, EMB, DTF, PRINT). Supplies department number/description for gold.dim_product.
- **silver.employee** — Clean current version of each employee. Feeds gold.dim_cashier.
- **silver.store** — Clean current version of each store/location. Feeds gold.dim_store and store labels in dim_cashier/dim_invoice.
- **silver.invoice** — Clean current state of each invoice (latest status). Feeds gold.dim_invoice, fact_retail_sales, fact_payments. Status changes flow via merge while Bronze keeps history.
- **silver.invoice_line** — Clean current version of each invoice line. Grain source for gold.fact_retail_sales.
- **silver.payment** — Clean current version of each payment. Grain source for gold.fact_payments.
- **silver.refund** — Clean current version of each refund, chained to payments. Supports refund analysis in gold.fact_payments.
- **silver.invoice_adjustment** — Clean current version of each invoice adjustment. Supports total reconciliation for gold.dim_invoice and fact_payments.
- **silver.invoice_status_history** — Clean invoice status transitions. Intentionally history-tracked (one row per transition) to support audit and SCD2 dim_invoice in Gold.
- **silver.customer_status_history** — Clean customer status transitions. History-tracked; supports customer_status history for fact_customer_behavior_snapshot.
- **silver.payment_method** — Clean payment method lookup. Feeds gold.dim_payment_method.
- **silver.payment_type** — Clean payment type lookup. Feeds gold.dim_payment_type.
- **silver.tax_rate** — Clean tax rate lookup. Supports tax reconciliation for gold.dim_invoice and fact_payments.
- **silver.state** — Clean state lookup (CA, AZ, TX). Standardizes state for gold.dim_customer and dim_store.
- **silver.invoice_status** — Clean invoice status lookup. Standardizes invoice status values for gold.dim_invoice.
- **silver.payment_status** — Clean payment status lookup. Standardizes payment status values for gold.fact_payments.


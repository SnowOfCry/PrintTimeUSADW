# Bronze Source-to-Table Mapping

PrintTimeUSA Data Warehouse | Bronze landing layer. Load strategy is **incremental_append** for every table: each extract appends new source-row versions; nothing is updated or deleted.

| Bronze Table                        | Source System | Source Table/File       | Source PK         | Watermark Column            | Load Strategy      | Supports DW Tables                                                             |
| ----------------------------------- | ------------- | ----------------------- | ----------------- | --------------------------- | ------------------ | ------------------------------------------------------------------------------ |
| bronze.oltp_customer                | oltp          | customer                | customer_id       | updated_at_source_timestamp | incremental_append | dim_customer, fact_customer_behavior_snapshot                                  |
| bronze.oltp_customer_address        | oltp          | customer_address        | address_id        | updated_at_source_timestamp | incremental_append | dim_customer                                                                   |
| bronze.oltp_product                 | oltp          | product                 | product_id        | updated_at_source_timestamp | incremental_append | dim_product, fact_retail_sales                                                 |
| bronze.oltp_product_category        | oltp          | product_category        | category_id       | updated_at_source_timestamp | incremental_append | dim_product                                                                    |
| bronze.oltp_department              | oltp          | department              | department_id     | updated_at_source_timestamp | incremental_append | dim_product                                                                    |
| bronze.oltp_employee                | oltp          | employee                | employee_id       | updated_at_source_timestamp | incremental_append | dim_cashier                                                                    |
| bronze.oltp_store                   | oltp          | store                   | store_id          | updated_at_source_timestamp | incremental_append | dim_store, dim_cashier, dim_invoice                                            |
| bronze.oltp_invoice                 | oltp          | invoice                 | invoice_id        | updated_at_source_timestamp | incremental_append | dim_invoice, fact_retail_sales, fact_payments, fact_customer_behavior_snapshot |
| bronze.oltp_invoice_line            | oltp          | invoice_line            | invoice_line_id   | updated_at_source_timestamp | incremental_append | fact_retail_sales                                                              |
| bronze.oltp_payment                 | oltp          | payment                 | payment_id        | updated_at_source_timestamp | incremental_append | fact_payments                                                                  |
| bronze.oltp_invoice_status_history  | oltp          | invoice_status_history  | status_history_id | changed_at_source_timestamp | incremental_append | dim_invoice                                                                    |
| bronze.oltp_customer_status_history | oltp          | customer_status_history | status_history_id | changed_at_source_timestamp | incremental_append | fact_customer_behavior_snapshot                                                |
| bronze.oltp_refund                  | oltp          | refund                  | refund_id         | updated_at_source_timestamp | incremental_append | fact_payments                                                                  |
| bronze.oltp_invoice_adjustment      | oltp          | invoice_adjustment      | adjustment_id     | updated_at_source_timestamp | incremental_append | dim_invoice, fact_payments                                                     |
| bronze.ref_payment_method           | ref           | payment_method          | payment_method_id | updated_at_source_timestamp | incremental_append | dim_payment_method                                                             |
| bronze.ref_payment_type             | ref           | payment_type            | payment_type_id   | updated_at_source_timestamp | incremental_append | dim_payment_type                                                               |
| bronze.ref_tax_rate                 | ref           | tax_rate                | tax_rate_id       | updated_at_source_timestamp | incremental_append | dim_invoice, fact_payments                                                     |
| bronze.ref_state                    | ref           | ref_state               | state_code        | updated_at_source_timestamp | incremental_append | dim_customer, dim_store                                                        |
| bronze.ref_invoice_status           | ref           | ref_invoice_status      | status_code       | updated_at_source_timestamp | incremental_append | dim_invoice                                                                    |
| bronze.ref_payment_status           | ref           | ref_payment_status      | status_code       | updated_at_source_timestamp | incremental_append | fact_payments                                                                  |

## Watermark notes

- **bronze.oltp_customer_address** — customer_address has updated_at (no source_updated_at); use updated_at as updated_at_source_timestamp.
- **bronze.oltp_product_category** — No source_updated_at; use updated_at as updated_at_source_timestamp.
- **bronze.oltp_department** — No source_updated_at; use updated_at as updated_at_source_timestamp.
- **bronze.oltp_invoice_line** — invoice_line has updated_at (no source_updated_at); use updated_at as updated_at_source_timestamp.
- **bronze.oltp_invoice_status_history** — History table is insert-only with no updated_at; use changed_at as changed_at_source_timestamp (event-time watermark).
- **bronze.oltp_customer_status_history** — History table is insert-only with no updated_at; use changed_at as changed_at_source_timestamp (event-time watermark).
- **bronze.oltp_refund** — refund has updated_at (no source_updated_at); use updated_at as updated_at_source_timestamp.
- **bronze.oltp_invoice_adjustment** — invoice_adjustment has updated_at (no source_updated_at); use updated_at as updated_at_source_timestamp.
- **bronze.ref_payment_type** — No source_updated_at; use updated_at as updated_at_source_timestamp.
- **bronze.ref_tax_rate** — No source_updated_at; use updated_at as updated_at_source_timestamp.
- **bronze.ref_state** — Tiny static lookup with no source_updated_at; use updated_at, or fall back to full extract with append-only batch tracking.
- **bronze.ref_invoice_status** — Tiny static lookup with no source_updated_at; use updated_at, or fall back to full extract with append-only batch tracking.
- **bronze.ref_payment_status** — Tiny static lookup with no source_updated_at; use updated_at, or fall back to full extract with append-only batch tracking.

## Purpose by table

- **bronze.oltp_customer** — Raw customer master records. Feeds dim_customer (SCD2 in Gold) and supplies customer attributes referenced by fact_customer_behavior_snapshot.
- **bronze.oltp_customer_address** — Raw customer address records (billing/shipping). Provides street/city/state/county enrichment for dim_customer.
- **bronze.oltp_product** — Raw product master. Feeds dim_product (SCD2) with price, markup, brand, and department/category links.
- **bronze.oltp_product_category** — Raw product category lookup. Supplies category_description and links category to department for dim_product.
- **bronze.oltp_department** — Raw department lookup (SIGNS, EMB, DTF, PRINT). Supplies department_number and department_description for dim_product.
- **bronze.oltp_employee** — Raw employee master. Feeds dim_cashier (SCD2) with name, active status, and store assignment.
- **bronze.oltp_store** — Raw store master. Feeds dim_store (SCD2) and supplies store labels denormalized into dim_cashier and dim_invoice.
- **bronze.oltp_invoice** — Raw invoice headers. Feeds dim_invoice (SCD2 on status/total) and supplies header context to fact_retail_sales, fact_payments, and fact_customer_behavior_snapshot. Status changes are preserved as appended versions.
- **bronze.oltp_invoice_line** — Raw invoice line items. The grain source for fact_retail_sales (qty, price, cost, extended amount).
- **bronze.oltp_payment** — Raw payment transactions (deposits, balances, full payments, refunds, adjustments). The grain source for fact_payments.
- **bronze.oltp_invoice_status_history** — Raw invoice status change log. Gives Silver/Gold the authoritative status-change timeline for SCD2 dim_invoice, complementing appended invoice versions.
- **bronze.oltp_customer_status_history** — Raw customer status change log. Supports customer_status history for fact_customer_behavior_snapshot and audit of active/inactive transitions.
- **bronze.oltp_refund** — Raw refund records chained to payments. Supplements fact_payments refund analysis and reconciliation.
- **bronze.oltp_invoice_adjustment** — Raw invoice adjustments (credits/debits). Supports reconciliation of invoice totals feeding dim_invoice and fact_payments.
- **bronze.ref_payment_method** — Reference payment method lookup. Feeds dim_payment_method (method code/name/type/active).
- **bronze.ref_payment_type** — Reference payment type lookup. Feeds dim_payment_type (DEPOSIT, BALANCE, FULL, REFUND, ADJUSTMENT).
- **bronze.ref_tax_rate** — Reference tax rate lookup. Supports tax reconciliation for dim_invoice / fact_payments (tax_amount validation).
- **bronze.ref_state** — Reference state lookup (CA, AZ, TX). Supports state/region standardization for dim_customer and dim_store.
- **bronze.ref_invoice_status** — Reference invoice status lookup (OPEN, PARTIAL, PAID, VOID). Standardizes invoice_status values for dim_invoice.
- **bronze.ref_payment_status** — Reference payment status lookup. Standardizes payment_status values feeding fact_payments.


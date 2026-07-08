# Silver-to-Gold Mapping

PrintTimeUSA Data Warehouse | Gold layer. Every Gold dimension and fact is mapped column-by-column from Silver. Gold applies Kimball modeling: surrogate keys, SCD2 dimensions, conformed `dim_date`, role-playing date views, and derived measures.

**Transformation classes**

| Class | Meaning |
|---|---|
| `direct` | Copied from a Silver column with no change (other than dropping the `silver_` prefix). |
| `cast` | Copied with a data-type/format change. |
| `lookup` | Resolved by joining another Silver table or a Gold dimension (surrogate-key lookup). |
| `derive` | Computed/standardized from one or more Silver columns. |
| `generate` | Produced by the Gold load itself (surrogate keys, `record_hash`, SCD2/DQ/audit columns). |

**Standard generated blocks** (apply to every dimension unless noted): `record_hash` = SHA-256 of tracked attributes (`generate`); audit block `source_system`/`source_record_id`/`etl_batch_id`/`etl_load_timestamp`/`etl_updated_timestamp` (`generate`/lineage); SCD2 block `valid_from`/`valid_to`/`is_current`/`row_version` (`generate`); DQ block `is_complete`/`is_validated`/`dq_issue_flag`/`dq_issue_description` (`generate`); soft-delete `is_deleted`/`deleted_timestamp` (`derive` from `silver_is_deleted_flag` / `generate`). Facts carry the audit + DQ blocks only (no `record_hash`, no SCD2, no soft-delete).

## Summary: source, strategy, load order

| # | Gold Table | Type | Primary Silver Source(s) | Grain | Load Strategy |
|---|---|---|---|---|---|
| 1 | gold.dim_date | dimension | generated calendar | one row per date | full generate (one-time + extend) |
| 2 | gold.dim_payment_type | dimension | silver.payment_type | one row per payment type | Type-1 overwrite |
| 3 | gold.dim_payment_method | dimension | silver.payment_method | one row per method | SCD2 merge |
| 4 | gold.dim_product | dimension | silver.product (+ product_category, department) | one row per product version | SCD2 merge |
| 5 | gold.dim_store | dimension | silver.store (+ state) | one row per store version | SCD2 merge |
| 6 | gold.dim_cashier | dimension | silver.employee (+ store) | one row per cashier version | SCD2 merge |
| 7 | gold.dim_customer | dimension | silver.customer (+ customer_address, state, dim_date) | one row per customer version | SCD2 merge |
| 8 | gold.dim_invoice | dimension | silver.invoice (+ customer, store) | one row per invoice version | SCD2 merge |
| 9 | gold.fact_retail_sales | fact | silver.invoice_line (+ invoice) | one row per invoice line | insert/append by grain |
| 10 | gold.fact_payments | fact | silver.payment | one row per payment | insert/append by grain |
| 11 | gold.fact_customer_behavior_snapshot | fact | silver.customer + invoice/payment aggregates | one row per customer × snapshot date | periodic snapshot insert |

**Load order:** dimensions first, then facts, because facts resolve dimension surrogate keys via lookup.
`dim_date` → `dim_payment_type` → `dim_payment_method` → `dim_product` → `dim_store` → `dim_cashier` → `dim_customer` → `dim_invoice` → `fact_retail_sales` → `fact_payments` (then a second pass to resolve `parent_payment_key`) → `fact_customer_behavior_snapshot`.

---

## 1. gold.dim_date

Generated calendar; not sourced from Silver. Load once and extend forward.

| Gold Column | Class | Rule |
|---|---|---|
| date_key | generate | YYYYMMDD integer smart key from the calendar date. |
| date | generate | Calendar date. |
| full_date_description | derive | e.g. "January 15, 2026". |
| day_of_week | derive | Day name. |
| day_number_in_calendar_month | derive | Day of month (1–31). |
| last_day_in_month_indicator | derive | 'Yes'/'No'. |
| calendar_week_ending_date | derive | Week-ending date. |
| calendar_month_name | derive | Month name. |
| calendar_month_number_in_year | derive | 1–12. |
| calendar_quarter | derive | 1–4. |
| calendar_year_quarter | derive | e.g. "2026-Q1". |
| calendar_year | derive | Year. |
| calendar_year_month | derive | e.g. "2026-01". |
| holiday_indicator | derive | Holiday label / 'None'. |
| weekday_indicator | derive | 'Weekday'/'Weekend'. |
| etl_load_timestamp / etl_updated_timestamp | generate | Load timestamps. |

---

## 2. gold.dim_payment_type  *(static Type-1 — no SCD2/record_hash/DQ)*

Source: **silver.payment_type**

| Gold Column | Class | Silver Source / Rule |
|---|---|---|
| payment_type_key | generate | Identity surrogate key. |
| type_code | cast | silver.payment_type.silver_type_code. Natural key. |
| type_name | direct | silver.payment_type.silver_type_name. |
| description | direct | silver.payment_type.silver_type_description. |
| etl_load_timestamp / etl_updated_timestamp | generate | Load timestamps. |
| is_deleted | derive | silver.payment_type.silver_is_deleted_flag. |

---

## 3. gold.dim_payment_method  *(SCD2)*

Source: **silver.payment_method**

| Gold Column | Class | Silver Source / Rule |
|---|---|---|
| payment_method_key | generate | Identity surrogate key. |
| method_code | cast | silver.payment_method.silver_method_code. Natural key. |
| method_name | direct | silver.payment_method.silver_method_name. |
| method_type | direct | silver.payment_method.silver_method_type. |
| is_active | direct | silver.payment_method.silver_is_active_flag. |
| record_hash | generate | SHA-256 of tracked attributes. |
| source_system / source_record_id / etl_batch_id / etl_load_timestamp / etl_updated_timestamp | generate | Audit block (`source_record_id` = silver_payment_method_id as text). |
| valid_from / valid_to / is_current / row_version | generate | SCD2 block. |
| is_complete / is_validated / dq_issue_flag / dq_issue_description | generate | DQ block. |
| is_deleted / deleted_timestamp | derive / generate | From silver_is_deleted_flag. |

---

## 4. gold.dim_product  *(SCD2)*

Source: **silver.product**; lookups: **silver.product_category**, **silver.department**

| Gold Column | Class | Silver Source / Rule |
|---|---|---|
| product_key | generate | Identity surrogate key. |
| sku_number | cast | silver.product.silver_product_sku. Natural key. |
| product_description | direct | silver.product.silver_product_description. |
| brand_description | direct | silver.product.silver_brand_name. |
| category_description | lookup | silver.product_category.silver_category_description via silver.product.silver_category_id. |
| department_number | lookup | silver.department.silver_department_code via silver.product.silver_department_id. |
| department_description | lookup | silver.department.silver_department_description via silver.product.silver_department_id. |
| markup | direct | silver.product.silver_markup_pct. |
| standard_price | direct | silver.product.silver_standard_price_amount. |
| local_made_indicator | derive | silver.product.silver_is_local_made_flag → 'Local'/'Not Local' text. |
| record_hash | generate | SHA-256 of tracked attributes. |
| audit block | generate | `source_record_id` = silver_product_id as text. |
| SCD2 block | generate | valid_from/valid_to/is_current/row_version. |
| DQ block | generate | is_complete/is_validated/dq_issue_flag/dq_issue_description. |
| is_deleted / deleted_timestamp | derive / generate | From silver_is_deleted_flag. |

---

## 5. gold.dim_store  *(SCD2)*

Source: **silver.store**; lookup: **silver.state**

| Gold Column | Class | Silver Source / Rule |
|---|---|---|
| store_key | generate | Identity surrogate key. |
| store_id | cast | silver.store.silver_store_code. Natural key. |
| store_name | direct | silver.store.silver_store_name. |
| store_city | direct | silver.store.silver_city. |
| store_state | lookup | silver.state.silver_state_name via silver.store.silver_state_code (else the code). |
| store_region | direct | silver.store.silver_region. |
| store_type | direct | silver.store.silver_store_type. |
| open_date | direct | silver.store.silver_open_date. |
| record_hash | generate | SHA-256 of tracked attributes. |
| audit block | generate | `source_record_id` = silver_store_id as text. |
| SCD2 block | generate | valid_from/valid_to/is_current/row_version. |
| DQ block | generate | DQ columns. |
| is_deleted / deleted_timestamp | derive / generate | From silver_is_deleted_flag. |

---

## 6. gold.dim_cashier  *(SCD2)*

Source: **silver.employee**; lookup: **silver.store**

| Gold Column | Class | Silver Source / Rule |
|---|---|---|
| cashier_key | generate | Identity surrogate key. |
| cashier_id | cast | silver.employee.silver_employee_code. Natural key. |
| cashier_first_name | direct | silver.employee.silver_first_name. |
| cashier_last_name | direct | silver.employee.silver_last_name. |
| cashier_full_name | direct | silver.employee.silver_full_name. |
| is_active | derive | silver.employee.silver_is_active_flag → 'Yes'/'No' (VARCHAR(3)). |
| store_id | lookup | silver.store.silver_store_code via silver.employee.silver_store_id. |
| store_name | lookup | silver.store.silver_store_name via silver.employee.silver_store_id. |
| record_hash | generate | SHA-256 of tracked attributes. |
| audit block | generate | `source_record_id` = silver_employee_id as text. |
| SCD2 block | generate | valid_from/valid_to/is_current/row_version. |
| DQ block | generate | DQ columns. |
| is_deleted / deleted_timestamp | derive / generate | From silver_is_deleted_flag. |

---

## 7. gold.dim_customer  *(SCD2)*

Source: **silver.customer**; lookups: **silver.customer_address**, **silver.state**, **gold.dim_date**

| Gold Column | Class | Silver Source / Rule |
|---|---|---|
| customer_key | generate | Identity surrogate key. |
| customer_id | cast | silver.customer.silver_customer_account_no. Natural key. |
| customer_name | direct | silver.customer.silver_customer_name. |
| customer_street_address | lookup | silver.customer_address.silver_street_address_line_1 (primary address). |
| customer_city | lookup | silver.customer_address.silver_city (primary address). |
| **customer_county** | **generate** | ⚠️ **No source in OLTP/Bronze/Silver.** Defaulted to `'Not Provided'` until a county source (e.g. ZIP→county reference) is added. **GAP.** |
| customer_state | lookup | silver.state.silver_state_name via silver.customer_address.silver_state_code. |
| customer_city_state | derive | `customer_city || ', ' || state` (e.g. "Modesto, CA"). |
| first_order_date_key | lookup | gold.dim_date.date_key via silver.customer.silver_first_order_date (role: vw_first_order_date). |
| record_hash | generate | SHA-256 of tracked attributes. |
| audit block | generate | `source_record_id` = silver_customer_id as text. |
| SCD2 block | generate | valid_from/valid_to/is_current/row_version. |
| DQ block | generate | DQ columns (`dq_issue_flag` set when county/address unresolved). |
| is_deleted / deleted_timestamp | derive / generate | From silver_is_deleted_flag. |

---

## 8. gold.dim_invoice  *(SCD2)*

Source: **silver.invoice**; lookups: **silver.customer**, **silver.store**

| Gold Column | Class | Silver Source / Rule |
|---|---|---|
| invoice_key | generate | Identity surrogate key. |
| invoice_number | cast | silver.invoice.silver_invoice_number. Natural key. |
| invoice_date | direct | silver.invoice.silver_invoice_date. |
| invoice_status | direct | silver.invoice.silver_invoice_status. |
| invoice_total | direct | silver.invoice.silver_total_amount. |
| customer_id | lookup | silver.customer.silver_customer_account_no via silver.invoice.silver_customer_id. |
| customer_name | lookup | silver.customer.silver_customer_name via silver.invoice.silver_customer_id. |
| store_id | lookup | silver.store.silver_store_code via silver.invoice.silver_store_id. |
| store_name | lookup | silver.store.silver_store_name via silver.invoice.silver_store_id. |
| record_hash | generate | SHA-256 of tracked attributes. |
| audit block | generate | `source_record_id` = silver_invoice_id as text. |
| SCD2 block | generate | valid_from/valid_to/is_current/row_version (status changes drive new versions). |
| DQ block | generate | DQ columns. |
| is_deleted / deleted_timestamp | derive / generate | From silver_is_deleted_flag. |

---

## 9. gold.fact_retail_sales  *(grain: invoice line)*

Source: **silver.invoice_line**; header lookup: **silver.invoice**; dimension key lookups as noted

| Gold Column | Class | Silver Source / Rule |
|---|---|---|
| sales_line_key | generate | Identity surrogate key. |
| date_key | lookup | gold.dim_date.date_key via silver.invoice.silver_invoice_date. |
| cashier_key | lookup | gold.dim_cashier (current) via silver.invoice.silver_employee_id. |
| product_key | lookup | gold.dim_product (current) via silver.invoice_line.silver_product_id. |
| customer_key | lookup | gold.dim_customer (current) via silver.invoice.silver_customer_id. |
| store_key | lookup | gold.dim_store (current) via silver.invoice.silver_store_id. |
| invoice_key | lookup | gold.dim_invoice (current) via silver.invoice.silver_invoice_number. |
| invoice_number | direct | silver.invoice.silver_invoice_number (degenerate dimension). |
| sales_qty | direct | silver.invoice_line.silver_order_qty. |
| unit_price | direct | silver.invoice_line.silver_unit_price_amount. |
| unit_cost | direct | silver.invoice_line.silver_unit_cost_amount. |
| sales_amount | direct | silver.invoice_line.silver_line_total_amount. |
| sales_cost | derive | `sales_qty * unit_cost`. |
| gross_profit | derive | `sales_amount - sales_cost`. |
| source_system / source_record_id / etl_batch_id / etl_load_timestamp / etl_updated_timestamp | generate | Audit block (`source_record_id` = silver_invoice_line_id as text). |
| is_complete / is_validated / dq_issue_flag / dq_issue_description | generate | DQ block. |

Unresolved dimension lookups default to the `-1` Not Provided member.

---

## 10. gold.fact_payments  *(grain: payment)*

Source: **silver.payment**; dimension key lookups as noted

| Gold Column | Class | Silver Source / Rule |
|---|---|---|
| payment_key | generate | Identity surrogate key. |
| invoice_key | lookup | gold.dim_invoice via silver.payment.silver_invoice_id → invoice_number. |
| customer_key | lookup | gold.dim_customer via silver.payment.silver_customer_id. |
| payment_method_key | lookup | gold.dim_payment_method via silver.payment.silver_payment_method_id → method_code. |
| date_key | lookup | gold.dim_date.date_key via silver.payment.silver_payment_date. |
| payment_type_key | lookup | gold.dim_payment_type via silver.payment.silver_payment_type_id → type_code. |
| cashier_key | lookup | gold.dim_cashier via silver.payment.silver_employee_id. |
| store_key | lookup | gold.dim_store via silver.payment.silver_store_id. |
| parent_payment_key | lookup | gold.fact_payments.payment_key via silver.payment.silver_parent_payment_id (2nd pass / self-join). |
| payment_sequence_num | direct | silver.payment.silver_payment_sequence_num. |
| payment_amount | direct | silver.payment.silver_payment_amount. |
| tax_amount | direct | silver.payment.silver_tax_amount. |
| fee_amount | direct | silver.payment.silver_fee_amount. |
| net_amount | direct | silver.payment.silver_net_amount. |
| audit block | generate | `source_record_id` = silver_payment_id as text. |
| DQ block | generate | is_complete/is_validated/dq_issue_flag/dq_issue_description. |

Unresolved dimension lookups default to the `-1` Not Provided member.

---

## 11. gold.fact_customer_behavior_snapshot  *(grain: customer × snapshot date)*

Source: **silver.customer** + aggregates over **silver.invoice** / **silver.payment**

| Gold Column | Class | Silver Source / Rule |
|---|---|---|
| snapshot_key | generate | Identity surrogate key. |
| snapshot_date_key | lookup | gold.dim_date.date_key for the snapshot run date (role: vw_snapshot_date). |
| customer_key | lookup | gold.dim_customer (current) via silver.customer.silver_customer_id. |
| last_order_date_key | lookup | gold.dim_date.date_key via MAX(silver.invoice.silver_invoice_date) per customer (role: vw_last_order_date). |
| lifetime_order_count | derive | COUNT(distinct invoices) per customer. |
| lifetime_sales_amount | derive | SUM(silver.invoice.silver_total_amount) per customer. |
| orders_last_30_days | derive | COUNT(invoices) with invoice_date within 30 days of snapshot. |
| avg_days_to_full_payment | derive | AVG(full-payment date − invoice_date) over paid invoices. |
| open_invoice_count | derive | COUNT(invoices with balance_due > 0). |
| open_invoice_total | derive | SUM(silver.invoice.silver_balance_due_amount) for open invoices. |
| is_active_customer | derive | silver.customer.silver_is_active_flag (as of snapshot). |
| customer_status | direct | silver.customer.silver_customer_status. |
| audit block | generate | `source_record_id` = silver_customer_id as text. |
| DQ block | generate | is_complete/is_validated/dq_issue_flag/dq_issue_description. |

---

## Gaps and assumptions

- **`dim_customer.customer_county` has no source** anywhere in OLTP → Bronze → Silver. It is generated as `'Not Provided'` until a county reference (e.g. a ZIP→county lookup) is introduced. This is the only Gold column with no traceable source.
- **`record_hash` is SHA-256 (`CHAR(64)`)** in Gold, whereas Bronze/Silver use unbounded-text hashes (`bronze_row_hash` / `silver_row_hash`), which the ETL implements as MD5. Gold deliberately standardizes on SHA-256 for SCD2 change detection; the two hash families are independent and not compared across layers.
- **Natural keys are sourced from Silver business columns** (e.g. `customer_id` ← `silver_customer_account_no`, `store_id` ← `silver_store_code`), not from Silver's numeric `silver_*_id` surrogate-ish business keys, to keep Gold natural keys human-meaningful.
- **Dimension key lookups in facts** use the *current* (`is_current = TRUE`) dimension version; an as-of (effective-dated) join may be substituted where point-in-time accuracy is required.
- **Not Provided members:** unresolved fact→dimension lookups resolve to the `-1` Not Provided dimension member; unresolved text attributes default to `'Not Provided'`.

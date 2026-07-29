# Power BI — DAX Measures Reference

PrintTimeUSA Data Warehouse · BI layer (ADR-017). The measures that sit on top of the
`gold.bi_dim_*` / `gold.bi_fact_*` serving views. **Ratios and time-intelligence live here, not in
the views** — a serving view exposes additive building blocks (amounts, counts); DAX combines them
in the filter context of each visual, which is the only place a ratio aggregates correctly.

**Related:** `docs/adr/017-bi-tool-power-bi-then-tableau.md` · the serving views in
`dbt/printtime_dw/models/gold/bi/` · `docs/bi/powerbi_build_guide.md` (connect + model + build).

---

## Setup (do these first)

1. **Create a dedicated measures table.** Home → Enter Data → an empty table named `_Measures`;
   put every measure below on it. Keeping measures off the fact tables makes them easy to find and
   keeps the field list clean. (This is convention, not correctness.)
2. **Mark the date table.** Select `bi_dim_date` → Table tools → **Mark as Date Table** → date
   column = `date`. Time-intelligence (`SAMEPERIODLASTYEAR`, `DATESYTD`, …) needs this.
3. **Set format strings** as noted per measure (Measure tools → Format). Currency = `$ #,##0`,
   percentages = `0.0%`.
4. **Naming:** measures are Title Case with spaces (`Gross Margin %`); columns stay as the view's
   snake_case. That visual distinction tells a report author at a glance what is a measure vs a
   column.

Throughout: **always `DIVIDE(n, d)`, never `n / d`** — `DIVIDE` returns blank on divide-by-zero
instead of erroring, which is the correct behavior in a slice with no denominator.

---

## Sales — `bi_fact_sales`

```DAX
Total Sales      = SUM ( bi_fact_sales[sales_amount] )        -- $ #,##0
Total Cost       = SUM ( bi_fact_sales[sales_cost] )          -- $ #,##0
Gross Profit     = SUM ( bi_fact_sales[gross_profit] )        -- $ #,##0
                   -- equals [Total Sales] - [Total Cost] by construction

-- THE ratio done right: ratio of the SUMS, in the visual's filter context —
-- never an average of the per-row margins the view deliberately does not expose.
Gross Margin %   = DIVIDE ( [Gross Profit], [Total Sales] )   -- 0.0%

Total Quantity   = SUM ( bi_fact_sales[sales_qty] )           -- #,##0

-- Weighted average price (sales ÷ units), NOT AVERAGE(unit_price) which would
-- weight a 1-unit line the same as a 500-unit line.
Avg Selling Price = DIVIDE ( [Total Sales], [Total Quantity] ) -- $ #,##0.00

-- Orders = distinct invoices (invoice_number is the degenerate dimension).
Order Count      = DISTINCTCOUNT ( bi_fact_sales[invoice_number] )   -- #,##0
Avg Order Value  = DIVIDE ( [Total Sales], [Order Count] )    -- $ #,##0

-- Time intelligence (requires bi_dim_date marked as the date table)
Sales LY         = CALCULATE ( [Total Sales], SAMEPERIODLASTYEAR ( bi_dim_date[date] ) )
Sales YoY %      = DIVIDE ( [Total Sales] - [Sales LY], [Sales LY] )   -- 0.0%
Sales YTD        = TOTALYTD ( [Total Sales], bi_dim_date[date] )       -- $ #,##0
```

## Payments — `bi_fact_payments`

Refunds are stored **negative** and flagged `payment_kind` / `is_refund`, so a plain `SUM` nets
them automatically (backlog #5). Split gross vs refunds on `payment_kind`, **never on the sign**.

```DAX
-- Net of refunds — the headline collections number.
Net Collected    = SUM ( bi_fact_payments[payment_amount] )   -- $ #,##0

Gross Payments   = CALCULATE ( [Net Collected], bi_fact_payments[payment_kind] = "Payment" )
Total Refunds    = CALCULATE ( [Net Collected], bi_fact_payments[payment_kind] = "Refund" )
                   -- negative by construction

-- Refunds as a positive share of gross (note the unary minus on the negative total).
Refund Rate %    = DIVIDE ( - [Total Refunds], [Gross Payments] )   -- 0.0%
Refund Count     = CALCULATE ( COUNTROWS ( bi_fact_payments ),
                               bi_fact_payments[is_refund] = TRUE () )   -- #,##0

Total Fees       = SUM ( bi_fact_payments[fee_amount] )       -- $ #,##0
Total Tax        = SUM ( bi_fact_payments[tax_amount] )       -- $ #,##0
```

## Customer behavior — `bi_fact_customer_snapshot`

**Semi-additive.** These are point-in-time balances/counts, one row per customer per month-end.
**Never sum a snapshot measure across snapshot dates** — always slice to a single `snapshot_date`.
The `Latest` pattern below pins to the most recent snapshot so a card shows "as of now" rather than
a meaningless sum over every month.

```DAX
-- Pin to the latest snapshot in the current filter context.
Latest Snapshot Date =
    CALCULATE ( MAX ( bi_fact_customer_snapshot[snapshot_date_key] ),
                ALL ( bi_dim_date ) )

Customers (Latest) =
    CALCULATE (
        DISTINCTCOUNT ( bi_fact_customer_snapshot[customer_key] ),
        bi_fact_customer_snapshot[snapshot_date_key] = [Latest Snapshot Date]
    )                                                          -- #,##0

At-Risk Customers (Latest) =
    CALCULATE (
        DISTINCTCOUNT ( bi_fact_customer_snapshot[customer_key] ),
        bi_fact_customer_snapshot[snapshot_date_key] = [Latest Snapshot Date],
        bi_fact_customer_snapshot[is_at_risk] = TRUE ()
    )                                                          -- #,##0

At-Risk %        = DIVIDE ( [At-Risk Customers (Latest)], [Customers (Latest)] )   -- 0.0%

Open Invoice Total (Latest) =
    CALCULATE (
        SUM ( bi_fact_customer_snapshot[open_invoice_total] ),
        bi_fact_customer_snapshot[snapshot_date_key] = [Latest Snapshot Date]
    )                                                          -- $ #,##0

-- Days Sales Outstanding proxy: average days-to-full-payment across customers in
-- the latest snapshot. Note it averages a per-customer average, so read it as a
-- trend indicator, not an exact figure.
Avg Days To Pay (Latest) =
    CALCULATE (
        AVERAGE ( bi_fact_customer_snapshot[avg_days_to_full_payment] ),
        bi_fact_customer_snapshot[snapshot_date_key] = [Latest Snapshot Date]
    )                                                          -- #,##0.0
```

---

## Notes for the report authors

- **One slicer, every fact.** Because the dimensions are conformed and separate, a single
  `bi_dim_date` or `bi_dim_customer` slicer cross-filters sales, payments and the snapshot at once.
  That is the payoff of the star model — measures above rely on it.
- **Two date roles on the snapshot.** `snapshot_date_key` is the active relationship to
  `bi_dim_date`; `last_order_date_key` is the second role — use `vw_last_order_date` as a separate
  date table, or an inactive relationship activated with `USERELATIONSHIP`. See the build guide.
- **The at-risk definition** lives in `bi_fact_customer_snapshot` (SQL), not here — so both Power
  BI and the coming Tableau version share one definition. Change the threshold there, not in DAX.

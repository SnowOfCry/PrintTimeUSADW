# Power BI — Connect, Model & Build Guide

PrintTimeUSA Data Warehouse · BI layer (ADR-017). Step-by-step to stand up the Power BI report on
the `gold.bi_*` serving views. Pair with `docs/bi/powerbi_dax_measures.md` (the measures) and
`docs/architecture/gold_star_schema.md` (the model it sits on).

> **What you do vs. what's already done.** The serving views, the model shape, the measures, and
> the dashboard specs are all prepared here. Your part is the Power BI Desktop GUI — connecting,
> importing, wiring relationships, pasting measures, and dropping visuals. Budget ~1–2 hours the
> first time.

---

## 0. Prerequisites

| Need | How |
|---|---|
| **Power BI Desktop** (free) | Microsoft Store → "Power BI Desktop" (recommended, auto-updates), or download from Microsoft. Windows 10/11. No license needed to build/view locally. |
| **Npgsql provider** | Power BI's PostgreSQL connector needs it. If Get Data → PostgreSQL prompts "install Npgsql", follow the link, install, restart Power BI. (Download: Npgsql GitHub releases, the `.msi`.) |
| **The DW running** | From the repo: `docker compose up -d postgres`. Confirm with the connection test below. |

**Connection details** (the DW Postgres container):

| Field | Value |
|---|---|
| Server | `localhost:5433` |
| Database | `printtime_dw` |
| Schema | `gold` |
| Username | `warehouse_user` |
| Password | in `.env` as `POSTGRES_PASSWORD` |

The port is `5433` on the host (mapped from `5432` in the container — see `docker-compose.yml`).

---

## 1. Connect

1. **Home → Get Data → More… → Database → PostgreSQL database → Connect.**
2. Server: `localhost:5433`  ·  Database: `printtime_dw`.
3. **Data Connectivity mode: Import** (not DirectQuery). At this data size Import is faster and
   enables the full DAX/time-intelligence surface. (DirectQuery would keep queries live against
   Postgres — unnecessary here and slower for interactive use.)
4. Credentials tab: **Database** → `warehouse_user` + the password from `.env`. Save.

---

## 2. Import the serving views

In the Navigator, tick **only these** (the star, not the raw dims/facts) — expand `gold`:

**Dimensions (8):** `bi_dim_date` · `bi_dim_product` · `bi_dim_customer` · `bi_dim_store` ·
`bi_dim_cashier` · `bi_dim_payment_method` · `bi_dim_payment_type` · `bi_dim_invoice`
**Facts (3):** `bi_fact_sales` · `bi_fact_payments` · `bi_fact_customer_snapshot`
**Second date role (1):** `vw_last_order_date` (for the snapshot's last-order date)

Click **Load**. Do **not** import the base `dim_*`/`fact_*` tables — the `bi_*` views are the clean
report model; importing both would clutter the field list and invite the wrong table.

---

## 3. Build the model (relationships)

Open **Model view**. Power BI may auto-detect some relationships on matching `*_key` names —
verify each against this list and create any that are missing. Every one is **one dimension → many
fact rows**, single cross-filter direction (dimension filters fact):

**bi_fact_sales**
- `date_key` → `bi_dim_date[date_key]`
- `product_key` → `bi_dim_product[product_key]`
- `customer_key` → `bi_dim_customer[customer_key]`
- `store_key` → `bi_dim_store[store_key]`
- `cashier_key` → `bi_dim_cashier[cashier_key]`
- `invoice_key` → `bi_dim_invoice[invoice_key]`

**bi_fact_payments**
- `date_key` → `bi_dim_date[date_key]`
- `customer_key` → `bi_dim_customer[customer_key]`
- `store_key` → `bi_dim_store[store_key]`
- `payment_method_key` → `bi_dim_payment_method[payment_method_key]`
- `payment_type_key` → `bi_dim_payment_type[payment_type_key]`
- `cashier_key` → `bi_dim_cashier[cashier_key]`
- `invoice_key` → `bi_dim_invoice[invoice_key]`

**bi_fact_customer_snapshot**
- `customer_key` → `bi_dim_customer[customer_key]`
- `snapshot_date_key` → `bi_dim_date[date_key]`  (the primary/active date role)
- `last_order_date_key` → `vw_last_order_date[last_order_date_key]`  (the second date role)

Because `bi_dim_date` and `bi_dim_customer` each connect to all three facts, **one date or customer
slicer cross-filters every subject area at once** — the payoff of the conformed star.

> **Role-playing dates.** A pair of tables can have only one *active* relationship, so the
> snapshot's two date columns can't both point at `bi_dim_date`. We use `vw_last_order_date` (built
> for exactly this, ADR-010) as an independent "Last Order Date" table. Alternatively, make a
> second (inactive) relationship `last_order_date_key → bi_dim_date` and activate it per-measure
> with `USERELATIONSHIP` — but the separate role table is simpler for report authors.

Then:

4. **Mark the date table.** Select `bi_dim_date` → Table tools → **Mark as Date Table** → `date`.
5. **Hide the keys from report view.** Right-click every `*_key` column (on facts *and* dims) →
   **Hide in report view**. Keys drive relationships, not visuals — hiding them keeps the field
   list to things people actually chart. Keep `invoice_number`, `po_number`, etc. visible.

---

## 4. Add the measures

1. Home → **Enter Data** → create an empty table named **`_Measures`** → Load.
2. Paste each measure from **`docs/bi/powerbi_dax_measures.md`** (New Measure, one at a time),
   setting the format string noted beside it.
3. Delete the dummy `Column1` on `_Measures` once a measure exists.

Do the setup steps at the top of that file first (measures table, date table, format strings).

---

## 5. Build the three dashboards

Three report pages, one per subject area. Fields below are `table[column]` or `[Measure]`.

### Page 1 — Sales & Margin
- **Slicers:** `bi_dim_date[calendar_year]`, `bi_dim_store[store_name]`, `bi_dim_product[department]`.
- **KPI cards:** `[Total Sales]`, `[Gross Profit]`, `[Gross Margin %]`, `[Order Count]`.
- **Matrix** — Rows `bi_dim_product[department]`; Values `[Total Sales]`, `[Gross Profit]`,
  `[Gross Margin %]`. (This is where the 4over catalog's ~17% margin vs ~63% in-house shows.)
- **Line chart** — Axis `bi_dim_date[calendar_year_month]`; Values `[Total Sales]`, `[Sales LY]`.
- **Clustered bar** — Axis `bi_dim_store[store_name]`; Value `[Total Sales]` (store comparison).
- *(optional)* **Map** — Location `bi_dim_store[store_state]`; Size `[Total Sales]`.

### Page 2 — Payments & Collections
- **KPI cards:** `[Net Collected]`, `[Gross Payments]`, `[Total Refunds]`, `[Refund Rate %]`.
- **Column** — Axis `bi_dim_payment_method[method_name]`; Value `[Net Collected]`.
- **Donut** — Legend `bi_dim_payment_type[type_name]`; Value `[Net Collected]`.
- **Line** — Axis `bi_dim_date[calendar_year_month]`; Value `[Net Collected]` (cash-flow trend).
- **Table (the PO view)** — `bi_dim_invoice[po_number]`, `[Net Collected]`, `[Refund Count]`;
  filter out `po_number = "Not Provided"`. Answers "group payments by PO" (backlog #10).

### Page 3 — Customer Health
- **KPI cards:** `[Customers (Latest)]`, `[At-Risk Customers (Latest)]`, `[At-Risk %]`,
  `[Open Invoice Total (Latest)]`.
- **Table (who's slipping away)** — `bi_dim_customer[customer_name]`,
  `bi_fact_customer_snapshot[days_since_last_order]`, `[Open Invoice Total (Latest)]`; visual-level
  filter `is_at_risk = True` and `snapshot_date_key = latest`. Sort by days descending.
- **Column** — Axis `bi_dim_customer[customer_state]`; Value `[At-Risk %]`.
- *(optional)* **Scatter** — X `lifetime_orders`, Y `lifetime_sales`, detail `customer_name`.

> The snapshot page reads "as of the latest month-end" — the `(Latest)` measures pin to it. With
> the current test data (snapshot 7 months after the last orders) most customers flag at-risk;
> that is a data-date artifact, and the 90-day threshold is adjustable in
> `bi_fact_customer_snapshot.sql` (ADR-017).

---

## 6. Save, refresh, share

- **Save** as `PrintTimeUSA.pbix`. Suggested location: `bi/powerbi/` in the repo. Note a `.pbix`
  is a **binary** file — it won't diff in git; treat it as an artifact, not source (the *logic* is
  in the views + measures reference, which are the reproducible parts).
- **Refresh data:** Home → Refresh re-pulls from Postgres (Import mode). Do this after a pipeline
  run to pick up new gold data. Automated/scheduled refresh needs the Power BI Service + an
  on-premises data gateway — out of scope for local development.

---

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| "PostgreSQL connector requires Npgsql" | Install the Npgsql `.msi` (GitHub releases), restart Power BI. |
| "could not connect" / timeout | Is the DB up? `docker compose up -d postgres`. Confirm host `localhost:5433` (not 5432). |
| Navigator shows no `gold` schema | Wrong DB/user, or grants. Connect as `warehouse_user` to `printtime_dw`; `gold` should list. |
| Blank rows / "(Blank)" on a slicer | A fact key not resolving — shouldn't happen (the `-1` members cover it). Recheck the relationship uses the `*_key` columns. |
| Margin % looks averaged/wrong | You charted a column, not the `[Gross Margin %]` measure. Ratios must be the DAX measure. |
| Snapshot numbers look inflated | You summed across snapshot dates. Use the `(Latest)` measures / slice to one `snapshot_date`. |

---

## Next: the Tableau version

Once this is built, the Tableau equivalent (ADR-017) connects to the **same** `gold.bi_*` views
with the same relationships and the same metric logic — only the calculated-field syntax and the
visuals differ. That is the point of the shared serving layer: the managers compare two front-ends
on identical numbers.

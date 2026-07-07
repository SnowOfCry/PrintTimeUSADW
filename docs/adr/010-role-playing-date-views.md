# ADR-010: Role-Playing Date Views over a Single dim_date

- **Status:** Accepted
- **Date:** 2026-06-20
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Informed:** Jaime Chavez Jr (CEO)

## Context

The date dimension plays multiple **roles** in this model. Beyond the ordinary transaction dates (invoice date on `fact_retail_sales`, payment date on `fact_payments`), three keys reference the calendar in a different role:

- `dim_customer.first_order_date_key` — the date a customer first ordered
- `fact_customer_behavior_snapshot.snapshot_date_key` — the day the snapshot was taken
- `fact_customer_behavior_snapshot.last_order_date_key` — the customer's most recent order

A report like "customers whose first order was in Q1, snapshotted in June" joins the calendar **twice in different roles in the same query**. If both joins hit `dim_date` directly, every column name is ambiguous (`calendar_year` of *which* date?) — the classic role-playing dimension problem.

## Decision

Keep **one physical `dim_date`** and expose each role as a **view** that re-labels every business calendar column with the role prefix:

| View | Key column | Consumer |
|---|---|---|
| `gold.vw_first_order_date` | `first_order_date_key` | `dim_customer` |
| `gold.vw_snapshot_date` | `snapshot_date_key` | `fact_customer_behavior_snapshot` |
| `gold.vw_last_order_date` | `last_order_date_key` | `fact_customer_behavior_snapshot` |

Each view is a straight `SELECT` over `dim_date` renaming `date_key → first_order_date_key`, `calendar_year → first_order_calendar_year`, and so on. ETL timestamps are not re-exposed. Ordinary transaction-date keys keep joining `dim_date` directly. A new role in the future costs one new view.

## Alternatives considered

1. **Physical copies of the date table per role.** Rejected: three-plus copies of the same calendar to load, extend, and keep synchronized — pure drift risk (extend `dim_date` to 2030 and forget one copy, and snapshot reports silently lose dates) for zero informational gain.
2. **No views — alias `dim_date` in each BI model/query.** Works mechanically, but pushes the role-naming problem onto every BI developer and every self-service user, who see two identical "Calendar Year" fields with no indication of which role they belong to. Rejected: the warehouse should ship the disambiguation, not delegate it.
3. **Single relationship + tool-specific role switching (Power BI inactive relationships / `USERELATIONSHIP`).** Rejected: forces DAX workarounds into every measure, is Power BI-only (Tableau has no equivalent), and contradicts the goal of a semantic model that works the same in any tool.

## Consequences

**Positive**

- One calendar to generate and extend (ADR-007: Type 0); every role stays automatically in sync.
- Zero additional storage; views are free at this scale.
- BI tools import each view as its own date table with self-describing column names (`snapshot_calendar_year` can never be confused with `first_order_calendar_year`).

**Negative / accepted costs**

- Column-per-role naming widens the documentation surface (the gold dictionary documents the views' role prefixes once, not per column). Accepted.
- Import-mode BI tools will materialize each view into their model cache — trivial for a calendar-sized table.
- Only the three designed roles are pre-built; a future role (e.g. due-date analysis) requires adding a view — deliberately cheap.

## Related

- ADR-007 (dim_date generation), ADR-001 (star schema)
- `sql/gold/002_create_gold_tables.sql` — the three view definitions
- `docs/data_dictionary/gold_data_dictionary.md` — role-playing views section

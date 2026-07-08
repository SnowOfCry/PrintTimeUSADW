# ADR-011: `-1` Not Provided Members and Unenforced Foreign Keys on Facts

- **Status:** Accepted
- **Date:** 2026-06-25
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Informed:** Jaime Chavez Jr (CEO)

## Context

Facts reference dimensions by surrogate key (`fact_retail_sales.product_key → dim_product.product_key`). Two coupled decisions follow:

1. Should the database **enforce** those links with `FOREIGN KEY` constraints?
2. What happens when a fact row's dimension lookup **fails** — a sale whose product hasn't reached `dim_product` yet, a payment with no store assigned?

The failure case is not hypothetical: dimension and fact loads are separate steps, sources contain NULLs (`payment.employee_id` and `store_id` are nullable in the OLTP), and a late-arriving dimension row must not cost the business a revenue line in the sales totals.

## Decision

**No `FOREIGN KEY` constraints on gold facts — indexed logical keys only. Every dimension seeds a reserved `-1` "Not Provided" member, and any failed lookup resolves to `-1`, never `NULL`.**

- Each dimension gets one reserved row: key `-1`, text attributes `'Not Provided'`, valid SCD2 housekeeping (`is_current = TRUE`), seeded **before the first fact load** (step 2 of the gold load order, ADR-007). This is Kimball's "unknown member" pattern; we label the member `'Not Provided'` so it reads cleanly in reports.
- Fact loads are **total**: every extracted measurement lands, with unresolved keys pointed at `-1` and `dq_issue_flag` set so the row is countable and traceable (ADR-012).
- Referential integrity is enforced **by the pipeline and by tests** (relationship checks fact→dim), not by database constraints.

## Alternatives considered

1. **Enforced FK constraints.** The OLTP-correct answer, rejected for the warehouse: one unmatched row would abort an entire 390k-row bulk load; constraints impose rigid load ordering and per-row validation overhead; and they offer no remedy for the business question — the sale still happened and must appear in revenue whether or not `dim_product` has caught up. Unenforced-but-tested keys are the standard Kimball warehouse posture.
2. **`NULL` keys for unmatched rows.** Rejected: inner joins silently drop the row (revenue disappears depending on how a query is written), Power BI renders NULL relationships as an unnameable blank row, and "how many facts are unmatched?" becomes unanswerable without `IS NULL` archaeology. `-1` makes the unknown *visible and countable*: `WHERE product_key = -1` is a monitoring query.
3. **Reject/quarantine facts with unmatched keys.** Rejected as the default: quarantining a sales line removes real revenue from totals until someone intervenes. Loading with `-1` + a DQ flag keeps totals correct immediately while still surfacing the issue. (Quarantine remains the right tool for *malformed* rows — ADR-012.)

## Consequences

**Positive**

- Totals always reconcile: an unmatched product never subtracts from revenue; it shows up as product "Not Provided" — visible in reports and honest about itself.
- No blank rows or dropped joins in Power BI / Tableau.
- Data-quality monitoring becomes trivial: "Not Provided" member counts per fact per batch are a dashboardable metric.

**Negative / accepted costs**

- **Integrity now depends on pipeline discipline + tests, not the engine.** A bug could write a key that matches nothing (not even `-1`); relationship tests (ADR-012) exist to catch exactly that.
- The `-1` seed rows are structural, not business data — dictionaries note them, and BI users occasionally ask what "Not Provided" means (a documentation duty, ADR-013).
- Implementation detail: the surrogate keys are `GENERATED ALWAYS AS IDENTITY`, so seeding `-1` requires `OVERRIDING SYSTEM VALUE` — a deliberate, visible exception in the seed script.

## Related

- ADR-007 (load order — seed step), ADR-009 (lean facts), ADR-012 (relationship tests, quarantine)
- `docs/naming_conventions/PrintTimeUSA_DW_Gold_Naming_Conventions.md` — `'Not Provided'` / `-1` default conventions
- `docs/load_strategy/gold_load_strategy.md` — Not Provided members section

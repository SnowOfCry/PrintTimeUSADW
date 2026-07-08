# ADR-007: Gold Load Strategy — SCD2 Dimensions plus Per-Grain Fact Loads

- **Status:** Accepted
- **Date:** 2026-07-01
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Informed:** Jaime Chavez Jr (CEO)

## Context

Bronze and silver each use one load strategy for every table (ADR-004, ADR-006). Gold cannot: dimensions describe entities whose attributes change over time and whose history the business wants (product prices, invoice status), while facts record measurements that must never be silently rewritten. A single strategy would either version things that shouldn't version, or overwrite history that must be kept.

The choice per table was driven by two signals already fixed in the gold specs: whether the table carries the SCD2 column block (`valid_from`/`valid_to`/`is_current`/`row_version`) in the DDL, and the table's grain per the silver-to-gold mapping.

## Decision

**Dimensions**

| Table(s) | Strategy | Rationale |
|---|---|---|
| `dim_date` | Type 0 — generate once, extend | Static calendar; deterministic `YYYYMMDD` key |
| `dim_payment_type` | Type 1 — overwrite on `type_code` | Static lookup; DDL deliberately has no SCD2 block |
| `dim_payment_method`, `dim_product`, `dim_store`, `dim_cashier`, `dim_customer`, `dim_invoice` | **Type 2** — hash-compare, close old version, insert `row_version + 1` | All carry the SCD2 block; price/status/assignment history is the point of the warehouse |

**Facts** (no SCD2 by design; loaded at their natural *parent grain* — the unit at which the source actually changes):

| Table | Grain | Strategy |
|---|---|---|
| `fact_retail_sales` | invoice line | **Reload-by-invoice**: delete the invoice's lines by `invoice_number` (degenerate key), reinsert from silver |
| `fact_payments` | payment | **Insert + second pass** resolving the self-referencing `parent_payment_key` (refund → original) via `(invoice_key, payment_sequence_num)` |
| `fact_customer_behavior_snapshot` | customer × snapshot date | **Periodic snapshot, append-only**: prior snapshot dates are immutable history |

**Load order:** `dim_date` → seed `-1` Not Provided members (ADR-011) → Type 1/2 dimensions → facts → snapshot. Dimensions load first because facts resolve surrogate keys against current (`is_current = TRUE`) dimension versions. Every gold load logs a batch to `audit.etl_batch_control` (ADR-008) with no watermark — silver is already current.

## Alternatives considered

1. **Type 1 everywhere (overwrite all dimensions).** Simplest, and what the silver layer already provides. Rejected: it erases the histories the model was designed to answer — "what was the margin when this was sold?" (product price changes), "how long do invoices sit in PARTIAL?" (status lifecycle). The SCD2 blocks in the DDL would be dead columns.
2. **Full reload of everything each run.** Viable at our volumes (~390k fact rows rebuild in seconds) and tempting for simplicity. Rejected for the dimensions: silver keeps only current versions (ADR-006), so a full dimensional rebuild **cannot reconstruct SCD2 history — every rebuild would permanently collapse all accumulated versions to today's state.** Once history is built, it exists only in gold; the load must preserve it. (Full reload remains an acceptable fallback for the *facts* specifically.)
3. **SCD2 on facts as well.** Rejected: facts are measurements, not descriptions. Corrections are handled by reloading the affected parent grain (invoice), and the payments/snapshot facts are append-only by nature. Versioned facts double storage to answer questions nobody asks.

## Consequences

**Positive**

- History accrues exactly where the specs put it: versioned dimensions, immutable measurements.
- Each fact reloads at the grain the business actually changes (an invoice, a payment, a snapshot day) — corrections are natural, no orphaned partial states.
- The `-1` Not Provided member + current-version key resolution keep fact loads total: no fact row is ever dropped for a missing dimension.

**Negative / accepted costs**

- **Gold dimensions become the only home of accumulated SCD2 history** — they can never be casually truncated/rebuilt; backup discipline matters (backlog #8).
- SCD2 version fidelity is bounded by gold's run frequency (documented in ADR-006); invoice status has the history-table escape hatch.
- The payments second pass makes `fact_payments` a two-step load — an ordering constraint the orchestrator must respect.

## Related

- ADR-006 (silver — the input and the fidelity bound), ADR-009 (why facts carry no source keys), ADR-011 (Not Provided members), ADR-008 (batch logging)
- `docs/load_strategy/gold_load_strategy.md` — full mechanics, SQL sketches, and the 13-step load order

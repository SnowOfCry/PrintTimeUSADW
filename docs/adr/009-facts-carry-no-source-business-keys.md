# ADR-009: Facts Carry No Source Business Keys (Reload at Parent Grain Instead)

- **Status:** Accepted
- **Date:** 2026-07-01
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Informed:** Jaime Chavez Jr (CEO)

## Context

A common warehouse pattern adds the source system's row identifier to every fact (e.g. `invoice_line_id` on the sales fact, `payment_id` on the payments fact) so the ETL can re-find a specific fact row later — for idempotent re-runs, corrections, and deletes. The gold design deliberately omits them: `fact_retail_sales` carries only `invoice_number` (the real OLTP invoice number, as a degenerate dimension), and `fact_payments` carries `payment_sequence_num` but no `payment_id`.

The question was whether that omission breaks loading. It was challenged during the load-strategy review and examined against the seeded production-shaped data.

## Decision

**Keep the facts lean — no source row identifiers.** Loading works at the **parent grain** instead of per row:

- **`fact_retail_sales`** reloads by invoice: `DELETE WHERE invoice_number = :n`, reinsert that invoice's lines from silver. Since `invoice_number` is the genuine OLTP key, this covers inserts, edits, and voids of any line without ever identifying a single line.
- **`fact_payments`** matches on **`(invoice_key, payment_sequence_num)`** — verified unique across all 57,409 seeded payments (payments per invoice: 1 × 24,998 invoices, 2 × 15,088, 3 × 745 — so ~39% of invoices have multiple payments, and the sequence number is what disambiguates them, exactly as the OLTP designed it: 1 = deposit, 2 = balance, …).
- **The refund chain needs no persisted `payment_id`.** `parent_payment_key` is resolved at load time from `silver.payment` (which retains `payment_id` and `parent_payment_id`): refund → parent's `(invoice_id, payment_sequence)` → parent's `payment_key`. The source id is used during the load and never stored on the fact.

## Alternatives considered

1. **Add source ids to the facts (`invoice_line_id`, `payment_id`).** The textbook "durable key" pattern, enabling surgical per-row `UPDATE`s and per-row incremental upserts. Rejected: reload-at-parent-grain already covers every correction case, the ids would carry zero analytical value for BI users, and lean facts are a Kimball design goal. Revisit condition: if fact volume ever makes per-invoice reloads too coarse.
2. **Add `line_number` to `fact_retail_sales`.** Would allow pinpointing one line within an invoice, mirroring `payment_sequence_num`. Rejected *for loading* (the reload unit is the invoice, so it's unnecessary); noted as a legitimate **degenerate dimension to add later if line-item drill-through reporting** is requested — a reporting decision, not a loading one.
3. **Row-hash matching (store a hash of source values as the match key).** Rejected: solves re-finding rows only until any value changes (the hash changes with it), which is precisely when you need the match.

## Consequences

**Positive**

- Facts stay narrow: every column is either a dimension key, a degenerate the business recognizes (`invoice_number`, `payment_sequence_num`), or a measure.
- Corrections are natural and atomic: an invoice's lines are always deleted/reinserted together — no risk of a half-updated invoice.
- The design was validated against data, not assumption: the `(invoice_id, payment_sequence)` uniqueness check is what confirmed `payment_id` adds nothing.

**Negative / accepted costs**

- No surgical single-line updates on `fact_retail_sales` — the whole invoice reloads even for a one-line change. Accepted: invoices have 1–12 lines; the difference is negligible.
- Per-row fact lineage to the exact silver row is not persisted (batch-level lineage via `etl_batch_id` remains). Accepted: reconciliation happens at invoice/payment grain, which the carried keys support.
- If finance/CS ever needs drill-through to a specific source transaction, `reference_no` (payment tender reference) is the natural degenerate to add — tracked as a revisit condition, not built speculatively.

## Related

- ADR-007 (the reload strategies this enables), ADR-011 (Unknown members for failed key lookups)
- `docs/load_strategy/gold_load_strategy.md` §"Why the facts carry no source business keys"
- `docs/architecture/Gold Schema.pdf` — fact column definitions

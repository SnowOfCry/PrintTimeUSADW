# ADR-012 (DRAFT / PROPOSAL): Data Quality & Validation Strategy

> **STATUS: PROPOSED — NOT YET DECIDED.**
> This is a working proposal to reconcile with Erick's own notes before it
> becomes the accepted ADR-012. Nothing here is final. Decision-makers will be
> Erick Palma (Data Engineer) + Freddy Vazquez (Manager).

## Why this is being decided before the silver build

The silver models are the next thing to be written. This decision fixes the
*shape* of every silver model (`validate → split by severity → merge the good
rows`), so deciding it first is nearly free, whereas retrofitting validation
onto 20 finished models is expensive. The ADR decides **behavior** (what happens
to a bad row); the concrete per-table checklist lives in a DQ spec that grows
during implementation.

## Proposed model: three severity tiers

| Tier | Behavior | When to use |
|---|---|---|
| **Flag** | Load the row, mark it, keep totals correct | Recoverable / analytical issues — the row is real and belongs in totals, but something is off |
| **Quarantine** | Do not load; store the raw row aside with a reason; count it in `rows_rejected` | The row cannot be trusted into silver (missing/uncastable business key) but should not fail the batch |
| **Fail batch** | Stop the load; mark the batch `failed` | Structural problems that make the whole extract untrustworthy |

Guiding principle (consistent with ADR-011): **never silently drop revenue.**
Flag keeps totals correct and visible; quarantine isolates untrustworthy rows;
fail stops only when the whole batch is suspect.

## Proposed check suite

### 1. Bronze → Silver (row-level, inside each merge)
| Check | Where (yours) | Tier | Priority |
|---|---|---|---|
| Required business key present & castable | `customer_id`, `invoice_id`, `payment_id`, … (`cast bigint; required`) | Quarantine | Must |
| Status maps to closed vocabulary | invoice (6), payment (5), customer (2), address_type (2) | Flag | Must |
| State code valid | `state_code` ∈ {CA, AZ, TX} | Flag | Must |
| Quantity/price sane | `order_qty > 0`, `unit_price ≥ 0` | Flag | Must |
| Date logic | `due_date ≥ invoice_date`; `payment_date` not future | Flag | Nice |
| Email shape | contains `@` (basic only) | Flag | Nice |

### 2. Financial reconciliation (the OLTP's own stated math) — highest value
| Check | Rule | Tier | Priority |
|---|---|---|---|
| Invoice header foots | `total = subtotal − discount + tax + fee` | Flag | Must |
| Balance consistent | `balance_due = total − paid` | Flag | Must |
| Line math foots | `line_total = qty × unit_price − discount` | Flag | Must |
| Header = Σ lines | `invoice.subtotal = Σ invoice_line.line_total` | Flag | Nice |

### 3. Batch-level (against `audit.etl_batch_control`)
| Check | Rule | Tier | Priority |
|---|---|---|---|
| Empty full-load extract | ref table returns 0 rows | Fail batch | Must |
| Row-count anomaly | full-load drops >50% vs. last succeeded batch | Fail batch | Nice |
| Count reconciliation | extracted = inserted + rejected | Fail batch | Must |

### 4. Post-load tests (dbt, the DAG test gate)
| Test | Where | Priority |
|---|---|---|
| `unique` + `not_null` on business keys | every silver table | Must |
| `relationships`: every fact key exists in its dim | 3 facts → 8 dims (safety net for ADR-011) | Must |
| One `is_current = TRUE` per natural key | all SCD2 dims | Must |
| `accepted_values` on statuses/codes | silver + gold | Must |
| Orphan check `invoice_line → invoice` | silver | Must |
| Freshness within window | `audit.etl_batch_control` (needs SLA, backlog #8) | Nice |
| Unknown-member rate below threshold | gold facts (`*_key = -1`) | Nice |

## New artifacts this requires
- **`audit.quarantine_row`** — raw row (JSONB) + reason + batch + source table. Does not exist yet.
- **`audit.dq_check_result`** — check name, table, key, batch, detail — because *silver tables have no DQ columns* (gold does: `dq_issue_flag`, `dq_issue_description`, `is_validated`). This is where silver flag-issues get recorded.
- Rule that populates the gold DQ columns per these tiers (currently defined but never set).

## Deliberate non-goals
- No RFC-compliant email validation, phone formatting, or zip regex — low value, high noise. ~20 meaningful checks beat 100 trivial ones; a DQ suite that cries wolf gets ignored.

## Open questions for the at-home session (Erick's notes vs. this proposal)
1. Are the three tiers the right granularity, or do you want a 2-tier (flag/reject) or 4-tier model?
2. Which reconciliation checks are **Flag** vs. **Quarantine**? (Proposal: flag, to keep revenue in totals — confirm.)
3. Do we build `audit.quarantine_row` + `audit.dq_check_result` now, or defer quarantine to a later phase and start with flag-only?
4. Freshness SLA value (backlog #8) — needed to make the freshness test real.
5. Anything in your notes not covered above.

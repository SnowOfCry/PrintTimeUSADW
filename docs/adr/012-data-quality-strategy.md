# ADR-012: Data Quality & Validation Strategy (Severity Tiers)

- **Status:** Accepted
- **Date:** 2026-07-02
- **Decision-makers:** Erick Palma (Data Engineer), Freddy Vazquez (Manager)
- **Informed:** Jaime Chavez Jr (CEO)

## Context

The gold tables already carry data-quality columns — `is_complete`, `is_validated`, `dq_issue_flag`, `dq_issue_description` — but nothing defined *when* they get set. Meanwhile bronze strips the OLTP's own constraints (state ∈ {CA,AZ,TX}, `order_qty > 0`, the invoice/line math), so the warehouse must re-check validity somewhere.

This is decided **before** the silver build because it fixes the *shape* of every silver model (`cast → clean → prune → deduplicate → validate`, per the Silver Validation & Transformation Set). Retrofitting validation onto 20 finished models is expensive; designing it in is nearly free. This ADR decides the **behavior** (what happens to a bad row) and the check suite; the per-table checklist grows during implementation.

The guiding constraint comes from ADR-011: **never silently drop revenue.** A quality issue must be visible without removing real business events from totals.

## Decision

### Three severity tiers

| Tier | Behavior | When |
|---|---|---|
| **Flag** | Load the row, mark it (`dq_issue_flag` in gold / `audit.dq_check_result` in silver), keep totals correct | Recoverable/analytical issues — the row is real and belongs in totals, but something is off |
| **Quarantine** | Do not load; store the raw row aside with a reason; count in `rows_rejected` | The row can't be trusted into silver (missing/uncastable business key) but must not fail the batch |
| **Fail batch** | Stop the load; mark the batch `failed` | Structural problems that make the whole extract untrustworthy |

### Missing vs. invalid (aligns with the Set, operation 6)

- **Missing** (NULL/empty): kept as `NULL` in silver (truthful); substituted with `'Not Provided'` (text) / `-1` member (key) in gold so BI never shows `(Blank)`. This is *defaulting*, not a DQ failure.
- **Invalid** (a value was provided but fails a rule — e.g. an unrecognized status): **kept raw and flagged**, never relabeled, so a genuine problem stays visible for investigation.
- **Uncastable required key**: quarantined.

### Check suite

**1. Bronze → Silver (row-level, inside each merge)**

| Check | Where | Tier | Priority |
|---|---|---|---|
| Required business key present & castable | `customer_id`, `invoice_id`, `payment_id`, … | Quarantine | Must |
| Status maps to closed vocabulary | invoice (6), payment (5), customer (2), address_type (2) | Flag | Must |
| State code valid | `state_code` ∈ {CA, AZ, TX} | Flag | Must |
| Quantity/price sane | `order_qty > 0`, `unit_price ≥ 0` | Flag | Must |
| Date logic | `due_date ≥ invoice_date`; `payment_date` not future | Flag | Nice |
| Email shape | contains `@` (basic only) | Flag | Nice |

**2. Financial reconciliation (the OLTP's own stated math — highest value)**

| Check | Rule | Tier | Priority |
|---|---|---|---|
| Invoice header foots | `total = subtotal − discount + tax + fee` | Flag | Must |
| Balance consistent | `balance_due = total − paid` | Flag | Must |
| Line math foots | `line_total = qty × unit_price − discount` | Flag | Must |
| Header = Σ lines | `invoice.subtotal = Σ invoice_line.line_total` | Flag | Nice |

**3. Batch-level (against `audit.etl_batch_control`)**

| Check | Rule | Tier | Priority |
|---|---|---|---|
| Empty full-load extract | ref table returns 0 rows | Fail batch | Must |
| Count reconciliation | extracted = inserted + rejected | Fail batch | Must |
| Row-count anomaly | full-load drops >50% vs. last succeeded batch | Fail batch | Nice |

**4. Post-load tests (dbt, the DAG test gate)**

| Test | Where | Priority |
|---|---|---|
| `unique` + `not_null` on business keys | every silver table | Must |
| `relationships`: every fact key exists in its dim | 3 facts → 8 dims (safety net for ADR-011) | Must |
| One `is_current = TRUE` per natural key | all SCD2 dims | Must |
| `accepted_values` on statuses/codes | silver + gold | Must |
| Orphan check `invoice_line → invoice` | silver | Must |
| Freshness within window | `audit.etl_batch_control` (needs the SLA — backlog #8) | Nice |
| "Not Provided" member rate below threshold | gold facts (`*_key = -1`) | Nice |

### New artifacts

- **`audit.quarantine_row`** — raw row (JSONB) + reason + batch + source table. Created when the silver models are built.
- **`audit.dq_check_result`** — check name, table, record key, batch, detail. Silver tables have no DQ columns (gold does), so silver flag-issues are recorded here.
- The rule set that populates the gold DQ columns (`dq_issue_flag`, `dq_issue_description`, `is_validated`, `is_complete`) per these tiers.

### Scope discipline

No RFC-compliant email validation, phone-format validation, or ZIP regex beyond length — low value, high noise. ~20 meaningful checks beat 100 trivial ones; a DQ suite that cries wolf gets ignored.

## Alternatives considered

1. **No formal DQ — clean opportunistically as problems appear.** The de-facto default of young warehouses. Rejected: `dq_issue_flag` would stay meaningless, `rows_rejected` never populated, and "can I trust this number?" would have no answer. The gold DQ columns already exist and demand a rule.
2. **Two tiers (accept / reject).** Simpler, rejected: it can't express the key nuance — a sale with a bad status is *not* the same as a sale with no customer id. Collapsing them either drops revenue (reject the first) or hides problems (accept the second). Three tiers keep revenue in totals *and* surface issues.
3. **Hard-fail the batch on any bad row.** The strictest posture. Rejected: one malformed row would abort a 390k-line load, and it removes real revenue until someone intervenes — the opposite of ADR-011's principle. Fail is reserved for *structural* problems only.
4. **An external DQ framework (Great Expectations / Soda).** Powerful, rejected for now: dbt tests plus the tiered in-model checks cover this single-source warehouse without a new tool and operator to run. Revisit if source count or check complexity grows (ties to the same trigger as ADR-003's connector-SaaS revisit).

## Consequences

**Positive**

- The gold `dq_*` columns and `audit.etl_batch_control.rows_rejected` finally have defined meaning — data trust becomes measurable, not asserted.
- Monitoring is trivial: unmatched-key counts, quarantine counts, and unmapped-status counts are one-line queries — a data-trust dashboard for the business.
- Revenue integrity holds: flag keeps real events in totals; nothing is silently dropped.
- The financial-reconciliation checks make the sales/collections numbers defensible ("the fact table foots to the source").

**Negative / accepted costs**

- Each silver/gold model carries validation logic (a `validate → split → merge` shape) — roughly +20–30% implementation effort on the silver build. Accepted: it's the cheap moment to add it.
- Two new audit tables to build and maintain.
- **Tiers are only real if someone looks.** Flags and quarantine need periodic review or they become theater — a small recurring operational duty (belongs in the runbook, backlog #8).
- Freshness checks depend on a stated SLA, which does not exist yet (deferred to backlog #8); the freshness test stays `Nice`/unbuilt until then.

## Related

- `docs/silver_validation_and_transformation_set.md` — operations 5 (validity checks) and 6 (unknown/missing handling) that this ADR governs
- ADR-005 (silver transformation standards), ADR-006 (merge), ADR-011 (`-1` "Not Provided" member — the "never drop revenue" principle)
- `audit.etl_batch_control` (ADR-008) — where batch-level results and `rows_rejected` land
- `docs/backlog.md` #8 — operational runbook + freshness SLA

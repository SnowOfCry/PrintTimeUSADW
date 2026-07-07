# ADR-005: Silver Transformation Standards (Casting, Normalization, Vocabularies, Derived Flags)

- **Status:** Accepted
- **Date:** 2026-05-12
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Informed:** Jaime Chavez Jr (CEO)

## Context

Bronze lands data raw (ADR-004); gold consumes conformed entities (ADR-001). Silver is where cleaning happens — but "cleaning" left undefined turns into ad-hoc fixes scattered across models. This ADR fixes the **standard transformation set** every silver model applies, so the rules are decided once, documented per column in the silver data dictionary, and applied identically everywhere.

Two properties forced rigor here:

- **Change detection depends on determinism.** Silver's merge updates a row only when `silver_row_hash` changes (ADR-006). If cleaning is not deterministic — if `'CA '` and `'ca'` clean differently on different runs — hashes flap and the warehouse "changes" without the business changing.
- **Gold conformance depends on vocabularies.** `dim_invoice.invoice_status` and the behavior snapshot's `customer_status` are only trustworthy if silver emits a closed set of values, not whatever the source spelled that day.

## Decision

Every silver model applies this standard set, with the per-column specifics declared in `docs/data_dictionary/silver_data_dictionary.md`:

| # | Standard | Rule | Example (from the dictionary) |
|---|---|---|---|
| 1 | **Type casting** | Cast every column to its declared silver contract type | `cast bigint` on ids; `cast NUMERIC(18,2)` on money; `cast date` |
| 2 | **String normalization** | `TRIM`, collapse internal multiple spaces, empty string → `NULL` | names, addresses, descriptions (`trim; '' -> NULL`) |
| 3 | **Case standardization** | Codes and SKUs upper-cased; emails lower-cased | `silver_state_code` (`ca → CA`), `silver_product_sku`, `silver_email` |
| 4 | **Controlled vocabularies** | Statuses map to closed lower-case sets; unmapped values are a DQ signal | invoice: `{pending, partial_paid, paid, cancelled, void, refunded}`; payment: `{pending, completed, failed, refunded, void}`; customer: `{active, inactive}`; address type: `{billing, shipping}` |
| 5 | **Derived business flags** | Reusable business semantics computed once in silver, not in every report | `silver_is_active_flag`, `silver_has_balance_due_flag`, `silver_paid_in_full_flag`, `silver_customer_name` (business name, else person name) |
| 6 | **Soft-delete standardization** | Source delete signals conform to `silver_is_deleted_flag`; rows are never physically deleted | all 20 tables |
| 7 | **Timestamps in UTC** | All `*_timestamp` columns store UTC; the convention is explicit, not driver-dependent | source `timestamptz` → naive UTC `TIMESTAMP` |
| 8 | **Lineage stamping** | Every row keeps its origin: `silver_source_record_id`, `silver_bronze_record_id`, `silver_bronze_batch_id`, `silver_batch_id` | all 20 tables |

Business-value transformations beyond this set (aggregations, metrics, dimensional shaping) are **out of scope for silver** — they belong to gold.

## Alternatives considered

1. **Pass-through silver (types only, no cleansing).** Deferring normalization to gold. Rejected: every gold model (and every future one) would re-implement trimming/casing/status-mapping, guaranteeing drift between models — and hash-based change detection in silver would be built on unstable raw values.
2. **Cleansing at extraction (in Python).** Rejected by ADR-003: business rules in pipeline code can't be re-run against history without re-extraction, and split the logic across two languages.
3. **Ad-hoc cleaning per model, as problems appear.** The de-facto standard of most young warehouses. Rejected deliberately: it produces inconsistent rules (one model maps `OPEN→pending`, another keeps `OPEN`), undocumented behavior, and no way to answer "what cleaning was applied to this column?" — the per-column dictionary answers that by design.

## Consequences

**Positive**

- Deterministic cleaning → stable row hashes → the merge only fires on true business change (no phantom updates).
- Gold inherits conformed vocabularies and reusable flags; report logic like "active customer" or "paid in full" is defined exactly once.
- Every cleaning rule is documented per column — auditable and interview-defensible ("what does silver do to `email`?" has a written answer).

**Negative / accepted costs**

- Silver values diverge from raw source spellings by design. Mitigated: bronze preserves the original values and each silver row points to its bronze origin (lineage columns).
- The dictionary must be maintained as models evolve — a real documentation tax, accepted as the price of having a contract.
- Unmapped status values need a defined behavior (reject, quarantine, or load-and-flag) — decided in the data quality ADR (ADR-012).

## Related

- ADR-003 (ELT — why cleansing is SQL), ADR-004 (bronze keeps raw), ADR-006 (merge/hash gating), ADR-012 (data quality)
- `docs/data_dictionary/silver_data_dictionary.md` — per-column cleaning rules (the operative spec)
- `docs/load_strategy/silver_incremental_merge_strategy.md` — standardized status vocabularies

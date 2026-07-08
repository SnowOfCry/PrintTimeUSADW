# ADR-014: Accept `dim_customer.customer_county` as 'Not Provided' (No Source)

- **Status:** Accepted
- **Date:** 2026-07-02
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Informed:** Jaime Chavez Jr (CEO)

## Context

The gold `dim_customer` schema includes a `customer_county` attribute. A source-to-target audit found it has **no source anywhere in the pipeline**:

- OLTP `customer_address` has `street_address`, `street_address2`, `city`, `state_code`, `zip_code` — **no county column**.
- `bronze.oltp_customer_address` and the silver address tables likewise carry no county (bronze faithfully copies the source, which doesn't have it).

So `customer_county` is the one gold column that cannot be populated from the data we extract. (Separately, the `bronze.oltp_customer_address` table *comment* misleadingly mentions "county enrichment" — it should be corrected; no such column exists.)

## Decision

**Ship `customer_county` populated as `'Not Provided'`** (per the missing-data convention, ADR-011/ADR-012), rather than dropping the column or blocking the gold build.

- The column stays in `dim_customer` so the model is stable if a county source is added later.
- It is not left `NULL` (no blanks in BI, per ADR-012); it reads `'Not Provided'`.
- County-level analysis is therefore **not available** until a source exists — an accepted, documented limitation, not a hidden one.

## Alternatives considered

1. **Drop `customer_county` from `dim_customer`.** Rejected: county is a plausible future analytics axis (regional reporting), and re-adding a dropped dimension column later is more disruptive than parking it as `'Not Provided'` now. Keeping it makes the eventual source addition a data change, not a schema change.
2. **Derive county from ZIP now via a reference table.** The real fix — a `ZIP → county` crosswalk (public USPS/Census data). Rejected *for now*: it is unbuilt work with no current business demand, and adding a new reference source is a small project of its own. Tracked as backlog #3, to be built when county reporting is actually requested.
3. **Infer county from city + state.** Rejected: city→county is many-to-many and ambiguous (a city can span counties; county names repeat across states), so it would fabricate wrong data — worse than an honest `'Not Provided'`.

## Consequences

**Positive**

- The gold build is unblocked; every other `dim_customer` attribute loads normally.
- The gap is explicit and honest — `'Not Provided'` in reports, documented here and in the mapping, rather than a silently empty or fabricated field.
- Adding county later is a clean, additive change (populate the existing column from a new reference source) with no schema churn.

**Negative / accepted costs**

- **No county-level customer reporting** until a source is added. Accepted: not a current business requirement.
- A `'Not Provided'` column can invite "why is this always blank?" questions from BI users — mitigated by documenting it (governance duty, ADR-013).

## Revisit trigger

Build the `ZIP → county` reference (backlog #3) when the business requests county-level reporting. At that point `customer_county` is populated from the crosswalk and this ADR is superseded.

## Related

- ADR-011 / ADR-012 (`'Not Provided'` missing-data convention), ADR-004 (bronze copies the source faithfully — which lacks county)
- `docs/source_to_dw_mapping/Silver_to_Gold_mapping.md` — the flagged gap; `docs/backlog.md` #3 (ZIP→county reference)
- `docs/dw_readiness_review.md` — where the gap was first identified

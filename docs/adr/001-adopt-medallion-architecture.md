# ADR-001: Adopt a Medallion Architecture (Bronze → Silver → Gold)

- **Status:** Accepted
- **Date:** 2026-04-02
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Informed:** Jaime Chavez Jr (CEO)

## Context

PrintTimeUSA needs a data warehouse that turns the operational print-shop system (invoices, invoice lines, payments, customers, products across CA/AZ/TX stores) into reliable analytics: retail sales, payments/collections, and customer behavior.

Business requirements that shaped this decision:

- **Auditability.** Invoice status changes (OPEN → PARTIAL → PAID → VOID) and payment corrections must be traceable back to exactly what the source system said, and when.
- **Reprocessability.** Business rules will evolve (status vocabularies, derived flags, margin logic). We must be able to re-run transformations against already-extracted data without re-extracting from the operational system.
- **Trustworthy BI.** Power BI / Tableau consumers need a clean, conformed star schema — not raw operational tables.
- **Small team.** One data engineer builds and operates this; the architecture must have clear, simple contracts per layer.

## Decision

Adopt a three-layer **medallion architecture**:

| Layer | Contract | Load pattern |
|---|---|---|
| **Bronze** | Raw source rows, as extracted, plus lineage metadata. Immutable. | Append-only |
| **Silver** | One clean, standardized, current row per business entity. | Incremental merge |
| **Gold** | Kimball star schema: conformed dimensions (SCD2) and facts. | Dimensional loads |

Each layer only reads from the layer above it (source → bronze → silver → gold). Cross-cutting run/watermark tracking lives in a separate `audit` schema (see ADR-008).

**Gold-layer modeling approach.** Having selected the medallion architecture, we then decided how to model the gold (presentation) layer: **star schema**, not snowflake. Dimensions are denormalized — `dim_product` carries category and department descriptions directly (instead of snowflaked `dim_category`/`dim_department` lookup tables), and `dim_customer` carries city/state/city_state. Facts join one hop to each dimension. Snowflaking was rejected because the storage it saves is trivial at our volumes, while the extra joins complicate every Power BI / Tableau model and slow ad-hoc queries.

## Alternatives considered

1. **Inmon (Corporate Information Factory).** A normalized (3NF) enterprise data warehouse built first, with departmental data marts derived from it. Rejected: its strength is integrating many sources across a large organization under central governance; for a single-source warehouse operated by one engineer, the heavy upfront enterprise modeling delays business value without adding integration benefit.
2. **Pure Kimball (transient staging → dimensional bus).** Dimensional models built directly from a transient staging area. We keep Kimball's *dimensional method* for gold, but rejected the pure form: transient staging is truncated each run, so raw history is lost — reprocessing a rule change would require re-extracting from the OLTP, and invoice-status history could not be reconstructed after the fact. Medallion effectively modernizes Kimball by persisting auditable bronze/silver layers beneath the dimensional presentation layer.
3. **Data Vault (hubs/links/satellites) + star schema marts.** Strong auditability, but its modeling overhead (3+ tables per entity, specialized conventions) is not justified for a single-source warehouse operated by one engineer. Medallion's bronze layer provides the audit/history benefit at a fraction of the complexity.
4. **Flat reporting tables (no dimensional model).** Denormalized one-big-tables per report. Rejected: fast to start, but every new question requires a new table, metrics drift between tables, and there is no conformed customer/product/date across subject areas.

**Within gold: star vs snowflake.** Snowflake schema (normalized dimension hierarchies) was considered and rejected — see the Decision section.

## Consequences

**Positive**

- Bronze preserves a complete, immutable change feed — SCD2 dimensions, audits, and rule-change reprocessing never require touching the operational system.
- Each layer has a single, teachable contract ("bronze appends, silver merges, gold models"), which keeps a one-engineer operation maintainable.
- BI consumers only ever see gold; upstream refactors don't break reports.

**Negative / accepted costs**

- Data is stored ~3× (raw, clean, modeled). Accepted: volumes are modest (~670k source rows) and PostgreSQL storage is cheap relative to the auditability gained.
- Every new source entity costs three artifacts (bronze table, silver model, gold integration) instead of one. Accepted: the per-layer conventions and mapping docs make this mechanical.
- Latency: data reaches BI only after three hops. Accepted: the business cadence is daily, not real-time.

## Related

- ADR-002 (platform/stack), ADR-004 (bronze append-only), ADR-006 (silver merge), ADR-007 (gold loads)
- `docs/load_strategy/` — per-layer strategy details
- `docs/source_to_dw_mapping/` — the three hop mappings

---
name: dw-spec-first
description: >
  Consult the PrintTimeUSA data-warehouse specifications BEFORE writing or changing
  anything in this repo. Use this skill whenever the task touches the warehouse — building
  or editing a dbt model, a contract, a source, a transformation, a naming choice, a load
  strategy, a data-quality or normalization rule, a status vocabulary, a derived column, a
  schema/DDL, or any decision about how data should be shaped or named. Trigger it even when
  the user just says "build the X model", "clean up Y", "add a column", "why is Z like
  this", or proposes a rule ("let's lowercase statuses", "preserve case", "use person name")
  — because the answer is almost always already decided in an ADR, the DDL spec, the
  data dictionary, the source-to-DW mapping, or the validation set. The project rule is:
  the spec is the source of truth, and when intuition and the spec disagree, the spec wins.
  Read the relevant spec first; do not decide from memory or first principles.
---

# Spec-First for the PrintTimeUSA Data Warehouse

## Why this exists

This warehouse is a deliberately designed system: every layer, load strategy, naming rule,
vocabulary, and derived column was decided and written down *before* the code. Deciding from
intuition — even good intuition — reintroduces drift the specs were written to prevent, and
silently contradicts decisions that were already made and reviewed. The cost of skipping the
spec is real: a "sensible" choice (preserve status case, map a name a certain way, pick a
freshness order) can violate an Accepted ADR, break a gold FK join, or make a hash unstable.

So the habit is simple and non-negotiable: **before writing or changing anything, read the
spec that governs it.** When your instinct and the spec disagree, the spec wins — or, if the
spec is genuinely wrong or missing, surface that to the user as a decision rather than quietly
overriding it.

## The one rule

> Read the governing spec **before** you act. Decide from the spec, not from memory.
> If intuition conflicts with the spec, the spec wins. If the spec seems wrong, stop and
> raise it with the user — changing a spec is a decision, not a side effect.

## Where the truth lives

Match the task to the doc(s) and read them first. Paths are relative to the repo root.

| If the task involves… | Read first |
|---|---|
| The exact columns, types, NOT NULLs, PK of a table | `sql/<layer>/*.sql` — the **DDL spec** (e.g. `sql/silver/002_create_silver_tables.sql`) |
| Why the architecture / layer / strategy is the way it is | `docs/adr/` (start at `docs/adr/README.md` — the index) |
| How a column maps from source to target, per table | `docs/source_to_dw_mapping/` (OLTP→bronze, Bronze→Silver, Silver→Gold) |
| Column meaning, allowed values, business definition | `docs/data_dictionary/` (bronze, silver, gold, audit) |
| Cleaning, casting, normalization, vocabularies, derived flags | `docs/adr/005-silver-transformation-standards.md` + `docs/silver_validation_and_transformation_set.md` |
| Load strategy (append / merge / SCD2), watermark, dedup order | `docs/load_strategy/` + ADR-004 (bronze), ADR-006 (silver), ADR-007 (gold) |
| Naming conventions | `docs/naming_conventions/` |
| Governance, PII, retention, deletion | `docs/adr/013-data-governance-and-pii.md` |
| Batch control / audit schema | `docs/adr/008-consolidate-etl-control-into-audit-schema.md` + `sql/audit/` |

When unsure which doc applies, check `docs/adr/README.md` first — it indexes every decision.

## The check, before you write

1. **Name the decision.** What am I about to choose — a type, a name, a normalization rule, a
   vocabulary, a load behavior, a derived value?
2. **Find its spec.** Use the table above. Open the DDL spec for the table *and* the ADR /
   dictionary / mapping that governs the rule. Read the relevant part — don't skim from memory.
3. **Confirm the data if the rule depends on it.** Vocabularies, derived columns, and "business
   vs person" style splits depend on actual source values — verify against the database, not
   assumptions (e.g. the real status values, whether a source column is populated).
4. **Act from the spec.** Implement what the spec says. Cite it in the model header comment
   (the existing silver models reference their ADR + DDL + strategy in the header block).
5. **If intuition disagrees with the spec:** the spec wins. Note the tension to the user.
6. **If the spec is wrong, missing, or self-contradicting:** stop and raise it as a decision.
   Do not silently override a written decision, and do not invent an unwritten one — propose
   the change, get agreement, and update the spec (usually the ADR or the validation set)
   *before or alongside* the code, so doc and code never drift.

## Common traps this prevents

- **Status vocabularies.** ADR-005 already mandates lowercase closed sets. Preserving source
  case (`OPEN`, `CLEARED`) violates it and breaks gold FK joins that expect the standardized
  value. Check ADR-005 before choosing a case rule for any status/type/code.
- **Derived columns & name rules.** "business name else person name", `is_active_flag` from
  status, deriving `full_name` from first+last — these are specified (ADR-005 §5, the
  validation set) and depend on real data (e.g. `full_name` is empty in source). Verify both.
- **Freshness / dedup order.** The `ROW_NUMBER()` ordering is standardized in
  `silver_incremental_merge_strategy.md` (updated → created → bronze load → bronze_record_id).
  Don't invent a different order (e.g. `source_row_version`) per table.
- **Types & NOT NULLs.** The DDL spec is authoritative. A silver table's 7 NOT NULLs (key,
  source_system, batch_id, created_at, updated_at, is_deleted_flag, row_hash) come straight
  from the DDL — the contract must enforce all of them, not a subset.
- **What silver keeps vs gold.** Silver keeps all business columns; gold is the selective
  layer (validation set §3). Don't drop business columns in silver.

## The tell

If you're about to type a transformation, a type, a name, or a rule and you're pulling the
answer from memory or "what makes sense" rather than from an open spec file — that is the
moment to stop and read the spec. The specs are short and indexed; reading them is cheaper
than the drift that skipping them causes.

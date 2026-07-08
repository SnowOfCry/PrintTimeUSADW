# PrintTimeUSA DW — Readiness Review

**Scope:** Advisory, read-only. Cross-references the artifacts under `docs/` (architecture schemas, naming conventions, data dictionaries, source-to-DW + silver-to-gold mappings, load-strategy notes) against the DDL under `sql/` (bronze, silver, gold, audit) and the extractor config (`ingestion/config/ingestion_config.yml`). Treats the schemas/mappings as the source of truth and checks that they agree.

**Date:** 2026-06-26 · **Reviewer role:** DW architect (advisory)

**Bottom line up front:** The *design* (OLTP → bronze → silver → gold) is coherent, and the mappings are complete enough to build a fully-loadable Gold star schema — with **two real source gaps** (`dim_customer.customer_county`, `gold.dim_date` has no generator). However, the project **cannot be populated end-to-end as currently wired**: the implemented extractor lands data in `bronze.raw_*` tables that do **not** match the designed `bronze.oltp_*`/`bronze.ref_*` tables silver reads from, the bronze/silver/gold **transformation logic does not exist yet** (only DDL), and the implemented `full_load` path contradicts the append-only bronze design. Details and a prioritized fix list below.

---

## 1. Populatability by layer

### 1a. OLTP → Bronze

**Design verdict: every bronze table is sourceable. Implementation verdict: broken lineage as wired.**

The OLTP source (`docs/architecture/Final OLTP.pdf`, 23 tables) and the bronze design agree on content. All **20** bronze tables (`sql/bronze/002_create_bronze_tables.sql`: 14 `oltp_*` + 6 `ref_*`) map to a real OLTP table with all business columns present (`docs/source_to_dw_mapping/OLTP_source_to_bronze_mapping.md`). Column renames are intentional and traceable (e.g. OLTP `invoice_line.extended_amount` → `bronze.oltp_invoice_line.line_total_amount`; `product.unit_cost` → `oltp_product.unit_cost_amount`; `payment.gross_amount` kept as `oltp_payment.gross_amount`).

**BLOCKER — extractor targets do not match the bronze design:**

| What the design expects (silver reads these) | What the live pipeline actually creates |
|---|---|
| `bronze.oltp_customer` | `bronze.raw_customer` |
| `bronze.ref_state` | `bronze.raw_ref_state` |
| `bronze.ref_payment_method` | `bronze.raw_payment_method` |

`ingestion/config/ingestion_config.yml` extracts 23 tables by **OLTP name**, and the loader writes to `bronze.raw_<name>` (`schema=bronze`, `target_table=raw_<table>` per `ingestion/load/bronze_loader.py` + `ingestion/main.py`). So the pipeline populates a *different physical table set* than the documented bronze layer. Silver's declared sources (`bronze.oltp_customer`, `bronze.ref_state`, …) would never be filled.

**Secondary implementation gaps (same root cause):**
- The bronze DDL requires `bronze_batch_id`, `bronze_source_system`, `bronze_row_hash` as `NOT NULL` with **no defaults**. A naive `df.to_sql()` of raw OLTP columns cannot populate them, and `to_sql(if_exists="replace")` would *drop* the typed DDL. The bronze "rename + stamp metadata + hash" load logic is **not implemented** — only a raw passthrough exists.
- Three extracted tables have **no bronze home**: `fee_type`, `product_variant`, `audit_log` (OLTP's own). They are extracted but unused by the bronze design (acceptable, but wasted work / confusing).

**Assumption:** I treat `bronze.oltp_*`/`ref_*` (the DDL + mapping) as the source of truth and the `raw_*` extractor as the thing that is out of step.

### 1b. Bronze → Silver

**Verdict: fully sourceable by design; no transform implemented yet.**

`sql/silver/002_create_silver_tables.sql` defines **20** silver tables, each with exactly one bronze source (`docs/source_to_dw_mapping/Bronze_to_Silver_mapping.md`), 1:1 with the 20 bronze tables. The merge strategy (`docs/load_strategy/silver_incremental_merge_strategy.md`) is well-specified (dedup latest-per-key via `ROW_NUMBER()`, upsert on business key, `silver_row_hash` change gate). No table is orphaned. **But:** there are **no silver transformation models/SQL** in the repo (the `dbt/printtime_dw/models/silver/` folder holds only placeholder YAML; `sql/silver/` is DDL only). So silver is *designed to be loadable* but is *not yet implemented*.

### 1c. Silver → Gold

**Verdict: all dims/facts sourceable from silver except `dim_date` (generated) — with one column with no source.**

Per `docs/source_to_dw_mapping/Silver_to_Gold_mapping.md` and `sql/gold/002_create_gold_tables.sql`, every Gold column traces to silver except the standard generated blocks (surrogate keys, `record_hash`, SCD2/DQ/audit). Two exceptions:

- **`gold.dim_date` has no generator.** It is "generated calendar", but there is **no seed, dbt macro, or SQL** in the repo to populate it. Until it exists, `dim_date`, the three `vw_*_date` views, `dim_customer.first_order_date_key`, and every fact `*_date_key` cannot be populated. **Gap (blocker for gold).**
- **`gold.dim_customer.customer_county` has no source.** Confirmed at the column level: OLTP `customer_address` and `bronze.oltp_customer_address` contain `street_address`, `street_address2`, `city`, `state_code`, `zip_code` — **no county column**. (Note: the `bronze.oltp_customer_address` table comment misleadingly claims "street/city/state/**county** enrichment", but no such column exists.) **Known gap** — defaults to `'Not Provided'`.

No transformation SQL/dbt models exist for gold either (only DDL + this review's recommended strategy).

**Minor analytical lineage notes (not blockers):**
- `product_variant` (`variant_id`, `color`) survives into `silver.invoice_line` (`silver_variant_id`, `silver_color`) but is **dropped** at gold: `fact_retail_sales` has no variant/color and there is no `dim_variant`. Sales cannot be sliced by color/size.
- `fee_type` is extracted but never modeled; fee is only the additive `fee_amount`. Fee cannot be broken down by fee type.

---

## 2. Source-to-DW mapping audit

**Does the mapping cover every Gold dim and fact column? Yes — 11/11 tables, every column.** `docs/source_to_dw_mapping/Silver_to_Gold_mapping.md` enumerates all 8 dimensions, 3 facts, and the 3 role-playing views, column-by-column, classed `direct/cast/lookup/derive/generate`. A DDL-vs-dictionary diff (done when the gold dictionary was authored) showed **no column drift**.

| Issue type | Findings |
|---|---|
| Missing from mapping | **None.** Every gold column appears. |
| Mapped from a non-existent source | **1 — `dim_customer.customer_county`** (no county in OLTP/bronze/silver). Correctly flagged in the mapping as a gap defaulting to `'Not Provided'`. |
| Type-mismatch / narrowing | **Amounts narrow silver→gold:** silver money is `NUMERIC(18,2)` (e.g. `silver_total_amount`, `silver_payment_amount`); gold uses `NUMERIC(12,2)` (`invoice_total`, `payment_amount`, `sales_amount`, …). Safe for this business (invoice values ≪ 10¹⁰) but it is a real precision reduction — overflow would error on load if any amount ≥ 10¹⁰. `lifetime_sales_amount`/`open_invoice_total` use `NUMERIC(14,2)` (good). |
| Ambiguous mapping | **`dim_product.department_number/description`** can resolve via two paths (`product.department_id` directly, or `product.category_id → product_category.department_id`). Mapping uses `product.department_id` — fine, but the two paths can disagree if source data is inconsistent; pick one and enforce. Minor. |
| Rename chains to verify | `payment_amount` ← `silver_payment_amount` ← `bronze.oltp_payment.gross_amount`. Traceable but the `gross_amount → payment_amount` rename should be explicit in the silver dictionary. |

**Can the mapping guarantee a fully-loadable Gold layer?** **Almost — with two caveats.** Every gold column has a defined rule, so an implementer has no ambiguity *except*: (1) `customer_county` (no source → `'Not Provided'`), and (2) `dim_date` requires a generator the mapping assumes but the repo doesn't provide. With those two handled, the mapping is complete enough to load Gold fully.

---

## 3. Consistency checks

| Check | Result |
|---|---|
| **DDL ↔ data dictionary drift (gold)** | ✅ No drift. All 11 gold tables match column-for-column (`docs/data_dictionary/gold_data_dictionary.md` ↔ `sql/gold/002`). |
| **Surrogate-key / natural-key integrity** | ✅ Every dim/fact has an identity `*_key` PK; natural keys are `_id`/`_code`/`_number` and not the PK. `dim_date.date_key` is correctly a `YYYYMMDD` smart key (not identity) so facts/views can derive it. |
| **Fact → dimension FK coverage** | ✅ Every fact key has a target dimension. `fact_retail_sales` (6 dims + degenerate `invoice_number`), `fact_payments` (8 incl. self-ref `parent_payment_key`), `fact_customer_behavior_snapshot` (3, via `dim_date` roles). FKs are **not enforced** (indexes only) — by design; relies on the `-1` Not Provided member. |
| **Role-playing date views** | ✅ `vw_first_order_date`, `vw_snapshot_date`, `vw_last_order_date` each re-label `gold.dim_date`. Clean for BI (each view is its own date table). |
| **`record_hash` algorithm (SHA-256 vs MD5)** | ⚠️ Cosmetic only. Gold `record_hash CHAR(64)` = SHA-256; bronze/silver `*_row_hash TEXT` = MD5 (per load-strategy notes). Each layer hashes its **own** values for its **own** change detection and **never compares across layers**, so the mismatch causes **no functional problem**. `CHAR(64)` exactly fits SHA-256 hex; a 32-char MD5 fed there would space-pad, but gold computes its own SHA-256, so this won't happen. Recommend a one-line note in the naming doc (already present). |
| **Control/audit table naming** | ✅ **RESOLVED (Option A).** Standardized on `audit.etl_batch_control` (+ `audit.audit_log`). The `control` schema was dropped, the Docker init now bootstraps the audit tables (`002_create_audit_tables.sql`), the bronze comments/docs were repointed `control.`→`audit.`, and the ingestion (`batch_control.py`, `watermark.py`, `main.py`) writes/reads it. `bronze_batch_id` (BIGINT) joins `audit.etl_batch_control.batch_key`. |
| **Naming-convention violations** | Minor: `gold.dim_date.date` uses the bare word `date` (a SQL keyword and exactly the "vague name" the general naming doc says to avoid). `dim_cashier.is_active VARCHAR(3)` ('Yes'/'No') departs from the `is_*_flag BOOLEAN` rule — but is documented as an explicit gold exception. Gold dropping the `_flag` suffix on `is_current`/`is_deleted` is intentional Kimball style. |
| **Bronze append-only vs implemented `full_load`** | ❌ Contradiction (see §5). |

---

## 4. BI readiness (Power BI / Tableau)

**Overall: the gold star schema is BI-friendly and close to drop-in for an import semantic model — once it's populated and the Not Provided members are seeded.**

| Dimension of readiness | Assessment |
|---|---|
| **Conformed dimensions** | ✅ `dim_customer`, `dim_store`, `dim_date`, etc. are shared across facts (e.g. `dim_customer`/`dim_store` join both `fact_retail_sales` and `fact_payments`). Conformed and reusable. |
| **Surrogate keys** | ✅ Integer identity keys → efficient, stable relationships. |
| **Grain clarity** | ✅ Clear and distinct: `fact_retail_sales` = one invoice line; `fact_payments` = one payment; `fact_customer_behavior_snapshot` = one customer × snapshot date. |
| **Degenerate dimension** | ✅ `invoice_number` carried on `fact_retail_sales` (no junk dimension needed). |
| **`-1` "Not Provided" member** | ❌ **Not seeded anywhere.** No script inserts the `-1` Not Provided row into each dimension. With unenforced FKs, unmatched fact keys will surface as blanks/limited relationships in Power BI ("blank row"). **Must seed a `-1` member per dimension.** |
| **Additive vs non-additive** | `fact_retail_sales` (`sales_qty`, `sales_amount`, `sales_cost`, `gross_profit`) = **fully additive** ✅. `fact_payments` (`payment_amount`, `tax_amount`, `fee_amount`, `net_amount`) = additive, **but** refunds chained via `parent_payment_key` risk double counting unless refunds are signed-negative or excluded — define the sign convention. `fact_customer_behavior_snapshot` = **non-additive across `snapshot_date`** (`lifetime_*`, `open_invoice_*`, `avg_days_to_full_payment`, `*_count` are point-in-time). BI must aggregate these with "last value in period"/AVERAGE, **never SUM across dates** — call this out in the model or users will write wrong measures. |
| **Date dimension + role-playing** | ✅ `dim_date` + 3 views = standard Power BI role-playing (separate date tables) → avoids `USERELATIONSHIP`/inactive-relationship DAX. Mark `dim_date` as the model Date table; ensure it is **contiguous/gap-free** (depends on the missing generator). |
| **Modeling friction / awkward DAX-LOD** | (1) `dim_date.date` is a reserved word → needs quoting in some SQL/DAX contexts (minor). (2) Non-additive snapshot measures (above) are the main trap. (3) No Not Provided member → blank-row handling. (4) `is_active`/indicators stored as `'Yes'/'No'` text are fine as slicers but can't be summed; expose a numeric companion if a % active KPI is needed. |

No structural blocker forces awkward DAX **beyond** the non-additive snapshot handling and the missing Not Provided member — both are normal, well-understood patterns once flagged.

---

## 5. Load-strategy review + Gold recommendation

### Existing strategies — consistency

- **Bronze:** declared **`incremental_append`**, append-only/immutable (`docs/load_strategy/bronze_incremental_append_strategy.md`). Coherent and well-justified (keeps full change history for SCD2).
- **Silver:** declared **`incremental_merge`** (upsert on business key, hash-gated). Coherent and well-specified.
- ❌ **Inconsistency:** `ingestion/config/ingestion_config.yml` marks 13 tables (`ref_*`, `store`, `department`, `product_category`, `employee`, `product`, `product_variant`) as **`full_load`**, and the loader implements `full_load` via `to_sql(if_exists="replace")` = **truncate + overwrite**. That directly **violates the append-only bronze design** (which permits a *full extract appended under a new batch*, never a replace). For static `ref_*` the doc explicitly allows an append-style full snapshot; the *replace* implementation is the problem, plus full-loading bigger dimension-like tables (`product`, `employee`) every run is heavy. Reconcile loader behavior with the append-only doc.
- **Gold:** no strategy declared anywhere except the SCD2 columns in the DDL. Recommendation below.

### Recommended Gold load strategy (table by table)

| Gold table | Recommended strategy | One-line justification |
|---|---|---|
| `dim_date` | **Generate once, extend forward** (range insert; no SCD) | Static calendar; carries no SCD2 columns. Build the generator (currently missing). |
| `dim_payment_type` | **SCD Type 1** (overwrite-in-place) | Tiny static lookup; history irrelevant; table intentionally has **no** SCD2 columns. |
| `dim_payment_method` | **SCD Type 2** | Carries `valid_from/valid_to/is_current/row_version`; method reclassification is rare but worth tracking. |
| `dim_product` | **SCD Type 2** | Price/markup/category changes must be point-in-time for margin analysis; has SCD2 columns. |
| `dim_store` | **SCD Type 2** | Region/type/name changes matter for trend continuity; has SCD2 columns. |
| `dim_cashier` | **SCD Type 2** | Store reassignment / active-status changes need history; has SCD2 columns. |
| `dim_customer` | **SCD Type 2** | Address/name/status change over time; has SCD2 columns. (county stays `'Not Provided'`.) |
| `dim_invoice` | **SCD Type 2** (on status/total) | OPEN→PARTIAL→PAID transitions are a stated core requirement; has SCD2 columns. |
| `fact_retail_sales` | **Incremental append** by grain (new/changed `silver.invoice_line`); restate on line edits | Lines are effectively immutable once invoiced; append keeps it simple. |
| `fact_payments` | **Incremental append**, then **2nd pass** to resolve `parent_payment_key` | One row per payment; the self-referencing refund/original link needs all rows present first. |
| `fact_customer_behavior_snapshot` | **Periodic snapshot** (insert one row per customer per snapshot date; never update priors) | Snapshot grain by definition; preserves point-in-time behavior metrics. |

### Recommended load order

```
1. dim_date  (generator)
2. dim_payment_type → dim_payment_method → dim_product → dim_store → dim_cashier → dim_customer → dim_invoice
   (seed the -1 Not Provided member in each dimension here)
3. fact_retail_sales
4. fact_payments        (pass 1: insert rows)
5. fact_payments        (pass 2: update parent_payment_key via self-join)
6. fact_customer_behavior_snapshot
```

Dimensions before facts (facts resolve surrogate keys by lookup); `dim_date` first (everything date-keyed depends on it); two-pass for the only self-referencing key (`parent_payment_key`).

---

## 6. Verdict + action list

**Can I populate all three layers and ship Gold to BI without problems, as the repo stands today? — No.** The *design and mappings* are sound and ~complete (one true source gap), but the *pipeline and transforms* are not built/aligned. Once the blockers below are cleared, the answer becomes **yes**.

### Blockers (must fix to populate end-to-end)

1. **Reconcile the extractor with the bronze design.** The pipeline writes `bronze.raw_*`; silver reads `bronze.oltp_*`/`bronze.ref_*`. Decide the canonical bronze names (recommend the documented `oltp_*`/`ref_*`) and make the loader target them **with** the bronze metadata (`bronze_batch_id`, `bronze_source_system`, `bronze_row_hash`, renames, `bronze_raw_payload_jsonb`). A raw `to_sql` passthrough cannot satisfy the bronze `NOT NULL` contract.
2. **Stop `full_load`→`replace` in bronze.** Change the loader so bronze is append-only (full *snapshot append* for static refs), per `bronze_incremental_append_strategy.md`. `if_exists="replace"` destroys history and the typed DDL.
3. **Build the transformation logic that doesn't exist yet:** bronze→silver merge SQL/dbt models, and silver→gold dim/fact loads (per §5). Today only DDL exists; no `.sql`/dbt models populate silver or gold.
4. **Add a `dim_date` generator** (seed or dbt macro) producing a gap-free calendar with `YYYYMMDD` `date_key`; without it gold dates and all `*_date_key`s cannot load.
5. **Seed the `-1` "Not Provided" member** in every dimension so unmatched fact keys (unenforced FKs) don't become BI blank rows.

### High-value fixes (decisions/correctness)

6. **Resolve `dim_customer.customer_county`:** either add a `ZIP → county` reference (true fix) or formally accept `'Not Provided'`. Also correct the misleading "county" claim in the `bronze.oltp_customer_address` table comment.
7. ✅ **DONE — Unified the control/audit table identity** on `audit.etl_batch_control` (+ `audit.audit_log`); dropped the `control` schema; wired batch logging + watermark read into the pipeline.
8. **Define the `fact_payments` refund sign convention** (`parent_payment_key` chain) so payment measures stay additive in BI without double counting.
9. **Document the non-additive snapshot measures** in `fact_customer_behavior_snapshot` (aggregate as last/avg, never SUM across `snapshot_date`).

### Nice-to-haves

10. Confirm the silver→gold **amount precision narrowing** (`NUMERIC(18,2)` → `NUMERIC(12,2)`) is acceptable; widen gold money columns if any amount could approach 10¹⁰.
11. Decide whether to model `product_variant` (color/size) and `fee_type` in gold, or accept the analytical loss; drop their extraction from `ingestion_config.yml` if unused.
12. Rename `gold.dim_date.date` to an event-style, non-keyword name (e.g. `calendar_date`) to satisfy the project's own naming rule and avoid quoting.
13. Disambiguate `dim_product` department resolution (single declared path).

---

### Appendix — what was reviewed

`docs/architecture/` (Final OLTP, Bronze, Silver, Gold schema PDFs) · `docs/naming_conventions/` (Bronze/Silver `.docx`, Gold `.md`) · `docs/source_to_dw_mapping/` (OLTP→bronze, bronze→silver, silver→gold) · `docs/data_dictionary/` (bronze, silver, gold, audit) · `docs/load_strategy/` (bronze append, silver merge) · `sql/bronze|silver|gold|audit/*.sql` · `ingestion/config/ingestion_config.yml` (+ loader/main behavior). No files were modified.

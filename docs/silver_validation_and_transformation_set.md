# Silver Validation & Transformation Set

PrintTimeUSA Data Warehouse | Silver layer. The agreed set of operations every Silver model applies as bronze data becomes clean, conformed, business-ready rows. Decided by Erick Palma (Data Engineer); each operation is grounded in the project's own specs rather than generic practice.

## Summary

Order of operations per Silver model: **cast → clean → prune columns → deduplicate → validate.**

| # | Operation | Discipline | What it does | Home spec |
|---|---|---|---|---|
| 1 | Type casting | Type enforcement | Cast every column to its declared Silver contract type | ADR-005 · silver data dictionary |
| 2 | String cleansing & field normalization | Cleansing | `TRIM` / collapse spaces / `'' → NULL`, plus field-specific normalization for names, addresses, emails, and phone numbers | ADR-005 |
| 3 | Column selection (scoping) | Pruning | Silver keeps **all** business columns; Gold is the selective layer (carries the identifiers people query) | ADR-005 (this doc) |
| 4 | Deduplication | Merge to latest | Collapse bronze's append-only versions to one current row per business key | ADR-006 |
| 5 | Source validity checks | Validation | Verify rows against the source's own rules; flag / quarantine / fail per severity | ADR-012 |
| 6 | Handling unknown & missing data | Defaulting | Missing → `NULL` in Silver, `'Not Provided'` / `-1` in Gold; unrecognized value → keep raw + flag; **no NULLs in Gold** | ADR-011 · ADR-012 |

Deliberately **out of scope:** row filtering. All rows are kept through Silver (soft-deletes and voids flagged, not deleted) so history stays intact; the only rows Silver drops are genuinely bad rows via quarantine (operation 5). See "Why no row filtering" below.

---

## 1. Type casting

Bronze lands data in loose/source types; Silver enforces a clean typed contract so Gold and BI can trust it. The per-column target types are declared in `docs/data_dictionary/silver_data_dictionary.md` (30+ columns), e.g.:

- ids → `cast bigint` (`silver_customer_id`, `silver_invoice_id`, …)
- money → `cast NUMERIC(18,2)` (`silver_total_amount`, `silver_unit_price_amount`, …)
- dates → `cast date` (`silver_invoice_date`, `silver_first_order_date`, …)
- flags → `cast boolean`; counters → `cast smallint`/`integer`

A value that cannot be cast to a *required* key type is a quarantine case (operation 5).

## 2. String cleansing & field normalization

### 2a. Baseline (every text column)

- `TRIM` leading/trailing whitespace
- collapse internal runs of spaces to one
- empty string → `NULL` (so `''` and `NULL` don't read as different values)

This is a **cleansing** step (the row still loads), and it must be deterministic: Silver's change detection hashes the *cleaned* values, so non-deterministic cleaning would make hashes flap and produce phantom updates.

### 2b. Field-specific normalization

On top of the baseline, these field families get canonical-form normalization so equal values become identical strings (which enables consistent display, matching, and deduplication):

| Field family | Columns (silver) | Normalization | Priority |
|---|---|---|---|
| **Person names** | `silver_first_name`, `silver_last_name`, `silver_full_name`, `silver_customer_name` (when person) | trim; collapse spaces; `'' → NULL`; **Title Case** — capitalize each word (`erick palma alvarado` → `Erick Palma Alvarado`) | Must |
| **Business names** | `silver_business_name`, `silver_customer_name` (when business) | trim; collapse spaces; `'' → NULL`; **preserve source case** (protects acronyms) | Must |
| **Email** | `silver_email` | trim; **lowercase**; `'' → NULL` | Must |
| **Phone** | `silver_phone_number` | strip all non-digits; standardize to a **canonical 10-digit form** (optionally E.164 `+1##########`); anything not resolving to 10 digits → flag for review (ADR-012) | Must |
| **Street / city** | `silver_street_address_line_1/2`, `silver_street_address`, `silver_city` | trim; collapse spaces; `'' → NULL`; city optionally title-cased | Trim/collapse Must; title-case Nice |
| **State code** | `silver_state_code` | trim; **UPPER** (also ADR-005 #6) | Must |
| **ZIP** | `silver_zip_code` | trim; keep canonical 5-digit (or ZIP+4); length-check | Must |

**Design notes (worth being able to defend):**

- **Phone and email normalization is what makes matching/dedup possible.** `480-863-7834`, `(480) 863-7834`, and `480.863.7834` are the same phone — normalizing to a canonical form means they hash identically and don't create phantom "changes" or duplicate-looking customers. `John@X.com` and `john@x.com` are the same mailbox — lowercasing prevents case-only duplicates.
- **Person names are Title-Cased for consistency** (`ERICK PALMA` and `erick palma` → `Erick Palma`). Accepted limitations of blanket title-casing: it lowercases internal caps (`McDonald → Mcdonald`), capitalizes name particles (`de la Cruz → De La Cruz`), and its handling of apostrophes/hyphens depends on the implementation. These cases are rare in this customer base, and consistent presentation was chosen over edge-case fidelity — a deliberate business decision, recorded here so it is intentional rather than accidental.
- **Business names keep their source casing** — title-casing corrupts the acronyms common in B2B customers (`PepsiCo → Pepsico`, `AA Autocare → Aa Autocare`, `LLC`, `USA`). The person-vs-business split follows `customer.business_name`: when a business name exists the customer is a business (preserve case), otherwise it is a person (Title Case). A targeted business-name cleanup can be added later if needed, rather than a blanket rule.
- **Full postal address standardization is out of scope.** Expanding `St → Street` / `Ave → Avenue` or CASS-certifying addresses requires an external service (USPS/Melissa); it is not worth building for internal analytics at this scale. Recorded as a future option in the backlog rather than implemented.

## 3. Column selection (scoping)

Column selection happens **progressively**, and the selective layer is **Gold, not Silver**. Silver keeps everything with business meaning; Gold's star schema is where columns are actually chosen, per each dimension/fact's grain.

| Layer | Column policy |
|---|---|
| **Bronze** | Everything — a faithful full copy of the source (ADR-004). |
| **Silver** | Keep **all business columns** — including `po_number`, `reference_no`, `notes`. Drop only bronze *plumbing* with no business use (`bronze_raw_payload_jsonb`, `bronze_source_row_number`, …). |
| **Gold** | Selective per the star schema — but carry the business identifiers people query (e.g. add `po_number` to `dim_invoice` so "payments grouped by PO" works). |

**Why Silver keeps generously.** Nothing is ever truly lost — bronze retains every source column — but Silver is the clean, reusable layer, and dropping a column that's later needed means adding it back and reprocessing. So the bias is to keep any column with analytical, join, or lineage value, and prune only genuinely-useless plumbing. The real, deliberate column selection is a **Gold, per-grain** decision.

> Example: `silver.invoice` keeps `silver_po_number`. A manager's request to "group all POs and their payments" runs as `fact_payments → dim_invoice → GROUP BY po_number` — once `po_number` is carried onto `dim_invoice` in Gold (a column that can be added when Gold is built; it is not in the current Gold schema).

## 4. Deduplication

Bronze is append-only, so the same business row appears once per extracted version. Silver keeps exactly one current row per business key (ADR-006):

- window the new bronze rows with `ROW_NUMBER()` partitioned by the business key, ordered by `updated_at_source_timestamp DESC` (event-time `changed_at` for the two history tables), tie-broken by bronze load time and `bronze_record_id`;
- keep `rn = 1`; upsert on the business key, updating only when `silver_row_hash` changes.

The two `*_status_history` tables are the intentional exception — they keep every transition (history is the record).

## 5. Source validity checks

Verify that data is valid against the **source's own stated rules** (bronze strips OLTP constraints, so Silver re-checks them). Severity is handled by the data-quality tiers in ADR-012 — flag (load + mark), quarantine (reject + count), or fail batch. Representative checks:

- **Required business key** present and castable → quarantine
- **Status vocabulary** — value maps to the closed set (invoice, payment, customer, address type) → flag
- **State code** ∈ {CA, AZ, TX} → flag
- **Quantity/price** — `order_qty > 0`, `unit_price ≥ 0` → flag
- **Financial reconciliation** — `total = subtotal − discount + tax + fee`; `balance_due = total − paid`; `line_total = qty × unit_price − discount` → flag (highest-value checks; they make the revenue numbers trustworthy)

Full check suite and tiering: `docs/adr/012-data-quality-strategy.md`.

## 6. Handling unknown & missing data

Goal: **no NULLs or blank labels in the Gold layer** — every missing or unrecognized value becomes a controlled value so BI tools never render `(Blank)`. The chosen label for missing data is **`'Not Provided'`** (text) / **`-1`** (dimension key).

| Situation | Silver does | Gold does (what BI shows) |
|---|---|---|
| Value missing (`NULL` / empty) | keep as `NULL` (truthful) | text attribute → `'Not Provided'`; dimension key → the `-1` member (labeled `'Not Provided'`) |
| Value provided but not in the vocabulary (bad status/state) | keep the raw value + set the DQ flag (so the actual bad value stays visible) | inherits the value + flag |
| Required key missing / uncastable | quarantine (from the validation step) | — |
| Required attribute missing | load the row, set `is_complete = false` | surfaced via `dq_issue_flag` |

**Why Silver keeps `NULL` but Gold doesn't.** Silver is the *truthful* cleaned record — a `NULL` there means "the source genuinely didn't provide this," which is real information for data-quality analysis. Gold is the *presentation* layer — a `NULL` renders as `(Blank)` in Power BI / Tableau, so Gold replaces every gap with the reserved `'Not Provided'` / `-1` member (ADR-011). Reports get a clean, countable `'Not Provided'` row instead of an unlabeled blank, and fact totals stay correct because unmatched keys resolve to the member rather than dropping.

**Missing vs. invalid are handled differently on purpose.** *Missing* (blank) becomes `'Not Provided'`. *Invalid* (a value was provided but isn't recognized — e.g. an unexpected status) is **not** relabeled; the raw value is kept and flagged, so a genuine data problem stays visible for investigation instead of being silently masked as "provided."

> The label text is a convention, set to `'Not Provided'` consistently across ADR-011, the Gold naming conventions, and the Gold data dictionary. Changing it globally later (e.g. to `'N/A'`) is a one-line change to the default, not a structural one. The technique itself is Kimball's "unknown member" — we simply label the member `'Not Provided'` so it reads cleanly in reports.

---

## Why no row filtering

Filtering rows to "only what we'll use" was considered and rejected: a row that looks useless today is often referenced by history.

- A **soft-deleted customer** dropped from `dim_customer` would orphan every historical invoice they placed → those past sales lose the customer's name and geography.
- A **VOID invoice** is itself a business fact ("how many orders were cancelled, for how much?") — deleting it makes that unanswerable.

So Silver keeps all rows (deleted/void marked via `silver_is_deleted_flag` and status), and filtering to active/relevant happens at **Gold or in the BI query** — a view concern, not a storage concern. The only rows Silver drops are genuinely bad rows, via quarantine.

## Related

- ADR-005 — silver transformation standards (casting, cleansing, vocabularies, derived flags, scoping)
- ADR-006 — silver incremental merge (deduplication)
- ADR-012 (draft) — data quality strategy (the validity checks and their severity tiers)
- `docs/data_dictionary/silver_data_dictionary.md` — per-column cast and cleaning rules

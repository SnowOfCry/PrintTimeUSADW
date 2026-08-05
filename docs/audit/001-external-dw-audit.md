# PrintTimeUSA Data Warehouse — External Audit Report (Round 1)

**Auditor role:** Independent Senior/Principal Data Engineer & DW Architect (external reviewer)
**Date:** 2026-07-28
**Scope:** Entire repository at commit `2b9433c` (v0.2.0-gold release)
**Superseded by:** [002](002-external-dw-audit.md) at commit `15c1c52` — kept as the point-in-time record
**Method:** `.claude/skills/dw-auditor/SKILL.md` — 20-phase evidence-based audit
**Standard applied:** "Would an experienced Senior or Principal Data Engineer confidently approve this architecture for production?"

---

## 1. Executive Summary

This is one of the best-documented and most deliberately designed small data warehouse
projects I have reviewed. The medallion architecture is genuinely ELT (ADR-003 is
enforced in code, not just claimed), the silver layer is disciplined and well-tested
(52 dbt data tests), lineage columns are first-class at every layer, and the ADR
discipline — 15 decision records with real alternatives and accepted costs — exceeds
what most enterprise teams produce.

However, the platform is **not production-ready**, and the gap is operational, not
architectural. The five findings that matter most:

1. **The Airflow DAG cannot execute end-to-end as written.** dbt is not installed in
   the Airflow image and the dbt environment variables are not forwarded to the
   Airflow containers. The "orchestrated pipeline" the README describes runs only by
   hand. (HIGH-1)
2. **Gold batch control was designed but never wired.** No process writes gold rows to
   `audit.etl_batch_control`, so both facts' incremental filters silently fall back to
   1900-01-01 and reload everything, every run — and gold rows carry `etl_batch_id =
   NULL`, breaking the documented lineage contract. (HIGH-2)
3. **SCD2 effective dating uses the load date, not the business date, and facts always
   resolve `is_current`.** Point-in-time ("as-was") reporting — the entire reason
   SCD2 was chosen — is not actually achievable, and fact reloads silently re-point
   history at today's dimension versions. (HIGH-3)
4. **There is no disaster recovery at all.** One Docker volume, no backup schedule, no
   restore procedure, no tested recovery. Score: 0. The warehouse database also hosts
   the Airflow metadata DB and SonarQube's store, so any restore entangles three
   systems. (HIGH-5)
5. **The access model exists only on paper.** ADR-013 defines roles and gold-read-only
   grants; no `CREATE ROLE`/`GRANT` exists anywhere in the SQL. Every service —
   ingestion, dbt, Airflow, SonarQube, pgAdmin — shares one all-privilege user.
   (HIGH-6)

**Overall score: 2.8 / 5. Classification: DEVELOPMENT READY** — the layers build and
produce correct-looking data when driven manually, but orchestration, recovery,
security, and observability must be completed before any production designation.

---

## 2. Architecture Assessment

**The architecture is appropriate and should not change.** PostgreSQL 16 + Python
extraction + dbt + Airflow on Docker Compose is the right stack for a single-source,
single-engineer, daily-cadence retail warehouse in the tens-of-thousands-of-invoices
range (max observed invoice total ≈ $196k; `invoice_line` ≈ 390k rows). No distributed
technology is justified at this volume, and ADR-002/ADR-003 document that reasoning
correctly. This audit found **no architectural anti-patterns in the layer design**:

- Bronze is append-only with full raw payload (`bronze_raw_payload_jsonb`), row hash,
  batch stamping, and delete-flag capture — reprocessing history is genuinely possible.
- Silver is dbt-owned incremental merge with dedup-latest-per-key, hash-gated updates,
  contracts, and a closed status vocabulary (ADR-005/006).
- Gold is a coherent Kimball star: 8 dimensions (SCD2 where justified, Type 1/0 where
  not), 3 facts with distinct explicit grains, role-playing date views, `-1` unknown
  members, and no source business keys on facts (ADR-009/010/011).
- The Python/SQL responsibility split is real: `ingestion/` performs zero business
  transformation.

The discrepancies are between **design and wiring** (findings below), not in the
design itself.

---

## 3. Scorecard

| # | Category | Score | Justification (evidence-based) |
|---|---|---|---|
| 1 | Architecture | **4** | Right-sized stack, strict layering, ADR-backed. Held back by design/wiring gaps (gold batch control, DAG). |
| 2 | Data Modeling | **3** | Grains explicit everywhere; strong Kimball hygiene. SCD2 effective-dating flaw (HIGH-3) undermines the stated purpose of Type 2. |
| 3 | Data Quality | **3** | 52 silver + ~85 gold test declarations; vocabularies and FKs covered. No SCD2 integrity tests, no fact-grain uniqueness test, no reconciliation checks. |
| 4 | Incremental Processing | **2** | Bronze watermarking works but has missed-row and duplicate-on-retry windows; gold "incremental" is a silent full reload (HIGH-2). |
| 5 | Data Governance | **3** | ADR-013 is a real governance decision; PII tags exist in the gold dictionary. Access model and erasure logging unimplemented. |
| 6 | Data Lineage | **4** | Row-level lineage columns at every layer; every hop has a mapping doc. Gold `etl_batch_id` is NULL, breaking the last link. |
| 7 | dbt | **4** | Clean project, sensible materializations, contracts, source freshness SLA, good macro use. No packages (no dbt_utils), no exposures, docs site not generated. |
| 8 | Airflow | **1** | The DAG cannot run: dbt absent from the image, env vars mismatched, one monolithic ingestion task, placeholder task referencing a dropped table. |
| 9 | Python | **3** | Typed, logged, structured, chunked loads. F-string SQL construction, no retries/timeouts, whole-table pandas extraction. |
| 10 | PostgreSQL | **3** | Typed DDL, PK/unique constraints, index scripts, identity keys. dbt `--full-refresh` would drop DDL-created indexes; no vacuum/analyze strategy stated. |
| 11 | Scalability | **3** | Fine at current and 10x volume. Pandas extraction and full-reload facts are the first walls at ~100x. |
| 12 | Performance | **3** | Adequate today; no measured baselines; hash-gated merges keep silver cheap. |
| 13 | Security | **2** | `.env` hygiene is good (never committed, verified in history). But: one shared all-privilege DB user, no roles/grants, default-able webserver secret, three systems in one DB. |
| 14 | Docker / Infrastructure | **3** | Healthchecks, restart policies, pinned images, init-baked schema. No resource limits; SonarQube co-tenant on the warehouse DB; single-host by design (accepted, ADR-002). |
| 15 | CI/CD | **2** | Ruff + mypy + pytest + compose-validate is a real start. CI never compiles dbt, never parses the DAG, never lints SQL — a broken model or DAG merges green. |
| 16 | Observability | **2** | Batch rows with counts/status/error for bronze only. No alerting (email_on_failure=False), no gold/silver batch records, no reconciliation, `rows_updated/deleted/rejected` never populated. |
| 17 | Reliability | **2** | Silver merge is idempotent; bronze retry can duplicate (absorbed downstream); one-task ingestion has no failure isolation; recovery procedures undocumented (backlog #8 acknowledges). |
| 18 | Disaster Recovery | **0** | No backups, no restore procedure, no RPO/RTO, nothing tested. Single Docker volume holds the warehouse + Airflow metadata + SonarQube. |
| 19 | Documentation | **5** | Exceptional. 15 ADRs, 4 data dictionaries, 3 mapping docs, load strategies per layer, naming conventions, a self-critical readiness review, and a maintained backlog. |
| 20 | Maintainability | **4** | Spec-first culture, consistent naming, self-documenting models, honest backlog. Single-person bus factor is the main risk. |

**Average: 2.80 / 5.** Per the framework, the DR score of 0 and Airflow score of 1
cap the classification regardless of the strong documentation and modeling scores.

---

## 4. Critical & High Findings

No CRITICAL findings (no evidence of active data corruption, loss, or breach — the
platform's honest mitigations, especially silver's dedup-latest and append-only
bronze, absorb most failure modes). Six HIGH findings follow.

---

### HIGH-1 — The orchestrated pipeline cannot execute

```text
ID:            HIGH-1
Category:      Airflow / Orchestration
Severity:      HIGH
Location:      airflow/dags/printtime_elt_pipeline.py:119-146,
               docker/airflow/requirements.txt, docker-compose.yml:12-32
Finding:       The DAG's dbt tasks (run_dbt_silver, run_dbt_gold, run_dbt_tests) run
               `dbt` via BashOperator inside the Airflow containers, but dbt is not
               installed in the Airflow image (requirements.txt contains providers,
               pandas, psycopg2 — no dbt-core/dbt-postgres), and the Airflow
               environment forwards DW_*/OLTP_* variables but not the DBT_USER /
               DBT_PASSWORD that profiles.yml requires (they have no defaults).
Evidence:      requirements.txt has no dbt package; docker-compose x-airflow-common
               env block lacks DBT_*; profiles.yml uses env_var('DBT_USER') with no
               fallback; the DAG's own comment admits "dbt must be installed there,
               OR swap for DockerOperator". Additionally, update_control_logs is a
               placeholder print() referencing control.elt_batch_log — a table in a
               schema that ADR-008 dropped.
Why It Matters: The platform's central claim — a daily, automated Extract → Bronze →
               Silver → Gold → Test pipeline — is not currently true. Every dbt build
               so far has been run manually in the dbt container.
Business Impact: No automated daily refresh; data freshness depends entirely on one
               person remembering to run commands. The freshness SLA defined in
               _bronze_sources.yml (warn 24h / error 48h) will fire on any missed day.
Technical Impact: First scheduled run fails at run_dbt_silver with "dbt: command not
               found". Retry logic, test gating, and the control-log finalization
               task are all dead code paths.
Recommendation: Pick one of the two options the DAG comment names and finish it:
               (a) add dbt-core + dbt-postgres to docker/airflow/requirements.txt and
               forward DBT_* env vars in x-airflow-common, or (b) use
               DockerOperator to run the existing dbt container. Delete or implement
               update_control_logs (its docstring references a dropped table).
               Add `python -c "import airflow; DagBag()"`-style DAG import validation
               to CI so a broken DAG cannot merge (see HIGH-7/CI).
Priority:      P1 — before any production designation
Effort:        0.5–1 day
```

### HIGH-2 — Gold batch control designed but never wired; facts silently full-reload

```text
ID:            HIGH-2
Category:      Incremental Processing / Observability
Severity:      HIGH
Location:      dbt/printtime_dw/models/gold/fact_retail_sales.sql:50-68,
               fact_payments.sql (same pattern); all gold models' etl_batch_id
Finding:       Both incremental facts filter on the last succeeded
               'gold.fact_retail_sales' / 'gold.fact_payments' batch in
               audit.etl_batch_control — but nothing anywhere (dbt hooks, DAG,
               Python) ever inserts gold batch rows. The subquery always coalesces
               to 1900-01-01, so every "incremental" run reloads every invoice/
               payment. Every gold model also stamps etl_batch_id as NULL.
Evidence:      Grep across the repo: the only writers of audit.etl_batch_control are
               ingestion/utils/batch_control.py (bronze loads only). Gold models
               contain `null::varchar(50) as etl_batch_id` (e.g. dim_customer.sql:139,
               fact_retail_sales.sql:135). The gold naming convention doc §116
               documents etl_batch_id as "joins audit.etl_batch_control.batch_id".
Why It Matters: The incremental design is non-functional (correct results, disguised
               full reload), and the documented gold lineage contract — "which batch
               produced this row" — is false for the entire gold layer.
Business Impact: None today (results are correct). At scale, gold rebuild time grows
               linearly with history. Audit/lineage claims in ADR-013 §5 are
               overstated for gold.
Technical Impact: delete+insert re-deletes and re-inserts all ~390k fact rows per
               run; surrogate fact keys churn upward monotonically
               (max(sales_line_key)+row_number), inflating the integer keyspace.
Recommendation: Add a dbt on-run-start/on-run-end hook pair (or a macro called per
               model) that inserts and finalizes a batch row in
               audit.etl_batch_control for each gold model run, and stamp
               etl_batch_id from that batch via var/invocation_id. Until then,
               change the facts' filter comment to say "full reload" so the code
               stops claiming an incrementality it doesn't have.
Priority:      P1
Effort:        1 day
```

### HIGH-3 — SCD2 effective dates use load date; facts always resolve is_current

```text
ID:            HIGH-3
Category:      Data Modeling
Severity:      HIGH
Location:      dbt/printtime_dw/models/gold/dim_customer.sql:142-143 (valid_from =
               current_date), post_hook (valid_to = current_date); same ADR-015
               pattern in all 6 SCD2 dims; fact_retail_sales.sql:94-98 (joins on
               is_current)
Finding:       This is incorrect for the stated purpose. SCD2 versions are dated by
               warehouse load date (current_date at run time), not by the business
               effective date from the source (e.g. silver_source_updated_at).
               Facts resolve dimension keys against is_current at load time. Two
               consequences: (1) any change that happened between loads is dated the
               day the pipeline ran, and multiple same-day changes produce
               overlapping/zero-day versions; (2) because fact_retail_sales reloads
               whole invoices (delete+insert), a reloaded historical sale is
               re-pointed to TODAY's customer/store/product version — historical
               attribution ("as-was" reporting) is silently rewritten.
Evidence:      valid_from/valid_to are current_date in every SCD2 dim; there is no
               join on valid_from <= invoice_date < valid_to anywhere; the fact
               reload unit is the invoice (model header, decision #3), so any line
               edit re-resolves all of that invoice's dimension keys against
               is_current.
Why It Matters: Point-in-time correctness is the only reason to pay SCD2's
               complexity (ADR-007 chose Type 2 explicitly because "address/status
               changes are why this dim is Type 2"). As built, the warehouse cannot
               answer "what was this customer's address when they bought this?" —
               it answers "what is it now?", which Type 1 would give for free.
Business Impact: Sales-by-region trend analysis, margin-at-time-of-sale, and any
               as-was report will drift as dimensions change and facts reload.
               Financial restatement risk is real but silent.
Technical Impact: History in the dims is retained but unreachable from the facts;
               the versioning cost (post_hooks, row_version, hashes) buys nothing.
Recommendation: Two changes: (1) date SCD2 versions from the business change
               timestamp (silver_source_updated_at_timestamp::date), falling back
               to load date only when the source timestamp is null; (2) resolve
               fact dimension keys by effective-date range (valid_from <=
               invoice_date < coalesce(valid_to, '9999-12-31')) instead of
               is_current — at minimum for fact_retail_sales' reload path.
               Alternatively, if the business genuinely only needs current-state
               reporting, downgrade the dims to Type 1 and delete the SCD2
               machinery — either position is defensible; the current hybrid is not.
Priority:      P1 — the longer this runs, the more history is mis-dated
Effort:        2–3 days including backfill reasoning
```

### HIGH-4 — Ingestion is one monolithic task with no failure isolation

```text
ID:            HIGH-4
Category:      Airflow / Reliability
Severity:      HIGH
Location:      airflow/dags/printtime_elt_pipeline.py:53-74
Finding:       All ~20 tables extract and load serially inside a single
               PythonOperator. A failure on table 7 aborts tables 8–20 for the day;
               retry re-runs all 20; there is no per-table visibility, retry, or
               parallelism, and no alerting (email_on_failure=False, no callbacks,
               no SLA).
Evidence:      _ingest_oltp_to_bronze loops config tables calling ingestion.main.run
               sequentially; DEFAULT_ARGS disables email; no on_failure_callback.
Why It Matters: One flaky table (or one OLTP lock) takes down the whole day's
               ingestion silently. The batch-control table records the failure, but
               nobody is notified and nothing downstream is isolated.
Business Impact: Silent data staleness; freshness SLA violations discovered by
               consumers rather than operators.
Technical Impact: Retrying the task re-extracts tables that already succeeded
               (cheap, watermarks advance) but re-appends any partially-loaded
               failed table's rows (see MED-3).
Recommendation: Use dynamic task mapping (Airflow 2.9 supports .expand over the
               config table list) to make one task per table, keep per-table
               retries, and add an on_failure_callback (email or webhook). This is
               a small change with outsized reliability gains.
Priority:      P1
Effort:        0.5 day
```

### HIGH-5 — No disaster recovery: no backups, no restore, no RPO/RTO

```text
ID:            HIGH-5
Category:      Disaster Recovery
Severity:      HIGH
Location:      Repository-wide (absence); docker-compose.yml volumes; backlog #8
Finding:       There is no backup of any kind: no pg_dump schedule, no WAL
               archiving, no volume snapshot procedure, no restore documentation,
               no RPO/RTO statement, and nothing ever restore-tested. The single
               postgres_data volume holds the warehouse AND the Airflow metadata DB
               AND SonarQube's store (all three point at ${POSTGRES_DB}).
Evidence:      No backup script under scripts/; no cron/DAG performing dumps;
               backlog #8 ("backup schedule... before production go-live")
               acknowledges the gap. .env.example: AIRFLOW_DB_NAME=printtime_dw.
               docker-compose.yml:169: SONAR_JDBC_URL targets the same DB.
Why It Matters: A disk failure or accidental volume removal (scripts/reset.sh
               exists) is unrecoverable except by full re-extraction from OLTP —
               which recovers current state but NOT bronze's accumulated history,
               the entire point of the append-only design (ADR-004). Bronze history
               is the one dataset this platform cannot recreate, and it is the one
               dataset with zero protection.
Business Impact: Irrecoverable loss of historical change data; SCD2 history in gold
               could not be rebuilt as-was.
Technical Impact: RPO = infinity, RTO = undefined.
Recommendation: Minimum viable DR this week: nightly pg_dump of the warehouse
               schemas to a location off the docker volume (host path or cloud
               bucket), 14-day retention, plus a documented and once-executed
               restore drill. Separate the Airflow metadata into its own database
               (one line in .env) so warehouse restores don't entangle scheduler
               state. Record RPO (24h) and RTO in the runbook (backlog #8).
Priority:      P1 — highest-consequence gap in the platform
Effort:        0.5 day for dump+retention; 0.5 day for the restore drill + doc
```

### HIGH-6 — Access model unimplemented: one all-privilege user for everything

```text
ID:            HIGH-6
Category:      Security / Governance
Severity:      HIGH
Location:      All sql/ DDL (absence of roles/grants); .env.example; docker-compose.yml
Finding:       ADR-013 §3 defines a least-privilege model (BI = gold read-only;
               bronze/silver restricted; service accounts per task). None of it
               exists: grep finds zero CREATE ROLE / GRANT / REVOKE statements in
               the repository. Ingestion, dbt, Airflow's metadata DB, SonarQube,
               and pgAdmin all authenticate as the single ${POSTGRES_USER} owner.
Evidence:      Grep for 'CREATE ROLE|GRANT|REVOKE' across *.sql: no matches.
               docker-compose.yml passes POSTGRES_USER to dbt (DBT_USER), Airflow
               (both metadata conn and DW_USER), and SonarQube (SONAR_JDBC_USERNAME).
Why It Matters: The PII-minimization argument in ADR-013 ("BI users never see raw
               contact PII — minimization is structural") depends on grants that do
               not exist. Any connected tool or user can read silver.customer email
               and phone. SonarQube — a third-party Java application — holds
               warehouse-owner credentials.
Business Impact: CCPA posture is weaker than documented; a compromise of any one
               service compromises all layers including PII.
Technical Impact: No blast-radius containment; accidental cross-schema writes
               possible from any client.
Recommendation: Implement ADR-013 §3 as sql/security/001_create_roles.sql: an
               ingestion role (bronze+audit write), a dbt role (read bronze, own
               silver/gold), a bi_reader role (gold SELECT only), and separate
               databases (not just users) for Airflow metadata and SonarQube.
               Bake into the postgres init image (remember: image rebuild required,
               not just a volume wipe).
Priority:      P1 for the role split; P2 for DB separation
Effort:        1 day
```

---

## 5. Detailed Findings (MEDIUM / LOW / INFORMATIONAL)

### MED-1 — Extractor builds SQL by f-string interpolation

- **Location:** `ingestion/extract/oltp_extractor.py:114-131`
- **Finding:** Table name, watermark column, and watermark **value** are interpolated
  directly into SQL (`WHERE {watermark_column} > '{last_value}'`). Inputs come from
  version-controlled config, so injection risk is low today, but the watermark value
  round-trips through `str()` (pandas Timestamp → string → SQL literal), which is
  fragile against timezone/precision changes, and any future config source (UI, API)
  inherits an injection surface.
- **Recommendation:** Parameterize the value (`WHERE {col} > %(wm)s` via
  SQLAlchemy `text()` bind params) and validate table/column names against an
  allowlist from `information_schema`. **Effort:** 2h.
- **✅ RESOLVED (2026-08-05):** the watermark value is now a **bound parameter**
  (`WHERE {col} > :watermark` via SQLAlchemy `text()`), so the driver sends its real
  type — no `str()` round-trip and no value-injection surface. Table/column identifiers
  (which can't be bound) are validated against a safe-identifier pattern
  (`[A-Za-z_][A-Za-z0-9_]*`); the true allowlist is already enforced upstream by
  `ingestion/main.py` against `ingestion_config.yml`. Unit tests cover both the binding
  and injection rejection. See `docs/fix/fix_log.md` FIX-009.

### MED-2 — Watermark semantics can permanently miss rows

- **Location:** `oltp_extractor.py` (strict `>`), `main.py:127-129` (max of extracted
  values as next watermark)
- **Finding:** Classic watermark race: a source row committed *after* extraction with
  an `updated_at` earlier than the captured max (in-flight transaction at extract
  time) is never picked up. Strict `>` plus string-serialized timestamps also risks
  boundary rows on precision truncation. Hard deletes on incremental tables are never
  captured (only source soft-delete flags flow through; full-load tables re-snapshot).
- **Recommendation:** Overlap the window (extract `>= watermark - interval '1 hour'`
  — bronze appends + silver dedup make re-extraction free and safe, which is a
  strength of this design), or watermark on an OLTP sequence/txid. Document the
  hard-delete gap explicitly in the bronze strategy doc. **Effort:** half day.
- **✅ RESOLVED (2026-08-05):** the extractor now filters `> (watermark −
  WATERMARK_LOOKBACK)` (default 1h) to re-scan late-committing rows; free here
  (bronze appends + silver dedups + full-load hash-skip). The hard-delete gap is
  now explicitly documented in the bronze strategy doc. See FIX-010.

### MED-3 — Partial batch failure leaves orphan rows; retry duplicates them

- **Location:** `ingestion/load/bronze_loader.py:181-196`
- **Finding:** Chunked `to_sql` commits every 20k-row chunk independently. A failure
  mid-load leaves a batch marked `failed` with some rows landed; the retry re-extracts
  the same window and appends everything again. Silver's dedup-latest absorbs this
  (correctness preserved — this is why it's MEDIUM, not HIGH), but bronze accumulates
  unflagged duplicates and `rows_extracted`/`rows_inserted` reconciliation is silently
  wrong for the failed batch.
- **Recommendation:** Either wrap the whole table load in one transaction
  (`engine.begin()` passed to `to_sql`), or on retry delete rows of the prior failed
  `bronze_batch_id` first. **Effort:** 2h.
- **✅ RESOLVED (2026-08-05):** the whole table load now runs in one transaction
  (`engine.begin()`), so a mid-load failure rolls back all chunks — no orphans,
  no retry duplication, bronze stays append-only. Proven by injecting a chunk-2
  failure (chunk 1 rolled back too). See FIX-010.

### MED-4 — `audit.audit_log` is defined, documented, and never written

- **Location:** `sql/audit/002_create_audit_tables.sql:53-73`; ADR-013 §4
- **Finding:** The row-level audit trail exists only as DDL. Nothing populates it —
  yet ADR-013 makes it the evidence store for CCPA erasures ("the action is logged in
  audit.audit_log"). A compliance procedure whose logging target has no writer is not
  implemented.
- **Recommendation:** Either write the erasure-logging procedure now (a documented
  SQL script/function that deletes + logs in one transaction) or mark ADR-013 §4 as
  not-yet-implemented in the backlog. **Effort:** half day.

### MED-5 — No SCD2 integrity tests

- **Location:** `dbt/printtime_dw/models/gold/_gold_models.yml`
- **Finding:** Gold tests cover surrogate-key uniqueness, not-nulls, relationships,
  and accepted values — good — but nothing tests the SCD2 invariants: exactly one
  `is_current` row per `source_record_id`, no overlapping `valid_from/valid_to`
  ranges, `row_version` monotonicity. These are precisely the invariants the
  append + post_hook pattern can violate on a mid-run failure (insert succeeded,
  post_hook didn't → two current rows → the next run's `is_current` join fans out and
  inserts duplicate versions).
- **Recommendation:** Add dbt_utils (there is no packages.yml at all) and use
  `dbt_utils.unique_combination_of_columns` on `(source_record_id)` filtered
  `where is_current`, plus a singular test for range overlaps. **Effort:** half day.
- **✅ RESOLVED (2026-08-05):** all three SCD2 invariants are now singular tests
  that gate the watermark (HIGH-7): `assert_scd2_one_current_version_per_entity`,
  `assert_scd2_no_overlapping_versions`, and `assert_scd2_row_version_contiguous`
  (all six SCD2 dims), plus a bonus `assert_fact_payments_refunds_are_negative`.
  Implemented as singular tests rather than adding dbt_utils/packages.yml (the gap
  was the missing tests, not the tool; dbt_packages is gitignored so a dependency
  would need `dbt deps` wired into the DAG + both images + CI). Each proven to
  catch a seeded violation. See `docs/fix/fix_log.md` FIX-011.

### MED-6 — CI cannot catch a broken dbt model or DAG

- **Location:** `.github/workflows/ci.yml`
- **Finding:** CI lints/type-checks/tests Python only. `dbt parse`/`dbt compile` is
  never run (a model or contract syntax error merges green), DAG files are never
  imported, and there is no SQL linter. The stated purpose of the pipeline —
  SQL-based transformation — has zero CI coverage. Unit tests: 3, all on SQL string
  builders (backlog #9 acknowledges).
- **Recommendation:** Add jobs: `dbt parse` (needs no DB), `dbt compile` against an
  ephemeral Postgres service container, a DagBag import test, and sqlfluff with the
  dbt templater. **Effort:** 1 day.

### MED-7 — Bronze grows without bound; full-load snapshot stacking

- **Location:** `ingestion_config.yml` (11 full-load tables), backlog #1, #2
- **Finding:** Known and consciously deferred (which is the right process), but worth
  elevating: 11 tables re-append complete snapshots daily even when unchanged, and no
  retention/archival policy exists. Combined with HIGH-5 (no backups), the
  monotonically growing, irreplaceable layer is also the unprotected one.
- **Recommendation:** Implement backlog #1's hash-skip (loader already computes
  `bronze_row_hash`; skip rows whose hash matches the latest bronze row per key).
  **Effort:** ~1h (backlog's own estimate).
- **✅ RESOLVED (2026-08-05):** full-load loads now hash-skip rows whose
  `bronze_row_hash` matches the latest snapshot (the hash covers the natural key,
  so unchanged rows hash identically). Proven: re-loading an unchanged table
  appended 0 rows. Incremental tables are intentionally not hash-skipped. See
  FIX-010.

### MED-8 — Airflow webserver secret has a committed default; Fernet key optional

- **Location:** `docker-compose.yml:16-17`
- **Finding:** `AIRFLOW__WEBSERVER__SECRET_KEY: ${AIRFLOW_SECRET_KEY:-changeme_in_env}`
  falls back to a known literal; `AIRFLOW__CORE__FERNET_KEY: ${AIRFLOW_FERNET_KEY:-}`
  falls back to empty (connections stored unencrypted). Local-only today (ADR-002),
  but defaults that work are defaults that ship.
- **Recommendation:** Remove both fallbacks so compose fails loudly when unset.
  **Effort:** minutes.
- **✅ RESOLVED (2026-08-05):** both converted to the fail-closed `${VAR:?message}`
  form — compose now aborts if `AIRFLOW_FERNET_KEY` / `AIRFLOW_SECRET_KEY` are
  unset instead of using the committed/empty default. Verified: config fails loudly
  when the secret is absent. See `docs/fix/fix_log.md` FIX-013.

### MED-9 — dbt `--full-refresh` silently drops DDL-managed indexes and constraints

- **Location:** `sql/{silver,gold}/002-003` vs dbt table/incremental materializations
- **Finding:** Silver/gold physical tables were created by hand-written DDL (typed
  columns, PKs, indexes in the `003_*` scripts). dbt incremental models reuse the
  existing tables — but any `--full-refresh` (or `on_schema_change` evolution) drops
  and recreates the table from the SELECT, losing every index and constraint the DDL
  created, with no error and no process to restore them.
- **Recommendation:** Move index/constraint creation into dbt post-hooks (or model
  contracts + config-defined indexes) so they survive rebuilds; treat `sql/` DDL as
  bootstrap-only and say so in the README. **Effort:** 1 day.

### LOW findings (abbreviated)

- **LOW-1:** `README.md.bak` is git-tracked; compiled `.pyc` files and Airflow
  scheduler logs sit in the working tree. Housekeeping.
- **LOW-2:** `dim_date` ends 2030-12-31 (`dim_date.sql:19`). Invoices dated beyond it
  will key to `-1` with no warning. Add a max-date test or extend generation.
- **LOW-3:** Surrogate keys via `max(key)+row_number()` as `integer` — safe
  single-threaded, but int32 headroom and concurrency fragility deserve a comment;
  fact keys churn fast under the current full-reload behavior (see HIGH-2).
- **LOW-4:** `oltp_extractor.py` docstring still says "Placeholder class" — it isn't;
  stale docs mislead reviewers.
- **LOW-5:** PII tags exist only in the gold data dictionary (12 mentions) — the
  bronze/silver dictionaries, where the PII actually lives, are untagged. ADR-013 §1
  says "tag every personal-data column in the data dictionaries."
- **LOW-6:** No dbt exposures and no generated docs site; lineage is file-and-doc
  based rather than queryable. Fine at this scale; `dbt docs generate` is nearly free.
- **LOW-7:** `pandas.read_sql` loads whole tables into memory (the 390k-row lesson is
  chunked on the *load* side only). Add `chunksize=` to extraction before the next
  order of magnitude.

### INFORMATIONAL

- **INFO-1:** The repo's own `docs/dw_readiness_review.md` (June) and `docs/backlog.md`
  are models of engineering honesty; all five June blockers verifiably closed. This
  audit's HIGH-2/HIGH-3 are the two significant issues that review did not anticipate.
- **INFO-2:** Naming: the `etl_*` prefixes contradict the ELT identity (separate
  discussion already underway; `dw_*` recommended for gold audit columns).
- **INFO-3:** SonarQube in the local stack is heavyweight for a one-person project
  and shares the warehouse DB; consider dropping it or isolating it. Not wrong,
  just unjustified complexity per the no-overengineering rule.

---

## 6. Data Model Assessment

**Strengths.** Every fact declares its grain in the model header and the grains are
correct and distinct (invoice line / payment / customer×snapshot-date). Dimensions
have proper surrogate keys separated from natural keys, `-1` unknown members are
seeded in-model (idempotently, first-build only), the degenerate `invoice_number` is
handled correctly, role-playing dates use views rather than DAX gymnastics, and SCD
type choices were *reasoned per table* (Type 0 calendar, Type 1 static lookup, Type 2
where change history matters) rather than cargo-culted — exactly what the audit
standard asks for.

**Weaknesses.** The SCD2 implementation undermines its own purpose (HIGH-3): load-date
effective dating plus is-current fact resolution means the retained history is
unreachable. The refund sign convention (negative amounts, `SUM` nets automatically)
is well-documented but nothing *tests* that refunds are negative — one positive refund
silently overstates revenue; add an expression test. `product_variant` (color) and
`fee_type` still vanish between silver and gold (known analytical loss, readiness
review §1c).

## 7. Pipeline Assessment

Ingestion code quality is good (typed, structured, logged, chunked writes, engine
reuse) and honestly scoped. The batch-control lifecycle (running → succeeded/failed
with counts and watermark window) is the right skeleton. But the pipeline as an
*operated system* fails the audit questions: a halfway failure leaves orphan bronze
rows (MED-3); the same batch run twice duplicates (absorbed downstream); a record
arriving late is dated wrong in SCD2 (HIGH-3); a deleted incremental-table record is
never noticed (MED-2); seven days of downtime recovers cleanly via watermarks (a
genuine pass); and the orchestrator that should own re-runs cannot currently run at
all (HIGH-1).

## 8. Data Quality Assessment

Silver testing is strong and well-prioritized: business-key uniqueness and not-null
on all 20 models, the 11 status vocabularies pinned by accepted_values, FK
relationships including the orphan-line check, and a source freshness SLA with a
sensible ref-table exemption. Gold testing covers keys and relationships. The gaps
are the *invariants machines don't see*: SCD2 single-current (MED-5), fact grain
uniqueness on the business key (`source_record_id`), refund-sign, and any
source-to-warehouse row-count reconciliation. The `rows_updated/deleted/rejected`
columns in batch control have never been populated — measurement was designed and
not wired, a recurring theme (HIGH-2, MED-4).

## 9. Governance Assessment

Documentation-side governance is excellent (ownership named in every ADR, definitions
and grain per dataset, PII classification decided, deletion procedure decided).
Enforcement-side governance is largely absent: no roles/grants (HIGH-6), no erasure
implementation (MED-4), PII tags missing from the dictionaries that hold PII (LOW-5).
The pattern: decisions are made and recorded to an enterprise standard; controls are
not yet built. Say so explicitly in the docs to keep them honest.

## 10. Security Assessment

Verified clean: no secrets in git history (checked), `.env` properly ignored,
credentials env-var-driven throughout, services bound to localhost ports on an
isolated bridge network, images pinned. Open: single shared all-privilege DB user
across five services (HIGH-6), default-able webserver secret and empty-able Fernet
key (MED-8), SonarQube holding warehouse-owner credentials, pgAdmin exposed with
basic auth (acceptable on-prem), and f-string SQL (MED-1). For an internet-exposed
deployment this section would be CRITICAL; for the documented on-prem posture
(ADR-002) it is HIGH.

## 11. Scalability Assessment

- **Current (≈60k invoices, 390k lines):** comfortable. No action.
- **10x:** pandas whole-table extraction (LOW-7) and the facts' silent full reload
  (HIGH-2) become the first felt pain; both are fixable within the stack.
- **100x:** bronze's daily full-snapshot stacking (MED-7) dominates storage; hash-skip
  and retention become mandatory; Postgres itself remains fine with partitioning on
  bronze/fact tables.
- **1000x:** single-node Postgres on Docker Compose stops being the right answer;
  ADR-002's own revisit triggers cover this. **No distributed technology is
  recommended at any horizon currently in evidence.**

## 12. Reliability Assessment

The design has real resilience properties — append-only bronze plus dedup-latest
silver means most retry/duplicate scenarios converge to correct state, which few
projects at this maturity can say. But reliability as practiced depends on one person
manually running an unalerted pipeline with no backups. The honest summary: the
*data* is resilient; the *operation* is fragile.

---

## 13. Production Readiness

```text
Classification: DEVELOPMENT READY
```

The scale is: NOT READY → EARLY DEVELOPMENT → **DEVELOPMENT READY** → PRE-PRODUCTION
→ PRODUCTION READY → ENTERPRISE READY.

**Reasoning.** All three layers exist, build, and produce a coherent, tested star
schema — this is well past EARLY DEVELOPMENT. It cannot be PRE-PRODUCTION while the
orchestrator cannot execute the pipeline (HIGH-1), there is no backup of an
irreplaceable dataset (HIGH-5), and historical reporting silently drifts (HIGH-3).
Per the scoring framework, the DR category at 0 caps the classification regardless
of the 5s elsewhere. A Senior/Principal Data Engineer would not approve this for
production today — and would also recognize it as perhaps two focused weeks away
from PRE-PRODUCTION, which is unusually close for a project of this scope.

---

## 14. Remediation Roadmap

### Phase 1 — Critical Fixes (this week)
1. Nightly `pg_dump` + retention + one executed restore drill; separate the Airflow
   metadata database (HIGH-5). **1 day.**
2. Make the DAG executable: dbt in the Airflow image (or DockerOperator), DBT_* env
   forwarding, delete/implement `update_control_logs` (HIGH-1). **1 day.**
3. Split the ingestion task per table + failure alerting (HIGH-4). **0.5 day.**

### Phase 2 — Production Readiness (before go-live)
4. Wire gold batch logging into `audit.etl_batch_control` and stamp `etl_batch_id`
   (HIGH-2). **1 day.**
5. Fix SCD2 effective dating to business timestamps and effective-date fact key
   resolution — or consciously downgrade to Type 1 and record the ADR (HIGH-3).
   **2–3 days.**
6. Implement roles/grants per ADR-013 §3 (HIGH-6). **1 day.**
7. CI: `dbt parse`/`compile`, DagBag import test, sqlfluff (MED-6). **1 day.**
8. Transactional (or self-cleaning) bronze loads (MED-3); parameterized extraction
   SQL (MED-1). **0.5 day.**
9. Runbook: deploy order, backfill procedure, restore procedure, freshness SLA
   ownership (backlog #8). **0.5 day.**

### Phase 3 — Engineering Excellence
10. SCD2 invariant tests + refund-sign test + fact business-key uniqueness (MED-5).
11. Erasure procedure writing to `audit.audit_log`, PII tags in bronze/silver
    dictionaries (MED-4, LOW-5).
12. Index management moved into dbt; document `sql/` as bootstrap-only (MED-9).
13. Hash-skip for full-load snapshots (MED-7 / backlog #1); housekeeping (LOW-1).
14. Remove compose secret fallbacks (MED-8); reconsider SonarQube (INFO-3).

### Phase 4 — Scale (triggered, not scheduled)
15. Chunked/streaming extraction (LOW-7) — trigger: any table > ~1M rows.
16. Bronze retention/archival (backlog #2) — trigger: backup duration or disk
    pressure noticeable.
17. Partition bronze append tables and `fact_retail_sales` by date — trigger: ~10x
    current volume.
18. Revisit ADR-002 (cloud) only on its own documented triggers.

---

*This report was produced under `.claude/skills/dw-auditor/SKILL.md`. Every finding
cites repository evidence; nothing was assumed compliant without inspection. Findings
marked NOT AUDITABLE: none — the repository's documentation coverage was sufficient
to audit every phase, which is itself remarkable.*

# PrintTimeUSA Data Warehouse — External Audit Report (Round 2)

**Auditor role:** Independent Senior/Principal Data Engineer & DW Architect (external reviewer)
**Date:** 2026-07-28
**Scope:** Entire repository at commit `15c1c52` (post `v0.3.0-orchestration`)
**Prior audit:** [001](001-external-dw-audit.md) at commit `2b9433c` (score 2.80, DEVELOPMENT READY)
**Method:** `.claude/skills/dw-auditor/SKILL.md` — 20-phase evidence-based audit, re-run in full
**Standard applied:** "Would an experienced Senior or Principal Data Engineer confidently approve this architecture for production?"

---

## 1. Executive Summary

The orchestration release is a real and substantial improvement, not a cosmetic one. Two
of the six HIGH findings from round 1 are closed, one is materially reduced, and the
engineering process on display — a fix log that traces a latent uniqueness defect back
to *why it was untestable* — is better than most production teams practice.

**Score moves from 2.80 to 3.05.** The classification does **not** change, and the
reason is narrow and specific: there are still no backups.

What changed:

- **HIGH-1 (DAG could not execute) — CLOSED.** dbt-core/dbt-postgres are pinned in the
  Airflow image identically to the dbt service, `DBT_*` vars are forwarded, artifacts
  are redirected to an Airflow-writable path, and ADR-016 records the decision.
- **HIGH-2 (gold batch control unwired) — MOSTLY CLOSED.** The DAG now opens and
  completes real batches per gold target, which is what actually switches the facts
  from disguised full reloads to genuine incremental loads. Residual: gold rows still
  stamp `etl_batch_id` as NULL (MED-10).
- **HIGH-4 (no failure isolation) — REDUCED to MEDIUM.** A `fail_open_batches` sweeper
  with `ONE_FAILED` now prevents stranded `running` rows from later being completed and
  silently advancing the watermark — a subtle failure mode caught and handled well.
  Ingestion is still one serial task and there is still no alerting.

What did not change, and one thing that got worse:

1. **NEW HIGH-7: data-quality tests run *after* the watermark advances.** `run_dbt_tests`
   is the last step in the chain, downstream of `complete_gold_batches`. By the time a
   test fails, the gold batches are already `succeeded` and the watermark has moved, so
   the offending rows will never be reprocessed. The sweeper cannot help — it only
   closes `running` batches. Combined with `email_on_failure: False` and no callback,
   **a failing test currently neither blocks bad data nor notifies anyone.**
2. **HIGH-5: still zero disaster recovery.** No backup, no restore procedure, no RPO/RTO,
   nothing tested. Bronze history remains the one dataset that cannot be re-extracted
   and the one dataset with no protection. This single category is what holds the
   classification.
3. **HIGH-3: SCD2 still dates versions by load date and facts still resolve `is_current`.**
   Verified unchanged across all six Type 2 dimensions.
4. **HIGH-6: still one all-privilege database user.** Zero `CREATE ROLE`/`GRANT` in the repo.

**Overall: 3.05 / 5. Classification: DEVELOPMENT READY (upper end)** — meaningfully
closer to PRE-PRODUCTION than at round 1, and gated almost entirely on backups.

---

## 2. Architecture Assessment

Unchanged and still correct: PostgreSQL 16 + Python extract/load + dbt + Airflow on
Docker Compose remains right-sized for a single-source, daily-cadence retail warehouse
at this volume. No distributed technology is justified at any horizon currently in
evidence, and ADR-016 correctly chose the boring option (dbt inside the Airflow image,
versions pinned to match the dbt service so orchestrated and ad-hoc runs cannot drift)
over introducing DockerOperator complexity.

The orchestration work strengthened the architecture in one important way: the batch
lifecycle is now the actual control plane rather than a documented intention. Silver
rows carry a real `silver_batch_id`; gold facts read a real watermark; failures close
their own batches. This is the difference between a designed audit trail and a working
one.

The layer design continues to show no anti-patterns. The one architectural weakness is
now the **ordering of validation relative to commitment** (HIGH-7) — the pipeline
commits state before it verifies it.

---

## 3. Scorecard

| # | Category | v1 | **v2** | Change / justification |
|---|---|---|---|---|
| 1 | Architecture | 4 | **4** | — Unchanged; sound and right-sized. |
| 2 | Data Modeling | 3 | **3** | — SCD2 effective-dating flaw (HIGH-3) verified unchanged. |
| 3 | Data Quality | 3 | **3** | — Test *content* unchanged; test *timing* now actively undermines it (HIGH-7). |
| 4 | Incremental Processing | 2 | **3** | ▲ Gold watermark genuinely functional; bronze watermark race (MED-2) remains. |
| 5 | Data Governance | 3 | **3** | — No change. |
| 6 | Data Lineage | 4 | **4** | — Silver lineage now real; gold `etl_batch_id` still NULL. Net flat. |
| 7 | dbt | 4 | **4** | — DRY lineage macro (−264 lines) is good work; still no packages.yml, no exposures. |
| 8 | Airflow | 1 | **3** | ▲▲ Executable, real batch lifecycle, failure sweeper, thoughtful retry semantics. Held from 4 by test ordering, no alerting, no `max_active_runs`, monolithic ingest. |
| 9 | Python | 3 | **3** | — `build_batch_id` extraction + tests is real improvement; extractor flaws (MED-1/2) dominate. |
| 10 | PostgreSQL | 3 | **3** | — No change. |
| 11 | Scalability | 3 | **3** | — No change. |
| 12 | Performance | 3 | **3** | — Facts now genuinely incremental, but still no measured baselines. |
| 13 | Security | 2 | **2** | — Zero roles/grants; verified unchanged. |
| 14 | Docker / Infrastructure | 3 | **3** | — dbt artifact path handling is a nice fix; still no resource limits, SonarQube co-tenant. |
| 15 | CI/CD | 2 | **2** | — Unchanged, and now *more* consequential: a real DAG can break and CI still won't notice. |
| 16 | Observability | 2 | **3** | ▲ Real batch records for silver + gold with row counts from `run_results.json`; still no alerting. |
| 17 | Reliability | 2 | **3** | ▲ Sweeper + retry reasoning + FIX-003; offset by HIGH-7 and concurrency gaps. |
| 18 | Disaster Recovery | 0 | **0** | — Nothing. This is the gate. |
| 19 | Documentation | 5 | **5** | — ADR-016 + fix log + Lesson 10/11 maintain an exceptional standard. |
| 20 | Maintainability | 4 | **4** | — DRY macro helps; single-person bus factor unchanged. |

**Average: 3.05 / 5** (was 2.80). Per the framework, the DR score of 0 caps the
classification regardless of gains elsewhere.

---

## 4. Critical & High Findings

Still no CRITICAL findings. Five HIGH findings: one new, four carried forward.

---

### HIGH-7 (NEW) — Data-quality tests run after the watermark is committed

```text
ID:            HIGH-7
Category:      Data Quality / Orchestration / Reliability
Severity:      HIGH
Location:      airflow/dags/printtime_elt_pipeline.py:322-340 (main_chain order),
               :188-199 (_complete_gold_batches), :202-226 (_fail_open_batches),
               :50-57 (DEFAULT_ARGS)
Finding:       This is incorrect ordering. run_dbt_tests is the LAST element of
               main_chain, downstream of complete_gold_batches. The gold batches
               are marked 'succeeded' — which is precisely what advances the facts'
               incremental watermark — before any test has run. A test failure
               therefore fails the DAG *after* the bad data has been committed and
               the watermark moved past it.
Evidence:      main_chain = [..., run_dbt_gold, complete_gold_batches, run_dbt_tests]
               (lines 322-331). _complete_gold_batches unconditionally calls
               complete_batch() for every gold target based only on the dbt *run*
               task having succeeded; it never consults test results.
               _fail_open_batches recovers only rows WHERE batch_status = 'running'
               (line 220) — it cannot revert an already-'succeeded' batch. The
               facts read `max(batch_end_timestamp) WHERE batch_status='succeeded'`,
               so the next run starts after the untested load.
               DEFAULT_ARGS sets email_on_failure: False with no on_failure_callback.
Why It Matters: The DAG docstring states tests "fail the DAG on breakage" — but
               failing the DAG after committing the state protects nothing. In the
               current wiring a failing test neither blocks bad data nor notifies a
               human. The test suite is, operationally, decorative.
Business Impact: Data that violates a business rule (a broken status vocabulary, an
               orphaned invoice line, a positive refund) lands in gold, is exposed
               to BI, and is never reprocessed — because the pipeline believes that
               range is already done. Silent incorrect reporting.
Technical Impact: Recovering requires a manual `dbt run --full-refresh` on the
               affected facts plus manual correction of audit.etl_batch_control.
               There is no automated path back.
Recommendation: Two changes, both small:
               (1) Move run_dbt_tests BETWEEN run_dbt_gold and complete_gold_batches,
                   so the watermark advances only after tests pass. The sweeper
                   already handles the failure path correctly — the gold batches
                   would still be 'running' and would be closed as 'failed', which
                   is exactly the desired behaviour.
               (2) Add an on_failure_callback (or set email_on_failure with an SMTP
                   connection) so a failed run is actually observed.
               Optionally split tests: run silver tests before the gold run so bad
               silver data never reaches gold at all.
Priority:      P1 — this is the highest-value single change in the repository
Effort:        1-2 hours
```

### HIGH-5 (CARRIED, unchanged) — No disaster recovery

```text
ID:            HIGH-5
Category:      Disaster Recovery
Severity:      HIGH
Location:      Repository-wide (absence); docker-compose.yml volumes; backlog #8
Finding:       Verified unchanged at 15c1c52. No pg_dump schedule, no WAL archiving,
               no volume snapshot procedure, no restore documentation, no RPO/RTO,
               nothing ever restore-tested. git ls-files matches nothing for
               backup|restore|pg_dump.
Evidence:      No backup script under scripts/; no backup DAG; the single
               postgres_data volume still backs the warehouse AND Airflow metadata
               (AIRFLOW_DB_NAME=printtime_dw) AND SonarQube's store.
Why It Matters: Bronze's append-only history is the one dataset that cannot be
               rebuilt by re-extracting from OLTP — re-extraction recovers current
               state only. That irreplaceable layer has zero protection, and
               scripts/reset.sh exists one typo away from it. Now that the pipeline
               runs daily and unattended, accumulated history grows daily too.
Business Impact: Irrecoverable loss of historical change data; SCD2 history could
               not be rebuilt as-was.
Technical Impact: RPO = infinity. RTO = undefined.
Recommendation: Unchanged from round 1 and now the sole gate on PRE-PRODUCTION:
               nightly pg_dump of the warehouse schemas to a path outside the
               docker volume, 14-day retention, ONE executed restore drill, and
               a separate database for Airflow metadata (a one-line .env change).
               Record RPO/RTO in the runbook (backlog #8).
Priority:      P0 — highest-consequence gap in the platform
Effort:        0.5 day for dump + retention; 0.5 day for the drill and its writeup
```

### HIGH-3 (CARRIED, unchanged) — SCD2 dates by load date; facts resolve is_current

```text
ID:            HIGH-3
Category:      Data Modeling
Severity:      HIGH
Location:      dim_cashier.sql:124, dim_customer.sql:142, dim_invoice.sql:137,
               dim_payment_method.sql:114, dim_product.sql:132, dim_store.sql:124
               (all `current_date::date as valid_from`);
               fact_retail_sales.sql and fact_payments.sql (is_current joins)
Finding:       Verified unchanged. All six Type 2 dimensions still date versions by
               warehouse load date rather than the business change timestamp, and
               facts still resolve dimension keys against is_current rather than by
               effective-date range. Point-in-time reporting remains unachievable.
Why It Matters: This is now MORE consequential than at round 1, not less. The
               pipeline previously ran by hand; it now runs daily and unattended, so
               mis-dated versions accumulate automatically, and the newly-working
               incremental fact reload re-points reloaded invoices at whatever the
               current dimension version is on the day of reload.
Business Impact: Margin-at-time-of-sale, sales-by-region trends, and any as-was
               report drift silently as dimensions change.
Technical Impact: SCD2 history is retained but unreachable from the facts; the
               versioning machinery (post_hooks, row_version, record_hash) buys
               nothing analytically.
Recommendation: Unchanged: (1) date versions from
               silver_source_updated_at_timestamp::date, falling back to load date
               only when null; (2) resolve fact dimension keys by
               valid_from <= invoice_date < coalesce(valid_to,'9999-12-31').
               Alternatively downgrade to Type 1 and record the ADR — either
               position is defensible; the current hybrid is not.
Priority:      P1
Effort:        2-3 days including backfill reasoning
```

### HIGH-6 (CARRIED, unchanged) — One all-privilege user for every service

```text
ID:            HIGH-6
Category:      Security / Governance
Severity:      HIGH
Location:      All sql/ DDL (absence); docker-compose.yml; .env.example
Finding:       Verified unchanged. `git grep -il "CREATE ROLE|GRANT |REVOKE" -- *.sql`
               returns nothing. ADR-013 §3's least-privilege model remains entirely
               unimplemented. Ingestion, dbt, Airflow (both metadata and DW
               connections), SonarQube, and pgAdmin all authenticate as the single
               ${POSTGRES_USER} owner.
Why It Matters: ADR-013's PII-minimization claim ("BI users never see raw contact
               PII — minimization is structural") depends on grants that do not
               exist. Any connected client can read silver.customer email/phone.
               SonarQube, a third-party Java application, holds warehouse-owner
               credentials.
Business Impact: CCPA posture weaker than documented; compromise of any one service
               compromises every layer including PII.
Technical Impact: No blast-radius containment.
Recommendation: Implement ADR-013 §3 as sql/security/001_create_roles.sql:
               ingestion role (bronze+audit write), dbt role (read bronze, own
               silver/gold), bi_reader (gold SELECT only); separate databases for
               Airflow metadata and SonarQube. Bake into the postgres init image —
               remember this requires `docker compose build --no-cache postgres`,
               not just a volume wipe.
Priority:      P1 for the role split; P2 for database separation
Effort:        1 day
```

### HIGH-4 (CARRIED, REDUCED) — Monolithic ingestion, no alerting

```text
ID:            HIGH-4
Category:      Airflow / Reliability
Severity:      HIGH → borderline MEDIUM (partially mitigated)
Location:      airflow/dags/printtime_elt_pipeline.py:115-135, :50-57
Finding:       Partially addressed. The new fail_open_batches sweeper closes the
               most dangerous consequence of a mid-run failure (stranded 'running'
               rows that a later manual fix could complete, silently advancing the
               watermark) — that was a genuinely subtle failure mode and it was
               caught and handled well. Still open: all ~20 tables extract and load
               serially inside one PythonOperator, so a failure on table 7 aborts
               8-20; and there is still no alerting whatsoever.
Evidence:      Line 130: `for table in tables:` inside _ingest_oltp_to_bronze.
               DEFAULT_ARGS: email_on_failure False, email_on_retry False, no
               on_failure_callback, no sla.
Why It Matters: The pipeline now runs unattended on a daily schedule. Unattended
               plus unalerted means failures are discovered by data consumers.
Business Impact: Silent staleness; the _bronze_sources.yml freshness SLA (warn 24h
               / error 48h) will fire into a void.
Technical Impact: Retry re-runs all 20 tables; no per-table visibility or parallelism.
Recommendation: Use Airflow 2.9 dynamic task mapping (.expand over the config table
               list) for one task per table with per-table retries, and add an
               on_failure_callback. Pair with HIGH-7's alerting fix — same change.
Priority:      P1 (alerting), P2 (task mapping)
Effort:        0.5 day
```

---

## 5. Detailed Findings — New in Round 2

### MED-10 (NEW) — Gold rows still stamp `etl_batch_id` as NULL

- **Location:** all 9 gold models, e.g. `dim_customer.sql:139`, `fact_retail_sales.sql:135`
  (`null::varchar(50) as etl_batch_id`)
- **Finding:** The residual half of HIGH-2. Gold batches now exist in
  `audit.etl_batch_control` and drive the watermark correctly, but no gold row records
  *which* batch produced it. The gold naming convention documents `etl_batch_id` as
  "joins `audit.etl_batch_control.batch_id`" — that join is still impossible.
- **Why it matters:** Row-level gold lineage is the last broken link in an otherwise
  end-to-end traceable chain. ADR-013 §5 claims full traceability as a governance
  capability.
- **Recommendation:** `start_gold_batches` already returns `{target: batch_key}` via
  XCom. Template it into `run_dbt_gold` as `--vars` exactly as the silver run does, and
  replace the NULL literal with `{{ var('gold_batch_id', -1) }}`. **Effort:** 2h.
- **✅ RESOLVED (2026-08-05):** `_start_gold_batches` now also exposes the TEXT `batch_id`
  per target and pushes a `gold_batch_ids` map; `run_dbt_gold` templates it into `--vars`;
  a `gold_batch_id()` macro resolves each model's own id (facts → own target, dims → the
  shared `gold.dimensions` batch per ADR-008); all 9 models stamp
  `'{{ gold_batch_id() }}'::varchar(50)`. Note the recommendation's `batch_key` was
  corrected to the **text `batch_id`**, since the naming convention joins on `batch_id`.
  Verified: every non-seed gold row joins cleanly to `etl_batch_control.batch_id`; 165/165
  tests pass. See `docs/fix/fix_log.md` FIX-006.

### MED-11 (NEW) — No `max_active_runs`; the sweeper is not scoped to a DAG run

- **Location:** `printtime_elt_pipeline.py:233-242` (no `max_active_runs`),
  `:214-223` (sweeper filters only on `initiated_by = :pipeline`)
- **Finding:** Two concurrent runs are possible (a manual trigger during a scheduled
  run, or a long run overlapping the next day). They would share watermarks and
  delete+insert the same fact rows. Worse, `_fail_open_batches` selects every `running`
  batch for the pipeline **without scoping to the current run**, so a failure in run A
  would mark run B's legitimately-in-flight batches as `failed` — corrupting run B's
  audit trail and preventing its watermark from advancing.
- **Recommendation:** Set `max_active_runs=1` on the DAG (one line, and correct for a
  watermark-driven pipeline), and additionally scope the sweeper's WHERE clause by
  `batch_key IN` the keys this run pushed to XCom. **Effort:** 1h.

### MED-12 (NEW) — `silver_batch_id` falls back to −1 on any ad-hoc dbt run

- **Location:** `macros/silver_lineage_and_metadata.sql:40` —
  `{{ var('silver_batch_id', -1) }}`
- **Finding:** The orchestrated path now supplies a real batch key, which is the
  improvement. But ADR-016 deliberately keeps the standalone dbt service for ad-hoc
  runs, and any `dbt run --select silver` from it stamps −1. Previously every row was
  −1 (uniformly meaningless); now the column is *mostly* trustworthy with occasional
  −1 sentinels, which is a worse failure mode because it invites trust.
- **Recommendation:** Either make the var required (`{{ var('silver_batch_id') }}` —
  dbt errors loudly if absent, forcing ad-hoc runs to pass one) or have ad-hoc runs
  open a real batch. Loud failure is preferable to a silent sentinel. **Effort:** 1h.

### LOW-8 (NEW) — `run_results.json` is a single shared path

- **Location:** `printtime_elt_pipeline.py:67` (`DBT_RUN_RESULTS`), `:91-108`
- **Finding:** Row counts are read from one fixed artifact path that every dbt
  invocation overwrites. Concurrent runs (see MED-11) or an ad-hoc dbt run inside the
  Airflow container would misattribute counts to the wrong batch. The code is honest
  about this — it degrades to 0 and comments that counts are "best-effort audit
  metadata, never a reason to fail a load," which is the correct engineering posture —
  so this is LOW, not MEDIUM.
- **Recommendation:** Namespace the target path per run (`DBT_TARGET_PATH` including
  `{{ run_id }}`) once `max_active_runs` is decided. **Effort:** 30m.

### MED-6 (CARRIED, now more consequential) — CI cannot catch a broken dbt model or DAG

- **Verified unchanged:** CI runs Ruff, mypy, pytest, and `docker compose config` only.
  No `dbt parse`, no `dbt compile`, no DagBag import test, no SQL linting, no
  `packages.yml` (dbt_utils still absent).
- **Why it is worse now:** at round 1 the DAG did not run, so a broken DAG was
  inert. It now runs daily in an orchestrated pipeline, and a syntax error in either a
  DAG or a dbt model still merges green. The `--vars` Jinja templating in
  `run_dbt_silver` (line 270) is exactly the kind of construct that breaks silently.
- **Recommendation:** Add `dbt parse` (no DB needed), `dbt compile` against an ephemeral
  Postgres service container, and a DagBag import test. **Effort:** 1 day.

### Carried forward unchanged from round 1

MED-1 (f-string SQL in extractor), MED-2 (watermark race / hard deletes never captured),
MED-3 (partial bronze load duplicates on retry), MED-4 (`audit.audit_log` never written
despite ADR-013 §4 depending on it), MED-5 (no SCD2 invariant tests — still no
`packages.yml`), MED-7 (bronze full-load snapshot stacking), MED-8 (compose secret
fallbacks), MED-9 (`--full-refresh` drops DDL-managed indexes), LOW-1 through LOW-7.
All verified still present at `15c1c52`.

> **✅ MED-4 RESOLVED (2026-08-05):** `audit.audit_log` is now written on every fact
> reload. The two `delete+insert` facts stage each replaced row's before-image in a
> `pre_hook` and write one **insert-only** `audit_log` row per row in a `post_hook` — with
> `old_row`, `new_row`, `changed_columns` (business columns only), `change_reason`
> (best-effort from `silver.invoice_adjustment`, else `source_update`), the real
> `etl_batch_id` (paired with MED-10), and `source_system`. SCD2 dimensions keep their own
> history in-table, so they don't need it (facts-only gap). `audit_log` stays strictly
> insert-only (ADR-008) via a temp-staging pattern, and `pt_dbt` was granted **INSERT on
> `audit_log` only** (not `etl_batch_control`). Verified end-to-end: a changed invoice logs
> old→new plus the exact changed columns. See `docs/fix/fix_log.md` FIX-007.

---

## 6. Data Model Assessment

Unchanged from round 1 in substance: grains are explicit and correct, surrogate/natural
key separation is clean, `-1` unknown members are seeded idempotently, SCD types were
reasoned per table rather than cargo-culted. The SCD2 effective-dating flaw (HIGH-3)
remains the one modeling defect that matters, and it is now accruing mis-dated history
daily rather than only when someone ran the pipeline by hand.

Still untested business invariants: refund sign (documented as negative, nothing
enforces it), fact grain uniqueness on `source_record_id`, SCD2 single-current-row.

## 7. Pipeline Assessment

This is where the release earned its score. The pipeline is now a real orchestrated
system: batch open → work → batch complete, with a failure sweeper closing what it
opened. The retry semantics were thought through correctly (a task with retries
remaining sits in `up_for_retry`, not `failed`, so `ONE_FAILED` does not fire
prematurely — the sweeper cannot close a batch a retrying task still needs).
`build_batch_id` was extracted into a pure, unit-tested function, and doing so exposed
a second latent defect — documented as FIX-003 with a genuinely useful rule ("a bug you
cannot unit test will come back").

Re-running the audit questions against the new implementation:

- *Fails halfway?* Sweeper closes open batches; watermark does not advance. **Pass.**
- *Same batch twice?* Bronze double-appends; silver dedup absorbs it. **Pass with caveat.**
- *Record two days late?* Picked up by watermark, but mis-dated in SCD2. **Partial (HIGH-3).**
- *Source record deleted?* Hard deletes still never captured. **Fail (MED-2).**
- *Unavailable seven days?* Watermarks recover cleanly. **Pass.**
- *Bad data detected by tests?* **Fail — committed before testing (HIGH-7).**
- *Two runs concurrently?* Undefined and mutually destructive. **Fail (MED-11).**

## 8. Data Quality Assessment

The test *content* remains strong (52 silver tests covering business keys, the 11 status
vocabularies, FK relationships including the orphan-line check, plus ~85 gold test
declarations and a source freshness SLA). The test *position in the pipeline* now
undermines all of it (HIGH-7). Fixing the ordering is a one-line change to `main_chain`
and is the single highest-leverage improvement available in this repository.

## 9. Governance Assessment

No change. Documentation-side governance stays exceptional; enforcement-side governance
stays absent — no grants (HIGH-6), no erasure implementation (MED-4), PII tags still
only in the gold dictionary rather than the bronze/silver dictionaries where the PII
actually lives (LOW-5). The gap between decided and built is the recurring theme, and
it is now the dominant one: the orchestration release proved this team closes that gap
well when it focuses on a layer.

## 10. Security Assessment

Verified clean again: no secrets in git history, `.env` ignored, env-var credentials
throughout, pinned images, isolated bridge network. Verified still open: single shared
all-privilege user (HIGH-6), compose secret fallbacks (MED-8), SonarQube holding
warehouse-owner credentials, f-string SQL (MED-1). Unchanged at 2/5.

## 11. Scalability Assessment

Improved in one respect: the facts are now genuinely incremental rather than silently
full-reloading every run, which removes the first bottleneck round 1 identified. Current
volume and 10x remain comfortable. At ~100x, bronze snapshot stacking (MED-7) dominates
storage and pandas whole-table extraction (LOW-7) becomes the ingestion wall. Single-node
PostgreSQL remains correct at every horizon currently in evidence. No distributed
technology recommended.

## 12. Reliability Assessment

Genuinely improved. The design's inherent resilience (append-only bronze + dedup-latest
silver) is now backed by an operational control plane that opens, tracks, and closes its
own work units. The remaining reliability gaps are ordering (HIGH-7), concurrency
(MED-11), alerting (HIGH-4), and recovery (HIGH-5) — three of which are hours of work.

---

## 13. Production Readiness

```text
Classification: DEVELOPMENT READY (upper end)
```

Scale: NOT READY → EARLY DEVELOPMENT → **DEVELOPMENT READY** → PRE-PRODUCTION →
PRODUCTION READY → ENTERPRISE READY.

**Reasoning.** Round 1 withheld PRE-PRODUCTION for three reasons: the orchestrator could
not run, historical reporting drifts silently, and there is no backup. The first is now
fixed and fixed well. The second and third are not, and a fourth has been identified
(tests commit before they validate).

Per the scoring framework, Disaster Recovery at 0 caps the classification on its own:
a platform whose irreplaceable dataset has no backup and no tested restore cannot be
called PRE-PRODUCTION regardless of a 3.05 average or a 5 in documentation. That is the
correct call and it is not a close one.

That said, the distance is now short and precisely known. **Phase 1 below is roughly
three days of work and would justify PRE-PRODUCTION.** A Senior/Principal Data Engineer
would not approve this for production today, but would recognise a project that closed
two HIGH findings between audits with better process discipline than most production
teams — and would expect the remaining gate to fall quickly.

---

## 14. Remediation Roadmap

### Phase 1 — Critical Fixes (~3 days; this is the PRE-PRODUCTION gate)
1. **Move `run_dbt_tests` before `complete_gold_batches`** and add an
   `on_failure_callback` (HIGH-7, HIGH-4 alerting). **2h — highest value in the repo.**
2. **Backups:** nightly `pg_dump`, 14-day retention, one executed restore drill,
   separate the Airflow metadata database (HIGH-5). **1 day.**
3. **`max_active_runs=1`** and scope the sweeper to the current run's batch keys
   (MED-11). **1h.**
4. **Roles and grants** per ADR-013 §3 (HIGH-6). **1 day.**

### Phase 2 — Production Readiness
5. Fix SCD2 effective dating and effective-date fact key resolution — or consciously
   downgrade to Type 1 with an ADR (HIGH-3). **2-3 days.**
6. Stamp `etl_batch_id` on gold rows via `--vars`, mirroring the silver pattern
   (MED-10). **2h.**
7. Make `silver_batch_id` required rather than defaulting to −1 (MED-12). **1h.**
8. CI: `dbt parse`, `dbt compile` against an ephemeral Postgres, DagBag import test,
   sqlfluff (MED-6). **1 day.**
9. Per-table dynamic task mapping for ingestion (HIGH-4). **0.5 day.**
10. Transactional bronze loads (MED-3); parameterized extraction SQL (MED-1). **0.5 day.**
11. Runbook: deploy order, backfill, restore, freshness SLA ownership (backlog #8). **0.5 day.**

### Phase 3 — Engineering Excellence
12. Add `packages.yml` + dbt_utils; SCD2 invariant tests, refund-sign test, fact grain
    uniqueness (MED-5).
13. Erasure procedure writing to `audit.audit_log`; PII tags in bronze/silver
    dictionaries (MED-4, LOW-5).
14. Index management into dbt post-hooks; document `sql/` as bootstrap-only (MED-9).
15. Hash-skip for full-load snapshots (MED-7 / backlog #1); remove compose secret
    fallbacks (MED-8); namespace dbt artifacts per run (LOW-8); housekeeping (LOW-1).

### Phase 4 — Scale (triggered, not scheduled)
16. Chunked/streaming extraction — trigger: any table > ~1M rows.
17. Bronze retention/archival (backlog #2) — trigger: backup duration or disk pressure.
18. Partition bronze append tables and `fact_retail_sales` by date — trigger: ~10x volume.
19. Revisit ADR-002 (cloud) only on its own documented triggers.

---

## Appendix — Round 1 → Round 2 Finding Status

| ID | Finding | v1 | v2 |
|---|---|---|---|
| HIGH-1 | DAG cannot execute | HIGH | **CLOSED** |
| HIGH-2 | Gold batch control unwired | HIGH | **CLOSED** (residual → MED-10) |
| HIGH-3 | SCD2 load-date dating | HIGH | **OPEN — unchanged** |
| HIGH-4 | Monolithic ingest, no alerting | HIGH | **REDUCED** (sweeper added; alerting + isolation open) |
| HIGH-5 | No disaster recovery | HIGH | **OPEN — unchanged** |
| HIGH-6 | No roles/grants | HIGH | **OPEN — unchanged** |
| HIGH-7 | Tests run after watermark commits | — | **NEW** |
| MED-10 | Gold `etl_batch_id` NULL | — | **RESOLVED** (2026-08-05, FIX-006) |
| MED-11 | No `max_active_runs`; unscoped sweeper | — | **NEW** |
| MED-12 | `silver_batch_id` −1 fallback | — | **NEW** |
| LOW-8 | Shared `run_results.json` path | — | **NEW** |
| MED-1..9, LOW-1..7 | Round 1 medium/low findings | — | **OPEN — verified unchanged** |

*Produced under `.claude/skills/dw-auditor/SKILL.md`. Every finding cites repository
evidence at commit `15c1c52`; carried-forward findings were re-verified rather than
assumed. Findings marked NOT AUDITABLE: none.*

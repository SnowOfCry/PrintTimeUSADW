# 003 — External Data-Warehouse Audit (Final)

**Auditor:** Independent Senior/Principal Data Engineering review
**Date:** 2026-08-07
**Commit audited:** `8d57789` (develop)
**Scope:** Full platform — architecture, modeling, ELT, data quality, governance, lineage,
security, infra, CI/CD, observability, reliability, DR, documentation.
**Prior audits:** [001](001-external-dw-audit.md), [002](002-external-dw-audit.md) — all HIGH and
MEDIUM findings from both were remediated and traced in [`docs/fix/fix_log.md`](../fix/fix_log.md)
(FIX-001 … FIX-016). This report is an independent re-assessment of the **current** state, not a
re-check of closed items.

---

## 1. Executive Summary

This is a genuinely well-engineered analytical platform for its stated context (a single retail
print shop, single-node PostgreSQL, ELT with dbt + Airflow, local/on-prem Docker). The core data
engineering — the part that is hardest to get right — is **strong and evidence-backed**: the
medallion separation is clean, the SCD2 dimensions are correct and effective-dated, the
incremental machinery is idempotent and watermark-gated, and the whole warehouse reconciles to
the cent and passes **168/168 dbt tests**. Two prior external audits were taken seriously and
closed in full, including non-trivial correctness fixes (SCD2 null-guard, per-key hash-skip,
watermark lookback) documented with root-cause discipline.

The remaining gaps are **operational, not architectural**. The single most important one is that
**CI does not compile or test dbt** — the business logic and all 168 data tests can regress on a
pull request without detection. After that, the gaps are the familiar "last mile to production"
items: no failure alerting, no container resource limits, PII masking deferred, secrets in `.env`
rather than a manager, and DR that is scripted but whose restore is not proven on a schedule.

There are **no CRITICAL findings** and **one HIGH finding** (the CI dbt gate). Nothing here
threatens data correctness today; the findings gate *unattended production operation*, not
correctness.

**Biggest risks:** (1) an unguarded dbt change reaching `main`; (2) a silent overnight pipeline
failure nobody is paged for; (3) an untested restore path.

**Production readiness: `PRE-PRODUCTION`** — with a short, well-scoped path to `PRODUCTION READY`
for the intended small-scale deployment (see §13–14).

---

## 2. Architecture Assessment

The intended architecture and the actual implementation **match** — a rarity worth stating. The
medallion is real, not cosmetic:

- **bronze** — append-only raw landing, one row per source row per batch, no business logic.
- **silver** — deterministic, contract-enforced, hash-gated incremental merge; one current row
  per business key; ADR-005 cleaning.
- **gold** — Kimball star; 6 SCD2 dims (append + post-hook close), 3 facts at explicit grain, 3
  role-playing date views, `-1` unknown members.
- **audit** — `etl_batch_control` (batches, watermarks, row counts, status) and `audit_log`
  (fact-level before/after change trail).

Separation of concerns is enforced by design: Python does Extract+Load only; every
transformation is SQL in dbt (ADR-003). Raw history is preserved (bronze append-only, ADR-004),
so any layer is reproducible with `dbt build --full-refresh`. The architecture is idempotent,
restartable, and reprocessable — and this was **demonstrated**, not asserted: a full teardown and
rebuild from bronze reproduced a clean baseline (all dims v1, 168 tests green).

The technology choice is correctly sized. Single-node PostgreSQL + dbt + Airflow is appropriate
for this data volume and velocity (ADR-002 chose this deliberately over cloud). No overengineering
— no Spark/Kafka/Kubernetes cargo-culting.

**Verdict:** appropriate, coherent, and honestly documented.

---

## 3. Scorecard (0–5)

| # | Category | Score | One-line rationale |
|---|---|---|---|
| 1 | Architecture | **5** | Clean medallion, true separation, reproducible, idempotent |
| 2 | Data Modeling | **4** | Correct Kimball SCD2 + explicit grain; one denormalization fan-out smell |
| 3 | Data Quality | **4** | 168 tests, cent-level reconciliation, contracts; a few business rules untested |
| 4 | Incremental Processing | **5** | Watermark + lookback, per-key hash-skip, tests-gate-watermark, fail-safe |
| 5 | Data Governance | **4** | 19 ADRs, dictionaries, mappings; PII identified but masking deferred |
| 6 | Data Lineage | **4** | `etl_batch_id` end-to-end + dbt DAG + change trail; no rendered lineage/exposures |
| 7 | dbt | **4** | Contracts, macros, incremental strategies, tests; audit macro is intricate |
| 8 | Airflow | **4** | `max_active_runs=1`, HIGH-7 gate, fail-open sweeper; no alerting, `retries=1` |
| 9 | Python | **4** | Typed, logged, batch-controlled, identifier-validated; thin unit coverage |
| 10 | PostgreSQL | **4** | Indexes, constraints, contracts; no partitioning for long-term growth |
| 11 | Scalability | **3** | Single-node; invoice-granular fact reload; fine now, ceiling at high scale |
| 12 | Performance | **4** | Incremental everywhere, indexed; reload granularity slightly coarse |
| 13 | Security | **4** | Least-privilege RBAC, `.env` gitignored, no hardcoded secrets; no vault/at-rest |
| 14 | Docker / Infrastructure | **3** | Healthchecks + restart; **no resource limits**; Compose ≠ prod orchestration |
| 15 | CI/CD | **2** | Lint + unit + compose-validate, but **dbt is never compiled or tested** |
| 16 | Observability | **4** | Rich batch metrics + watermarks + errors; no alerting/dashboards |
| 17 | Reliability | **4** | Idempotent, gated, single active run, stranded-batch sweeper |
| 18 | Disaster Recovery | **3** | ADR-018 + backup/restore scripts; restore not proven on a schedule |
| 19 | Documentation | **5** | Exceptional — ADRs, dictionaries, mappings, fix log, README |
| 20 | Maintainability | **5** | Spec-first, ADR-governed, DRY macros, clear structure |

**Overall: 3.9 / 5** — "Strong, pre-production." The average is not inflated by hiding a critical
failure; the lowest score (CI/CD, 2) is a genuine risk and is called out as the top finding.

---

## 4. Critical & High Findings

### AUDIT-003-H1 — CI does not compile or test dbt (the core logic is ungated)

```
ID:            AUDIT-003-H1
Category:      CI/CD
Severity:      HIGH
Location:      .github/workflows/ci.yml
```

**Finding:** CI runs three jobs — Ruff lint/format, pytest unit tests (`ingestion/` only), and
`docker compose config` validation. It **never runs `dbt compile`, `dbt build`, or `dbt test`.**

**Evidence:** the workflow's only jobs are `lint`, `unit-tests`, and `docker-compose-validate`;
there is no service container for Postgres and no dbt invocation anywhere in the file.

**Why it matters:** the entire business value of this repo lives in dbt — 34 models and **168 data
tests**, contracts, SCD2 logic, reconciliation. None of it is exercised on a pull request. A PR can
merge a model that fails to compile, breaks a contract, violates the SCD2 no-overlap guard, or
breaks cent-level reconciliation, and CI will be green.

**Business impact:** silent introduction of incorrect reporting or a broken pipeline into `main`;
the safety net the team built (168 tests) is not enforced at the gate where it matters.

**Technical impact:** regressions are caught only when someone runs dbt locally or the DAG fails in
Airflow — after merge, not before.

**Recommendation:** add a CI job that spins up an ephemeral `postgres:16` service, seeds the
schemas (`sql/`), runs `dbt build --select silver gold` (or at minimum `dbt compile` +
`dbt test`) against it, and fails the PR on any error. This is the same command the DAG already
runs; wiring it into CI is low effort and closes the biggest operational gap.

```
Priority:      P1 (before any further feature work)
Effort:        ~half day
```

*(No CRITICAL findings. The prior audits' correctness-level items are closed and verified.)*

---

## 5. Detailed Findings (MEDIUM / LOW / INFO)

### AUDIT-003-M1 — No failure alerting on the pipeline
```
Category: Airflow / Observability | Severity: MEDIUM
Location: airflow/dags/printtime_elt_pipeline.py (DEFAULT_ARGS)
```
**Finding:** `email_on_failure=False` and no alert callback / webhook. A failed nightly run is only
discoverable by opening the Airflow UI. **Evidence:** DAG default args disable email; no
`on_failure_callback`. **Why it matters:** the platform is observable (rich `etl_batch_control`
metrics) but not *actively* — nobody is told when it breaks. **Recommendation:** add an
`on_failure_callback` (email/Slack/webhook) at the DAG level, and consider alerting when
`fail_open_batches` closes stranded batches. **Effort:** ~2 h.

### AUDIT-003-M2 — Containers have no resource limits
```
Category: Docker / Infrastructure | Severity: MEDIUM
Location: docker-compose.yml
```
**Finding:** healthchecks (2) and `restart: unless-stopped` (6) are present, but **no** memory/CPU
limits on any service. **Evidence:** zero `deploy.resources` / `mem_limit` / `cpus` entries.
**Why it matters:** a runaway dbt/Airflow task or a large fact reload can consume all host memory
and take down Postgres alongside it — no failure isolation. **Recommendation:** set `mem_limit`
(and reservations) per service, sized to the host. **Effort:** ~1 h.

### AUDIT-003-M3 — PII masking not implemented
```
Category: Data Governance / Security | Severity: MEDIUM
Location: docs/adr/013-data-governance-and-pii.md; backlog #4
```
**Finding:** customer/employee email + phone are CCPA-relevant PII, identified in ADR-013 and
tracked in the backlog, but no masking, tagging, or column-level access control is implemented; the
BI reader role can read raw PII. **Why it matters:** governance is *documented* but not *enforced*.
**Recommendation:** at minimum, a masked view layer for `pt_bi_reader`, or column-level grants;
decide retention/deletion for PII per ADR-013. **Effort:** ~half day.

### AUDIT-003-M4 — Secrets live in `.env`, not a secret manager
```
Category: Security | Severity: MEDIUM
Location: .env / docker-compose.yml
```
**Finding:** all credentials come from `.env` (correctly gitignored; **no** secrets in Git history —
verified). For real production this is still plaintext-on-disk with no rotation. **Why it matters:**
adequate for local/dev; insufficient for production. **Recommendation:** integrate a secret
manager (Docker secrets, Vault, or cloud KMS) for the deployed environment; keep `.env` for local.
**Effort:** ~half day (environment-dependent).

### AUDIT-003-M5 — DR restore is scripted but not proven on a schedule
```
Category: Disaster Recovery | Severity: MEDIUM
Location: scripts/backup_warehouse.sh, scripts/restore_warehouse.sh, ADR-018
```
**Finding:** ADR-018 closed the prior HIGH-5 (no DR) with backup + restore scripts and a
reproducibility argument (bronze + code rebuilds silver/gold). But there is no evidence of an
*automated, tested* restore drill with a recorded RPO/RTO measurement. **Why it matters:** "a backup
never restored is not validated." **Recommendation:** schedule the backup, and add a periodic
restore-to-scratch drill that asserts row counts + a reconciliation check; record the measured RTO.
**Effort:** ~half day.

### AUDIT-003-L1 — `dim_invoice` versions on denormalized `customer_name` / `store_name`
```
Category: Data Modeling | Severity: LOW
Location: dbt/printtime_dw/models/gold/dim_invoice.sql (record_hash)
```
**Finding:** `dim_invoice`'s change-hash includes the denormalized `customer_name` and
`store_name`, so renaming a customer mints a new version of **every** invoice that customer owns
(observed: 3,401 such ripple versions vs 298 direct invoice changes). **Why it matters:** invoice
history churns on changes to *other* dimensions, inflating `dim_invoice`. It is currently **correct**
(effective dates are historical and monotonic; no overlap), just verbose. **Recommendation:** a
deliberate ADR decision — either accept the fan-out (denormalized attributes stay current) or drop
`customer_name`/`store_name` from the version hash (invoice versions only on its own attributes).
**Effort:** ~2 h if changed.

### AUDIT-003-L2 — Thin ingestion unit-test coverage
```
Category: Python / Testing | Severity: LOW
Location: tests/unit/ (backlog #9)
```
**Finding:** only a few unit tests (extractor query builders); the bronze loader's per-key
hash-skip and identifier validation (FIX-016) are proven functionally, not unit-tested.
**Recommendation:** add unit tests for `bronze_loader` (hash-skip, key_columns validation) and
`batch_control`. **Effort:** ~half day.

### AUDIT-003-L3 — Append-only bronze grows unbounded (no retention)
```
Category: PostgreSQL / Scalability | Severity: LOW
Location: ADR-004; backlog #2
```
**Finding:** bronze grows monotonically by design; full-load hash-skip (FIX-016) removed the
per-run stacking, but there is still no archival/retention policy. Fine now; revisit before bronze
becomes operationally large. **Recommendation:** a retention/partition-by-batch-date policy when
size warrants. **Effort:** design ~half day.

### AUDIT-003-I1 — End-user ("who") attribution bounded by the source
```
Category: Data Lineage / Governance | Severity: INFORMATIONAL
Location: backlog #12
```
Already correctly documented as an **external** limitation: the DW attributes changes to the ETL
run (`etl_batch_id`) and captures a human actor where the source records one (status-history
`changed_by`, `adjusted_by`, `refunded_by`), but the OLTP `customer`/`invoice` base tables carry no
`updated_by`, so generic field edits can't be tied to a person. Not a warehouse gap — a source
dependency. No action until the source adds the column.

---

## 6. Data Model Assessment

**Strengths:** every fact has an explicit, documented grain (`fact_retail_sales` = invoice line,
tested unique on `sales_line_key`; `fact_payments` = payment, tested unique on `payment_key`);
additivity is reasoned (refunds stored negative with `parent_payment_key` so `SUM` nets correctly);
SCD2 is real Type 2 with contiguous, non-overlapping windows and a machine-checked no-overlap guard;
`-1` unknown members prevent NULL-join loss; surrogate keys are dbt-managed and stable.
**Weakness:** the `dim_invoice` cross-dimension denormalization fan-out (L1). **Verdict:** strong,
professional dimensional modeling.

## 7. Pipeline Assessment

**Ingestion** (Python EL): typed, logged, watermark-driven, batch-controlled, with SQL-identifier
validation on dynamic table/keys. **Transformation** (dbt): contract-enforced silver merge +
SCD2/fact gold, all incremental. **Orchestration** (Airflow): `max_active_runs=1` (no concurrent
watermark corruption), tests **gate** the watermark (HIGH-7 — validation runs before the fact
batches complete), and a `ONE_FAILED` sweeper closes stranded batches so a later manual fix can't
silently advance the watermark. This is the strongest part of the platform and is battle-tested by
the closed incremental-correctness fixes (MED-2 lookback, MED-7 per-key hash-skip). **Gap:** no
alerting (M1), `retries=1`.

## 8. Data Quality Assessment

168 dbt tests: PK uniqueness, not-null, accepted values, relationships, plus **singular** tests for
SCD2 (one-current, no-overlap, contiguity) and fact-to-silver reconciliation to the cent. Coverage
is well-targeted, not trivial-field padding. **Improvement:** add explicit business-rule tests
(e.g., `balance_due = total − paid`, non-negative quantities) and consider `dbt-expectations` for
distributional checks.

## 9. Governance Assessment

19 ADRs capture decisions with alternatives and consequences; data dictionaries, source-to-target
mappings, a fix log, and a maintained backlog exist. Ownership/decision-makers are named in ADRs.
**Gaps:** PII enforcement (M3) and formal per-dataset SLA/retention statements are documented in
places but not consistently enforced.

## 10. Security Assessment

Least-privilege RBAC is implemented and real (`pt_ingestion` / `pt_dbt` / `pt_bi_reader`, ADR-019) —
verified that `pt_dbt` cannot even TRUNCATE ingestion-owned tables. `.env` is gitignored, and a scan
found **no** hardcoded credentials in tracked files and **no** secrets in Git history. **Gaps:**
`.env` is not a secret manager (M4), PII is readable by the BI role (M3), and encryption-at-rest /
network TLS are not addressed (acceptable for local, required for production).

## 11. Scalability Assessment

Current scale (tens of thousands of invoices, ~66k lines) is comfortable on single-node Postgres.
At **10×** it remains fine. At **100×**, two pressure points emerge: (a) `fact_retail_sales` reloads
at invoice granularity via delete+insert — a change to any line reloads all lines of that invoice,
and a broad change set means large rewrites; (b) append-only bronze growth (L3). At **1000×**, a
columnar/MPP target or partitioning would be justified — but not before. No premature distribution
is warranted now; the architecture is correctly sized with clearly identified ceilings.

## 12. Reliability Assessment

Idempotent and restartable: re-running a batch hash-skips unchanged rows; the watermark only
advances after tests pass; a crashed run's open batches are swept to `failed` so recovery is clean.
The full teardown-and-rebuild performed during this engagement is direct evidence the platform
recovers to a correct state from bronze + code.

---

## 13. Production Readiness — `PRE-PRODUCTION`

The **data platform** (architecture, modeling, ELT, DQ, governance docs) is `PRODUCTION READY` for
the intended single-node, small-retail-shop deployment. The **operational wrapper** holds it at
`PRE-PRODUCTION`:

- **Blocking:** CI does not test dbt (H1) — regressions can reach `main` undetected.
- **Strongly advised before unattended operation:** failure alerting (M1), container resource
  limits (M2), a proven/automated restore drill (M5).
- **Required before handling real customer PII in production:** masking/retention enforcement (M3)
  and a secret manager (M4).

None of these are architectural rework; they are additive and well-scoped. Close H1 + M1 + M2 and
this is honestly `PRODUCTION READY` for its target scale.

An experienced Senior/Principal engineer would **approve the design** and **conditionally approve
for production** pending the CI dbt gate and basic operational alerting — which is a strong position
for a platform of this size.

---

## 14. Remediation Roadmap

**Phase 1 — Close the gate (do first)**
- H1: add an ephemeral-Postgres CI job running `dbt build` (or `compile` + `test`) on every PR.

**Phase 2 — Production readiness (before unattended operation)**
- M1: DAG `on_failure_callback` → email/Slack.
- M2: per-service `mem_limit`/reservations in compose.
- M5: schedule backups + a periodic restore drill that asserts reconciliation; record RTO/RPO.

**Phase 3 — Governance & security hardening (before real PII)**
- M3: masked BI view layer / column grants + PII retention decision.
- M4: secret manager for the deployed environment.

**Phase 4 — Engineering excellence & scale (as volume grows)**
- L1: ADR decision on `dim_invoice` denormalization fan-out.
- L2: unit tests for `bronze_loader` + `batch_control`.
- L3: bronze retention/partitioning policy.
- Business-rule and distributional dbt tests; rendered lineage/exposures.

---

## 15. Bottom line

Two prior audits were closed with real rigor, and it shows: the correctness-critical machinery is
sound, tested, and reproducible, and the documentation is genuinely excellent. The platform is not
yet production-ready **only** because the automated safety net doesn't run at the CI gate and the
operational alerting/limits aren't in place — not because anything is architecturally wrong. This is
a mature, honestly-documented, well-scoped data platform one short sprint away from production for
its target scale.

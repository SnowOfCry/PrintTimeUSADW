# External Audits

PrintTimeUSA Data Warehouse. Each audit is an independent, evidence-based review of the whole platform against professional and production-readiness standards, run by an external-reviewer agent whose brief is to be skeptical rather than to defend the implementation.

**Format:** each report is anchored to the exact commit it audited and follows Executive Summary → Architecture Assessment → Scorecard (20 categories, 0–5) → Findings (CRITICAL/HIGH/MEDIUM/LOW, each with evidence, impact, and a concrete recommendation) → Production Readiness → Remediation Roadmap.

**Immutable:** an audit is a point-in-time record of what was true at one commit. Superseded reports are kept and marked, never edited or deleted — the trajectory across rounds is the value.

**How to run one:** invoke the `dw-auditor` skill (`.claude/skills/dw-auditor/SKILL.md`). Number the new report `NNN-external-dw-audit.md`, record the commit in its header, mark the previous round as superseded, and add a row here.

**Readiness scale:** `NOT READY` · `EARLY DEVELOPMENT` · `DEVELOPMENT READY` · `PRE-PRODUCTION` · `PRODUCTION READY` · `ENTERPRISE READY`

## Index

| # | Date | Commit | Score | Classification | Headline |
|---|---|---|---|---|---|
| [001](001-external-dw-audit.md) | 2026-07-28 | `2b9433c` (v0.2.0-gold) | 2.80 / 5 | DEVELOPMENT READY | Excellent design and documentation; orchestration, recovery, security and observability unbuilt. 6 HIGH findings. |
| [002](002-external-dw-audit.md) | 2026-07-28 | `15c1c52` (v0.3.0-orchestration) | 3.05 / 5 | DEVELOPMENT READY (upper end) | Pipeline now genuinely runs and gold batches drive real incremental loads. 2 HIGH closed, 1 new: tests run after the watermark commits. *(superseded by 003)* |
| [003](003-external-dw-audit.md) | 2026-08-07 | `8d57789` (develop) | 3.90 / 5 | **PRE-PRODUCTION** | Every prior HIGH closed (SCD2 effective-dating, RBAC, tests-gate-watermark, DR). 1 new HIGH: CI never compiles/tests dbt. Core platform strong; remaining gaps are operational (alerting, resource limits, PII masking, secret manager). |

## Score trajectory

| Category | 001 | 002 | 003 |
|---|---|---|---|
| Architecture | 4 | 4 | **5** |
| Data Modeling | 3 | 3 | **4** |
| Data Quality | 3 | 3 | **4** |
| Incremental Processing | 2 | 3 | **5** |
| Data Governance | 3 | 3 | **4** |
| Data Lineage | 4 | 4 | 4 |
| dbt | 4 | 4 | 4 |
| Airflow | 1 | 3 | **4** |
| Python | 3 | 3 | **4** |
| PostgreSQL | 3 | 3 | **4** |
| Scalability | 3 | 3 | 3 |
| Performance | 3 | 3 | **4** |
| Security | 2 | 2 | **4** |
| Docker / Infrastructure | 3 | 3 | 3 |
| CI/CD | 2 | 2 | 2 |
| Observability | 2 | 3 | **4** |
| Reliability | 2 | 3 | **4** |
| Disaster Recovery | 0 | 0 | **3** |
| Documentation | 5 | 5 | 5 |
| Maintainability | 4 | 4 | **5** |
| **Overall** | **2.80** | **3.05** | **3.90** |

## HIGH findings — status as of round 003

All HIGH findings from rounds 001–002 are now **closed or addressed**. Round 003 raises **one** new
HIGH (CI does not test dbt).

| ID | Finding | First raised | Status at 003 |
|---|---|---|---|
| **AUDIT-003-H1** | CI runs lint/unit/compose-validate but never compiles or tests dbt — the 168 data tests and all model logic are ungated on PRs | 003 | **CLOSED** ([`fix_log.md` FIX-017](../fix/fix_log.md)) — added a `dbt-build` CI job on an ephemeral `postgres:16` that runs the full build + all 168 tests on every PR. Validated: `dbt build` → PASS=213, 0 errors. |
| HIGH-7 | Data-quality tests run *after* the watermark commits | 002 | **CLOSED** — tests now gate the watermark (HIGH-7 / FIX-004); proven a failing test holds the fact batches `running`. Alerting tracked separately (003-M1). |
| HIGH-5 | No disaster recovery | 001 | **ADDRESSED** ([ADR-018](../adr/018-disaster-recovery-and-backup.md)); DR re-scored 0 → 3. Remaining: scheduled/proven restore drill (003-M5). |
| HIGH-3 | SCD2 dated by load date; facts resolve `is_current` | 001 | **CLOSED** — effective-dating by source instant + event-date fact resolution; SCD2 null-guard (FIX-015). Verified: no-overlap / one-current guards green across 5-version chains. |
| HIGH-6 | One all-privilege DB user for every service | 001 | **CLOSED** — least-privilege RBAC ([ADR-019](../adr/019-least-privilege-database-roles.md)): `pt_ingestion` / `pt_dbt` / `pt_bi_reader`. Security re-scored 2 → 4. |
| HIGH-4 | No alerting on failure | 001 | **REDUCED** — failure sweeper + single-active-run added; alerting still open, re-classified MEDIUM (003-M1). |

**Related:** [`docs/adr/`](../adr/README.md) (decisions) · [`docs/fix/fix_log.md`](../fix/fix_log.md) (bugs and their root causes) · [`docs/backlog.md`](../backlog.md) (deferred work) · [`docs/dw_readiness_review.md`](../dw_readiness_review.md) (the earlier internal advisory review)

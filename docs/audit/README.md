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
| [002](002-external-dw-audit.md) | 2026-07-28 | `15c1c52` (v0.3.0-orchestration) | 3.05 / 5 | DEVELOPMENT READY (upper end) | Pipeline now genuinely runs and gold batches drive real incremental loads. 2 HIGH closed, 1 new: tests run after the watermark commits. |

## Score trajectory

| Category | 001 | 002 |
|---|---|---|
| Architecture | 4 | 4 |
| Data Modeling | 3 | 3 |
| Data Quality | 3 | 3 |
| Incremental Processing | 2 | **3** |
| Data Governance | 3 | 3 |
| Data Lineage | 4 | 4 |
| dbt | 4 | 4 |
| Airflow | 1 | **3** |
| Python | 3 | 3 |
| PostgreSQL | 3 | 3 |
| Scalability | 3 | 3 |
| Performance | 3 | 3 |
| Security | 2 | 2 |
| Docker / Infrastructure | 3 | 3 |
| CI/CD | 2 | 2 |
| Observability | 2 | **3** |
| Reliability | 2 | **3** |
| Disaster Recovery | 0 | 0 |
| Documentation | 5 | 5 |
| Maintainability | 4 | 4 |
| **Overall** | **2.80** | **3.05** |

## Open HIGH findings

Carried into round 002 and still open. See the round-002 report for full detail.

| ID | Finding | First raised | Status |
|---|---|---|---|
| HIGH-7 | Data-quality tests run *after* `complete_gold_batches` commits the watermark, so a failing test neither blocks bad data nor notifies anyone | 002 | **Data-integrity part FIXED** (see [`fix_log.md` FIX-004](../fix/fix_log.md)) — tests now gate the watermark; proven a failed test holds it. Alerting still open (see HIGH-4). Pending re-score in round 003. |
| HIGH-5 | No disaster recovery: no backup, no restore procedure, no RPO/RTO, nothing tested | 001 | Open — the sole gate on PRE-PRODUCTION |
| HIGH-3 | SCD2 versions dated by load date, and facts resolve `is_current`, so point-in-time reporting is unachievable | 001 | Open |
| HIGH-6 | One all-privilege database user for every service; ADR-013 §3 access model unimplemented | 001 | Open |
| HIGH-4 | Ingestion is one serial task; no alerting on failure | 001 | Reduced — failure sweeper added; isolation and alerting still open |

**Related:** [`docs/adr/`](../adr/README.md) (decisions) · [`docs/fix/fix_log.md`](../fix/fix_log.md) (bugs and their root causes) · [`docs/backlog.md`](../backlog.md) (deferred work) · [`docs/dw_readiness_review.md`](../dw_readiness_review.md) (the earlier internal advisory review)

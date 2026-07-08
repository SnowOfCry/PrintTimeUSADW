# ADR-013: Data Governance — PII Classification, Access, Retention, and Deletion

- **Status:** Accepted
- **Date:** 2026-07-02
- **Decision-makers:** Jaime Chavez Jr (CEO), Freddy Vazquez (Manager)
- **Proposed by:** Erick Palma (Data Engineer)

## Context

The warehouse holds personal data about California/Arizona/Texas customers and about employees: names, email addresses, phone numbers, and street addresses. As a California company, PrintTimeUSA is subject to the **CCPA/CPRA**, which grants consumers rights over their personal information — including the right to know, and the **right to request deletion**.

The project so far is silent on governance: no column is marked as PII, no access model is defined, and the append-only bronze design (ADR-004) is in direct tension with a deletion request. Because these are compliance and business decisions — not engineering ones — they belong to the CEO and Manager, with Engineering proposing the approach.

The DW's setting lowers the risk: it runs **on company hardware, on-premises, not exposed to the internet** (ADR-002), accessed by one engineer plus a few internal BI users. The same people already have this data in the operational system.

## Decision

### 1. PII classification
Tag every personal-data column in the data dictionaries with a sensitivity level:

| Level | Examples (columns) |
|---|---|
| **PII** | customer/employee `email`, `phone`, person `first_name`/`last_name`/`full_name`, `street_address` |
| **Internal** | business names, city/state/ZIP, product/store/financial data |
| **Public** | reference data (states, statuses, payment methods) |

Rationale: you cannot protect or honor deletion on data you have not first identified. A PII register (the tagged dictionaries) is the cheapest, highest-leverage governance control.

### 2. PII minimization in Gold
Keep raw PII (email, phone) **out of the Gold/BI layer.** The star schema already does this: `dim_customer` and `dim_cashier` carry names and geography but **not** email or phone. Email/phone live only in bronze and silver, which BI users do not query. This is data minimization by design — formalized here as a rule: **new Gold columns must not introduce email/phone or other high-sensitivity PII without explicit sign-off.**

### 3. Access model
| Role | Access |
|---|---|
| Engineering (Erick) | Full — bronze, silver, gold, audit |
| BI / analysts / managers | **Gold read-only** (no email/phone by construction) |
| Application/service accounts | Least privilege per task |

Implemented with PostgreSQL roles/grants: a read-only role on the `gold` schema for BI consumers; `bronze`/`silver` (which hold PII) restricted to engineering.

### 4. Retention & right-to-deletion (the bronze tension)
A verified CCPA deletion request is the **one sanctioned exception to bronze's append-only immutability** (ADR-004). On a validated request:

- the data subject's rows are hard-deleted (or irreversibly anonymized) across **bronze, silver, and gold**;
- the action is **logged in `audit.audit_log`** (who, when, which subject, which tables) — so the erasure itself is auditable even though the data is gone;
- everything else in bronze stays immutable.

General retention (how long to keep old bronze versions) remains deferred (backlog #2) until volume warrants a policy.

### 5. Lineage (already built — recorded as a governance capability)
Every row is traceable: `bronze_batch_id` / `bronze_record_id`, the silver `silver_bronze_record_id` / `silver_batch_id` / `source_*` columns, and `audit.etl_batch_control`. "Where did this value come from and which load produced it?" is answerable by join — a governance requirement this project already satisfies.

### 6. Documentation standards
Decisions live in ADRs; every layer has a data dictionary; every hop has a mapping; naming is standardized. All governance docs are **Markdown in the repo** (diffable, reviewable) — the two remaining `.docx` naming docs are to be converted (backlog #7).

## Alternatives considered

1. **No formal governance (status quo).** Rejected: leaves the company unable to answer a CCPA request or even list where PII lives — a compliance and reputational risk that a tagging exercise removes cheaply.
2. **Mask/encrypt all PII in silver and gold.** The heavy posture. Rejected for now: for an internal, on-prem DW accessed by people who already hold this data in the OLTP, column masking adds friction and breaks legitimate uses (e.g. matching a customer by email) for little real risk reduction. Revisit if PII must reach a less-trusted audience (external sharing, a cloud move — ties to ADR-002).
3. **Adopt a cloud governance/DLP platform (e.g. catalog + policy tooling).** Rejected at this scale/cost — the tagged dictionaries plus PostgreSQL grants cover the need. Revisit alongside any cloud migration.

## Consequences

**Positive**

- The company can answer "what personal data do we hold and where?" and can honor a deletion request with an auditable process.
- BI users never see raw contact PII — minimization is structural, not policy-dependent.
- Access is least-privilege by schema; lineage is already first-class.

**Negative / accepted costs**

- **Deletion breaks bronze immutability for that individual** — the one documented, logged exception. Accepted as a legal obligation that overrides the audit-history principle for the specific data subject only.
- The PII register (tagged dictionaries) and access grants must be maintained as the model evolves — an ownership duty (belongs in the runbook, backlog #8).
- No automated PII discovery — classification is manual; acceptable for a single, well-understood source.

## Related

- ADR-002 (on-prem posture — why risk is lower), ADR-004 (bronze immutability — the deletion tension), ADR-011 (Gold carries no email/phone)
- `docs/data_dictionary/` — where PII tags live; `audit.audit_log` — where erasures are logged
- `docs/backlog.md` #2 (retention), #7 (`.docx` → `.md`), #8 (runbook / ownership)

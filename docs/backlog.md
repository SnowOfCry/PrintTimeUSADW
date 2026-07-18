# Engineering Backlog

PrintTimeUSA Data Warehouse | Deliberately deferred work and open decisions. Each item was consciously postponed — this file exists so "future work" mentioned in ADRs and reviews stays trackable. Review when the trigger condition occurs or when the roadmap (silver → gold → BI) clears.

| # | Item | Context / where it came from | Trigger to act | Effort |
|---|---|---|---|---|
| 1 | Hash-skip for unchanged full-load snapshots | Append-only bronze stacks identical snapshots of the 13 `full_load` tables (~100 redundant rows/run). ADR-004. | Next time `bronze_loader.py` is touched, or after gold ships | ~1 h |
| 2 | Bronze retention/archival policy | Bronze grows monotonically by design. ADR-004. | Bronze size becomes operationally noticeable (backups slow, disk pressure) | Design: ~half day |
| 3 | `dim_customer.customer_county` source | No county column exists in OLTP/bronze/silver; gold defaults to `'Not Provided'`. Readiness review; planned ADR-014. | Business asks for county-level reporting → add ZIP→county reference table | ~half day |
| 4 | PII handling implementation (email/phone) | `customer`/`employee` email + phone are CCPA-relevant PII; no masking/tagging implemented. Governance decision in planned ADR-013. | ADR-013 decision made | Depends on decision |
| 5 | Refund sign convention for `fact_payments` | Refunds chained via `parent_payment_key` risk double-counting in BI SUMs if sign convention undocumented. Readiness review §4. | Before first Power BI/Tableau model ships | ~1 h (doc + check) |
| 6 | Accept or widen `NUMERIC(18,2) → (12,2)` narrowing | Silver money is 18,2; gold is 12,2 (overflow errors if any amount ≥ 10^10). Readiness review §2. | Formal sign-off, or widen gold columns during gold build | ~1 h |
| 7 | Convert naming-convention `.docx` docs to Markdown + reconcile drift | Two `.docx` specs aren't diffable and have drifted from the DDL (unprefixed silver metadata columns; never-built tables like `oltp_location`). Docs audit. | Next documentation pass | ~2 h |
| 8 | Operational runbook + deployment doc | No documented deploy order, backfill/reprocess procedure, backup schedule, or "data ready by HH:MM" delivery SLA. Docs audit; ADR-002 mitigation. (Source-freshness staleness SLA — warn 24h / error 48h on `oltp_*` — is now defined in `_bronze_sources.yml` per ADR-012 §4.) | Before production go-live | ~half day |
| 9 | Unit/integration test coverage for ingestion | Only 3 unit tests (extractor query builders). CI exists; coverage thin. | Alongside silver/gold implementation | Ongoing |
| 10 | Add `po_number` to `gold.dim_invoice` | Not in the current Gold schema; needed for "group payments by PO number" (silver already keeps `silver_po_number`). Silver Validation & Transformation Set §3. | During the Gold build | ~15 min (column + reload) |
| 11 | Invoice-status accumulating-snapshot fact | `dim_invoice` is standard Type 2 (gold-run fidelity); exact status-duration analysis ("avg days in PARTIAL") needs the full transition timeline. `silver.invoice_status_history` (with `changed_at`) is the authoritative source. Gold load strategy §"dim_invoice" decision. | Business asks for exact status-duration / cycle-time reporting | ~half day |

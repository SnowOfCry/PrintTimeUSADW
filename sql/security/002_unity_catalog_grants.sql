-- =============================================================================
-- 002_unity_catalog_grants.sql — Unity Catalog access model (Databricks)
-- -----------------------------------------------------------------------------
-- The Databricks/Azure translation of 001_create_roles.sql (Postgres). Same
-- least-privilege intent (ADR-013 §3 / ADR-019, closes external-audit HIGH-6),
-- expressed with Unity Catalog GRANTs instead of Postgres roles.
--
--   pt_ingestion  — writes BRONZE + AUDIT only          (Python ingestion + the
--                   pipeline's batch-control/watermark tasks). No silver/gold PII.
--   pt_dbt        — reads BRONZE + AUDIT; full control of SILVER + GOLD (dbt needs
--                   to create/replace models). Writes audit_log on fact reloads.
--   pt_bi_reader  — SELECT on GOLD only. No grant on bronze/silver/audit, so BI
--                   consumers STRUCTURALLY cannot read raw contact PII
--                   (silver.customer.silver_email / silver_phone_number).
--                   Unity Catalog denies by default → this is enforcement, not
--                   policy (ADR-013 §2, "minimization is structural").
--
-- KEY DIFFERENCES FROM POSTGRES:
--   * UC privileges are INHERITED: GRANT on a SCHEMA applies to all current AND
--     future tables/views in it — no per-table grants, no ALTER DEFAULT PRIVILEGES.
--   * No separate INSERT/UPDATE — write access is a single privilege: MODIFY.
--     Read is SELECT.
--   * Principals are groups written in backticks (`pt_dbt`), created in the
--     workspace/account Identity settings (NOT here).
--   * "Ownership" of silver/gold is expressed as ALL PRIVILEGES here so the
--     workspace admin stays owner during the POC; in a team/prod workspace you
--     may instead ALTER SCHEMA ... OWNER TO `pt_dbt`.
--
-- ENTITLEMENTS (set in group settings, not here): all three get "Databricks SQL
-- access"; pt_ingestion/pt_dbt also get "Workspace access"; pt_bi_reader does
-- NOT (least privilege). None get Admin.
--
-- IDEMPOTENT: GRANT is additive and safe to re-run.
-- =============================================================================

-- ── 1. Catalog entry (all three) ─────────────────────────────────────────────
GRANT USE CATALOG ON CATALOG printtime_dw TO `pt_ingestion`;
GRANT USE CATALOG ON CATALOG printtime_dw TO `pt_dbt`;
GRANT USE CATALOG ON CATALOG printtime_dw TO `pt_bi_reader`;

-- ── 2. pt_ingestion — write bronze + audit, nothing else ─────────────────────
GRANT USE SCHEMA, SELECT, MODIFY ON SCHEMA printtime_dw.bronze TO `pt_ingestion`;
GRANT USE SCHEMA, SELECT, MODIFY ON SCHEMA printtime_dw.audit  TO `pt_ingestion`;

-- ── 3. pt_dbt — read bronze + audit; OWN (full control of) silver + gold ─────
GRANT USE SCHEMA, SELECT         ON SCHEMA printtime_dw.bronze TO `pt_dbt`;
GRANT USE SCHEMA, SELECT, MODIFY ON SCHEMA printtime_dw.audit  TO `pt_dbt`;  -- writes audit.audit_log on fact reloads
GRANT ALL PRIVILEGES             ON SCHEMA printtime_dw.silver TO `pt_dbt`;
GRANT ALL PRIVILEGES             ON SCHEMA printtime_dw.gold   TO `pt_dbt`;

-- ── 4. pt_bi_reader — SELECT on GOLD ONLY (no bronze/silver/audit → no PII) ───
GRANT USE SCHEMA, SELECT ON SCHEMA printtime_dw.gold TO `pt_bi_reader`;

-- ── 5. Verify (run and eyeball) ──────────────────────────────────────────────
-- SHOW GRANTS `pt_bi_reader` ON SCHEMA printtime_dw.gold;    -- should list SELECT/USE SCHEMA
-- SHOW GRANTS `pt_bi_reader` ON SCHEMA printtime_dw.silver;  -- should be EMPTY (PII guarantee)

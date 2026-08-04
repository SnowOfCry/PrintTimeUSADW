-- =============================================================================
-- 001_create_roles.sql — Least-privilege database roles (RBAC)
-- -----------------------------------------------------------------------------
-- Implements ADR-013 §3 (Access model) and closes external-audit finding HIGH-6
-- ("one all-privilege database user for every service"). Splits the single
-- superuser `warehouse_user` into three least-privilege LOGIN roles so that a
-- compromise of any one service cannot read or write every layer.
--
--   pt_ingestion  — writes BRONZE + AUDIT only          (the Python ingestion +
--                   the DAG's batch-control/watermark tasks). No silver/gold PII.
--   pt_dbt        — reads BRONZE + AUDIT; OWNS SILVER + GOLD (dbt needs full DDL
--                   to create/drop/replace models). Cannot write bronze/audit.
--   pt_bi_reader  — SELECT on GOLD only. No USAGE on bronze/silver/audit, so BI
--                   consumers structurally cannot read raw contact PII
--                   (silver.customer.silver_email / silver_phone_number). This
--                   is the enforcement ADR-013 §2 promised ("minimization is
--                   structural, not policy-dependent").
--
-- `warehouse_user` remains the superuser/owner: admin, pgAdmin, break-glass, and
-- the Airflow metadata connection (database separation for Airflow/SonarQube is
-- audit HIGH-6 phase 2 — tracked separately, out of scope here).
--
-- IDEMPOTENT: safe to re-run. Roles are created only if absent; grants and
-- ownership are re-asserted each run.
--
-- PASSWORDS are supplied as psql variables (never hardcoded here):
--   psql -v ingestion_pw='...' -v dbt_pw='...' -v bi_pw='...' -f 001_create_roles.sql
-- The wrapper scripts/apply_roles.sh reads them from the PT_*_PASSWORD env vars.
--
-- APPLY ORDER: run this AFTER the bronze/silver/gold/audit objects exist (it
-- transfers ownership of existing silver/gold objects and grants on existing
-- tables). On a from-scratch rebuild: create schemas + all layer DDL as
-- warehouse_user first, then run this script. See ADR-019.
-- =============================================================================
\set ON_ERROR_STOP on

-- ── 1. Roles (create if absent, then set password from the psql var) ─────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pt_ingestion') THEN
        CREATE ROLE pt_ingestion LOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pt_dbt') THEN
        CREATE ROLE pt_dbt LOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pt_bi_reader') THEN
        CREATE ROLE pt_bi_reader LOGIN;
    END IF;
END$$;

ALTER ROLE pt_ingestion WITH PASSWORD :'ingestion_pw';
ALTER ROLE pt_dbt       WITH PASSWORD :'dbt_pw';
ALTER ROLE pt_bi_reader WITH PASSWORD :'bi_pw';

-- Explicit CONNECT (don't rely on the PUBLIC default).
GRANT CONNECT ON DATABASE printtime_dw TO pt_ingestion, pt_dbt, pt_bi_reader;

-- ── 2. pt_ingestion — write bronze + audit, nothing else ─────────────────────
GRANT USAGE ON SCHEMA bronze, audit TO pt_ingestion;
GRANT SELECT, INSERT               ON ALL TABLES    IN SCHEMA bronze TO pt_ingestion;
GRANT SELECT, INSERT, UPDATE       ON ALL TABLES    IN SCHEMA audit  TO pt_ingestion;
GRANT USAGE, SELECT, UPDATE        ON ALL SEQUENCES IN SCHEMA bronze TO pt_ingestion;
GRANT USAGE, SELECT, UPDATE        ON ALL SEQUENCES IN SCHEMA audit  TO pt_ingestion;

-- ── 3. pt_dbt — read bronze + audit; OWN silver + gold ───────────────────────
GRANT USAGE  ON SCHEMA bronze, audit TO pt_dbt;
GRANT SELECT ON ALL TABLES IN SCHEMA bronze TO pt_dbt;
GRANT SELECT ON ALL TABLES IN SCHEMA audit  TO pt_dbt;   -- gold facts read audit.etl_batch_control

-- Ownership of silver + gold (schemas and every object in them) so dbt can
-- create / drop / replace models. Transfers existing objects from the prior
-- owner; a no-op for objects pt_dbt already owns.
ALTER SCHEMA silver OWNER TO pt_dbt;
ALTER SCHEMA gold   OWNER TO pt_dbt;
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT n.nspname, c.relname, c.relkind
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname IN ('silver', 'gold')
          AND c.relkind IN ('r', 'v', 'm', 'S', 'p')   -- table, view, matview, sequence, partitioned
    LOOP
        EXECUTE format(
            'ALTER %s %I.%I OWNER TO pt_dbt',
            CASE r.relkind
                WHEN 'v' THEN 'VIEW'
                WHEN 'm' THEN 'MATERIALIZED VIEW'
                WHEN 'S' THEN 'SEQUENCE'
                ELSE 'TABLE'
            END, r.nspname, r.relname);
    END LOOP;
END$$;

-- ── 4. pt_bi_reader — SELECT on gold ONLY (no bronze/silver/audit → no PII) ───
GRANT USAGE  ON SCHEMA gold TO pt_bi_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA gold TO pt_bi_reader;   -- ALL TABLES covers views too

-- ── 5. Default privileges for FUTURE objects (so grants survive new models) ──
-- bronze/audit objects are created by warehouse_user (layer DDL / init):
ALTER DEFAULT PRIVILEGES FOR ROLE warehouse_user IN SCHEMA bronze
    GRANT SELECT, INSERT ON TABLES TO pt_ingestion;
ALTER DEFAULT PRIVILEGES FOR ROLE warehouse_user IN SCHEMA bronze
    GRANT USAGE, SELECT ON SEQUENCES TO pt_ingestion;
ALTER DEFAULT PRIVILEGES FOR ROLE warehouse_user IN SCHEMA audit
    GRANT SELECT, INSERT, UPDATE ON TABLES TO pt_ingestion;
ALTER DEFAULT PRIVILEGES FOR ROLE warehouse_user IN SCHEMA bronze
    GRANT SELECT ON TABLES TO pt_dbt;
ALTER DEFAULT PRIVILEGES FOR ROLE warehouse_user IN SCHEMA audit
    GRANT SELECT ON TABLES TO pt_dbt;
-- silver/gold objects are created by pt_dbt going forward → BI reader must keep
-- reading new gold models automatically:
ALTER DEFAULT PRIVILEGES FOR ROLE pt_dbt IN SCHEMA gold
    GRANT SELECT ON TABLES TO pt_bi_reader;

-- ── 6. Report ────────────────────────────────────────────────────────────────
\echo 'Roles present:'
SELECT rolname, rolcanlogin, rolsuper FROM pg_roles WHERE rolname LIKE 'pt_%' ORDER BY rolname;

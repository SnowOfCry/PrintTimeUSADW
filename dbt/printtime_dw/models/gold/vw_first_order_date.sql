-- =============================================================================
-- gold.vw_first_order_date
-- Role-playing date view (ADR-010): re-labels gold.dim_date for the FIRST ORDER
-- date role, used by gold.dim_customer.first_order_date_key.
-- Spec: sql/gold/002_create_gold_tables.sql (gold.vw_first_order_date)
-- The column aliasing lives in macros/role_playing_date_view.sql (all three
-- views are identical apart from the prefix).
-- =============================================================================
{{ config(materialized='view') }}

{{ role_playing_date_view('first_order') }}

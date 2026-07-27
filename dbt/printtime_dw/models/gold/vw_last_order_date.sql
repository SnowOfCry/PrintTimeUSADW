-- =============================================================================
-- gold.vw_last_order_date
-- Role-playing date view (ADR-010): re-labels gold.dim_date for the LAST ORDER
-- date role, used by gold.fact_customer_behavior_snapshot.last_order_date_key.
-- Spec: sql/gold/002_create_gold_tables.sql (gold.vw_last_order_date)
-- =============================================================================
{{ config(materialized='view') }}

{{ role_playing_date_view('last_order') }}

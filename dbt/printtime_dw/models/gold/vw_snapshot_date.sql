-- =============================================================================
-- gold.vw_snapshot_date
-- Role-playing date view (ADR-010): re-labels gold.dim_date for the SNAPSHOT
-- date role, used by gold.fact_customer_behavior_snapshot.snapshot_date_key.
-- Spec: sql/gold/002_create_gold_tables.sql (gold.vw_snapshot_date)
-- =============================================================================
{{ config(materialized='view') }}

{{ role_playing_date_view('snapshot') }}

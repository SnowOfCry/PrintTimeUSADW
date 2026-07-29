-- =============================================================================
-- gold.bi_dim_invoice — INVOICE dimension for BI (ADR-017)
-- One row per invoice version (SCD2). Slicing attributes only — invoice number,
-- PO number (enables "group payments by PO", backlog #10), and status. The
-- invoice's customer/store are reached through the facts' own conformed
-- dimensions, so they are intentionally NOT duplicated here. invoice_total is
-- omitted: it is an invoice-grain figure that would double-count if summed
-- across the sales lines that relate to it. Audit/DQ/SCD2 plumbing hidden.
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi']) }}

select
    invoice_key,
    invoice_number,
    po_number,
    invoice_status,
    is_current
from {{ ref('dim_invoice') }}

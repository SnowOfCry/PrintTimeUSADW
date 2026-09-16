-- =============================================================================
-- gold.bi_dim_customer_contact — MASKED customer contact for BI (AUDIT-003-M3)
-- -----------------------------------------------------------------------------
-- Surfaces email/phone to the BI layer in MASKED form ONLY. Raw PII never leaves
-- silver: pt_bi_reader has no silver/bronze access, and gold carries no raw PII.
-- This view reads silver but is OWNED by pt_dbt, so a BI role selecting from it
-- runs with the owner's rights and receives only the masked expressions — never
-- the raw columns. This is the sanctioned way to show contact info downstream.
--   email : first char + ***@domain      e.g.  a***@example.com
--   phone : last 4 digits only           e.g.  ***-***-1234
-- Governance: ADR-013. NEVER add raw email/phone to any gold model or view.
-- =============================================================================
{{ config(materialized='view', tags=['gold', 'bi', 'pii-masked']) }}

select
    cast(silver_customer_account_no as string)                 as customer_id,
    cast(silver_customer_name as string)                      as customer_name,
    cast(case
        when silver_email is null or silver_email = '' then null
        else left(silver_email, 1) || '***@' || split_part(silver_email, '@', 2)
    end as string)                                       as email_masked,
    cast(case
        when silver_phone_number is null then null
        else '***-***-' || right(regexp_replace(silver_phone_number, '\\D', ''), 4)
    end as string)                                        as phone_masked
from {{ ref('customer') }}
where silver_is_deleted_flag = false

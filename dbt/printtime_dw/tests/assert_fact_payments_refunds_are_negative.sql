-- =============================================================================
-- Singular test: every refund in fact_payments is stored as a NEGATIVE amount.
-- -----------------------------------------------------------------------------
-- Protects the refund-sign convention the fact documents (ADR-009 / audit MED-5):
-- refunds carry a resolved parent_payment_key (pointing at the payment they
-- reverse) and are stored with a negative payment_amount, so SUM(payment_amount)
-- NETS refunds automatically. A refund stored non-negative would double-count the
-- reversal in every downstream revenue/collections measure.
--
-- A refund = a row whose parent_payment_key resolves to a real parent (not NULL
-- and not the -1 Not Provided member). Fails (returns rows) if any such row has a
-- non-negative amount.
-- =============================================================================
select
    payment_key,
    parent_payment_key,
    payment_amount
from {{ ref('fact_payments') }}
where parent_payment_key is not null
  and parent_payment_key <> -1
  and payment_amount >= 0

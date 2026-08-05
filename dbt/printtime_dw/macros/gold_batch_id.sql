{% macro gold_batch_id() -%}
{#-
  Resolve THIS gold model's ETL batch id from the {target: batch_id} map the DAG
  passes via `--vars gold_batch_ids` (MED-10). Facts use their own target
  ('gold.<model>'); every SCD2 dimension shares the single 'gold.dimensions'
  batch (ADR-008 — dimensions load as one batch), so they all resolve to it.

  Gold stamps the TEXT batch_id (joins audit.etl_batch_control.batch_id per the
  gold naming convention), NOT the integer batch_key that silver stamps.

  Falls back to '-1' for ad-hoc `dbt run --select gold` outside the DAG (no var
  set), mirroring silver's -1 convention so ad-hoc runs never error.

  Emits a bare token; the model quotes it:  '{{ gold_batch_id() }}'::varchar(50)
-#}
{%- set ids = var('gold_batch_ids', {}) -%}
{%- set target = ('gold.' ~ this.identifier) if this.identifier.startswith('fact_') else 'gold.dimensions' -%}
{{- ids.get(target, '-1') -}}
{%- endmacro %}

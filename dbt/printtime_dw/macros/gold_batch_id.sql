{% macro require_batch_id(name) -%}
{#-
  Return the batch var `name` if supplied. On run/build — the operations that
  actually PERSIST a batch_id into a row — a missing var raises a LOUD compile
  error rather than silently stamping a -1 sentinel that would pollute an
  otherwise-trustworthy lineage column (MED-12: a sentinel mixed with real
  values invites false trust). For compile / parse / docs (which persist
  nothing) it returns -1 as a harmless placeholder, so those operations don't
  require the var. The orchestration DAG always supplies the var; ad-hoc
  `dbt run` must too.
-#}
{%- set v = var(name, none) -%}
{%- if v is not none -%}
{{- v -}}
{%- elif execute and flags.WHICH in ['run', 'build'] -%}
{#- `execute` is false during parse (all models render) and true only when a
    SELECTED model is actually being built — so this raises only for a model
    being run without its batch var, not for unselected models during parse. -#}
{{ exceptions.raise_compiler_error(name ~ " is required for run/build — pass --vars " ~ name ~ "=<batch key>. The orchestration DAG supplies it; ad-hoc runs must too.") }}
{%- else -%}
{{- -1 -}}
{%- endif -%}
{%- endmacro %}


{% macro gold_batch_id() -%}
{#-
  Resolve THIS gold model's ETL batch id from the {target: batch_id} map the DAG
  passes via `--vars gold_batch_ids` (MED-10). Facts use their own target
  ('gold.<model>'); every SCD2 dimension shares the single 'gold.dimensions'
  batch (ADR-008 — dimensions load as one batch), so they all resolve to it.

  Gold stamps the TEXT batch_id (joins audit.etl_batch_control.batch_id per the
  gold naming convention), NOT the integer batch_key that silver stamps.

  Loud on run/build if the map is absent (MED-12) — no silent '-1' in persisted
  gold rows; '-1' is emitted only for compile/parse/docs, which persist nothing.

  Emits a bare token; the model quotes it:  '{{ gold_batch_id() }}'::varchar(50)
-#}
{%- set ids = var('gold_batch_ids', none) -%}
{%- if ids is none and execute and flags.WHICH in ['run', 'build'] -%}
{{ exceptions.raise_compiler_error("gold_batch_ids is required for run/build — pass --vars gold_batch_ids={...}. The orchestration DAG supplies it; ad-hoc gold runs must too.") }}
{%- elif ids is none -%}
{{- '-1' -}}
{%- else -%}
{%- set target = ('gold.' ~ this.identifier) if this.identifier.startswith('fact_') else 'gold.dimensions' -%}
{{- ids.get(target, '-1') -}}
{%- endif -%}
{%- endmacro %}

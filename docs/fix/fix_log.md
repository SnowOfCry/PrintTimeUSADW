# Fix Log

PrintTimeUSA Data Warehouse. Bugs that actually bit us, what caused them, and the **class of
mistake** each one belongs to — so the same shape of bug is recognizable next time.

This is deliberately not a changelog. An entry earns its place only if the root cause was
non-obvious or the fix taught a reusable rule. Newest first.

**Related:** `docs/adr/` (decisions), `docs/dbt/dbt_decisions.md` (dbt implementation log),
`docs/backlog.md` (deferred work).

---

## FIX-003 — `batch_id` uniqueness depended on the wall clock advancing

| | |
|---|---|
| **Found** | 2026-07-28, while writing the regression test for **FIX-002** |
| **Symptom** | Latent — never fired in production. Surfaced as a failing unit test: 50 ids generated in a tight loop were not all distinct. |
| **Would have surfaced as** | `UniqueViolation` on `uq_etl_batch_control_batch_id`, failing a DAG task |
| **Affected** | `ingestion/utils/batch_control.py` → `build_batch_id()` |
| **Severity** | Low probability, task-fatal impact |

### Cause

`batch_id` derives its uniqueness entirely from a microsecond timestamp:

```python
suffix = f":{int(datetime.now().timestamp() * 1_000_000)}"
```

That is only unique if the clock actually advances between calls. It does not always: the DAG's
`_start_gold_batches` opens **four batches in a tight loop**, and any two landing in the same
microsecond produce identical ids and collide against the UNIQUE constraint.

It had never fired because each call happens to make a DB round trip (~1 ms), which is far longer
than the clock's resolution. That is luck, not design — the guarantee lived in the *timing of an
unrelated I/O call*, not in the code.

### How it was found

This is the interesting part. FIX-002 recurred precisely because the id-building was **inline
inside `start_batch()`**, which opens a database connection and therefore could not be unit
tested. Closing FIX-002 properly meant extracting a pure `build_batch_id()` so the width
guarantee could be asserted.

The moment it became testable, a *different* assertion failed — the uniqueness one. The original
bug had been hiding a second defect in the same function.

### Fix

Make the epoch strictly increasing per process, independent of clock resolution:

```python
_epoch_lock = threading.Lock()
_last_epoch_micros = 0

def _next_epoch_micros() -> int:
    global _last_epoch_micros
    with _epoch_lock:
        now = int(datetime.now().timestamp() * 1_000_000)
        if now <= _last_epoch_micros:
            now = _last_epoch_micros + 1
        _last_epoch_micros = now
        return now
```

The lock matters because Airflow may run tasks concurrently; across separate processes the wall
clock still separates them. Verified with 500 ids generated in a tight loop — all distinct and
monotonically increasing (`tests/unit/test_batch_control.py`).

### Rule

> **A bug you cannot unit test will come back.** If fixing something requires extracting it into a
> pure function to make it testable, that extraction *is* part of the fix — and the new test may
> well find a second defect the original bug was hiding.

A companion rule from the cause itself:

> **Don't let a correctness guarantee rest on incidental timing.** If uniqueness depends on "the
> clock will have moved by then", it depends on how fast the surrounding code happens to run.

---

## FIX-002 — `batch_id` overflowed `VARCHAR(50)` on gold target names

| | |
|---|---|
| **Found** | 2026-07-28, first orchestrated gold run (`start_gold_batches` task) |
| **Symptom** | `psycopg2.errors.StringDataRightTruncation: value too long for type character varying(50)` |
| **Affected** | `ingestion/utils/batch_control.py` → `start_batch()` |
| **Severity** | Blocked the whole gold half of the DAG |

### Cause

`batch_id` was built by plain concatenation:

```python
batch_id = f"{target_table}:{epoch_micros}"
```

The longest gold target overflows the column:

```
gold.fact_customer_behavior_snapshot   36
:                                       1
1785273477728790                       16   (epoch microseconds)
                                     ────
                                       53   > VARCHAR(50)
```

Bronze never triggered it — its longest name (`oltp_customer_status_history`, 28 chars) totals
45. The bug lay dormant through the entire bronze and silver phase and only fired when gold
introduced longer table names.

**The aggravating detail:** the line above it already said *"Keep batch_id within VARCHAR(50)"*.
The intent was documented; nothing enforced it. A comment is a wish — only code is a guarantee.

**This was the second occurrence of the same class.** An earlier version used
`{pipeline}:{table}:{epoch_ms}` and overflowed during the bronze build. That fix shortened the
*format* (dropped `pipeline`) — it removed the symptom for the names that existed at the time,
but never added enforcement, so the bug simply waited for longer names.

### Fix

```python
_BATCH_ID_MAX_LEN = 50          # matches audit.etl_batch_control.batch_id

suffix   = f":{int(datetime.now().timestamp() * 1_000_000)}"
batch_id = f"{target_table[: _BATCH_ID_MAX_LEN - len(suffix)]}{suffix}"
```

Three deliberate choices:

1. **Trim the prefix, never the suffix.** The epoch is what makes the id UNIQUE; truncating it
   would risk collisions against `uq_etl_batch_control_batch_id`. The readable prefix is the safe
   thing to lose.
2. **No information is lost.** The full name is stored in `target_table VARCHAR(100)`;
   `batch_id` is only an external identifier.
3. **The limit is a named constant tied to the DDL**, not a magic number inside an f-string.

Longest name now lands at exactly 50: `gold.fact_customer_behavior_snaps:1785273477728790`

### Rule

> **When a string is assembled from variable-length parts and stored in a fixed-width column,
> the code must enforce the width.** If a comment states a constraint, there should be a constant
> enforcing it.

Habits that would have caught it:

- **Test with the longest realistic input**, not a convenient one. `state` (5 chars) passes
  everything; `gold.fact_customer_behavior_snapshot` is the honest test.
- **Fix the class, not the instance.** The first overflow was patched by shortening the format;
  had it been patched with enforcement, there would have been no second occurrence.

**Follow-up:** writing the regression test for this fix exposed a second, independent defect in
the same function — see **FIX-003**.

---

## FIX-001 — dbt `PermissionError` writing `logs/` and `target/` under Airflow

| | |
|---|---|
| **Found** | 2026-07-28, first orchestrated `run_dbt_silver` task |
| **Symptom** | `PermissionError: [Errno 13] Permission denied: '/dbt/printtime_dw/logs/dbt.log'` |
| **Affected** | Airflow ↔ dbt (`docker-compose.yml`) |
| **Severity** | Blocked every dbt task in the DAG |

### Cause

dbt always writes `logs/dbt.log` and `target/` next to the project. That project directory is
mounted into **two different services that run as different users**:

```
./dbt/printtime_dw  →  dbt container      (its own user)
./dbt/printtime_dw  →  airflow containers (user "airflow", uid 50000)
```

Earlier ad-hoc `docker compose run --rm dbt ...` invocations created `logs/` and `target/` owned
by the dbt container's user. When Airflow later tried to write there, the OS refused.

Note the failure happened **before a single model ran** — dbt initializes logging first — so the
error had nothing to do with the SQL, which made the message initially misleading.

### Fix

Give Airflow its own artifact location rather than contend for the shared one (dbt-native env
vars, so no code changed):

```yaml
DBT_LOG_PATH:    /opt/airflow/dbt_artifacts/logs
DBT_TARGET_PATH: /opt/airflow/dbt_artifacts/target
```

`/opt/airflow/` lives inside the Airflow container and is owned by the airflow user. The DAG
reads `run_results.json` from the matching path
(`/opt/airflow/dbt_artifacts/target/run_results.json`).

**Second benefit:** orchestrated and ad-hoc runs no longer overwrite each other's
`run_results.json`. Had they shared it, a DAG task could have reported row counts from a manual
run — a silent data-quality lie in the audit log.

### Rule

> **When one host folder is mounted into containers that run as different users, whoever writes
> first owns it.** Give each writer its own path; don't reach for `chmod 777`.

Watch for this whenever a second service starts mounting an existing volume, or when
`Permission denied` appears on a path that demonstrably exists.

---

## Earlier fixes (condensed)

Kept short — each was resolved during the build and is recorded in the relevant commit.

| Area | Symptom | Cause & fix |
|---|---|---|
| Ingestion | `'Engine' object has no attribute 'cursor'` | pandas 2.2 requires SQLAlchemy ≥2.0 connectables; Airflow 2.9.3 pins SQLAlchemy 1.4. Pinned `pandas==2.1.4`. |
| Ingestion | Bronze loader OOM on `invoice_line` (390k rows) | Whole frame converted + buffered at once. Chunked at 20k rows (`LOAD_CHUNK_ROWS`). |
| Ingestion | `invalid input syntax for type json` | NULL numerics became float `NaN`, which Postgres JSON rejects. `df.astype(object).where(df.notna(), None)`. |
| dbt | `create schema if not exists ""` | `generate_schema_name` macro lost its `{%- else -%}` branch, so it returned an empty string. Restored the branch. |
| dbt | Model built but constraints missing | `CREATE TABLE AS SELECT` silently drops `NOT NULL`/PK. Enabled model **contracts** (declare-then-insert). |
| dbt | `on_schema_change 'ignore' invalid` | incremental + contract forbids the default. Chose `'fail'` — schema drift should be loud. |
| dbt | `--full-refresh` passed, incremental run failed | A `::text` cast vs a `varchar(100)` contract. The full refresh coerced it; the incremental insert did not. **Always test both paths.** |
| Gold | SCD2 dim collapsed to one row per key | `incremental_strategy='merge'` overwrites in place = Type 1. SCD2 requires `append` + a post-hook to close the prior version (ADR-015). |

---

## How to add an entry

Add a numbered section at the top (newest first) with: symptom, cause, fix, and — the part that
matters most — the **rule** it generalizes to. If a bug produced no reusable rule, it probably
belongs in a commit message rather than here.

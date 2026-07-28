# ADR-016: Run dbt Inside the Airflow Image (BashOperator) Rather Than DockerOperator

- **Status:** Accepted
- **Date:** 2026-07-28
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Informed:** Jaime Chavez Jr (CEO)

## Context

ADR-003 put every transformation in dbt, and ADR-002 put the whole stack in Docker Compose on a
single host. The DAG (`printtime_elt_pipeline`) therefore has to *execute dbt* — but the DAG ran
against a stack where dbt lived in its own service, `docker/dbt`, which Airflow had no way to
invoke. The DAG's dbt tasks were written but had never run: dbt was not installed in the Airflow
image, the project was not mounted there, and no `DBT_*` connection variables were passed.

So "how does Airflow run dbt?" was an open architectural question, not a detail. It determines
how every future transformation task executes, and it is awkward to change later because task
definitions, image contents, and mounts all move together.

Two constraints shaped the choice:

1. **Version drift between orchestrated and ad-hoc runs would be a silent correctness risk.** If
   the DAG ran a different dbt version than a developer's manual run, the same model could
   produce different SQL.
2. **This is a single-host local stack** (ADR-002), run on Windows/Docker Desktop, not a
   Kubernetes cluster — so the cost of container-orchestration machinery is high relative to its
   benefit here.

## Decision

**Install dbt in the Airflow image and invoke it with `BashOperator`.**

- `dbt-core==1.8.7` and `dbt-postgres==1.8.2` are added to `docker/airflow/requirements.txt`,
  **pinned identically** to `docker/dbt/requirements.txt`. The comment in both files states that
  they must move together.
- The dbt project is mounted into the Airflow services at the **same path** the dbt service uses
  (`./dbt/printtime_dw:/dbt/printtime_dw`), so commands are copy-pasteable between the two.
- `DBT_HOST/PORT/DATABASE/USER/PASSWORD/SCHEMA` are added to the Airflow environment; the
  existing `profiles.yml` already reads them via `env_var()`, so no dbt config changed.
- **dbt writes its artifacts to an Airflow-local path**, not into the mounted project:
  `DBT_LOG_PATH=/opt/airflow/dbt_artifacts/logs`,
  `DBT_TARGET_PATH=/opt/airflow/dbt_artifacts/target`.
- The dedicated `dbt` service is **kept** for ad-hoc developer use (`docker compose run --rm dbt
  dbt build --select silver`).

The artifact isolation is part of the decision, not an incidental bug fix (see FIX-001):
the mounted project's `logs/` and `target/` are owned by the dbt container's user, so Airflow
cannot write them; and even with permissions solved, a shared `target/run_results.json` would let
a manual run's row counts be recorded against an orchestrated batch — a silent lie in the audit
log.

## Alternatives considered

1. **`DockerOperator` — Airflow launches the existing dbt image per task.** The most appealing
   option on paper: zero dbt duplication, one image, no version-drift risk, and the
   `apache-airflow-providers-docker` package is already installed. Rejected for this stack: it
   requires mounting the host Docker socket into the Airflow containers, which grants Airflow
   effective root on the host and is awkward and flaky on Docker Desktop for Windows. That is a
   real security and portability cost to avoid duplicating two pinned lines. **Revisit if** the
   stack moves to Kubernetes (where `KubernetesPodOperator` is the natural, socket-free
   equivalent) or to a multi-host deployment.
2. **`astronomer-cosmos` (renders dbt models as native Airflow tasks).** Genuinely attractive —
   per-model task granularity, retries and observability at model level rather than one opaque
   `dbt run`. Rejected for now: it adds a substantial dependency and a second source of truth for
   the DAG's shape, for observability we do not yet need at 34 models that build in seconds.
   Revisit if per-model retry/lineage in the Airflow UI becomes a real operational need.
3. **dbt Cloud / a hosted scheduler.** Rejected as inconsistent with ADR-002 (the whole point of
   the local Docker stack is no per-seat SaaS cost) and it would split orchestration across two
   systems.
4. **Airflow calls dbt over SSH / a sidecar API.** Rejected as unnecessary indirection for
   processes on the same host.

## Consequences

**Positive**

- The DAG runs dbt with no new infrastructure, no socket exposure, and no container-in-container
  complexity.
- Commands are identical in both contexts because the project path matches, so a task that works
  in the dbt container works verbatim in the DAG.
- Artifact isolation means orchestrated and ad-hoc runs cannot corrupt each other's
  `run_results.json` — which the DAG reads to record row counts in `audit.etl_batch_control`.
- The dedicated dbt service still exists for interactive work, so the developer workflow is
  unchanged.

**Negative / accepted costs**

- **dbt is pinned in two files that must stay identical.** This is the real cost of the choice.
  Mitigation: both files carry a comment naming the other; a version bump is a two-file change.
  If they ever drift, the DAG and manual runs could compile the same model differently.
- The Airflow image is larger and slower to build (dbt-core plus its dependency tree).
- dbt's own logs live outside the project directory, so debugging an orchestrated run means
  reading the Airflow task log (which captures dbt's stdout) rather than `logs/dbt.log`.
- Airflow and dbt now share a Python environment, so a future dependency conflict between them is
  possible. None exists today; both pin their own requirements.

## Related

- ADR-002 (local Docker stack — why not cloud/hosted), ADR-003 (ELT — dbt owns transformations),
  ADR-008 (batch control in the audit schema — what the DAG's batch tasks write)
- `docs/fix/fix_log.md` — FIX-001 (artifact-path permissions), FIX-002 (`batch_id` overflow)
- `airflow/dags/printtime_elt_pipeline.py` — the DAG this decision enables
- `docker/airflow/requirements.txt` and `docker/dbt/requirements.txt` — the paired pins

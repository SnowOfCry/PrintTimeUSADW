FROM apache/airflow:2.9.3-python3.11

# Switch to root only for system packages, then back to airflow user.
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
        postgresql-client-16 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
# postgresql-client-16 (pinned to the warehouse server version — a newer client
# emits PG17+ SET params like transaction_timeout that PG16 rejects on restore)
# provides pg_dump/pg_restore/psql for the scheduled backup DAG
# (Airflow can't `docker exec` into the postgres container — ADR-016 — so it runs
#  these client tools against the warehouse over the docker network instead).

USER airflow

# Install extra Python dependencies.
COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt

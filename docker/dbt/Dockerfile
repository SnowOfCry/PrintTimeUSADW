FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        libpq-dev \
        build-essential \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt

# dbt project is mounted at runtime — no COPY needed here.
WORKDIR /dbt

# Default command: run all models. Override in docker-compose or Airflow tasks.
CMD ["dbt", "run"]

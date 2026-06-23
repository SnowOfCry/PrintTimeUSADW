FROM apache/airflow:2.9.3-python3.11

# Switch to root only for system packages, then back to airflow user.
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

USER airflow

# Install extra Python dependencies.
COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt

FROM postgres:16

# Copy initialization scripts into the Docker entrypoint init directory.
# Scripts are executed in alphabetical order on first container start.
COPY init/ /docker-entrypoint-initdb.d/

# Healthcheck so Docker Compose knows when Postgres is ready.
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
    CMD pg_isready -U ${POSTGRES_USER:-warehouse_user} -d ${POSTGRES_DB:-printtime_dw}

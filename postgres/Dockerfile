FROM postgres:17.0


# Copy configs
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY pg_hba.conf /etc/postgresql/pg_hba.conf

# To add more databases later, just add more lines in this Dockerfile:
# echo '    CREATE DATABASE your_app_name;' >> /docker-entrypoint-initdb.d/10-create-dbs.sh && \
# echo '    GRANT ALL PRIVILEGES ON DATABASE your_app_name TO "$POSTGRES_USER";' >> /docker-entrypoint-initdb.d/10-create-dbs.sh && \

# Create init script that uses ENV variables
RUN echo '#!/bin/bash' > /docker-entrypoint-initdb.d/10-create-dbs.sh && \
    echo 'set -e' >> /docker-entrypoint-initdb.d/10-create-dbs.sh && \
    echo 'psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL' >> /docker-entrypoint-initdb.d/10-create-dbs.sh && \
    echo '    CREATE DATABASE ${KEYCLOAK_DB_NAME};' >> /docker-entrypoint-initdb.d/10-create-dbs.sh && \
    echo '    GRANT ALL PRIVILEGES ON DATABASE ${KEYCLOAK_DB_NAME} TO "$POSTGRES_USER";' >> /docker-entrypoint-initdb.d/10-create-dbs.sh && \
    echo '    CREATE DATABASE ${PHARMACY_DB};' >> /docker-entrypoint-initdb.d/10-create-dbs.sh && \
    echo '    GRANT ALL PRIVILEGES ON DATABASE ${PHARMACY_DB} TO "$POSTGRES_USER";' >> /docker-entrypoint-initdb.d/10-create-dbs.sh && \
    echo 'EOSQL' >> /docker-entrypoint-initdb.d/10-create-dbs.sh && \
    chmod +x /docker-entrypoint-initdb.d/10-create-dbs.sh

EXPOSE ${POSTGRES_PORT}

CMD ["postgres","-c","config_file=/etc/postgresql/postgresql.conf"]


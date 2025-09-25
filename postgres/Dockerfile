FROM postgres:17.0

ENV POSTGRES_DB=clinic-mouzaia-hub \
    POSTGRES_USER=admin \
    POSTGRES_PASSWORD=admin \
    LANG=en_US.utf8 \
    LC_ALL=en_US.utf8 \
    TZ=Africa/Algiers

# Copy configs
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY pg_hba.conf /etc/postgresql/pg_hba.conf

EXPOSE 5432

CMD ["postgres","-c","config_file=/etc/postgresql/postgresql.conf"]


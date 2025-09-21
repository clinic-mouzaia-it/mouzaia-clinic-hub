-- Postgres init script for Keycloak out-of-the-box setup
DO
$do$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'keycloak_user') THEN
      CREATE ROLE keycloak_user LOGIN PASSWORD 'keycloak_pass';
   END IF;
END
$do$;

CREATE DATABASE clinic_keycloak OWNER keycloak_user;

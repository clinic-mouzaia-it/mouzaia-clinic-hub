#!/usr/bin/env bash
set -euo pipefail

NETWORK_NAME=web
POSTGRES_VOLUME=clinic-hub-postgres-db-data
KEYCLOAK_VOLUME=clinic-hub-keycloak-data

echo "[clinic-hub] Ensuring network '$NETWORK_NAME' exists..."
docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || docker network create "$NETWORK_NAME"

echo "[clinic-hub] Ensuring volume '$POSTGRES_VOLUME' exists..."
docker volume inspect "$POSTGRES_VOLUME" >/dev/null 2>&1 || docker volume create "$POSTGRES_VOLUME" >/dev/null

echo "[clinic-hub] Ensuring volume '$KEYCLOAK_VOLUME' exists..."
docker volume inspect "$KEYCLOAK_VOLUME" >/dev/null 2>&1 || docker volume create "$KEYCLOAK_VOLUME" >/dev/null

start_or_replace() {
    local name="$1"
    shift
    if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
        echo "[clinic-hub] Removing existing container: $name"
        docker rm -f "$name" >/dev/null 2>&1 || true
    fi
    echo "[clinic-hub] Starting: $name"
    docker run -d --restart unless-stopped --name "$name" --network "$NETWORK_NAME" "$@"
}

echo "[clinic-hub] Starting Postgres..."
start_or_replace db -p 5432:5432 -v "$POSTGRES_VOLUME:/var/lib/postgresql/data" clinic-hub-postgres:v0.1.0

echo "[clinic-hub] Waiting for Postgres to be ready..."
until docker exec db pg_isready -U admin >/dev/null 2>&1; do
    sleep 1
done

echo "[clinic-hub] Starting Keycloak..."
start_or_replace keycloak -v "$KEYCLOAK_VOLUME:/opt/keycloak/data" clinic-hub-keycloak:v0.1.0

echo "[clinic-hub] Starting KrakenD..."
start_or_replace krakend -p 8080:8080 clinic-hub-krakend:v0.1.0

echo "[clinic-hub] Starting Traefik..."
start_or_replace traefik -p 80:80 clinic-hub-traefik:v0.1.0

echo "[clinic-hub] All services are up."
echo "Traefik:  http://hubtraefik.mouzaiaclinic.local (admin/admin)"
echo "Keycloak: http://hubkeycloak.mouzaiaclinic.local (admin/admin)"
echo "KrakenD Gateway: http://hubapi.mouzaiaclinic.local"
echo "Postgres: host hubpostgres.mouzaiaclinic.local, port 5432, db clinic-mouzaia-hub, user admin, password admin"

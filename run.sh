#!/usr/bin/env bash
set -euo pipefail

# Run stack with Docker Compose, using positional syntax: action then services

usage() {
  cat <<'USAGE'
Usage: bash run.sh [action] [services...]

Actions (default: up):
  build               Build images for selected services (or all if none)
  up                  Bring up services (detached)
  down                Stop and remove services; with no services, bring the whole stack down
  restart             Restart services (or all if none)
  kill                Force stop services
  remove              Remove stopped service containers

Examples:
  bash run.sh up                              # up all
  bash run.sh up keycloak postgres            # up only Keycloak and Postgres
  bash run.sh down keycloak postgres          # stop and remove only those services
  bash run.sh restart                         # restart all
  bash run.sh build identity-service          # build only identity-service
USAGE
}

# Determine compose command (Docker Compose v2 preferred)
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  echo "Error: Docker Compose is required. Install Docker Desktop or docker-compose plugin." >&2
  exit 1
fi

ACTION="${1:-up}"
if [[ "$ACTION" == "-h" || "$ACTION" == "--help" ]]; then
  usage; exit 0
fi
shift || true
SERVICES=("$@")

# Helper to conditionally append services
compose_with_services() {
  if [[ ${#SERVICES[@]} -gt 0 ]]; then
    "${COMPOSE_CMD[@]}" "$@" "${SERVICES[@]}"
  else
    "${COMPOSE_CMD[@]}" "$@"
  fi
}

case "$ACTION" in
  up)
    echo "[clinic-hub] Bringing up services (detached)..."
    compose_with_services up -d --remove-orphans
    ;;
  down)
    if [[ ${#SERVICES[@]} -eq 0 ]]; then
      echo "[clinic-hub] Bringing down the entire stack..."
      "${COMPOSE_CMD[@]}" down
    else
      echo "[clinic-hub] Stopping selected services..."
      compose_with_services stop
      echo "[clinic-hub] Removing selected service containers..."
      compose_with_services rm -fsv
    fi
    ;;
  restart)
    echo "[clinic-hub] Restarting services..."
    compose_with_services restart
    ;;
  kill)
    echo "[clinic-hub] Force stopping services..."
    compose_with_services kill
    ;;
  remove)
    echo "[clinic-hub] Removing service containers..."
    compose_with_services rm -fsv
    ;;
  build)
    compose_with_services build
    ;;
  *)
    echo "Unknown action: $ACTION" >&2
    usage; exit 2 ;;
esac

if [[ "$ACTION" == "up" ]]; then
  echo
  echo "[clinic-hub] Services are starting. If it's the first run, Postgres initialization can take ~10-20s."
  echo "Traefik:  http://hubtraefik.mouzaiaclinic.local"
  echo "Keycloak: http://hubkeycloak.mouzaiaclinic.local"
  echo "Postgres: host hubpostgres.mouzaiaclinic.local"
  echo "Krakend: http://hubapi.mouzaiaclinic.local"
fi


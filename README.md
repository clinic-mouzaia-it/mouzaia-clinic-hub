## Mouzaia Clinic Hub

Minimal, offline-ready stack with three containers: Traefik, Keycloak, and Postgres. All credentials and configs are baked into the images so end users only need the images to run.

### What’s included
- Traefik v3.5.2 (HTTP only)
  - Dashboard protected with basic auth (admin/admin)
  - Routes:
    - `hubtraefik.mouzaiaclinic.local` → Traefik dashboard
    - `hubkeycloak.mouzaiaclinic.local` → Keycloak service
- Keycloak 26.3 (vanilla)
  - Runs on HTTP 8080 behind Traefik
  - Admin: `admin` / `admin` (baked)
  - DB connection pre-configured to the `db` container
- Postgres 17.0
  - DB: `clinic-mouzaia-hub`
  - User: `admin` / `admin` (baked)
  - Timezone: Africa/Algiers, scram auth enforced

### Hostname/DNS requirement
Configure your DNS (e.g., pfSense) to resolve these hostnames to the Docker host IP:
- `hubtraefik.mouzaiaclinic.local`
- `hubkeycloak.mouzaiaclinic.local`
- `hubpostgres.mouzaiaclinic.local`

No TLS in this setup; everything runs over HTTP on port 80. Postgres is exposed on 5432.

### Build images (maintainer)
From the project root:
```bash
docker compose build
```

This builds three images with pinned tags:
- `clinic-hub-traefik:v0.1.0`
- `clinic-hub-keycloak:v0.1.0`
- `clinic-hub-postgres:v0.1.0`

Note: Credentials are baked in via the Dockerfiles. No .env files are required for build or runtime.

### Run everything (end user) – one command
You don’t need docker compose to run. Use the included script:
```bash
bash run.sh
```

The script will:
- Create a `web` Docker network if missing
- Create two named volumes (data persists across restarts):
  - `clinic-hub-postgres-db-data` → `/var/lib/postgresql/data`
  - `clinic-hub-keycloak-data` → `/opt/keycloak/data`
- Start containers in order: Postgres → Keycloak → Traefik
- Wait for Postgres readiness before starting Keycloak

### Manual run (alternative to run.sh)
```bash
docker network create web || true

docker run -d --restart unless-stopped --name db --network web \
  -p 5432:5432 -v clinic-hub-postgres-db-data:/var/lib/postgresql/data \
  clinic-hub-postgres:v0.1.0

docker run -d --restart unless-stopped --name keycloak --network web \
  -v clinic-hub-keycloak-data:/opt/keycloak/data \
  clinic-hub-keycloak:v0.1.0

docker run -d --restart unless-stopped --name traefik --network web \
  -p 80:80 clinic-hub-traefik:v0.1.0
```

### Access
- Traefik dashboard: `http://hubtraefik.mouzaiaclinic.local` (admin/admin)
- Keycloak: `http://hubkeycloak.mouzaiaclinic.local`
- Postgres (from clients like DBeaver):
  - Host: `hubpostgres.mouzaiaclinic.local`
  - Port: `5432`
  - DB: `clinic-mouzaia-hub`
  - User: `admin`
  - Password: `admin`

### Security notes
- Credentials are embedded in images for a frictionless offline setup; rebuild images to change defaults.
- You can rotate Keycloak admin in the UI; update Postgres passwords via SQL; Traefik dashboard auth requires rebuilding with a new bcrypt hash.

### Project layout
```
docker-compose.yml        # For building images locally (optional for runtime)
run.sh                    # One-click launcher (no compose needed to run)
traefik/
  Dockerfile
  traefik.yaml            # static config (entrypoint, providers, api)
  dynamic.yaml            # routers/services/middlewares
keycloak/
  Dockerfile
postgres/
  Dockerfile
  postgresql.conf         # minimal server config (timezone, auth, listen)
  pg_hba.conf             # scram auth rules
```

### Customization
- DNS: Use pfSense or similar to map hostnames to the Docker host.
- Credentials: Edit Dockerfiles and rebuild images. For more flexibility, consider adding build args or switching to docker compose with a .env.

# Mouzaia Clinic Hub - Docker Infrastructure

## Overview
This repository provides a modern, development-friendly Docker setup for the Mouzaia Clinic Hub, including:
- Traefik v3 (reverse proxy, dashboard, automatic service discovery)
- PostgreSQL 15+ (persistent storage)
- Custom Docker network for secure service communication

All services are accessible via local DNS (no port numbers needed).

---

## Quick Start

### 1. Prerequisites
- [Docker](https://docs.docker.com/get-docker/) & [Docker Compose](https://docs.docker.com/compose/)

```
DNS resolution for hub.mouzaiaclinic.local
DNS resolution for hubtraefik.mouzaiaclinic.local
DNS resolution for hubpostgres.mouzaiaclinic.local
DNS resolution for hubkeycloak.mouzaiaclinic.local
```

### 2. Environment Variables
Copy the appropriate env file:

```
cp .env.development .env
# or for production
cp .env.production .env
```

You can customize database credentials, Traefik dashboard access, and more in these files.

### 3. Start the Stack
```
docker-compose up --build
```

### 4. Access Services
- **Clinic Hub App**: http://hub.mouzaiaclinic.local
- **Traefik Dashboard**: `${KEYCLOAK_DASHBOARD_URL}`
- **PostgreSQL**: accessible via Traefik at its configured URL
- **Keycloak Auth**: `${KEYCLOAK_URL}` (for admin and realm management)

> **Note:** All URLs are driven by environment variables in `.env.development` and `.env.production`. No URLs are hardcoded in configs or code.

### 5. Stop the Stack
```
docker-compose down
```


---

## Keycloak Integration
- Keycloak is accessible at `${KEYCLOAK_URL}` (default: http://hubkeycloak.mouzaiaclinic.local) through Traefik.
- Realm, admin user, and client configuration are imported from `keycloak/realm-config.json`, using environment variables for credentials.
- To change any service URL, update the corresponding variable in your `.env.*` file.

---

**Note:** The postgres db is not exposed and can be accessed with the `${KC_DB_URL}` variable.
---
## Directory Structure
```
mouzaia-clinic-hub/
├── docker-compose.yml
├── docker-compose.override.yml (optional)
├── .env.development
├── .env.production
├── traefik/
│   └── traefik.yml
├── keycloak/
│   ├── realm-config.json
│   └── themes/
├── .gitignore
└── README.md
```

---

## Features
- **Traefik v3**: Modern reverse proxy, auto-discovers containers, routes by DNS, dashboard enabled
- **PostgreSQL**: Data persists in `pgdata/` volume
- **All configuration via environment variables**
- **No port numbers required**: All services routed via standard HTTP ports (80/443)
- **Easy to extend**: Add more services with Traefik labels

---

## Troubleshooting
- If services are not reachable, ensure your `/etc/hosts` entries are correct and there are no conflicting services on ports 80/443.
- For advanced Traefik config, edit `traefik/traefik.yml`.

---

## Security
- Never commit real secrets to `.env.*` files in production.
- The dashboard is for development/testing only. Restrict access in production.

---

## License
MIT

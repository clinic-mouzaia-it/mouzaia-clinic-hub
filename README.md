## Mouzaia Clinic Hub

Minimal, offline-ready stack with three containers: Traefik, Keycloak, and Postgres. All credentials and configs are baked into the images so end users only need the images to run.

### What's included
- **Traefik v3.5.2** (HTTP only)
  - Dashboard protected with basic auth (admin/admin)
  - Routes:
    - `hubtraefik.mouzaiaclinic.local` → Traefik dashboard
    - `hubkeycloak.mouzaiaclinic.local` → Keycloak service
- **Keycloak 26.3** (vanilla)
  - Runs on HTTP 8080 behind Traefik
  - Admin: `admin` / `admin` (baked into image)
  - DB connection pre-configured to the `db` container
- **Postgres 17.0**
  - DB: `clinic-mouzaia-hub`
  - User: `admin` / `admin` (baked into image)
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

**Note:** Credentials are hardcoded in the Dockerfiles. No .env files are required for build or runtime.

### Run everything (end user) – one command
You don't need docker compose to run. Use the included script:
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
- **Traefik dashboard:** `http://hubtraefik.mouzaiaclinic.local` (admin/admin)
- **Keycloak:** `http://hubkeycloak.mouzaiaclinic.local` (admin/admin)
- **Postgres** (from clients like DBeaver):
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
mouzaia-clinic-hub/
├── docker-compose.yml        # For building images locally (optional for runtime)
├── run.sh                    # One-click launcher (no compose needed to run)
├── traefik/
│   ├── Dockerfile
│   ├── traefik.yaml          # static config (entrypoint, providers, api)
│   └── dynamic.yaml          # routers/services/middlewares
├── keycloak/
│   └── Dockerfile
└── postgres/
    ├── Dockerfile
    ├── postgresql.conf       # minimal server config (timezone, auth, listen)
    └── pg_hba.conf           # scram auth rules
```

### Customization
- **DNS:** Use pfSense or similar to map hostnames to the Docker host.
- **Credentials:** Edit Dockerfiles and rebuild images. For more flexibility, consider adding build args or switching to docker compose with a .env.

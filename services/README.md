# Services Workspace

This directory hosts a self-contained Node.js + TypeScript workspace for backend microservices using npm workspaces.

## Workspace layout
- `package.json` — npm workspaces for `shared`, `identity-service`, `pharmacy-service`.
- `tsconfig.base.json` — base TS config (ES2020, CJS) with path mapping `@clinic/shared/*`.
- `shared/` — common types and helpers (no secrets).
- `identity-service/` — existing service (preserved behavior).
- `pharmacy-service/` — new service scaffold.

## Install
From this directory:

```
npm ci
```

## Build

- Build everything (shared first):
```
npm run build:all
```
- Or per service:
```
npm run build:identity
npm run build:pharmacy
```

## Docker build (local)
These are example local builds. Root docker-compose will be used normally; do not change it.

```
# identity service
docker build -t clinic-hub-identity:latest ./identity-service -f identity-service/Dockerfile

# pharmacy service
docker build -t clinic-hub-pharmacy:latest ./pharmacy-service -f pharmacy-service/Dockerfile
```

## Smoke test (example)
Run the container and check health (adjust networking as needed):

```
# Identity
docker run --rm -p 4000:4000 clinic-hub-identity:latest curl -s http://localhost:4000/health

# Pharmacy
docker run --rm -p 4100:4100 clinic-hub-pharmacy:latest curl -s http://localhost:4100/health
```

At runtime, secrets and environment variables are provided by the root `.env` via `docker-compose.yml`. Do not hardcode secrets.

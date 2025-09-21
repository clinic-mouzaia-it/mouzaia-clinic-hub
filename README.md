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
- Add the following to your `/etc/hosts` (Linux/macOS) or `C:\Windows\System32\drivers\etc\hosts` (Windows):

```
127.0.0.1 hub.mouzaiaclinic.local
127.0.0.1 hubtraefik.mouzaiaclinic.local
127.0.0.1 hubpostgres.mouzaiaclinic.local
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
- **Traefik Dashboard**: http://hubtraefik.mouzaiaclinic.local
- **PostgreSQL**: http://hubpostgres.mouzaiaclinic.local (for testing connectivity)

> **Note:** The dashboard is protected by basic auth (see `.env`).

### 5. Stop the Stack
```
docker-compose down
```

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

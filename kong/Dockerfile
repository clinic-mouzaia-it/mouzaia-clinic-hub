# Clinic Hub Kong - DB-less, baked config
FROM kong:3.6

# Copy single declarative config into image
COPY kong.yaml /etc/kong/kong.yaml

## All runtime configuration is provided via docker-compose env_file (.env)

# Expose proxy ports only (Traefik will reach 8000 on the Docker network)
EXPOSE 8000 8443

# Use default CMD from base image (no startup args/configs required)

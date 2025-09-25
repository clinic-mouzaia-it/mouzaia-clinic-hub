FROM traefik:3.5.2

# Copy static and dynamic configuration
COPY traefik.yaml /etc/traefik/traefik.yaml
COPY dynamic.yaml /etc/traefik/dynamic.yaml

EXPOSE 80

# Default command provided by base image starts Traefik


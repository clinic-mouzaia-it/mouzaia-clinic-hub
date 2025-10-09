FROM quay.io/keycloak/keycloak:26.3

# Preload realm import (filename must match `<realm>-realm.json`)
COPY clinic-mouzaia-hub-realm.json /opt/keycloak/data/import/clinic-mouzaia-hub-realm.json

EXPOSE ${KC_HTTP_PORT}

CMD ["start", "--import-realm"]


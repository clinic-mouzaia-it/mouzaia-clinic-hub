FROM quay.io/keycloak/keycloak:26.3

ENV KEYCLOAK_ADMIN=admin \
    KEYCLOAK_ADMIN_PASSWORD=admin \
    KC_DB=postgres \
    KC_DB_URL=jdbc:postgresql://db:5432/keycloak \
    KC_DB_USERNAME=admin \
    KC_DB_PASSWORD=admin \
    KC_HOSTNAME=hubkeycloak.mouzaiaclinic.local \
    KC_HTTP_ENABLED=true \
    KC_HTTP_PORT=8080 \
    KC_PROXY_HEADERS=xforwarded \
    KC_HOSTNAME_STRICT=false

EXPOSE 8080

CMD ["start"]


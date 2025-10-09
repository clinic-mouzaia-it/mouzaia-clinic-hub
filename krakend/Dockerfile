FROM krakend:2.11.0

# Copy KrakenD configuration
COPY krakend.json /etc/krakend/krakend.json

EXPOSE ${KrakenD_HTTP_PORT}

CMD ["krakend", "run", "-c", "/etc/krakend/krakend.json"]


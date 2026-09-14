FROM oven/bun:debian

ARG UID=1000
ARG GID=1000
ARG APP_DIR=/app

RUN apt-get update && apt-get install -y --no-install-recommends \
    passwd \
    && rm -rf /var/lib/apt/lists/*

RUN set -e; \
    # Aggiorna GID di bun se diverso da quello richiesto
    if [ "${GID}" != "1000" ]; then \
        groupmod -g "${GID}" bun; \
    fi; \
    # Aggiorna UID di bun se diverso da quello richiesto
    if [ "${UID}" != "1000" ]; then \
        usermod -u "${UID}" -g "${GID}" bun; \
    fi; \
    # Prepara la directory applicativa e la home con i permessi corretti
    mkdir -p "${APP_DIR}" /home/bun; \
    chown -R "${UID}:${GID}" "${APP_DIR}" /home/bun

COPY entrypoint.bun.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER bun
WORKDIR ${APP_DIR}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

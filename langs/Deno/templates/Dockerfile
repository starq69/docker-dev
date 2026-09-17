# -------------------------------------------------
# Dockerfile.Deno
# -------------------------------------------------
FROM denoland/deno:2.9.7

ARG HOSTUSER UID GID
ARG APP_DIR=/app
ENV TZ=Europe/Rome

RUN groupadd -g ${GID} ${HOSTUSER} && \
    useradd -m -u ${UID} -g ${GID} ${HOSTUSER} && \
    ln -sf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    apt-get update && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Definiamo la variabile d'ambiente globale per la cache
ENV DENO_DIR=/home/${HOSTUSER}/.deno_cache/cache

COPY entrypoint.Deno.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER ${HOSTUSER}
WORKDIR ${APP_DIR}
ENV PATH="${APP_DIR}:$PATH"
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]


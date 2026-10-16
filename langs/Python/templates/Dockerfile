# Dockerfile.Python

FROM debian:trixie-slim

COPY --from=ghcr.io/astral-sh/uv:0.10.5 /uv /uvx /bin/

ARG HOSTUSER UID GID
ARG APP_DIR=/app
ENV TZ=Europe/Rome

# Force uv to use system Python instead of downloading it
ENV UV_LINK_MODE=copy

# Force the build to fail if the auto-generated lock is not up to date
#ENV UV_LOCKED=1

RUN groupadd -g ${GID} ${HOSTUSER} && \
    useradd -m -u ${UID} -g ${GID} ${HOSTUSER} && \
    ln -sf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    apt-get update && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*


COPY entrypoint.Python.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER ${HOSTUSER}
WORKDIR ${APP_DIR}
ENV PATH="${APP_DIR}/.venv/bin:$PATH"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

#CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]


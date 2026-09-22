FROM perl:5.38-slim

ARG HOSTUSER UID GID
ARG APP_DIR=/app
ENV TZ=Europe/Rome

RUN groupadd -g ${GID} ${HOSTUSER} && \
    useradd -m -u ${UID} -g ${GID} ${HOSTUSER} && \
    ln -sf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \ 
    apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    make \
    libc6-dev \
    libssl-dev \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

RUN cpanm -n Carton

COPY entrypoint.Perl.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

#COPY cpanfile cpanfile.snapshot ./
EXPOSE 3000

ENV PERL5LIB="${APP_DIR}/local/lib/perl5"
ENV PATH="${APP_DIR}/local/bin:$PATH"

USER ${HOSTUSER}
WORKDIR ${APP_DIR}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

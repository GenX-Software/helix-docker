FROM ubuntu:24.04

LABEL org.opencontainers.image.description="Perforce Helix Core 2026.1"

RUN apt-get update && \
    apt-get install -y --no-install-recommends wget gnupg ca-certificates && \
    mkdir -p /etc/apt/keyrings && \
    wget -qO - https://package.perforce.com/perforce.pubkey | gpg --dearmor -o /etc/apt/keyrings/perforce.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/perforce.gpg] http://package.perforce.com/apt/ubuntu noble release" \
        > /etc/apt/sources.list.d/perforce.list && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        helix-p4d=2026.1-3089746~noble && \
    apt-get remove -y wget gnupg && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY files/restore.sh /usr/local/bin/restore.sh
COPY files/setup.sh /usr/local/bin/setup.sh
COPY files/init.sh /usr/local/bin/init.sh
COPY files/latest_checkpoint.sh /usr/local/bin/latest_checkpoint.sh

RUN chmod +x /usr/local/bin/restore.sh \
             /usr/local/bin/setup.sh \
             /usr/local/bin/init.sh \
             /usr/local/bin/latest_checkpoint.sh

# Same names as sourcegraph/helix-docker, so an existing compose file keeps working.
ARG NAME=perforce-server
ARG P4NAME=master
ARG P4TCP=1666
ARG P4USER=admin
ARG P4PASSWD=pass12349ers
ARG P4CASE=-C0
ARG P4CHARSET=utf8

ENV NAME=$NAME \
    P4NAME=$P4NAME \
    P4TCP=$P4TCP \
    P4PORT=$P4TCP \
    P4USER=$P4USER \
    P4PASSWD=$P4PASSWD \
    P4CASE=$P4CASE \
    P4CHARSET=$P4CHARSET \
    JNL_PREFIX=$P4NAME \
    P4HOME=/p4 \
    P4ROOT=/p4/root \
    P4DEPOTS=/p4/depots \
    P4CKP=/p4/checkpoints \
    PATH=/opt/perforce/bin:/opt/perforce/sbin:$PATH

EXPOSE $P4TCP
VOLUME $P4HOME

# User P4LOG is ../logs/log from /p4/root/root, i.e. /p4/root/logs/log.
ENTRYPOINT \
    init.sh && \
    /usr/bin/tail -F $P4ROOT/logs/log

# p4 info -s as P4USER=admin has no ticket and logs a failed auth check
# every interval. p4dctl status never talks to the p4 protocol.
HEALTHCHECK \
    --interval=2m \
    --timeout=10s \
    CMD p4dctl status -t p4d "$NAME" | grep -q "service is running."

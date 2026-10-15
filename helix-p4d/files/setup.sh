#!/bin/bash
set -euo pipefail

# First-time only. init.sh must not call this when /p4/root/root already has db.*.
# configure-helix-p4d.sh -r $P4ROOT nests the live root at $P4ROOT/root.

SERVICE="${NAME:-${P4NAME:-perforce-server}}"

if [ -z "${P4CHARSET:-}" ]; then
    echo "[ERROR] P4CHARSET is not set."
    exit 255
fi
if [ "${P4CHARSET}" != "none" ] && [ "${P4CHARSET}" != "utf8" ]; then
    echo "[ERROR] P4CHARSET must be 'none' or 'utf8'."
    exit 255
fi
if [ -z "${P4CASE:-}" ]; then
    echo "[ERROR] P4CASE is not set."
    exit 255
fi
if [ "${P4CASE}" != "-C0" ] && [ "${P4CASE}" != "-C1" ]; then
    echo "[ERROR] P4CASE must be -C0 or -C1."
    exit 255
fi

opts=()
if [ "${P4CHARSET}" != "none" ]; then
    opts+=(--unicode)
fi
if [ "${P4CASE}" = "-C1" ]; then
    opts+=(--case=1)
else
    opts+=(--case=0)
fi

fresh=0
if [ ! -f "$P4ROOT/root/db.counters" ] && [ ! -f "$P4ROOT/db.counters" ]; then
    fresh=1
fi

if [ ! -d "$P4ROOT/etc" ]; then
    echo "[INFO] Copying /etc/perforce to $P4ROOT/etc"
    mkdir -p "$P4ROOT/etc"
    cp -a /etc/perforce/. "$P4ROOT/etc/"
fi
if [ ! -L /etc/perforce ]; then
    mv /etc/perforce /etc/perforce.orig
    ln -s "$P4ROOT/etc" /etc/perforce
fi

if ! p4dctl list 2>/dev/null | grep -q "$SERVICE"; then
    /opt/perforce/sbin/configure-helix-p4d.sh "$SERVICE" -n \
        -p "$P4PORT" -r "$P4ROOT" -u "$P4USER" -P "${P4PASSWD}" "${opts[@]}"
fi

# Defaults for a brand-new server only. An upgraded volume already has
# server.depot.root, journalPrefix, security, triggers — leave them alone.
if [ "$fresh" = 1 ]; then
    p4 login <<EOF
$P4PASSWD
EOF
    p4 configure set "${P4NAME}#server.depot.root=${P4DEPOTS}"
    p4 configure set "${P4NAME}#journalPrefix=${P4CKP}/${JNL_PREFIX}"
    p4dctl stop -t p4d "$SERVICE" || true
fi


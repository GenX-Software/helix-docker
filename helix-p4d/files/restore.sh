#!/bin/bash
set -euo pipefail

if [ ! -L "$P4CKP/latest" ]; then
    echo "[INFO] Link not found - looking for checkpoint"
    /usr/local/bin/latest_checkpoint.sh
fi
if [ ! -L "$P4CKP/latest" ]; then
    echo "[ERROR] Checkpoint for link $P4CKP/latest not found."
    exit 255
fi
if [ -z "${P4CASE:-}" ]; then
    echo "[ERROR] P4CASE is not set."
    exit 255
fi

# configure-helix-p4d.sh -r /p4/root stores db.* in /p4/root/root.
TARGET="$P4ROOT"
if [ -d "$P4ROOT/root" ] || [ -f "$P4ROOT/root/db.counters" ]; then
    TARGET="$P4ROOT/root"
fi
mkdir -p "$TARGET"

STAGE="$TARGET.restore-staging.$$"
rm -rf "$STAGE"
mkdir -p "$STAGE"
trap 'rm -rf "$STAGE"' EXIT

fail() {
    echo "[ERROR] $1"
    echo "[ERROR] Database in $TARGET left as it was."
    exit 255
}

echo "[INFO] Restoring $P4CKP/latest into staging with $P4CASE"
p4d $P4CASE -r "$STAGE" -jr -z "$P4CKP/latest" \
    || fail "p4d -jr failed"
p4d $P4CASE -r "$STAGE" -xu \
    || fail "p4d -xu failed"
[ -f "$STAGE/db.counters" ] \
    || fail "Restore produced no db.counters"

BACKUP="$P4CKP/pre-restore-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP"
cp -a "$TARGET"/db.* "$BACKUP"/ 2>/dev/null || true
cp -a "$TARGET"/server.id "$BACKUP"/ 2>/dev/null || true

echo "[INFO] Replacing database in $TARGET (previous copy in $BACKUP)"
rm -f "$TARGET"/db.*
cp -a "$STAGE"/. "$TARGET"/ || {
    cp -a "$BACKUP"/. "$TARGET"/ 2>/dev/null || true
    fail "Could not copy restored database into place"
}
chown -R perforce:perforce "$TARGET"/db.* "$TARGET"/server.id 2>/dev/null || true
echo "[INFO] Checkpoint restored."

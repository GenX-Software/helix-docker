#!/bin/bash
set -euo pipefail

SERVICE="${NAME:-${P4NAME:-perforce-server}}"

mkdir -p "$P4ROOT" "$P4DEPOTS" "$P4CKP"

# Live database after configure-helix-p4d.sh -r /p4/root.
server_root() {
    if [ -f "$P4ROOT/root/db.counters" ]; then
        echo "$P4ROOT/root"
    elif [ -f "$P4ROOT/db.counters" ]; then
        echo "$P4ROOT"
    else
        echo ""
    fi
}

# sourcegraph persisted p4dctl under $P4ROOT/etc and symlinked /etc/perforce.
link_volume_etc() {
    if [ -d "$P4ROOT/etc" ]; then
        if [ ! -L /etc/perforce ]; then
            echo "[INFO] Linking /etc/perforce -> $P4ROOT/etc"
            if [ -d /etc/perforce ]; then
                mv /etc/perforce /etc/perforce.image
            fi
            ln -s "$P4ROOT/etc" /etc/perforce
        fi
        return 0
    fi
    return 1
}

# 2026.1 p4dctl rejects AUTOUPGRADE as a service-level key (it is only
# an Environment variable in configure-p4d.sh). A previous init wrote it
# at the top of genx-p4.conf and that file is on the volume. Strip it
# before every p4dctl start. Schema upgrade is already done via p4d -xu.
sanitize_p4dctl_confs() {
    local dir=/etc/perforce/p4dctl.conf.d
    [ -d "$dir" ] || return 0
    local f
    for f in "$dir"/*.conf; do
        [ -f "$f" ] || continue
        if grep -q '^[[:space:]]*AUTOUPGRADE[[:space:]]*=' "$f"; then
            echo "[INFO] Removing AUTOUPGRADE from $f (not a p4dctl setting)"
            sed -i '/^[[:space:]]*AUTOUPGRADE[[:space:]]*=/d' "$f"
        fi
    done
}

save_volume_etc() {
    if [ ! -d "$P4ROOT/etc" ] && [ -d /etc/perforce ]; then
        echo "[INFO] Saving p4dctl registration to $P4ROOT/etc"
        mkdir -p "$P4ROOT/etc"
        cp -a /etc/perforce/. "$P4ROOT/etc/"
        mv /etc/perforce /etc/perforce.image
        ln -s "$P4ROOT/etc" /etc/perforce
    fi
}

write_service_conf() {
    local root="$1"
    local conf="/etc/perforce/p4dctl.conf.d/${SERVICE}.conf"
    mkdir -p /etc/perforce/p4dctl.conf.d
    cat > "$conf" <<EOF
p4d ${SERVICE}
{
    Owner    =	perforce
    Execute  =	/opt/perforce/sbin/p4d
    Umask    =	077
    Enabled  =	true

    Environment
    {
        P4ROOT    =	${root}
        P4PORT    =	${P4PORT}
        P4SSLDIR  =	ssl
        PATH      =	/bin:/usr/bin:/usr/local/bin:/opt/perforce/bin:/opt/perforce/sbin
    }
}
EOF
}

# The 2023.2 image and this one both call the user "perforce", but the
# numeric UID often differs (Focal package vs Noble). The volume is 0700
# for the old UID, so the new user cannot chdir into P4ROOT. Prefer
# moving the container user onto the volume's UID so archives are not
# chown'd. If the tree is owned by root, take the metadata dirs only.
align_perforce_to_volume() {
    local root="$1"
    local vol_uid vol_gid cur_uid
    vol_uid=$(stat -c '%u' "$root")
    vol_gid=$(stat -c '%g' "$root")
    cur_uid=$(id -u perforce)

    if [ "$vol_uid" = "$cur_uid" ]; then
        return 0
    fi

    if [ "$vol_uid" = 0 ]; then
        echo "[INFO] $root is owned by root; giving metadata dirs to perforce"
        chown -R perforce:perforce "$root"
        chown perforce:perforce "$(dirname "$root")" 2>/dev/null || true
        [ -d "$(dirname "$root")/journals" ] && chown -R perforce:perforce "$(dirname "$root")/journals"
        [ -d "$(dirname "$root")/logs" ] && chown -R perforce:perforce "$(dirname "$root")/logs"
        [ -d "$(dirname "$root")/etc" ] && chown -R perforce:perforce "$(dirname "$root")/etc"
        return 0
    fi

    echo "[INFO] Volume owner is $vol_uid:$vol_gid; image perforce is $cur_uid — aligning UID"
    if getent group "$vol_gid" >/dev/null; then
        usermod -u "$vol_uid" -g "$vol_gid" perforce || true
    else
        groupmod -g "$vol_gid" perforce || true
        usermod -u "$vol_uid" -g "$vol_gid" perforce || true
    fi
    if [ "$(id -u perforce)" != "$vol_uid" ]; then
        echo "[WARN] Could not retarget perforce to $vol_uid; chowning metadata dirs"
        chown -R perforce:perforce "$root"
        [ -d "$(dirname "$root")/journals" ] && chown -R perforce:perforce "$(dirname "$root")/journals"
        [ -d "$(dirname "$root")/logs" ] && chown -R perforce:perforce "$(dirname "$root")/logs"
    fi
}

upgrade_schema() {
    local root="$1"
    echo "[INFO] p4d -xu against $root"
    su -s /bin/sh perforce -c "p4d -r '$root' -xu"
}

if [ -L "$P4CKP/latest" ]; then
    echo "[INFO] Restoring checkpoint..."
    restore.sh
    echo "[INFO] Server restored"
fi

link_volume_etc || true
sanitize_p4dctl_confs

ROOT="$(server_root)"

if [ -n "$ROOT" ]; then
    echo "[INFO] Existing database at $ROOT"
    align_perforce_to_volume "$ROOT"
    if ! p4dctl list 2>/dev/null | grep -q "$SERVICE"; then
        echo "[INFO] No p4dctl service '$SERVICE'; writing one for $ROOT"
        write_service_conf "$ROOT"
    fi
    upgrade_schema "$ROOT"
    save_volume_etc
    sanitize_p4dctl_confs
    echo "[INFO] Starting $SERVICE..."
    p4dctl start -t p4d "$SERVICE"
else
    echo "[INFO] No database under $P4ROOT; first-time setup"
    setup.sh
    save_volume_etc
    sanitize_p4dctl_confs
    echo "[INFO] Starting $SERVICE..."
    p4dctl start -t p4d "$SERVICE"
fi

echo "[INFO] Server [RUNNING]"
# Do not call `p4` here. P4USER=admin with no ticket logs
# "failed authentication check" at security 3/4, including for `info -s`.
until p4dctl status -t p4d "$SERVICE" >/dev/null 2>&1; do sleep 1; done

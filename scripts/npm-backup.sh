#!/usr/bin/env bash
set -Eeuo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/nginx-proxy-manager}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
install -d -m 0700 "$BACKUP_ROOT"
WORK_DIR="$(mktemp -d "${BACKUP_ROOT}/.backup-${STAMP}.XXXXXX")"
ARCHIVE="${BACKUP_ROOT}/nginx-proxy-manager-${STAMP}.tar.gz"
trap 'rm -rf "$WORK_DIR"' EXIT
install -d -m 0700 "$WORK_DIR/data" "$WORK_DIR/nginx-system-config"

# SQLite online backup gives a consistent database while the application runs.
if [[ -f /data/database.sqlite ]]; then
  sqlite3 /data/database.sqlite ".timeout 10000" ".backup '$WORK_DIR/data/database.sqlite'"
fi

rsync -a \
  --exclude='database.sqlite' \
  --exclude='logs/' \
  --exclude='nginx/temp/' \
  /data/ "$WORK_DIR/data/"
rsync -a /etc/letsencrypt/ "$WORK_DIR/letsencrypt/"
rsync -a /etc/nginx-proxy-manager/ "$WORK_DIR/adaptation-config/"
cp -a /etc/nginx/nginx.conf /etc/nginx/conf.d "$WORK_DIR/nginx-system-config/"
cp -a /etc/nginx-proxy-manager/installation.json "$WORK_DIR/installation.json"

cat >"$WORK_DIR/BACKUP-METADATA" <<META
created_utc=${STAMP}
hostname=$(hostname)
active_release=$(readlink -f /opt/nginx-proxy-manager/current)
contains_secrets=yes
META

tar -C "$WORK_DIR" -czf "$ARCHIVE" .
chmod 0600 "$ARCHIVE"
(
  cd "$BACKUP_ROOT"
  sha256sum "$(basename "$ARCHIVE")" >"$(basename "${ARCHIVE}.sha256")"
)
chmod 0600 "${ARCHIVE}.sha256"
printf '%s\n' "$ARCHIVE"

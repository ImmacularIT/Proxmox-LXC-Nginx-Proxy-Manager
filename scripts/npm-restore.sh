#!/usr/bin/env bash
set -Eeuo pipefail

usage() { echo "Usage: $0 --archive /path/to/backup.tar.gz" >&2; exit 2; }
archive=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive) archive="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$archive" && -f "$archive" ]] || usage
[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

if [[ -f "${archive}.sha256" ]]; then
  (cd "$(dirname "$archive")" && sha256sum -c "$(basename "${archive}.sha256")")
fi

tmp="$(mktemp -d /var/tmp/npm-restore.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
tar -C "$tmp" -xzf "$archive"
[[ -f "$tmp/installation.json" && -d "$tmp/data" ]] || {
  echo "Archive does not look like an NPM LXC backup" >&2
  exit 1
}

/usr/local/sbin/npm-lxc-backup >/dev/null
systemctl stop nginx-proxy-manager-nginx.service nginx-proxy-manager-backend.service
rsync -a --delete "$tmp/data/" /data/
rsync -a --delete "$tmp/letsencrypt/" /etc/letsencrypt/
rsync -a "$tmp/adaptation-config/" /etc/nginx-proxy-manager/
rsync -a "$tmp/nginx-system-config/" /etc/nginx/
/usr/local/sbin/npm-lxc-prepare
chown -R npm:npm /data /etc/letsencrypt
systemctl start nginx-proxy-manager-backend.service
backend_ready=0
for _ in {1..120}; do
  if ss -ltnH 'sport = :3000' | grep -q .; then
    backend_ready=1
    break
  fi
  if ! systemctl is-active --quiet nginx-proxy-manager-backend.service; then
    break
  fi
  sleep 1
done
if [[ "$backend_ready" -ne 1 ]]; then
  echo "Backend did not become ready after restore" >&2
  journalctl -u nginx-proxy-manager-backend.service --no-pager -n 80 >&2 || true
  exit 1
fi
systemctl start nginx-proxy-manager-nginx.service
/usr/local/sbin/npm-lxc-healthcheck

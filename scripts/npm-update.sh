#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<USAGE
Usage: $0 --version-file /root/validated-versions.sh

The version file must come from a reviewed ImmacularIT adaptation release. This
helper never selects "latest" and never consumes a moving upstream branch.
USAGE
  exit 2
}

version_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version-file) version_file="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$version_file" && -f "$version_file" ]] || usage
[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

owner="$(stat -c %u "$version_file")"
mode="$(stat -c %a "$version_file")"
[[ "$owner" == 0 ]] || { echo "Version file must be owned by root" >&2; exit 1; }
perm=$((8#$mode))
(( (perm & 022) == 0 )) || {
  echo "Version file must not be group/world writable" >&2
  exit 1
}

current_lib="/usr/local/lib/npm-lxc"
# shellcheck source=/dev/null
source "$current_lib/versions.sh"
current_version="$NPM_VERSION"
current_commit="$NPM_COMMIT"
current_base_commit="$NPM_BASE_COMMIT"
old_release="$(readlink -f /opt/nginx-proxy-manager/current)"

candidate_lib="$(mktemp -d /var/tmp/npm-update-manifest.XXXXXX)"
trap 'rm -rf "$candidate_lib"' EXIT
cp -a "$version_file" "$candidate_lib/versions.sh"
IFS=$'\t' read -r candidate_version candidate_commit candidate_base_commit < <(
  bash -c 'source "$1"; printf "%s\t%s\t%s\n" "$NPM_VERSION" "$NPM_COMMIT" "$NPM_BASE_COMMIT"' _ "$candidate_lib/versions.sh"
)
[[ -n "$candidate_version" && -n "$candidate_commit" && -n "$candidate_base_commit" ]] || {
  echo "Candidate version manifest is incomplete" >&2
  exit 1
}

[[ "$candidate_version" != "$current_version" || "$candidate_commit" != "$current_commit" ]] || {
  echo "Selected manifest is already installed (${current_version}, ${current_commit})" >&2
  exit 1
}
[[ "$candidate_base_commit" == "$current_base_commit" ]] || {
  echo "The official nginx-full base changed." >&2
  echo "A full adaptation update, including a rebuilt and revalidated OpenResty stack, is required." >&2
  exit 1
}

printf 'Current:   %s (%s)\n' "$current_version" "$current_commit"
printf 'Selected:  %s (%s)\n' "$candidate_version" "$candidate_commit"
read -r -p "Build and install the selected release? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || exit 0

backup_archive="$(/usr/local/sbin/npm-lxc-backup)"
echo "Pre-update backup: ${backup_archive}"

NPM_LXC_LIB_DIR="$candidate_lib" /usr/local/lib/npm-lxc/install-release.sh
new_release="/opt/nginx-proxy-manager/releases/${candidate_version}"
[[ -f "$new_release/index.js" ]] || { echo "New release build missing" >&2; exit 1; }

systemctl stop nginx-proxy-manager-nginx.service nginx-proxy-manager-backend.service
ln -s "$new_release" /opt/nginx-proxy-manager/.current.new
mv -Tf /opt/nginx-proxy-manager/.current.new /opt/nginx-proxy-manager/current

sed -i -E \
  -e "s|^NPM_BUILD_VERSION=.*|NPM_BUILD_VERSION=${candidate_version}|" \
  -e "s|^NPM_BUILD_COMMIT=.*|NPM_BUILD_COMMIT=${candidate_commit}|" \
  -e "s|^NPM_BUILD_DATE=.*|NPM_BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)|" \
  /etc/nginx-proxy-manager/environment

set +e
systemctl start nginx-proxy-manager-backend.service
backend_ready=0
for _ in {1..180}; do
  if ss -ltnH 'sport = :3000' | grep -q .; then backend_ready=1; break; fi
  sleep 1
done
if [[ "$backend_ready" -eq 1 ]]; then
  systemctl start nginx-proxy-manager-nginx.service
  /usr/local/sbin/npm-lxc-healthcheck
  health_status=$?
else
  health_status=1
fi
set -e

if [[ "$health_status" -ne 0 ]]; then
  systemctl stop nginx-proxy-manager-nginx.service nginx-proxy-manager-backend.service || true
  ln -s "$old_release" /opt/nginx-proxy-manager/.current.rollback
  mv -Tf /opt/nginx-proxy-manager/.current.rollback /opt/nginx-proxy-manager/current
  cat >&2 <<ROLLBACK
Update health checks failed. The active application symlink was returned to:
  ${old_release}

Database migrations may already have run. Restore the pre-update backup before
starting the old release:
  /usr/local/sbin/npm-lxc-restore --archive ${backup_archive}
ROLLBACK
  exit 1
fi

install -o root -g root -m 0644 "$candidate_lib/versions.sh" "$current_lib/versions.sh"
python3 - "$candidate_version" "$candidate_commit" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path
p = Path('/etc/nginx-proxy-manager/installation.json')
data = json.loads(p.read_text())
data['upstream_release'] = f'v{sys.argv[1]}'
data['upstream_commit'] = sys.argv[2]
data['active_release'] = f'/opt/nginx-proxy-manager/releases/{sys.argv[1]}'
data['last_update_utc'] = datetime.now(timezone.utc).isoformat()
p.write_text(json.dumps(data, indent=2) + '\n')
PY
chmod 0600 /etc/nginx-proxy-manager/installation.json
printf 'Update completed: %s -> %s\n' "$current_version" "$candidate_version"
printf 'Rollback backup retained at: %s\n' "$backup_archive"

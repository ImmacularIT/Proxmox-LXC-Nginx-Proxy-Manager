#!/usr/bin/env bash
set -Eeuo pipefail

quiet=0
[[ "${1:-}" == "--quiet" ]] && quiet=1
failures=()

check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    [[ "$quiet" -eq 1 ]] || printf 'PASS  %s\n' "$description"
  else
    failures+=("$description")
    [[ "$quiet" -eq 1 ]] || printf 'FAIL  %s\n' "$description"
  fi
}

check "backend service active" systemctl is-active --quiet nginx-proxy-manager-backend.service
check "nginx service active" systemctl is-active --quiet nginx-proxy-manager-nginx.service
check "OpenResty configuration valid" /usr/sbin/nginx -t
check "backend port 3000 listening" bash -c "ss -ltnH 'sport = :3000' | grep -q ."
check "administration port 81 listening" bash -c "ss -ltnH 'sport = :81' | grep -q ."
check "HTTP port 80 listening" bash -c "ss -ltnH 'sport = :80' | grep -q ."
check "HTTPS port 443 listening" bash -c "ss -ltnH 'sport = :443' | grep -q ."
check "administration UI responds" curl -fsS --max-time 10 http://127.0.0.1:81/
check "installed release marker" test -s /etc/nginx-proxy-manager/installation.json
check "no Docker runtime installed" bash -c "! command -v docker && ! command -v podman"

if [[ ${#failures[@]} -gt 0 ]]; then
  printf 'Health check failed (%d): %s\n' "${#failures[@]}" "${failures[*]}" >&2
  exit 1
fi
[[ "$quiet" -eq 1 ]] || echo "All native LXC health checks passed."

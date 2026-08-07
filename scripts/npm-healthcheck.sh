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

port_listening() {
  local port="$1"
  ss -ltnH "sport = :${port}" | grep -q .
}

# systemd can report the OpenResty service active a fraction of a second before
# all worker listeners are visible to ss. Wait for the expected native sockets
# while the service remains active so installation/reboot health checks do not
# fail on that harmless startup window.
wait_for_nginx_listeners() {
  local attempt port ready
  for attempt in {1..30}; do
    ready=1
    for port in 80 81 443; do
      if ! port_listening "$port"; then
        ready=0
        break
      fi
    done
    [[ "$ready" -eq 1 ]] && return 0
    systemctl is-active --quiet nginx-proxy-manager-nginx.service || return 1
    sleep 1
  done
  return 1
}

check "backend service active" systemctl is-active --quiet nginx-proxy-manager-backend.service
check "nginx service active" systemctl is-active --quiet nginx-proxy-manager-nginx.service
check "OpenResty configuration valid" /usr/sbin/nginx -t
check "backend port 3000 listening" port_listening 3000

# Give OpenResty one bounded readiness window before recording the individual
# listener results. The subsequent checks remain explicit for diagnostics.
wait_for_nginx_listeners >/dev/null 2>&1 || true
check "administration port 81 listening" port_listening 81
check "HTTP port 80 listening" port_listening 80
check "HTTPS port 443 listening" port_listening 443
check "administration UI responds" curl -fsS --max-time 10 http://127.0.0.1:81/
check "installed release marker" test -s /etc/nginx-proxy-manager/installation.json
check "no Docker runtime installed" bash -c "! command -v docker && ! command -v podman"

if [[ ${#failures[@]} -gt 0 ]]; then
  printf 'Health check failed (%d): %s\n' "${#failures[@]}" "${failures[*]}" >&2
  exit 1
fi
[[ "$quiet" -eq 1 ]] || echo "All native LXC health checks passed."

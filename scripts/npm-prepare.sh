#!/usr/bin/env bash
set -Eeuo pipefail

NPM_USER="npm"
NPM_GROUP="npm"
ACTIVE_RELEASE="/opt/nginx-proxy-manager/current"
ENV_FILE="/etc/nginx-proxy-manager/environment"

[[ "$(id -u)" -eq 0 ]] || { echo "npm-lxc-prepare must run as root" >&2; exit 1; }
[[ -L "$ACTIVE_RELEASE" && -f "$ACTIVE_RELEASE/index.js" ]] || {
  echo "Active Nginx Proxy Manager release is missing" >&2
  exit 1
}
[[ -f "$ENV_FILE" ]] || { echo "Missing ${ENV_FILE}" >&2; exit 1; }

is_true() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

install -d -o "$NPM_USER" -g "$NPM_GROUP" -m 0750 \
  /data \
  /data/nginx \
  /data/custom_ssl \
  /data/logs \
  /data/access \
  /data/nginx/default_host \
  /data/nginx/default_www \
  /data/nginx/proxy_host \
  /data/nginx/redirection_host \
  /data/nginx/stream \
  /data/nginx/dead_host \
  /data/nginx/temp \
  /data/nginx/custom \
  /data/letsencrypt-acme-challenge \
  /etc/letsencrypt \
  /run/nginx \
  /tmp/nginx/body \
  /tmp/npmuserhome \
  /var/lib/nginx/cache/public \
  /var/lib/nginx/cache/private \
  /var/lib/logrotate \
  /var/cache/nginx/proxy_temp \
  /var/log/nginx

install -d -o root -g root -m 0700 /var/backups/nginx-proxy-manager

# Upstream writes generated include files here. Keep shipped templates root-owned
# and limit the writable include directory to the application group.
install -d -o root -g "$NPM_GROUP" -m 0770 /etc/nginx/conf.d/include
touch /var/log/nginx/error.log
chown "$NPM_USER:$NPM_GROUP" /var/log/nginx/error.log
chmod 0640 /var/log/nginx/error.log
chown -R "$NPM_USER:$NPM_GROUP" /data /etc/letsencrypt /tmp/npmuserhome
chown -R "$NPM_USER:$NPM_GROUP" /run/nginx /tmp/nginx /var/lib/nginx /var/cache/nginx /var/log/nginx
chmod 0600 "$ENV_FILE"

# Translate the official dynamic-resolver preparation into a systemd pre-start
# action without changing Proxmox-owned /etc/resolv.conf.
if ! is_true "${DISABLE_RESOLVER:-false}"; then
  mapfile -t resolvers < <(
    awk '$1 == "nameserver" { sub(/%.*/, "", $2); print $2 }' /etc/resolv.conf
  )
  [[ ${#resolvers[@]} -gt 0 ]] || {
    echo "No resolver found in /etc/resolv.conf" >&2
    exit 1
  }
  rendered=()
  for resolver in "${resolvers[@]}"; do
    if [[ "$resolver" == *:* ]]; then
      rendered+=("[$resolver]")
    else
      rendered+=("$resolver")
    fi
  done
  ipv6_option=""
  is_true "${DISABLE_IPV6:-false}" && ipv6_option=" ipv6=off"
  printf 'resolver %s%s valid=10s;\n' "${rendered[*]}" "$ipv6_option" \
    >/etc/nginx/conf.d/include/resolvers.conf
  chown root:"$NPM_GROUP" /etc/nginx/conf.d/include/resolvers.conf
  chmod 0640 /etc/nginx/conf.d/include/resolvers.conf
fi

# Preserve the official DISABLE_IPV6 behavior without touching any Proxmox
# network configuration. Only Nginx listen directives are toggled. Empty
# custom include files are valid Nginx configuration and must remain empty.
while IFS= read -r -d '' conf; do
  [[ -s "$conf" ]] || continue
  tmp="${conf}.tmp"
  if is_true "${DISABLE_IPV6:-false}"; then
    sed -E 's/^([^#]*)listen \[::\]/\1#listen [::]/g' "$conf" >"$tmp"
  else
    sed -E 's/^(\s*)#listen \[::\]/\1listen [::]/g' "$conf" >"$tmp"
  fi
  if cmp -s "$conf" "$tmp"; then
    rm -f "$tmp"
  else
    mv "$tmp" "$conf"
  fi
done < <(find /etc/nginx/conf.d /data/nginx -type f -name '*.conf' -print0)
chown -R "$NPM_USER:$NPM_GROUP" /data/nginx
find /etc/nginx/conf.d -type f -name '*.conf' -exec chown root:"$NPM_GROUP" {} +

# Upstream deliberately ships this generated file blank; the backend rewrites
# it during its periodic IP-range refresh, so it must remain writable by npm.
ip_ranges_file="/etc/nginx/conf.d/include/ip_ranges.conf"
if [[ -e "$ip_ranges_file" ]]; then
  chown "$NPM_USER:$NPM_GROUP" "$ip_ranges_file"
  chmod 0640 "$ip_ranges_file"
fi

# Required empty custom include files are harmless and prevent include failures.
for name in root_top events http_top http stream root; do
  custom_file="/data/nginx/custom/${name}.conf"
  if [[ ! -e "$custom_file" ]]; then
    install -o "$NPM_USER" -g "$NPM_GROUP" -m 0640 /dev/null "$custom_file"
  fi
done

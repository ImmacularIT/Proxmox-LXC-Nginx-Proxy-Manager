#!/usr/bin/env bash
# Copyright (c) 2026 ImmacularIT
# License: MIT
# Native Debian 13 LXC adaptation of the official Docker-based Nginx Proxy Manager application.
set -Eeuo pipefail

if [[ -n "${FUNCTIONS_FILE_PATH:-}" ]]; then
  # shellcheck disable=SC1090
  source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
  color
  verb_ip6
  catch_errors
  setting_up_container
  network_check
  update_os
fi

: "${STD:=}"
PROJECT_OWNER="ImmacularIT"
PROJECT_REPO="Proxmox-LXC-Nginx-Proxy-Manager"
PROJECT_REF="${NPM_PROJECT_REF:-develop/native-lxc-v2.15.1}"
PROJECT_RAW="https://raw.githubusercontent.com/${PROJECT_OWNER}/${PROJECT_REPO}/${PROJECT_REF}"
EXPECTED_NPM_COMMIT="76f09db610cfcaecf6d608a8947d6f75aa028870"
EXPECTED_NPM_BASE_COMMIT="fe5ba055ed29033a619e9103bef5d8218fe1fab0"
EXPECTED_CERTBOT_VERSION="5.6.0"
EXPECTED_PYOPENSSL_VERSION="26.2.0"
EXPECTED_CRYPTOGRAPHY_VERSION="48.0.0"
LIB_DIR="/usr/local/lib/npm-lxc"
BUILD_ROOT="/var/tmp/npm-native-build"

info() { if declare -F msg_info >/dev/null; then msg_info "$1"; else printf '==> %s\n' "$1"; fi; }
ok() { if declare -F msg_ok >/dev/null; then msg_ok "$1"; else printf 'OK: %s\n' "$1"; fi; }
fatal() { if declare -F msg_error >/dev/null; then msg_error "$1"; else printf 'ERROR: %s\n' "$1" >&2; fi; exit 1; }

project_download() {
  local destination path url
  destination="$1"
  path="$2"
  url="${PROJECT_RAW}/${path}"
  install -d -m 0755 "$(dirname "$destination")"
  if declare -F curl_download >/dev/null; then
    curl_download "$destination" "$url"
  else
    curl -fsSL --retry 3 --retry-delay 2 -o "$destination" "$url"
  fi
  [[ -s "$destination" ]] || fatal "Downloaded an empty project file: ${path}"
}

[[ "$(id -u)" -eq 0 ]] || fatal "The container installer must run as root"
[[ "$(. /etc/os-release; printf '%s' "$ID")" == "debian" ]] || fatal "Debian is required"
[[ "$(. /etc/os-release; printf '%s' "$VERSION_ID")" == "13" ]] || fatal "Debian 13 is required"
case "$(dpkg --print-architecture)" in
  amd64) ;;
  arm64) fatal "ARM64 is not enabled until a complete native runtime test passes" ;;
  *) fatal "Unsupported architecture: $(dpkg --print-architecture)" ;;
esac

info "Installing native build and runtime dependencies"
$STD apt-get update
$STD apt-get install -y --no-install-recommends \
  apache2-utils apt-transport-https build-essential ca-certificates cargo curl dos2unix gettext git gnupg jq \
  libaugeas0 libffi-dev liblua5.1-0-dev libmaxminddb-dev libncurses-dev libpcre2-dev \
  libreadline-dev libssl-dev logrotate lua5.1 moreutils openssl pkg-config procps \
  perl python3 python3-dev python3-venv rsync rustc socat sqlite3 tar tzdata unzip wget xz-utils \
  zlib1g-dev iproute2
ok "Installed native build and runtime dependencies"

info "Creating dedicated application identity"
getent group npm >/dev/null || groupadd --system npm
id npm >/dev/null 2>&1 || useradd --system --gid npm --home-dir /tmp/npmuserhome --shell /usr/sbin/nologin npm
install -d -o npm -g npm -m 0750 /tmp/npmuserhome
ok "Created dedicated application identity"

info "Installing Node.js 22 and Yarn Classic"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
chmod 0644 /etc/apt/keyrings/nodesource.gpg
node_arch="$(dpkg --print-architecture)"
cat >/etc/apt/sources.list.d/nodesource.sources <<NODE_REPO
Types: deb
URIs: https://deb.nodesource.com/node_22.x
Suites: nodistro
Components: main
Architectures: ${node_arch}
Signed-By: /etc/apt/keyrings/nodesource.gpg
NODE_REPO
$STD apt-get update
$STD apt-get install -y nodejs
npm install --global yarn@1.22.22
[[ "$(node --version)" == v22.* ]] || fatal "Node.js 22 validation failed"
[[ "$(yarn --version)" == "1.22.22" ]] || fatal "Yarn validation failed"
ok "Installed Node.js $(node --version) and Yarn $(yarn --version)"

info "Installing pinned Certbot environment"
rm -rf /opt/certbot
python3 -m venv /opt/certbot
/opt/certbot/bin/pip install --disable-pip-version-check --no-cache-dir --upgrade pip
# The pinned upstream Dockerfile currently requests pyOpenSSL 24.3.0 together
# with cryptography 48.0.0. Those declared dependency ranges conflict. Keep
# the upstream cryptography pin and use pyOpenSSL 26.2.0, which explicitly
# supports cryptography 48.x and Python 3.13.
/opt/certbot/bin/pip install --disable-pip-version-check --no-cache-dir \
  "pyopenssl==${EXPECTED_PYOPENSSL_VERSION}" 'cffi' \
  "certbot==${EXPECTED_CERTBOT_VERSION}" "cryptography==${EXPECTED_CRYPTOGRAPHY_VERSION}" \
  'tldextract' 'zope' 'pip-system-certs'
ln -sfn /opt/certbot/bin/certbot /usr/local/bin/certbot
certbot_version="$(/usr/local/bin/certbot --version | awk '{print $2}')"
pyopenssl_version="$(/opt/certbot/bin/python -c 'import importlib.metadata; print(importlib.metadata.version("pyopenssl"))')"
cryptography_version="$(/opt/certbot/bin/python -c 'import importlib.metadata; print(importlib.metadata.version("cryptography"))')"
[[ "$certbot_version" == "$EXPECTED_CERTBOT_VERSION" ]] || fatal "Certbot version validation failed: ${certbot_version}"
[[ "$pyopenssl_version" == "$EXPECTED_PYOPENSSL_VERSION" ]] || fatal "pyOpenSSL version validation failed: ${pyopenssl_version}"
[[ "$cryptography_version" == "$EXPECTED_CRYPTOGRAPHY_VERSION" ]] || fatal "cryptography version validation failed: ${cryptography_version}"
/opt/certbot/bin/pip check >/dev/null || fatal "Certbot Python environment has unresolved dependency conflicts"
chown -R npm:npm /opt/certbot
ok "Installed Certbot ${certbot_version} (pyOpenSSL ${pyopenssl_version}, cryptography ${cryptography_version})"

info "Installing project-owned native service tooling"
install -d -o root -g root -m 0755 "$LIB_DIR"
project_download "$LIB_DIR/versions.sh" lib/versions.sh
# shellcheck source=/dev/null
source "$LIB_DIR/versions.sh"
[[ "$NPM_COMMIT" == "$EXPECTED_NPM_COMMIT" ]] || fatal "Project version manifest has an unexpected NPM commit"
[[ "$NPM_BASE_COMMIT" == "$EXPECTED_NPM_BASE_COMMIT" ]] || fatal "Project version manifest has an unexpected base-image commit"
[[ "$CERTBOT_VERSION" == "$EXPECTED_CERTBOT_VERSION" ]] || fatal "Project version manifest has an unexpected Certbot version"
[[ "$PYOPENSSL_VERSION" == "$EXPECTED_PYOPENSSL_VERSION" ]] || fatal "Project version manifest has an unexpected pyOpenSSL version"
[[ "$CRYPTOGRAPHY_VERSION" == "$EXPECTED_CRYPTOGRAPHY_VERSION" ]] || fatal "Project version manifest has an unexpected cryptography version"
for script in build-openresty-native.sh install-release.sh; do
  project_download "$LIB_DIR/$script" "scripts/$script"
  chmod 0755 "$LIB_DIR/$script"
done
project_download /usr/local/sbin/npm-lxc-prepare scripts/npm-prepare.sh
project_download /usr/local/sbin/npm-lxc-healthcheck scripts/npm-healthcheck.sh
project_download /usr/local/sbin/npm-lxc-backup scripts/npm-backup.sh
project_download /usr/local/sbin/npm-lxc-restore scripts/npm-restore.sh
project_download /usr/local/sbin/npm-lxc-update scripts/npm-update.sh
chmod 0755 /usr/local/sbin/npm-lxc-{prepare,healthcheck,backup,restore,update}
project_download /etc/systemd/system/nginx-proxy-manager-backend.service systemd/nginx-proxy-manager-backend.service
project_download /etc/systemd/system/nginx-proxy-manager-nginx.service systemd/nginx-proxy-manager-nginx.service
ok "Installed project-owned native service tooling"

info "Building the pinned official OpenResty environment"
BUILD_ROOT="$BUILD_ROOT" "$LIB_DIR/build-openresty-native.sh"
ok "Built OpenResty ${OPENRESTY_VERSION}"

info "Building Nginx Proxy Manager ${NPM_RELEASE} from official source"
BUILD_ROOT="$BUILD_ROOT" "$LIB_DIR/install-release.sh"
release_dir="/opt/nginx-proxy-manager/releases/${NPM_VERSION}"
[[ -f "$release_dir/index.js" ]] || fatal "Built release is missing: ${release_dir}"
install -d -o root -g root -m 0755 /opt/nginx-proxy-manager
ln -sfn "$release_dir" /opt/nginx-proxy-manager/current
if [[ -e /app && ! -L /app ]]; then
  fatal "Refusing to replace an existing non-symlink /app path"
fi
rm -f /app
ln -s /opt/nginx-proxy-manager/current /app
ok "Built Nginx Proxy Manager ${NPM_RELEASE}"

info "Installing official runtime templates"
rsync -a "$release_dir/share/upstream-rootfs/etc/nginx/" /etc/nginx/
rm -f /etc/nginx/conf.d/dev.conf
install -d -m 0755 /etc/logrotate.d /var/www/html
install -m 0644 "$release_dir/share/upstream-rootfs/etc/logrotate.d/nginx-proxy-manager" /etc/logrotate.d/nginx-proxy-manager
install -m 0644 "$release_dir/share/upstream-rootfs/etc/letsencrypt.ini" /etc/letsencrypt.ini
rsync -a --delete "$release_dir/share/upstream-rootfs/var/www/html/" /var/www/html/
chmod 0644 /etc/logrotate.d/nginx-proxy-manager /etc/letsencrypt.ini
ok "Installed official runtime templates"

info "Creating protected native configuration"
install -d -o root -g root -m 0700 /etc/nginx-proxy-manager
cat >/etc/nginx-proxy-manager/environment <<ENVIRONMENT
NODE_ENV=production
NODE_OPTIONS=--openssl-legacy-provider
SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
NPM_BUILD_VERSION=${NPM_VERSION}
NPM_BUILD_COMMIT=${NPM_COMMIT}
NPM_BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DB_SQLITE_FILE=/data/database.sqlite
DISABLE_IPV6=false
DISABLE_RESOLVER=false
IP_RANGES_FETCH_ENABLED=true
HOME=/tmp/npmuserhome
CERTBOT_VERSION=${CERTBOT_VERSION}
ENVIRONMENT
chmod 0600 /etc/nginx-proxy-manager/environment

/usr/local/sbin/npm-lxc-prepare
systemctl daemon-reload
systemctl enable nginx-proxy-manager-backend.service nginx-proxy-manager-nginx.service

cat >/etc/nginx-proxy-manager/installation.json <<MANIFEST
{
  "adaptation_version": "${ADAPTATION_VERSION}",
  "upstream_release": "${NPM_RELEASE}",
  "upstream_commit": "${NPM_COMMIT}",
  "upstream_base_commit": "${NPM_BASE_COMMIT}",
  "openresty_version": "${OPENRESTY_VERSION}",
  "openresty_commit": "${OPENRESTY_COMMIT}",
  "node_version": "$(node --version)",
  "yarn_version": "$(yarn --version)",
  "certbot_version": "${certbot_version}",
  "pyopenssl_version": "${pyopenssl_version}",
  "cryptography_version": "${cryptography_version}",
  "database_engine": "SQLite (better-sqlite3)",
  "operating_system": "$(. /etc/os-release; printf '%s %s' "$PRETTY_NAME" "$VERSION_ID")",
  "architecture": "$(dpkg --print-architecture)",
  "installed_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "active_release": "${release_dir}",
  "runtime_test_status": "UNTESTED"
}
MANIFEST
chmod 0600 /etc/nginx-proxy-manager/installation.json
ok "Created protected native configuration"

info "Starting native services"
systemctl start nginx-proxy-manager-backend.service
backend_ready=0
for _ in {1..180}; do
  if ss -ltnH 'sport = :3000' | grep -q .; then
    backend_ready=1
    break
  fi
  if ! systemctl is-active --quiet nginx-proxy-manager-backend.service; then
    journalctl -u nginx-proxy-manager-backend.service --no-pager -n 100 >&2 || true
    fatal "Backend service exited during startup"
  fi
  sleep 1
done
[[ "$backend_ready" -eq 1 ]] || fatal "Backend did not listen on port 3000"
systemctl start nginx-proxy-manager-nginx.service
/usr/local/sbin/npm-lxc-healthcheck
ok "Started native Nginx Proxy Manager services"

rm -rf "$BUILD_ROOT"
apt-get clean
rm -rf /var/lib/apt/lists/*

if declare -F motd_ssh >/dev/null; then motd_ssh; fi
if declare -F customize >/dev/null; then customize; fi
if declare -F cleanup_lxc >/dev/null; then cleanup_lxc; fi

echo
echo "Nginx Proxy Manager ${NPM_RELEASE} is installed natively without a nested container runtime."
echo "Open the administration interface on port 81 and complete the official first-run setup wizard."
echo "No default administrator credentials were created."

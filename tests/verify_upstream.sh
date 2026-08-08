#!/usr/bin/env bash
set -Eeuo pipefail
trap 'rc=$?; echo "Upstream verification failed at line ${LINENO}: ${BASH_COMMAND}" >&2; exit "$rc"' ERR

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/versions.sh
source "$ROOT/lib/versions.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git init -q "$tmp/npm"
git -C "$tmp/npm" remote add origin "$NPM_REPOSITORY"
git -C "$tmp/npm" fetch -q --depth 1 origin "$NPM_COMMIT"
git -C "$tmp/npm" checkout -q --detach FETCH_HEAD
[[ "$(git -C "$tmp/npm" rev-parse HEAD)" == "$NPM_COMMIT" ]]
[[ "$(<"$tmp/npm/.version")" == "$NPM_VERSION" ]]

verify_blob() {
  local path="$1" expected="$2" actual
  actual="$(git -C "$tmp/npm" hash-object "$tmp/npm/$path")"
  [[ "$actual" == "$expected" ]] || {
    echo "Blob mismatch: ${path}: ${actual} != ${expected}" >&2
    exit 1
  }
}
verify_blob docker/Dockerfile "$NPM_DOCKERFILE_BLOB"
verify_blob backend/package.json "$NPM_BACKEND_PACKAGE_BLOB"
verify_blob backend/yarn.lock "$NPM_BACKEND_LOCK_BLOB"
verify_blob frontend/package.json "$NPM_FRONTEND_PACKAGE_BLOB"
verify_blob frontend/yarn.lock "$NPM_FRONTEND_LOCK_BLOB"
verify_blob docker/rootfs/etc/nginx/nginx.conf "$NPM_NGINX_CONFIG_BLOB"

for path in \
  backend/index.js backend/migrate.js backend/setup.js backend/lib/config.js \
  backend/migrations frontend/yarn.lock docker/rootfs/etc/nginx/conf.d/production.conf \
  docker/rootfs/etc/s6-overlay/s6-rc.d/prepare/00-all.sh \
  docker/rootfs/etc/s6-overlay/s6-rc.d/backend/run \
  docker/rootfs/etc/s6-overlay/s6-rc.d/nginx/run; do
  [[ -e "$tmp/npm/$path" ]] || { echo "Expected upstream path missing: ${path}" >&2; exit 1; }
done

git init -q "$tmp/base"
git -C "$tmp/base" remote add origin "$NPM_BASE_REPOSITORY"
git -C "$tmp/base" fetch -q --depth 1 origin "$NPM_BASE_COMMIT"
git -C "$tmp/base" checkout -q --detach FETCH_HEAD
[[ "$(git -C "$tmp/base" rev-parse HEAD)" == "$NPM_BASE_COMMIT" ]]
verify_base_blob() {
  local path="$1" expected="$2" actual
  actual="$(git -C "$tmp/base" hash-object "$tmp/base/$path")"
  [[ "$actual" == "$expected" ]] || {
    echo "Base-image blob mismatch: ${path}: ${actual} != ${expected}" >&2
    exit 1
  }
}
verify_base_blob docker/Dockerfile "$NPM_BASE_DOCKERFILE_BLOB"
verify_base_blob docker/Dockerfile.certbot "$NPM_BASE_CERTBOT_DOCKERFILE_BLOB"
verify_base_blob docker/Dockerfile.certbot-node "$NPM_BASE_CERTBOT_NODE_DOCKERFILE_BLOB"
verify_base_blob scripts/build-lua.sh "$NPM_BASE_BUILD_LUA_BLOB"
verify_base_blob scripts/build-openresty.sh "$NPM_BASE_BUILD_OPENRESTY_BLOB"
verify_base_blob scripts/install-openresty.sh "$NPM_BASE_INSTALL_OPENRESTY_BLOB"

grep -F 'FROM debian:trixie-slim' "$tmp/base/docker/Dockerfile" >/dev/null
grep -F 'https://deb.nodesource.com/setup_22.x' "$tmp/base/docker/Dockerfile.certbot-node" >/dev/null
grep -F -- '--with-http_v3_module' "$tmp/base/scripts/build-openresty.sh" >/dev/null
grep -F -- '--with-stream' "$tmp/base/scripts/build-openresty.sh" >/dev/null

echo "Pinned upstream Docker-derived markers verified."

#!/usr/bin/env bash
set -Eeuo pipefail

# Use a neutral UTF-8 process locale for deterministic build output. This avoids
# warnings when Proxmox passes host locale names that are not generated inside
# a fresh minimal Debian container, without changing the container's locale.
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

LIB_DIR="${NPM_LXC_LIB_DIR:-/usr/local/lib/npm-lxc}"
if [[ -r "$LIB_DIR/versions.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/versions.sh"
else
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=../lib/versions.sh
  source "$SCRIPT_DIR/../lib/versions.sh"
fi

RELEASE_ROOT="${RELEASE_ROOT:-/opt/nginx-proxy-manager/releases}"
BUILD_ROOT="${BUILD_ROOT:-/var/tmp/npm-native-build}"
SOURCE_DIR="$BUILD_ROOT/nginx-proxy-manager-${NPM_VERSION}"
STAGING_DIR="$RELEASE_ROOT/.${NPM_VERSION}.staging"
FINAL_DIR="$RELEASE_ROOT/${NPM_VERSION}"

clone_exact() {
  local repo="$1" commit="$2" dest="$3"
  rm -rf "$dest"
  git init -q "$dest"
  git -C "$dest" remote add origin "$repo"
  git -C "$dest" fetch -q --depth 1 origin "$commit"
  git -C "$dest" checkout -q --detach FETCH_HEAD
  local actual
  actual="$(git -C "$dest" rev-parse HEAD)"
  [[ "$actual" == "$commit" ]] || {
    echo "Expected ${commit}; fetched ${actual}" >&2
    exit 1
  }
}

verify_blob() {
  local path="$1" expected="$2" actual
  actual="$(git -C "$SOURCE_DIR" hash-object "$SOURCE_DIR/$path")"
  [[ "$actual" == "$expected" ]] || {
    echo "Upstream marker changed: ${path} (${actual}, expected ${expected})" >&2
    exit 1
  }
}

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
[[ "$(node --version)" == v${NODE_MAJOR}.* ]] || {
  echo "Node.js ${NODE_MAJOR}.x is required" >&2
  exit 1
}
[[ "$(yarn --version)" == "$YARN_VERSION" ]] || {
  echo "Yarn ${YARN_VERSION} is required" >&2
  exit 1
}

mkdir -p "$RELEASE_ROOT" "$BUILD_ROOT"
clone_exact "$NPM_REPOSITORY" "$NPM_COMMIT" "$SOURCE_DIR"
[[ "$(<"$SOURCE_DIR/.version")" == "$NPM_VERSION" ]] || {
  echo "Release marker does not match ${NPM_VERSION}" >&2
  exit 1
}
verify_blob docker/Dockerfile "$NPM_DOCKERFILE_BLOB"
verify_blob backend/package.json "$NPM_BACKEND_PACKAGE_BLOB"
verify_blob backend/yarn.lock "$NPM_BACKEND_LOCK_BLOB"
verify_blob frontend/package.json "$NPM_FRONTEND_PACKAGE_BLOB"
verify_blob frontend/yarn.lock "$NPM_FRONTEND_LOCK_BLOB"
verify_blob docker/rootfs/etc/nginx/nginx.conf "$NPM_NGINX_CONFIG_BLOB"

export NODE_OPTIONS="--openssl-legacy-provider"

pushd "$SOURCE_DIR/frontend" >/dev/null
NODE_ENV=development yarn install --frozen-lockfile --non-interactive --production=false
# The pinned upstream source does not commit frontend/src/locale/lang/*.json.
# Its official CI compiles them from frontend/src/locale/src before `yarn build`.
yarn locale-compile
[[ -f src/locale/lang/en.json && -f src/locale/lang/lang-list.json ]] || {
  echo "Frontend locale compilation did not create the expected language files" >&2
  exit 1
}
NODE_ENV=production yarn build
[[ -f dist/index.html ]] || { echo "Frontend build did not create dist/index.html" >&2; exit 1; }
popd >/dev/null

pushd "$SOURCE_DIR/backend" >/dev/null
NODE_ENV=production yarn install --frozen-lockfile --non-interactive --production=true
[[ -f index.js && -d node_modules ]] || { echo "Backend dependency installation failed" >&2; exit 1; }
# Peer/type-package warnings from Yarn do not prove runtime breakage. The
# initial supported database is SQLite, so directly load the native binding
# under the exact Node.js runtime before accepting the release.
NODE_ENV=production node --input-type=module -e "await import('better-sqlite3')"
popd >/dev/null

rm -rf "$STAGING_DIR"
install -d -m 0755 "$STAGING_DIR"
rsync -a --delete \
  --exclude='.git' \
  --exclude='test' \
  "$SOURCE_DIR/backend/" "$STAGING_DIR/"
install -d -m 0755 "$STAGING_DIR/frontend"
rsync -a --delete "$SOURCE_DIR/frontend/dist/" "$STAGING_DIR/frontend/"
install -d -m 0755 "$STAGING_DIR/share/upstream-rootfs"
rsync -a "$SOURCE_DIR/docker/rootfs/" "$STAGING_DIR/share/upstream-rootfs/"

# The verified upstream v2.15.1 source intentionally keeps backend/package.json
# at the generic application version 2.0.0, while runtime API/update endpoints
# read that field directly. The official Docker build carries the real release
# separately as BUILD_VERSION/NPM_BUILD_VERSION. For the native release, stamp
# only the staged runtime copy after all immutable source/blob checks so the API
# reports the same verified release as .version without altering source proof.
node --input-type=module - "$STAGING_DIR/package.json" "$NPM_VERSION" <<'NODE'
import fs from "node:fs";
const [, , packagePath, releaseVersion] = process.argv;
const pkg = JSON.parse(fs.readFileSync(packagePath, "utf8"));
pkg.version = releaseVersion;
fs.writeFileSync(packagePath, `${JSON.stringify(pkg, null, "\t")}\n`);
NODE
staged_version="$(node --input-type=module -e "import pkg from '${STAGING_DIR}/package.json' with { type: 'json' }; console.log(pkg.version)")"
[[ "$staged_version" == "$NPM_VERSION" ]] || {
  echo "Staged backend version metadata mismatch: ${staged_version}" >&2
  exit 1
}

printf '%s\n' "$NPM_RELEASE" >"$STAGING_DIR/.upstream-release"
printf '%s\n' "$NPM_COMMIT" >"$STAGING_DIR/.upstream-commit"
printf '%s\n' "$NPM_BASE_COMMIT" >"$STAGING_DIR/.upstream-base-commit"
printf '%s\n' "$ADAPTATION_VERSION" >"$STAGING_DIR/.adaptation-version"
chmod -R u+rwX,go+rX,go-w "$STAGING_DIR"
chown -R root:npm "$STAGING_DIR"

if [[ -e "$FINAL_DIR" ]]; then
  echo "Release directory already exists: ${FINAL_DIR}" >&2
  rm -rf "$STAGING_DIR"
  exit 1
fi
mv "$STAGING_DIR" "$FINAL_DIR"
printf '%s\n' "$FINAL_DIR"

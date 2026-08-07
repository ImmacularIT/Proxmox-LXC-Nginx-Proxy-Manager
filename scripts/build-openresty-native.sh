#!/usr/bin/env bash
set -Eeuo pipefail

# Build under Debian's always-available neutral UTF-8 locale. Proxmox may pass
# host LC_* values into the container before those locales have been generated,
# which otherwise causes extremely noisy Perl warnings during OpenResty builds.
# This changes only this build process; it does not rewrite the container locale.
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

BUILD_ROOT="${BUILD_ROOT:-/var/tmp/npm-native-build}"
OPENRESTY_JOBS="${OPENRESTY_JOBS:-$(nproc)}"
LUAROCKS_BIN="/usr/local/bin/luarocks"

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
    echo "Expected ${commit} from ${repo}, got ${actual}" >&2
    exit 1
  }
}

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
mkdir -p "$BUILD_ROOT"

# Debian 13 supplies Lua 5.1.5. The explicit check preserves the official base
# image's Lua ABI while avoiding an unverified HTTP tarball download.
lua_version="$(lua5.1 -v 2>&1 | awk '{print $2}')"
[[ "$lua_version" == "$LUA_VERSION" ]] || {
  echo "Expected Lua ${LUA_VERSION}; found ${lua_version}" >&2
  exit 1
}

clone_exact "https://github.com/luarocks/luarocks.git" "$LUAROCKS_COMMIT" "$BUILD_ROOT/luarocks"
pushd "$BUILD_ROOT/luarocks" >/dev/null
./configure --with-lua=/usr --with-lua-include=/usr/include/lua5.1 --lua-version=5.1
make -j"$OPENRESTY_JOBS"
make install
popd >/dev/null
[[ -x "$LUAROCKS_BIN" ]] || {
  echo "LuaRocks executable was not installed at ${LUAROCKS_BIN}" >&2
  exit 1
}
[[ "$("$LUAROCKS_BIN" --version | head -n1)" == *"${LUAROCKS_VERSION}"* ]] || {
  echo "LuaRocks version validation failed" >&2
  exit 1
}

clone_exact "https://github.com/openresty/openresty.git" "$OPENRESTY_COMMIT" "$BUILD_ROOT/openresty-src"
clone_exact "https://github.com/leev/ngx_http_geoip2_module.git" "$GEOIP2_COMMIT" "$BUILD_ROOT/ngx_http_geoip2_module"

pushd "$BUILD_ROOT/openresty-src" >/dev/null
[[ "$(./util/ver)" == "$OPENRESTY_VERSION" ]] || {
  echo "OpenResty tag/commit version mismatch" >&2
  exit 1
}
make
popd >/dev/null

OPENRESTY_TREE="$BUILD_ROOT/openresty-src/openresty-${OPENRESTY_VERSION}"
[[ -d "$OPENRESTY_TREE" ]] || {
  echo "OpenResty generated source tree missing: ${OPENRESTY_TREE}" >&2
  exit 1
}

pushd "$OPENRESTY_TREE" >/dev/null
./configure \
  --prefix=/etc/nginx \
  --sbin-path=/usr/sbin/nginx \
  --modules-path=/usr/lib/nginx/modules \
  --conf-path=/etc/nginx/nginx.conf \
  --error-log-path=/var/log/nginx/error.log \
  --http-log-path=/var/log/nginx/access.log \
  --pid-path=/var/run/nginx.pid \
  --lock-path=/var/run/nginx.lock \
  --http-client-body-temp-path=/var/cache/nginx/client_temp \
  --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
  --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
  --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
  --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
  --user=npm \
  --group=npm \
  --with-compat \
  --with-threads \
  --with-http_addition_module \
  --with-http_auth_request_module \
  --with-http_dav_module \
  --with-http_flv_module \
  --with-http_gunzip_module \
  --with-http_gzip_static_module \
  --with-http_mp4_module \
  --with-http_random_index_module \
  --with-http_realip_module \
  --with-http_secure_link_module \
  --with-http_slice_module \
  --with-http_ssl_module \
  --with-http_stub_status_module \
  --with-http_sub_module \
  --with-http_v2_module \
  --with-http_v3_module \
  --with-mail \
  --with-mail_ssl_module \
  --with-stream \
  --with-stream_realip_module \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module \
  --add-dynamic-module="$BUILD_ROOT/ngx_http_geoip2_module"
make -j"$OPENRESTY_JOBS"
make install
popd >/dev/null

# Pin the rock versions that were current when the selected official base image
# was built. This closes the moving-LuaRocks dependency left by upstream.
"$LUAROCKS_BIN" install lua-cjson "$LUA_CJSON_ROCK"
"$LUAROCKS_BIN" install lua-resty-http "$LUA_RESTY_HTTP_ROCK"
"$LUAROCKS_BIN" install lua-resty-openidc "$LUA_RESTY_OPENIDC_ROCK"

nginx -V 2>&1 | grep -F -- "--with-http_v3_module" >/dev/null
nginx -V 2>&1 | grep -F -- "--with-stream" >/dev/null
nginx -V 2>&1 | grep -F -- "--add-dynamic-module=${BUILD_ROOT}/ngx_http_geoip2_module" >/dev/null
printf '%s\n' "$OPENRESTY_VERSION" >/etc/nginx/openresty-version
#!/usr/bin/env bash
# Canonical, reviewable version pins for the native LXC adaptation.

readonly ADAPTATION_VERSION="0.1.1-dev"
readonly NPM_RELEASE="v2.15.1"
readonly NPM_VERSION="2.15.1"
readonly NPM_COMMIT="76f09db610cfcaecf6d608a8947d6f75aa028870"
readonly NPM_REPOSITORY="https://github.com/NginxProxyManager/nginx-proxy-manager.git"
readonly NPM_DOCKERFILE_BLOB="01b478b0e157bfb9f2c44e57d5dd1062a549d037"
readonly NPM_BACKEND_PACKAGE_BLOB="80ae74b45e45f05cb90a8d627800c502b1421986"
readonly NPM_BACKEND_LOCK_BLOB="427e834fa11c29dfca8be5a6a11fac2a54c662fa"
readonly NPM_FRONTEND_PACKAGE_BLOB="769a2a7702ea69ebd363aa7e3a7d280ec89103b2"
readonly NPM_FRONTEND_LOCK_BLOB="d5f803762f90cd7e126270b0ba154d9caad85936"
readonly NPM_NGINX_CONFIG_BLOB="bdba3b3055400e1cfc6c01788354560ad87c3daf"

# Source of the official nginxproxymanager/nginx-full:certbot-node base image
# used by the selected NPM release.
readonly NPM_BASE_REPOSITORY="https://github.com/NginxProxyManager/docker-nginx-full.git"
readonly NPM_BASE_COMMIT="fe5ba055ed29033a619e9103bef5d8218fe1fab0"
readonly NPM_BASE_DOCKERFILE_BLOB="3837f53f9553ca15d1a420297d7a9d9a2b179b4c"
readonly NPM_BASE_CERTBOT_DOCKERFILE_BLOB="27847736cda2053880267613aa1ec9acf3dbba38"
readonly NPM_BASE_CERTBOT_NODE_DOCKERFILE_BLOB="73dd3e3d5be801cabcb8a7a6e25d10387d091ef1"
readonly NPM_BASE_BUILD_LUA_BLOB="f13ac9814c7bdaf6047bb73b6f01b71bee9331a8"
readonly NPM_BASE_BUILD_OPENRESTY_BLOB="433373cb54b93aa2539cd04edac19ea069c471ca"
readonly NPM_BASE_INSTALL_OPENRESTY_BLOB="537ef037ed6ece9abf32858682fe448a6169622a"

readonly OPENRESTY_VERSION="1.29.2.5"
readonly OPENRESTY_COMMIT="2ec0f65e434c92e9f78fd5c3af601a6b286c6d2b"
readonly GEOIP2_COMMIT="445df24ef3781e488cee3dfe8a1e111997fc1dfe"
readonly LUA_VERSION="5.1.5"
readonly LUAROCKS_VERSION="3.13.0"
readonly LUAROCKS_COMMIT="3421bedc2ce2b64e79530bb97497531b014899a8"
readonly LUA_CJSON_ROCK="2.1.0.10-1"
readonly LUA_RESTY_OPENIDC_ROCK="1.8.0-1"
readonly LUA_RESTY_HTTP_ROCK="0.17.2-0"
readonly CERTBOT_VERSION="5.6.0"
# The pinned upstream Dockerfile currently combines pyOpenSSL 24.3.0 with
# cryptography 48.0.0, whose declared dependency ranges conflict. The native
# adaptation keeps upstream cryptography 48.0.0 and pins the first pyOpenSSL
# release that explicitly supports cryptography 48.x.
readonly PYOPENSSL_VERSION="26.2.0"
readonly CRYPTOGRAPHY_VERSION="48.0.0"
readonly NODE_MAJOR="22"
readonly YARN_VERSION="1.22.22"

# Generic Proxmox LXC builder only. It is not an application source and this
# repository is not an official Community Scripts project.
readonly PVE_BUILD_COMMIT="5ddc4a2a41991324a534dd02b81fe3bc5a3bca04"
readonly GUACAMOLE_BRANDING_COMMIT="15c268e6fd0e6f9b441aa9f785c278c3f580171b"

# Project technical handoff

This document records the architecture, implementation, maintenance workflow,
known risks, and test state for `ImmacularIT/Proxmox-LXC-Nginx-Proxy-Manager`.

**Status snapshot:** 2026-08-06
**Project state:** development draft; no Proxmox runtime test completed
**Target platform:** Proxmox VE 9.x, unprivileged Debian 13 LXC
**Pinned upstream release:** `v2.15.1`
**Pinned upstream commit:** `76f09db610cfcaecf6d608a8947d6f75aa028870`
**Pinned official base-image source:** `fe5ba055ed29033a619e9103bef5d8218fe1fab0`

Do not promote this branch to production or merge it into `main` until the
runtime test plan reflects real results.

## Executive summary

The official Nginx Proxy Manager project packages its application as a Docker
image. That image combines a Node.js backend, a compiled React frontend,
OpenResty/Nginx, Lua modules, Certbot, initialization scripts, and s6-overlay
service supervision. It exposes ports 80, 81, and 443 and persists `/data` and
`/etc/letsencrypt`.

This adaptation treats the official Docker implementation as the executable
specification and recreates it directly in Debian 13. The application source is
not replaced, forked, or reimplemented. Exact official commits are fetched and
built into versioned release directories. Docker-specific initialization is
translated into root-only installation work, a systemd pre-start helper, and
normal systemd services.

The final design contains no nested container runtime.

## Authoritative upstream sources

Application:

- repository: `https://github.com/NginxProxyManager/nginx-proxy-manager`
- release: `v2.15.1`
- commit: `76f09db610cfcaecf6d608a8947d6f75aa028870`

Official base image source:

- repository: `https://github.com/NginxProxyManager/docker-nginx-full`
- commit: `fe5ba055ed29033a619e9103bef5d8218fe1fab0`

Supporting source pins:

- OpenResty `1.29.2.5`, commit `2ec0f65e434c92e9f78fd5c3af601a6b286c6d2b`;
- GeoIP2 module commit `445df24ef3781e488cee3dfe8a1e111997fc1dfe`;
- LuaRocks `3.13.0`, commit `3421bedc2ce2b64e79530bb97497531b014899a8`;
- Lua `5.1.5` from Debian 13 packages;
- Node.js major `22`;
- Yarn `1.22.22`;
- Certbot `5.6.0`.

The generic Proxmox LXC builder is pinned to Community Scripts commit
`5ddc4a2a41991324a534dd02b81fe3bc5a3bca04`. It is used only for Proxmox host
container creation and menu behavior. It is not an application source, and the
project is not represented as an official Community Script.

## Official Docker-to-native mapping

| Official Docker component or behavior | Native Debian 13 LXC translation |
|---|---|
| `debian:trixie-slim` base | Proxmox Debian 13 LXC template and explicit APT packages |
| `nginxproxymanager/nginx-full:certbot-node` | OpenResty built from the pinned official base-image recipe, Node.js 22 APT packages, Yarn Classic, and a pinned Certbot Python virtual environment |
| `docker/Dockerfile` copies `backend` to `/app` | Official backend built under `/opt/nginx-proxy-manager/releases/<version>`; `/app` is a compatibility symlink to the active release |
| Prebuilt `frontend/dist` copied to `/app/frontend` | Frontend built with its official Yarn v1 lockfile and copied into the active release's `frontend` directory |
| `yarn install` for backend | `yarn install --frozen-lockfile --production=true`, including native Node modules |
| s6 `backend` longrun | `nginx-proxy-manager-backend.service` |
| s6 `nginx` longrun | `nginx-proxy-manager-nginx.service` |
| s6 restart loop around Node | systemd `Restart=on-failure` and `RestartSec=2s` |
| s6 prepare `10-usergroup.sh` | fixed dedicated `npm` system user and group created at installation |
| s6 prepare `20-paths.sh` | `npm-lxc-prepare` creates all required persistent, runtime, cache, and log paths |
| s6 prepare `30-ownership.sh` | explicit ownership and restrictive modes in `npm-lxc-prepare` |
| s6 prepare `40-dynamic.sh` | systemd pre-start resolver generation using Proxmox-managed `/etc/resolv.conf` without modifying it |
| s6 prepare `50-ipv6.sh` | checked Nginx-only toggle of IPv6 listen directives; no LXC network changes |
| s6 prepare `60-secrets.sh` | root-only environment file; `_FILE` secret indirection is not needed for the initial local-SQLite path |
| s6 prepare `90-banner.sh` | omitted as cosmetic Docker-console output |
| `/init` s6 entrypoint | normal system boot and explicit systemd dependencies |
| `/data` Docker volume | `/data`, retained as the official application path |
| `/etc/letsencrypt` Docker volume | `/etc/letsencrypt`, retained as the official certificate path |
| internal backend port 3000 | loopback/internal service port; not a documented external port |
| exposed ports 80, 81, 443 | OpenResty binds with systemd `CAP_NET_BIND_SERVICE`; Proxmox/network firewall controls exposure |
| Docker test CA copied into trust store | deliberately omitted; a production LXC must not trust the upstream image's test-only CA |
| s6 environment processing | protected `/etc/nginx-proxy-manager/environment` loaded by systemd |
| container image replacement upgrades | versioned native build, backup, atomic symlink switch, official migration on backend start, health check, and rollback guidance |

## Repository layout

```text
.github/workflows/syntax.yml
    Bash, ShellCheck, JSON, systemd, branding, source-pin, and secret validation.

assets/README.md
    Immutable branding-source documentation.

ct/nginx-proxy-manager.sh
    Proxmox-host launcher and Default Install identity/network prompts.

install/nginx-proxy-manager-install.sh
    Container-side native installation orchestration.

json/nginx-proxy-manager.json
    Project metadata and default resources.

lib/versions.sh
    Canonical version, commit, and source-blob pins.

scripts/build-openresty-native.sh
    Native reproduction of the official OpenResty build.

scripts/install-release.sh
    Exact source checkout, marker verification, frontend/backend build, and
    immutable release creation.

scripts/npm-prepare.sh
    Translated Docker-entrypoint preparation for paths, ownership, resolvers,
    and IPv6 Nginx directives.

scripts/npm-healthcheck.sh
    Native service, port, Nginx configuration, UI, manifest, and no-Docker checks.

scripts/npm-backup.sh
scripts/npm-restore.sh
scripts/npm-update.sh
    Protected lifecycle helpers.

systemd/*.service
    Explicit backend and OpenResty service units.

docs/PROXMOX-BRANDING.md
docs/RUNTIME-TEST-PLAN.md
docs/PROJECT-HANDOFF.md
    Branding, test, and engineering handoff documentation.
```

## Host-side launcher

`ct/nginx-proxy-manager.sh` runs on the Proxmox host.

It performs these operations:

1. downloads `misc/build.func` at the pinned generic-builder commit;
2. checks that the builder contains exactly one expected moving helper-base
   marker and rewrites that marker to the same pinned commit before sourcing;
3. sets Debian 13, unprivileged LXC, 2 CPU, 4096 MB RAM, and 16 GB disk defaults;
4. leaves ARM64 disabled pending native validation;
5. runs the generic storage and Default/Advanced selection flow;
6. adds Default Install prompts for container ID, hostname, bridge, DHCP/static
   IPv4, static gateway, and optional VLAN;
7. validates IDs cluster-wide, hostnames, bridges, CIDR addresses, gateway
   subnet membership, and VLAN values;
8. preserves user tags, removes `community-script`, and adds project tags;
9. intercepts only the generic builder's calculated installer request and
   substitutes this repository's installer at the selected project ref;
10. creates the container;
11. runs the normal completion hook;
12. replaces the final visible Proxmox description with project-specific
    attribution and links.

The launcher does not configure network identity from inside the container.

### Generic-builder fragility

The installer interception depends on `build.func` continuing to fetch:

```text
https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/${var_install}.sh
```

with `curl`. CI checks project markers, but every maintenance cycle must inspect
the newly selected builder commit. If the download method, URL, variable, or
execution order changes, the launcher must fail visibly rather than silently
fall back to an unrelated installer.

## Container installation flow

The container installer:

1. validates Debian 13 and AMD64;
2. installs explicit build and runtime dependencies;
3. creates the `npm` system account;
4. installs Node.js 22 from the NodeSource signed APT repository;
5. installs exact Yarn Classic `1.22.22`;
6. creates `/opt/certbot` and installs Certbot `5.6.0` and the official pinned
   cryptography-related versions used by the base image;
7. downloads project-owned service tooling from the same development ref;
8. validates the project manifest's expected NPM and base-image commits;
9. builds the pinned OpenResty environment;
10. fetches the exact official NPM commit;
11. verifies `.version` plus selected Git blob IDs for the Dockerfile, package
    manifests, lockfile, and Nginx configuration;
12. builds the frontend and production backend;
13. creates `/opt/nginx-proxy-manager/releases/2.15.1`;
14. installs official Nginx, logrotate, Let's Encrypt, and static default-host
    templates from the pinned source;
15. creates active `/opt/nginx-proxy-manager/current` and `/app` symlinks;
16. writes root-only configuration and installation manifests;
17. enables and starts the backend, waits for port 3000, starts OpenResty, and
    runs the native health check.

The application backend itself calls the official Knex migration path before it
listens on port 3000. This is retained unchanged.

## OpenResty build

The official base image compiles OpenResty rather than using Debian's standard
Nginx package. Substituting `apt install nginx` would lose important behavior.

The native builder reproduces the official configuration, including:

- compatibility and thread support;
- HTTP addition, auth request, DAV, FLV, gunzip, gzip static, MP4, random index,
  real IP, secure link, slice, SSL, stub status, sub, HTTP/2, and HTTP/3 modules;
- mail and mail SSL;
- stream, stream real IP, stream SSL, and stream SSL preread;
- dynamic GeoIP2 module;
- Lua 5.1-compatible LuaRocks modules used by the official base.

The GeoIP2 module is changed from upstream's moving clone to an exact commit.
LuaRocks modules are also given exact versions, closing another moving
build-time dependency in the official image recipe.

## Services

### `nginx-proxy-manager-backend.service`

- user/group: `npm:npm`;
- working directory: active application release;
- command: Node with the official uncaught-exception behavior and 250 MB old
  space limit;
- reads the protected environment through systemd;
- runs the preparation helper as a privileged pre-start command;
- uses a private writable `/tmp` and a systemd-managed shared `/run/nginx`
  runtime directory so reboot-cleared paths exist before sandboxing is applied;
- writes only to declared application, certificate, Nginx include, runtime,
  cache, log, and Certbot paths;
- restarts on failure.

The backend initializes the database, runs official migrations, creates JWT keys
when absent, installs required Certbot DNS plugins, schedules certificate and IP
range work, and listens on port 3000.

### `nginx-proxy-manager-nginx.service`

- user/group: `npm:npm`;
- requires the backend service;
- validates Nginx configuration before start;
- has only `CAP_NET_BIND_SERVICE` for ports 80, 81, and 443;
- uses a private writable `/tmp` and the shared systemd-managed `/run/nginx`
  runtime directory;
- uses the official `daemon off` configuration;
- restarts on failure;
- writes only to declared data, configuration, certificate, runtime, cache, and
  log paths.

## Database architecture

The selected NPM release supports:

- SQLite through `better-sqlite3`;
- MySQL/MariaDB through `mysql2`;
- PostgreSQL through `pg`.

The initial adaptation supports local SQLite only. The upstream code defaults to
`/data/database.sqlite` when no external database environment is present. This
path avoids a separate database service and keeps the first validation scope
small without inventing an unsupported database mode.

External MySQL/MariaDB and PostgreSQL remain future optional work. They must not
be advertised until credentials, TLS options, migrations, backup, restore, and
failure handling are tested.

## First administrator

The selected release no longer requires historical default credentials. When no
active user exists and `INITIAL_ADMIN_EMAIL` and `INITIAL_ADMIN_PASSWORD` are
not set, the frontend presents the official setup wizard. The adaptation leaves
both variables unset and never prints an administrator password.

## Files, ownership, and persistence

### Immutable or rebuildable

- `/opt/nginx-proxy-manager/releases/<version>` — root-owned release;
- `/usr/sbin/nginx`, `/etc/nginx/openresty-version`, Lua modules — pinned build;
- `/opt/certbot` — pinned environment plus runtime-installed DNS plugins;
- `/usr/local/lib/npm-lxc` — root-owned adaptation tooling.

### Mutable application state

- `/data/database.sqlite` — SQLite database;
- `/data/keys.json` — generated JWT key pair;
- `/data/nginx` — generated host, stream, temporary, default, and custom Nginx configuration;
- `/data/custom_ssl` — imported custom certificate material;
- `/data/access` — access-list generated files;
- `/data/logs` — application and proxy logs;
- `/etc/letsencrypt` — certificates, account state, renewal configuration, and DNS credentials.

### Secrets

- `/etc/nginx-proxy-manager/environment` — mode `0600`, root-owned;
- `/etc/nginx-proxy-manager/installation.json` — mode `0600`;
- `/etc/letsencrypt/credentials` — generated by upstream with mode `0600`;
- backup archives and checksums — mode `0600`.

No generated database, key, certificate, password, token, or environment file is
committed.

## Proxmox ownership boundaries

Proxmox remains responsible for:

- container ID and hostname;
- bridge, DHCP/static address, gateway, VLAN, IPv6, DNS, MTU, and MAC address;
- `/etc/hosts` and `/etc/resolv.conf`;
- storage and root filesystem;
- container features and privilege model;
- firewall policy.

The application installer reads `/etc/resolv.conf` only to render an Nginx
resolver include. It does not overwrite Proxmox-managed files. UFW is not
installed.

## Backup and restore

`npm-lxc-backup`:

- creates an SQLite online backup with the SQLite CLI;
- captures `/data` except rebuildable temporary data and normal logs;
- captures `/etc/letsencrypt`;
- captures adaptation configuration and Nginx system templates;
- records active release and hostname metadata;
- creates a root-only gzip archive and SHA-256 sidecar.

The archive contains secrets and must be handled accordingly.

`npm-lxc-restore --archive ...`:

1. verifies the sidecar checksum when present;
2. validates archive structure;
3. creates a safety backup of the current instance;
4. stops both services;
5. restores application data, certificates, and protected configuration;
6. re-applies paths and ownership;
7. starts the backend, waits for port 3000, starts OpenResty, and runs health checks.

The restore path is untested and must be exercised in a disposable container.

## Native update workflow

Updates are explicit. The helper accepts only a root-owned, non-writable reviewed
version manifest. It does not query or install `latest`.

The workflow is:

1. read current release and commit;
2. read selected release and exact commit;
3. reject an unchanged selection;
4. reject a changed official base-image commit because that requires a full
   OpenResty adaptation review;
5. request explicit confirmation;
6. create a protected backup;
7. fetch and verify the exact selected source;
8. build a new versioned release while the old release remains active;
9. stop services;
10. atomically replace the active symlink;
11. update build metadata;
12. start the backend so official migrations run;
13. start OpenResty and run health checks;
14. on failure, return the application symlink to the old release and print the
    exact backup restore command;
15. on success, retain the backup and install the selected manifest.

Database migrations may not be backward compatible. A failed update therefore
requires restoring the pre-update backup before restarting the old application.
A Proxmox snapshot remains mandatory during initial update testing.

## Automated validation

The workflow validates:

- Bash syntax and ShellCheck;
- JSON syntax and required metadata;
- expected launcher and installer paths;
- project tags and description hooks;
- systemd unit syntax and hardening markers;
- pinned upstream release, commits, and selected Git blob IDs;
- existence of Docker-derived entrypoints, manifests, migrations, and templates;
- official base-image Dockerfiles and build scripts;
- OpenResty feature flags;
- absence of mutable NPM application branch URLs in production scripts;
- absence of nested-runtime installation or launch commands;
- remote branding PNG signatures;
- obvious private-key and GitHub token patterns;
- absence of accidental placeholder files.

CI validates source conversion assumptions but does not compile the complete
OpenResty and application stack. The real Debian 13 LXC build remains the
runtime gate.

Local pre-publication validation on 2026-08-06 completed successfully for Bash
syntax, JSON parsing, repository invariants, workflow YAML parsing, whitespace
and conflict-marker scanning, and `systemd-analyze verify`. ShellCheck, remote
branding downloads, pinned upstream checkout verification, and the complete
native source build still require GitHub Actions or a networked Debian 13 test
container and are not recorded as passed.

## Current test matrix

All runtime entries are `NOT RUN`. See `docs/RUNTIME-TEST-PLAN.md` for the full
matrix. In particular, these high-value gates remain open:

- container creation on Proxmox VE 9;
- Debian 13.6 template selection;
- frontend, backend native module, and OpenResty build completion;
- service startup and restart behavior;
- first-run setup wizard;
- real HTTP/HTTPS/WebSocket proxy host;
- certificate issuance and renewal;
- persistence after full container reboot;
- backup and disposable restore;
- update and rollback;
- browser validation of branding;
- ARM64.

No feature may be changed to `PASS` without observed evidence.

## Known risks and fragile assumptions

1. **Generic builder interception.** A future `build.func` may change its
   installer retrieval mechanism. Re-pin only after inspecting it.
2. **OpenResty source build.** OpenResty's own `make` process assembles bundled
   source components. The exact OpenResty Git commit is pinned, but its build
   must be observed in the Debian test environment.
3. **LuaRocks transitive dependencies.** Direct rocks are pinned, but their
   rockspecs can resolve transitive packages. The installed rock manifest must
   be captured after the first successful build and considered for tighter
   locking.
4. **NodeSource package repository.** Node major is fixed and APT signatures are
   verified, but exact Debian package versions are not yet frozen. Record the
   first tested package version and assess pinning.
5. **Certbot DNS plugin installation.** Upstream installs required plugins at
   runtime. The `/opt/certbot` ownership permits this, but each provider path is
   untested.
6. **Non-root OpenResty.** Binding is granted through
   `CAP_NET_BIND_SERVICE`. HTTP/3, reloads initiated by the backend, certificate
   reads, and all generated configuration permissions require real testing.
7. **Systemd hardening.** `ProtectSystem=strict` includes explicit writable
   paths. Any unrecorded upstream write outside those paths will fail visibly
   and must be investigated rather than broadening permissions blindly.
8. **SQLite concurrency and recovery.** The official default is retained, but
   backup, power-loss recovery, and update migration behavior need tests.
9. **Remote artwork.** CI checks PNG content, but Proxmox browser rendering can
   differ and is not yet validated.

## Debugging runbook

### Installation failure

Inspect the host creation log and the container journal. In developer mode,
keep the failed container for diagnosis when possible.

Inside the container:

```bash
cat /etc/nginx-proxy-manager/installation.json
node --version
yarn --version
certbot --version
nginx -V
readlink -f /opt/nginx-proxy-manager/current
```

### Backend failure

```bash
systemctl status nginx-proxy-manager-backend.service
journalctl -u nginx-proxy-manager-backend.service -b --no-pager
sudo -u npm test -w /data
sudo -u npm test -w /etc/letsencrypt
sqlite3 /data/database.sqlite 'PRAGMA integrity_check;'
```

### OpenResty failure

```bash
nginx -t
systemctl status nginx-proxy-manager-nginx.service
journalctl -u nginx-proxy-manager-nginx.service -b --no-pager
ss -ltnup | grep -E ':(80|81|443|3000)\b'
ls -la /run/nginx /data/nginx /etc/nginx/conf.d/include
```

### Certificate failure

```bash
certbot --version
/opt/certbot/bin/pip list
find /etc/letsencrypt -maxdepth 3 -ls
journalctl -u nginx-proxy-manager-backend.service --since -30min
```

### Complete health snapshot

```bash
npm-lxc-healthcheck
systemctl --failed
journalctl -u nginx-proxy-manager-backend.service -u nginx-proxy-manager-nginx.service -b --no-pager
```

## Upstream maintenance procedure

For each new official NPM release:

1. inspect official release notes, release tag, and commit;
2. verify whether the official `docker-nginx-full` base changed;
3. inspect Dockerfiles, s6 scripts, package manifests, lockfiles, migrations,
   Nginx templates, environment handling, volumes, ports, and setup behavior;
4. update exact pins and Git blob markers;
5. compare every Docker component against the mapping table;
6. add deterministic assertions for new or changed source markers;
7. build in a disposable Debian 13 LXC;
8. take a Proxmox snapshot;
9. exercise update from the prior tested release;
10. verify database, proxy hosts, certificates, access lists, WebSockets,
    backup, restore, reboot, and rollback;
11. record failures and fixes;
12. update this handoff and the runtime matrix;
13. keep the pull request in draft until the maintainer confirms the required
    real-world tests.

## Release checklist

- [ ] Development branch exists in the target repository.
- [ ] Draft pull request is open and remains draft.
- [ ] Repository checks pass.
- [ ] Upstream pins and source markers are reviewed.
- [ ] Proxmox VE 9 unprivileged Debian 13 installation passes.
- [ ] Default and Advanced Install paths pass.
- [ ] Proxmox networking and tags match selected values.
- [ ] Browser branding passes.
- [ ] No nested container runtime is present.
- [ ] Full container reboot passes.
- [ ] First-run setup and real proxy host pass.
- [ ] Certificate flow passes.
- [ ] Backup and restore pass.
- [ ] Update and rollback pass from a snapshot.
- [ ] Documentation reflects actual evidence.
- [ ] Maintainer approves changing the pull request from draft.

## Commit and pull-request history

No remote commit or pull request is recorded in this initial local engineering
draft. Add verified commit IDs and the draft PR URL after the target repository
has been created and the branch has been published. Never record a GitHub
operation as successful without checking it through GitHub.

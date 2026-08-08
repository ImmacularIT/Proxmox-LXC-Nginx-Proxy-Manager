# Project technical handoff

This document records the current architecture, implementation boundaries,
maintenance workflow, and runtime evidence for
`ImmacularIT/Proxmox-LXC-Nginx-Proxy-Manager`.

**Status snapshot:** 2026-08-08  
**Project state:** development draft; supported v2.15.1 runtime matrix complete  
**Target platform:** Proxmox VE 9.x, unprivileged Debian 13 AMD64 LXC  
**Pinned upstream release:** `v2.15.1`  
**Pinned upstream commit:** `76f09db610cfcaecf6d608a8947d6f75aa028870`  
**Pinned official base-image source:** `fe5ba055ed29033a619e9103bef5d8218fe1fab0`

Keep the development pull request Draft until final release review is complete
and the maintainer explicitly chooses to promote it.

## Executive summary

The official Nginx Proxy Manager project is distributed as a Docker
application. This repository converts that official implementation into a
native Debian 13 Proxmox LXC installation without Docker, Docker Compose,
Podman, Kubernetes, or another nested container runtime.

The application itself is not reimplemented. Exact upstream commits and
selected Git blobs are verified before build. The native adaptation reproduces
the official frontend, backend, OpenResty, Lua, GeoIP2, Certbot, Nginx template,
and persistent-data behavior using Debian packages, source builds, versioned
release directories, root-only preparation, and hardened systemd services.

The project targets AMD64 only.

## Authoritative upstream pins

Application:

- Nginx Proxy Manager release: `v2.15.1`;
- application commit: `76f09db610cfcaecf6d608a8947d6f75aa028870`.

Official base-image source:

- `NginxProxyManager/docker-nginx-full` commit:
  `fe5ba055ed29033a619e9103bef5d8218fe1fab0`.

Supporting pins:

- OpenResty `1.29.2.5`, commit
  `2ec0f65e434c92e9f78fd5c3af601a6b286c6d2b`;
- GeoIP2 module commit `445df24ef3781e488cee3dfe8a1e111997fc1dfe`;
- LuaRocks `3.13.0`, commit `3421bedc2ce2b64e79530bb97497531b014899a8`;
- Lua `5.1.5`;
- Node.js `22.x`;
- Yarn Classic `1.22.22`;
- Certbot `5.6.0`;
- pyOpenSSL `26.2.0`;
- cryptography `48.0.0`.

The official Certbot-related Docker pins currently contain a Python dependency
combination that is not installable unchanged on Debian 13/Python 3.13. The
native adaptation retains the upstream cryptography pin and uses pyOpenSSL
26.2.0, with `pip check` required to pass.

## Repository layout

```text
.github/workflows/syntax.yml
    Repository validation and upstream-drift checks.

ct/nginx-proxy-manager.sh
    Independent Proxmox-host launcher.

install/nginx-proxy-manager-install.sh
    Container-side native installation orchestration.

json/nginx-proxy-manager.json
    Project metadata and default resources.

lib/versions.sh
    Canonical release, commit, and source-blob pins.

scripts/build-openresty-native.sh
    Native reproduction of the official OpenResty build.

scripts/install-release.sh
    Exact source checkout, immutable verification, frontend/backend build,
    runtime version stamping, and versioned release creation.

scripts/npm-prepare.sh
    Runtime path, ownership, resolver, health-helper link, and compatibility
    setup.

scripts/npm-healthcheck.sh
    Native service, port, Nginx, UI, release, and no-Docker checks.

systemd/*.service
    Hardened backend and OpenResty service units.

docs/PROXMOX-BRANDING.md
docs/RUNTIME-TEST-PLAN.md
docs/PROJECT-HANDOFF.md
    Branding, runtime evidence, and engineering documentation.
```

Backup/restore and adaptation-level update helpers are intentionally not part of
the current release surface.

## Independent Proxmox launcher

`ct/nginx-proxy-manager.sh` runs directly on the Proxmox VE host and is owned by
this project. It does not source or execute an unrelated installer framework.

It requires normal Proxmox host tools including `pct`, `pveam`, `pvesm`,
`pvesh`, `pveversion`, and `whiptail`.

The launcher:

1. validates root execution, Proxmox VE 9.x, and AMD64;
2. presents the project welcome screen;
3. offers Default or Advanced Install;
4. validates a cluster-wide unused container ID;
5. validates the hostname;
6. selects an active LXC root-disk storage;
7. prompts for bridge, DHCP/static IPv4, gateway where required, and optional
   VLAN;
8. allows CPU/RAM/disk overrides only in Advanced mode;
9. shows the complete user-facing configuration for confirmation;
10. resolves Debian template-cache storage automatically after confirmation;
11. reuses or downloads an official Debian 13 AMD64 Proxmox template;
12. creates an unprivileged container with native `pct create`;
13. starts the CT and runs this repository's container installer;
14. runs the native health check;
15. applies project tags and project-specific Proxmox description/branding;
16. reports the administration URL on port 81.

Default resources are 2 CPU cores, 4096 MiB RAM, and a 16 GiB root disk.
Nesting and keyctl are not enabled by the launcher; runtime testing confirmed
that Nginx Proxy Manager does not require them.

Template storage is intentionally not a normal installer question. The launcher
prefers an active `vztmpl` storage already containing a Debian 13 AMD64
template, then conventional `local`, then the first active template-capable
storage. Administrators may override the internal selection with
`NPM_TEMPLATE_STORAGE=<storage>`.

The launcher sends no project installation telemetry or usage data.

## Container installation flow

The container installer:

1. validates Debian 13 and AMD64;
2. installs explicit native build/runtime packages;
3. creates the dedicated `npm` system user/group;
4. installs Node.js 22 and Yarn Classic 1.22.22;
5. builds the pinned Certbot Python environment;
6. installs project-owned native build/preparation/health tooling;
7. builds the pinned official OpenResty environment;
8. fetches and verifies the exact NPM source commit and selected source blobs;
9. compiles frontend locales and the production frontend;
10. installs the production backend and validates `better-sqlite3`;
11. creates `/opt/nginx-proxy-manager/releases/2.15.1`;
12. stamps the verified runtime copy of `package.json` to `2.15.1` only after
    immutable upstream verification, so the API/UI report the real release;
13. installs the official runtime Nginx, logrotate, Let's Encrypt, and static
    templates;
14. creates `/opt/nginx-proxy-manager/current` and `/app` symlinks;
15. writes protected runtime configuration and installation metadata;
16. prepares persistent/runtime paths;
17. starts the backend, waits for port 3000, starts OpenResty, and runs the
    native health check.

The official backend remains responsible for its own database migrations and
application initialization.

## Native OpenResty build

The official base image compiles OpenResty rather than using Debian's stock
Nginx package. The native builder therefore reproduces the pinned official
configuration instead of substituting `apt install nginx`.

Important retained features include HTTP/2 and HTTP/3 modules, stream and SSL
preread, Lua integration, dynamic GeoIP2, mail support, and official proxy/temp
/cache path behavior.

LuaRocks is invoked through its absolute `/usr/local/bin/luarocks` path so
Proxmox execution environments with a reduced `PATH` cannot break the build.

## Runtime identity and systemd hardening

Both long-running services run as `npm:npm`, not root.

### Backend service

`nginx-proxy-manager-backend.service` runs Node from the active versioned
release, uses `Restart=on-failure`, `NoNewPrivileges=true`,
`ProtectSystem=strict`, `PrivateTmp=true`, and related hardening. Its ambient and
bounding capability sets contain only `CAP_NET_BIND_SERVICE`.

The capability is required because upstream NPM itself invokes
`/usr/sbin/nginx -t` and `nginx -s reload` during proxy/certificate workflows.
The official Docker deployment normally performs those operations with much
broader privileges; this adaptation grants only the low-port bind capability.

Because the backend invokes Nginx inside its own `PrivateTmp` namespace, the
service-owned `/var/cache/nginx/tmp` directory is bound to the official
`/tmp/nginx` path. This preserves `PrivateTmp=true` while allowing upstream
Nginx configuration tests to create their expected temp paths.

Upstream's Nginx test uses `-g "error_log off;"`. With this OpenResty prefix,
`off` resolves as a relative filename. `npm-lxc-prepare` therefore creates the
single root-owned compatibility path `/etc/nginx/nginx/off -> /dev/null` rather
than granting the backend write access to `/etc/nginx`.

### OpenResty service

`nginx-proxy-manager-nginx.service` runs OpenResty as `npm:npm`, validates its
configuration before start, has only `CAP_NET_BIND_SERVICE` for ports 80/81/443,
uses `PrivateTmp=true` with the same service-owned `/tmp/nginx` backing path,
uses the shared `/run/nginx` runtime directory, restarts on failure, and retains
strict filesystem/systemd hardening.

Neither service has a write allowance for a project backup directory because
backup/restore tooling is not part of the current supported runtime.

## First administrator and authentication

NPM v2.15.1 presents the official setup wizard when no administrator exists.
The adaptation does not set `INITIAL_ADMIN_EMAIL` or
`INITIAL_ADMIN_PASSWORD`, does not invent credentials, and never prints a
default administrator password.

Real clean-install testing confirmed the first-run wizard, absence of default
credentials, administrator creation/removal, and TOTP two-factor authentication.

## Database and persistent state

SQLite is the default native database path and remains at
`/data/database.sqlite`.

NPM also contains upstream support for MySQL/MariaDB and PostgreSQL, but this
adaptation validates SQLite as the native default. External database modes must
not be advertised as runtime-tested unless separately exercised.

Persistent application paths include:

- `/data` — database, JWT keys, generated Nginx configuration, custom
  certificates, access-list data, logs, and other application state;
- `/etc/letsencrypt` — ACME accounts, certificates, renewal data, and DNS
  credentials.

Protected adaptation paths include:

- `/etc/nginx-proxy-manager/environment`;
- `/etc/nginx-proxy-manager/installation.json`.

Real testing confirmed that application-created proxy hosts and Let's Encrypt
state survive a full CT reboot and service restarts.

## Certificate behavior

The first real Let's Encrypt test exposed three native-systemd compatibility
requirements before Certbot could run: backend low-port capability, the backend
private `/tmp/nginx` mapping, and the read-only-safe `error_log off`
compatibility target described above.

After those fixes, Certbot 5.6.0 reached the production Let's Encrypt ACME API.
An initial registration using the intentionally fake `test@example.com` user
email was correctly rejected by Let's Encrypt because `example.com` is a
forbidden contact domain. Replacing it with a real administrator email allowed
issuance to succeed.

A subsequent fresh install from the development branch, with the fixes already
integrated, successfully issued production Let's Encrypt certificates for three
real subdomains without manual runtime patching.

Certificate import/download, DNS challenge behavior, renewal, and service
persistence are covered by the Application feature matrix and are recorded as
PASSED there.

## Runtime validation status

Real validation was performed on Proxmox VE 9.2.9, kernel 7.0.14-9-pve, with
Debian 13.6 AMD64 unprivileged LXC instances.

The maintainer confirmed the complete supported matrices as PASSED:

- Container creation;
- Build and service;
- Proxmox branding;
- Application feature.

This includes Default and Advanced installer paths, DHCP/static networking,
validation cases, native builds and services, restart/recovery behavior,
first-run authentication, HTTP/HTTPS/WebSocket proxying, access lists, Force
SSL, certificate import, HTTP and DNS certificate workflows, renewal, stream,
HTTP/3, logs, reboot/service persistence, correct v2.15.1 reporting, and the
branding/tag checks.

The authoritative detailed record is `docs/RUNTIME-TEST-PLAN.md`.

## Lifecycle scope

Backup/restore and adaptation-level in-place update/rollback are not upstream
NPM v2.15.1 application features and are not part of this release's supported
surface. The project metadata is therefore `updateable: false`, the installer
does not install lifecycle helper commands, and those functions are not runtime
release gates.

They may be designed later as separate ImmacularIT features. Such future work
must define data ownership, consistent database handling, certificate/secret
handling, failure recovery, migration compatibility, and its own runtime test
plan before being advertised.

## Upstream release maintenance model

A new NPM release is handled as a new native adaptation cycle rather than by an
automatic updater. For each upstream release:

1. create a new development branch for the target NPM version;
2. select the exact NPM tag and commit;
3. inspect Dockerfile, backend/frontend dependency, Nginx, Certbot, migration,
   and runtime changes;
4. review the exact official base-image/OpenResty source revision;
5. refresh version/blob pins only after reviewing diffs;
6. run repository CI;
7. build a fresh unprivileged Debian 13 AMD64 LXC on supported Proxmox VE;
8. repeat the runtime validation required for the changed release;
9. keep the PR Draft and `main` untouched until the required gates pass and the
   maintainer explicitly approves promotion.

A changed official base-image/OpenResty pin always requires a full adaptation
review. Even an application-only update must not bypass exact-pin review and
fresh runtime validation.

## Proxmox ownership boundaries

Proxmox remains responsible for container ID and hostname; bridge, DHCP/static
address, gateway, VLAN, DNS, MTU, and MAC address; `/etc/hosts` and
`/etc/resolv.conf`; storage and root filesystem; container privilege/features;
and firewall/NAT policy.

The native installer reads resolver information only to render the Nginx
resolver include. It does not overwrite Proxmox-owned networking files and does
not install UFW.

## Maintenance rule

Never claim a runtime test passed from repository review or CI alone. Runtime
status must come from real Proxmox evidence recorded in the runtime test plan.

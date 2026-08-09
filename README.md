# Proxmox LXC Nginx Proxy Manager

An independent ImmacularIT project that converts the official, Docker-based
[Nginx Proxy Manager](https://github.com/NginxProxyManager/nginx-proxy-manager)
application into a native Debian 13 Proxmox LXC installation.

<a href="https://www.buymeacoffee.com/eli66" target="_blank"><img src="http://public.jc21.com/github/by-me-a-coffee.png" alt="Buy Me A Coffee" style="height: 51px !important;width: 217px !important;" ></a>

> **Release status:** the supported Nginx Proxy Manager v2.15.1 runtime matrix
> has been exercised successfully on Proxmox VE 9.2.9 with Debian 13.6 AMD64.
> Container creation, native build/services, Proxmox branding, the application
> feature matrix, the final fresh-install health smoke test, and the final
> nesting-enabled start/reboot smoke check all pass. The validated release was
> promoted to `main` on 2026-08-08. Backup/restore and adaptation-level in-place
> update tooling are future ImmacularIT project options and are not part of the
> current supported feature set.

## Direct installation

Run this command as `root` in the Proxmox host shell:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ImmacularIT/Proxmox-LXC-Nginx-Proxy-Manager/main/ct/nginx-proxy-manager.sh)
```

The launcher defaults all project self-fetches to `main`. `NPM_PROJECT_REF` can
still be set explicitly when testing a future development branch.

The host launcher is project-owned and uses Proxmox's own `pct`, `pveam`,
`pvesm`, and `pvesh` commands directly. It does not load an unrelated script
framework and does not send installation telemetry or usage data.

Default Install prompts for container ID, hostname, LXC root-disk storage,
bridge, DHCP or static IPv4, static gateway, and optional VLAN. Debian template
handling is automatic. After the user approves the CT configuration, the
launcher refreshes the official Proxmox appliance catalog and determines the
newest available Debian 13 AMD64 standard template. It reuses that exact cached
template when present. If the newest cached Debian 13 template is older than the
current catalog version, the launcher downloads the newer catalog template and
uses it for the new CT. A cached template newer than the refreshed catalog is
not replaced by an older one. Existing older template files are not deleted.

Template-cache storage is also selected automatically: prefer a storage already
holding the exact newest template, then an existing Debian 13 template cache,
then Proxmox's conventional `local` storage, then the first active
`vztmpl`-capable storage. Administrators can override this internal choice with
`NPM_TEMPLATE_STORAGE=<storage>` when launching the script; it is not exposed as
a normal installer dialog.

Advanced Install additionally allows CPU, RAM, and disk customization. The
launcher always creates an **unprivileged** LXC and enables the Proxmox
`nesting=1` feature by default. This is a host/container compatibility choice to
avoid the recurring Proxmox warning for Systemd 257 guests; Nginx Proxy Manager
does not require a nested container runtime. keyctl remains disabled and is
not enabled by the launcher.

Enabling the Proxmox nesting feature broadens the guest's visibility of some
host kernel filesystems compared with a non-nesting LXC. The container remains
unprivileged and the application still runs without Docker, Podman, Kubernetes,
or another nested runtime.

Current default resources are deliberately sized for the source build:

- 2 CPU cores;
- 4096 MB RAM;
- 16 GB disk;
- unprivileged Debian 13 AMD64 LXC with `nesting=1`.

This project targets AMD64 only. ARM64 support is not part of the project scope
or runtime test plan.

## Pinned upstream

| Component | Version or revision |
|---|---|
| Nginx Proxy Manager | `v2.15.1` |
| Nginx Proxy Manager commit | `76f09db610cfcaecf6d608a8947d6f75aa028870` |
| Official `docker-nginx-full` source | `fe5ba055ed29033a619e9103bef5d8218fe1fab0` |
| OpenResty | `1.29.2.5`, commit `2ec0f65e434c92e9f78fd5c3af601a6b286c6d2b` |
| Node.js | `22.x` |
| Yarn | `1.22.22` |
| Certbot | `5.6.0` |
| Lua / LuaRocks | `5.1.5` / `3.13.0` |
| Base operating system | Debian 13 |
| Target architecture | AMD64 |

The installer fetches exact Git commits and validates release markers and
selected Git blob IDs before building. It does not install from `develop`,
`main`, `master`, or another moving application branch.

## Native architecture

The final container does not require Docker, Docker Compose, Podman,
Kubernetes, or another nested container runtime. The Proxmox `nesting=1`
container feature described below is an LXC compatibility setting; it does not
mean a nested Docker/Podman/Kubernetes runtime is installed or used.

- The official frontend is built with the pinned Yarn lockfile and served as
  static files by OpenResty.
- The official backend and Node dependencies are built into a versioned release
  under `/opt/nginx-proxy-manager/releases/`.
- The official OpenResty build flags, Lua integration, HTTP/3, stream support,
  and GeoIP2 module are reproduced from the pinned `docker-nginx-full` source.
- The backend runs as `nginx-proxy-manager-backend.service` on local port 3000.
- OpenResty runs as `nginx-proxy-manager-nginx.service` on ports 80, 81, and 443.
- SQLite is the initial supported database path and remains at
  `/data/database.sqlite`.
- `/data` and `/etc/letsencrypt` retain the official persistent-volume layout.
- Both long-running services use the dedicated `npm` system account.

See [docs/PROJECT-HANDOFF.md](docs/PROJECT-HANDOFF.md) for the complete Docker-to-LXC mapping.

## Ports

| Port | Purpose | Exposure |
|---|---|---|
| 80/TCP | HTTP proxy traffic and ACME HTTP challenge | Expose as required |
| 81/TCP | Administration interface | Restrict to trusted management networks |
| 443/TCP and UDP | HTTPS and HTTP/3 proxy traffic | Expose as required |
| 3000/TCP | Internal backend API | Local to the container |
| Database | SQLite file, no network port | Not externally exposed |

Proxmox and the surrounding network remain responsible for firewall policy.
The installer does not install UFW and does not rewrite hostname, resolver,
`/etc/hosts`, IP addressing, gateway, bridge, VLAN, or Proxmox interface data.

## First run

Nginx Proxy Manager `v2.15.1` presents a setup wizard when the database contains
no active user. This adaptation does not create default administrator
credentials and does not set `INITIAL_ADMIN_EMAIL` or
`INITIAL_ADMIN_PASSWORD`.

Open `http://CONTAINER-IP:81` and complete the official wizard.

## Persistent and protected paths

| Path | Purpose |
|---|---|
| `/opt/nginx-proxy-manager/releases/<version>` | Immutable application release |
| `/opt/nginx-proxy-manager/current` | Active release symlink |
| `/app` | Compatibility symlink used by official Nginx templates |
| `/data` | Database, generated Nginx configuration, keys, logs, and application data |
| `/etc/letsencrypt` | Certificates, ACME accounts, and DNS credentials |
| `/etc/nginx-proxy-manager/environment` | Root-only runtime environment |
| `/etc/nginx-proxy-manager/installation.json` | Installed-version manifest |
| `/etc/nginx` | Official Nginx/OpenResty templates and generated includes |
| `/opt/certbot` | Pinned Certbot virtual environment and DNS plugins |

## Service and maintenance commands

```bash
systemctl status nginx-proxy-manager-backend.service
systemctl status nginx-proxy-manager-nginx.service
journalctl -u nginx-proxy-manager-backend.service
journalctl -u nginx-proxy-manager-nginx.service
npm-lxc-healthcheck
```

## Lifecycle scope and upstream updates

Nginx Proxy Manager v2.15.1 does not provide an application-level backup/restore
workflow for this adaptation. The project therefore does not ship
`npm-lxc-backup`, `npm-lxc-restore`, or `npm-lxc-update`, and project metadata is
set to `updateable: false`.

NPM's own certificate-management features remain available, including importing
a custom certificate and downloading an existing certificate through the
application where supported.

When the original NPM project publishes a new release, treat it as a new native
adaptation cycle rather than an automatic in-place upgrade. Create a new
development branch, pin and review the new exact upstream revisions, inspect
Docker/build/runtime/migration changes, run CI, build a fresh Proxmox LXC, and
repeat the runtime validation appropriate to that release before promotion.
Backup/restore or migration tooling across native adaptation releases may be
added later as separately designed and validated ImmacularIT features.

## Validation status

Repository checks cover Bash and JSON syntax, systemd units, required metadata,
version pins, Docker-derived source markers, branding PNG signatures, forbidden
nested-runtime installation commands, moving upstream branch URLs, explicit
no-telemetry launcher/installer invariants, latest Debian-template catalog
selection and download invariants, the fixed unprivileged `nesting=1` default
with `keyctl` disabled, AMD64-only target enforcement, certificate-workflow
compatibility, lifecycle-scope invariants, and obvious private-key or token
patterns.

Real Proxmox validation on PVE 9.2.9 / Debian 13.6 AMD64 has completed the
supported v2.15.1 application/runtime matrices, the final fresh-install health
smoke test, and the nesting-enabled start/reboot confirmation. The production
CT remained unprivileged with keyctl disabled, the Systemd 257 nesting warning
no longer appeared, and `npm-lxc-healthcheck` passed after reboot. See
[docs/RUNTIME-TEST-PLAN.md](docs/RUNTIME-TEST-PLAN.md) for the recorded evidence.

## Project identity

Nginx Proxy Manager remains an upstream project maintained by its authors and
is officially distributed as a Docker application. This repository is an
unofficial native Proxmox LXC adaptation maintained by
[ImmacularIT](https://github.com/ImmacularIT).

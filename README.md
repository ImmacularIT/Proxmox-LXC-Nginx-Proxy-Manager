# Proxmox Nginx Proxy Manager LXC

An independent ImmacularIT project that converts the official, Docker-based
[Nginx Proxy Manager](https://github.com/NginxProxyManager/nginx-proxy-manager)
application into a native Debian 13 Proxmox LXC installation.

> **Development status:** active runtime validation is in progress on Proxmox
> VE 9.2.9 with Debian 13.6 AMD64. The complete Container creation, Build and
> service, Proxmox branding, and Application feature matrices have now been
> exercised successfully, including fresh installation, static/DHCP networking,
> Advanced Install, service recovery, HTTP/HTTPS/WebSocket and stream proxying,
> HTTP/3, access lists, certificate import, Let's Encrypt HTTP and DNS flows,
> renewal, first-run setup, administrators/TOTP, reboot/service persistence,
> logging, and correct runtime/GUI version reporting. The project remains a
> development draft only while the Backup, restore, and update matrix is
> completed. Use only a disposable test container until the runtime matrix is
> complete.

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
Kubernetes, or a nested container runtime.

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

## Development installation

Run this only on a disposable Proxmox VE 9.x test host:

```bash
bash <(curl -fsSL \
  https://raw.githubusercontent.com/ImmacularIT/Proxmox-LXC-Nginx-Proxy-Manager/develop/native-lxc-v2.15.1/ct/nginx-proxy-manager.sh)
```

The host launcher is project-owned and uses Proxmox's own `pct`, `pveam`,
`pvesm`, and `pvesh` commands directly. It does not load an unrelated script
framework and does not send installation telemetry or usage data.

Default Install prompts for container ID, hostname, LXC root-disk storage,
bridge, DHCP or static IPv4, static gateway, and optional VLAN. Debian template
cache placement is handled automatically: the launcher first reuses an active
`vztmpl` storage that already contains a Debian 13 AMD64 template, otherwise it
prefers Proxmox's conventional `local` storage, then the first active
`vztmpl`-capable storage. Administrators can override this internal choice with
`NPM_TEMPLATE_STORAGE=<storage>` when launching the script; it is not exposed as
a normal installer dialog.

Advanced Install additionally allows CPU, RAM, and disk customization. The
launcher always creates an unprivileged LXC without enabling nesting or keyctl;
runtime validation has shown that Nginx Proxy Manager does not require either
feature.

Current default resources are deliberately sized for the source build:

- 2 CPU cores;
- 4096 MB RAM;
- 16 GB disk;
- unprivileged Debian 13 AMD64 LXC.

This project targets AMD64 only. ARM64 support is not part of the project scope
or runtime test plan.

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
| `/var/backups/nginx-proxy-manager` | Protected backup archives |

## Service and maintenance commands

```bash
systemctl status nginx-proxy-manager-backend.service
systemctl status nginx-proxy-manager-nginx.service
journalctl -u nginx-proxy-manager-backend.service
journalctl -u nginx-proxy-manager-nginx.service
npm-lxc-healthcheck
npm-lxc-backup
npm-lxc-restore --archive /var/backups/nginx-proxy-manager/<archive>.tar.gz
```

Updates are never automatic. A reviewed adaptation version manifest must be
provided explicitly:

```bash
npm-lxc-update --version-file /root/validated-versions.sh
```

The update helper builds a new versioned release, creates a backup, switches the
active symlink, lets the official backend run its migrations, checks health,
and retains rollback guidance and the backup path.

## Validation status

Repository checks cover Bash and JSON syntax, systemd units, required metadata,
version pins, Docker-derived source markers, branding PNG signatures, forbidden
nested-runtime installation commands, moving upstream branch URLs, explicit
no-telemetry launcher/installer invariants, automatic template-storage handling,
no unnecessary LXC nesting/keyctl features, AMD64-only target enforcement, and
obvious private-key or token patterns.

Real Proxmox validation has now passed the complete Container creation, Build and
service, Proxmox branding, and Application feature matrices on Debian 13.6 AMD64.
Only the Backup, restore, and update matrix remains open before the runtime plan
is complete. See [docs/RUNTIME-TEST-PLAN.md](docs/RUNTIME-TEST-PLAN.md).

## Project identity

Nginx Proxy Manager remains an upstream project maintained by its authors and
is officially distributed as a Docker application. This repository is an
unofficial native Proxmox LXC adaptation maintained by
[ImmacularIT](https://github.com/ImmacularIT).

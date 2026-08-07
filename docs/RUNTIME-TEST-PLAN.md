# Runtime test plan

No item in this document is passed by repository review alone. Record the
Proxmox version, Debian template version, container ID, date, tester, observed
result, logs or screenshots where useful, and the fixing commit for every
failure.

## Test environment

Target environment:

- Proxmox VE 9.x;
- unprivileged Debian 13 LXC;
- Debian 13.6 template where available;
- disposable storage and a pre-install snapshot;
- test DNS names routed to the container;
- inbound TCP 80 and TCP/UDP 443 where certificate and HTTP/3 testing requires it;
- disposable HTTP, HTTPS, and WebSocket backends.

Current runtime-validation instance:

- date: 2026-08-07;
- Proxmox VE: 9.2.9, kernel 7.0.14-9-pve;
- template: Debian 13.6 AMD64;
- privilege model: unprivileged LXC;
- container ID: 901;
- network observed during install: DHCP IPv4, 192.168.1.110.

## Container creation matrix

| Test | Status | Evidence / notes |
|---|---|---|
| Default container ID accepted | NOT RUN | |
| Custom unused container ID | NOT RUN | |
| Cluster-wide used ID rejected | NOT RUN | |
| Default hostname | NOT RUN | |
| Custom valid hostname | NOT RUN | |
| Invalid hostname rejected | NOT RUN | |
| Storage selection | NOT RUN | |
| Bridge selection | NOT RUN | |
| DHCP | NOT RUN | |
| Static IPv4 CIDR | NOT RUN | |
| Gateway in selected subnet | NOT RUN | |
| Invalid gateway rejected | NOT RUN | |
| Optional VLAN blank | NOT RUN | |
| VLAN 1-4094 | NOT RUN | |
| Invalid VLAN rejected | NOT RUN | |
| Final Proxmox `net0` values | NOT RUN | |
| Advanced Install remains functional | NOT RUN | |
| Proxmox owns hostname and resolver files | NOT RUN | |
| Unprivileged container confirmed | PASSED | 2026-08-07, PVE 9.2.9 / Debian 13.6 / CT 901 created and exercised as an unprivileged LXC. |
| No Docker or Podman binary installed | PASSED | 2026-08-07, CT 901: `npm-lxc-healthcheck` reported `PASS  no Docker runtime installed`. |

## Build and service matrix

| Test | Status | Evidence / notes |
|---|---|---|
| Exact NPM commit fetched | PASSED | 2026-08-07, CT 901 reached a completed immutable `2.15.1` release after the installer verified the pinned NPM commit. |
| Exact source blob checks pass | PASSED | 2026-08-07, CT 901 completed the source-verification/build path using the pinned blob checks. |
| Node.js 22 and Yarn 1 validation | PASSED | 2026-08-07, CT 901 installed and validated Node.js 22.23.2 and Yarn 1.22.22. |
| Frontend build completes | PASSED | 2026-08-07, CT 901 completed locale compilation and the Vite production frontend build. |
| Backend native dependencies compile | PASSED | 2026-08-07, CT 901 completed the production backend dependency installation and immutable release creation. |
| OpenResty 1.29.2.5 build completes | PASSED | 2026-08-07, CT 901 completed the native OpenResty 1.29.2.5 source build. |
| HTTP/3, stream, Lua and GeoIP2 flags present | NOT RUN | |
| Certbot 5.6.0 works | PASSED | 2026-08-07, CT 901 installed Certbot 5.6.0 with pyOpenSSL 26.2.0 and cryptography 48.0.0; dependency check passed. |
| SQLite database initializes | PASSED | 2026-08-07, CT 901: backend selected `/data/database.sqlite`, created the database and JWT keys successfully. |
| Official migrations complete | PASSED | 2026-08-07, CT 901: official migration chain ran from database version `none` through the current schema before the backend began listening. |
| Backend systemd startup | PASSED | Initial `ExecStartPre` failure rejected an intentionally empty custom Nginx include; fix `3d782a82f011f62e707666d7f81d4b1cabd4e17a` was installed from CI-validated code commit `1041ed5076d8584a62a3afd626ec1a0cd5245764`. Retest: prepare exited 0, service active/running, backend PID listening on port 3000. |
| OpenResty systemd startup | PASSED | Initial systemd `nginx -t` failed because `PrivateTmp=true` isolated `/tmp/nginx/body` between service commands. Retest with commit `4ff425adff791cb7248c52abac0e15217b3fcc7c`: `PrivateTmp=true` retained, `/var/cache/nginx/tmp` bound to `/tmp/nginx`, pre-start checks exited 0, OpenResty active/running. |
| Restart policies recover processes | NOT RUN | Explicit start-limit safeguards are installed; process-recovery behavior still requires a deliberate failure/restart test. |
| Health helper passes | PASSED | 2026-08-07, CT 901: all native LXC health checks passed with backend and Nginx active, configuration valid, ports 3000/80/81/443 listening, UI responsive, release marker valid, and no Docker runtime installed. |
| Full container reboot survives | NOT RUN | |
| Persistent data survives reboot | NOT RUN | |

## Proxmox branding matrix

| Test | Status | Evidence / notes |
|---|---|---|
| Project tags present | NOT RUN | |
| User tags preserved | NOT RUN | |
| `community-script` tag absent | NOT RUN | |
| NPM logo renders | NOT RUN | |
| ImmacularIT logo renders | NOT RUN | |
| Official/adaptation distinction is clear | NOT RUN | |
| All panel links work | NOT RUN | |
| No Community promotional links | NOT RUN | |
| Fallback text remains readable with images blocked | NOT RUN | |

## Application feature matrix

| Test | Status | Evidence / notes |
|---|---|---|
| Administration interface on port 81 | PASSED | 2026-08-07, CT 901: OpenResty listened on IPv4/IPv6 port 81 and local HTTP request returned status 200. Browser rendering remains a separate test. |
| First-run setup wizard | NOT RUN | |
| No invented/default credentials | NOT RUN | |
| Create administrator | NOT RUN | |
| Create HTTP proxy host | NOT RUN | |
| Proxy to HTTPS backend | NOT RUN | |
| WebSocket proxying | NOT RUN | |
| Access list behavior | NOT RUN | |
| HTTP-to-HTTPS redirect | NOT RUN | |
| Certificate import | NOT RUN | |
| Let's Encrypt HTTP challenge | NOT RUN | |
| DNS challenge plugin installation | NOT RUN | |
| Certificate renewal | NOT RUN | |
| Stream proxy | NOT RUN | |
| HTTP/3 where network permits | NOT RUN | |
| Application logs | NOT RUN | |
| OpenResty logs | NOT RUN | |
| Proxy hosts survive service restart | NOT RUN | |
| Certificates survive service restart | NOT RUN | |

## Backup, restore, and update matrix

| Test | Status | Evidence / notes |
|---|---|---|
| Backup archive and checksum created | NOT RUN | |
| SQLite online backup is consistent | NOT RUN | |
| Secrets have restrictive permissions | NOT RUN | |
| Restore into disposable instance | NOT RUN | |
| Restored proxy hosts work | NOT RUN | |
| Restored certificates work | NOT RUN | |
| Update builds new release directory | NOT RUN | |
| Pre-update snapshot and backup | NOT RUN | |
| Official migration during update | NOT RUN | |
| Atomic active-release switch | NOT RUN | |
| Post-update health checks | NOT RUN | |
| Failed-update rollback procedure | NOT RUN | |

## ARM64 gate

ARM64 remains disabled in launcher metadata. Enable it only after repeating the
complete build, startup, proxy, certificate, reboot, backup, restore, and update
matrix on an ARM64 Proxmox host or equivalent validated environment.

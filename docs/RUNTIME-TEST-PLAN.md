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
- AMD64 architecture;
- disposable storage and a pre-install snapshot;
- test DNS names routed to the container;
- inbound TCP 80 and TCP/UDP 443 where certificate and HTTP/3 testing requires it;
- disposable HTTP, HTTPS, and WebSocket backends.

Runtime-validation instances:

- 2026-08-07: Proxmox VE 9.2.9, kernel 7.0.14-9-pve; Debian 13.6 AMD64; unprivileged CT 901. Initial native runtime validation exposed and corrected installation/service compatibility defects.
- 2026-08-08: repeated fresh Default Install runs on the same PVE/template/privilege model validated the LuaRocks/OpenResty path fixes, startup readiness, independent launcher completion, installer UX, template-storage behavior, no nesting/keyctl requirement, runtime version metadata, and helper-command behavior.
- 2026-08-08: real certificate tracing exposed three native-systemd compatibility requirements before Certbot could complete: backend `CAP_NET_BIND_SERVICE` for upstream child `nginx -t`, a backend `PrivateTmp` mapping for the official `/tmp/nginx` path, and a read-only-safe `/etc/nginx/nginx/off -> /dev/null` compatibility target for upstream's `error_log off` test. These were fixed and regression-guarded.
- 2026-08-08: a subsequent fresh clean installation with those fixes integrated successfully issued production Let's Encrypt certificates for three real subdomains. HTTP proxying, Force SSL, WebSockets, first-run setup, administrator management, TOTP, correct `v2.15.1` GUI/version reporting, reboot persistence, and Proxmox branding were also confirmed.
- 2026-08-08: the maintainer confirmed the complete Container creation, Build and service, and Application feature matrices below all pass on the tested Proxmox VE 9.2.9 / Debian 13.6 AMD64 environment.

## Container creation matrix

The maintainer confirmed the complete matrix below as passing on 2026-08-08.

| Test | Status | Evidence / notes |
|---|---|---|
| Default container ID accepted | PASSED | Maintainer-confirmed complete matrix pass. |
| Custom unused container ID | PASSED | Maintainer-confirmed complete matrix pass. |
| Cluster-wide used ID rejected | PASSED | Maintainer-confirmed complete matrix pass. |
| Default hostname | PASSED | Maintainer-confirmed complete matrix pass. |
| Custom valid hostname | PASSED | Maintainer-confirmed complete matrix pass. |
| Invalid hostname rejected | PASSED | Maintainer-confirmed complete matrix pass. |
| Storage selection | PASSED | Maintainer-confirmed complete matrix pass. |
| Bridge selection | PASSED | Maintainer-confirmed complete matrix pass. |
| DHCP | PASSED | Maintainer-confirmed complete matrix pass. |
| Static IPv4 CIDR | PASSED | Maintainer-confirmed complete matrix pass. |
| Gateway in selected subnet | PASSED | Maintainer-confirmed complete matrix pass. |
| Invalid gateway rejected | PASSED | Maintainer-confirmed complete matrix pass. |
| Optional VLAN blank | PASSED | Maintainer-confirmed complete matrix pass. |
| VLAN 1-4094 | PASSED | Maintainer-confirmed complete matrix pass. |
| Invalid VLAN rejected | PASSED | Maintainer-confirmed complete matrix pass. |
| Final Proxmox `net0` values | PASSED | Maintainer-confirmed complete matrix pass. |
| Advanced Install remains functional | PASSED | Maintainer-confirmed complete matrix pass. |
| Proxmox owns hostname and resolver files | PASSED | Maintainer-confirmed complete matrix pass. |
| Unprivileged container confirmed | PASSED | Maintainer-confirmed complete matrix pass; launcher does not enable nesting or keyctl. |
| No Docker or Podman binary installed | PASSED | Maintainer-confirmed complete matrix pass; native health validation also confirmed no Docker runtime. |

## Build and service matrix

The maintainer confirmed the complete matrix below as passing on 2026-08-08.

| Test | Status | Evidence / notes |
|---|---|---|
| Fresh end-to-end installation from current branch | PASSED | Maintainer-confirmed complete matrix pass. |
| Exact NPM commit fetched | PASSED | Maintainer-confirmed complete matrix pass. |
| Exact source blob checks pass | PASSED | Maintainer-confirmed complete matrix pass. |
| Node.js 22 and Yarn 1 validation | PASSED | Maintainer-confirmed complete matrix pass. |
| Frontend build completes | PASSED | Maintainer-confirmed complete matrix pass. |
| Backend native dependencies compile | PASSED | Maintainer-confirmed complete matrix pass. |
| OpenResty 1.29.2.5 build completes | PASSED | Maintainer-confirmed complete matrix pass. |
| HTTP/3, stream, Lua and GeoIP2 flags present | PASSED | Maintainer-confirmed complete matrix pass. |
| Certbot 5.6.0 works | PASSED | Maintainer-confirmed complete matrix pass; production Let's Encrypt issuance also succeeded. |
| SQLite database initializes | PASSED | Maintainer-confirmed complete matrix pass. |
| Official migrations complete | PASSED | Maintainer-confirmed complete matrix pass. |
| Backend systemd startup | PASSED | Maintainer-confirmed complete matrix pass. |
| OpenResty systemd startup | PASSED | Maintainer-confirmed complete matrix pass with hardened native services. |
| Restart policies recover processes | PASSED | Maintainer-confirmed complete matrix pass. |
| Health helper passes | PASSED | Maintainer-confirmed complete matrix pass. |
| Administration helpers reachable by short `pct exec` command | PASSED | Maintainer-confirmed complete matrix pass. |
| Full container reboot survives | PASSED | Maintainer-confirmed complete matrix pass with nesting disabled. |
| Persistent data survives reboot | PASSED | Maintainer-confirmed complete matrix pass with real proxy and certificate data. |

## Proxmox branding matrix

All Proxmox branding checks below were confirmed as passing by the maintainer on 2026-08-08.

| Test | Status | Evidence / notes |
|---|---|---|
| Project tags present | PASSED | Maintainer-confirmed branding matrix pass. |
| User tags preserved | PASSED | Maintainer-confirmed branding matrix pass. |
| `community-script` tag absent | PASSED | Maintainer-confirmed branding matrix pass. |
| NPM logo renders | PASSED | Maintainer-confirmed branding matrix pass. |
| ImmacularIT logo renders | PASSED | Maintainer-confirmed branding matrix pass. |
| Official/adaptation distinction is clear | PASSED | Maintainer-confirmed branding matrix pass. |
| All panel links work | PASSED | Maintainer-confirmed branding matrix pass. |
| No Community promotional links | PASSED | Maintainer-confirmed branding matrix pass. |
| Fallback text remains readable with images blocked | PASSED | Maintainer-confirmed branding matrix pass. |

## Application feature matrix

The maintainer confirmed the complete matrix below as passing on 2026-08-08.

| Test | Status | Evidence / notes |
|---|---|---|
| Administration interface on port 81 | PASSED | Maintainer-confirmed complete matrix pass. |
| First-run setup wizard | PASSED | Official setup wizard appears on first GUI access and completes successfully. |
| No invented/default credentials | PASSED | No administrator credentials are pre-created; the first administrator is created through the setup wizard. |
| Create administrator | PASSED | Administrator creation and removal both work. |
| Two-factor authentication (TOTP) | PASSED | TOTP enrollment and authentication work. |
| Runtime installed version metadata | PASSED | Runtime/API version reports `v2.15.1`. |
| GUI displayed version / false update banner | PASSED | GUI footer displays `v2.15.1` and no false update banner is shown. |
| Create HTTP proxy host | PASSED | Maintainer-confirmed complete matrix pass. |
| Proxy to HTTPS backend | PASSED | Maintainer-confirmed complete matrix pass. |
| WebSocket proxying | PASSED | Maintainer-confirmed complete matrix pass; a real proxied application was exercised with WebSockets Support enabled. |
| Access list behavior | PASSED | Maintainer-confirmed complete matrix pass. |
| HTTP-to-HTTPS redirect | PASSED | Maintainer-confirmed complete matrix pass; Force SSL was also exercised with a real Let's Encrypt certificate. |
| Certificate import | PASSED | Maintainer-confirmed complete matrix pass. |
| Let's Encrypt HTTP challenge | PASSED | Production HTTP/webroot issuance succeeded for three real subdomains on a fresh install. |
| DNS challenge plugin installation | PASSED | Maintainer-confirmed complete matrix pass. |
| Certificate renewal | PASSED | Maintainer-confirmed complete matrix pass. |
| Stream proxy | PASSED | Maintainer-confirmed complete matrix pass. |
| HTTP/3 where network permits | PASSED | Maintainer-confirmed complete matrix pass. |
| Application logs | PASSED | Maintainer-confirmed complete matrix pass. |
| OpenResty logs | PASSED | Maintainer-confirmed complete matrix pass. |
| Proxy hosts survive service restart | PASSED | Maintainer-confirmed complete matrix pass. |
| Certificates survive service restart | PASSED | Maintainer-confirmed complete matrix pass. |

## Backup, restore, and update matrix

This is now the only runtime matrix section that remains open.

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

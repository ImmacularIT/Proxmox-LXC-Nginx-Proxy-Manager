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

Runtime-validation instances:

- 2026-08-07: Proxmox VE 9.2.9, kernel 7.0.14-9-pve; Debian 13.6 AMD64; unprivileged CT 901; DHCP IPv4 192.168.1.110. This instance reached a working backend/OpenResty/UI stack after targeted fixes.
- 2026-08-08: same PVE/template/privilege model; fresh Default Install CT 901; DHCP IPv4 192.168.1.113. This clean run stopped during the OpenResty preparation stage when the LuaRocks executable was installed under `/usr/local/bin` but then looked up through an environment-dependent `PATH`.
- 2026-08-08: same PVE/template/privilege model; subsequent fresh Default Install CT 901 completed end-to-end without installer errors after the LuaRocks, OpenResty readiness, launcher completion, installer-UX, template-storage, nesting/keyctl, and runtime-version fixes. A post-install `/usr/local/sbin/npm-lxc-healthcheck` invocation passed every native health check. Direct `pct exec 901 -- npm-lxc-healthcheck` initially failed only because Proxmox's direct command PATH omitted `/usr/local/sbin`; the helper itself was present and healthy. Follow-up commit `d3b6e01dde02d1ee57215e02ccc4b0583c2cc91f` exposes the user-facing administration helpers through `/usr/local/bin` as well.

## Container creation matrix

| Test | Status | Evidence / notes |
|---|---|---|
| Default container ID accepted | PASSED | 2026-08-08 fresh Default Install accepted the suggested unused CT 901 after the previous test CT had been removed. |
| Custom unused container ID | NOT RUN | |
| Cluster-wide used ID rejected | NOT RUN | |
| Default hostname | PASSED | 2026-08-08 fresh Default Install created hostname `nginx-proxy-manager`. |
| Custom valid hostname | NOT RUN | |
| Invalid hostname rejected | NOT RUN | |
| Storage selection | PASSED | Project-owned installer selected the LXC root storage while Debian template-cache storage was resolved automatically and no template-storage dialog was shown in the later clean run. |
| Bridge selection | PASSED | 2026-08-08 Default Install selected `vmbr0`. |
| DHCP | PASSED | Fresh Default Install obtained working DHCP IPv4 connectivity. |
| Static IPv4 CIDR | NOT RUN | |
| Gateway in selected subnet | NOT RUN | |
| Invalid gateway rejected | NOT RUN | |
| Optional VLAN blank | PASSED | 2026-08-08 fresh Default Install used no VLAN. |
| VLAN 1-4094 | NOT RUN | |
| Invalid VLAN rejected | NOT RUN | |
| Final Proxmox `net0` values | NOT RUN | |
| Advanced Install remains functional | NOT RUN | |
| Proxmox owns hostname and resolver files | NOT RUN | |
| Unprivileged container confirmed | PASSED | PVE 9.2.9 / Debian 13.6 CT 901 created and exercised as an unprivileged LXC; nesting and keyctl are not enabled by the launcher. |
| No Docker or Podman binary installed | PASSED | Latest clean runtime CT: health helper reported `PASS  no Docker runtime installed`. |

## Build and service matrix

| Test | Status | Evidence / notes |
|---|---|---|
| Fresh end-to-end installation from current branch | PASSED | 2026-08-08, PVE 9.2.9 / Debian 13.6 / fresh Default Install CT 901: launcher completed without errors; native OS/dependency setup, Node/Yarn, Certbot, LuaRocks/OpenResty, NPM frontend/backend build, release creation, SQLite initialization, migrations, backend/Nginx startup and final health checks all completed. The earlier host-side completion `$1` bug had already been corrected before this run. |
| Exact NPM commit fetched | PASSED | Clean CT 901 reached a completed immutable `2.15.1` release after verifying the pinned NPM commit. |
| Exact source blob checks pass | PASSED | Clean CT 901 completed the source-verification/build path using the pinned blob checks. |
| Node.js 22 and Yarn 1 validation | PASSED | Reconfirmed 2026-08-08 fresh runs: Node.js 22.23.2 and Yarn 1.22.22. |
| Frontend build completes | PASSED | Clean CT 901 completed locale compilation and the Vite production frontend build. |
| Backend native dependencies compile | PASSED | Clean CT 901 completed production backend dependency installation and immutable release creation. |
| OpenResty 1.29.2.5 build completes | PASSED | Clean CT 901 completed the native OpenResty 1.29.2.5 source build with the absolute LuaRocks path fix in place. |
| HTTP/3, stream, Lua and GeoIP2 flags present | NOT RUN | |
| Certbot 5.6.0 works | PASSED | Reconfirmed 2026-08-08 fresh run with pyOpenSSL 26.2.0 and cryptography 48.0.0; dependency check passed. |
| SQLite database initializes | PASSED | Clean CT 901 selected `/data/database.sqlite`, initialized the database and created JWT keys. |
| Official migrations complete | PASSED | Clean CT 901 completed the official migration chain before the backend began listening. |
| Backend systemd startup | PASSED | Latest clean run started the backend successfully and health validation confirmed port 3000 listening. Earlier empty-custom-include defect was fixed by `3d782a82f011f62e707666d7f81d4b1cabd4e17a`. |
| OpenResty systemd startup | PASSED | Latest clean run started OpenResty successfully with `PrivateTmp=true` retained; health validation confirmed configuration plus ports 80/81/443. Earlier private-temp defect was fixed by `4ff425adff791cb7248c52abac0e15217b3fcc7c`. |
| Restart policies recover processes | NOT RUN | Explicit start-limit safeguards are installed; process-recovery behavior still requires a deliberate failure/restart test. |
| Health helper passes | PASSED | 2026-08-08 latest clean CT 901: `/usr/local/sbin/npm-lxc-healthcheck` reported backend and Nginx active, OpenResty configuration valid, ports 3000/80/81/443 listening, administration UI responding, release marker present, and no Docker runtime installed. |
| Administration helpers reachable by short `pct exec` command | RETEST | Latest installed CT predates helper-link commit `d3b6e01dde02d1ee57215e02ccc4b0583c2cc91f`; absolute `/usr/local/sbin/npm-lxc-healthcheck` works. Current branch creates `/usr/local/bin` links for healthcheck/backup/restore/update so `pct exec <CTID> -- npm-lxc-healthcheck` should work on the next install. |
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
| Administration interface on port 81 | PASSED | Working CT returned HTTP 200 on port 81; earlier browser GUI login/dashboard navigation also succeeded. |
| First-run setup wizard | NOT RUN | Preserve as NOT RUN until the wizard path itself is explicitly confirmed/recorded on a clean empty data path. |
| No invented/default credentials | NOT RUN | |
| Create administrator | NOT RUN | |
| Runtime installed version metadata | PASSED | 2026-08-08 CT 901: `package.json` returned `2.15.1`; direct backend `/` returned version 2.15.1; `/version/check` returned `current: v2.15.1`, `latest: v2.15.1`, `update_available: false`. This validates the staged runtime version-stamp fix. |
| GUI displayed version / false update banner | RETEST | Backend/version API defect is closed, but preserve the browser-visible banner check until the GUI is explicitly observed after the corrected clean install. |
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

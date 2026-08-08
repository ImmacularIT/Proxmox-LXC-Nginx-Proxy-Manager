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

- 2026-08-07: Proxmox VE 9.2.9, kernel 7.0.14-9-pve; Debian 13.6 AMD64; unprivileged CT 901; DHCP IPv4 192.168.1.110. This instance reached a working backend/OpenResty/UI stack after targeted fixes.
- 2026-08-08: same PVE/template/privilege model; fresh Default Install CT 901; DHCP IPv4 192.168.1.113. This clean run stopped during the OpenResty preparation stage when the LuaRocks executable was installed under `/usr/local/bin` but then looked up through an environment-dependent `PATH`.
- 2026-08-08: same PVE/template/privilege model; subsequent fresh Default Install CT 901 completed end-to-end without installer errors after the LuaRocks, OpenResty readiness, launcher completion, installer-UX, template-storage, nesting/keyctl, and runtime-version fixes. A post-install `/usr/local/sbin/npm-lxc-healthcheck` invocation passed every native health check. Direct `pct exec 901 -- npm-lxc-healthcheck` initially failed only because Proxmox's direct command PATH omitted `/usr/local/sbin`; the helper itself was present and healthy. Follow-up commit `d3b6e01dde02d1ee57215e02ccc4b0583c2cc91f` exposes the user-facing administration helpers through `/usr/local/bin` as well. The same CT then survived `pct reboot 901` with nesting disabled: Proxmox emitted its generic Systemd 257 nesting warning, the task completed, CT 901 returned to `running`, the complete native health check passed again, and DHCP assigned 192.168.1.117.
- 2026-08-08: a new unprivileged Debian 13.6 CT 901 received DHCP IPv4 192.168.1.118 and was used for the first real Let's Encrypt HTTP-challenge test. Runtime tracing exposed three native-systemd compatibility requirements before Certbot could run: the unprivileged backend needs `CAP_NET_BIND_SERVICE` for upstream's child `nginx -t`, the backend's `PrivateTmp` namespace needs the official `/tmp/nginx` path bound to its service-owned cache directory, and upstream's `-g "error_log off;"` test requires a read-only-safe `/etc/nginx/nginx/off -> /dev/null` compatibility target. After those fixes, Certbot 5.6.0 reached the production Let's Encrypt ACME API successfully. The first ACME registration was then correctly rejected because the deliberately fake NPM account email `test@example.com` uses the forbidden `example.com` domain; replacing it with a real email allowed certificate issuance for `oiko.iclust.se` to succeed.
- 2026-08-08: follow-up fresh clean installation from the current development branch, with the ACME/systemd compatibility fixes integrated rather than patched manually. The maintainer then completed a real Let's Encrypt HTTP-challenge test for three real subdomains and certificate issuance succeeded for all three. This confirms the certificate-path fixes work as part of a clean install and are not artifacts of the earlier patched test container. One tested proxy host had WebSockets Support enabled and the proxied application worked. Another terminated external HTTPS with a Let's Encrypt certificate, had Force SSL enabled, and successfully proxied to an internal HTTP backend on port 8080. The same clean runtime displayed the correct `v2.15.1` GUI footer without a false update banner, supported administrator creation and removal, successfully enrolled and used TOTP two-factor authentication, presented the official first-run setup wizard on initial GUI access, and required creation of the first administrator because no default credentials were present.

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
| Fresh end-to-end installation from current branch | PASSED | 2026-08-08, PVE 9.2.9 / Debian 13.6: fresh Default Install completed the native build/startup path without manual runtime patching, and the later clean-install verification with the integrated ACME/systemd fixes proceeded far enough to obtain real Let's Encrypt certificates for three subdomains. |
| Exact NPM commit fetched | PASSED | Clean CT 901 reached a completed immutable `2.15.1` release after verifying the pinned NPM commit. |
| Exact source blob checks pass | PASSED | Clean CT 901 completed the source-verification/build path using the pinned blob checks. |
| Node.js 22 and Yarn 1 validation | PASSED | Reconfirmed 2026-08-08 fresh runs: Node.js 22.23.2 and Yarn 1.22.22. |
| Frontend build completes | PASSED | Clean CT 901 completed locale compilation and the Vite production frontend build. |
| Backend native dependencies compile | PASSED | Clean CT 901 completed production backend dependency installation and immutable release creation. |
| OpenResty 1.29.2.5 build completes | PASSED | Clean CT 901 completed the native OpenResty 1.29.2.5 source build with the absolute LuaRocks path fix in place. |
| HTTP/3, stream, Lua and GeoIP2 flags present | NOT RUN | |
| Certbot 5.6.0 works | PASSED | Reconfirmed 2026-08-08 fresh run with pyOpenSSL 26.2.0 and cryptography 48.0.0; dependency check passed. Real ACME flows also launched Certbot 5.6.0 successfully, contacted the production Let's Encrypt directory, and issued certificates. |
| SQLite database initializes | PASSED | Clean CT 901 selected `/data/database.sqlite`, initialized the database and created JWT keys. |
| Official migrations complete | PASSED | Clean CT 901 completed the official migration chain before the backend began listening. |
| Backend systemd startup | PASSED | Latest clean run started the backend successfully and health validation confirmed port 3000 listening. Earlier empty-custom-include defect was fixed by `3d782a82f011f62e707666d7f81d4b1cabd4e17a`. |
| OpenResty systemd startup | PASSED | Latest clean run started OpenResty successfully with `PrivateTmp=true` retained; health validation confirmed configuration plus ports 80/81/443. Earlier private-temp defect was fixed by `4ff425adff791cb7248c52abac0e15217b3fcc7c`. |
| Restart policies recover processes | NOT RUN | Explicit start-limit safeguards are installed; process-recovery behavior still requires a deliberate failure/restart test. |
| Health helper passes | PASSED | 2026-08-08 latest clean CT 901: `/usr/local/sbin/npm-lxc-healthcheck` reported backend and Nginx active, OpenResty configuration valid, ports 3000/80/81/443 listening, administration UI responding, release marker present, and no Docker runtime installed. |
| Administration helpers reachable by short `pct exec` command | RETEST | Latest installed CT predates helper-link commit `d3b6e01dde02d1ee57215e02ccc4b0583c2cc91f`; absolute `/usr/local/sbin/npm-lxc-healthcheck` works. Current branch creates `/usr/local/bin` links for healthcheck/backup/restore/update so `pct exec <CTID> -- npm-lxc-healthcheck` should work on the next install. |
| Full container reboot survives | PASSED | 2026-08-08 CT 901: `pct reboot 901` completed with only Proxmox's generic `Systemd 257 detected. You may need to enable nesting.` warning. Nesting remained disabled. After reboot `pct status 901` reported `running`, both services were active, all ports and OpenResty configuration passed health checks, the administration UI responded, and no Docker runtime was present. |
| Persistent data survives reboot | PASSED | 2026-08-08 fresh clean-install runtime with real proxy hosts and Let's Encrypt certificates was rebooted; the maintainer confirmed the persisted application data remained intact and the configured services continued working without issues after the CT returned. |

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
| First-run setup wizard | PASSED | 2026-08-08 fresh clean-install GUI test: the official setup wizard appeared on first access to an empty installation and completed successfully. |
| No invented/default credentials | PASSED | 2026-08-08 fresh clean-install GUI test: no default administrator credentials existed; the first administrator had to be created through the setup wizard. |
| Create administrator | PASSED | 2026-08-08 fresh clean-install GUI test: administrator creation and removal both worked normally. |
| Two-factor authentication (TOTP) | PASSED | 2026-08-08 fresh clean-install GUI test: TOTP two-factor authentication enrollment and authentication worked successfully. |
| Runtime installed version metadata | PASSED | 2026-08-08 CT 901: `package.json` returned `2.15.1`; direct backend `/` returned version 2.15.1; `/version/check` returned `current: v2.15.1`, `latest: v2.15.1`, `update_available: false`. This validates the staged runtime version-stamp fix. |
| GUI displayed version / false update banner | PASSED | 2026-08-08 fresh clean-install GUI footer displayed `© 2026 jc21.com Theme by Tabler v2.15.1`; the visible version matched the pinned runtime and no false update banner was present. |
| Create HTTP proxy host | PASSED | 2026-08-08 fresh clean-install real-subdomain test: NPM successfully proxied an externally accessed HTTPS host to an internal HTTP service on port 8080. |
| Proxy to HTTPS backend | NOT RUN | The tested upstream service was HTTP on port 8080; an HTTPS upstream/backend still needs a separate test. |
| WebSocket proxying | PASSED | 2026-08-08 fresh clean-install real-subdomain test: WebSockets Support was enabled on the first tested proxy host and the proxied application worked successfully through NPM. |
| Access list behavior | NOT RUN | |
| HTTP-to-HTTPS redirect | PASSED | 2026-08-08 fresh clean-install real-subdomain test: Force SSL was enabled with a Let's Encrypt certificate; external access over HTTPS worked while the upstream remained HTTP on port 8080. |
| Certificate import | NOT RUN | |
| Let's Encrypt HTTP challenge | PASSED | 2026-08-08: initial real ACME tracing on CT 901 / 192.168.1.118 reached production Let's Encrypt and succeeded after replacing the deliberately invalid `test@example.com` account email with a real address. A subsequent fresh clean installation from the current development branch then issued Let's Encrypt certificates successfully for three real subdomains with the compatibility fixes integrated and no manual runtime patching. |
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

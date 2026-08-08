# Runtime test plan

No item in this document is passed by repository review alone. Record the
Proxmox version, Debian template version, container ID, date, tester, observed
result, logs or screenshots where useful, and the fixing commit for every
failure.

## Test environment

Target environment:

- Proxmox VE 9.x;
- unprivileged Debian 13 LXC with `nesting=1` and keyctl disabled;
- Debian 13.6 template where available;
- AMD64 architecture;
- disposable storage and a pre-install snapshot;
- test DNS names routed to the container;
- inbound TCP 80 and TCP/UDP 443 where certificate and HTTP/3 testing requires it;
- disposable HTTP, HTTPS, and WebSocket backends.

Runtime-validation instances:

- 2026-08-07: Proxmox VE 9.2.9, kernel 7.0.14-9-pve; Debian 13.6 AMD64; unprivileged CT 901. Initial native runtime validation exposed and corrected installation/service compatibility defects.
- 2026-08-08: repeated fresh Default Install runs on the same PVE/template/privilege model validated the LuaRocks/OpenResty path fixes, startup readiness, independent launcher completion, installer UX, template-storage behavior, runtime version metadata, and helper-command behavior. Those earlier runs also proved that Nginx Proxy Manager itself does not require nesting or keyctl to function.
- 2026-08-08: real certificate tracing exposed three native-systemd compatibility requirements before Certbot could complete: backend `CAP_NET_BIND_SERVICE` for upstream child `nginx -t`, a backend `PrivateTmp` mapping for the official `/tmp/nginx` path, and a read-only-safe `/etc/nginx/nginx/off -> /dev/null` compatibility target for upstream's `error_log off` test. These were fixed and regression-guarded.
- 2026-08-08: a subsequent fresh clean installation with those fixes integrated successfully issued production Let's Encrypt certificates for three real subdomains. HTTP proxying, Force SSL, WebSockets, first-run setup, administrator management, TOTP, correct `v2.15.1` GUI/version reporting, reboot persistence, and Proxmox branding were also confirmed.
- 2026-08-08: the maintainer confirmed the complete Container creation, Build and service, Proxmox branding, and Application feature matrices below all pass on the tested Proxmox VE 9.2.9 / Debian 13.6 AMD64 environment.
- 2026-08-08: after those matrices passed, the host launcher was tightened to refresh the Proxmox appliance catalog on every approved installation and download/use the newest Debian 13 AMD64 template when the cached copy is older. The install-method chooser was also simplified without changing Default/Advanced behavior.
- 2026-08-08: the maintainer completed a final fresh installation from release-candidate head `c7653f4cc712e6a2702988038a7f445d48e6445a` and confirmed the resulting installation works correctly. The successful installer completion also confirms its mandatory native `npm-lxc-healthcheck` completed successfully. The launcher cannot reach container creation if its mandatory `pveam update` catalog refresh fails, so the final run also confirms the refreshed-catalog path executed successfully. The special older-cache and empty-cache download branches were not separately claimed as runtime-exercised.
- 2026-08-08: after the successful final installation, the production container default was changed to enable Proxmox `nesting=1` while remaining unprivileged and leaving keyctl disabled. This is intended to suppress the recurring `Systemd 257 detected. You may need to enable nesting.` Proxmox start warning. Because this changes the host-side CT configuration, one narrow final start/reboot warning check remains before promotion.

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
| Unprivileged container confirmed | PASSED | Maintainer-confirmed complete matrix pass. The current launcher remains unprivileged, enables `nesting=1` as a fixed production default, and does not enable keyctl. |
| No Docker or Podman binary installed | PASSED | Maintainer-confirmed complete matrix pass; native health validation also confirmed no Docker runtime. |

## Build and service matrix

The maintainer confirmed the complete matrix below as passing on 2026-08-08.

| Test | Status | Evidence / notes |
|---|---|---|
| Fresh end-to-end installation from current branch | PASSED | Maintainer-confirmed complete matrix pass; final release-candidate installation also completed successfully before the subsequent nesting-default change. |
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
| Health helper passes | PASSED | Maintainer-confirmed complete matrix pass; final release-candidate installer also reached completion after its mandatory health check. |
| Administration helpers reachable by short `pct exec` command | PASSED | Maintainer-confirmed complete matrix pass for the supported `npm-lxc-healthcheck` helper. |
| Full container reboot survives | PASSED | Maintainer-confirmed complete matrix pass on the earlier non-nesting configuration. The current `nesting=1` production configuration has a separate narrow reboot gate below. |
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

## Final release-candidate smoke test

The application/runtime matrices above remain PASSED. The following narrow
release-candidate checks cover host-side changes made after those tests.

| Test | Status | Evidence / notes |
|---|---|---|
| Proxmox appliance catalog refreshes before template selection | PASSED | Final fresh installation completed successfully. The launcher runs mandatory `pveam update` before template selection and aborts on failure, so successful continuation confirms this path completed. |
| Older cached Debian 13 template downloads current catalog template | NOT RUN | Version comparison/download behavior is regression-guarded in CI, but this exact older-cache branch was not explicitly observed during the final runtime run. It is not claimed as a runtime PASS. |
| Missing Debian 13 template downloads automatically | NOT RUN | Automatic-download behavior is regression-guarded in CI, but this exact empty-cache branch was not explicitly observed during the final runtime run. It is not claimed as a runtime PASS. |
| Fresh install and `npm-lxc-healthcheck` pass on pre-nesting release-candidate head | PASSED | Maintainer confirmed the final installation from `c7653f4cc712e6a2702988038a7f445d48e6445a` completed and works correctly. The installer executes `/usr/local/sbin/npm-lxc-healthcheck` before reporting successful service startup, so normal completion confirms the health check passed. |
| Current CT configuration is unprivileged with `nesting=1` and keyctl disabled | RETEST | Current launcher now passes `--unprivileged 1 --features nesting=1` to `pct create` and does not enable keyctl. Requires real Proxmox confirmation. |
| Proxmox start/reboot no longer reports the Systemd 257 nesting warning | RETEST | This is the reason for enabling nesting and must be observed on the real PVE host before promotion. |
| Current nesting-enabled CT remains healthy after start/reboot | RETEST | Run the native health check after the start/reboot used for the warning test. The full NPM application matrix does not need to be repeated unless a regression is observed. |

The final promotion gate is reopened only for the nesting-enabled Proxmox CT
configuration. The two unobserved template-cache edge branches remain explicitly
unclaimed runtime paths; they are guarded by automated tests and do not reopen
the already-completed NPM runtime matrices.

## Future lifecycle features

Backup/restore and adaptation-level in-place update/rollback tooling are not
upstream NPM application features and are not release gates for this native
adaptation. They may be designed and validated as separate future ImmacularIT
project features.

The current project metadata therefore uses `updateable: false`, and the
installer does not ship `npm-lxc-backup`, `npm-lxc-restore`, or
`npm-lxc-update` commands. NPM's own certificate import and certificate download
behavior remains part of the Application feature matrix above.

When the original NPM author publishes a new release, maintain it as a new
adaptation cycle: create a new development branch, update and review exact
upstream pins, inspect Docker/runtime/build/migration changes, run repository CI,
perform a fresh Proxmox installation, and repeat the runtime validation required
for the changed release before promoting it.
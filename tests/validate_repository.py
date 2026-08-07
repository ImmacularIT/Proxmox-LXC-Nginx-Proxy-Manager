#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

required_files = [
    "ct/nginx-proxy-manager.sh",
    "install/nginx-proxy-manager-install.sh",
    "json/nginx-proxy-manager.json",
    "lib/versions.sh",
    "scripts/build-openresty-native.sh",
    "scripts/install-release.sh",
    "scripts/npm-prepare.sh",
    "scripts/npm-healthcheck.sh",
    "scripts/npm-backup.sh",
    "scripts/npm-restore.sh",
    "scripts/npm-update.sh",
    "systemd/nginx-proxy-manager-backend.service",
    "systemd/nginx-proxy-manager-nginx.service",
    "docs/PROJECT-HANDOFF.md",
    "docs/PROXMOX-BRANDING.md",
    "docs/RUNTIME-TEST-PLAN.md",
    "README.md",
]
for relative in required_files:
    assert (ROOT / relative).is_file(), f"Missing required file: {relative}"

workflow = (ROOT / ".github/workflows/syntax.yml").read_text()
assert "actions/checkout@11d5960a326750d5838078e36cf38b85af677262" in workflow
assert "actions/checkout@v" not in workflow

metadata = json.loads((ROOT / "json/nginx-proxy-manager.json").read_text())
for key in {
    "name", "slug", "type", "updateable", "privileged", "interface_port",
    "description", "install_methods", "repository_url",
}:
    assert key in metadata, f"Missing metadata field: {key}"
assert metadata["slug"] == "nginx-proxy-manager"
assert metadata["type"] == "ct"
assert metadata["privileged"] is False
assert metadata["interface_port"] == 81
assert metadata["install_methods"][0]["script"] == "ct/nginx-proxy-manager.sh"
assert metadata["install_methods"][0]["resources"]["version"] == "13"
assert "default_credentials" not in metadata

versions = (ROOT / "lib/versions.sh").read_text()
expected_pins = {
    "NPM_RELEASE": "v2.15.1",
    "NPM_COMMIT": "76f09db610cfcaecf6d608a8947d6f75aa028870",
    "NPM_BASE_COMMIT": "fe5ba055ed29033a619e9103bef5d8218fe1fab0",
    "NPM_FRONTEND_LOCK_BLOB": "d5f803762f90cd7e126270b0ba154d9caad85936",
    "NPM_BASE_DOCKERFILE_BLOB": "3837f53f9553ca15d1a420297d7a9d9a2b179b4c",
    "NPM_BASE_CERTBOT_DOCKERFILE_BLOB": "27847736cda2053880267613aa1ec9acf3dbba38",
    "NPM_BASE_CERTBOT_NODE_DOCKERFILE_BLOB": "73dd3e3d5be801cabcb8a7a6e25d10387d091ef1",
    "NPM_BASE_BUILD_OPENRESTY_BLOB": "433373cb54b93aa2539cd04edac19ea069c471ca",
    "OPENRESTY_VERSION": "1.29.2.5",
    "OPENRESTY_COMMIT": "2ec0f65e434c92e9f78fd5c3af601a6b286c6d2b",
    "GEOIP2_COMMIT": "445df24ef3781e488cee3dfe8a1e111997fc1dfe",
    "NODE_MAJOR": "22",
    "CERTBOT_VERSION": "5.6.0",
}
for name, value in expected_pins.items():
    marker = f'readonly {name}="{value}"'
    assert marker in versions, f"Missing or changed pin: {marker}"
assert "PVE_BUILD_COMMIT" not in versions

launcher = (ROOT / "ct/nginx-proxy-manager.sh").read_text()
for marker in [
    "prompt_identity",
    "prompt_network",
    "select_storage",
    "find_or_download_template",
    "pct create",
    "pveam update",
    "set_project_description",
    "nginx-proxy-manager;reverse-proxy;immacularit;webserver",
    "unofficial native Proxmox LXC adaptation",
    "No installation telemetry or usage data is sent",
]:
    assert marker in launcher, f"Missing launcher marker: {marker}"
assert "donate" not in launcher.lower()

installer = (ROOT / "install/nginx-proxy-manager-install.sh").read_text()
for marker in [
    "EXPECTED_NPM_COMMIT",
    "build-openresty-native.sh",
    "install-release.sh",
    "nginx-proxy-manager-backend.service",
    "nginx-proxy-manager-nginx.service",
    "DB_SQLITE_FILE=/data/database.sqlite",
    "No default administrator credentials were created",
    "service_diagnostics",
    "export LANG=C.UTF-8",
    "export LC_ALL=C.UTF-8",
    "service identity enforced by systemd",
]:
    assert marker in installer, f"Missing installer marker: {marker}"
assert "FUNCTIONS_FILE_PATH" not in installer
assert "msg_info" not in installer
assert "msg_ok" not in installer
assert "msg_error" not in installer
assert "%s: " in installer, "Status labels must be separated from live command output with a colon"

# Neither host-side container creation nor container-side installation may
# contact, advertise, or report diagnostics to an unrelated script service.
launcher_and_installer = launcher + "\n" + installer
for forbidden in [
    "telemetry.community-scripts.org",
    "git.community-scripts.org",
    "raw.githubusercontent.com/community-scripts",
    "community-scripts.github.io",
    "post_to_api",
    "post_progress_to_api",
    "DIAGNOSTICS=",
    "TELEMETRY_",
]:
    assert forbidden not in launcher_and_installer, f"Forbidden external framework runtime marker: {forbidden}"

# Helper scripts are copied into /usr/local/lib/npm-lxc at runtime. They must
# prefer the installed versions manifest and only fall back to the repository
# relative path when executed directly from a source checkout.
for helper_name in ["build-openresty-native.sh", "install-release.sh"]:
    helper = (ROOT / "scripts" / helper_name).read_text()
    assert 'NPM_LXC_LIB_DIR:-/usr/local/lib/npm-lxc' in helper, (
        f"Installed-layout version lookup missing from {helper_name}"
    )
    assert 'if [[ -r "$LIB_DIR/versions.sh" ]]' in helper, (
        f"Installed versions manifest guard missing from {helper_name}"
    )
    assert "export LANG=C.UTF-8" in helper and "export LC_ALL=C.UTF-8" in helper, (
        f"Neutral UTF-8 build locale missing from {helper_name}"
    )

install_release = (ROOT / "scripts/install-release.sh").read_text()
assert "yarn locale-compile" in install_release, "Official frontend locale compilation step missing"
assert install_release.index("yarn locale-compile") < install_release.index("NODE_ENV=production yarn build"), (
    "Frontend locales must be compiled before the production frontend build"
)
assert "src/locale/lang/en.json" in install_release
assert "src/locale/lang/lang-list.json" in install_release
assert "better-sqlite3" in install_release, "Runtime-critical SQLite module load validation missing"
assert "pkg.version = releaseVersion" in install_release, "Verified release version is not stamped into runtime package metadata"
assert install_release.index('verify_blob backend/package.json') < install_release.index("pkg.version = releaseVersion"), (
    "Runtime version metadata may only be adapted after immutable upstream package verification"
)
assert "Staged backend version metadata mismatch" in install_release

production_shell = "\n".join(
    p.read_text(errors="replace")
    for p in [ROOT / "install/nginx-proxy-manager-install.sh", *sorted((ROOT / "scripts").glob("*.sh"))]
)
for pattern in [
    r"apt(?:-get)?\s+install[^\n]*(?:docker|podman)",
    r"get\.docker\.com",
    r"docker\s+compose\s+up",
    r"podman\s+run",
]:
    assert not re.search(pattern, production_shell, flags=re.I), f"Nested runtime command found: {pattern}"

for pattern in [
    r"hostnamectl\s+set-hostname",
    r"(?:>|tee\s+)(?:/etc/hosts|/etc/resolv\.conf|/etc/network/interfaces)",
    r"\bufw\b",
]:
    assert not re.search(pattern, production_shell, flags=re.I), f"Proxmox-owned networking mutation found: {pattern}"

prepare = (ROOT / "scripts/npm-prepare.sh").read_text()
for marker in [
    "/data/nginx/proxy_host",
    "/data/nginx/redirection_host",
    "/data/nginx/stream",
    "/data/nginx/dead_host",
    "/data/letsencrypt-acme-challenge",
    "/etc/letsencrypt",
    "/var/backups/nginx-proxy-manager",
    "/etc/nginx/conf.d/include/ip_ranges.conf",
]:
    assert marker in prepare, f"Missing persistent/runtime path marker: {marker}"
assert '[[ -s "$conf" ]] || continue' in prepare, "Empty Nginx include files must be accepted"
assert "IPv6 rewrite produced an empty file" not in prepare, "Empty custom includes must not be fatal"

# Production application source must use immutable commits, not mutable branches.
assert "NginxProxyManager/nginx-proxy-manager/main" not in production_shell
assert "NginxProxyManager/nginx-proxy-manager/develop" not in production_shell
assert "NginxProxyManager/docker-nginx-full/main" not in production_shell
assert "NginxProxyManager/docker-nginx-full/master" not in production_shell

for unit in (ROOT / "systemd").glob("*.service"):
    text = unit.read_text()
    assert "[Service]" in text
    assert "Restart=on-failure" in text
    assert "User=npm" in text
    assert "NoNewPrivileges=true" in text
    assert "ProtectSystem=strict" in text
    assert "PrivateTmp=true" in text
    assert "RuntimeDirectory=nginx" in text
    assert "ExecStartPre=+/usr/local/sbin/npm-lxc-prepare" in text
    assert "StartLimitIntervalSec=60" in text
    assert "StartLimitBurst=5" in text

nginx_unit = (ROOT / "systemd/nginx-proxy-manager-nginx.service").read_text()
assert "CacheDirectory=nginx/tmp" in nginx_unit, "Nginx private temp backing directory missing"
assert "CacheDirectoryMode=0750" in nginx_unit
assert "BindPaths=/var/cache/nginx/tmp:/tmp/nginx" in nginx_unit, (
    "Official /tmp/nginx path must survive per-process systemd filesystem namespaces"
)

for path in ROOT.rglob("*"):
    if path.is_file() and ".git" not in path.parts:
        lowered = path.name.lower()
        assert lowered not in {"placeholder", "placeholder.txt", "todo.txt"}, f"Placeholder file committed: {path}"

print("Repository structure and conversion markers validated.")

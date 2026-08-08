#!/usr/bin/env bash
# Copyright (c) 2026 ImmacularIT
# License: MIT
# Upstream application: https://github.com/NginxProxyManager/nginx-proxy-manager
set -Eeuo pipefail

APP="Nginx Proxy Manager"
PROJECT_OWNER="ImmacularIT"
PROJECT_REPO="Proxmox-LXC-Nginx-Proxy-Manager"
PROJECT_REF="${NPM_PROJECT_REF:-develop/native-lxc-v2.15.1}"
PROJECT_URL="https://github.com/${PROJECT_OWNER}/${PROJECT_REPO}"
PROJECT_INSTALL_URL="https://raw.githubusercontent.com/${PROJECT_OWNER}/${PROJECT_REPO}/${PROJECT_REF}/install/nginx-proxy-manager-install.sh"
UPSTREAM_PROJECT_URL="https://github.com/NginxProxyManager/nginx-proxy-manager"
IMMACULARIT_PROFILE_URL="https://github.com/ImmacularIT"
IMMACULARIT_LOGO_URL="https://raw.githubusercontent.com/ImmacularIT/Proxmox-Itiligent-Guacamole/15c268e6fd0e6f9b441aa9f785c278c3f580171b/assets/immacularit-logo.png"
NPM_LOGO_URL="https://nginxproxymanager.com/github.png"
BACKTITLE="ImmacularIT - ${APP}"

DEFAULT_DISK=16
DEFAULT_CPU=2
DEFAULT_RAM=4096
DEFAULT_HOSTNAME="nginx-proxy-manager"
DEFAULT_BRIDGE="vmbr0"
DEFAULT_TAGS="nginx-proxy-manager;reverse-proxy;immacularit;webserver"

CTID=""
HN=""
ROOT_STORAGE=""
TEMPLATE_STORAGE="${NPM_TEMPLATE_STORAGE:-}"
BRG="$DEFAULT_BRIDGE"
NET="dhcp"
GATE=""
VLAN=""
CPU="$DEFAULT_CPU"
RAM="$DEFAULT_RAM"
DISK="$DEFAULT_DISK"
ONBOOT=1
INSTALL_LOG=""

info() { printf '\n  ⏳ %s: ' "${1%:}"; }
ok() { printf '\n  ✔️  %s\n' "$1"; }
warn() { printf '\n  ⚠️  %s\n' "$1" >&2; }
fatal() { printf '\n  ✖️  %s\n' "$1" >&2; exit 1; }

cleanup_temp=()
cleanup() {
  local f
  for f in "${cleanup_temp[@]:-}"; do
    [[ -n "$f" ]] && rm -f -- "$f"
  done
}
trap cleanup EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || fatal "Required command is missing on the Proxmox host: $1"
}

for cmd in pveversion pvesh pct pvesm pveam curl whiptail awk grep sed sort ip; do
  require_command "$cmd"
done

[[ "$(id -u)" -eq 0 ]] || fatal "Run this launcher directly as root on the Proxmox VE host"
PVE_RAW="$(pveversion)"
PVE_VERSION="$(printf '%s' "$PVE_RAW" | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"
[[ "$PVE_VERSION" == 9.* ]] || fatal "This project currently targets Proxmox VE 9.x; found ${PVE_RAW}"
[[ "$(dpkg --print-architecture)" == "amd64" ]] || fatal "The current runtime test gate supports AMD64 only"

show_welcome() {
  whiptail --backtitle "$BACKTITLE" --title "WELCOME" \
    --ok-button "Continue" \
    --msgbox "\nThis independent ImmacularIT installer creates an unprivileged Debian 13 LXC and installs Nginx Proxy Manager natively.\n\nThe final container does not require Docker, Podman, Kubernetes, or another nested container runtime.\n\nDefault Install asks only for user-facing container choices. Debian template storage and the latest available Debian 13 AMD64 template are handled automatically by the launcher.\n\nYou can review the complete container configuration before anything is created.\n\nNo installation telemetry or usage data is sent by this launcher." \
    21 78
}

valid_container_id() {
  local id="$1"
  [[ "$id" =~ ^[0-9]+$ ]] || return 1
  ! pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
    | grep -Eq '"vmid"[[:space:]]*:[[:space:]]*'"$id"'([,}])'
}

valid_hostname() {
  local name="$1" label
  [[ ${#name} -ge 1 && ${#name} -le 253 ]] || return 1
  [[ "$name" =~ ^[a-z0-9.-]+$ ]] || return 1
  IFS='.' read -r -a labels <<<"$name"
  for label in "${labels[@]}"; do
    [[ -n "$label" && ${#label} -le 63 ]] || return 1
    [[ "$label" != -* && "$label" != *- ]] || return 1
  done
}

valid_ipv4() {
  local ip="$1" a b c d n
  IFS='.' read -r a b c d <<<"$ip"
  [[ -n "${a:-}" && -n "${b:-}" && -n "${c:-}" && -n "${d:-}" ]] || return 1
  for n in "$a" "$b" "$c" "$d"; do
    [[ "$n" =~ ^[0-9]+$ ]] || return 1
    (( n >= 0 && n <= 255 )) || return 1
  done
}

valid_cidr() {
  local value="$1" ip prefix
  [[ "$value" == */* ]] || return 1
  ip="${value%/*}"
  prefix="${value#*/}"
  valid_ipv4 "$ip" || return 1
  [[ "$prefix" =~ ^[0-9]+$ ]] && (( prefix >= 0 && prefix <= 32 ))
}

ip_to_int() {
  local ip="$1" a b c d
  IFS='.' read -r a b c d <<<"$ip"
  printf '%u' "$(( (a << 24) | (b << 16) | (c << 8) | d ))"
}

gateway_in_subnet() {
  local cidr="$1" gw="$2" ip prefix ipn gwn mask
  ip="${cidr%/*}"
  prefix="${cidr#*/}"
  valid_ipv4 "$gw" || return 1
  ipn="$(ip_to_int "$ip")"
  gwn="$(ip_to_int "$gw")"
  if (( prefix == 0 )); then
    return 0
  fi
  mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
  (( (ipn & mask) == (gwn & mask) ))
}

valid_vlan() {
  local vlan="$1"
  [[ -z "$vlan" ]] && return 0
  [[ "$vlan" =~ ^[0-9]+$ ]] && (( vlan >= 1 && vlan <= 4094 ))
}

select_storage() {
  local selected default_storage
  local -a stores=() menu=()
  mapfile -t stores < <(pvesm status --content rootdir 2>/dev/null | awk 'NR > 1 && $3 == "active" {print $1}')
  [[ ${#stores[@]} -gt 0 ]] || fatal "No active Proxmox storage supports LXC root disks"
  default_storage="${stores[0]}"
  for selected in "${stores[@]}"; do
    menu+=("$selected" "Active container storage")
  done
  selected=$(whiptail --backtitle "$BACKTITLE" --title "STORAGE" \
    --ok-button "Next" --cancel-button "Exit Script" \
    --menu "\nSelect storage for the LXC root disk:" 18 72 10 "${menu[@]}" \
    --default-item "$default_storage" 3>&1 1>&2 2>&3) || exit 0
  printf '%s' "$selected"
}

resolve_template_storage() {
  local latest_template="${1:-}" requested="${TEMPLATE_STORAGE:-}" storage
  local -a stores=()
  mapfile -t stores < <(pvesm status --content vztmpl 2>/dev/null | awk 'NR > 1 && $3 == "active" {print $1}')
  [[ ${#stores[@]} -gt 0 ]] || fatal "No active Proxmox storage supports container templates (vztmpl)"

  if [[ -n "$requested" ]]; then
    for storage in "${stores[@]}"; do
      if [[ "$storage" == "$requested" ]]; then
        printf '%s' "$storage"
        return 0
      fi
    done
    fatal "Requested template storage is not active or does not support vztmpl: ${requested}"
  fi

  # Prefer a storage that already contains the exact newest catalog template.
  # This avoids an unnecessary duplicate download when the latest template is
  # cached outside Proxmox's conventional `local` storage.
  if [[ -n "$latest_template" ]]; then
    for storage in "${stores[@]}"; do
      if pveam list "$storage" 2>/dev/null \
        | awk -v wanted="vztmpl/${latest_template}" '
            length($1) >= length(wanted) && substr($1, length($1) - length(wanted) + 1) == wanted {found=1}
            END {exit !found}
          '; then
        printf '%s' "$storage"
        return 0
      fi
    done
  fi

  # If the latest catalog template is not cached anywhere, prefer a storage
  # already used for Debian 13 templates so the cache stays consolidated.
  for storage in "${stores[@]}"; do
    if pveam list "$storage" 2>/dev/null \
      | awk '$1 ~ /debian-13-standard_.*_amd64\.tar\.zst$/ {found=1} END {exit !found}'; then
      printf '%s' "$storage"
      return 0
    fi
  done

  # `local` is Proxmox's conventional template/cache storage. If it is not
  # available, use the first active vztmpl-capable storage deterministically.
  for storage in "${stores[@]}"; do
    if [[ "$storage" == "local" ]]; then
      printf '%s' "$storage"
      return 0
    fi
  done
  printf '%s' "${stores[0]}"
}

select_bridge() {
  local path bridge selected
  local -a bridges=() menu=()
  for path in /sys/class/net/*/bridge; do
    [[ -d "$path" ]] || continue
    bridge="${path%/bridge}"
    bridge="${bridge##*/}"
    bridges+=("$bridge")
  done
  [[ ${#bridges[@]} -gt 0 ]] || fatal "No Proxmox network bridge was found"
  for bridge in "${bridges[@]}"; do
    if [[ "$bridge" == "$DEFAULT_BRIDGE" ]]; then
      menu+=("$bridge" "Current default")
    else
      menu+=("$bridge" "Available bridge")
    fi
  done
  selected=$(whiptail --backtitle "$BACKTITLE" --title "NETWORK BRIDGE" \
    --ok-button "Next" --cancel-button "Exit Script" \
    --menu "\nSelect the bridge for this container:" 18 72 10 "${menu[@]}" \
    --default-item "$DEFAULT_BRIDGE" 3>&1 1>&2 2>&3) || exit 0
  printf '%s' "$selected"
}

prompt_identity() {
  local suggested id name
  suggested="$(pvesh get /cluster/nextid 2>/dev/null)"
  while true; do
    id=$(whiptail --backtitle "$BACKTITLE" --title "CONTAINER ID" \
      --ok-button "Next" --cancel-button "Exit Script" \
      --inputbox "\nContainer ID\n\nPress Enter to use the suggested ID." 12 62 "$suggested" \
      3>&1 1>&2 2>&3) || exit 0
    if valid_container_id "$id"; then CTID="$id"; break; fi
    whiptail --backtitle "$BACKTITLE" --title "INVALID CONTAINER ID" --msgbox "Container ID must be numeric and unused across the cluster." 9 62
  done
  while true; do
    name=$(whiptail --backtitle "$BACKTITLE" --title "CONTAINER NAME" \
      --ok-button "Next" --cancel-button "Exit Script" \
      --inputbox "\nContainer name\n\nPress Enter to use the suggested name." 12 66 "$DEFAULT_HOSTNAME" \
      3>&1 1>&2 2>&3) || exit 0
    name="${name,,}"
    name="${name// /}"
    if valid_hostname "$name"; then HN="$name"; break; fi
    whiptail --backtitle "$BACKTITLE" --title "INVALID CONTAINER NAME" --msgbox "Use lowercase letters, numbers, dots and hyphens only. Labels cannot start or end with a hyphen." 10 66
  done
}

prompt_network() {
  local method static_ip gateway vlan
  BRG="$(select_bridge)"
  method=$(whiptail --backtitle "$BACKTITLE" --title "IPv4" \
    --ok-button "Next" --cancel-button "Exit Script" \
    --menu "\nChoose how the container receives its IPv4 address:" 15 68 2 \
    "dhcp" "Automatic address from DHCP (recommended)" \
    "static" "Static IPv4 address" \
    --default-item "dhcp" 3>&1 1>&2 2>&3) || exit 0
  if [[ "$method" == "static" ]]; then
    while true; do
      static_ip=$(whiptail --backtitle "$BACKTITLE" --title "STATIC IPv4" \
        --ok-button "Next" --cancel-button "Exit Script" \
        --inputbox "\nEnter IPv4 address in CIDR form.\nExample: 192.168.1.50/24" 12 68 "" \
        3>&1 1>&2 2>&3) || exit 0
      valid_cidr "$static_ip" && break
      whiptail --backtitle "$BACKTITLE" --title "INVALID IPv4" --msgbox "Enter a valid IPv4 CIDR address." 9 58
    done
    while true; do
      gateway=$(whiptail --backtitle "$BACKTITLE" --title "IPv4 GATEWAY" \
        --ok-button "Next" --cancel-button "Exit Script" \
        --inputbox "\nEnter the gateway for ${static_ip}." 10 62 "" \
        3>&1 1>&2 2>&3) || exit 0
      gateway_in_subnet "$static_ip" "$gateway" && break
      whiptail --backtitle "$BACKTITLE" --title "INVALID GATEWAY" --msgbox "Gateway must be a valid IPv4 address in the same subnet." 9 66
    done
    NET="$static_ip"
    GATE="$gateway"
  else
    NET="dhcp"
    GATE=""
  fi
  while true; do
    vlan=$(whiptail --backtitle "$BACKTITLE" --title "VLAN" \
      --ok-button "Review" --cancel-button "Exit Script" \
      --inputbox "\nOptional VLAN tag (1-4094). Leave blank for untagged." 10 64 "" \
      3>&1 1>&2 2>&3) || exit 0
    valid_vlan "$vlan" && break
    whiptail --backtitle "$BACKTITLE" --title "INVALID VLAN" --msgbox "VLAN must be blank or 1-4094." 9 58
  done
  VLAN="$vlan"
}

prompt_advanced_resources() {
  local value
  while true; do
    value=$(whiptail --backtitle "$BACKTITLE" --title "CPU CORES" --inputbox "\nCPU cores" 9 54 "$CPU" 3>&1 1>&2 2>&3) || exit 0
    [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 128 )) && { CPU="$value"; break; }
  done
  while true; do
    value=$(whiptail --backtitle "$BACKTITLE" --title "RAM" --inputbox "\nRAM in MiB" 9 54 "$RAM" 3>&1 1>&2 2>&3) || exit 0
    [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 512 )) && { RAM="$value"; break; }
  done
  while true; do
    value=$(whiptail --backtitle "$BACKTITLE" --title "DISK" --inputbox "\nRoot disk size in GiB" 9 54 "$DISK" 3>&1 1>&2 2>&3) || exit 0
    [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 8 )) && { DISK="$value"; break; }
  done
}

confirm_configuration() {
  local configuration
  configuration=$(cat <<EOF_CONFIGURATION
Install method: ${method^}
Container ID: ${CTID}
Hostname: ${HN}
Container type: Unprivileged Debian 13
Storage: ${ROOT_STORAGE}
Disk: ${DISK} GiB
CPU: ${CPU} cores
RAM: ${RAM} MiB
Bridge: ${BRG}
IPv4: ${NET}
Gateway: ${GATE:-DHCP/none}
VLAN: ${VLAN:-none}

Create this container and begin the native installation?
EOF_CONFIGURATION
)
  whiptail --backtitle "$BACKTITLE" --title "REVIEW CONFIGURATION" \
    --yes-button "Install" --no-button "Change / Cancel" \
    --yesno "$configuration" 21 78
}

find_or_download_template() {
  local available="${1:-}" existing existing_name newest_name
  [[ -n "$available" ]] || fatal "No Debian 13 AMD64 standard template was selected from the Proxmox appliance catalog"

  existing=$(pveam list "$TEMPLATE_STORAGE" 2>/dev/null \
    | awk '$1 ~ /debian-13-standard_.*_amd64\.tar\.zst$/ {print $1}' \
    | sort -V | tail -n1)

  if [[ -n "$existing" ]]; then
    existing_name="${existing##*/}"
    newest_name=$(printf '%s\n%s\n' "$existing_name" "$available" | sort -V | tail -n1)

    if [[ "$existing_name" == "$available" ]]; then
      info "Using cached Debian template ${existing_name}" >&2
      printf '%s' "$existing"
      return 0
    fi

    # A locally cached template can occasionally be newer than the refreshed
    # catalog (for example after a catalog rollback). Never replace it with an
    # older catalog entry.
    if [[ "$newest_name" == "$existing_name" ]]; then
      warn "Cached Debian template ${existing_name} is newer than catalog entry ${available}; using cached template"
      printf '%s' "$existing"
      return 0
    fi

    info "Newer Debian template available (${existing_name} -> ${available})" >&2
  else
    info "No cached Debian 13 AMD64 template found on ${TEMPLATE_STORAGE}" >&2
  fi

  info "Downloading ${available} to ${TEMPLATE_STORAGE}" >&2
  pveam download "$TEMPLATE_STORAGE" "$available" >&2 \
    || fatal "Failed to download Debian template ${available} to ${TEMPLATE_STORAGE}"
  printf '%s:vztmpl/%s' "$TEMPLATE_STORAGE" "$available"
}

set_project_description() {
  local project_description
  project_description=$(cat <<EOF_DESCRIPTION
<div align='center'>
  <a href='${UPSTREAM_PROJECT_URL}' target='_blank' rel='noopener noreferrer'>
    <img src='${NPM_LOGO_URL}' alt='Nginx Proxy Manager logo' style='width:440px;max-width:85%;height:auto;' />
  </a>
  <h2 style='font-size:24px;margin:16px 0 8px;'>Nginx Proxy Manager LXC</h2>
  <p style='margin:8px 0;line-height:1.5;'>Nginx Proxy Manager is officially distributed as a Docker application. This container is an <strong>unofficial native Proxmox LXC adaptation</strong> and does not run a nested container runtime.</p>
  <p style='margin:8px 0 4px;'>Adapted and maintained for Proxmox by</p>
  <a href='${IMMACULARIT_PROFILE_URL}' target='_blank' rel='noopener noreferrer'>
    <img src='${IMMACULARIT_LOGO_URL}' alt='ImmacularIT logo' style='width:210px;max-width:60%;height:auto;' />
  </a>
  <p style='margin:12px 0;'>
    <a href='${UPSTREAM_PROJECT_URL}' target='_blank' rel='noopener noreferrer'>Official upstream</a>
    &nbsp;|&nbsp;
    <a href='${PROJECT_URL}' target='_blank' rel='noopener noreferrer'>ImmacularIT adaptation</a>
    &nbsp;|&nbsp;
    <a href='${PROJECT_URL}/issues' target='_blank' rel='noopener noreferrer'>Issues</a>
  </p>
</div>
EOF_DESCRIPTION
)
  pct set "$CTID" --description "$project_description" >/dev/null
}

handle_install_failure() {
  local rc="$1" choice="keep"
  printf '\n  ✖️  Installation failed in container %s (exit code %s)\n' "$CTID" "$rc" >&2
  [[ -n "$INSTALL_LOG" ]] && printf '  📋 Host-side installation log: %s\n' "$INSTALL_LOG" >&2
  if [[ -t 0 ]]; then
    choice=$(whiptail --backtitle "$BACKTITLE" --title "INSTALLATION FAILED" \
      --menu "\nKeep the container for debugging or destroy it?" 14 72 2 \
      "keep" "Keep container ${CTID} for debugging" \
      "destroy" "Stop and permanently destroy container ${CTID}" \
      --default-item "keep" 3>&1 1>&2 2>&3) || choice="keep"
  fi
  if [[ "$choice" == "destroy" ]]; then
    pct stop "$CTID" >/dev/null 2>&1 || true
    pct destroy "$CTID" --purge 1
    ok "Container ${CTID} removed"
  else
    warn "Container ${CTID} kept for debugging"
  fi
  exit "$rc"
}

show_welcome

method=$(whiptail --backtitle "$BACKTITLE" --title "INSTALL METHOD" \
  --menu "\nChoose how to configure the Debian 13 unprivileged LXC:" 15 76 2 \
  "default" "Recommended defaults with identity/network prompts" \
  "advanced" "Also customize CPU, RAM and disk" \
  --default-item "default" 3>&1 1>&2 2>&3) || exit 0

prompt_identity
ROOT_STORAGE="$(select_storage)"
prompt_network
[[ "$method" == "advanced" ]] && prompt_advanced_resources
confirm_configuration || exit 0

clear || true
printf '  ⚙️  Using %s Install on node %s\n' "${method^}" "$(hostname)"
printf '  💡  PVE Version: %s (Kernel: %s)\n' "$PVE_VERSION" "$(uname -r)"
printf '  🆔  Container ID: %s\n' "$CTID"
printf '  🏠  Hostname: %s\n' "$HN"
printf '  📦  Container Type: Unprivileged\n'
printf '  💾  Disk Size: %s GB on %s\n' "$DISK" "$ROOT_STORAGE"
printf '  🧠  CPU Cores: %s\n' "$CPU"
printf '  🛠️  RAM Size: %s MiB\n' "$RAM"
printf '  🌉  Bridge: %s\n' "$BRG"
printf '  📡  IPv4: %s\n' "$NET"
printf '  🌐  Gateway: %s\n' "${GATE:-DHCP/none}"
printf '  🏷️  VLAN: %s\n' "${VLAN:-none}"

# Always refresh the official appliance catalog before choosing a template so
# a new CT does not silently start from an older cached Debian image.
info "Refreshing the official Proxmox appliance catalog"
pveam update || fatal "Failed to refresh the official Proxmox appliance catalog"
LATEST_TEMPLATE=$(pveam available --section system 2>/dev/null \
  | awk '$2 ~ /^debian-13-standard_.*_amd64\.tar\.zst$/ {print $2}' \
  | sort -V | tail -n1)
[[ -n "$LATEST_TEMPLATE" ]] \
  || fatal "No Debian 13 AMD64 standard template is available from the Proxmox appliance catalog"

# Template cache placement is an implementation detail, not a normal user
# choice. Prefer a storage already holding the latest template, otherwise keep
# existing Debian template caches consolidated before falling back to `local`.
TEMPLATE_STORAGE="$(resolve_template_storage "$LATEST_TEMPLATE")"
TEMPLATE="$(find_or_download_template "$LATEST_TEMPLATE")"
ok "Debian template ready: ${TEMPLATE##*/}"

net0="name=eth0,bridge=${BRG},ip=${NET},ip6=auto,type=veth"
[[ -n "$GATE" ]] && net0+=",gw=${GATE}"
[[ -n "$VLAN" ]] && net0+=",tag=${VLAN}"

create_args=(
  "$CTID" "$TEMPLATE"
  --hostname "$HN"
  --cores "$CPU"
  --memory "$RAM"
  --swap 512
  --rootfs "${ROOT_STORAGE}:${DISK}"
  --unprivileged 1
  --ostype debian
  --net0 "$net0"
  --onboot "$ONBOOT"
  --tags "$DEFAULT_TAGS"
  --start 0
)

info "Creating Debian 13 unprivileged LXC ${CTID}"
pct create "${create_args[@]}"
ok "LXC Container ${CTID} was successfully created"
set_project_description

info "Starting LXC Container ${CTID}"
pct start "$CTID"
for _ in {1..60}; do
  if pct exec "$CTID" -- true >/dev/null 2>&1; then break; fi
  sleep 1
done
pct exec "$CTID" -- true >/dev/null 2>&1 || handle_install_failure 117
ok "Started LXC Container"

IP=""
for _ in {1..60}; do
  IP="$(pct exec "$CTID" -- sh -c "hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$' | head -n1" 2>/dev/null || true)"
  [[ -n "$IP" ]] && break
  sleep 1
done
[[ -n "$IP" ]] || handle_install_failure 118
ok "Network Connected: ${IP}"

installer_tmp="$(mktemp)"
cleanup_temp+=("$installer_tmp")
info "Downloading the ImmacularIT native installer"
curl -fsSL --retry 3 --retry-delay 2 "$PROJECT_INSTALL_URL" -o "$installer_tmp"
[[ -s "$installer_tmp" ]] || fatal "Downloaded an empty installer"
pct push "$CTID" "$installer_tmp" /root/nginx-proxy-manager-install.sh --perms 0755
ok "Prepared project installer"

INSTALL_LOG="/tmp/nginx-proxy-manager-${CTID}-$(date +%Y%m%d-%H%M%S).log"
printf '\n  🚀 Installing Nginx Proxy Manager natively in container %s:\n' "$CTID"
set +e
pct exec "$CTID" -- env NPM_PROJECT_REF="$PROJECT_REF" bash /root/nginx-proxy-manager-install.sh 2>&1 | tee "$INSTALL_LOG"
rc=${PIPESTATUS[0]}
set -e
[[ "$rc" -eq 0 ]] || handle_install_failure "$rc"

# The container IPv4 was already resolved and validated before installation.
# Reuse it for the completion message rather than reparsing shell output here.
ok "Completed successfully"
printf '\n  🌐 Administration interface: http://%s:81\n' "$IP"
printf '  ℹ️  Complete the official first-run setup wizard; no default credentials are created.\n'
printf '  🔒 No installation telemetry or usage data is sent by this project launcher.\n'

if [[ -t 0 ]]; then
  whiptail --backtitle "$BACKTITLE" --title "INSTALLATION COMPLETE" \
    --ok-button "Finish" \
    --msgbox "\nNginx Proxy Manager was installed natively in LXC ${CTID}.\n\nAdministration interface:\nhttp://${IP}:81\n\nComplete the official first-run setup wizard. No default administrator credentials were created." \
    16 76
fi
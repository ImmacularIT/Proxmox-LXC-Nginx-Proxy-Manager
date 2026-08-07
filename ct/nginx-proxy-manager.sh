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

DEFAULT_DISK=16
DEFAULT_CPU=2
DEFAULT_RAM=4096
DEFAULT_HOSTNAME="nginx-proxy-manager"
DEFAULT_BRIDGE="vmbr0"
DEFAULT_TAGS="nginx-proxy-manager;reverse-proxy;immacularit;webserver"

CTID=""
HN=""
ROOT_STORAGE=""
TEMPLATE_STORAGE=""
BRG="$DEFAULT_BRIDGE"
NET="dhcp"
GATE=""
VLAN=""
CPU="$DEFAULT_CPU"
RAM="$DEFAULT_RAM"
DISK="$DEFAULT_DISK"
ONBOOT=1
NESTING=0
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
  local ip="$1" a b c d
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
  local content="$1" title="$2" selected default_storage
  local -a stores=() menu=()
  mapfile -t stores < <(pvesm status --content "$content" 2>/dev/null | awk 'NR > 1 && $3 == "active" {print $1}')
  [[ ${#stores[@]} -gt 0 ]] || fatal "No active Proxmox storage supports content type ${content}"
  default_storage="${stores[0]}"
  for selected in "${stores[@]}"; do
    menu+=("$selected" "Active ${content} storage")
  done
  selected=$(whiptail --backtitle "ImmacularIT - ${APP}" --title "$title" \
    --ok-button "Select" --cancel-button "Exit" \
    --menu "\nSelect storage:" 18 72 10 "${menu[@]}" \
    --default-item "$default_storage" 3>&1 1>&2 2>&3) || exit 0
  printf '%s' "$selected"
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
    menu+=("$bridge" "Available bridge")
  done
  selected=$(whiptail --backtitle "ImmacularIT - ${APP}" --title "NETWORK BRIDGE" \
    --ok-button "Select" --cancel-button "Exit" \
    --menu "\nSelect the bridge for this container:" 18 72 10 "${menu[@]}" \
    --default-item "$DEFAULT_BRIDGE" 3>&1 1>&2 2>&3) || exit 0
  printf '%s' "$selected"
}

prompt_identity() {
  local suggested id name
  suggested="$(pvesh get /cluster/nextid 2>/dev/null)"
  while true; do
    id=$(whiptail --backtitle "ImmacularIT - ${APP}" --title "CONTAINER ID" \
      --inputbox "\nEnter an unused Proxmox container ID." 10 62 "$suggested" \
      3>&1 1>&2 2>&3) || exit 0
    if valid_container_id "$id"; then CTID="$id"; break; fi
    whiptail --title "INVALID CONTAINER ID" --msgbox "Container ID must be numeric and unused across the cluster." 9 62
  done
  while true; do
    name=$(whiptail --backtitle "ImmacularIT - ${APP}" --title "CONTAINER HOSTNAME" \
      --inputbox "\nEnter the container hostname." 10 62 "$DEFAULT_HOSTNAME" \
      3>&1 1>&2 2>&3) || exit 0
    name="${name,,}"
    name="${name// /}"
    if valid_hostname "$name"; then HN="$name"; break; fi
    whiptail --title "INVALID HOSTNAME" --msgbox "Use lowercase letters, numbers, dots and hyphens only." 9 62
  done
}

prompt_network() {
  local method static_ip gateway vlan
  BRG="$(select_bridge)"
  method=$(whiptail --backtitle "ImmacularIT - ${APP}" --title "IPv4" \
    --menu "\nChoose IPv4 configuration:" 14 68 2 \
    "dhcp" "Automatic address from DHCP" \
    "static" "Static IPv4 address" \
    --default-item "dhcp" 3>&1 1>&2 2>&3) || exit 0
  if [[ "$method" == "static" ]]; then
    while true; do
      static_ip=$(whiptail --backtitle "ImmacularIT - ${APP}" --title "STATIC IPv4" \
        --inputbox "\nEnter IPv4 address in CIDR form, e.g. 192.168.1.50/24" 11 68 "" \
        3>&1 1>&2 2>&3) || exit 0
      valid_cidr "$static_ip" && break
      whiptail --title "INVALID IPv4" --msgbox "Enter a valid IPv4 CIDR address." 9 58
    done
    while true; do
      gateway=$(whiptail --backtitle "ImmacularIT - ${APP}" --title "IPv4 GATEWAY" \
        --inputbox "\nEnter the gateway for ${static_ip}." 10 62 "" \
        3>&1 1>&2 2>&3) || exit 0
      gateway_in_subnet "$static_ip" "$gateway" && break
      whiptail --title "INVALID GATEWAY" --msgbox "Gateway must be a valid IPv4 address in the same subnet." 9 66
    done
    NET="$static_ip"
    GATE="$gateway"
  else
    NET="dhcp"
    GATE=""
  fi
  while true; do
    vlan=$(whiptail --backtitle "ImmacularIT - ${APP}" --title "VLAN" \
      --inputbox "\nOptional VLAN tag (1-4094). Leave blank for untagged." 10 64 "" \
      3>&1 1>&2 2>&3) || exit 0
    valid_vlan "$vlan" && break
    whiptail --title "INVALID VLAN" --msgbox "VLAN must be blank or 1-4094." 9 58
  done
  VLAN="$vlan"
}

prompt_advanced_resources() {
  local value
  while true; do
    value=$(whiptail --backtitle "ImmacularIT - ${APP}" --title "CPU CORES" --inputbox "\nCPU cores" 9 54 "$CPU" 3>&1 1>&2 2>&3) || exit 0
    [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 128 )) && { CPU="$value"; break; }
  done
  while true; do
    value=$(whiptail --backtitle "ImmacularIT - ${APP}" --title "RAM" --inputbox "\nRAM in MiB" 9 54 "$RAM" 3>&1 1>&2 2>&3) || exit 0
    [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 512 )) && { RAM="$value"; break; }
  done
  while true; do
    value=$(whiptail --backtitle "ImmacularIT - ${APP}" --title "DISK" --inputbox "\nRoot disk size in GiB" 9 54 "$DISK" 3>&1 1>&2 2>&3) || exit 0
    [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 8 )) && { DISK="$value"; break; }
  done
  if whiptail --backtitle "ImmacularIT - ${APP}" --title "NESTING" \
    --yesno "\nEnable LXC nesting/keyctl?\n\nNginx Proxy Manager does not require this. Leave disabled unless you have a separate reason." 13 72; then
    NESTING=1
  else
    NESTING=0
  fi
}

find_or_download_template() {
  local existing available
  existing=$(pveam list "$TEMPLATE_STORAGE" 2>/dev/null \
    | awk '$1 ~ /debian-13-standard_.*_amd64\.tar\.zst$/ {print $1}' \
    | sort -V | tail -n1)
  if [[ -n "$existing" ]]; then
    printf '%s' "$existing"
    return 0
  fi
  info "Refreshing the official Proxmox appliance catalog"
  pveam update
  available=$(pveam available --section system 2>/dev/null \
    | awk '$2 ~ /^debian-13-standard_.*_amd64\.tar\.zst$/ {print $2}' \
    | sort -V | tail -n1)
  [[ -n "$available" ]] || fatal "No Debian 13 AMD64 standard template is available from the Proxmox appliance catalog"
  info "Downloading ${available} to ${TEMPLATE_STORAGE}"
  pveam download "$TEMPLATE_STORAGE" "$available"
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
    choice=$(whiptail --backtitle "ImmacularIT - ${APP}" --title "INSTALLATION FAILED" \
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

method=$(whiptail --backtitle "ImmacularIT - ${APP}" --title "INSTALL METHOD" \
  --menu "\nChoose how to configure the Debian 13 unprivileged LXC:" 15 76 2 \
  "default" "Recommended defaults with identity/network prompts" \
  "advanced" "Also customize CPU, RAM, disk and nesting" \
  --default-item "default" 3>&1 1>&2 2>&3) || exit 0

prompt_identity
ROOT_STORAGE="$(select_storage rootdir "CONTAINER STORAGE")"
TEMPLATE_STORAGE="$(select_storage vztmpl "TEMPLATE STORAGE")"
prompt_network
[[ "$method" == "advanced" ]] && prompt_advanced_resources

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
printf '  📦  Nesting/keyctl: %s\n' "$([[ "$NESTING" -eq 1 ]] && echo enabled || echo disabled)"

TEMPLATE="$(find_or_download_template)"
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
[[ "$NESTING" -eq 1 ]] && create_args+=(--features "nesting=1,keyctl=1")

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

IP="$(pct exec "$CTID" -- sh -c "hostname -I | awk '{print \\$1}'" 2>/dev/null || printf '%s' "$IP")"
ok "Completed successfully"
printf '\n  🌐 Administration interface: http://%s:81\n' "$IP"
printf '  ℹ️  Complete the official first-run setup wizard; no default credentials are created.\n'
printf '  🔒 No installation telemetry or usage data is sent by this project launcher.\n'

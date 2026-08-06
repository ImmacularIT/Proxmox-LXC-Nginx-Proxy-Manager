#!/usr/bin/env bash
# Copyright (c) 2026 ImmacularIT
# License: MIT
# Upstream application: https://github.com/NginxProxyManager/nginx-proxy-manager
set -Eeuo pipefail

readonly PVE_BUILD_COMMIT="5ddc4a2a41991324a534dd02b81fe3bc5a3bca04"
readonly BUILD_FUNC_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/${PVE_BUILD_COMMIT}/misc/build.func"
readonly MAIN_MARKER='_FUNC_BASE="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc"'
readonly PINNED_MARKER="_FUNC_BASE=\"https://raw.githubusercontent.com/community-scripts/ProxmoxVE/${PVE_BUILD_COMMIT}/misc\""

build_func="$(curl -fsSL --retry 3 --retry-delay 2 "$BUILD_FUNC_URL")" || {
  echo "Failed to download pinned Community Scripts builder" >&2
  exit 1
}
[[ "$(grep -Fc "$MAIN_MARKER" <<<"$build_func")" -eq 1 ]] || {
  echo "Pinned build.func bootstrap marker changed; refusing an unchecked patch" >&2
  exit 1
}
build_func="${build_func/$MAIN_MARKER/$PINNED_MARKER}"
source /dev/stdin <<<"$build_func"
unset build_func

APP="Nginx-Proxy-Manager"
var_tags="${var_tags:-nginx-proxy-manager;reverse-proxy;immacularit;webserver}"
var_disk="${var_disk:-16}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

PROJECT_OWNER="ImmacularIT"
PROJECT_REPO="Proxmox-LXC-Nginx-Proxy-Manager"
PROJECT_REF="${NPM_PROJECT_REF:-develop/native-lxc-v2.15.1}"
UPSTREAM_PROJECT_URL="https://github.com/NginxProxyManager/nginx-proxy-manager"
IMMACULARIT_PROFILE_URL="https://github.com/ImmacularIT"
PROJECT_URL="https://github.com/${PROJECT_OWNER}/${PROJECT_REPO}"
IMMACULARIT_LOGO_URL="https://raw.githubusercontent.com/ImmacularIT/Proxmox-Itiligent-Guacamole/15c268e6fd0e6f9b441aa9f785c278c3f580171b/assets/immacularit-logo.png"
NPM_LOGO_URL="https://nginxproxymanager.com/github.png"

header_info "$APP"
variables
# Preserve the project filename expected by this independent repository.
var_install="nginx-proxy-manager-install"
NSAPP="nginx-proxy-manager"
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -x /usr/local/sbin/npm-lxc-update ]]; then
    msg_error "No native Nginx Proxy Manager installation found"
    exit 1
  fi
  msg_warn "Updates require a reviewed ImmacularIT version manifest; no automatic latest update is performed."
  echo "Run inside the container:"
  echo "  npm-lxc-update --version-file /root/validated-versions.sh"
  exit 0
}

configure_default_identity() {
  [[ "${METHOD:-}" == "default" ]] || return 0
  if [[ "${PHS_SILENT:-0}" == "1" || ! -t 0 || "${TERM:-dumb}" == "dumb" ]]; then
    return 0
  fi
  local requested_id requested_hostname
  while true; do
    requested_id=$(whiptail \
      --backtitle "ImmacularIT - ${APP}" \
      --title "DEFAULT INSTALL: CONTAINER ID" \
      --ok-button "Next" --cancel-button "Exit Script" \
      --inputbox "\nContainer ID [${CT_ID:-$NEXTID}]\n\nPress Enter to use the suggested ID." 12 62 \
      "${CT_ID:-$NEXTID}" 3>&1 1>&2 2>&3) || exit_script
    requested_id="${requested_id:-${CT_ID:-$NEXTID}}"
    if [[ "$requested_id" =~ ^[0-9]+$ ]] && validate_container_id "$requested_id"; then break; fi
    whiptail --title "INVALID CONTAINER ID" \
      --msgbox "Container ID must be numeric and unused across the Proxmox cluster." 9 62
  done
  while true; do
    requested_hostname=$(whiptail \
      --backtitle "ImmacularIT - ${APP}" \
      --title "DEFAULT INSTALL: CONTAINER HOSTNAME" \
      --ok-button "Next" --cancel-button "Exit Script" \
      --inputbox "\nContainer hostname [${HN:-nginx-proxy-manager}]\n\nPress Enter to use the suggested hostname." 12 68 \
      "${HN:-nginx-proxy-manager}" 3>&1 1>&2 2>&3) || exit_script
    requested_hostname="${requested_hostname:-${HN:-nginx-proxy-manager}}"
    requested_hostname=$(echo "${requested_hostname,,}" | tr -d ' ')
    if validate_hostname "$requested_hostname"; then break; fi
    whiptail --title "INVALID HOSTNAME" \
      --msgbox "Use lowercase letters, numbers, dots and hyphens only. Labels cannot start or end with a hyphen." 10 68
  done
  CT_ID="$requested_id"
  CTID="$requested_id"
  HN="$requested_hostname"
  export CT_ID CTID HN
}

configure_default_network() {
  [[ "${METHOD:-}" == "default" ]] || return 0
  if [[ "${PHS_SILENT:-0}" == "1" || ! -t 0 || "${TERM:-dumb}" == "dumb" ]]; then
    return 0
  fi
  local bridge_path bridge selected_bridge ip_method static_ip gateway vlan
  local current_gateway="${GATE:-}"
  local -a bridges=() bridge_menu=()
  case "$current_gateway" in ,gw=*) current_gateway="${current_gateway#,gw=}" ;; esac
  for bridge_path in /sys/class/net/*/bridge; do
    [[ -d "$bridge_path" ]] || continue
    bridge="${bridge_path%/bridge}"
    bridge="${bridge##*/}"
    validate_bridge "$bridge" && bridges+=("$bridge")
  done
  local bridge_found=0
  for bridge in "${bridges[@]}"; do [[ "$bridge" == "${BRG:-vmbr0}" ]] && bridge_found=1; done
  if [[ "$bridge_found" -eq 0 ]] && validate_bridge "${BRG:-vmbr0}"; then
    bridges=("${BRG:-vmbr0}" "${bridges[@]}")
  fi
  [[ ${#bridges[@]} -gt 0 ]] || { msg_error "No active Proxmox network bridge was found"; exit 116; }
  for bridge in "${bridges[@]}"; do
    if [[ "$bridge" == "${BRG:-vmbr0}" ]]; then
      bridge_menu+=("$bridge" "Current default")
    else
      bridge_menu+=("$bridge" "Available bridge")
    fi
  done
  while true; do
    selected_bridge=$(whiptail --backtitle "ImmacularIT - ${APP}" \
      --title "DEFAULT INSTALL: NETWORK BRIDGE" --ok-button "Next" --cancel-button "Exit Script" \
      --menu "\nSelect the Proxmox bridge for this container:" 16 64 7 \
      "${bridge_menu[@]}" --default-item "${BRG:-vmbr0}" 3>&1 1>&2 2>&3) || exit_script
    ip_method="dhcp"
    [[ "${NET:-dhcp}" != "dhcp" ]] && ip_method="static"
    ip_method=$(whiptail --backtitle "ImmacularIT - ${APP}" \
      --title "DEFAULT INSTALL: IPv4" --ok-button "Next" --cancel-button "Exit Script" \
      --menu "\nChoose how the container receives its IPv4 address:" 15 68 2 \
      "dhcp" "Automatic address from DHCP (recommended)" \
      "static" "Static address entered manually" \
      --default-item "$ip_method" 3>&1 1>&2 2>&3) || exit_script
    if [[ "$ip_method" == "static" ]]; then
      while true; do
        static_ip=$(whiptail --backtitle "ImmacularIT - ${APP}" \
          --title "DEFAULT INSTALL: STATIC IPv4" --ok-button "Next" --cancel-button "Exit Script" \
          --inputbox "\nEnter the IPv4 address in CIDR format.\nExample: 192.168.2.50/24" 12 62 \
          "$([[ "${NET:-dhcp}" != "dhcp" ]] && printf '%s' "$NET")" 3>&1 1>&2 2>&3) || exit_script
        validate_ip_address "$static_ip" && break
        whiptail --title "INVALID STATIC ADDRESS" --msgbox "Enter a valid IPv4 CIDR address." 9 58
      done
      while true; do
        gateway=$(whiptail --backtitle "ImmacularIT - ${APP}" \
          --title "DEFAULT INSTALL: GATEWAY" --ok-button "Next" --cancel-button "Exit Script" \
          --inputbox "\nEnter the IPv4 gateway." 11 62 "$current_gateway" 3>&1 1>&2 2>&3) || exit_script
        if validate_gateway_ip "$gateway" && validate_gateway_in_subnet "$static_ip" "$gateway"; then break; fi
        whiptail --title "INVALID GATEWAY" \
          --msgbox "The gateway must be a valid IPv4 address in the same subnet as ${static_ip}." 10 66
      done
    else
      static_ip="dhcp"
      gateway=""
    fi
    while true; do
      vlan=$(whiptail --backtitle "ImmacularIT - ${APP}" \
        --title "DEFAULT INSTALL: VLAN" --ok-button "Review" --cancel-button "Exit Script" \
        --inputbox "\nEnter a VLAN tag from 1 to 4094.\nLeave blank for an untagged interface." 12 62 \
        "${VLAN:-}" 3>&1 1>&2 2>&3) || exit_script
      validate_vlan_tag "$vlan" && break
      whiptail --title "INVALID VLAN" --msgbox "VLAN must be blank or a number between 1 and 4094." 9 58
    done
    if whiptail --backtitle "ImmacularIT - ${APP}" --title "CONFIRM NETWORK SETTINGS" \
      --yes-button "Use Settings" --no-button "Change" \
      --yesno "\nBridge: ${selected_bridge}\nIPv4: ${static_ip}\nGateway: ${gateway:-None}\nVLAN: ${vlan:-None}\n\nUse these network settings?" 15 64; then
      BRG="$selected_bridge"
      SDN_VNET=""
      NET="$static_ip"
      GATE="$gateway"
      VLAN="$vlan"
      export BRG SDN_VNET NET GATE VLAN
      break
    fi
  done
}

configure_project_tags() {
  local raw_tags="${TAGS:-${var_tags:-}}" tag cleaned=""
  local -a existing_tags=() requested_tags=("nginx-proxy-manager" "reverse-proxy" "immacularit" "webserver")
  IFS=';' read -r -a existing_tags <<<"$raw_tags"
  for tag in "${existing_tags[@]}" "${requested_tags[@]}"; do
    tag="${tag//[[:space:]]/}"
    [[ -z "$tag" || "$tag" == "community-script" ]] && continue
    case ";${cleaned};" in *";${tag};"*) ;; *) cleaned="${cleaned:+${cleaned};}${tag}" ;; esac
  done
  TAGS="$cleaned"
  export TAGS
}

set_project_description() {
  local project_description
  project_description=$(cat <<EOF_DESCRIPTION
<div align='center'>
  <a href='${UPSTREAM_PROJECT_URL}' target='_blank' rel='noopener noreferrer'>
    <img src='${NPM_LOGO_URL}' alt='Nginx Proxy Manager logo' style='width:440px;max-width:85%;height:auto;' />
  </a>
  <h2 style='font-size:24px;margin:16px 0 8px;'>Nginx Proxy Manager LXC</h2>
  <p style='margin:8px 0;line-height:1.5;'>Nginx Proxy Manager is officially distributed as a Docker application. This container is an <strong>unofficial native Proxmox LXC adaptation</strong> of that upstream application and does not run a nested Docker runtime.</p>
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
  pct set "$CTID" -description "$project_description"
}

_PROJECT_INSTALL_URL="https://raw.githubusercontent.com/${PROJECT_OWNER}/${PROJECT_REPO}/${PROJECT_REF}/install/nginx-proxy-manager-install.sh"
_COMMUNITY_INSTALL_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/${var_install}.sh"

start
configure_default_identity
configure_default_network
configure_project_tags
export NPM_PROJECT_REF="$PROJECT_REF"

curl() {
  local arg project_fetch=0 content
  local token="${GITHUB_TOKEN:-${var_github_token:-}}"
  local -a rewritten=()
  for arg in "$@"; do
    if [[ "$arg" == "$_COMMUNITY_INSTALL_URL" ]]; then
      rewritten+=("$_PROJECT_INSTALL_URL")
      project_fetch=1
    else
      rewritten+=("$arg")
    fi
  done
  if [[ "$project_fetch" -eq 1 ]]; then
    if [[ -n "$token" ]]; then
      content=$(command curl -H "Authorization: Bearer ${token}" "${rewritten[@]}") || return
    else
      content=$(command curl "${rewritten[@]}") || return
    fi
    printf 'export NPM_PROJECT_REF=%q\n%s' "$PROJECT_REF" "$content"
  else
    command curl "${rewritten[@]}"
  fi
}

build_container
unset -f curl
description
set_project_description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}Nginx Proxy Manager setup has completed.${CL}"
echo -e "${INFO}${YW}Administration interface:${CL} ${BGN}http://${IP}:81${CL}"
echo -e "${INFO}${YW}Complete the official first-run setup wizard; no default credentials are created.${CL}"

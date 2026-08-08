#!/usr/bin/env bash
set -Eeuo pipefail

launcher="ct/nginx-proxy-manager.sh"
installer="install/nginx-proxy-manager-install.sh"
readme="README.md"

for file in "$launcher" "$installer"; do
  grep -Fq 'PROJECT_REF="${NPM_PROJECT_REF:-main}"' "$file"
  ! grep -Fq 'PROJECT_REF="${NPM_PROJECT_REF:-develop/' "$file"
done

grep -Fq 'https://raw.githubusercontent.com/ImmacularIT/Proxmox-LXC-Nginx-Proxy-Manager/main/ct/nginx-proxy-manager.sh' "$readme"
! grep -Fq '/develop/native-lxc-v2.15.1/ct/nginx-proxy-manager.sh' "$readme"

printf '%s\n' "Production main self-fetch invariants validated."

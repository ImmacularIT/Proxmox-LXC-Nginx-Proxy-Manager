#!/usr/bin/env bash
set -Eeuo pipefail

launcher="ct/nginx-proxy-manager.sh"
readme="README.md"

grep -Fq 'PROJECT_REF="${NPM_PROJECT_REF:-main}"' "$launcher"
! grep -Fq 'PROJECT_REF="${NPM_PROJECT_REF:-develop/' "$launcher"
grep -Fq 'https://raw.githubusercontent.com/ImmacularIT/Proxmox-LXC-Nginx-Proxy-Manager/main/ct/nginx-proxy-manager.sh' "$readme"
! grep -Fq '/develop/native-lxc-v2.15.1/ct/nginx-proxy-manager.sh' "$readme"

printf '%s\n' "Production main self-fetch invariants validated."

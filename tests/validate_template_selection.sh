#!/usr/bin/env bash
set -Eeuo pipefail

launcher="ct/nginx-proxy-manager.sh"

# Every approved install must refresh the Proxmox appliance catalog before
# selecting the Debian 13 template. Cached templates are an optimization, not a
# reason to skip checking what Proxmox currently publishes.
grep -Fq 'pveam update || fatal "Failed to refresh the official Proxmox appliance catalog"' "$launcher"
grep -Fq 'LATEST_TEMPLATE=$(pveam available --section system 2>/dev/null \' "$launcher"
grep -Fq 'TEMPLATE_STORAGE="$(resolve_template_storage "$LATEST_TEMPLATE")"' "$launcher"
grep -Fq 'TEMPLATE="$(find_or_download_template "$LATEST_TEMPLATE")"' "$launcher"

# The selected storage should prefer a cache that already contains the exact
# latest catalog template, then an existing Debian 13 cache, then `local`.
grep -Fq 'local latest_template="${1:-}" requested="${TEMPLATE_STORAGE:-}" storage' "$launcher"
grep -Fq 'wanted="vztmpl/${latest_template}"' "$launcher"
grep -Fq 'debian-13-standard_.*_amd64\.tar\.zst' "$launcher"

# If the newest cached template differs from the refreshed catalog version, the
# version-aware comparison decides whether to reuse the cache or download the
# newer catalog template. Download/progress output must stay off stdout because
# find_or_download_template runs inside command substitution.
grep -Fq 'newest_name=$(printf '\''%s\n%s\n'\'' "$existing_name" "$available" | sort -V | tail -n1)' "$launcher"
grep -Fq 'if [[ "$newest_name" == "$existing_name" ]]; then' "$launcher"
grep -Fq 'info "Newer Debian template available (${existing_name} -> ${available})" >&2' "$launcher"
grep -Fq 'pveam download "$TEMPLATE_STORAGE" "$available" >&2 \' "$launcher"
grep -Fq 'printf '\''%s:vztmpl/%s'\'' "$TEMPLATE_STORAGE" "$available"' "$launcher"

python3 - <<'PY'
from pathlib import Path

text = Path("ct/nginx-proxy-manager.sh").read_text()
refresh = text.index('pveam update || fatal "Failed to refresh the official Proxmox appliance catalog"')
available = text.index('LATEST_TEMPLATE=$(pveam available --section system')
resolve = text.index('TEMPLATE_STORAGE="$(resolve_template_storage "$LATEST_TEMPLATE")"')
select = text.index('TEMPLATE="$(find_or_download_template "$LATEST_TEMPLATE")"')
create = text.index('pct create "${create_args[@]}"')
assert refresh < available < resolve < select < create

old_short_circuit = '''if [[ -n "$existing" ]]; then
    printf '%s' "$existing"
    return 0
  fi
  info "Refreshing the official Proxmox appliance catalog"'''
assert old_short_circuit not in text, "Cached Debian template must not bypass the catalog freshness check"
PY

printf '%s\n' "Latest Debian template selection invariants validated."

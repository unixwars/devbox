#!/usr/bin/env bash
# Tests .devcontainer/install-sops-age.sh against the real pinned releases.
set -eu
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
installer="$here/../../.devcontainer/install-sops-age.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

bash "$installer" "$tmp/ok" >/dev/null
pinned=$(sed -n 's/^SOPS_VERSION=//p' "$installer")
"$tmp/ok/sops" --version 2>&1 | grep -q "$pinned" || { echo "sops version mismatch"; exit 1; }
"$tmp/ok/age" --version >/dev/null
"$tmp/ok/age-keygen" --version >/dev/null

if SOPS_SHA256_OVERRIDE=bad bash "$installer" "$tmp/bad" >/dev/null 2>&1; then
  echo "install succeeded despite bad checksum"; exit 1
fi
for b in sops age age-keygen; do
  [ ! -e "$tmp/bad/$b" ] || { echo "binary $b left after mismatch"; exit 1; }
done

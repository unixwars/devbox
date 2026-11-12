#!/usr/bin/env bash
# Install pinned sops and age (age, age-keygen) into <dest_dir>.
# Every download is sha256-verified before anything is installed; on mismatch
# nothing is written to <dest_dir>.
# Test seam: SOPS_SHA256_OVERRIDE replaces the expected sops checksum.
set -euo pipefail

SOPS_VERSION=3.13.3
AGE_VERSION=1.3.2
# sops: from sops-v3.13.3.checksums.txt in the official release.
SOPS_SHA256_amd64=e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b
SOPS_SHA256_arm64=53b0abacd38ef1b12a66d6c100956691b9cefce018d91f81e73ddf7438b94d77
# age: age publishes no checksum file; these are the release asset digests
# reported by the GitHub releases API (and confirmed against the downloaded files).
AGE_SHA256_amd64=cbe24006683f8eb669266162894b9a522a1af52f2665fbc63a4bb032ed26ac10
AGE_SHA256_arm64=6b8dc4333c53a5a57c9e5834e3a48f92605d7154014cd07269ff3327db5d37f4

dest=${1:?usage: install-sops-age.sh <dest_dir>}

case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
sops_var=SOPS_SHA256_$arch; age_var=AGE_SHA256_$arch
sops_sha=${SOPS_SHA256_OVERRIDE:-${!sops_var}}
age_sha=${!age_var}

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

curl -fsSL -o "$work/sops" \
  "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${arch}"
curl -fsSL -o "$work/age.tar.gz" \
  "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-${arch}.tar.gz"

echo "$sops_sha  $work/sops" | sha256sum -c --quiet - >&2 || { echo "sops checksum mismatch" >&2; exit 1; }
echo "$age_sha  $work/age.tar.gz" | sha256sum -c --quiet - >&2 || { echo "age checksum mismatch" >&2; exit 1; }

tar -xzf "$work/age.tar.gz" -C "$work"
mkdir -p "$dest"
install -m 0755 "$work/sops" "$dest/sops"
install -m 0755 "$work/age/age" "$dest/age"
install -m 0755 "$work/age/age-keygen" "$dest/age-keygen"

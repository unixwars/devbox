#!/usr/bin/env bash
# Optional extra "stripe": install the pinned Stripe CLI into <dest_dir> (default /usr/local/bin). The download is sha256-verified
# (digests from the GitHub releases API) before anything is installed.
set -euo pipefail

STRIPE_VERSION=1.55.12
STRIPE_SHA256_amd64=89d0bbec0970917a07fbd4d3a98afecf95b08f88f0687362c4a94447a0610245
STRIPE_SHA256_arm64=28ef728e916175ad93fc55d781d125964503763090e336af230c74159a72883a

dest=${1:-/usr/local/bin}
SUDO=""; [ -w "$dest" ] || [ "$(id -u)" = 0 ] || SUDO=sudo

if command -v stripe >/dev/null 2>&1 && stripe --version 2>/dev/null | grep -q "$STRIPE_VERSION"; then
  echo "stripe: already installed"; exit 0
fi

case "$(uname -m)" in
  x86_64|amd64) arch=amd64; asset=x86_64 ;;
  aarch64|arm64) arch=arm64; asset=arm64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
var=STRIPE_SHA256_$arch

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
file=stripe_${STRIPE_VERSION}_linux_${asset}.tar.gz
curl -fsSL -o "$work/$file" "https://github.com/stripe/stripe-cli/releases/download/v${STRIPE_VERSION}/$file"
echo "${!var}  $work/$file" | sha256sum -c - >/dev/null
tar -xzf "$work/$file" -C "$work" stripe
$SUDO install -m 755 "$work/stripe" "$dest/stripe"

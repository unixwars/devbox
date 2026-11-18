#!/usr/bin/env bash
# Install the pinned Stripe CLI into <dest_dir>. The download is sha256-verified
# (digests from the GitHub releases API) before anything is installed.
set -euo pipefail

STRIPE_VERSION=1.55.12
STRIPE_SHA256_amd64=89d0bbec0970917a07fbd4d3a98afecf95b08f88f0687362c4a94447a0610245
STRIPE_SHA256_arm64=28ef728e916175ad93fc55d781d125964503763090e336af230c74159a72883a

dest=${1:?usage: install-stripe-cli.sh <dest_dir>}

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
install -m 755 "$work/stripe" "$dest/stripe"

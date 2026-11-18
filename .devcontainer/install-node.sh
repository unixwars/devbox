#!/usr/bin/env bash
# Install Node.js (the LTS line NODE_MAJOR) from nodejs.org into <dest_dir>, e.g. /opt/node.
# The tarball is sha256-verified against the SHASUMS256.txt published beside it. Re-running the
# build picks up newer patch releases only when this layer is rebuilt; bump NODE_MAJOR for a new LTS.
set -euo pipefail

NODE_MAJOR=${NODE_MAJOR:-26}
dest=${1:?usage: install-node.sh <dest_dir>}

case "$(uname -m)" in
  x86_64|amd64) arch=x64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

base=https://nodejs.org/dist/latest-v${NODE_MAJOR}.x
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
curl -fsSL "$base/SHASUMS256.txt" -o "$work/SHASUMS256.txt"
file=$(grep -oE "node-v[0-9.]+-linux-$arch\.tar\.gz" "$work/SHASUMS256.txt" | head -n1)
[ -n "$file" ] || { echo "no linux-$arch tarball listed for Node $NODE_MAJOR" >&2; exit 1; }
curl -fsSL "$base/$file" -o "$work/$file"
(cd "$work" && grep " $file\$" SHASUMS256.txt | sha256sum -c -)
mkdir -p "$dest"
tar -xzf "$work/$file" -C "$dest" --strip-components=1 --no-same-owner
echo "node: installed $("$dest/bin/node" --version) in $dest"

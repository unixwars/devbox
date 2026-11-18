#!/usr/bin/env bash
# Optional extra "test-tooling": a Postgres server and client, the system libraries Chromium
# needs (Playwright), and the `devbox-pg` helper. Works as root (image build) or with sudo.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SUDO=""; [ "$(id -u)" = 0 ] || SUDO=sudo

if command -v devbox-pg >/dev/null 2>&1; then echo "test-tooling: already installed"; exit 0; fi

export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update
$SUDO apt-get install -y --no-install-recommends \
  postgresql postgresql-client \
  fonts-liberation fonts-noto-color-emoji libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 \
  libcairo2 libcups2t64 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0t64 libnspr4 libnss3 \
  libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 \
  libxkbcommon0 libxrandr2
$SUDO rm -rf /var/cache/apt/archives
$SUDO install -m 755 "$here/bin/devbox-pg" /usr/local/bin/devbox-pg
echo "test-tooling: installed. Fetch the browser with: npx playwright install chromium"

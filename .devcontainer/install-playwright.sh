#!/usr/bin/env bash
# Opt-in: Chromium for Playwright. The system libraries live in the container layer, so
# re-run this after a rebuild; the browser download itself is cached in the devbox-cache volume.
set -euo pipefail
cd "${1:-.}"
sudo env "PATH=$PATH" npx --yes playwright install-deps chromium
npx --yes playwright install chromium

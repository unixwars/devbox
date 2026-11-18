#!/usr/bin/env bash
# Optional extra "vercel": the Vercel CLI, pinned, from npm. Needs node, so it cannot run
# during the image build; post-create installs it (the npm cache is a volume).
set -euo pipefail

VERCEL_VERSION=66.1.0

if ! command -v npm >/dev/null 2>&1; then echo "vercel: npm not available yet" >&2; exit 3; fi
if command -v vercel >/dev/null 2>&1 && [ "$(vercel --version 2>/dev/null | tail -1)" = "$VERCEL_VERSION" ]; then
  echo "vercel: already installed"; exit 0
fi
npm install -g "vercel@$VERCEL_VERSION"

#!/usr/bin/env bash
# Install optional extras. Names come from the arguments, else from $DEVBOX_EXTRAS
# (space or comma separated). "all" means every extra. Safe to run again.
#   test-tooling  Postgres, Chromium system libraries, devbox-pg
#   stripe        Stripe CLI (pinned, checksum verified)
#   vercel        Vercel CLI (pinned, from npm)
# Node is in the image before this runs, so every extra installs at build time.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
all="test-tooling stripe vercel"
list=${*:-${DEVBOX_EXTRAS:-}}
list=${list//,/ }
[ -n "${list// /}" ] || exit 0
[ "$list" = all ] && list=$all

for name in $list; do
  case "$name" in
    test-tooling) bash "$here/install-test-tooling.sh" ;;
    stripe) bash "$here/install-stripe-cli.sh" ;;
    vercel)
      if command -v npm >/dev/null 2>&1; then bash "$here/install-vercel-cli.sh"
      else echo "vercel: skipped, npm not found" >&2; exit 3; fi ;;
    *) echo "unknown extra: $name (known: $all)" >&2; exit 2 ;;
  esac
done

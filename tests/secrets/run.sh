#!/usr/bin/env bash
# Runs every tests/secrets/test-*.sh; one PASS/FAIL line per file; non-zero if any fails.
# Installs pinned sops/age into a cache dir on first use and prepends it to PATH.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
tools=${SECRETS_TOOLS_DIR:-${XDG_CACHE_HOME:-$repo/.superpowers/cache}/sops-age-tools}

if [ -f "$repo/.devcontainer/install-sops-age.sh" ] \
   && ! { [ -x "$tools/sops" ] && [ -x "$tools/age" ] && [ -x "$tools/age-keygen" ]; }; then
  bash "$repo/.devcontainer/install-sops-age.sh" "$tools" >&2 || echo "WARN: tool install failed" >&2
fi
export PATH="$tools:$PATH"

fail=0
for t in "$here"/test-*.sh; do
  [ -e "$t" ] || continue
  if out=$(bash "$t" 2>&1); then
    echo "PASS $(basename "$t")"
  else
    echo "FAIL $(basename "$t")"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1
  fi
done
exit "$fail"

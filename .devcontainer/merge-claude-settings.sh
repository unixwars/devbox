#!/usr/bin/env bash
# Usage: merge-claude-settings.sh <template.json> <settings.json>
# Unions permissions.deny from the template into the settings file (created if missing),
# keeping existing order, adding only new rules, and preserving every other key.
# Idempotent; atomic write; leaves an invalid existing file untouched and exits 1.
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: merge-claude-settings.sh <template> <settings_file>" >&2; exit 2; }
tpl=$1; dst=$2

jq -e . "$tpl" >/dev/null 2>&1 || { echo "merge-claude-settings: template is not valid JSON: $tpl" >&2; exit 1; }
if [ -s "$dst" ]; then
  jq -e 'type == "object"' "$dst" >/dev/null 2>&1 \
    || { echo "merge-claude-settings: $dst is not a valid JSON object; leaving it untouched" >&2; exit 1; }
fi

mkdir -p "$(dirname "$dst")"
tmp=$(mktemp "$(dirname "$dst")/.settings.XXXXXX")
trap 'rm -f "$tmp"' EXIT

base=$dst; [ -s "$dst" ] || base=/dev/null
jq -n --slurpfile tpl "$tpl" --slurpfile cur "$base" '
  ($cur[0] // {}) as $c
  | $c | .permissions = (($c.permissions // {}) | .deny = (((.deny // []) + ($tpl[0].permissions.deny // [])) | reduce .[] as $r ([]; if index([$r]) then . else . + [$r] end)))
' > "$tmp"
chmod --reference="$dst" "$tmp" 2>/dev/null || chmod 600 "$tmp"
mv "$tmp" "$dst"
trap - EXIT

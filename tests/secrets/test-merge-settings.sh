#!/usr/bin/env bash
# Tests .devcontainer/merge-claude-settings.sh (deny-rule union into settings.json).
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dc="$here/../../.devcontainer"
m="$dc/merge-claude-settings.sh"; tpl="$dc/claude-settings.template.json"
# shellcheck source=lib.sh
. "$here/lib.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# missing file (and missing parent dir) is created with all six rules
f=$T/new/settings.json
if bash "$m" "$tpl" "$f" && jq -e '.permissions.deny | length == 6' "$f" >/dev/null; then
  pass create_missing
else fail create_missing; fi

# unrelated keys preserved, overlapping rule not duplicated, existing order first
f=$T/existing.json
cat > "$f" <<'J'
{"model":"opus","permissions":{"allow":["Bash(ls)"],"deny":["Bash(rm *)","Bash(sops *)"]},"env":{"A":"1"}}
J
bash "$m" "$tpl" "$f"
if jq -e '.model=="opus" and .env.A=="1" and .permissions.allow==["Bash(ls)"]
  and .permissions.deny[0]=="Bash(rm *)" and .permissions.deny[1]=="Bash(sops *)"
  and (.permissions.deny|length)==7 and (.permissions.deny|unique|length)==7' "$f" >/dev/null; then
  pass merge_preserves_and_dedupes
else fail merge_preserves_and_dedupes; fi

# idempotent: second run is byte-identical
cp "$f" "$T/before"; bash "$m" "$tpl" "$f"
if cmp -s "$T/before" "$f"; then pass idempotent; else fail idempotent; fi

# invalid JSON: non-zero exit, file untouched
f=$T/bad.json; printf '{not json' > "$f"; cp "$f" "$T/bad.orig"
if bash "$m" "$tpl" "$f" 2>/dev/null; then fail invalid_json_rejected "exit 0"
elif cmp -s "$f" "$T/bad.orig"; then pass invalid_json_rejected
else fail invalid_json_rejected "file modified"; fi
exit $LIB_FAILED

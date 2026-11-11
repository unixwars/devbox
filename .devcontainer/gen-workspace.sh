# .devcontainer/gen-workspace.sh
#!/usr/bin/env bash
# Keeps the folder list of shared.code-workspace in step with the repos and worktrees under
# /workspaces. Everything else in the file, and any folder you added or renamed by hand, stays.
set -euo pipefail

root=${WORKSPACES_ROOT:-/workspaces}
out=$root/shared.code-workspace

# Top-level repos, plus the worktrees git reports for them. Worktrees inside their repo's own
# folder are skipped: the repo root already shows them.
found=$(
  for d in "$root"/*/; do
    d=${d%/}
    [ -e "$d/.git" ] || continue
    echo "$d"
    [ -d "$d/.git" ] || continue
    git -C "$d" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | while read -r w; do
      case $w in
        "$d"|"$d"/*) ;;
        "$root"/*) [ -d "$w" ] && echo "$w" ;;
      esac
    done
  done | sort -u
)

base='{}'
[ -f "$out" ] && base=$(cat "$out")
if ! jq -e . <<<"$base" >/dev/null 2>&1; then
  echo "gen-workspace: $out is not plain JSON (comments?); left untouched" >&2
  exit 0
fi

printf '%s\n' "$found" | jq -R . | jq -s 'map(select(length > 0))' > "$out.found"

# Keep: folders outside the root (hand-added) and folders still on disk, in their old order,
# names included. Add: anything new, named by its path under the root.
jq --slurpfile found "$out.found" --arg root "$root" '
  $found[0] as $f
  | ((.folders // [])
      | map(select(((.path // "") | startswith($root + "/") | not)
                   or (.path as $p | $f | index($p) != null)))) as $keep
  | ($keep | map(.path // "")) as $known
  | .folders = $keep + ($f | map(select(. as $p | $known | index($p) == null))
                            | map({name: ltrimstr($root + "/"), path: .}))
' <<<"$base" > "$out.tmp"

mv "$out.tmp" "$out"
rm -f "$out.found"

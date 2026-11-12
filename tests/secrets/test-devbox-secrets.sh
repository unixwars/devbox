#!/usr/bin/env bash
# Tests .devcontainer/host/devbox-secrets (unlock/lock/status/edit) against a fixture repo.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ds="$here/../../.devcontainer/host/devbox-secrets"
# shellcheck source=lib.sh
. "$here/lib.sh"
mk_fixture || exit 1
trap 'rm -rf "$FIXTURE_DIR"' EXIT

export DEVBOX_RUNTIME_DIR=$FIXTURE_DIR/run/devbox
export DEVBOX_KEY_ENC=$FIXTURE_DIR/box.key.age
export DEVBOX_SECRETS_REPO=$SECRETS_REPO
export DEVBOX_ADMIN_KEY=$ADMIN_KEY
cat > "$FIXTURE_DIR/decrypt-stub" <<STUB
#!/usr/bin/env bash
cat "$BOX_KEY"
STUB
chmod +x "$FIXTURE_DIR/decrypt-stub"
export DEVBOX_AGE_DECRYPT=$FIXTURE_DIR/decrypt-stub
KEY=$DEVBOX_RUNTIME_DIR/age.key

bash "$ds" unlock >/dev/null 2>&1
mode=$(stat -c %a "$KEY" 2>/dev/null)
if [ "$mode" = 600 ] && cmp -s "$KEY" "$BOX_KEY"; then pass unlock_writes_key_0600; else fail unlock_writes_key_0600 "mode=$mode"; fi

if [ "$(ls -A "$DEVBOX_RUNTIME_DIR")" = age.key ]; then pass unlock_does_not_leave_temp; else fail unlock_does_not_leave_temp; fi

before=$(stat -c %i "$DEVBOX_RUNTIME_DIR")
bash "$ds" lock >/dev/null 2>&1; bash "$ds" unlock >/dev/null 2>&1
after=$(stat -c %i "$DEVBOX_RUNTIME_DIR")
if [ "$before" = "$after" ]; then pass unlock_preserves_dir_inode; else fail unlock_preserves_dir_inode; fi

if bash "$ds" unlock >/dev/null 2>&1 && bash "$ds" lock >/dev/null 2>&1 && bash "$ds" lock >/dev/null 2>&1; then
  pass unlock_twice_and_lock_twice; else fail unlock_twice_and_lock_twice; fi

if [ -d "$DEVBOX_RUNTIME_DIR" ] && [ ! -e "$KEY" ]; then pass lock_removes_key_only; else fail lock_removes_key_only; fi

bash "$ds" status >/dev/null 2>&1; s1=$?
bash "$ds" unlock >/dev/null 2>&1
bash "$ds" status >/dev/null 2>&1; s2=$?
if [ "$s1" = 1 ] && [ "$s2" = 0 ]; then pass status_reflects_state; else fail status_reflects_state "locked=$s1 unlocked=$s2"; fi

cat > "$FIXTURE_DIR/editor-stub" <<STUB
#!/usr/bin/env bash
echo "\$TMPDIR" > "$FIXTURE_DIR/seen-tmpdir"
echo NEW=1 >> "\$1"
STUB
chmod +x "$FIXTURE_DIR/editor-stub"
EDITOR=$FIXTURE_DIR/editor-stub bash "$ds" edit boutique dev >/dev/null 2>&1
seen=$(cat "$FIXTURE_DIR/seen-tmpdir" 2>/dev/null)
dec=$(SOPS_AGE_KEY_FILE=$ADMIN_KEY sops decrypt --input-type dotenv --output-type dotenv "$SECRETS_REPO/boutique/dev.env" 2>/dev/null)
if [ "$seen" = "$DEVBOX_RUNTIME_DIR" ] && printf '%s\n' "$dec" | grep -qx 'NEW=1' \
   && grep -q '^sops_' "$SECRETS_REPO/boutique/dev.env"; then
  pass edit_uses_runtime_tmpdir; else fail edit_uses_runtime_tmpdir "tmpdir=$seen"; fi

bash "$ds" edit ../x dev >/dev/null 2>&1; e1=$?
bash "$ds" edit boutique 'a b' >/dev/null 2>&1; e2=$?
if [ "$e1" = 2 ] && [ "$e2" = 2 ]; then pass edit_rejects_bad_names; else fail edit_rejects_bad_names "$e1 $e2"; fi

exit $LIB_FAILED

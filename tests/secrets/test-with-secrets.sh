#!/usr/bin/env bash
# Tests .devcontainer/bin/with-secrets against a fixture secrets repo.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ws="$here/../../.devcontainer/bin/with-secrets"
# shellcheck source=lib.sh
. "$here/lib.sh"
mk_fixture || exit 1
export DEVBOX_SECRETS_DIR=$SECRETS_REPO DEVBOX_SECRETS_KEY=$BOX_KEY

# eq NAME EXPECTED ACTUAL (values are not echoed on mismatch)
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "output mismatch"; fi; }

out=$(bash "$ws" boutique dev -- sh -c 'echo $DATABASE_URL' 2>/dev/null)
eq unlocked_exports_value 'postgres://fake:fake@localhost/dev' "$out"

out=$(bash "$ws" boutique dev -- sh -c 'echo $SHARED $GLOBAL_ONLY' 2>/dev/null)
eq project_overrides_global 'from-project global-fake' "$out"

out=$(bash "$ws" boutique dev -- sh -c 'echo $EQ' 2>/dev/null)
eq value_with_equals 'a=b=c' "$out"

out=$(bash "$ws" boutique dev -- printf '%s|' "a b" "it's" '$HOME' 'x;y' 2>/dev/null)
eq args_quoted "a b|it's|\$HOME|x;y|" "$out"

bash "$ws" boutique dev -- sh -c 'exit 7' >/dev/null 2>&1; rc=$?
eq exit_code_passthrough 7 "$rc"

err=$(DEVBOX_SECRETS_KEY=$FIXTURE_DIR/absent.key bash "$ws" boutique dev -- true 2>&1 >/dev/null); rc=$?
eq locked_rc 3 "$rc"
eq locked_msg 'locked: run devbox-secrets unlock on the host' "$err"
: > "$FIXTURE_DIR/empty.key"
DEVBOX_SECRETS_KEY=$FIXTURE_DIR/empty.key bash "$ws" boutique dev -- true >/dev/null 2>&1; rc=$?
eq locked_empty_key 3 "$rc"

err=$(bash "$ws" nosuch dev -- true 2>&1 >/dev/null); rc=$?
eq unknown_project_rc 4 "$rc"
eq unknown_project_oneline 1 "$(printf '%s\n' "$err" | wc -l)"
case $err in *goroutine*|*panic*|*sops*Error*) fail unknown_project_clean "sops text leaked";; *) pass unknown_project_clean;; esac

err=$(bash "$ws" boutique prod -- true 2>&1 >/dev/null); rc=$?
eq prod_with_box_key_rc 5 "$rc"
eq prod_with_box_key_oneline 1 "$(printf '%s\n' "$err" | wc -l)"
case $err in *goroutine*|*Failed*|*"Error getting"*) fail prod_clean "sops text leaked";; *) pass prod_clean;; esac

err=$(bash "$ws" boutique dev true 2>&1 >/dev/null); rc=$?
eq usage_no_dashes 2 "$rc"
case $err in *sage*) pass usage_text;; *) fail usage_text;; esac
bash "$ws" boutique dev -- >/dev/null 2>&1; rc=$?
eq usage_no_command 2 "$rc"
bash "$ws" '../x' dev -- true >/dev/null 2>&1; rc=$?
eq usage_bad_name 2 "$rc"

mkdir "$FIXTURE_DIR/tmp"
TMPDIR=$FIXTURE_DIR/tmp bash "$ws" boutique dev -- true >/dev/null 2>&1
eq no_plaintext_on_disk '' "$(ls -A "$FIXTURE_DIR/tmp")"

out=$(SOPS_AGE_KEY_FILE=/nonexistent/bad bash "$ws" boutique dev -- sh -c 'echo $EQ' 2>/dev/null)
eq key_not_from_env 'a=b=c' "$out"

out=$(bash "$ws" boutique dev -- sh -c 'echo "${SOPS_AGE_KEY_FILE-unset}"' 2>/dev/null)
eq wrapped_cmd_has_no_key_file unset "$out"

SOPS_AGE_KEY=$(grep '^AGE-SECRET-KEY' "$ADMIN_KEY") bash "$ws" boutique prod -- true >/dev/null 2>&1; rc=$?
eq sops_age_key_env_ignored 5 "$rc"

exit "$LIB_FAILED"

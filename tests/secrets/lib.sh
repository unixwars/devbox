#!/usr/bin/env bash
# Shared helpers for tests/secrets/test-*.sh (source this file).
#
# mk_fixture creates a throwaway encrypted secrets repo and exports:
#   FIXTURE_DIR  temp root (removed on exit via an EXIT trap)
#   BOX_KEY      path to the box age identity file
#   ADMIN_KEY    path to the admin age identity file
#   SECRETS_REPO encrypted repo dir: .sops.yaml, boutique/dev.env, boutique/prod.env,
#                _global/dev.env (fake throwaway values only)
# Needs sops, age-keygen on PATH (tests/secrets/run.sh arranges that).
# pass NAME / fail NAME [MSG]: print a result line; fail marks the run failed (exit status).

LIB_FAILED=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1${2:+: $2}"; LIB_FAILED=1; }

mk_fixture() {
  FIXTURE_DIR=$(mktemp -d)
  trap 'rm -rf "$FIXTURE_DIR"' EXIT
  BOX_KEY=$FIXTURE_DIR/box.key
  ADMIN_KEY=$FIXTURE_DIR/admin.key
  SECRETS_REPO=$FIXTURE_DIR/secrets
  age-keygen -o "$BOX_KEY" >/dev/null 2>&1
  age-keygen -o "$ADMIN_KEY" >/dev/null 2>&1
  local box admin
  box=$(age-keygen -y "$BOX_KEY"); admin=$(age-keygen -y "$ADMIN_KEY")
  mkdir -p "$SECRETS_REPO/boutique" "$SECRETS_REPO/_global"
  cat > "$SECRETS_REPO/.sops.yaml" <<YAML
creation_rules:
  - path_regex: ^(_global|[^/]+)/(dev|preview)\.env\$
    age: $box,$admin
  - path_regex: ^[^/]+/prod\.env\$
    age: $admin
YAML
  printf '%s\n' 'DATABASE_URL=postgres://fake:fake@localhost/dev' 'SHARED=from-project' \
    'EQ=a=b=c' > "$SECRETS_REPO/boutique/dev.env"
  printf '%s\n' 'DATABASE_URL=postgres://fake:fake@localhost/prod' > "$SECRETS_REPO/boutique/prod.env"
  printf '%s\n' 'SHARED=from-global' 'GLOBAL_ONLY=global-fake' > "$SECRETS_REPO/_global/dev.env"
  (
    cd "$SECRETS_REPO" || exit 1
    local f
    for f in boutique/dev.env boutique/prod.env _global/dev.env; do
      SOPS_AGE_KEY_FILE=$ADMIN_KEY sops encrypt --input-type dotenv --output-type dotenv "$f" > "$f.enc" \
        && mv "$f.enc" "$f" || exit 1
    done
  ) || { echo "mk_fixture: encryption failed" >&2; return 1; }
  export FIXTURE_DIR BOX_KEY ADMIN_KEY SECRETS_REPO
}

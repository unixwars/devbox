# sops+age secrets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `devbox-secrets` volume with a sops+age encrypted secrets repo, a host-side unlock to tmpfs, and an in-box `with-secrets` wrapper.

**Architecture:** A private repo of sops dotenv files (cloned on the host, bind-mounted read-only at `/secrets`). The box age key is passphrase-encrypted on the host; `devbox-secrets unlock` writes it to tmpfs, which is bind-mounted read-only into the container. `with-secrets` runs one command through `sops exec-env --same-process`. Pure bash scripts, tested against throwaway keys.

**Tech Stack:** bash, sops (>= 3.10), age, jq, Podman devcontainer.

**Spec:** `docs/secrets.md` (working dir for all paths: `/workspaces/devbox.copy`, a git repo; the real repo is synced by the owner afterwards).

## Global Constraints

- sops >= 3.10 (passphrase-protected age identities), version and sha256 pinned from the official release checksums; never invent a checksum.
- `exec-env` takes one command string run via `/bin/sh -c`: quote each argument POSIX-style (`'` becomes `'\''`), never bash `printf %q`.
- Always `--same-process`.
- `SOPS_AGE_KEY_FILE` is set only inside `with-secrets`, never in `containerEnv`.
- `.sops.yaml`: `path_regex` rules exactly as in the spec; no catch-all rule; `prod.env` admin key only; dev and preview on box key plus admin key.
- `lock`/`unlock` only create or remove the key file inside an existing directory (umask 077, temp file in the same directory, then `mv`); never delete or recreate the directory.
- `initializeCommand` runs `mkdir -p` on both the runtime directory and `~/src/secrets`; runtime dir mount source is `${localEnv:XDG_RUNTIME_DIR:/run/user/1000}/devbox`.
- Mounts: `~/src/secrets` read-only at `/secrets`; runtime dir read-only at `/run/devbox-secrets`.
- Claude deny rules use `//` absolute prefixes in user settings.
- No secret values in logs, test output or commits.
- Not run on Podman: container-level checks are manual and listed in Task 5.

## Review Focus

- Arguments containing spaces, single quotes, `$` and `;` reach the command unchanged (wrapper quoting).
- A value containing `=` survives intact.
- Unknown project or env, or a prod file with the box key, gives a one-line error and a distinct exit code, not a sops stack trace.
- Missing `--`, or no command, prints usage and exits 2.
- `lock` when already locked and `unlock` when already unlocked are harmless.
- The key directory is never recreated (a pre-existing directory inode is preserved across `lock`/`unlock`).

---

## File Structure

| Path | Responsibility |
|---|---|
| `.devcontainer/install-sops-age.sh` | Download pinned sops and age into a directory, verifying sha256 |
| `.devcontainer/bin/with-secrets` | In-box wrapper (installed to `/usr/local/bin`) |
| `.devcontainer/host/devbox-secrets` | Host script: `unlock`, `lock`, `status`, `edit` |
| `.devcontainer/claude-settings.template.json` | `permissions.deny` rules |
| `.devcontainer/merge-claude-settings.sh` | Idempotent jq merge of the template into `~/.claude/settings.json` |
| `tests/secrets/lib.sh` | Test helpers: temp dir, throwaway keys, `.sops.yaml`, fixtures |
| `tests/secrets/test-*.sh`, `tests/secrets/run.sh` | One test file per script, plus a runner |

Tests need `sops`, `age`, `jq` on `PATH`; Task 1 provides them.

---

### Task 1: Pinned sops and age install

**Files:**
- Create: `.devcontainer/install-sops-age.sh`, `tests/secrets/run.sh`, `tests/secrets/test-install.sh`
- Modify: `.devcontainer/Dockerfile`

**Interfaces:**
- Produces: `install-sops-age.sh <dest_dir>` installs `sops` and `age`/`age-keygen` into `<dest_dir>`, exit 0 only if checksums match. `run.sh` runs every `tests/secrets/test-*.sh` and exits non-zero if any fails.

- [ ] **Step 1: Write the failing test** `test-install.sh`: installs into a temp dir; asserts `<dir>/sops --version` output contains the pinned version, `<dir>/age --version` runs, and that a run with a corrupted expected checksum (env `SOPS_SHA256_OVERRIDE=bad`) exits non-zero and leaves no binary.
- [ ] **Step 2: Run** `bash tests/secrets/run.sh`. Expected: FAIL (script missing).
- [ ] **Step 3: Implement** `install-sops-age.sh`. Pin the latest sops 3.x (>= 3.10) and age release at implementation time, take the sha256 values from each project's official checksum file and hardcode them, download with `curl -fsSL`, verify with `sha256sum -c` before installing.
- [ ] **Step 4: Dockerfile.** `COPY install-sops-age.sh` and run it into `/usr/local/bin`; copy `bin/with-secrets` there too (created in Task 2, so add this `COPY` line in Task 2).
- [ ] **Step 5: Run** `bash tests/secrets/run.sh`. Expected: PASS. Add `export PATH="<dest>:$PATH"` to the runner so later tests find the binaries.
- [ ] **Step 6: Commit** `git add -A && git commit -m "feat(secrets): pinned sops and age install"`.

### Task 2: `with-secrets`

**Files:**
- Create: `.devcontainer/bin/with-secrets`, `tests/secrets/lib.sh`, `tests/secrets/test-with-secrets.sh`
- Modify: `.devcontainer/Dockerfile` (add `COPY bin/with-secrets /usr/local/bin/with-secrets`, `chmod 755`)

**Interfaces:**
- Produces: `with-secrets <project> <env> -- <cmd> [args...]`. Reads `DEVBOX_SECRETS_DIR` (default `/secrets`) and `DEVBOX_SECRETS_KEY` (default `/run/devbox-secrets/age.key`). Exit codes: 2 usage, 3 locked (key file missing or empty), 4 no such project/env file, 5 decrypt failed; otherwise the command's own exit code. Merges `_global/<env>.env` then `<project>/<env>.env` (project wins); a missing `_global` file is fine.
- `lib.sh` provides: `mk_fixture` (temp dir; generates box and admin keys with `age-keygen`; writes the spec's `.sops.yaml` with the real public keys; encrypts `boutique/dev.env`, `boutique/prod.env`, `_global/dev.env` with sops dotenv), `pass`/`fail` helpers.

- [ ] **Step 1: Write failing tests** in `test-with-secrets.sh` (each with the exact assertion):
  - `unlocked_exports_value`: `with-secrets boutique dev -- sh -c 'echo $DATABASE_URL'` prints the fixture value.
  - `project_overrides_global`: same key in both files prints the project value; a global-only key is also present.
  - `value_with_equals`: a value `a=b=c` prints unchanged.
  - `args_quoted`: `with-secrets boutique dev -- printf '%s|' "a b" "it's" '$HOME' 'x;y'` prints `a b|it's|$HOME|x;y|`.
  - `exit_code_passthrough`: `-- sh -c 'exit 7'` exits 7.
  - `locked`: key file absent: exit 3, stderr contains `locked: run devbox-secrets unlock on the host`.
  - `unknown_project`: exit 4, one-line stderr, no sops stack trace.
  - `prod_with_box_key`: `with-secrets boutique prod -- true` exits 5 with a one-line message.
  - `usage`: no `--`, or nothing after it: exit 2 with usage text.
  - `no_plaintext_on_disk`: `TMPDIR` pointed at an empty dir; after a run the dir is still empty.
  - `key_not_from_env`: with `SOPS_AGE_KEY_FILE` pre-set in the caller's environment to a bad path, the wrapper still succeeds (it sets its own).
- [ ] **Step 2: Run** `bash tests/secrets/run.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** `with-secrets` (bash, `set -euo pipefail`). Single-quote each argument into one string; nest `sops exec-env --same-process <global> '<inner>'` around `sops exec-env --same-process <project> '<quoted command>'`; classify failures by checking file existence and key presence first, then mapping sops decrypt failure to exit 5 with a one-line message (suppress sops' own output).
- [ ] **Step 4: Run** the suite. Expected: PASS.
- [ ] **Step 5: Commit** `git commit -am "feat(secrets): with-secrets wrapper"`.

### Task 3: `devbox-secrets` host script

**Files:**
- Create: `.devcontainer/host/devbox-secrets`, `tests/secrets/test-devbox-secrets.sh`

**Interfaces:**
- Produces: `devbox-secrets unlock|lock|status [--container <name>]|edit <project> <env>`. Environment: `DEVBOX_RUNTIME_DIR` (default `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/devbox`), `DEVBOX_KEY_ENC` (default `~/.config/devbox/box.key.age`), `DEVBOX_SECRETS_REPO` (default `~/src/secrets`), `DEVBOX_ADMIN_KEY` (default `~/.config/devbox/admin.key`), `DEVBOX_AGE_DECRYPT` (test seam, default `age -d`). Key file is `$DEVBOX_RUNTIME_DIR/age.key`. `status` exits 0 if unlocked, 1 if locked; with `--container` also runs `podman exec <name> test -s /run/devbox-secrets/age.key` and reports the container view.

- [ ] **Step 1: Write failing tests:**
  - `unlock_writes_key_0600`: with `DEVBOX_AGE_DECRYPT` set to a stub that cats the box key, `unlock` creates `age.key` mode 600 with the key contents.
  - `unlock_preserves_dir_inode`: record the directory inode before and after `lock` then `unlock`; equal.
  - `unlock_does_not_leave_temp`: after unlock the directory contains only `age.key`.
  - `unlock_twice_and_lock_twice`: second call exits 0.
  - `lock_removes_key_only`: directory still exists after `lock`.
  - `status_reflects_state`: exit 1 locked, 0 unlocked.
  - `edit_uses_runtime_tmpdir`: with `EDITOR` a stub script that records `$TMPDIR` and appends `NEW=1`, `edit boutique dev` makes the stub see `TMPDIR=$DEVBOX_RUNTIME_DIR`, the decrypted fixture contains `NEW=1`, and the stored file is still encrypted.
  - `edit_rejects_bad_names`: `edit ../x dev` and `edit boutique 'a b'` exit 2 (names must match `^[A-Za-z0-9_-]+$`).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** `unlock`: `mkdir -p` only if the directory is absent; `umask 077`; run the decrypt command into a `mktemp` file inside the runtime dir; `mv` over `age.key`. `edit`: `cd` into the repo, export `TMPDIR` and `SOPS_AGE_KEY_FILE=$DEVBOX_ADMIN_KEY`, run `sops edit` on the validated path; refuse an `EDITOR` containing `--wait` with a message.
- [ ] **Step 4: Run** the suite. Expected: PASS.
- [ ] **Step 5: Commit** `git commit -am "feat(secrets): devbox-secrets host script"`.

### Task 4: Claude deny rules and devcontainer wiring

**Files:**
- Create: `.devcontainer/claude-settings.template.json`, `.devcontainer/merge-claude-settings.sh`, `tests/secrets/test-merge-settings.sh`
- Modify: `.devcontainer/devcontainer.json`, `.devcontainer/post-create.sh`, `.devcontainer/Dockerfile`

**Interfaces:**
- Produces: `merge-claude-settings.sh <template> <settings_file>` creates the settings file if missing and unions `permissions.deny` entries without duplicates, preserving all other keys.
- Template deny list (exactly): `Read(//run/devbox-secrets/**)`, `Read(//workspaces/**/.env*)`, `Bash(sops *)`, `Bash(with-secrets * -- env*)`, `Bash(with-secrets * -- printenv*)`, `Bash(* /run/devbox-secrets*)`.

- [ ] **Step 1: Write failing tests:** merge into a missing file yields valid JSON containing all six rules; merge into a file with existing unrelated keys and an existing deny entry preserves them; running twice yields identical output (idempotent).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** the template and the jq merge script.
- [ ] **Step 4: Run** the suite. Expected: PASS.
- [ ] **Step 5: Wire the devcontainer** (no automated test; verify with the command in Step 6):
  - `devcontainer.json`: add `initializeCommand` (`mkdir -p` the runtime dir `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/devbox` and `~/src/secrets`, mode 700 on the first); add the two read-only bind mounts per Global Constraints; remove the `devbox-secrets` volume mount; do not add `SOPS_AGE_KEY_FILE` to `containerEnv`.
  - `post-create.sh`: remove the `chmod ~/.secrets` and `ln -sf ... ~/.gh_token` lines; add a call to `merge-claude-settings.sh` for `~/.claude/settings.json`.
  - `Dockerfile`: remove the `.secrets` directory from the mount-point `install -d` lines.
- [ ] **Step 6: Verify** the config parses and has no leftovers. Run `grep -n 'devbox-secrets\|SOPS_AGE_KEY_FILE\|\.gh_token' .devcontainer/devcontainer.json .devcontainer/post-create.sh .devcontainer/Dockerfile`. Expected: `devbox-secrets` appears only as the `/run/devbox-secrets` mount target; `SOPS_AGE_KEY_FILE` and `.gh_token` do not appear; and `sed 's#//.*##' .devcontainer/devcontainer.json | jq .` exits 0.
- [ ] **Step 7: Commit** `git add -A && git commit -m "feat(secrets): devcontainer wiring and Claude deny rules"`.

### Task 5: Documentation and manual verification list

**Files:**
- Modify: `docs/secrets.md`, `docs/design.md`, `README.md`

- [ ] **Step 1: Add a Setup section to `docs/secrets.md`** with the exact one-time commands: generate box and admin keys (`age-keygen`), passphrase-protect the box key (`age -p`) into `~/.config/devbox/box.key.age`, protect the admin key (sops >= 3.10), `git init` the secrets repo with the spec's `.sops.yaml`, create the fine-grained `GH_TOKEN` and add `_global/dev.env`, back up the admin key as one Bitwarden item, install `devbox-secrets` on the host `PATH`. Add the CLAUDE.md/AGENTS.md line for projects (never print the environment or secret values). Change the Status line to "implemented, container checks pending".
- [ ] **Step 2: `README.md`:** remove the `devbox-secrets` row from the Volumes table and add a short "Secrets" paragraph linking `docs/secrets.md`.
- [ ] **Step 3: `docs/design.md`:** replace the "Planned" line with the implemented description; update *Persistence* (secrets volume removed) and *Known risks* (box key shared by all projects; agents can print their own environment); remove "secret injection proxy" nuance only if wording is now wrong (the proxy stays out of scope).
- [ ] **Step 4: Manual verification checklist** in `docs/secrets.md` (container-level, to run after the first rebuild): `${localEnv:XDG_RUNTIME_DIR:/run/user/1000}` resolves; the `dev` user can read the mounted key (`keep-id` ownership); `with-secrets` works from a VS Code terminal after `unlock` and fails cleanly after `lock`; recreating the host key file (lock/unlock) is visible in the running container; the deny rules block `cat /run/devbox-secrets/age.key` and `sops -d`; each project's tooling honors injected variables over `.env` files.
- [ ] **Step 5: Run** `bash tests/secrets/run.sh`. Expected: all PASS.
- [ ] **Step 6: Commit** `git commit -am "docs(secrets): setup, README and design updates"`.

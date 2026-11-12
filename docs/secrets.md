# Secrets design

Status: implemented, container checks pending (see Manual verification). Replaces the `devbox-secrets` volume and the per-project
gitignored `.env` files. Revised after review; items marked *(unverified)* were not checked
against sources or a running Podman.

## Problems this solves

- **Accidental leakage.** An agent reads a `.env` file, the values enter the session
  transcript, and they have to be rotated.
- **Logistics.** Secrets sit in gitignored files per project and can be lost, with no single
  place to update them.
- **Plaintext at rest** in a volume readable by anything running in the box.

It reduces accidents; it does not stop a determined exfiltration or an agent that prints its own
environment (see Limits).

## Overview

| Piece | Where | Role |
|---|---|---|
| Secrets repo | Private git repo, cloned on the host at `~/src/secrets` | Source of truth. One sops-encrypted dotenv file per project and environment. Its remote is the backup. |
| Admin key | Host, passphrase-protected, backed up as one Bitwarden item | Decrypts everything, including prod. Never enters the box. |
| Box key | Host, passphrase-encrypted file | Decrypts dev files only. Unsealed into the box per work session. |
| `devbox-secrets` | Host script | `unlock`, `lock`, `status`, `edit <project> <env>` |
| `with-secrets` | In the box | Runs one command with one environment's values in its process environment |

```
host                                             container
~/src/secrets (encrypted)  -- bind, read-only --> /secrets
$XDG_RUNTIME_DIR/devbox/age.key (tmpfs)
                           -- bind, read-only --> /run/devbox-secrets/age.key
                                                  with-secrets <project> <env> -- cmd
```

`with-secrets` details:

- sops `exec-env` takes a file and **one command string** that it runs through `/bin/sh -c`.
  The wrapper therefore joins its arguments into a single string with POSIX single quoting
  (`'` becomes `'\''`). Do not use bash `printf %q`: it can emit `$'..'`, and `/bin/sh` on
  Debian is dash.
- Use `--same-process` so sops replaces itself with the command and does not stay behind as a
  parent holding plaintext. Pin a sops version that has it.
- `SOPS_AGE_KEY_FILE` is set **inside the wrapper only**, not in `containerEnv`, so a bare
  `sops decrypt` in an agent shell fails.
- `_global` is merged by the wrapper, which runs nested `exec-env` calls: `_global/<env>.env`
  first, then the project file (project values win).

## Setup (once, on the host)

```
mkdir -p ~/.config/devbox ~/src/secrets && chmod 700 ~/.config/devbox
# keys
age-keygen -o ~/.config/devbox/box.key
age-keygen -o ~/.config/devbox/admin.key
# box key: passphrase-protected, unsealed per session by `devbox-secrets unlock`
age -p -o ~/.config/devbox/box.key.age ~/.config/devbox/box.key
shred -u ~/.config/devbox/box.key
# secrets repo
cd ~/src/secrets && git init
# write .sops.yaml (rules above, with the public keys printed by age-keygen), then:
sops _global/dev.env       # add GH_TOKEN=... (fine-grained, no access to the secrets repo)
git add -A && git commit -m "init"
# put devbox-secrets on PATH
ln -s /path/to/devbox/.devcontainer/host/devbox-secrets ~/.local/bin/devbox-secrets
```

- `devbox-secrets` reads `~/.config/devbox/box.key.age` and, for `edit`, the identity at
  `~/.config/devbox/admin.key`. Override with `DEVBOX_KEY_ENC`, `DEVBOX_ADMIN_KEY`,
  `DEVBOX_SECRETS_REPO`, `DEVBOX_RUNTIME_DIR`.
- Admin key protection *(unverified, not run)*: sops >= 3.10 supports passphrase-protected age
  identities. Encrypt the identity with `age -p -o ~/.config/devbox/admin.key.enc
  ~/.config/devbox/admin.key`, shred the plaintext, and point `DEVBOX_ADMIN_KEY` at the
  encrypted file; sops should prompt for the passphrase on `edit`. `devbox-secrets edit` runs
  sops with `SOPS_AGE_KEY_FILE=$DEVBOX_ADMIN_KEY`.
- Back up the admin key (and passphrase) as one Bitwarden item. Losing it loses prod.
- Without `sops` and `age` on the host, install them first (versions pinned in
  `.devcontainer/install-sops-age.sh`).
- Tests: `bash tests/secrets/run.sh`.
- In each project's `CLAUDE.md` / `AGENTS.md` add: "Never print the environment or secret
  values (no `env`, `printenv`, `cat` of key or env files); run commands through
  `with-secrets <project> <env> -- <cmd>`."

## Secrets repo layout

```
secrets/
  .sops.yaml
  _global/dev.env          # GH_TOKEN and other cross-project values
  <project>/dev.env        # encrypted to box key + admin key
  <project>/preview.env    # see decision below
  <project>/prod.env       # encrypted to the admin key only
```

`.sops.yaml` assigns recipients by path. `path_regex` is a Go regular expression, matched
relative to the directory of `.sops.yaml`, not a glob:

```yaml
creation_rules:
  - path_regex: ^(_global|[^/]+)/(dev|preview)\.env$
    age: <box public key>,<admin public key>
  - path_regex: ^[^/]+/prod\.env$
    age: <admin public key>
```

- There is no catch-all rule, so a path that matches nothing is rejected
  (`no matching creation rules found`) rather than encrypted to the wrong recipients.
- `.sops.yaml` is looked up from the current directory, so `devbox-secrets edit` must `cd` to
  the repo or pass `--config`. Do not pass recipients on the command line: that bypasses the
  rules *(unverified for age)*.
- `prod.env` is never encrypted to the box key, so the box cannot decrypt it even though the
  ciphertext is visible there.
- `preview.env` is deliberately on the box key (see Decisions).

### File format

Files use sops' dotenv store, which is stricter than most dotenv loaders:

- Each line splits at the first `=`. Quotes are **not** stripped, so `KEY="v"` stores a value
  that includes the quote characters. Write `KEY=v`.
- No `export ` prefix. Multiline values must be `\n` escapes. A non-comment line without `=` is
  an error.
- `exec-env` passes the plaintext values to the environment as stored.
- Key names, file names, project and environment names, and approximate value lengths are
  visible to anyone who can read the repo, including the box.

## Workflow

### Use a secret

```
with-secrets boutique dev -- npm run dev
with-secrets boutique dev -- npx prisma migrate dev
```

Values exist only in that process and its children, and nothing is written to the project.
Tools that load `.env` files without overwriting existing variables pick the injected values up
unchanged: Next.js, `dotenv` (the npm package, default), Vite, and `node --env-file` *(the last
two unverified)*. Exceptions: python-dotenv's `dotenv run` overrides by default, and the npm
`dotenv-cli` needs care with `-o`. Scripts of the form `dotenv run -f .env.local -- cmd` should
be replaced with `with-secrets`. Each project must be checked individually.

If a tool insists on a file:

```
TMPDIR=/dev/shm sops exec-file --filename boutique.env /secrets/boutique/dev.env 'tool --env-file {}'
```

- `exec-file` creates its temp directory under `$TMPDIR`, which in the container is the overlay
  filesystem, not tmpfs. Set `TMPDIR=/dev/shm` as above, or add `--tmpfs /tmp` to `runArgs`.
- By default it exposes a FIFO: nothing hits disk, but it can be read once, so tools that read
  the file twice or `stat` it break. `--no-fifo` writes a 0600 plaintext file instead.

### Start and end a session

```
devbox-secrets unlock   # host: prompts for the box key passphrase, writes the key to tmpfs
devbox-secrets lock     # host: removes the key file
devbox-secrets status   # host side, plus a check from inside the container
```

- `unlock` and `lock` only create or remove the key **file inside the existing directory**
  (write with umask 077 to a temp file in the same directory, then `mv`). Never delete and
  recreate the directory: the container's bind mount keeps pointing at the old one, and the box
  would stay "locked" until restart.
- Logout does not reliably clear the key: with `loginctl enable-linger` (common for rootless
  Podman) the tmpfs survives. Run `lock` at the end of a session. tmpfs pages can also be
  swapped *(unverified)*.
- While locked, `with-secrets` exits non-zero with
  `locked: run devbox-secrets unlock on the host`.

### Change or add a secret

On the host:

```
devbox-secrets edit boutique dev      # sops opens the decrypted file in $EDITOR, re-encrypts on save
git -C ~/src/secrets commit -am "..." && git -C ~/src/secrets push
```

- The container sees new values on the next `with-secrets` call (read-only bind mount of the
  host clone). No rebuild and no restart. Running processes keep their old environment.
- `sops edit` writes decrypted content to a temp file for the editor. `devbox-secrets edit`
  sets `TMPDIR=$XDG_RUNTIME_DIR`, uses an editor without swap or backup files, and does not
  use an `EDITOR="code --wait"` style editor.
- Changing a value here does not rotate it. Rotate at the provider first, then update the file.
- A new project or environment is a new file whose path matches a `.sops.yaml` rule.
  `devbox-secrets edit` requires the file to exist. Create it with
  `cd ~/src/secrets && sops <project>/<env>.env` (sops uses the matching `.sops.yaml` rule;
  an unmatched path is rejected), then commit.
- **Removing a recipient** (replacing the box key, or moving a file to admin-only): run
  `sops updatekeys`, then `sops rotate -i` on each file. `updatekeys` alone re-wraps the same
  data key. Old git commits stay decryptable with the old key, so if the box key was
  compromised, rotate every dev and preview value at the provider, not just the key.
- Do not edit a decrypted copy and re-encrypt it.

## Changes to this repo (implemented)

- `Dockerfile`: install `sops` (3.10 or later, which supports passphrase-protected age
  identities and, in the pinned version, `--same-process`) and `age`, with checksums.
- `devcontainer.json`:
  - `initializeCommand` runs `mkdir -p` on **both** the runtime directory and
    `~/src/secrets`: Podman fails the container start when a bind source is missing.
  - Use `${localEnv:XDG_RUNTIME_DIR:/run/user/1000}` with a default, since an unset variable
    would turn the mount source into `/devbox` *(default syntax unverified)*.
  - Mounts: `~/src/secrets` read-only at `/secrets`, the tmpfs directory read-only at
    `/run/devbox-secrets`. Remove the `devbox-secrets` volume mount.
- `post-create.sh`: drop the `chmod ~/.secrets` and `~/.gh_token` lines; merge the Claude
  settings template below. See the GH_TOKEN decision.
- Create the fine-grained GitHub token (no access to the secrets repo) and store it in
  `_global/dev.env` as `GH_TOKEN`.
- New: host script `devbox-secrets`, in-box script `with-secrets`.
- Claude settings template merged into `~/.claude/settings.json` (user settings, so paths are
  anchored with `//` for absolute):
  - `Read(//run/devbox-secrets/**)`
  - `Read(//workspaces/**/.env*)`, with an allowance for `.env.example`
  - `Bash(sops *)`: `with-secrets` calls sops internally and is unaffected
  - `Bash(with-secrets * -- env*)`, `Bash(with-secrets * -- printenv*)`, `Bash(* /run/devbox-secrets*)`
  - A relative `Read(/run/...)` pattern is anchored at the settings source and would protect
    nothing.
  - Read denials cover `cat`, `head`, `tail`, `sed` and redirections, but not a script that
    opens the file itself.
- A line in each project's CLAUDE.md or AGENTS.md: never print the environment or secret values.
- `design.md`: update *Known risks* ("every project reads the same secrets volume" still holds
  for the box key) and *Out of scope*.

## Decisions

1. **GH_TOKEN: use a fine-grained token that excludes the secrets repo.** `~/.gh_token` is
   "the path the projects expect" per `post-create.sh`, and agents use `gh` constantly, so the
   token stays available in the box (delivered through `with-secrets`/`_global`, with the
   `~/.gh_token` expectation to be replaced per project). If the token could push to the
   secrets repo, a compromised box could commit forged ciphertext (sops does not authenticate
   the writer and the admin public key is in `.sops.yaml`), for example replacing `prod.env`.
   Review the secrets repo diff on the host before using pulled changes.
2. **`preview.env` is readable by the box key** (encrypted to box key and admin key, as in the
   `.sops.yaml` rule above).
3. **No separate uid for secret-bearing commands.** They run as `dev`. It would only stop
   accidents, since `dev` has sudo, and it adds complexity.

## Limits

- **Agents can still print secrets.** Every process runs as `dev`, so `ps eww`,
  `cat /proc/<pid>/environ`, `with-secrets … -- env`, or
  `with-secrets … -- node -e 'console.log(process.env.X)'` put values in the transcript. The
  `deny` rules, the CLAUDE.md line and an optional PreToolUse hook reduce this. They are
  backstops against accidents, not a boundary, and a shell can bypass them.
- **While unlocked, anything running as `dev` can read the box key** and decrypt every dev file
  in the repo. The `dev` user has passwordless sudo and egress is unrestricted, so a prompt
  injection or hostile install script could exfiltrate them. Locking between sessions and
  keeping prod out of the box bound the exposure; they do not remove it.
- **No direnv auto-loading of secrets.** Claude's shells start from a snapshot of the shell
  setup, so a direnv hook would export decrypted values into every agent command and into the
  transcript. direnv is fine for non-secret variables.
- The box key protects all dev environments of all projects at once. Per-project keys would
  narrow that and cost more key management.
- **Other sops key sources are not cleared.** `with-secrets` sets `SOPS_AGE_KEY_FILE`, but
  `SOPS_AGE_KEY`, `SOPS_AGE_KEY_CMD` and `~/.config/sops/age/keys.txt` in the caller's
  environment still apply. A caller that holds the admin key can decrypt prod through them.
- `DEVBOX_SECRETS_DIR` must be an absolute path.
- Claude's OAuth login (`.credentials.json` in `devbox-claude`) stays in plaintext in its
  volume.
- Tools that regenerate plaintext, such as `vercel env pull` writing `.env.local`, defeat the
  scheme if used inside the box.

## Out of scope

- A credential-injecting egress proxy plus egress allowlist (the real fix for exfiltration of
  HTTP-style credentials; the container would hold placeholders only).
- Replacing Claude's OAuth credentials with `CLAUDE_CODE_OAUTH_TOKEN` through this mechanism.
- Per-project box keys.
- Vault or OpenBao, or Bitwarden as the store.
- Migrating existing projects. When a project moves over, its `.env*` files and `.bak` copies
  must be deleted, or a variable `with-secrets` does not set silently falls back to a stale
  file value; the old `devbox-secrets` volume should be removed.

## Manual verification (container level, after the first rebuild)

Shell tests (`bash tests/secrets/run.sh`) cover the scripts only. Check by hand:

- [ ] The image builds: sops/age install (checksums) and the `with-secrets` COPY.
- [ ] `${localEnv:XDG_RUNTIME_DIR:/run/user/1000}` resolves to the real runtime dir (the
      mount source exists and is the host `devbox` directory).
- [ ] The `dev` user can read the mounted `/run/devbox-secrets/age.key` (`keep-id` ownership).
- [ ] From a VS Code terminal: `with-secrets <project> dev -- true` works after `unlock` and
      fails with `locked: ...` after `lock`.
- [ ] `lock` then `unlock` on the host is visible in the running container (directory not
      recreated, no restart).
- [ ] The deny rules block `cat /run/devbox-secrets/age.key` and `sops -d`.
- [ ] Each project's tooling honors injected variables over `.env` files.
- [ ] `devbox-secrets status --container <name>` reports correctly with real podman.

## To verify when implementing

Not run: this was designed without a running Podman. The list above covers the
container-level items; the rest remain open.

- `${localEnv:XDG_RUNTIME_DIR}` is available to VS Code when it builds the mounts, with a
  fallback when it is not (Flatpak or snap VS Code may differ).
- File ownership of the tmpfs key inside the container under `--userns=keep-id`.
- The pinned sops supports `exec-env --same-process` and passphrase-protected age identities;
  the `age -p` flow (encrypt the identity with `age -p`, unlock with `age -d -o` under umask 077).
- Each project's tooling honors pre-set environment variables over `.env` files.
- Whether the host uses SELinux (mounts would need relabelling; the existing ones have none).
- Shell tests with throwaway keys: unlocked run works, locked run fails cleanly, the box key
  cannot decrypt a prod file, `exec-env` writes no plaintext to disk, quoting survives
  arguments with spaces and quotes, and values from a migrated `.env` match what the old
  loader produced.

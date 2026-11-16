# Changelog

All notable changes to devbox. Versions are git tags on `main`.

## [0.2.0] - 2026-11-16

### Added
- sops+age secrets: encrypted dotenv files per project and environment in a private host repo
  (`~/src/secrets`, mounted read-only at `/secrets`). Prod is encrypted to the admin key only.
- `devbox-secrets` host script: `unlock`, `lock`, `status [--container]`, `edit`. The
  passphrase-protected box key is unsealed to tmpfs and mounted read-only at `/run/devbox-secrets`.
- `with-secrets <project> <env> -- cmd`: runs one command with that environment's values via
  `sops exec-env --same-process`; nothing is written to disk.
- Claude `permissions.deny` rules for `.env*`, the key mount, `sops *`, and `env`/`printenv`
  through the wrapper, merged into `~/.claude/settings.json` on create.
- Pinned sops 3.13.3 and age 1.3.2, installed with verified checksums.
- Shell tests in `tests/secrets/` (`bash tests/secrets/run.sh`).
- `tests/verify-on-host.sh`: interactive wizard that verifies the setup from the host (sandbox
  container with the real mounts, passphrase flows, then the rebuilt devcontainer); `--from N` resumes.
- `VERSION` file.
- `.devcontainer/host/setup-secrets.sh`: host wizard for the one-time secrets setup (keys,
  passphrases, secrets repo, `.sops.yaml` with `dev`, `preview`, `local` and admin-only `prod`, first
  files, PATH link, unlock test, private remote). Re-runnable.
- `docs/secrets.md`: design, setup, limits and a manual verification checklist.

### Changed
- `shared.code-workspace` is generated at `/workspaces/shared.code-workspace` by
  `gen-workspace.sh` on every start; README no longer asks for manual entries.
- README: intro, audience, and secrets sections.
- VS Code port auto-forwarding is on (`remote.autoForwardPorts: true`; it was off in 0.1.0).

### Removed
- The `devbox-secrets` volume and the `~/.gh_token` link. `GH_TOKEN` now comes from
  `_global/dev.env` in the secrets repo.

### Migration
- Move each project's `.env*` files into the secrets repo, then delete the plaintext copies.
- Remove the old volume: `podman volume rm devbox-secrets`.

### Known limits
- While unlocked, anything running as `dev` can read the box key, and agents can print their own
  environment. See Limits in `docs/secrets.md`.

## [0.1.0]

- Initial devcontainer: rootless Podman, Debian slim, Claude Code, Node LTS, gh, with Claude
  state in named volumes.

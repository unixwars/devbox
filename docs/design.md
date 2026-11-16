# devbox design

## Goal

One development container for all local projects, light on a laptop (i5-1235U, 12c, 
16 GB), where Claude state and secrets survive rebuilds.

## Decisions

| Decision | Choice | Traded away |
|---|---|---|
| Runtime | Rootless Podman | Ports below 1024 and some kernel features; needs `keep-id` for file ownership |
| Containers | One, not one per project | Projects share installed tools and a filesystem; secrets are not isolated between them |
| Network | Unrestricted, no gateway or proxy | No egress allowlist (the o3s approach); saves two idle containers and a lot of setup |
| Nested containers | None | An agent cannot start a project's database inside the box; use a sibling container or the shared Neon DB |
| Base | `debian:stable-slim` plus a short package list | Anything else is `sudo apt install` and is lost on rebuild; add it to the Dockerfile |
| Node | devcontainer `node` feature, LTS | Pinned by feature, not by project |
| Claude | `npm -g` at create, state in volumes | Reinstall on every rebuild, cheap thanks to the npm cache volume |
| Playwright | Opt-in script | Not ready out of the box; avoids roughly 500 MB and a RAM spike for projects that do not need it |
| Projects | Bind mount of `~/src/projects` at `/workspaces` | Only that subdirectory is visible |
| Limits | 8 GB, 6 CPUs | A runaway dev server is killed or throttled before it freezes the laptop |

## Persistence

Named volumes for `~/.claude`, `~/.agents`, `~/.npm` and `~/.cache`.
`CLAUDE_CONFIG_DIR` points at `~/.claude` so `.claude.json` is inside the volume too.
Mount points are created in the image, owned by the user, so a fresh volume starts with
the right ownership.

Secrets are not in a volume: sops+age files in a host git repo (`~/src/secrets`, mounted
read-only), decrypted by a box key that the host unseals onto tmpfs (`devbox-secrets unlock`)
and that `with-secrets` uses per command. See `docs/secrets.md`.

## Known risks

- Wrong file ownership on the host if the uid is not 1000 and `keep-id` is not adjusted.
- Claude memory is keyed by path; renaming a project folder orphans its memory.
- The box key decrypts all dev and preview secrets of all projects while unlocked, and agents can print their own environment.
- `--memory` and `--cpus` are ignored or rejected without cgroup v2 delegation.
- Not run: this was written without Podman available. First build may need small fixes.

## Out of scope

Egress allowlist, secret injection proxy, nested Podman or Docker, other agents than Claude.

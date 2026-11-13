<p align="center"><img src="docs/assets/logo.webp" alt="devbox logo" width="640" /></p>

# devbox

One rootless-Podman devcontainer shared by all local projects. Debian slim, Claude Code,
Node LTS, gh. Claude's memory, plugins, skills and agents live in named volumes and survive rebuilds.
Secrets are sops+age files on the host, see Secrets.

## Why?

Agents are great for coding, but my laptop holds my digital life and it would be unwise
to hand over the keys to the castle. I got tired of spinning up a different devcontainer
for each project I'm working on, so this brings us here. I also wanted to make sure I kept
my secrets properly persisted under source control, without worrying about leaks, loss,
or having to constantly scrub them because Claude decide to parse whole gitignored files
and suddenly making them visible in the session.

## What?

This project gives you isolation between your development box and the rest of your data, 
keeps your development and production secrets segregated by audience, and solves the
following problems:

- Accidental leaks when an agent reads a .env file, the values enter the session transcript, and they have to be rotated.
- Logistics. Secrets sit in gitignored files per project and can be lost, with no single place to update them.
- Plaintext at rest in a volume readable by anything running in the box.

It reduces accidents; it does not stop a determined exfiltration or an agent that prints its own environment. 

## Who?

This project is for you if:

- you want to keep your devbox isolated from the rest of your data.
- you want to keep your secrets stored, encrypted, under source control.
- you don't want to spend hours researching.
- you need a lightweight process that suits a solo developer workflow.
- you're OK with agents seeing each other's code, and potentially secrets to their respective dev environments.
- you care about production secrets being kept 

This project is not for you if:

- you're looking to gate everything your agent does, including network access.
- you're trying to defend against hostile agents.
- you're orchestrating complex workflows where agents interact with whole development teams.
- you need complete isolation between projects.
- you need to inject credentials on the fly, including secrets, so your agents never actually see them.

## Setup (once)

1. Install Podman and the VS Code Dev Containers extension.
2. In VS Code settings set `dev.containers.dockerPath` to `podman`.
3. Create the projects folder and put or clone your projects in it:
   `mkdir -p ~/src/projects`. This is the only part of `~/src` the container can see.
   To use another subdirectory, edit `workspaceMount` in `.devcontainer/devcontainer.json`.
4. Check `id -u` and `id -g`. If either is not 1000, change `--userns=keep-id:uid=...,gid=...`
   in `devcontainer.json` and `UID`/`GID` in the Dockerfile.
5. Open this folder in VS Code and run "Dev Containers: Reopen in Container".
6. In the container, File > Open Workspace from File > `/workspaces/shared.code-workspace`.
   You do not add projects by hand: `gen-workspace.sh` runs on every container start and
   lists each repo under `/workspaces`, plus the git worktrees it finds for them. Folders you
   add or rename by hand, and the rest of the file, are kept; entries whose folder is gone are
   dropped. If you put comments in the file it is left untouched, so keep it plain JSON.

## Volumes

| Volume | Mounted at | Holds |
|---|---|---|
| devbox-claude | ~/.claude | Claude config, memory, plugins, skills |
| devbox-agents | ~/.agents | agents |
| devbox-npm | ~/.npm | npm download cache |
| devbox-cache | ~/.cache | Playwright browsers and other caches |

`podman volume ls` lists them. A rebuild keeps them. `podman volume rm devbox-claude`
deletes that state for good.

## Secrets

Secrets live encrypted in a private git repo at `~/src/secrets` (read-only at `/secrets`).
On the host `devbox-secrets unlock` puts the box key on tmpfs; in the box
`with-secrets <project> <env> -- <cmd>` runs a command with the values in its environment.
Setup, workflow and limits: `docs/secrets.md`.

## Playwright (opt-in)

`bash /devbox/.devcontainer/install-playwright.sh /workspaces/<project>`. Run again after a
rebuild, since the system libraries live in the container layer.

## Limits

The container is capped at 8 GB and 6 CPUs (`runArgs`). Rootless limits need cgroup v2
delegation, supported by any modern systemd-based Linux distributions default (such as
Fedora 31+, Arch Linux, Debian 11+, Ubuntu 21.10+, and RHEL 9+) out of the box.
systemd 244 or newer is needed for non-root cgroup delegation If Podman complains, remove
the two flags.

See `docs/design.md` for the decisions behind this.

#!/usr/bin/env bash
# Runs after the container is created. Idempotent and quick: heavy tools are opt-in.
set -euo pipefail

# Claude Code deny rules for secrets (merged into the persisted settings; idempotent)
bash /devbox/.devcontainer/merge-claude-settings.sh /devbox/.devcontainer/claude-settings.template.json "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

# Let `git push` over SSH reach github.com without a prompt
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keyscan -t ed25519,rsa github.com 2>/dev/null >> ~/.ssh/known_hosts || true
sort -u -o ~/.ssh/known_hosts ~/.ssh/known_hosts

# Claude Code (the npm cache is a volume, so this is fast after the first time)
npm install -g @anthropic-ai/claude-code

# gh tab completion
gh completion -s bash | sudo tee /etc/bash_completion.d/gh >/dev/null

echo "devbox ready. Playwright is opt-in: bash /devbox/.devcontainer/install-playwright.sh"

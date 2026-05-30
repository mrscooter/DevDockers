#!/bin/bash
set -euo pipefail

# Convenience wrapper: open an interactive zsh shell in the running dev-env container.
# Requires the container to be up (`./up.sh` / `docker compose up -d`).
# TERM/COLORTERM are forced because `docker exec` otherwise hands the shell a
# colorless terminal (TERM=dumb/xterm, no COLORTERM), which makes Claude Code's
# menu-selection highlight (and other TUI colors) collapse into the background.
docker compose exec \
  -e TERM=xterm-256color \
  -e COLORTERM=truecolor \
  dev-env zsh

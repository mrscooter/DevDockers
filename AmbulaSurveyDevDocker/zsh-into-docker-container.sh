#!/bin/bash
set -euo pipefail

# Convenience wrapper: open an interactive zsh shell in the running dev-env container.
# Requires the container to be up (`docker compose up -d`).
docker compose exec dev-env zsh

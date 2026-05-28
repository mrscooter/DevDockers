#!/bin/bash
set -euo pipefail

# Apply git identity from environment (updates on every container start, so changes
# to DEV_NAME/DEV_EMAIL in .env take effect by just restarting the container).
git config --global user.name  "${DEV_NAME}"
git config --global user.email "${DEV_EMAIL}"

# Sane defaults so common git ops behave well.
git config --global init.defaultBranch master
git config --global pull.rebase false

exec "$@"

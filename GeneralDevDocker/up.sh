#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Grant X access (loud preflight; non-fatal if no display - the container is still
# useful for CLI work), then start the container detached. Extra args pass through
# to `docker compose up`, e.g.  ./up.sh --build  or  ./up.sh --force-recreate.
./xhost-setup.sh || echo "WARNING: continuing without X access - GUI apps (Typora, ...) won't open until a display is available." >&2

exec docker compose up -d "$@"

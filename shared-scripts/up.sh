#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Grant X access (loud preflight; non-fatal if no display - the container is still
# useful for CLI work), then start the container detached. Extra args pass through
# to `docker compose up`, e.g.  ./up.sh --build  or  ./up.sh --force-recreate.
./xhost-setup.sh || echo "WARNING: continuing without X access - GUI apps in the container won't open until a display is available." >&2

# This container's ssh-agent socket dir and SSH key dir (see ssh-agent-paths.sh). The
# socket dir must exist before the container starts, or the bind mount creates it
# root-owned.
# shellcheck source=ssh-agent-paths.sh
. ./ssh-agent-paths.sh
mkdir -p -m 700 "${ssh_sock_dir}" "${ssh_key_dir}"

docker compose up -d "$@"

if [ -z "$(ssh_keys)" ]; then
  echo
  echo "NOTE: SSH key directory is empty (no private key with its .pub): ${ssh_key_dir}"
  echo "      Add keys there if you want ssh / git inside the container to use them;"
  echo "      ./zsh-into-docker-container.sh then loads them (asking for the passphrase once)."
fi

#!/bin/bash
set -euo pipefail

# Generate this container's own SSH identity (ed25519) in ~/.ssh. A dedicated key keeps
# host keys out of the container and can be revoked on its own if it ever leaks. Run once,
# interactively, and set a passphrase: it is what protects the key file at rest. The key
# persists in the home volume (gone after `docker compose down -v`).
#
# Usage:
#   generate-ssh-key
#
# keychain (configured in ~/.zshrc) loads it in each new zsh session, asking for the
# passphrase once per container start.

key="${HOME}/.ssh/id_ed25519"
share_dir="${HOME}/fast_share"
shared_pub="${share_dir}/GeneralDevDocker_id_ed25519.pub"

if [ -e "${key}" ]; then
  echo "ERROR: ${key} already exists - refusing to overwrite it." >&2
  echo "To replace it, delete it (and its .pub) first, and revoke the old public key wherever it is registered." >&2
  exit 1
fi

mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"

ssh-keygen -t ed25519 -C "devuser@GeneralDevDocker $(date +%F)" -f "${key}"

if ssh-keygen -y -P '' -f "${key}" >/dev/null 2>&1; then
  echo
  echo "WARNING: the key has NO passphrase - anything that can read ~/.ssh can use it anywhere." >&2
  echo "  Add one with:  ssh-keygen -p -f ${key}" >&2
fi

if [ -d "${share_dir}" ]; then
  cp "${key}.pub" "${shared_pub}"
  echo
  echo "Public key also copied to the host bridge: ${shared_pub}"
fi

echo
echo "Public key:"
cat "${key}.pub"
echo
echo "Register it on GitHub (Settings > SSH and GPG keys) / GitLab (Preferences > SSH Keys),"
echo "or as a per-repo deploy key for narrower access."
echo "Open a new zsh session to load it via keychain."

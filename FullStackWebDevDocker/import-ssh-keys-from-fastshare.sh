#!/bin/bash
set -euo pipefail

# Copy a private SSH key from the host->container bridge (~/fast_share) into the
# container-private ~/.ssh, with correct permissions. Use this instead of bind-
# mounting host ~/.ssh, so only the keys you deliberately hand-carry ever reach the
# container - company/other keys stay out unless you explicitly import them.
#
# Usage:
#   import-ssh-keys-from-fastshare <name>   # e.g. import-ssh-keys-from-fastshare id_ed25519
#   import-ssh-keys-from-fastshare          # lists candidate keys sitting in ~/fast_share
#
# After import, keychain (configured in ~/.zshrc) auto-loads ~/.ssh/id_* on each new
# zsh session, so a fresh shell picks the key up.

share_dir="${HOME}/fast_share"
ssh_dir="${HOME}/.ssh"

if [ $# -eq 0 ]; then
  echo "Private keys available in ${share_dir}:"
  keys=$(find "${share_dir}" -maxdepth 1 -type f -name 'id_*' ! -name '*.pub' -printf '  %f\n' 2>/dev/null)
  if [ -n "${keys}" ]; then
    printf '%s\n' "${keys}"
  else
    echo "  (none - drop a private key into ${share_dir} from the host first)"
  fi
  echo
  echo "Then run:  import-ssh-keys-from-fastshare <name>"
  exit 0
fi

name="$1"
src="${share_dir}/${name}"

if [ ! -f "${src}" ]; then
  echo "ERROR: ${src} not found. Drop the private key into ${share_dir} from the host first." >&2
  exit 1
fi

mkdir -p "${ssh_dir}"
chmod 700 "${ssh_dir}"
cp "${src}" "${ssh_dir}/${name}"
chmod 600 "${ssh_dir}/${name}"

# Public key is optional for the SSH client; copy it too if it was brought along.
if [ -f "${src}.pub" ]; then
  cp "${src}.pub" "${ssh_dir}/${name}.pub"
  chmod 644 "${ssh_dir}/${name}.pub"
fi

echo "Imported ${name} -> ${ssh_dir}/${name}"
echo "Open a new zsh session (or run: keychain --eval ${ssh_dir}/${name}) to load it."
echo "Tip: delete ${src} from fast_share if you do not want the key lingering on the bridge."

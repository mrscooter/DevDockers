#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Convenience wrapper: open an interactive zsh shell in the running dev-env container.
# Requires the container to be up (`./up.sh`).

# Host-side ssh-agent, one per container (paths: ssh-agent-paths.sh): compose.yaml mounts
# its socket dir and points SSH_AUTH_SOCK there, so private keys never enter the
# container - it can only ask the agent to sign. Started on first use and kept until
# reboot. Each key is added once, asking for its passphrase here on the host (plus sudo
# for root-owned key files); it counts as loaded when its .pub fingerprint is in the agent.
# shellcheck source=ssh-agent-paths.sh
. ./ssh-agent-paths.sh
export SSH_AUTH_SOCK="${ssh_sock_dir}/agent.sock"
mapfile -t keys < <(ssh_keys)
if (( ${#keys[@]} )); then
  agent_rc=0
  ssh-add -l >/dev/null 2>&1 || agent_rc=$?
  if [ "${agent_rc}" -eq 2 ]; then
    rm -f "${SSH_AUTH_SOCK}"
    ssh-agent -a "${SSH_AUTH_SOCK}" >/dev/null
  fi
  loaded="$(ssh-add -l 2>/dev/null || true)"
  for key in "${keys[@]}"; do
    fp="$(ssh-keygen -lf "${key}.pub" 2>/dev/null | awk '{print $2}')"
    if [ -n "${fp}" ] && grep -qF "${fp}" <<<"${loaded}"; then
      continue
    fi
    if [ -r "${key}" ]; then
      ssh-add "${key}" || echo "WARNING: could not add ${key} to the agent." >&2
    else
      sudo SSH_AUTH_SOCK="${SSH_AUTH_SOCK}" ssh-add "${key}" || echo "WARNING: could not add ${key} to the agent." >&2
    fi
  done
fi

# TERM/COLORTERM are forced because `docker exec` otherwise hands the shell a
# colorless terminal (TERM=dumb/xterm, no COLORTERM), which makes Claude Code's
# menu-selection highlight (and other TUI colors) collapse into the background.
docker compose exec \
  -e TERM=xterm-256color \
  -e COLORTERM=truecolor \
  dev-env zsh

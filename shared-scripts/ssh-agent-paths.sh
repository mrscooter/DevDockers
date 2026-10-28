# shellcheck shell=bash
# Sourced (from the dev-docker's directory) by up.sh and zsh-into-docker-container.sh:
# where this container's host-side ssh-agent keeps its socket and which keys it loads. One
# agent per container, named after its container_name as compose resolves it (shell env,
# .env, compose.yaml default), so the socket dir matches the one compose.yaml mounts.
dotenv() { sed -n "s/^$1=//p" .env 2>/dev/null | tail -n 1 | tr -d "\"'"; }
container="$(docker compose config | sed -n 's/^    container_name: //p')"
ssh_sock_dir="${HOME}/.local/state/${container}-ssh"
ssh_key_dir="$(dotenv SSH_KEY_DIR)"
ssh_key_dir="${ssh_key_dir:-${HOME}/.ssh/${container}}"
ssh_key_dir="${ssh_key_dir/#\~/${HOME}}"

# Private keys in ssh_key_dir with their .pub next to them: the ones the agent loads.
ssh_keys() {
  local pub
  for pub in "${ssh_key_dir}"/*.pub; do
    if [ -e "${pub%.pub}" ]; then
      printf '%s\n' "${pub%.pub}"
    fi
  done
}

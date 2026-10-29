#!/bin/bash
set -euo pipefail

# Apply git identity from environment (updates on every container start, so changes
# to DEV_NAME/DEV_EMAIL in .env take effect by just restarting the container).
git config --global user.name  "${DEV_NAME}"
git config --global user.email "${DEV_EMAIL}"

# Sane defaults so common git ops behave well.
git config --global init.defaultBranch master
git config --global pull.rebase false
git config --global push.autoSetupRemote true

# --- nicnajder-general-utils checkout ----------------------------------------
# Cloned into ~/Tools on first start; on every start its master is brought up to date:
# fast-forwarded in place when checked out, otherwise only the master ref moves, so
# switching to it gives the current state. Origin is the SSH address for manual
# pull/push, but this update fetches anonymously over HTTPS: at container start the
# host-side ssh-agent often has no keys loaded yet (zsh-into-docker-container.sh loads
# them). Never fatal: the container must start offline or with a diverged master too.
utils_https=https://github.com/mrscooter/nicnajder-general-utils.git
utils_ssh=git@github.com:mrscooter/nicnajder-general-utils.git
utils_dir="${HOME}/Tools/nicnajder-general-utils"
update_utils_repo() {
  if [ ! -e "${utils_dir}" ]; then
    mkdir -p "${HOME}/Tools" && git clone -q "${utils_https}" "${utils_dir}" || return
  fi
  git -C "${utils_dir}" remote set-url origin "${utils_ssh}" || return
  git -C "${utils_dir}" fetch -q "${utils_https}" +refs/heads/master:refs/remotes/origin/master || return
  if [ "$(git -C "${utils_dir}" symbolic-ref -q --short HEAD)" = master ]; then
    git -C "${utils_dir}" merge -q --ff-only origin/master
  else
    git -C "${utils_dir}" fetch . origin/master:master
  fi
}
update_utils_repo || echo "[utils-repo] WARNING: could not clone/update ${utils_dir}"

# --- micro editor defaults ---------------------------------------------------
# Soft-wrap at the screen edge on word boundaries. Lives in the home volume, which
# masks anything baked into the image after first creation, so it is set here on
# every start. Fills missing keys only, leaving any user overrides intact. A file that is
# not strict JSON (micro also accepts comments / trailing commas) is left untouched: the
# parse error fails the script and the warning below prints.
python3 - "${HOME}/.config/micro/settings.json" <<'PY' || echo "[micro-defaults] WARNING: could not write micro settings"
import json, os, sys
p = sys.argv[1]
os.makedirs(os.path.dirname(p), exist_ok=True)
d = json.load(open(p)) if (os.path.exists(p) and os.path.getsize(p)) else {}
changed = False
for k in ("softwrap", "wordwrap"):
    if k not in d:
        d[k] = True
        changed = True
if changed:
    json.dump(d, open(p, "w"), indent=4)
PY

exec "$@"

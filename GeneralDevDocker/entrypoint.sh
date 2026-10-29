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

# --- Claude bootstrap --------------------------------------------------------
# Set up this user's personal Claude config INSIDE the container's home volume with
# the utils repo's own installer (install.sh claude: CLAUDE.md + general rules, a
# container-local LOCAL-CLAUDE.md, the status line, the ncn plugin with the skills),
# without baking anything machine-specific into the image. The Claude *login* is NOT
# handled here - it is container-local and separate from the host's: run claude and
# log in once, it persists in the home volume.
#
# Runs on every start: the installer is idempotent, and --yes lets it replace what is
# in its way (moved to the clone's backups/) instead of prompting with nobody at the
# terminal. New commits are not pulled here: git pull in the clone, as on any machine.
# Any failure (e.g. no network for the first clone) warns but never blocks the start.
claude_bootstrap() {
  local repo="${CLAUDE_UTILS_REPO:-https://github.com/mrscooter/nicnajder-general-utils.git}"
  local dir="${CLAUDE_UTILS_DIR:-/home/devuser/Tools/nicnajder-general-utils}"

  if [ ! -d "${dir}/.git" ]; then
    echo "[claude-bootstrap] cloning ${repo} -> ${dir}"
    mkdir -p "$(dirname "${dir}")"
    git clone "${repo}" "${dir}" || return
  fi
  "${dir}/install.sh" --yes claude
}

if [ "${CLAUDE_BOOTSTRAP:-true}" = "true" ]; then
  claude_bootstrap || echo "[claude-bootstrap] WARNING: setup failed, Claude instructions/skills" \
    "may be missing; restart the container or run install.sh claude in the utils clone"
fi

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

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
# Wire up this user's personal Claude setup INSIDE the container's home volume,
# without baking anything machine-specific into the image:
#   1. clone the public utils repo (skills + universal instructions),
#   2. symlink its GLOBAL-GENERAL-CLAUDE.md + every skill into ~/.claude,
#   3. write a ~/.claude/CLAUDE.md that imports only the universal rules.
# The Claude *login* is NOT handled here - it is container-local and separate from
# the host's: run claude and log in once, it persists in the home volume.
#
# Idempotent: by default each step is "create only if absent", so it is a no-op on
# every start after the first (the home volume persists the results). Set
# CLAUDE_BOOTSTRAP_FORCE=true to git-pull the repo, overwrite the generated
# CLAUDE.md, and re-point the symlinks. Any failure here (e.g. no network) warns
# loudly but never blocks container start - so the explicit guards below, not
# `set -e`, are what keep a failed clone from producing broken symlinks (set -e is
# suppressed inside a function invoked with `|| ...`).
claude_bootstrap() {
  local repo="${CLAUDE_UTILS_REPO:-https://github.com/mrscooter/nicnajder-general-utils.git}"
  local dir="${CLAUDE_UTILS_DIR:-/home/devuser/Tools/nicnajder-general-utils}"
  local force="${CLAUDE_BOOTSTRAP_FORCE:-false}"
  local claude_home="${HOME}/.claude"

  # Create a symlink honoring force (re-point) vs default (only if nothing is there,
  # treating a broken symlink as "there" so we do not error trying to clobber it).
  _bootstrap_link() {
    local src="$1" dst="$2"
    if [ "${force}" = "true" ]; then
      ln -sfn "${src}" "${dst}"
    elif [ ! -e "${dst}" ] && [ ! -L "${dst}" ]; then
      ln -s "${src}" "${dst}"
    fi
  }

  # 1. Clone (or, with FORCE, refresh) the utils repo.
  if [ ! -d "${dir}/.git" ]; then
    echo "[claude-bootstrap] cloning ${repo} -> ${dir}"
    mkdir -p "$(dirname "${dir}")"
    # Full (not shallow) clone: the repo is tiny, and a shallow clone can make a
    # later FORCE `git pull --ff-only` fail to fast-forward across the shallow edge.
    git clone "${repo}" "${dir}"
  elif [ "${force}" = "true" ]; then
    echo "[claude-bootstrap] FORCE: git pull in ${dir}"
    git -C "${dir}" pull --ff-only
  fi

  # If the repo still is not here (clone failed, e.g. no network), say so loudly and
  # stop: the symlink steps would no-op on the missing source anyway, and we must not
  # hide the reason skills/instructions are absent. The generated CLAUDE.md (step 3)
  # is independent, so it is still written below.
  if [ ! -d "${dir}/.git" ]; then
    echo "[claude-bootstrap] WARNING: utils repo not present at ${dir} (clone failed?)." \
         "Skills + universal instructions will be MISSING until it is cloned;" \
         "fix connectivity and restart, or set CLAUDE_BOOTSTRAP=false to silence."
  fi

  # 2. Symlink the universal instructions + every skill into ~/.claude. These guards
  # also mean a failed clone (repo absent) simply skips linking, never breaks it.
  mkdir -p "${claude_home}/skills"

  local universal_src="${dir}/claude/GLOBAL-GENERAL-CLAUDE.md"
  [ -f "${universal_src}" ] && _bootstrap_link "${universal_src}" "${claude_home}/UNIVERSAL_CLAUDE.md"

  if [ -d "${dir}/claude/skills" ]; then
    for skill in "${dir}"/claude/skills/*/; do
      [ -d "${skill}" ] || continue
      _bootstrap_link "${skill%/}" "${claude_home}/skills/$(basename "${skill}")"
    done
  fi

  # 3. Write the global CLAUDE.md (Mercury-free; imports the universal rules only).
  if [ "${force}" = "true" ] || { [ ! -e "${claude_home}/CLAUDE.md" ] && [ ! -L "${claude_home}/CLAUDE.md" ]; }; then
    cat > "${claude_home}/CLAUDE.md" <<'EOF'
# Global Instructions

Universal rules (all projects) live in an external repo, resolved via `~/.claude/`:
- @UNIVERSAL_CLAUDE.md -> nicnajder-general-utils/claude/GLOBAL-GENERAL-CLAUDE.md

**Symlink integrity:** this import, and the personal skills under `~/.claude/skills/`,
resolve through symlinks into the cloned utils repo. A broken one (the repo not present
at its expected path) makes the import silently yield nothing. If this file's imported
content seems missing or empty, or a referenced skill will not load, STOP and loudly
tell the user; do not silently proceed with missing instructions.
EOF
  fi

  # 4. Status line: symlink the shared script and point settings.json at it (only if
  # the utils repo ships claude/statusline-command.sh; absent -> simply skipped).
  local statusline_src="${dir}/claude/statusline-command.sh"
  if [ -f "${statusline_src}" ]; then
    _bootstrap_link "${statusline_src}" "${claude_home}/statusline-command.sh"
    python3 - "${claude_home}/settings.json" <<'PY' || echo "[claude-bootstrap] WARNING: could not set statusLine in settings.json"
import json, os, sys
p = sys.argv[1]
try:
    d = json.load(open(p)) if (os.path.exists(p) and os.path.getsize(p)) else {}
except Exception:
    d = {}
want = {"type": "command", "command": "bash ~/.claude/statusline-command.sh"}
if d.get("statusLine") != want:
    d["statusLine"] = want
    json.dump(d, open(p, "w"), indent=2)
PY
  fi

  echo "[claude-bootstrap] done"
}

if [ "${CLAUDE_BOOTSTRAP:-true}" = "true" ]; then
  claude_bootstrap || echo "[claude-bootstrap] WARNING: bootstrap failed; continuing without it"
fi

# --- micro editor defaults ---------------------------------------------------
# Soft-wrap at the screen edge on word boundaries. Lives in the home volume, which
# masks anything baked into the image after first creation, so it is set here on
# every start. Fills missing keys only, leaving any user overrides intact.
python3 - "${HOME}/.config/micro/settings.json" <<'PY' || echo "[micro-defaults] WARNING: could not write micro settings"
import json, os, sys
p = sys.argv[1]
os.makedirs(os.path.dirname(p), exist_ok=True)
try:
    d = json.load(open(p)) if (os.path.exists(p) and os.path.getsize(p)) else {}
except Exception:
    d = {}
changed = False
for k in ("softwrap", "wordwrap"):
    if k not in d:
        d[k] = True
        changed = True
if changed:
    json.dump(d, open(p, "w"), indent=4)
PY

exec "$@"

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

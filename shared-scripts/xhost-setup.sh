#!/bin/bash
set -euo pipefail

# Grant this host user's UID access to this session's X server. The container runs as
# the same UID (USER_ID in .env) and connects through the mounted /tmp/.X11-unix socket,
# so its GUI apps can open windows. Narrower than `xhost +local:`, which admits any local
# UID. Covers Xorg and Wayland's XWayland. Idempotent; ./up.sh runs it each start.

if [ -z "${DISPLAY:-}" ]; then
  echo "ERROR: \$DISPLAY is not set - no X server to talk to. GUI apps in the container need a graphical session (Xorg, or Wayland with XWayland)." >&2
  exit 1
fi

if ! command -v xhost >/dev/null 2>&1; then
  echo "ERROR: 'xhost' not found - install it (Debian/Ubuntu: sudo apt install x11-xserver-utils)." >&2
  exit 1
fi

if ! xhost >/dev/null 2>&1; then
  echo "ERROR: cannot reach the X server at DISPLAY=$DISPLAY (on Wayland, ensure XWayland is running)." >&2
  exit 1
fi

xhost "+SI:localuser:$(id -un)" >/dev/null
echo "Granted X access to UID $(id -u) (xhost +SI:localuser:$(id -un)) for DISPLAY=$DISPLAY."

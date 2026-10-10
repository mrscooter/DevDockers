#!/bin/bash
set -euo pipefail

# Grant local clients (incl. Docker containers using the mounted /tmp/.X11-unix
# socket) access to this session's X server, so GUI apps in the container can open
# windows. Covers Xorg and Wayland's XWayland. Idempotent; ./up.sh runs it each start.

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

xhost +local: >/dev/null
echo "Granted local X access (xhost +local:) for DISPLAY=$DISPLAY."

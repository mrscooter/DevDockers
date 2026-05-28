#!/bin/bash
set -euo pipefail

# Allow X11 connections from local Docker containers. Must be run once per host
# session (after each login/reboot) before launching WebStorm from inside the container.
xhost +local:docker

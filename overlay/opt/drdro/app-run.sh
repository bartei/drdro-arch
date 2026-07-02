#!/bin/bash
# Launcher: run the Kivy app fullscreen on KMS/DRM as root, no display server.
set -eu
export HOME=/root
export KCFG_KIVY_LOG_DIR=/var/log/drdro
export KCFG_KIVY_LOG_MAXFILES=30
export SDL_VIDEODRIVER=kmsdrm
export KIVY_GL_BACKEND=sdl2
mkdir -p /var/log/drdro
cd /opt/drdro/app
source .venv/bin/activate
# Hand off from the Plymouth splash (kept until now) to the app — no-op if Plymouth isn't installed.
command -v plymouth >/dev/null 2>&1 && plymouth quit --retain-splash 2>/dev/null || true
exec python -m dro.main

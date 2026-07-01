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
exec python -m dro.main

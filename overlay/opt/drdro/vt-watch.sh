#!/bin/bash
# VT-switch handoff for the app. SDL2-classic muted the console keyboard and handled
# Ctrl+Alt+Fn itself (VT_ACTIVATE + drop DRM master on switch); sdl2-compat/SDL3's KMSDRM has no
# VT handling at all (libsdl-org/SDL#15166), so the kernel switches the VT but the app keeps DRM
# master and the screen stays frozen on the DRO. This watcher makes the display follow the VT:
# off tty1 -> stop the app (console becomes visible, logind's autovt spawns a login); back on
# tty1 -> restart it. Only restarts the app if it stopped it, so a deliberate
# `systemctl stop drdro` over SSH stays stopped.
set -u

stopped_by_me=0
while sleep 1; do
    vt="$(fgconsole 2>/dev/null)" || continue
    active="$(systemctl is-active drdro 2>/dev/null)"
    if [ "$vt" != 1 ] && [ "$active" = active ]; then
        systemctl stop drdro
        stopped_by_me=1
    elif [ "$vt" = 1 ] && [ "$stopped_by_me" = 1 ] && [ "$active" != active ]; then
        systemctl start drdro
        stopped_by_me=0
    fi
done

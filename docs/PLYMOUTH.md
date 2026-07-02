# Silent boot with Plymouth (drDRO splash)

Goal: boot with **no text** — just the drDRO logo + a boot-progress bar — then the app on tty1's
framebuffer. `Ctrl+Alt+F2` gives a login prompt on tty2 for maintenance.

**Status: ON by default (late splash), live-validated on the bench Pi 3B (2026-07-02).** The
theme is ported (`plymouth/theme/`), `build.sh`'s guarded block runs unless `ENABLE_PLYMOUTH=0`.
Verified: plymouthd paints ~12 s after power-on (root mount), the app starts ~5 s later and takes
over via `plymouth quit --retain-splash` (no console text anywhere; power-on → splash is a black
screen — killing that gap needs the early/initramfs splash below). Two refinements beyond the
original plan, both required in practice:
- `plymouth-quit.service` + `plymouth-quit-wait.service` are **masked** — otherwise systemd quits
  the splash at multi-user, seconds before Kivy paints (black gap). `app-run.sh` owns the quit.
- tty2 login relies on **`drdro-vt-watch.service`** (overlay): sdl2-compat/SDL3's KMSDRM has no VT
  handling (SDL2-classic did), so without the watcher the app never releases DRM master and
  Ctrl+Alt+F2 switches the VT invisibly.

```
ENABLE_PLYMOUTH=0 sudo -E ./build.sh     # opt OUT (verbose boot for debugging)
```

## The pieces (all wired in the guarded block)

1. **Package:** `plymouth`.
2. **Theme:** `plymouth/theme/{drdro.plymouth,drdro.script,splash.png,bar.png}` →
   `/usr/share/plymouth/themes/drdro/`, plus `plymouth/plymouthd.conf` → `/etc/plymouth/`
   (`Theme=drdro`). Logo is the drDRO mark reused from the Debian/ospi variant; the script centers
   it on black and grows a thin progress bar via `Plymouth.SetBootProgressFunction`.
3. **Quiet kernel cmdline** (`boot/cmdline.txt`, applied by the guarded block):
   `console=tty3 quiet loglevel=3 vt.global_cursor_default=0 logo.nologo splash plymouth.ignore-serial-consoles`
   — kernel console moves to **tty3** (out of sight), boot is quiet, no rainbow/cursor.
4. **No console on tty1:** `systemctl mask getty@tty1` — tty1 is left for Plymouth → the app.
   `Ctrl+Alt+F2` still works: systemd's `autovt@tty2` spawns a login on demand (default `NAutoVTs`).
5. **Handoff to the app with no black flash:** `app-run.sh` runs `plymouth quit --retain-splash`
   just before launching Kivy, so the splash stays until the DRO paints over it.

## Early vs late splash (the hardware-iteration bit)

- **Late (what the guarded block does first):** no initramfs changes. `plymouth-start.service` brings
  the splash up once systemd is running (after root mount). Simplest, low-risk — there's a second or
  two of firmware/kernel output before the splash. Good enough for a first cut.
- **Early (fully silent from power-on):** requires the `plymouth` + KMS hooks in the **initramfs** so
  the splash appears before the rootfs mounts. Since the linux-rpi kernel swap, the image already
  boots via an mkinitcpio initramfs (`initramfs initramfs-linux.img followkernel` is in the stock
  config.txt) — what's left is adding `plymouth` to mkinitcpio `HOOKS` (and ensuring the `vc4`/`drm`
  KMS modules load early) and rebuilding. This is the part to iterate on the actual boards — get
  "late" working first, then push the splash earlier.

## Verify on hardware
- Logo + progress bar visible from early boot; **no scrolling text** on the main display.
- App appears fullscreen with no black gap after the splash.
- `Ctrl+Alt+F2` → login prompt (tty2); `Ctrl+Alt+F1` back to the app.
- `journalctl -b` still has full logs (we only *hid* the console, `console=tty3`).

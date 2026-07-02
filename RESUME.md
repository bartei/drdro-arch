# drDRO-arch — RESUME (session handoff)

**Read this first when picking up in a new session.** Build/architecture detail is in
[`README.md`](README.md); silent-boot plan in [`docs/PLYMOUTH.md`](docs/PLYMOUTH.md).

## What this is
A **purpose-built Raspberry Pi appliance image** for the drDRO Kivy app (`drdro-software-f4`), built
on **Arch Linux ARM (ALARM)**. One dead-simple `build.sh`: unpack the ALARM `rpi-aarch64` tarball →
native `chroot` (on a `ubuntu-24.04-arm` runner, no qemu) → swap mainline kernel+U-Boot for
**linux-rpi** → `pacman -S` the runtime → **pyenv builds CPython 3.13** → `pip install` the app into
a baked venv (Kivy et al. as **wheels**) → assemble a 2-partition SD image. Repo:
`github.com/bartei/drdro-arch`. (Replaced NixOS — too big/fighty — and the parked Buildroot/Yocto
experiments in `github.com/bartei/drdro-os`.)

## Status as of 2026-07-01 (evening session)
Validated **on real Pi 3B hardware**: boots, app autostarts, hardware GL (VC4 V3D), **RS-485
serial works**, **USB touchscreen works** (QDtech MPI7003 1024×600), offline first boot,
`default`/`default` + SSH + passwordless sudo. Only known-bad: **onboard brcmfmac wifi** (below).

**The live hardware fixes are now BAKED into the repo** (this session — gathered from the live Pi
over SSH and ported):
- `build.sh`: kernel swap in the chroot — `pacman -Rdd uboot-raspberrypi linux-aarch64` →
  `pacman -S linux-rpi` (direct `kernel8.img` boot, no U-Boot, `cmdline.txt` authoritative,
  per-board dtb auto-select).
- `packages.txt`: **`mtdev`** added (THE touchscreen fix — Kivy's default `probesysfs` then
  auto-detects the panel, no Kivy config change; verified: live Kivy config is stock). Also
  `sdl2` → `sdl2-compat` (what Arch actually ships/live Pi has).
- `boot/config.txt`: replaced with **linux-rpi's stock file + our settings** appended under `[all]`
  (`enable_uart=1`, i2c/spi/audio dtparams), exactly as on the bench Pi, plus a deliberate
  `disable_splash=1` re-add (rainbow suppression; lost in the kernel-swap reset, harmless).
  Includes `initramfs initramfs-linux.img followkernel` (mkinitcpio initramfs is now the boot path).
- `boot/cmdline.txt`: `+ brcmfmac.roamoff=1` (as live; also added to the Plymouth cmdline variant).
- New overlay: `/etc/NetworkManager/conf.d/10-wifi-powersave.conf` (`wifi.powersave = 2` = off).

**Bloat pass DONE (same session): live rootfs 3203 → 1638 MB (−1.57 GB), verified across a
reboot** (app active, GL = VC4 V3D, `/dev/serial0` present). Applied live first, then baked
identically into `build.sh`:
- pacman + pip caches purged (609 + 37 MB — build.sh never cleaned them!).
- CPython test suite (145 MB) + static libpython.a (67 MB) removed from the pyenv install.
- gdb chain removed (~185 MB): base-devel→debugedit→gdb dragged in system python 3.14 (78 MB),
  boost-libs (58 MB), source-highlight. `-Rdd gdb texinfo groff`, then `-Rns` the orphans.
- Firmware: atheros (136 MB) + "other" (69 MB) dropped; KEEP broadcom (onboard) + realtek (USB
  dongles), marked `--asexplicit`.
- man/info/doc (~115 MB) + non-English locales (~155 MB) removed; pacman `NoExtract` keeps them
  out in the field.
- vim/vim-runtime/ex-vi-compat (44 MB) + ALARM leftovers (dhcpcd, netctl, dialog, wireless_tools,
  net-tools) removed. nano stays.
- HOSTAGES (checked, must keep): guile 55 MB (make links it), icu 45 MB (libxml2), llvm-libs
  161 MB (mesa V3D shaders), perl 63 MB (git).
- `BOOT_MB` 256 → 128 (boot content is ~66 MB).

**Rootfs auto-grow DONE (same session), live-tested on the bench Pi** (the old "auto-grows on
first boot" comment in build.sh had been false): new `drdro-growfs.service` + `/opt/drdro/
growfs.sh` in the overlay (enabled via shipped wants symlink), `cloud-guest-utils` (growpart) in
packages.txt. growpart grows p2 to the card, then online `resize2fs`. Stampless — runs every boot,
no-ops with growpart's NOCHANGE (exit 1) once full-size, so moving to a bigger card re-grows.
Live test: p2 4.8G → 29.5G on the 32 GB bench card, while mounted, then clean reboot with the
NOCHANGE path. Build-time root slack tightened (135%+256 → 115%+128 MB) since the card, not the
image, now provides field headroom.

**NOT yet verified in a fresh image**: the baked changes (kernel swap + slim-down) haven't been
through CI + a reflash yet. Next step: push/`gh workflow run build-arch`, flash, and check parity
with the live Pi (kernel `uname -r` ends `-rpi`, touch works, `/dev/serial0` exists, no console on
the UART, app runs, du roughly matches 1.6 GB).

## Wifi — SOLVED (2026-07-02): brcmfmac FWSUP offload was the culprit
**Fix (baked, overlay): `/etc/modprobe.d/brcmfmac.conf` → `options brcmfmac
feature_disable=0x82000`** (bit 13 = FWSUP in-firmware supplicant, bit 19 = SAE offload).
Live-proven: after reboot `iw list` stops advertising `4WAY_HANDSHAKE_STA_PSK`, and
`nmcli device wifi connect raspberry password raspberry3` — the exact command that always failed —
connected immediately (wlan0 `10.1.2.150`, 0% loss) on the multi-AP 2.4 GHz network.

Root cause, found by comparing against the known-good `ospi` Debian image (a pi-gen fork —
**RPi OS trixie**, NOT an "older stack" as previously assumed): kernels gate FWSUP identically
(checked rpi-6.12.y vs rpi-6.18.y sources), firmware identical (Cypress 7.45.98), NM comparable —
the delta is **wpa_supplicant 2.11 (Arch) vs 2.10 (Debian trixie)**. 2.11 started handing the
WPA2-PSK 4-way handshake to brcmfmac's in-firmware supplicant; the BCM43430's Cypress firmware
botches it, and because the handshake runs in firmware, the supplicant "never sees EAPOL" →
"Authentication timed out" + NM's misleading "Secrets were required". Debian's 2.10 never engages
the offload — that's the whole reason ospi worked. Known upstream:
https://bugzilla.redhat.com/show_bug.cgi?id=2302577 . This explains why every earlier experiment
(kernel swap, firmware swap, CCMP/TKIP, powersave, roamoff, iwd, wext) failed — none touched the
offload path. Note the earlier multi-AP theory is dead too (untested single-AP diagnostic is moot).
- BCM43430 is 2.4 GHz only — `raspberry5` (5 GHz) still can't work, by hardware.
- The app configures wifi via the python `nmcli` lib (shells out to `nmcli`; runs as root with
  `nmcli.disable_use_sudo()`) — verified end-to-end from the app venv on the slimmed image.
- Live-Pi debugging leftovers, deliberately NOT baked: `iwd` (can go now), the saved
  `raspberry.nmconnection` profile (site-specific; the UI creates these in the field).

## Double DHCP — SOLVED (2026-07-02): NetworkManager is the sole network owner
The image used to ship **both systemd-networkd (ALARM default) and NetworkManager enabled** — two
DHCP clients per port, so the bench Pi's ethernet held two leases at once (.124 + .129, the
"wandering IP"). Fixed live and baked into `build.sh`: **networkd + resolved + all their sockets
+ systemd-network-generator disabled** (`|| true` guard — socket names drift across systemd
releases), NM owns everything. DNS: without resolved, **NM writes /etc/resolv.conf** with the
DHCP-provided servers (nsswitch's nss-resolve falls back to plain dns automatically); build.sh now
also rm's the chroot-era static resolv.conf (1.1.1.1) from the image so first boot starts clean.
Live-verified across a reboot: one address per interface, DNS resolves, wifi + app fine. `iwd`
debug leftover also removed from the live Pi.

## VT switching (Ctrl+Alt+F2) — SOLVED (2026-07-02): drdro-vt-watch
On Debian it worked because **SDL2-classic** muted the console keyboard, handled Ctrl+Alt+Fn
itself and dropped DRM master on switch. Arch ships **sdl2-compat on SDL3**, whose KMSDRM has NO
VT handling (libsdl-org/SDL#15166): the kernel switches the VT fine (keyboard isn't even grabbed)
but the app keeps DRM master, so the screen stays frozen on the DRO — "can't go to tty2".
Fix (overlay): **`drdro-vt-watch.service`** + `/opt/drdro/vt-watch.sh` — polls `fgconsole`; off
tty1 → `systemctl stop drdro` (screen freed, logind autovt spawns a tty2 login); back on tty1 →
restart. Only restarts what it stopped, so a deliberate `systemctl stop drdro` over SSH sticks.
Remote-tested end-to-end with a **uinput virtual keyboard** emitting Ctrl+Alt+F2/F1 (fgconsole
follows, app stops/starts, getty@tty2 spawns). App takes ~2–3 s to release the screen (SDL
teardown). Physical-keyboard confirmation on the bench still pending.

## Test hardware / access
- Pi 3B on the bench: **Ethernet `10.1.2.129`**, **wifi `10.1.2.150`** (both NM; one address per
  interface since the NM-only switch). SSH: `ssh default@10.1.2.129` (pw `default`); `sudo -i`
  passwordless. Also `root`/`root`, `alarm`/`alarm`.
- Automate from this host (NixOS, no sshpass on PATH):
  `nix-shell -p sshpass --run 'sshpass -p default ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null default@10.1.2.129 "<cmd>"'`
- The live Pi ≈ what the repo now builds (kernel 6.18.37-1-rpi, mtdev, powersave conf), plus the
  wifi-debug leftovers listed above.
- App: `/opt/drdro/app` (git v1.3.0 + `.venv`), runs as root via `drdro.service`; logs in
  `/var/log/drdro/`. Kivy config `/root/.kivy/config.ini` (stock). App `config.ini`:
  `serial_port = /dev/serial0` (build.sh sed).

## Build & CI
```
gh workflow run build-arch -R bartei/drdro-arch          # or push to main
gh run list -R bartei/drdro-arch --limit 3
gh run download <run-id> -R bartei/drdro-arch -n drdro-arch-rpi-aarch64   # zip -> raw .img
sudo dd if=drdro-arch-rpi-aarch64.img of=/dev/sdX bs=4M conv=fsync status=progress
# Local (needs an aarch64 host, root): sudo ./build.sh  -> out/drdro-arch-rpi-aarch64.img
```
Watch a run to completion (external `jq` NOT on PATH — use `gh -q`):
`until [ "$(gh run view <id> -R bartei/drdro-arch --json status -q .status)" = completed ]; do sleep 30; done`

## Roadmap / open items
1. **CI-build + flash + verify the newly baked changes** (kernel swap, mtdev, slim-down, BOOT_MB
   128) — top priority.
2. ~~Double DHCP~~ SOLVED — NM sole owner; networkd/resolved disabled in build.sh (see above).
3. ~~Wifi~~ SOLVED — `feature_disable=0x82000` modprobe conf in overlay (see above). Firmware
   note stands: image ships broadcom + realtek wifi firmware only — if a unit ever needs an
   atheros/mediatek USB dongle, re-add that linux-firmware split.
4. ~~Bloat pass~~ DONE (see Status). Leftover on the live Pi only (not in the image): `iwd`
   (wifi-debug tool, kept for the hotspot diagnostic).
5. **Plymouth silent boot — ENABLED by default + live-validated** (late splash; docs/PLYMOUTH.md).
   Remaining refinement: **early splash** — add the `plymouth` mkinitcpio hook (+ early vc4 KMS)
   to cover the ~12 s black gap between power-on and root mount. Visual sign-off on the bench
   (splash look, progress bar) still pending user eyes.
6. **Universal Pi 3/4/5 image** — linux-rpi + firmware dtb auto-select makes this mostly a
   test-matrix problem now.
7. Serial: app repo's `config.ini` points at a USB CH340 by-id path; `build.sh` forces
   `serial_port = /dev/serial0` (GPIO) — right for the bench Pi. Revisit if a unit uses the dongle.
8. ~~Rootfs auto-grow~~ DONE (drdro-growfs.service, live-tested; see Status).

## Gotchas / hard-won
- ALARM `rpi-aarch64` ships **mainline kernel + U-Boot**, whose `boot.txt` sets
  `console=ttyS1,115200` and **overrides `/boot/cmdline.txt`** (serial spam on the RS-485 UART).
  linux-rpi direct boot makes `cmdline.txt` authoritative. Swap is baked in `build.sh`.
- linux-rpi install **resets `/boot/config.txt`** to RPi stock — `build.sh` step 5 overwrites with
  our copy (stock + appends). If linux-rpi's stock file changes, refresh `boot/config.txt`.
- chroot in CI: fix DNS (`rm /etc/resolv.conf` symlink → write `1.1.1.1`), pacman `SigLevel=Never`
  + disable `CheckSpace` (false OOM in chroot), build on `/mnt` (root disk too small).
- Arch is rolling (Python **3.14**) → app venv pinned to **3.13 via pyenv** (Kivy wheels);
  `base-devel` stays (compiles CPython).
- Touch: Kivy needs **`mtdev`**; default `probesysfs` then auto-detects — no Kivy config change.
- `/dev/serial0` doesn't exist on stock ALARM — shipped `99-com.rules` udev rule creates it.
- Slimming: `pacman -Rns` fails the whole transaction if ANY named package is missing — the
  vi/vim names vary across tarball generations, hence the `$(pacman -Qq ... 2>/dev/null|sort -u)`
  guard in build.sh. `guile` can't go while `make` stays (linked, not dlopened). `default-cursors`
  and `pacman-mirrorlist` looked huge in a size audit once — that was a B-vs-MiB parsing bug;
  they're bytes.

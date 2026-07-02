# drDRO-OS (Arch Linux ARM)

Purpose-built Raspberry Pi appliance image for the **drDRO** Kivy app (`drdro-software-f4`), built
on **Arch Linux ARM (ALARM)**. The simplest of the drDRO OS experiments: glibc + native pip, so
Kivy/pydantic/etc. "just work" from PyPI wheels with no wheelhouse and no sandbox.

## How it works

`build.sh` runs on a **native aarch64 host** (the GitHub ARM64 runner — no qemu):

1. Fetch the ALARM `rpi-aarch64` rootfs tarball.
2. `chroot` in (native) and swap ALARM's mainline kernel + U-Boot for **`linux-rpi`** (the RPi
   downstream kernel). Mainline+U-Boot broke serial (U-Boot's baked `console=ttyS1` overrides
   `cmdline.txt` — login spam on the RS-485 UART) and touch; linux-rpi direct-boots `kernel8.img`,
   making our `cmdline.txt` authoritative, and the firmware picks the dtb per board.
3. `pacman -S` the runtime: SDL2, mesa (v3d/vc4 GL), `mtdev` (touch), Python, git,
   NetworkManager, audio, fonts (see [`packages.txt`](packages.txt)).
4. `git clone` the app and **`pip install` it into a baked venv** at `/opt/drdro/app/.venv`. Native
   pip pulls the correct aarch64 wheels — so the venv ships *inside the image* and **first boot needs
   no network and no wheelhouse**. (This is why the Arch track is simpler than the Buildroot/Yocto
   ones, which needed a vendored wheelhouse for offline first boot.)
5. Overlay the launcher + `drdro.service`, write our `config.txt`/`cmdline.txt` (`boot/config.txt`
   here = linux-rpi's stock file + our settings appended under `[all]`).
6. Assemble a 2-partition SD image (FAT boot + ext4 root) with `mke2fs -d` + `mtools` — no loop
   mounts.

The app runs as root on KMS/DRM (SDL2 `kmsdrm`), fullscreen, no display server. The UART is left
free for the RS-485 board link (`console=tty1`, no serial console). Root is writable (Arch's
nature), so the in-app updater can `git pull` + `pip install` a newer version in the field.

On boot, `drdro-growfs.service` grows the root partition + ext4 to fill the actual SD card
(sfdisk + partx + online resize2fs; short-circuits once full-size), so the image ships with only
a small build-time slack and any card size works.

Boot is **silent** (Plymouth drDRO splash → app; kernel console on tty3; see
`docs/PLYMOUTH.md`). `Ctrl+Alt+F2` hands the screen to a tty2 login for maintenance and
`Ctrl+Alt+F1` returns to the app — via `drdro-vt-watch.service`, which stops/starts the app
around VT switches because sdl2-compat/SDL3's KMSDRM never releases DRM master on its own.

## Build & CI

- **CI:** `.github/workflows/build.yml` (run on demand via *workflow_dispatch*, or on push) builds on
  `ubuntu-24.04-arm` and uploads the raw `.img` (the artifact zip is the compression).
  ```
  gh workflow run build-arch -R bartei/drdro-arch
  gh run download <run-id> -R bartei/drdro-arch -n drdro-arch-rpi-aarch64   # unzips to the flashable .img
  sudo dd if=drdro-arch-rpi-aarch64.img of=/dev/sdX bs=4M conv=fsync status=progress
  ```
- **Locally** (on an aarch64 box): `sudo ./build.sh` → `out/drdro-arch-rpi-aarch64.img`.

## Access (dev defaults — intentionally permissive)

- User **`default`** / password **`default`**, in `wheel` with **passwordless sudo** to root.
- **SSH** enabled with **password login** (`ssh default@<ip>`). The app itself runs as root.
- Stock ALARM `root`/`root` and `alarm`/`alarm` also still exist.

## Notes / trade-offs

- **Rolling release, by choice.** Each build pulls current Arch packages + the latest app release
  (`APP_REF=latest` = newest `v*` tag; override to pin). Not reproducible build-to-build — accepted
  here: CI is run on demand and images are tested before release.
- **`SigLevel = Never` during the build** (skips pacman key init, which hangs in CI). Revisit if
  build-time package provenance matters.
- **Slimmed on purpose** (rootfs ~1.6 GB, down from ~3.2 GB; every removal validated on the bench
  Pi 3B): no pacman/pip caches, no man/info/doc pages, English-only locales (pacman `NoExtract`
  keeps it that way in the field), wifi firmware only for broadcom (onboard) + realtek (common USB
  dongles), no gdb chain (a `debugedit` dep that dragged in system python/boost), no vim stack
  (nano stays), no CPython test suite/static libpython. See the slim-down block in `build.sh`.
  KEEP: `base-devel` (pyenv compiles CPython), `guile` (make links it), `llvm-libs` (mesa V3D),
  `perl` (git), `icu` (libxml2).
- ALARM `rpi-aarch64` covers Pi 3/4/5 from one tarball; this image targets that family. With
  linux-rpi the firmware auto-selects the dtb per board, so one universal image is within reach.
- **Hardware-validated on a Pi 3B**: boots, app autostarts, hardware GL (**VC4 V3D**, not
  llvmpipe), USB touch (via `mtdev`), RS-485 on `/dev/serial0`, and **onboard wifi** — the latter
  needs the shipped `modprobe.d/brcmfmac.conf` (`feature_disable=0x82000`: wpa_supplicant ≥ 2.11
  offloads the WPA handshake to the Cypress firmware, which botches it; see `RESUME.md`). The app
  configures wifi through NetworkManager (`nmcli`). BCM43430 is 2.4 GHz-only.

#!/usr/bin/env bash
# Build a drDRO Arch Linux ARM (aarch64) Raspberry Pi appliance image.
#
# Runs on an aarch64 host (native GitHub ARM64 runner) as root — the chroot runs natively, no qemu.
# Steps: fetch the ALARM rpi-aarch64 rootfs tarball -> swap mainline kernel + U-Boot for linux-rpi
# (the RPi downstream kernel) -> pacman-install the runtime -> git-clone the app + `pip install` it
# into a baked venv (native pip pulls the right aarch64 wheels; no wheelhouse, and first boot needs
# no network) -> overlay our service + boot config -> assemble a 2-partition SD image (FAT boot +
# ext4 root) with no loop mounts (mke2fs -d + mtools).
#
# Output: out/drdro-arch-rpi-aarch64.img
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-$HERE/work}"
OUT="${OUT:-$HERE/out}"
ROOTFS="$WORK/rootfs"

ALARM_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-aarch64-latest.tar.gz"
APP_REPO="https://github.com/bartei/drdro-software-f4.git"
APP_REF="${APP_REF:-latest}"   # "latest" = newest release tag; or set a tag/branch/rev
BOOT_MB=128   # /boot content is ~66 MB (kernel8 + initramfs + firmware blobs + overlays) — 2x headroom
DRDRO_VERSION="${DRDRO_VERSION:-dev}"   # semantic-release passes the real version at release time
ENABLE_PLYMOUTH="${ENABLE_PLYMOUTH:-1}"   # silent boot + drDRO splash (see docs/PLYMOUTH.md); 0 = verbose boot

[ "$(id -u)" -eq 0 ] || { echo "build.sh: must run as root (chroot + mke2fs -d)"; exit 1; }
mkdir -p "$WORK" "$OUT"

# --- 1. ALARM rootfs ---
TARBALL="$WORK/alarm.tar.gz"
[ -f "$TARBALL" ] || curl -fSL "$ALARM_URL" -o "$TARBALL"
rm -rf "$ROOTFS"; mkdir -p "$ROOTFS"
bsdtar -xpf "$TARBALL" -C "$ROOTFS"

# --- 2. chroot prep (native aarch64) ---
mount -t proc  none "$ROOTFS/proc"
mount -t sysfs none "$ROOTFS/sys"
mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"
# Real nameservers for the chroot. ALARM ships /etc/resolv.conf as a symlink to the
# systemd-resolved stub; remove it first so we write a plain file the chroot actually reads
# (writing through the symlink from the host shell resolves to the wrong target).
rm -f "$ROOTFS/etc/resolv.conf"
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$ROOTFS/etc/resolv.conf"
cleanup() { umount -R "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev" 2>/dev/null || true; }
trap cleanup EXIT

# --- 3. resolve the app ref (latest STABLE release tag by default) ---
# Prerelease tags (v1.4.1-beta.N, published from the app's dev branch) sort ABOVE their
# stable release in -v:refname order — filter them out so the image never bakes a beta.
if [ "$APP_REF" = "latest" ]; then
    APP_REF="$(git ls-remote --tags --refs --sort=-v:refname "$APP_REPO" 'v*' \
               | sed 's#.*/##' | grep -v -e - | head -n1)"
    echo "build.sh: latest stable release tag = ${APP_REF:-<none>}"
fi

# --- 4. pacman runtime + git-clone app + pip install into a baked venv ---
mapfile -t PKGS < <(grep -vE '^\s*#|^\s*$' "$HERE/packages.txt")
chroot "$ROOTFS" /bin/bash -euo pipefail -c "
    # pacman-key --init needs lots of entropy and often hangs in CI. Since the image is validated
    # before release, skip signature checks for the build (revisit if provenance matters).
    sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf
    # CheckSpace can't statvfs the cachedir mount inside a chroot ('could not determine cachedir
    # mount point' -> false 'not enough free disk space'); disable it for the build.
    sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
    # Never extract man/info/docs or non-English locales (~275 MB across the image) — applies to
    # the -Syu below and to any pacman use in the field; the tarball's preexisting files are rm'd
    # in the slim-down at the end. Must land INSIDE [options] — appending to the end of ALARM's
    # pacman.conf puts it in the [aur] repo section where pacman ignores it with a warning.
    sed -i '/^\[options\]/a NoExtract = usr/share/man/* usr/share/info/* usr/share/doc/* usr/share/gtk-doc/*\nNoExtract = usr/share/locale/* !usr/share/locale/en* !usr/share/locale/locale.alias' /etc/pacman.conf
    pacman -Syu --noconfirm

    # Kernel: replace ALARM's mainline kernel + U-Boot with the RPi downstream kernel. Proven on
    # the bench Pi 3B — mainline+U-Boot broke the appliance three ways: U-Boot's baked boot.txt
    # cmdline (console=ttyS1) overrides /boot/cmdline.txt and spews a login console onto the
    # RS-485 UART, the USB touch panel wasn't registered, and brcmfmac wifi is even worse.
    # linux-rpi direct-boots kernel8.img (no U-Boot -> our cmdline.txt is authoritative), ships
    # raspberrypi-overlays, and the firmware auto-selects the dtb per board (paves the way for one
    # universal Pi 3/4/5 image). It also resets /boot/config.txt to the RPi stock file — step 5
    # overwrites it with ours (stock + drDRO settings). -Rdd: nothing depends on the kernel, so
    # remove without dep checks.
    pacman -Rdd --noconfirm uboot-raspberrypi linux-aarch64
    pacman -S --noconfirm linux-rpi

    pacman -S --noconfirm --needed ${PKGS[*]}

    # NetworkManager is the ONLY interface owner (the app's UI drives it via nmcli). The ALARM
    # tarball ships systemd-networkd (with a catch-all wired .network) enabled — left on,
    # networkd + NM each run a DHCP client on the same port and the device holds two ethernet
    # leases at once (proven on the bench Pi: .124 + .129, a 'wandering' IP). Disable networkd;
    # socket unit names drift across systemd releases, so tolerate absent ones.
    # DNS: systemd-resolved STAYS enabled (ALARM default). systemd-tmpfiles recreates
    # /etc/resolv.conf as the resolved stub symlink on every boot, and NM auto-detects that and
    # feeds resolved over D-Bus — fighting this wiring broke DNS twice (dangling symlink with
    # resolved off; then rc-manager=file, which FOLLOWS the symlink into the absent
    # /run/systemd/resolve). Bonus: resolved's fallback DNS servers keep names resolving even if
    # a site's DHCP hands out a dead DNS. Live-verified on the Pi 5 across a reboot.
    systemctl enable NetworkManager
    systemctl disable \
        systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service \
        systemd-networkd-resolve-hook.socket systemd-networkd-varlink.socket \
        systemd-networkd-varlink-metrics.socket systemd-network-generator.service \
        2>/dev/null || true

    # Trim firmware: keep only Broadcom (onboard wifi/BT — works, see modprobe.d/brcmfmac.conf in
    # the overlay), Realtek (common USB wifi dongle chipsets, in case a unit needs one) and the
    # RPi blobs.
    # The -Syu pulls the full split linux-firmware set; drop the rest (no such hardware on a Pi) —
    # nvidia/amdgpu/radeon/intel are hundreds of MB each, atheros alone is ~136 MB. -Rdd: targeted
    # removal, ignore the linux-firmware meta's dep so we can drop it without touching the keepers.
    pacman -Rdd --noconfirm \
        linux-firmware linux-firmware-amdgpu linux-firmware-nvidia linux-firmware-radeon \
        linux-firmware-intel linux-firmware-cirrus linux-firmware-mediatek \
        linux-firmware-atheros linux-firmware-other \
        2>/dev/null || true
    # The keepers were deps of the removed meta — mark explicit so orphan sweeps never eat them.
    pacman -D --asexplicit linux-firmware-broadcom linux-firmware-realtek firmware-raspberrypi

    # UART is the RS-485 board link only — no login prompt on it (ALARM enables a serial getty by
    # default, which spews a login banner onto the wire). The kernel console is already tty1-only
    # (see boot/cmdline.txt).
    systemctl mask serial-getty@ttyAMA0.service serial-getty@ttyS0.service serial-getty@ttyAMA10.service
    # tty3 is the log console (drdro-log-tty3.service tails app.log there) — keep logind from
    # spawning a login prompt on top of it. tty2 stays the maintenance login (Ctrl+Alt+F2).
    systemctl mask autovt@tty3.service

    # Maintenance user 'default' (password 'default'), passwordless sudo to root, SSH with password
    # login. Ease-of-use over hardening — deliberate for this single-purpose device.
    useradd -m -G wheel -s /bin/bash default
    echo 'default:default' | chpasswd
    install -d -m 0750 /etc/sudoers.d
    echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-wheel-nopasswd
    chmod 0440 /etc/sudoers.d/10-wheel-nopasswd
    systemctl enable sshd
    install -d /etc/ssh/sshd_config.d
    printf 'PasswordAuthentication yes\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/10-drdro.conf

    install -d /opt/drdro
    git clone '$APP_REPO' /opt/drdro/app
    git -C /opt/drdro/app checkout -q '${APP_REF:-main}'
    # The board is on the GPIO UART; the committed config.ini points at a USB path.
    [ -f /opt/drdro/app/config.ini ] && sed -i 's|^serial_port *=.*|serial_port = /dev/serial0|' /opt/drdro/app/config.ini

    # Pin the venv to Python 3.13 via pyenv — it HAS aarch64 wheels for Kivy et al., unlike Arch's
    # rolling python (3.14, ahead of upstream wheels). pyenv compiles CPython once here; app deps
    # then install as prebuilt wheels (no compiling Kivy), and field pip updates stay wheel-based.
    export PYENV_ROOT=/opt/pyenv
    git clone --depth 1 https://github.com/pyenv/pyenv \"\$PYENV_ROOT\"
    PYVER=\$(\"\$PYENV_ROOT/bin/pyenv\" latest -k 3.13)
    \"\$PYENV_ROOT/bin/pyenv\" install -s \"\$PYVER\"
    PYBIN=\"\$PYENV_ROOT/versions/\$PYVER/bin/python\"

    \"\$PYBIN\" -m venv /opt/drdro/app/.venv
    /opt/drdro/app/.venv/bin/pip install --upgrade pip
    /opt/drdro/app/.venv/bin/pip install /opt/drdro/app

    # --- slim down (every removal validated live on the bench Pi 3B: app + GL + touch + serial
    # all fine after a reboot) ---
    # gdb enters only via base-devel's debugedit (used for makepkg debug packages — never here)
    # and drags ~185 MB with it: system python 3.14, boost-libs, source-highlight. texinfo/groff
    # only build/format docs. The vim stack goes (nano stays for field edits); dhcpcd/netctl/
    # dialog/wireless_tools/net-tools are ALARM-tarball leftovers superseded by NetworkManager.
    # KEEP: guile (make links it), icu (libxml2), llvm-libs (mesa V3D shaders), perl (git).
    pacman -Rdd --noconfirm gdb texinfo groff
    pacman -Rns --noconfirm gdb-common source-highlight python boost-libs \
        dhcpcd netctl dialog wireless_tools net-tools \
        \$(pacman -Qq ex-vi-compat vi vim vim-runtime 2>/dev/null | sort -u)
    # CPython's bundled test suite (145 MB!) and static libpython (67 MB) are dead weight at
    # runtime — wheels never link the static lib, and a field source build doesn't need it either.
    rm -rf \"\$PYENV_ROOT/versions/\$PYVER\"/lib/python3.*/test
    rm -f  \"\$PYENV_ROOT/versions/\$PYVER\"/lib/python3.*/config-*/libpython*.a
    # Tarball-preexisting docs/locales (the NoExtract above only covers packages installed after
    # it), then package + pip caches — together ~650 MB.
    rm -rf /usr/share/man/* /usr/share/info/* /usr/share/doc/* /usr/share/gtk-doc/*
    find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en*' ! -name 'locale.alias' -exec rm -rf {} +
    rm -rf /var/cache/pacman/pkg/* /root/.cache
"

# --- 5. overlay (launcher + drdro.service) + boot config (no serial console, KMS GL) ---
# boot/config.txt in this repo = linux-rpi's stock file + drDRO settings appended; this copy
# replaces the stock one the linux-rpi package just installed.
cp -a "$HERE/overlay/." "$ROOTFS/"
cp "$HERE/boot/config.txt"  "$ROOTFS/boot/config.txt"
cp "$HERE/boot/cmdline.txt" "$ROOTFS/boot/cmdline.txt"
# The image knows its own release version (support: `cat /etc/drdro-release` on a device).
echo "VERSION=${DRDRO_VERSION}" > "$ROOTFS/etc/drdro-release"

# --- 5b. optional: silent boot + drDRO Plymouth splash (see docs/PLYMOUTH.md) ---
if [ "$ENABLE_PLYMOUTH" = "1" ]; then
    echo "build.sh: enabling Plymouth silent boot"
    install -d "$ROOTFS/usr/share/plymouth/themes/drdro" "$ROOTFS/etc/plymouth"
    cp "$HERE"/plymouth/theme/* "$ROOTFS/usr/share/plymouth/themes/drdro/"
    cp "$HERE/plymouth/plymouthd.conf" "$ROOTFS/etc/plymouth/plymouthd.conf"
    chroot "$ROOTFS" /bin/bash -euo pipefail -c "
        pacman -S --noconfirm --needed plymouth
        plymouth-set-default-theme drdro
        systemctl mask getty@tty1.service    # tty1 is for the splash -> app; login on tty2 (Ctrl+Alt+F2, via drdro-vt-watch)
        # Keep the splash up until app-run.sh's 'plymouth quit --retain-splash' — otherwise
        # systemd's plymouth-quit kills it at multi-user, seconds before Kivy paints (black gap).
        systemctl mask plymouth-quit.service plymouth-quit-wait.service
    "
    # Quiet cmdline: kernel console off the main display (tty3), no boot text, show the splash.
    echo "console=tty3 quiet loglevel=3 vt.global_cursor_default=0 logo.nologo splash plymouth.ignore-serial-consoles root=/dev/mmcblk0p2 rw rootwait rootfstype=ext4 fsck.repair=yes brcmfmac.roamoff=1" \
        > "$ROOTFS/boot/cmdline.txt"
fi

# --- 5c. Pi 5 bootloader EEPROM self-heal (boot partition files) ---
# linux-rpi 6.18+ won't boot on Pi 5s with a pre-~Dec-2025 bootloader EEPROM (boot-loops at the
# diagnostic screen; ALARM forum t=17369/t=17381). The BCM2712 boot ROM loads recovery.bin from
# the SD FAT BEFORE the EEPROM runs, so these three files make an old Pi 5 heal itself on first
# power-on: recovery.bin verifies pieeprom.upd against pieeprom.sig, flashes it, renames itself
# to recovery.000 (that's the re-flash-loop guard), and reboots straight into the OS — the same
# official mechanism rpi-eeprom-update stages. The `.upd` naming is what makes it auto-continue;
# `pieeprom.bin` naming would halt on a green screen (that's the Imager utility card).
# Up-to-date boards just pay one redundant flash+reboot per freshly flashed card. Pi 3 ROMs have
# no recovery.bin concept (ignored). CAUTION: files are 2712-only — the Pi 4 (2711) ROM also
# loads recovery.bin from SD, so revisit this before ever shipping a Pi 4 unit.
# Pinned from raspberrypi/rpi-eeprom firmware-2712/default (the production release stream).
RPI_EEPROM_COMMIT="aa33b8dc7cee51de4b75580095521dea50407d6e"
RPI_EEPROM_VER="2026-05-26"
RPI_EEPROM_URL="https://raw.githubusercontent.com/raspberrypi/rpi-eeprom/$RPI_EEPROM_COMMIT/firmware-2712/default"
curl -fsSL -o "$ROOTFS/boot/pieeprom.upd" "$RPI_EEPROM_URL/pieeprom-$RPI_EEPROM_VER.bin"
curl -fsSL -o "$ROOTFS/boot/recovery.bin" "$RPI_EEPROM_URL/recovery.bin"
sha256sum -c --quiet <<EOF
fee8bee6a738a1a61004f0770f15534de7a48a2a199dc4c7af7ed73ab04f18dd  $ROOTFS/boot/pieeprom.upd
73dab9a01c139b7d995ac9a4055ee0d15551d7f8dbf1c2605bae584ef7126e0c  $ROOTFS/boot/recovery.bin
EOF
# Same format rpi-eeprom-digest writes: sha256 of the image, then the image timestamp (release
# date — deterministic, and lets a newer EEPROM's self-update logic see this file as old news).
{ sha256sum "$ROOTFS/boot/pieeprom.upd" | awk '{print $1}'
  echo "ts: $(date -u -d "$RPI_EEPROM_VER" +%s)"; } > "$ROOTFS/boot/pieeprom.sig"

# The static resolv.conf (written in step 2) was only for the chroot builds above; restore the
# Arch factory state — the systemd-resolved stub symlink (same one systemd-tmpfiles would
# recreate at boot). resolved is enabled, so the target exists at runtime.
ln -sf ../run/systemd/resolve/stub-resolv.conf "$ROOTFS/etc/resolv.conf"

cleanup; trap - EXIT

# --- 6. assemble the SD image (FAT boot p1 + ext4 root p2), no loop mounts ---
IMG="$OUT/drdro-arch-rpi-aarch64.img"
BOOT_IMG="$WORK/boot.vfat"; ROOT_IMG="$WORK/root.ext4"

# FAT boot from rootfs/boot/*, then empty /boot (mounted from p1 at runtime per ALARM fstab).
rm -f "$BOOT_IMG"; truncate -s "${BOOT_MB}M" "$BOOT_IMG"
mkfs.vfat -F 32 -n BOOT "$BOOT_IMG" >/dev/null
mcopy -s -i "$BOOT_IMG" "$ROOTFS"/boot/* ::/
rm -rf "${ROOTFS:?}/boot"/*

# ext4 root sized to content + modest slack — just enough for first-boot writes before
# drdro-growfs.service (overlay) expands the partition + fs to fill the actual card.
ROOT_KB=$(du -sk "$ROOTFS" | cut -f1)
ROOT_MB=$(( ROOT_KB / 1024 * 115 / 100 + 128 ))
rm -f "$ROOT_IMG"
mke2fs -q -t ext4 -L ROOT -d "$ROOTFS" "$ROOT_IMG" "${ROOT_MB}M"

# disk: 1MiB align, p1 FAT (bootable), p2 ext4.
rm -f "$IMG"; truncate -s "$(( 1 + BOOT_MB + ROOT_MB + 8 ))M" "$IMG"
sfdisk "$IMG" >/dev/null <<EOF
label: dos
start=1MiB, size=${BOOT_MB}MiB, type=c, bootable
type=83
EOF
dd if="$BOOT_IMG" of="$IMG" bs=1M seek=1 conv=notrunc status=none
dd if="$ROOT_IMG" of="$IMG" bs=1M seek=$((1 + BOOT_MB)) conv=notrunc status=none

echo "build.sh: wrote $IMG ($(du -h "$IMG" | cut -f1))"

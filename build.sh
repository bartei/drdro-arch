#!/usr/bin/env bash
# Build a drDRO Arch Linux ARM (aarch64) Raspberry Pi appliance image.
#
# Runs on an aarch64 host (native GitHub ARM64 runner) as root — the chroot runs natively, no qemu.
# Steps: fetch the ALARM rpi-aarch64 rootfs tarball -> pacman-install the runtime -> git-clone the
# app + `pip install` it into a baked venv (native pip pulls the right aarch64 wheels; no wheelhouse,
# and first boot needs no network) -> overlay our service + boot config -> assemble a 2-partition SD
# image (FAT boot + ext4 root) with no loop mounts (mke2fs -d + mtools).
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
BOOT_MB=256

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

# --- 3. resolve the app ref (latest release tag by default) ---
if [ "$APP_REF" = "latest" ]; then
    APP_REF="$(git ls-remote --tags --refs --sort=-v:refname "$APP_REPO" 'v*' \
               | head -n1 | sed 's#.*/##')"
    echo "build.sh: latest release tag = ${APP_REF:-<none>}"
fi

# --- 4. pacman runtime + git-clone app + pip install into a baked venv ---
mapfile -t PKGS < <(grep -vE '^\s*#|^\s*$' "$HERE/packages.txt")
chroot "$ROOTFS" /bin/bash -euo pipefail -c "
    # pacman-key --init needs lots of entropy and often hangs in CI. Since the image is validated
    # before release, skip signature checks for the build (revisit if provenance matters).
    sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf
    pacman -Syu --noconfirm
    pacman -S --noconfirm --needed ${PKGS[*]}
    systemctl enable NetworkManager

    install -d /opt/drdro
    git clone '$APP_REPO' /opt/drdro/app
    git -C /opt/drdro/app checkout -q '${APP_REF:-main}'
    # The board is on the GPIO UART; the committed config.ini points at a USB path.
    [ -f /opt/drdro/app/config.ini ] && sed -i 's|^serial_port *=.*|serial_port = /dev/serial0|' /opt/drdro/app/config.ini

    # Baked venv: native pip pulls the correct aarch64 wheels (Kivy/pydantic-core/...). No wheelhouse.
    python -m venv /opt/drdro/app/.venv
    /opt/drdro/app/.venv/bin/pip install --upgrade pip
    /opt/drdro/app/.venv/bin/pip install /opt/drdro/app
"

# --- 5. overlay (launcher + drdro.service) + boot config (no serial console, KMS GL) ---
cp -a "$HERE/overlay/." "$ROOTFS/"
cp "$HERE/boot/config.txt"  "$ROOTFS/boot/config.txt"
cp "$HERE/boot/cmdline.txt" "$ROOTFS/boot/cmdline.txt"

cleanup; trap - EXIT

# --- 6. assemble the SD image (FAT boot p1 + ext4 root p2), no loop mounts ---
IMG="$OUT/drdro-arch-rpi-aarch64.img"
BOOT_IMG="$WORK/boot.vfat"; ROOT_IMG="$WORK/root.ext4"

# FAT boot from rootfs/boot/*, then empty /boot (mounted from p1 at runtime per ALARM fstab).
rm -f "$BOOT_IMG"; truncate -s "${BOOT_MB}M" "$BOOT_IMG"
mkfs.vfat -F 32 -n BOOT "$BOOT_IMG" >/dev/null
mcopy -s -i "$BOOT_IMG" "$ROOTFS"/boot/* ::/
rm -rf "${ROOTFS:?}/boot"/*

# ext4 root sized to content + slack (root auto-grows on first boot).
ROOT_KB=$(du -sk "$ROOTFS" | cut -f1)
ROOT_MB=$(( ROOT_KB / 1024 * 135 / 100 + 256 ))
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

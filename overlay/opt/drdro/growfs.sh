#!/bin/bash
# Grow the root partition to fill the SD card, then the ext4 filesystem (online resize while
# mounted). Runs at every boot and no-ops in milliseconds once full-size (growpart exit 1 =
# NOCHANGE) — stampless on purpose, so moving the card image to a bigger card grows again.
set -eu

ROOTPART="$(findmnt -no SOURCE /)"                                     # /dev/mmcblk0p2
DISK="/dev/$(lsblk -no PKNAME "$ROOTPART")"                            # /dev/mmcblk0
PARTNUM="$(cat "/sys/class/block/$(basename "$ROOTPART")/partition")"  # 2

rc=0
out="$(growpart "$DISK" "$PARTNUM" 2>&1)" || rc=$?
echo "$out"
case "$rc" in
    0) resize2fs "$ROOTPART" ;;   # partition grew -> grow the fs into it
    1) ;;                         # NOCHANGE: already fills the disk
    *) exit "$rc" ;;
esac

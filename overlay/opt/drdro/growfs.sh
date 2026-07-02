#!/bin/bash
# Grow the root partition to fill the SD card, then the ext4 filesystem (online resize while
# mounted). Pure util-linux + e2fsprogs (sfdisk/partx/resize2fs — the same calls growpart wraps);
# Arch's cloud-guest-utils package would drag the 78 MB system python back into the image.
# Runs at every boot: once full-size it exits after a sysfs size compare (no disk writes), so
# moving the card image to a bigger card grows again.
set -eu

ROOTPART="$(findmnt -no SOURCE /)"                                     # /dev/mmcblk0p2
DISK="$(lsblk -no PKNAME "$ROOTPART")"                                 # mmcblk0
PARTNUM="$(cat "/sys/class/block/$(basename "$ROOTPART")/partition")"  # 2

disk_sz="$(cat "/sys/block/$DISK/size")"
part_start="$(cat "/sys/class/block/$(basename "$ROOTPART")/start")"
part_sz="$(cat "/sys/class/block/$(basename "$ROOTPART")/size")"

# Within 16 MiB (32768 sectors) of the disk end -> already grown. (The image itself leaves an
# ~8 MiB tail after p2, so a card no bigger than the image also lands here.)
if [ $(( part_start + part_sz + 32768 )) -ge "$disk_sz" ]; then
    exit 0
fi

# ",+" = extend partition $PARTNUM to the maximum. --no-reread + partx -u because the disk holds
# the mounted root (BLKRRPART would fail); ext4 then grows online.
echo ",+" | sfdisk --no-reread --force -N "$PARTNUM" "/dev/$DISK"
partx -u "/dev/$DISK"
resize2fs "$ROOTPART"

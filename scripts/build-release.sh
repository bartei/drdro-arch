#!/usr/bin/env bash
# python-semantic-release build_command: invoked by `semantic-release version` with NEW_VERSION
# in the environment. Builds the image with the version baked in (/etc/drdro-release), then
# drops the versioned release artifact + checksums into dist/ for `semantic-release publish`.
set -euo pipefail

: "${NEW_VERSION:?build-release.sh must be run by semantic-release (NEW_VERSION unset)}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$HERE/work}"
OUT="${OUT:-$HERE/out}"

sudo WORK="$WORK" OUT="$OUT" DRDRO_VERSION="$NEW_VERSION" "$HERE/build.sh"

mkdir -p "$HERE/dist"
IMG="$OUT/drdro-arch-rpi-aarch64.img"
ASSET="$HERE/dist/drdro-arch-v${NEW_VERSION}-rpi-aarch64.img.zst"
zstd -T0 -12 --force "$IMG" -o "$ASSET"
(cd "$HERE/dist" && sha256sum "$(basename "$ASSET")" > "drdro-arch-v${NEW_VERSION}-SHA256SUMS.txt")
ls -lh "$HERE/dist"

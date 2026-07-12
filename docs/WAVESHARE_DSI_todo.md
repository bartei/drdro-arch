# Waveshare 10.1" DSI LCD (C) — tracker

Detail in [`WAVESHARE_DSI_design.md`](WAVESHARE_DSI_design.md).

## Phase 1 — Implement (single image + config.txt toggle)
- [x] Add commented `vc4-kms-dsi-waveshare-panel,10_1_inch` block to `boot/config.txt`
- [x] `build.sh`: warn if `vc4-kms-dsi-waveshare-panel.dtbo` missing from linux-rpi
- [x] Design/field guide + this tracker
- [x] README + RESUME notes

## Phase 2 — Verify on hardware (DSI panel required) — VERIFIED 2026-07-12
- [x] Confirm `.dtbo` present in a freshly built image (no build warning)
- [x] Flash, uncomment the overlay line, boot with DSI panel → image shows at 1280×800
- [x] Touch works: multitouch + on-screen keyboard (mtdev/probesysfs, no app change)
- [x] Orientation correct with the committed line (no `rotation=`/`swapxy` tweak needed)
- [x] Regression: an HDMI unit (line left commented) is unaffected
- [x] DSI1 default correct on the board tested

## Later / optional
- [ ] Build-time `PANEL=` variant baking a ready-to-flash `…-dsi.img` (only if pre-configured
      per-display images are wanted; the field toggle covers the need for now)

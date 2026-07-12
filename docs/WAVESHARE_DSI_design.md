# Waveshare 10.1" DSI LCD (C) support — design & field guide

Adds support for the **Waveshare 10.1inch DSI LCD (C)** to the Arch image, alongside the HDMI
displays that already work out of the box. Companion tracker: [`WAVESHARE_DSI_todo.md`](WAVESHARE_DSI_todo.md).

Product: <https://www.waveshare.com/wiki/10.1inch_DSI_LCD_(C)>

## What the panel actually is
It is a **MIPI-DSI** display (DSI ribbon for video) with an **I²C capacitive touch** controller —
**not** SPI. (A 10.1" panel can't run video over SPI; the old Raspbian/ospi image drove it over DSI
too. The "SPI" in the request was a mis-recollection.) Native resolution **1280×800**.

## Why this is easy on this image
The panel is **natively supported by the kernel this image already runs** — `linux-rpi`, the RPi
downstream kernel (currently 6.18.x). No Waveshare driver package, no `WS_*DSI*.sh` install script
(those are only for old Bullseye/Buster kernels). The support is the in-tree overlay
`vc4-kms-dsi-waveshare-panel`, which ships as `/boot/overlays/vc4-kms-dsi-waveshare-panel.dtbo`
with the kernel package. It works with our existing KMS stack (`dtoverlay=vc4-kms-v3d`) with no
change to the graphics path.

Enabling it is a **single overlay line** in `config.txt`:

```
dtoverlay=vc4-kms-dsi-waveshare-panel,10_1_inch
```

- `10_1_inch` → compatible `waveshare,10.1inch-panel`; sets the panel + touch geometry
  (800×1280 with `invx` + `swapxy` applied, i.e. landscape 1280×800 with correctly-mapped touch).
- Default **DSI port is DSI1** — the standard display connector on Pi 3/4 and the recommended port
  on Pi 5/CM. (Add `,dsi0` to use DSI0.) One line therefore works across Pi 3B/4/5.
- Optional orientation tweaks: `,rotation=90`, `,invx`, `,invy`, `,swapxy`.
- `vc4-kms-v3d` must remain enabled above it (it already is in our `config.txt`).

### Touch needs no app change
The overlay instantiates the Goodix I²C touch as a standard multitouch **evdev** device. Kivy's
`mtdev` + default `probesysfs` input provider auto-detects it exactly like today's USB touch panel
— so the on-screen keyboard and multitouch behave the same. No Kivy config and no `packages.txt`
change.

## The design decision: single image + `config.txt` toggle
**Chosen:** ship **one image** (default = HDMI, unchanged). `config.txt` carries the Waveshare
overlay line **commented out**, fully documented in-file. A DSI unit is enabled by **uncommenting
that one line** — editable straight on the SD card's FAT boot partition from any computer, **no
reflash**.

**Why not enable the overlay unconditionally?** A DSI panel has **no hotplug-detect (HPD)**. Once
the overlay is loaded, KMS *always* reports the DSI connector as connected, even with nothing
plugged in. On an HDMI-only unit that creates a phantom display, and the headless SDL `kmsdrm`
launcher (no display server to arbitrate) could render the app to the invisible DSI instead of the
HDMI. So the overlay must only be present on units that actually have the panel — which the
per-unit toggle achieves with zero risk to HDMI units.

**Why the toggle and not a build variant / auto-detect** (both considered, rejected for now):
- *Build-time variant (a `PANEL=` flag baking a separate `…-dsi.img`)* — viable and additive, but
  doubles the release artifacts and CI surface for what is a one-line SD-card edit. Easy to add
  later if pre-configured per-display images become worthwhile.
- *Boot auto-detect (probe → rewrite `config.txt` → reboot)* — nicest UX but fragile: the panel's
  touch I²C bus generally isn't visible until the overlay is already loaded, so a pre-overlay probe
  can't reliably see it, and it introduces a first-boot reboot cycle. Not worth the risk for an
  appliance whose display is fixed at assembly time.

## Enabling a unit in the field
1. Insert the SD card into any computer; open the **boot** (FAT) partition.
2. Edit `config.txt`, find the commented Waveshare block, and remove the leading `#` from:
   `#dtoverlay=vc4-kms-dsi-waveshare-panel,10_1_inch`.
3. (Optional) append an orientation tweak, e.g. `,rotation=90`.
4. Save, eject, boot the Pi with the DSI panel connected. The image appears in a few seconds and
   touch works. (Leave HDMI unplugged on a DSI unit.)

## Verification checklist (real hardware)
See [`WAVESHARE_DSI_todo.md`](WAVESHARE_DSI_todo.md) Phase 2. In short: `.dtbo` present in the built
image → uncomment → panel lights up at 1280×800 → multitouch + on-screen keyboard work → an HDMI
unit (line left commented) is unaffected → confirm orientation (note any `rotation`/`swapxy` tweak
the specific panel batch needs).

## Sources
- Waveshare wiki — 10.1inch DSI LCD (C): <https://www.waveshare.com/wiki/10.1inch_DSI_LCD_(C)>
- RPi kernel overlay: `arch/arm/boot/dts/overlays/vc4-kms-dsi-waveshare-panel-overlay.dts`
  (params confirmed: `10_1_inch`, `dsi0`, `rotation`, `invx`, `invy`, `swapxy`, `disable_touch`).
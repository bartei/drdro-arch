# CHANGELOG

<!-- version list -->

## v1.1.0 (2026-07-12)

### Continuous Integration

- Add mock static content deploy pipeline
  ([`7115fdf`](https://github.com/bartei/drdro-arch/commit/7115fdf240d227ee0f9dbf2c8cc292b1683832fe))

- Remove static content deploy pipeline
  ([`27ac494`](https://github.com/bartei/drdro-arch/commit/27ac494945b8a4126464226d6518e54feacbb0e2))

### Features

- Add Waveshare 10.1" DSI LCD (C) display support
  ([`330fc95`](https://github.com/bartei/drdro-arch/commit/330fc9530e6a3ba5ce30de5c726b49f8824fd802))


## v1.0.2 (2026-07-03)

### Bug Fixes

- Keep systemd-resolved — NM-owned resolv.conf broke DNS two ways
  ([`8cb7211`](https://github.com/bartei/drdro-arch/commit/8cb721110fdb80490ca68718cf2a15eb9d24e07a))

### Documentation

- 5 GHz on Pi 5 verified working — raspberry5 failures were a wrong PSK
  ([`62c838e`](https://github.com/bartei/drdro-arch/commit/62c838eef948c7dde74a7099652b31df405f5025))

- V1.0.2 wrap-up — all field findings closed and user-verified on Pi 3B + Pi 5
  ([`168e624`](https://github.com/bartei/drdro-arch/commit/168e6240eb766c89d3a0910beb446e6a40763af3))


## v1.0.2-beta.2 (2026-07-03)

### Bug Fixes

- Lift the Pi 5 USB current cap for the touchscreen
  ([`7bbaa63`](https://github.com/bartei/drdro-arch/commit/7bbaa6349408b240f663a74874c4ef4554d58bae))

- NetworkManager writes /etc/resolv.conf itself — DNS was dead on every fresh boot
  ([`2440990`](https://github.com/bartei/drdro-arch/commit/2440990dbc8aa4c16d4162e08408b2e9f11d6519))

### Documentation

- Field-test round 2 — keyboard+EEPROM verified, Pi 5 power root cause, DNS fix, 5 GHz trap open
  ([`d92df26`](https://github.com/bartei/drdro-arch/commit/d92df26c81a6132ecb92d5dd6757306049276656))


## v1.0.2-beta.1 (2026-07-02)

### Bug Fixes

- Self-heal old Pi 5 bootloader EEPROMs from the boot partition
  ([`e82e0a3`](https://github.com/bartei/drdro-arch/commit/e82e0a321c7ec77c2cd24bfc91e63dcf122c8144))

- Show the on-screen keyboard (Kivy keyboard_mode=systemanddock)
  ([`621e02a`](https://github.com/bartei/drdro-arch/commit/621e02a9aa4f32296f40d81ed23beb22fd303fb6))

### Documentation

- Record v1.0.1 field-test findings (vkeyboard, Pi 5 EEPROM)
  ([`ffd0911`](https://github.com/bartei/drdro-arch/commit/ffd0911ed933227f0915df648b3db20468b3a51e))


## v1.0.1 (2026-07-02)

### Bug Fixes

- **app**: Resolve 'latest' to the newest STABLE app tag (skip betas)
  ([`bd4b01b`](https://github.com/bartei/drdro-arch/commit/bd4b01b1963c749b00f62277ed700ddc3773b591))

### Continuous Integration

- Fold beta changes into stable release notes
  ([`1b66640`](https://github.com/bartei/drdro-arch/commit/1b66640871f796b2bc74562d98d6e21a35f66049))


## v1.0.0 (2026-07-02)

- Initial stable release — graduates v1.0.0-beta.1

## v1.0.0-beta.1 (2026-07-02)

- Initial Release

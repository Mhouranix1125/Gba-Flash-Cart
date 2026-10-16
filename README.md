# ChisFlash

An open-source Game Boy Advance flashcart (a reprogrammable GBA cartridge).

- [Discord](https://discord.gg/Hq8PSSpnEM)
- Original project by ChisBread, inspired by [opencartgba](https://github.com/laqieer/opencartgba).
- Latest PCB releases are published on OSHWHub: [ChisBread](https://oshwhub.com/eda_lmizqtvvk/works)

New here? Start with the [Project Overview](document/0-project-overview.md). It explains how the
pieces fit together in plain terms.

## How it works in one paragraph

A GBA cartridge has two main chips: a **ROM** that holds the game and a **save chip** that holds your
save file. The GBA talks to them over a 32-pin bus that shares pins between addresses and data, which
no off-the-shelf memory chip understands directly. ChisFlash puts a small programmable logic chip (a
**CPLD**, Altera MAX II EPM240) between the GBA and the memory. The CPLD latches and counts addresses
for a 256Mbit NOR flash chip (the "ROM") and handles save-chip bank switching, so games with 1Mbit
saves work.

## Board versions

| Board | Version | Save chip | Firmware folder | PCB + BOM |
| --- | --- | --- | --- | --- |
| Pichu ("Lite Edition") | v0.1 | 1Mbit SRAM (IS62LV1024), battery-backed | [firmware/QuartusII1MSRAM](firmware/QuartusII1MSRAM) | [oshwhub](https://oshwhub.com/chisbread/chisflash-pichu) |
| Prometheus | v1.0 | 1Mbit FRAM (FM28V100), no battery needed | [firmware/QuartusII1MFRAM](firmware/QuartusII1MFRAM) | [oshwhub](https://oshwhub.com/chisbread/chisflash-prometheus) |
| Celebi | v1.1 | 1Mbit Flash (SST39VF010); also supports 512Kbit Flash | [firmware/QuartusII1MFlash](firmware/QuartusII1MFlash) | [oshwhub](https://oshwhub.com/chisbread/chisflash-celebi) |

For 512Kbit Flash games on Celebi, see the [512Kbit ROM patch](https://github.com/ChisBread/gba-auto-batteryless-patcher/tree/custom_flashid).

The Celebi PCB also has an **S-3511A real-time clock chip**, a 32.768 kHz crystal, and a CR2032 battery
holder. The firmware does not drive the clock yet (see Features below).

## Features

The goal is a fully featured GBA flashcart.

| Feature | Status |
| --- | --- |
| 256Mbit (32MB) game ROM | ✅ |
| 512Kbit SRAM/FRAM saves | ✅ |
| 1Mbit SRAM/FRAM saves (bank switching) | ✅ |
| 1Mbit/512Kbit Flash saves (bank switching) | ✅ |
| Real-time clock (RTC) | ❌ (hardware present on Celebi, firmware not written) |
| Rumble | ❌ |
| Gyro sensor | ❌ |
| Solar sensor | ❌ |

## Images

![realcart](./images/realcart.png)
![top_v1.0](./images/top_v1.0.png)
![but_v1.0](./images/but_v1.0.png)
![top_v0.1](./images/top_v0.1.png)
![but_v0.1](./images/but_v0.1.png)

## Schematic

![schematic](./images/sch.png)

## Bill of materials

- [ChisFlash BOM](BOM.md)

## Repository layout

```
ChisFlash
├── README.md          This file
├── BOM.md             Parts list
├── LICENSE.txt        GPL-3.0
├── document/          Technical documentation
│   ├── 0-project-overview.md
│   └── 1-how-does-the-gba-cart-work.md
├── firmware/          CPLD firmware (Quartus II 13.0 SP1 projects, VHDL)
│   ├── QuartusII1MSRAM/   Pichu v0.1, 1Mbit SRAM
│   ├── QuartusII1MFRAM/   Prometheus v1.0, 1Mbit FRAM
│   └── QuartusII1MFlash/  Celebi v1.1, 1Mbit/512Kbit Flash (+ RTC hardware)
├── hardware/          PCB design files (EasyEDA Pro .epro projects)
└── images/            Photos and renders
```

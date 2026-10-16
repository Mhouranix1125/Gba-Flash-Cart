# ChisFlash Project Overview

This is a plain-English guide to what ChisFlash is, how its parts fit together, and where everything
lives in this repo. For bus-level detail, read [How Does a GBA Game Cartridge Work?](1-how-does-the-gba-cart-work.md)
next.

## What it is

ChisFlash is a reprogrammable GBA cartridge (a "flashcart"). You write a game ROM into its flash chip
with an external programmer, plug it into a GBA, and it behaves like the original cartridge, saves
included.

## The big picture

```
            GBA cartridge slot (32 pins)
   /CS /CS2 /RD /WR   AD0-AD15        A16-A23
     │    │   │   │      │               │
     ▼    ▼   ▼   ▼      ▼               ▼
  ┌──────────────────────────┐
  │   CPLD (EPM240, "mapper") │──ROM_A0-15──►┌──────────────────┐
  │  - latches + counts addr  │              │ ROM: 256Mbit NOR │◄── AD0-15 (data)
  │  - save bank select (BK)  │──BK (A16)──┐ │ flash (S29GL256) │◄── A16-23 (high addr)
  │  - LEDs                   │            │ └──────────────────┘
  └──────────────────────────┘            │ ┌──────────────────┐
                                           └►│ Save chip        │◄── AD0-15 (addr)
                                             │ SRAM / FRAM /    │◄─► A16-23 (data)
                                             │ Flash, 1Mbit     │
                                             └──────────────────┘
```

Why the CPLD is needed: to save pins, the GBA sends the low 16 bits of a ROM address on the same pins
it later uses for data (AD0-AD15). A normal flash chip needs its address held steady the whole time,
so the CPLD:

1. **Captures** the low 16 address bits when /CS falls, and sends them to the ROM chip on separate pins
   (`ROM_A`).
2. **Adds 1** to that address after each read or write strobe, because the GBA reads sequential data
   without resending the address.
3. **Picks the save bank.** The save chip holds 128KB, but the GBA can only see 64KB at once. The CPLD
   drives the save chip's top address line (A16, signal `BK`) when the game asks to switch banks.

The high 8 address bits (A16-A23) go straight from the slot to the ROM chip, since the GBA holds them
steady.

## The three board versions

All three use the same CPLD (Altera MAX II **EPM240T100C5N**) and the same ROM chip (**S29GL256S**,
256Mbit). They differ in the save chip:

| Board | Version | Save chip | How it remembers saves | Firmware |
|---|---|---|---|---|
| **Pichu** ("Lite Edition") | v0.1 | IS62LV1024 1Mbit SRAM | Coin cell battery + diode backup circuit | `firmware/QuartusII1MSRAM` (entity `chislite`) |
| **Prometheus** | v1.0 | FM28V100 1Mbit FRAM | FRAM keeps data without power | `firmware/QuartusII1MFRAM` (entity `chisflash`) |
| **Celebi** | v1.1 | SST39VF010 1Mbit Flash | Flash keeps data without power | `firmware/QuartusII1MFlash` (entity `chisflash`) |

The Celebi board also carries **RTC hardware**: an S-3511A real-time clock (U6), a 32.768 kHz crystal
(X1), and a CR2032 battery (BAT1) with a diode-OR power rail (`VMIX`) so the clock keeps running when the
cart is unpowered. The RTC connects to the CPLD through nets named `GPIO0`-`GPIO2` and `DEBUGIO0`.
**The firmware does not implement the RTC yet.** See "Adding RTC" below.

## How saving works on each board

GBA games use one of several save types. ChisFlash handles them like this:

- **SRAM/FRAM boards (Pichu, Prometheus).** These work with games that use SRAM saves, and with games
  patched to save to SRAM. For 1Mbit saves, the bank is chosen with the bootleg-cart convention of
  writing the bank number to GBA address `0x09000000`. The CPLD watches for that write and sets `BK`.
  Emulating the real Flash command set on these boards is still a TODO in the code.
- **Flash board (Celebi).** Games that natively use Flash saves (Pokémon, for example) send standard
  Flash commands: an unlock sequence `5555h=AAh, 2AAAh=55h`, then a command byte. The SST39VF010 chip
  carries out program and erase commands itself. The CPLD steps in for two things the SST chip
  can't do the way games expect:
    - **Chip ID (command `90h`).** Games check the Flash ID to choose their save routine. The CPLD
      holds `GBA_RD0` high, which disables the memory chips' outputs, and replies with a Macronix
      1Mbit ID (manufacturer `0xC2`, device `0x09`) instead.
    - **Bank switch (command `B0h`).** The CPLD records the bank number and drives `BK`.
  The reported ID can be changed at runtime by writing to `0x09000002` (manufacturer) and `0x09000004`
  (device). The 512Kbit ROM patch linked in the README relies on this.

## The LEDs

Both LEDs are wired so that pulling the CPLD pin low turns them on.

- **LED(1)** lights whenever the save chip is being accessed (/CS2 low).
- **LED(0)** "breathes" while the ROM is being read. A counter of bus accesses drives a simple software
  PWM that fades the LED in and out.

## Repo map

| Path | What's there |
|---|---|
| `firmware/*/*.vhd` | The CPLD logic, one VHDL file per board. Start here to understand the behavior. |
| `firmware/*/*.qsf` | Quartus settings, including the **CPLD pin assignments** for every signal. |
| `firmware/*/*.qpf` | Quartus project files. |
| `firmware/*/Waveform.vwf` | Simulation waveforms for Quartus' simulator. |
| `hardware/*.epro` | EasyEDA Pro projects (schematic + PCB), one per board. Open them in EasyEDA Pro. |
| `BOM.md` | Parts list. |
| `images/` | Board renders, a photo, and the schematic image. |

## Building and programming the firmware

1. Install **Quartus II 13.0 SP1** (Web Edition is free). This is the last version with good MAX II
   support and the version these projects were made with.
2. Open the `.qpf` for your board, then run **Processing → Start Compilation**.
3. Connect a USB-Blaster to the board's 6-pin JTAG header (XP1). Open **Tools → Programmer**, load the
   generated `.pof` file, and program the CPLD. The cart needs 3.3V power while you do this.

Writing the game ROM itself to the S29GL256 is a separate step that needs a GBA cart flasher. This repo
does not cover it.

## Adding RTC (notes for upcoming work)

What's already in place:

- **Protocol:** the game reaches the RTC through a GPIO port at `0x080000C4` (data), `0x080000C6`
  (direction), and `0x080000C8` (control). See section 3 of
  [the cart document](1-how-does-the-gba-cart-work.md#real-time-clock).
- **Hardware (Celebi only):** the S-3511A (U6), crystal (X1), and CR2032 (BAT1) are on the board. This
  wiring was read from the PCB netlist in `hardware/ProDoc_ChisFlash-Celebi.epro`:

  | S-3511A pin | Net | CPLD (U5) pin | Notes |
  |---|---|---|---|
  | 1 | `DEBUGIO0` | 33 | |
  | 2 | `XIN` | – | Crystal X1 + load capacitor C4 |
  | 3 | `XOUT` | – | Crystal X1 |
  | 5 | `GPIO2` | 28 | |
  | 6 | `GPIO0` | 29 | |
  | 7 | `GPIO1` | 30 | Pull-up resistor R2 |
  | 8 | `VMIX` | – | Supply, diode-OR of VCC and the CR2032 (D1, D2) |
  | – | `GPIO3` | 27 | Not connected to the RTC |

  Check the S-3511A datasheet for which pin is CS, SCK, SIO, and the interrupt output before writing
  the firmware.
- **Output gating (Celebi only):** the CPLD's `GBA_RD0` pin (75) drives `/OE` on both the ROM chip and
  the save chip, so the CPLD can silence the ROM and put its own data on the bus. That's exactly what
  RTC reads need. On Pichu and Prometheus, `/RD` goes straight to the memory chips, so those boards
  would need a hardware change for this.

What the firmware would need:

- Three small registers inside the CPLD, decoded at ROM halfword addresses `0x000062`, `0x000063`, and
  `0x000064` (GBA `0x080000C4`, `C6`, `C8`) with A16-A23 = `0x00`.
- On writes, update the registers and drive the RTC pins according to the direction bits.
- On reads, when the control register allows it, hold `GBA_RD0` high and have the CPLD drive the GPIO
  bits onto AD0-AD3 instead of the ROM.
- New ports for the RTC pins in the VHDL entity, with matching pin assignments in the `.qsf`.
- The EPM240 has 240 logic elements, and the Flash firmware already uses part of that, so the RTC logic
  has to stay small.

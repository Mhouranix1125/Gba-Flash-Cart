# How Does a GBA Game Cartridge Work?

## Introduction

This document explains how the Game Boy Advance talks to a cartridge, and why a flashcart like
ChisFlash needs a small logic chip (a CPLD) to make ordinary memory chips work in a GBA.

## 1. Cartridge Structure

### Cartridge Bus: Pinout

The cartridge slot has 32 pins with 1.5 mm spacing. Directions are from the GBA's point of view
(O = the GBA drives the pin, I = the cartridge drives it).

| Pin   | Name    | Direction | Description |
|-------|---------|-----------|-------------|
| 1     | VDD     | O   | Power, 3.3V DC |
| 2     | PHI     | O   | System clock (selectable: off, 4.19MHz, 8.38MHz, or 16.78MHz) |
| 3     | /WR     | O   | Write strobe. The latched address increments on each rising edge of /RD or /WR |
| 4     | /RD     | O   | Read strobe. The latched address increments on each rising edge of /RD or /WR |
| 5     | /CS     | O   | ROM chip select. Address bits A0-A15 are latched on its falling edge |
| 6-21  | AD0-15  | I/O | Low 16 address bits and/or 16-bit ROM data (see below) |
| 22-29 | A16-23  | I/O | High 8 ROM address bits, or 8-bit SRAM data (see below) |
| 30    | /CS2    | O   | SRAM (save chip) select |
| 31    | /REQ    | I   | Interrupt request (/IREQ) or DMA request (/DREQ) |
| 32    | GND     | O   | Ground, 0V |

A slash in front of a name (for example /CS) means the signal is **active low**: it does its job when
pulled to 0V.

When the GBA accesses **SRAM**, it puts a 16-bit address on AD0-AD15 and moves 8-bit data over A16-A23.

When the GBA accesses **ROM**, it puts a 24-bit address on AD0-AD15 plus A16-A23, then moves 16-bit
data over AD0-AD15.

The 24-bit ROM address is the real 25-bit memory address (counted in bytes) divided by two (counted in
16-bit halfwords).

Key points:

- AD0-AD15 carry the low 16 address bits.
    - The cartridge increments this address on every rising edge of /WR or /RD.
- ROM reads and writes
    - /CS enables the ROM chip. The address arrives on AD0-AD15 and A16-A23, and data moves over AD0-AD15.
    - AD0-AD15 carry both the ROM address and the data, so the cartridge must **latch** (capture and
      hold) the address when /CS falls. That frees the same pins for data.
    - The latched 16 bits plus A16-A23 form a 24-bit address. Each address holds 16 bits of data, giving
      256Mbit (32MB) of address space.
- RAM reads and writes
    - /CS2 enables the SRAM chip. The address arrives on AD0-AD15 and data moves over A16-A23.
    - The 16-bit address goes straight to the SRAM, with no latching needed. Each address holds 8 bits,
      giving 512Kbit (64KB) of address space. Bank switching, covered later, extends this.

### Cartridge Bus: Timing

Read/write timing for cartridge memory:

| Region          | Bus width | Read         | Write    | Cycles |
|-----------------|-----------|--------------|----------|--------|
| Cartridge Flash | 16-bit    | 8/16/32-bit  | 16/32-bit | 5/5/8 \*\*/\*\*\* |
| Cartridge ROM   | 16-bit    | 8/16/32-bit  | N/A      | 5/5/8 \*\*/\*\*\* |
| Cartridge SRAM  | 8-bit     | 8-bit        | 8-bit    | 5 \*\* |

Notes:
```
  *   Add 1 cycle if the GBA accesses video memory at the same time.
  **  Default wait-state settings. See the System Control chapter of GBATEK.
  *** Sequential and non-sequential accesses are timed separately.
  One cycle is about 59.59ns (a 16.78MHz clock).
```

#### Cartridge Bus: Summary

No mass-produced memory chip speaks this cartridge protocol directly.

Given the timing and power requirements, a CPLD/FPGA is a good way to build the glue logic in between.
It needs to:

- Latch the address and auto-increment it
- Pass the combined 24-bit address to the ROM chip
- Implement Flash ROM save backup, including bank switching for 1Mbit saves
- Implement 1Mbit FRAM saves by recognizing the Flash bank-switch command
- Handle other advanced features, such as rumble and a real-time clock

### ROM Chip

The ROM chip stores the game's program and data. Because of the bus limits above, it can be at most
256Mbit (32MB).

Flashcarts usually use parallel NOR flash for the ROM. It's easy to work with but relatively expensive.

### SRAM Chip

The SRAM chip stores save data. Because of the bus limits above, it can be at most 512Kbit (64KB).

Some GBA games use **bank switching**, which lets the cartridge expose 1Mbit (128KB) of save memory
through the same 64KB window, one half at a time.

Note: higher-end flashcarts use FRAM instead of battery-backed SRAM so the save survives without power.

## 2. Address Map

### Address Map

| Address range     | Function     | Size    | Description |
|-------------------|--------------|---------|-------------|
| 08000000-09FFFFFF | ROM/FlashROM | 32MB    | ROM/FlashROM address space (wait state 0) |
| 0A000000-0BFFFFFF | ROM/FlashROM | 32MB    | ROM/FlashROM address space (wait state 1) |
| 0C000000-0DFFFFFF | ROM/FlashROM | 32MB    | ROM/FlashROM address space (wait state 2) |
| 0E000000-0E00FFFF | SRAM         | 64KB    | SRAM address space (8-bit bus) |
| 0E010000-0FFFFFFF | Unused       | Unknown | Unused address space |

The three ROM regions are mirrors of the same 32MB. They differ only in how many wait states the GBA
inserts per access.

### Special Operations

#### Flash ROM Bank Switching

Games with 1Mbit Flash saves pick which 64KB half is visible by sending this command sequence:

```
  [E005555h]=AAh, [E002AAAh]=55h, [E005555h]=B0h  (select bank command)
  [E000000h]=bnk                                  (write bank number 0..1)
```

The first two writes are an "unlock" sequence that every Flash command starts with. B0h is the
bank-select command, and the next write gives the bank number.

## 3. Special Communication

Besides the ROM and SRAM chips, some special peripherals also talk to the GBA over the cartridge bus.
This section will be expanded later.

### Real-Time Clock

Pokémon Ruby/Sapphire/Emerald and a few other games use a Seiko S-3511 real-time clock. The game talks
to it through a 3-pin "GPIO" port mapped into ROM space:

| GBA address | Register | Purpose |
|-------------|----------|---------|
| 080000C4h   | Data     | Bit 0 = SCK (clock), bit 1 = SIO (data), bit 2 = CS (chip select) |
| 080000C6h   | Direction | 1 = pin is an output from the GBA, 0 = input |
| 080000C8h   | Control  | Bit 0 = 1 makes the port readable. When 0, reads return normal ROM data |

The game bit-bangs a serial protocol over these pins to read and set the date and time. The clock
values are stored in BCD. See GBATEK, section "GBA Cart Real-Time Clock (RTC)", for the full protocol.

### Rumble
### Solar Sensor
### Other

GBA cartridges can also include other peripherals, such as a real-time clock, rumble motor, or solar
sensor.

- Reference: [GBATEK](http://problemkaputt.de/gbatek.htm)

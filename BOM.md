# ChisFlash V1.0 BOM

| ID | Name | Designator | Footprint | Quantity | Manufacturer Part | Manufacturer | Supplier | Supplier Part |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | S29GL256S10TFI010 | U2 | TSOP-56_L18.4-W14.0-P0.50-LS20.0-TL | 1 | S29GL256S10TFI010 | SPANSION | LCSC | C1350995 |
| 2 | FM28V100-TG | U4 | STSOP-32_L8.0-W11.8-P0.50-LS13.4-TL | 1 | FM28V100-TG | CYPRESS | LCSC | C2959453 |
| 3 | 100nF | C1,C2 | C0603 | 2 |  |  |  |  |
| 4 | NCD0603B1 | LED1 | LED0603-RD | 1 | NCD0603B1 |  | LCSC | C84266 |
| 5 | NCD0603G1 | LED2 | LED0603-RD | 1 | NCD0603G1 |  | LCSC | C84267 |
| 6 | 1kΩ | R1 | R0603 | 1 | 0603WAF1001T5E | UNI-ROYAL |  | C21190 |
| 7 | 10uF | C3 | C0603 | 1 | CL10A106MA8NRNC | SAMSUNG |  | C96446 |
| 8 | EPM240T100C5N | U5 | TQFP-100_L14.0-W14.0-P0.50-LS16.0-BL | 1 | EPM240T100C5N | Intel/Altera |  | C10041 |

What each part does:

- **U2, S29GL256S10TFI010**: 256Mbit parallel NOR flash that holds the game ROM.
- **U4, FM28V100-TG**: 1Mbit FRAM that holds the save file. It keeps data without a battery.
- **U5, EPM240T100C5N**: MAX II CPLD, the "mapper" logic between the GBA bus and the memory chips.
- **LED1, LED2**: blue and green activity LEDs. **R1** is their current-limiting resistor.
- **C1-C3**: power-supply decoupling capacitors.

# ChisFlash V0.1 BOM

Same as V1.0, with these changes:

- Replace FM28V100-TG with IS62LV1024LL-55H (1Mbit SRAM).
- Add two 10kΩ resistors, one 100kΩ resistor, two 1N4148WS diodes, and one 1616 coin cell battery.
  These form the battery backup that keeps the SRAM save alive while the cart is unpowered.

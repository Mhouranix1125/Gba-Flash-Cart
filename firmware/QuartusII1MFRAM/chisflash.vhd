library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ChisFlash mapper for the v1.0 "Prometheus" board (1Mbit FRAM save chip).
--
-- What this CPLD does:
--   1. Latches the low 16 bits of the ROM address from the shared AD bus and
--      auto-increments it after every read/write strobe, so the parallel NOR
--      flash chip always sees a full, stable 24-bit address.
--   2. Drives the save chip's bank-select line (address bit A16) so a 64KB
--      window on the GBA can reach the full 128KB (1Mbit) FRAM.
--   3. Drives two activity LEDs.
--
-- Background on the GBA cartridge bus: document/1-how-does-the-gba-cart-work.md

-- chisflash entity declaration (the CPLD's pins)
entity chisflash is
	port (
		GBA_AD : in std_logic_vector(15 downto 0); -- GBA cart bus AD0-AD15: low 16 bits of the ROM address (also carries ROM data, which goes straight to the flash chip)
		GBA_A : in std_logic_vector(7 downto 0);   -- GBA cart bus A16-A23: high 8 bits of the ROM address (carries 8-bit data during save-chip access)
		GBA_CS : in std_logic;                     -- /CS: ROM chip select (active low)
		GBA_CS2 : in std_logic;                    -- /CS2: save chip (SRAM/FRAM) chip select (active low)
		GBA_RD : in std_logic; 		    		   -- /RD: read strobe (active low)
		GBA_WR : in std_logic; 		    		   -- /WR: write strobe (active low)
		ROM_A : out std_logic_vector(15 downto 0); -- Latched low 16 bits of the ROM address, sent to the flash chip's A0-A15
		GBA_BK : out std_logic := '0';             -- Save chip bank select (drives the FRAM's A16)
		LED : inout std_logic_vector(1 downto 0) := "ZZ" -- Activity LEDs (pulled low = on, high-Z = off)
	);
end chisflash;

-- Cart ROM address management and save chip bank selection
architecture cart of chisflash is
	signal GBA_RD_WR : std_logic;                    -- Combined strobe: goes low when either /RD or /WR is low
	signal ADDR : std_logic_vector(15 downto 0);     -- Latched low 16 bits of the ROM address
	signal BK : std_logic := '0';                    -- Current save chip bank (0 or 1)
	signal WR_RD_CNT : unsigned(25 downto 0) := (others => '0'); -- Counts ROM read/write strobes; drives the LED fade effect
begin
	GBA_RD_WR <= GBA_RD and GBA_WR;
	process (GBA_CS, GBA_RD_WR, GBA_AD) is
	begin
		-- See: document/1-how-does-the-gba-cart-work.md, section "Cartridge Bus: Pinout"
		if GBA_CS = '1' then
		-- While /CS is high the latch follows the AD bus, so the value held at the
		-- moment /CS falls is the address. This acts like latching on the falling edge of /CS.
			ADDR <= GBA_AD;
		elsif rising_edge(GBA_RD_WR) then
		-- On every rising edge of /RD or /WR, advance to the next address (sequential access)
			ADDR <= std_logic_vector(unsigned(ADDR) + 1);
			WR_RD_CNT <= WR_RD_CNT + 1;
		end if;
	end process;
	ROM_A <= ADDR;
	process (GBA_CS, GBA_CS2, GBA_WR, ADDR, GBA_A, GBA_AD) is
	begin
		-- Post-processing 1: save chip bank selection
		if GBA_CS = '0' and falling_edge(GBA_WR) then
		-- Bank select used by bootleg (reproduction) carts and by ROMs patched for them.
		--    How it works: those carts select the save bank by writing to GBA address 0x09000000.
		--        GBA 0x09000000 is ROM byte offset 0x1000000. The ROM bus is 16 bits wide, so the
		--        halfword address is 0x800000: high byte (A16-A23) = 10000000, low 16 bits
		--        (latched ADDR) = 0000000000000000. The bank number is bit 0 of the data written.
			if ADDR = "0000000000000000" and GBA_A = "10000000" then
				BK <= GBA_AD(0);
			end if;
		-- Post-processing 2: TODO. Emulate the standard Flash backup command set
		-- (the native save method used by Pokemon, Sonic, etc.)
		end if;
	end process;
	GBA_BK <= BK;
	-- Read/write activity LEDs
	process (GBA_CS, GBA_CS2, WR_RD_CNT) is
	begin
		if GBA_CS2 = '0' then
			LED(1) <= '0';
			-- Save chip is being accessed: LED(1) on, LED(0) off
			LED(0) <= 'Z';
		else
			LED(1) <= 'Z';
			-- While the ROM is being accessed, LED(0) is only active while the counter's top bit is 0
			if GBA_CS = '0' AND WR_RD_CNT(25) = '0' then
				-- Software PWM: compare the counter's upper bits with its lower bits to get a
				-- duty cycle that ramps up (bit 24 = 0) then down (bit 24 = 1), i.e. a "breathing" fade
				if  WR_RD_CNT(24) = '0' AND WR_RD_CNT(23 downto 12) > WR_RD_CNT(11 downto 0) then
					LED(0) <= '0';
				elsif WR_RD_CNT(24) = '1' AND WR_RD_CNT(23 downto 12) < WR_RD_CNT(11 downto 0) then
					LED(0) <= '0';
				else
					LED(0) <= 'Z';
				end if;
			else
				LED(0) <= 'Z';
			end if;
		end if;
	end process;
end cart;
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ChisFlash mapper for the v1.1 "Celebi" board (1Mbit Flash save chip, SST39VF010).
--
-- What this CPLD does:
--   1. Latches the low 16 bits of the ROM address from the shared AD bus and
--      auto-increments it after every read/write strobe (same as the other boards).
--   2. Watches the commands the game sends to the save flash chip so it can:
--        - answer "Chip ID" reads itself, reporting a Macronix 1Mbit ID
--          (0xC2 / 0x09) that games recognize, instead of the SST chip's real ID.
--          It does this by holding GBA_RD0 high, which disables the memory chips' outputs;
--        - handle the "bank switch" command, which the SST chip doesn't support,
--          by driving the chip's A16 line.
--      Program and erase commands pass straight through to the real flash chip.
--   3. Lets software change the reported ID (MID/DID) by writing to ROM address
--      0x09000002 / 0x09000004. This is how a ROM patched for 512Kbit Flash can be served.
--   4. Drives two activity LEDs.
--
-- Note: the board also has an S-3511A real-time clock (U6) wired to CPLD pins 27-30
-- (GPIO0-3) and 33 (DEBUGIO0), but this firmware does not implement the RTC yet.
-- See document/0-project-overview.md, "Adding RTC".
--
-- Background on the GBA cartridge bus: document/1-how-does-the-gba-cart-work.md

-- chisflash entity declaration (the CPLD's pins)
entity chisflash is
	port (
		GBA_AD : inout std_logic_vector(15 downto 0)
							:= "ZZZZZZZZZZZZZZZZ"; -- GBA cart bus AD0-AD15: low 16 bits of the address (also data)
		GBA_A : inout std_logic_vector(7 downto 0);   -- GBA cart bus A16-A23: high 8 bits of the ROM address, or 8-bit save data (the CPLD drives it when returning the chip ID)
		GBA_CS : in std_logic;                     -- /CS: ROM chip select (active low)
		GBA_CS2 : in std_logic;                    -- /CS2: save chip chip select (active low)
		GBA_RD : in std_logic; 		    		   -- /RD: read strobe (active low)
		GBA_WR : in std_logic; 		    		   -- /WR: write strobe (active low)
		ROM_A : out std_logic_vector(15 downto 0); -- Latched low 16 bits of the ROM address, sent to the ROM flash chip's A0-A15
		GBA_BK : out std_logic := '0';             -- Save chip bank select (drives the save flash's A16)
		GBA_RD0 : out std_logic := '1';                -- Gated /RD (active low): drives /OE of BOTH the ROM chip and the save chip. Held high so the CPLD can drive the bus instead
		LED : inout std_logic_vector(1 downto 0) := "ZZ";           -- Activity LEDs (pulled low = on, high-Z = off)
		DEBUGIO : inout std_logic_vector(1 downto 0) := "ZZ"      -- Spare debug I/O pins (unused)
	);
end chisflash;

-- Cart ROM address management and save bank selection
architecture cart of chisflash is
	signal GBA_RD_WR : std_logic;                    -- Combined strobe: goes low when either /RD or /WR is low
	signal ADDR : std_logic_vector(15 downto 0);     -- Latched low 16 bits of the ROM address
	signal BK : std_logic := '0';                    -- Current save bank (0 or 1)
	signal RD0 : std_logic := '1';                -- '1' = block the memory chips' outputs (the CPLD is answering instead)
	signal WR_RD_CNT : unsigned(25 downto 0) := (others => '0'); -- Counts ROM read/write strobes; drives the LED fade effect
	-- Flash command state machine. Addresses are save-chip addresses (GBA 0x0E00xxxx).
	-- State | Meaning
	-- 0000   | Idle
	-- 0001   | Got 5555h=AAh (first unlock write)
	-- 0010   | Got 5555h=AAh, 2AAAh=55h (unlocked, waiting for a command)
	-- 0011   | 5555h=AAh, 2AAAh=55h, 5555h=90h: Chip ID mode
	-- 0100   | 5555h=AAh, 2AAAh=55h, 5555h=B0h: Bank switch (next write selects the bank)
	-- 0101   | 5555h=AAh, 2AAAh=55h, 5555h=A0h: Write one byte          (reserved, not used below)
	-- 0110   | 5555h=AAh, 2AAAh=55h, 5555h=80h: Sector/chip erase start  (reserved, not used below)
	-- 0111   | Chip erase done                                       (reserved, not used below)
	-- 1000   | Sector erase done / byte write done                   (treated like idle below)
	-- 1001   | Sector/chip erase in progress                         (reserved, not used below)
	-- 1010   | Sector/chip erase in progress                         (reserved, not used below)
	-- 1111   | Unknown intermediate command                          (reserved, not used below)
	signal FLASH_STATUS : std_logic_vector(3 downto 0) := "0000"; -- 1M Flash command state
	-- Overridable by writing to GBA address 0x09000002
	signal MID : std_logic_vector(7 downto 0) := "11000010"; -- Reported Flash manufacturer ID (default 0xC2 = Macronix)
	-- Overridable by writing to GBA address 0x09000004
	signal DID : std_logic_vector(7 downto 0) := "00001001"; -- Reported Flash device ID (default 0x09 = 1Mbit MX29L010)
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
		if falling_edge(GBA_WR) then
			if GBA_CS = '0' then
				-- ROM-space write: let software override the reported Flash ID.
				-- A16-A23 = 0x80 selects ROM byte offset 0x1000000+ (GBA 0x09000000+).
				if GBA_A = "10000000" then
					-- Halfword 0x800001 = GBA 0x09000002: set MID
					if ADDR = "0000000000000001" then
						MID <= GBA_AD(7 downto 0);
					-- Halfword 0x800002 = GBA 0x09000004: set DID
					elsif ADDR = "0000000000000010" then
						DID <= GBA_AD(7 downto 0);
					end if;
				end if;
			elsif GBA_CS2 = '0' then
				-- Save-space write: track the Flash command sequence.
				-- During save access AD0-AD15 is the address and A16-A23 is the data byte.
				if FLASH_STATUS = "0000" or FLASH_STATUS = "1000" then
					-- 5555h=AAh
					if GBA_AD = "0101010101010101" and GBA_A = "10101010"  then
						FLASH_STATUS <= "0001";
					end if;
				elsif FLASH_STATUS = "0001" then
					-- (5555h=AAh already seen)
					-- 2AAAh=55h: unlock complete
					if GBA_AD = "0010101010101010" and GBA_A = "01010101" then
						FLASH_STATUS <= "0010";
					else
						FLASH_STATUS <= "0000";
					end if;
				elsif FLASH_STATUS = "0010" then
					-- (5555h=AAh, 2AAAh=55h already seen)
					-- The third write to 5555h is the command byte
					if GBA_AD = "0101010101010101" then
						-- 5555h=90h: enter Chip ID mode
						if GBA_A = "10010000" then
							FLASH_STATUS <= "0011";
						-- 5555h=B0h: bank switch
						elsif GBA_A = "10110000" then
							FLASH_STATUS <= "0100";
						else
							FLASH_STATUS <= "0000";
						end if;
					else
						FLASH_STATUS <= "0000";
					end if;
				elsif FLASH_STATUS = "0011" then
					-- Any write of F0h exits Chip ID mode
					if GBA_A = "11110000" then
						FLASH_STATUS <= "0000";
					end if;
				elsif FLASH_STATUS = "0100" then
					-- Bank switch: 0000h=bank, the bank number is bit 0 of the data byte
					BK <= GBA_A(0);
					FLASH_STATUS <= "0000";
				else
					FLASH_STATUS <= "0000";
				end if;
			end if;
		end if;
	end process;
	process (GBA_CS, GBA_CS2, GBA_RD, ADDR, GBA_A, GBA_AD, FLASH_STATUS) is
	begin
		if GBA_RD = '0' then
			if GBA_CS2 = '0' then
				if FLASH_STATUS = "0011" then
					-- Chip ID mode: the CPLD answers instead of the save chip
					-- (default: manufacturer 0xC2, device 0x09)
					if GBA_AD = "0000000000000001" then
						-- Read of 0001h: device ID
						RD0 <= '1';
						GBA_A <= DID;
					elsif GBA_AD = "0000000000000000" then
						-- Read of 0000h: manufacturer ID
						RD0 <= '1';
						GBA_A <= MID;
					else
						RD0 <= '0';
						GBA_A <= "ZZZZZZZZ";
					end if;
				else
					-- Normal save read: let the save chip drive the bus
					RD0 <= '0';
					GBA_A <= "ZZZZZZZZ";
				end if;
			else
				RD0 <= '0';
				GBA_A <= "ZZZZZZZZ";
			end if;
		else
			-- Not reading: release the buses
			RD0 <= '0';
			GBA_A <= "ZZZZZZZZ";
			GBA_AD <= "ZZZZZZZZZZZZZZZZ";
		end if;
	end process;
	GBA_RD0 <= RD0 or GBA_RD; -- Memory /OE: active only while /RD is low and the CPLD is not answering
	GBA_BK <= BK; -- Save bank select signal
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
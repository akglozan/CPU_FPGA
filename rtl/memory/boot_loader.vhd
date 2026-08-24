-- Parses the boot-load protocol (address+length header, then payload
-- bytes) arriving from spi_slave, and drives a Wishbone master
-- write-only bus to DMA the payload into SDRAM. Knows nothing about
-- SPI timing itself -- purely a consumer of rx_byte/rx_valid.
--
-- IMPORTANT TIMING CONSTRAINT: this module has no way to apply
-- backpressure to the incoming byte stream. If wb_ack_i takes longer
-- to arrive than the gap between two SPI byte arrivals, the byte that
-- arrives mid-write is silently lost. The SPI clock on the ESP32 side
-- MUST be kept slow enough that this never happens in practice --
-- verify against the SDRAM controller's worst-case write latency
-- before finalizing the SPI clock rate.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity boot_loader is
    port (
        clk     : in  std_logic;
        rst_n   : in  std_logic;

        -- Byte stream from spi_slave.
        rx_byte  : in  std_logic_vector(7 downto 0);
        rx_valid : in  std_logic;

        -- Wishbone master, write-only (this module never reads back
        -- from the bus, so there is no wb_dat_i port).
        wb_adr_o : out std_logic_vector(31 downto 0);
        wb_dat_o : out std_logic_vector(31 downto 0);
        wb_sel_o : out std_logic_vector(3 downto 0);
        wb_we_o  : out std_logic;
        wb_stb_o : out std_logic;
        wb_cyc_o : out std_logic;
        wb_ack_i : in  std_logic
    );
end entity boot_loader;

architecture rtl of boot_loader is

    -- ST_HDR_ADDR/ST_HDR_LEN: collecting the 8-byte per-file header
    -- (4-byte destination address, then 4-byte length), little-endian.
    -- ST_PAYLOAD: assembling payload bytes into a 32-bit word.
    -- ST_WRITE: driving one Wishbone write cycle for the word just
    -- assembled, then either continuing the same file or looping back
    -- to ST_HDR_ADDR for the next one.
    type state_t is (ST_HDR_ADDR, ST_HDR_LEN, ST_PAYLOAD, ST_WRITE);
    signal state : state_t := ST_HDR_ADDR;

    -- Destination address and remaining-bytes countdown for the file
    -- currently being received.
    signal addr_reg  : unsigned(31 downto 0) := (others => '0');
    signal remaining : unsigned(31 downto 0) := (others => '0');

    -- Word currently being assembled from incoming bytes, and how many
    -- of its 4 lanes are valid so far (0..3, i.e. the index of the
    -- lane the NEXT byte will land in) -- needed to build the correct
    -- wb_sel_o mask on the final, possibly-partial word of a file.
    signal word_reg      : std_logic_vector(31 downto 0) := (others => '0');
    signal bytes_in_word : natural range 0 to 4 := 0;
    signal sel_reg       : std_logic_vector(3 downto 0) := (others => '0');

begin

    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state         <= ST_HDR_ADDR;
                addr_reg      <= (others => '0');
                remaining     <= (others => '0');
                bytes_in_word <= 0;
                wb_cyc_o      <= '0';
                wb_stb_o      <= '0';
                wb_we_o       <= '0';
            else
                case state is

                    -- Collect 4 header bytes into addr_reg, little-endian
                    -- (first byte received -> bits 7:0).
                    when ST_HDR_ADDR =>
                        if rx_valid = '1' then
                            case bytes_in_word is
                                when 0 => addr_reg(7 downto 0)   <= unsigned(rx_byte);
                                when 1 => addr_reg(15 downto 8)  <= unsigned(rx_byte);
                                when 2 => addr_reg(23 downto 16) <= unsigned(rx_byte);
                                when others =>
                                    addr_reg(31 downto 24) <= unsigned(rx_byte);
                            end case;

                            if bytes_in_word = 3 then
                                bytes_in_word <= 0;
                                state <= ST_HDR_LEN;
                            else
                                bytes_in_word <= bytes_in_word + 1;
                            end if;
                        end if;

                    -- Collect 4 length bytes into remaining, same packing.
                    when ST_HDR_LEN =>
                        if rx_valid = '1' then
                            case bytes_in_word is
                                when 0 => remaining(7 downto 0)   <= unsigned(rx_byte);
                                when 1 => remaining(15 downto 8)  <= unsigned(rx_byte);
                                when 2 => remaining(23 downto 16) <= unsigned(rx_byte);
                                when others =>
                                    remaining(31 downto 24) <= unsigned(rx_byte);
                            end case;

                            if bytes_in_word = 3 then
                                bytes_in_word <= 0;
                                -- A zero-length header is a malformed/
                                -- edge case we shouldn't hang on -- go
                                -- to ST_PAYLOAD regardless; its own
                                -- remaining=0 handling below catches
                                -- this on the very next byte (or, if
                                -- no more bytes ever arrive for a
                                -- genuinely empty file, simply idles
                                -- there harmlessly until the next byte
                                -- does show up).
                                state <= ST_PAYLOAD;
                            else
                                bytes_in_word <= bytes_in_word + 1;
                            end if;
                        end if;

                    -- Accumulate payload bytes into word_reg. Flush to a
                    -- bus write when either the word fills up (4 bytes)
                    -- or the file's last byte lands (remaining bytes
                    -- exhausted), whichever comes first -- this second
                    -- condition is what correctly handles a payload
                    -- whose length isn't a multiple of 4 (e.g. DOOM1.WAD
                    -- is 4,207,819 bytes -- 3 bytes short of a whole
                    -- number of words).
                    when ST_PAYLOAD =>
                        if rx_valid = '1' then
                            case bytes_in_word is
                                when 0 => word_reg(7 downto 0)   <= rx_byte;
                                when 1 => word_reg(15 downto 8)  <= rx_byte;
                                when 2 => word_reg(23 downto 16) <= rx_byte;
                                when others =>
                                    word_reg(31 downto 24) <= rx_byte;
                            end case;

                            remaining <= remaining - 1;

                            if bytes_in_word = 3 or remaining = 1 then
                                -- Build the byte-enable mask for however
                                -- many lanes are actually valid in this
                                -- word (a full word if bytes_in_word=3,
                                -- otherwise a partial final word).
                                case bytes_in_word is
                                    when 0 => sel_reg <= "0001";
                                    when 1 => sel_reg <= "0011";
                                    when 2 => sel_reg <= "0111";
                                    when others => sel_reg <= "1111";
                                end case;
                                bytes_in_word <= 0;
                                state <= ST_WRITE;
                            else
                                bytes_in_word <= bytes_in_word + 1;
                            end if;
                        end if;

                    -- Hold the Wishbone write cycle asserted until the
                    -- slave acknowledges, then advance the destination
                    -- address by one word and either continue this
                    -- file's payload or, if that was the last word, go
                    -- back to waiting for the next file's header.
                    when ST_WRITE =>
                        wb_cyc_o <= '1';
                        wb_stb_o <= '1';
                        wb_we_o  <= '1';
                        wb_adr_o <= std_logic_vector(addr_reg);
                        wb_dat_o <= word_reg;
                        wb_sel_o <= sel_reg;

                        if wb_ack_i = '1' then
                            wb_cyc_o <= '0';
                            wb_stb_o <= '0';
                            wb_we_o  <= '0';
                            addr_reg <= addr_reg + 4;

                            if remaining = 0 then
                                state <= ST_HDR_ADDR;
                            else
                                state <= ST_PAYLOAD;
                            end if;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;

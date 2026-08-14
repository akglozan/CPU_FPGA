library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity uart_tx is
    generic (
        CLK_FREQ  : positive := 50000000;
        BAUD_RATE : positive := 115200
    );
    port (
        clk      : in  std_logic;
        rst_n    : in  std_logic;
        tx_data  : in  std_logic_vector(7 downto 0);
        tx_start : in  std_logic;
        tx_busy  : out std_logic;
        tx_out   : out std_logic
    );
end entity uart_tx;

architecture rtl of uart_tx is

    -- 50 MHz / 115200 = 434 clocks per UART bit.
    constant CLKS_PER_BIT : positive := CLK_FREQ / BAUD_RATE;

    type state_t is (
        STATE_IDLE,
        STATE_START,
        STATE_DATA,
        STATE_STOP
    );

    signal state     : state_t := STATE_IDLE;
    signal clk_count : natural range 0 to CLKS_PER_BIT - 1 := 0;
    signal bit_index : natural range 0 to 7 := 0;
    signal tx_shift  : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_reg    : std_logic := '1';
    signal busy_reg  : std_logic := '0';

begin

    assert CLK_FREQ >= BAUD_RATE
        report "uart_tx: CLK_FREQ must be greater than or equal to BAUD_RATE"
        severity failure;

    tx_out  <= tx_reg;
    tx_busy <= busy_reg;

    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state     <= STATE_IDLE;
                clk_count <= 0;
                bit_index <= 0;
                tx_shift  <= (others => '0');
                tx_reg    <= '1';
                busy_reg  <= '0';

            else
                case state is

                    when STATE_IDLE =>
                        tx_reg    <= '1';
                        clk_count <= 0;
                        bit_index <= 0;
                        busy_reg  <= '0';

                        if tx_start = '1' then
                            tx_shift  <= tx_data;
                            tx_reg    <= '0';
                            busy_reg  <= '1';
                            state     <= STATE_START;
                        end if;

                    when STATE_START =>
                        tx_reg   <= '0';
                        busy_reg <= '1';

                        if clk_count = CLKS_PER_BIT - 1 then
                            clk_count <= 0;
                            bit_index <= 0;
                            state     <= STATE_DATA;
                        else
                            clk_count <= clk_count + 1;
                        end if;

                    when STATE_DATA =>
                        tx_reg   <= tx_shift(bit_index);
                        busy_reg <= '1';

                        if clk_count = CLKS_PER_BIT - 1 then
                            clk_count <= 0;

                            if bit_index = 7 then
                                bit_index <= 0;
                                state     <= STATE_STOP;
                            else
                                bit_index <= bit_index + 1;
                            end if;
                        else
                            clk_count <= clk_count + 1;
                        end if;

                    when STATE_STOP =>
                        tx_reg   <= '1';
                        busy_reg <= '1';

                        if clk_count = CLKS_PER_BIT - 1 then
                            clk_count <= 0;
                            busy_reg  <= '0';
                            state     <= STATE_IDLE;
                        else
                            clk_count <= clk_count + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
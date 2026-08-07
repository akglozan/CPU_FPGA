library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity uart_tx is
    generic (
        CLK_FREQ  : integer := 50_000_000; -- 50 MHz system clock
        BAUD_RATE : integer := 115_200     -- Target baud rate
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        -- MMIO Interface
        tx_data  : in  std_logic_vector(7 downto 0);
        tx_start : in  std_logic;
        tx_busy  : out std_logic;
        -- Physical Output Pin
        tx_out   : out std_logic
    );
end entity uart_tx;

architecture Behavioral of uart_tx is

    type state_type is (IDLE, START, DATA, STOP);
    signal current_state, next_state : state_type;

    -- Internal counters and registers
    signal counter   : unsigned(8 downto 0) := (others => '0');
    signal bit_index : unsigned(2 downto 0) := (others => '0');
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal baud_tick : std_logic := '0';

begin

    -- Synchronous Process: State update, Baud Prescaler, and Datapath Outputs
    process(clk, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
            counter       <= (others => '0');
            baud_tick     <= '0';
            bit_index     <= (others => '0');
            shift_reg     <= (others => '0');
            tx_out        <= '1';
            tx_busy       <= '0';
        elsif rising_edge(clk) then
            -- Advance FSM State
            current_state <= next_state;

            -- Baud Prescaler Counter
            if counter = 0 then
                baud_tick <= '1';
                counter   <= to_unsigned(433, counter'length);
            else
                baud_tick <= '0';
                counter   <= counter - 1;
            end if;

            -- State-dependent Datapath Actions
            case current_state is
                when IDLE =>
                    if tx_start = '1' then
                        shift_reg <= tx_data;
                    end if;
                    counter   <= to_unsigned(433, counter'length); -- Keep counter loaded in IDLE
                    bit_index <= (others => '0');
                    tx_out    <= '1';
                    tx_busy   <= '0';

                when START =>
                    tx_out  <= '0'; -- Start bit (space)
                    tx_busy <= '1';

                when DATA =>
                    if baud_tick = '1' then
                        shift_reg <= '0' & shift_reg(7 downto 1); -- Shift right LSB first
                        bit_index <= bit_index + 1;
                    end if;
                    tx_out  <= shift_reg(0);
                    tx_busy <= '1';

                when STOP =>
                    bit_index <= (others => '0');
                    tx_out    <= '1'; -- Stop bit (mark)
                    tx_busy   <= '1';
            end case;
        end if;
    end process;

    -- Combinational Process: Next-State Logic (VHDL-2008)
    process(all)
    begin
        case current_state is
            when IDLE =>
                if tx_start = '1' then
                    next_state <= START;
                else
                    next_state <= IDLE;
                end if;

            when START =>
                if baud_tick = '1' then
                    next_state <= DATA;
                else
                    next_state <= START;
                end if;

            when DATA =>
                if baud_tick = '1' then
                    if bit_index = 7 then
                        next_state <= STOP;
                    else
                        next_state <= DATA;
                    end if;
                else
                    next_state <= DATA;
                end if;

            when STOP =>
                if baud_tick = '1' then
                    next_state <= IDLE;
                else
                    next_state <= STOP;
                end if;
        end case;
    end process;

end architecture Behavioral;
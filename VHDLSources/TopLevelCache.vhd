---------------------------------------------------------------------------------------------------------
-- Author: Coby Cockrell
-- Date: 11/08/2024
-- Purpose: Top-level entity combining MainCache and ARCManagementPolicy to implement a cache system with
--          an Adaptive Replacement Cache (ARC) policy.
---------------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity TopLevelCache is
    generic(
        ADDR_WIDTH : integer := 32;  --Address bus width for MainCache
        DATA_WIDTH : integer := 32;  --Data bus width for MainCache
        CACHE_SIZE : integer := 64   --Total number of cache lines for ARC policy
    );
    port (
        clk         : in  std_logic;
        reset       : in  std_logic;
        addr        : in  std_logic_vector(ADDR_WIDTH-1 downto 0); --Incoming address
        data_in     : in  std_logic_vector(DATA_WIDTH-1 downto 0); 
        data_out    : out std_logic_vector(DATA_WIDTH-1 downto 0); 
        hit_rate    : out integer;                                 --Hit rate as a percentage (0 to 100)
        wait_out_signal : out std_logic
        --average_latency : out integer                              --Average latency in cycles
    );
end TopLevelCache;

architecture Behavioral of TopLevelCache is

    --Signals to connect MainCache and ARCManagementPolicy
    signal hit_signal      : std_logic;                           --Hit signal from MainCache to ARC policy
    signal replace_way_sig : integer range 0 to CACHE_SIZE-1;     --Replacement way from ARC policy to MainCache
    
    --Additional signals for hit rate and latency calculations
    signal total_hits      : integer := 0;                        --Total number of hits
    signal total_accesses  : integer := 0;                        --Total number of accesses (hits + misses)
    --signal total_latency   : integer := 0;                        --Cumulative latency for all accesses
    --signal current_latency : integer := 0;                        --Latency of the current access
    signal prev_addr       : std_logic_vector(ADDR_WIDTH-1 downto 0); --Previous address for comparison

    --Internal control signals
    signal internal_write_en : std_logic := '0';                  --Internal write enable signal
    signal miss_detected     : std_logic := '0';                  --Signal to track if a miss was detected

    --State machine signals
    type cache_state_type is (IDLE, STABILIZE, MISS, WRITE_AFTER_MISS, READ_WAIT);
    signal cache_state       : cache_state_type := IDLE;
    signal next_state        : cache_state_type := IDLE;
    signal data_out_internal : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal wait_signal       : std_logic;
    


begin
    
    data_out <= data_out_internal;
    wait_out_signal <= wait_signal;
    --Instantiate ARCManagementPolicy
    ARCPolicyInst: entity work.ARCManagementPolicy
        generic map (
            ADDR_WIDTH => ADDR_WIDTH,      --Address width for ARC policy (same as MainCache)
            CACHE_SIZE => CACHE_SIZE       --Total number of cache lines for ARC policy
        )
        port map (
            clk         => clk,
            reset       => reset,
            addr        => addr(ADDR_WIDTH-1 downto 0), --Pass most significant bits of address
            hit         => hit_signal,     
            replace_way => replace_way_sig
        );

    -- Instantiate MainCache
    CacheInst: entity work.MainCache
        generic map (
            ADDR_WIDTH => ADDR_WIDTH,      --Address width for MainCache
            DATA_WIDTH => DATA_WIDTH       --Data width for MainCache
        )
        port map (
            clk             => clk,
            reset           => reset,
            addr            => addr,       --Pass full address to MainCache
            data_in         => data_in,    --Input data for writes
            data_out        => data_out_internal,   --Output data for reads
            write_en        => internal_write_en,   --Use internal write enable signal here.
            hit             => hit_signal,          --Output hit signal to ARC policy
            replace_way     => replace_way_sig,      --Replacement way from ARC policy.
            wait_signal     => wait_signal
        );

    process(clk)
    begin
        if rising_edge(clk) then

            if reset = '1' then 
                cache_state <= IDLE;
                internal_write_en <= '0';
                total_hits <= 0;
                total_accesses <= 0;
                --total_latency <= 0;
                --current_latency <= 0;
                prev_addr <= (others => '0');
                miss_detected <= '0';
                
            
            else 
                cache_state <= next_state;

                case cache_state is

                    when IDLE =>
                        if addr /= prev_addr then 
                            total_accesses <= total_accesses + 1;
                            
                            next_state <= STABILIZE;
                          
                            prev_addr <= addr;               --Update previous address.
                        end if;
                        
                    when STABILIZE => 
                        if hit_signal = '1' then 
                                total_hits <= total_hits + 1;
                                --current_latency <= 3;         --Hit latency is 3 cycles.
                                next_state <= IDLE;     --Wait for data_out to propagate.
                                
                            else 
                                --current_latency <= 20;        --Miss latency is fixed at 20 cycles.
                                miss_detected <= '1';         --Mark that a miss has been detected.
                                next_state <= MISS;           --Move to MISS state.
                                
                            end if;
                            
                            
                    when MISS =>
                        internal_write_en <= '1';             --Enable write after miss.
                        next_state <= WRITE_AFTER_MISS;       --Move to WRITE_AFTER_MISS state.
                        

                    when WRITE_AFTER_MISS =>
                        internal_write_en <= '0';             --Disable write enable after writing.
                        next_state <= IDLE;             --Move to READ_WAIT state.
                        


                    when others =>
                        next_state <= IDLE;

                end case;
                
                --total_latency <= total_latency + current_latency;
            end if;

        end if;
    end process;

    process(total_hits, total_accesses)
    begin
        if total_accesses > 0 then 
            hit_rate <= (total_hits * 100) / total_accesses;      --Hit rate as a percentage.
            --average_latency <= total_latency / total_accesses;   --Average latency in cycles.
        else 
            hit_rate <= 0;
            --average_latency <= 0;
        end if;
    end process;

end Behavioral;

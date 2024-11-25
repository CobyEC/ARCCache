---------------------------------------------------------------------------------------------------------
--Author: Coby Cockrell
--Date: 11/09/2024 
--Purpose: This file impliments the cache itself, managing the instantiated ways, and coordinating read/write signals
---------------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity MainCache is
    generic(
        ADDR_WIDTH : integer := 32;  --Width of address bus
        DATA_WIDTH : integer := 32   --Width of data bus
    );
    port (
        clk         : in  std_logic;
        reset       : in  std_logic;
        addr        : in  std_logic_vector(ADDR_WIDTH-1 downto 0); --Incoming address
        data_in     : in  std_logic_vector(DATA_WIDTH-1 downto 0); 
        data_out    : out std_logic_vector(DATA_WIDTH-1 downto 0); 
        write_en    : in  std_logic;                               --Write enable signal
        hit         : out std_logic;                               
        replace_way : in  integer range 0 to 1;            --Way to replace (from ARC)
        wait_signal : out std_logic
    );
end MainCache;

architecture Structural of MainCache is
    
    function log2(value: integer) return integer is
    variable result: integer := 0;
    variable temp: integer := value;
    begin
        if value <= 0 then
            return -1; --Return -1 for invalid input (logarithm not defined for non-positive values)
        end if;
    
        while temp > 1 loop
            temp := temp / 2; --Divide by 2 iteratively
            result := result + 1; 
        end loop;
    
        return result;
    end function;
    
    
    
    constant NUM_WAYS           : integer := 4;   
    constant TOTAL_CACHE_SIZE   : integer := 64; 
    constant CACHE_LINES_PER_WAY: integer := TOTAL_CACHE_SIZE / NUM_WAYS;

    --Derived constants for tag and index sizes
    constant TAG_BITS   : integer := ADDR_WIDTH - log2(CACHE_LINES_PER_WAY);
    constant INDEX_BITS : integer := log2(CACHE_LINES_PER_WAY);

    --Signal types for hits, valid bits, and data outputs from each way
    type hit_array_type is array (0 to NUM_WAYS-1) of std_logic;
    type valid_array_type is array (0 to NUM_WAYS-1) of std_logic;
    type way_data_array_type is array (0 to NUM_WAYS-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    type wait_array_type is array (0 to NUM_WAYS-1) of std_logic;

    --Signals for hits, valid bits, and data outputs from each way
    signal way_hits         : hit_array_type;
    signal valid_sig        : valid_array_type;
    signal way_data_outs    : way_data_array_type;
    signal wait_array       :wait_array_type;

    --Write enable signals for each way
    signal write_enable_signals: std_logic_vector(NUM_WAYS-1 downto 0);

    --Address breakdown signals
    signal addr_tag     : std_logic_vector(TAG_BITS-1 downto 0);
    signal addr_index   : std_logic_vector(INDEX_BITS-1 downto 0);
    
    
    --Map addr_index directly to read_line_index and write_line_index
    signal read_line_index: integer range 0 to CACHE_LINES_PER_WAY-1;
begin

    --Split incoming address into tag and index fields
    addr_tag <= addr(ADDR_WIDTH-1 downto INDEX_BITS);
    addr_index <= addr(INDEX_BITS-1 downto 0);

   process(replace_way, write_en)
    variable temp_write_enable_signals : std_logic_vector(NUM_WAYS-1 downto 0);
    begin
        --Default: disable all ways
        temp_write_enable_signals := (others => '0');
        
        --Enable only the selected way if replace_way is valid
        if replace_way >= 0 and replace_way < NUM_WAYS then
            temp_write_enable_signals(replace_way) := write_en;
        end if;
        
        --Assign the modified variable back to the signal
        write_enable_signals <= temp_write_enable_signals;
    end process;

    read_line_index <= to_integer(unsigned(addr_index));

    -- Instantiate CacheWay modules for each way
    gen_ways: for j in 0 to NUM_WAYS-1 generate
        WayInst: entity work.CacheWay
            generic map (
                DATA_WIDTH => DATA_WIDTH,
                ADDR_WIDTH => TAG_BITS,               --Pass only tag bits as ADDR_WIDTH for CacheWay
                CACHE_LINES => CACHE_LINES_PER_WAY    --Adjust cache lines per way dynamically
            )
            port map (
                clk              => clk,
                reset            => reset,
                addr_tag         => addr_tag,         
                data_in          => data_in,
                data_out         => way_data_outs(j),
                write_en         => write_enable_signals(j),
                valid            => valid_sig(j),
                hit              => way_hits(j),
                write_line_index => read_line_index,   --Use index for both reads and writes
                read_line_index  => read_line_index,   --Use index for both reads and writes
                WAIT_DAMMIT => wait_array(j)
            );
    end generate;

    --Combine hits and data outputs from all ways
    process(way_hits, way_data_outs)
        variable found_hit : boolean := false; --Variable to track if a hit is found
    begin
        hit <= '0';                            --Default: No hit
        data_out <= (others => 'Z');           --Default: High impedance
        wait_signal <= '1';
    
        for j in way_hits'range loop 
            if way_hits(j) = '1' then          --If any way registers a hit:
                hit <= '1';                    --Set global hit signal
                data_out <= way_data_outs(j);  --Output data from the hitting way
                found_hit := true;             --Mark that a hit was found
                wait_signal <= wait_array(j);
                exit;                          
            end if;
        end loop;
    end process;

end Structural;

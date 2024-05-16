library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sid_coeffs_mux_tb is
  
end entity sid_coeffs_mux_tb;

architecture testbench of sid_coeffs_mux_tb is

  signal clk, we, cs            	: std_logic := '0';
  signal val0, val1, val2, val3 	: unsigned(15 downto 0) := (others => '0');
  signal val4, val5, val6, val7 	: unsigned(15 downto 0) := (others => '0');
  signal addr0, addr1, addr2, addr3     : integer range 0 to 2047 := 0;
  signal addr4, addr5, addr6, addr7     : integer range 0 to 2047 := 0;
  signal wraddr                         : unsigned(11 downto 0) := (others => '0');
  signal di, do                         : unsigned(7 downto 0) := (others => '0');
  
begin  -- architecture testbench

  sid_coeffs_mux : entity work.sid_coeffs_mux(mayan)
    port map (
      clk   => clk,
      val0  => val0,
      val1  => val1,
      val2  => val2,
      val3  => val3,
      val4  => val4,
      val5  => val5,
      val6  => val6,
      val7  => val7,
      addr0 => addr0,
      addr1 => addr1,
      addr2 => addr2,
      addr3 => addr3,
      addr4 => addr4,
      addr5 => addr5,
      addr6 => addr6,
      addr7 => addr7,
      waddr => wraddr,
      we    => we,
      cs    => cs,
      di    => di,
      do    => do);

  main_testbench: process is

    type pattern_type is record
      addr0, addr1, addr2, addr3 : integer range 0 to 2047;
      wraddr                      : unsigned(11 downto 0);
      cs, we                     : std_logic;
      di                         : unsigned(7 downto 0);
      delay                      : integer; 
    end record pattern_type;

    type pattern_array is array (natural range <>) of pattern_type;

    constant patterns : pattern_array := (
      (0, 10, 200, 1000, x"000", '0', '0', x"00", 40),
      (0, 10, 200, 1000, x"001", '1', '0', x"00", 2),
      (0, 10, 200, 1000, x"001", '0', '1', x"AD", 2),
      (0, 10, 200, 1000, x"001", '1', '1', x"DE", 2),
      (1, 10, 200, 1000, x"001", '0', '0', x"00", 40)
      );
    
  begin  -- process main_testbench

    for i in patterns'range loop

      addr0 <= patterns(i).addr0;
      addr1 <= patterns(i).addr1;
      addr2 <= patterns(i).addr2;
      addr3 <= patterns(i).addr3;
      wraddr <= patterns(i).wraddr;
      cs <= patterns(i).cs;
      we <= patterns(i).we;
      di <= patterns(i).di;
      for j in 0 to patterns(i).delay loop
        clk <= '1';
        wait for 0.5 us;
        clk <= '0';
        wait for 0.5 us;
      end loop;  -- j      
    end loop;  -- i

    assert false report "Test completed" severity note;

    wait;
    
  end process main_testbench;

end architecture testbench;

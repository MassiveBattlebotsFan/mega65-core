library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lowpass_tb is
  
end entity lowpass_tb;

architecture testbench of lowpass_tb is

  signal signal_in, signal_out : unsigned(31 downto 0);
  signal step : std_logic := '0';
  
begin  -- architecture testbench

  lowpass : entity work.resistor_capacitor(Experimental)
    generic map (
      capacitor_f => 0.00000000047,
      charge_res_ohm => 1153.0,
      discharge_res_ohm => 1153.0)
    port map (
      signal_in  => signal_in,
      signal_out => signal_out,
      step => step);

  -- purpose: main testbench process
  -- type   : combinational
  -- inputs : 
  -- outputs: 
  main: process is

    type pattern_type is record
      signal_in : unsigned(31 downto 0);
      delay     : integer;
    end record pattern_type;
    
    type pattern_array is array (natural range <>) of pattern_type;
    
    constant pattern : pattern_array := (
      (x"00000000",40),
      (x"FFFFFFFF",400000),
      (x"40000000",8000),
      (x"c0000000",400000)
      );
    
  begin  -- process main

    for i in pattern'range loop

      signal_in <= pattern(i).signal_in;

      for delaytime in 0 to pattern(i).delay loop
        step <= '1';
        wait for 12.5 ns;
        step <= '0';
        wait for 12.5 ns;        
      end loop;  -- delaytime
      
    end loop;  -- i

    assert false report "Test complete" severity note;

    wait;
    
  end process main;

end architecture testbench;

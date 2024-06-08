library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity timer555 is
  
end entity timer555;

architecture testbench of timer555 is

  signal cap_input, cap_output : unsigned(31 downto 0) := (others => '0');
  signal step, reset, output : std_logic := '0';

  signal thresh_pos, trig_neg : unsigned(31 downto 0) := (others => '0');
  signal thresh_output, trig_output : std_logic := '0';
begin  -- architecture testbench

  ext_rc1 : entity work.resistor_capacitor(Experimental)
    generic map (
      capacitor_f => 0.000001,
      charge_res_ohm => 10000.0,
      discharge_res_ohm => 10330.0)
    port map (
      signal_in  => cap_input,
      signal_out => cap_output,
      step => step);

  thresh_comp : entity work.comparator(Experimental)
    port map (
      pos    => thresh_pos,
      neg    => x"AAAAAAAA",
      output => thresh_output,
      step   => step);
  
  trig_comp : entity work.comparator(Experimental)
    port map (
      pos    => x"55555555",
      neg    => trig_neg,
      output => trig_output,
      step   => step);

  logic: process (step, reset, thresh_output, trig_output, cap_output) is
  begin  -- process logic
    if rising_edge(step) then
      if reset = '1' then
        output <= '0';
      else
        if trig_output = '1' then
          output <= '1';
        else
          if thresh_output = '1' then
            output <= '0';
          end if;
        end if;
      end if;
      cap_input <= (others => output);
      thresh_pos <= cap_output;
      trig_neg <= cap_output;
    end if;
  end process logic;
  
  -- purpose: main testbench process
  -- type   : combinational
  -- inputs : 
  -- outputs: 
  main: process is

    type pattern_type is record
      reset     : std_logic;
      delay     : integer;
    end record pattern_type;
    
    type pattern_array is array (natural range <>) of pattern_type;
    
    constant pattern : pattern_array := (
      ('1',400),
      ('0',1000000)
      );
    
  begin  -- process main

    for i in pattern'range loop

      reset <= pattern(i).reset;
      
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

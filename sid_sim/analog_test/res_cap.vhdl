library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity resistor_capacitor is
  
  generic (
    capacitor_uf : integer := 470;
    charge_res_mohm : integer := 1000;
    discharge_res_mohm : integer := 1000);  -- capacitor multiplication coefficient

  port (
    signal_in  : in  unsigned(31 downto 0);  -- input signal
    signal_out : out unsigned(31 downto 0) := (others => '0');
    step : in std_logic
    );  -- output signal

end entity resistor_capacitor;

architecture Experimental of resistor_capacitor is
  subtype analog is unsigned(31 downto 0);
  subtype signed_analog is signed(31 downto 0);

  constant charge_coefficient : analog := x"ffffffff" / (charge_res_mohm * capacitor_uf);
  constant discharge_coefficient : analog := x"ffffffff" / (discharge_res_mohm * capacitor_uf);
  
  -- purpose: accumulate change in capacitor
  function cap_acc (
    current, target : analog)
    return analog is

    variable diff_ct, diff_tc : analog;
    variable diff_scaled : unsigned(63 downto 0);  -- 32 bit * 32 bit is 64 bit max
  begin  -- function cap_acc

    diff_ct := current - target;
    diff_tc := target - current;

    if target < current then
      diff_scaled := diff_ct * discharge_coefficient;
      return current - diff_scaled(63 downto 32);
    else
      diff_scaled := diff_tc * charge_coefficient;
      return current + diff_scaled(63 downto 32);
    end if;
    
  end function cap_acc;
  
begin  -- architecture Experimental

  main: process (signal_in, step) is
    variable cap1_in : analog := (others => '0');
    variable cap1_out : analog := (others => '0');
  begin  -- process main

    if rising_edge(step) then
      cap1_in := signal_in;
      cap1_out := cap_acc(cap1_out, cap1_in);
      signal_out <= cap1_out;
    end if;
    
  end process main;
  
end architecture Experimental;

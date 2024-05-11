library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity comparator is
  
  port (
    pos : in  unsigned(31 downto 0);
    neg : in  unsigned(31 downto 0);
    output   : out std_logic;
    step     : in  std_logic);

end entity comparator;

architecture Experimental of comparator is

begin  -- architecture Experimental

  main: process (step) is
  begin  -- process main
    if rising_edge(step) then
      if pos > neg then
        output <= '1';
      else
        output <= '0';
      end if;
    end if;
  end process main;

end architecture Experimental;

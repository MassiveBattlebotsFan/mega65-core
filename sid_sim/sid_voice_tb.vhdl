library IEEE;
use IEEE.numeric_std.all;
use IEEE.std_logic_1164.all;

entity sid_voice_tb is
  
end entity sid_voice_tb;

architecture testbench of sid_voice_tb is

  signal clock, clock_1MHz, reset : std_logic := '0';
  signal Freq_lo, Freq_hi : unsigned(7 downto 0);
  signal Pw_lo, Pw_hi : unsigned(7 downto 0);
  signal Control : unsigned(7 downto 0);
  signal Att_dec, Sus_Rel : unsigned(7 downto 0);
  signal PA_MSB_in, PA_MSB_out : std_logic;
  signal Osc, Env : unsigned(7 downto 0);
  signal voice : unsigned(11 downto 0);
  
begin  -- architecture testbench

  sid_voice : entity work.sid_voice(Behavioral)
    port map (
      cpuclock   => clock,
      clk_1MHz   => clock_1MHz,
      reset      => reset,
      Freq_lo    => Freq_lo,
      Freq_hi    => Freq_hi,
      Pw_lo      => Pw_lo,
      Pw_hi      => Pw_hi,
      Control    => Control,
      Att_dec    => Att_dec,
      Sus_Rel    => Sus_Rel,
      PA_MSB_in  => PA_MSB_in,
      PA_MSB_out => PA_MSB_out,
      Osc        => Osc,
      Env        => Env,
      voice      => voice);

  -- purpose: main testbench process
  -- type   : combinational
  -- inputs : 
  -- outputs: 
  main: process is

    type pattern_type is record
      Freq_lo   : unsigned(7 downto 0);
      Freq_hi   : unsigned(7 downto 0);
      Pw_lo     : unsigned(7 downto 0);
      Pw_hi     : unsigned(7 downto 0);
      Control   : unsigned(7 downto 0);
      Att_dec   : unsigned(7 downto 0);
      Sus_Rel   : unsigned(7 downto 0);
      PA_MSB_in : std_logic;
      reset     : std_logic;
      delay     : integer;
    end record pattern_type;

    type pattern_array is array (natural range <>) of pattern_type;

    constant patterns : pattern_array := (
      (x"00", x"00", x"00", x"00", x"00", x"00", x"00", '0', '1', 10),
      (x"00", x"40", x"00", x"00", x"10", x"00", x"F0", '0', '0', 90),
      (x"00", x"40", x"00", x"00", x"11", x"00", x"F0", '0', '0', 10900),
      (x"00", x"40", x"00", x"00", x"10", x"00", x"F0", '0', '0', 500),
      (x"00", x"40", x"00", x"00", x"21", x"00", x"F0", '0', '0', 20000),
      (x"00", x"40", x"00", x"00", x"20", x"00", x"F0", '0', '0', 500),
      (x"00", x"40", x"00", x"00", x"38", x"00", x"F0", '0', '0', 100),
      (x"00", x"40", x"00", x"00", x"31", x"00", x"F0", '0', '0', 10900),
      (x"00", x"40", x"00", x"00", x"81", x"00", x"F0", '0', '0', 1000),
      (x"00", x"40", x"00", x"00", x"89", x"00", x"F0", '0', '0', 100),
      (x"00", x"40", x"00", x"00", x"88", x"00", x"F0", '0', '0', 100),
      (x"00", x"40", x"00", x"00", x"81", x"00", x"F0", '0', '0', 1800),
      (x"00", x"40", x"00", x"00", x"81", x"00", x"F0", '0', '1', 100),
      (x"00", x"40", x"00", x"00", x"81", x"00", x"F0", '0', '0', 500),
      (x"00", x"40", x"00", x"00", x"91", x"00", x"F0", '0', '0', 500),
      (x"00", x"40", x"00", x"08", x"51", x"00", x"F0", '0', '0', 9800),
      (x"00", x"40", x"00", x"08", x"61", x"00", x"F0", '0', '0', 10000)
      );

    variable delay : integer;
    
  begin  -- process main

    for i in patterns'range loop
      Freq_lo <= patterns(i).Freq_lo;
      Freq_hi <= patterns(i).Freq_hi;
      Pw_lo <= patterns(i).Pw_lo;
      Pw_hi <= patterns(i).Pw_hi;
      Control <= patterns(i).Control;
      Att_dec <= patterns(i).Att_dec;
      Sus_Rel <= patterns(i).Sus_Rel;
      PA_MSB_in <= patterns(i).PA_MSB_in;
      reset <= patterns(i).reset;
      delay := patterns(i).delay;

      while delay > 0 loop
        clock <= '0';
        clock_1MHz <= '0';
        wait for 0.125 us;
        clock <= '1';
        wait for 0.125 us;
        clock <= '0';
        wait for 0.125 us;
        clock <= '1';
        wait for 0.125 us;
        clock <= '0';
        clock_1MHz <= '1';
        wait for 0.125 us;
        clock <= '1';
        wait for 0.125 us;
        clock <= '0';
        wait for 0.125 us;
        clock <= '1';
        wait for 0.125 us;
        delay := delay - 1;
      end loop;
      
    end loop;  -- i

    assert false report "Test completed" severity note;

    wait;
    
  end process main;
  
end architecture testbench;

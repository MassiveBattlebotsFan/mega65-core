library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sid_filters_tb is
  
end entity sid_filters_tb;

architecture testbench of sid_filters_tb is

  -- inputs
  signal clk, rst : std_logic := '0';
  signal fc_lo, fc_hi, res_filt, mode_vol : unsigned(7 downto 0) := (others => '0');
  signal voice1, voice2, voice3, ext_in : signed(12 downto 0) := (others => '0');
  signal input_valid, mode : std_logic := '0';

  -- outputs
  signal sound : signed(18 downto 0) := (others => 'Z');
  signal valid : std_logic := 'Z';

  -- filter table stuff
  signal filt_addr : integer range 0 to 2047 := 0;
  signal filt_val : unsigned(15 downto 0) := (others => 'Z');
  signal mux_addr : unsigned(11 downto 0) := (others => 'Z');
  signal mux_di : unsigned(7 downto 0) := (others => 'Z');

  -- wave gen stuff
  signal gen_wave_freq : integer := 0;
begin  -- architecture testbench

  filter : entity work.sid_filters(beh)
    port map (
      clk               => clk,
      rst               => rst,
      Fc_lo             => fc_lo,
      Fc_hi             => fc_hi,
      Res_Filt          => res_filt,
      Mode_Vol          => mode_vol,
      voice1            => voice1,
      voice2            => voice2,
      voice3            => voice3,
      ext_in            => ext_in,
      input_valid       => input_valid,
      mode              => mode,
      sound             => sound,
      valid             => valid,
      filter_table_addr => filt_addr,
      filter_table_val  => filt_val);

  filt_coeffs: entity work.sid_coeffs(beh)
    port map (
      clka  => clk,
      clkb  => '0',
      addra => mux_addr,
      addrb => (others => '0'),
      dia   => (others => '0'),
      dib   => (others => '0'),
      douta => mux_di,
      doutb => open,
      wea   => '0',
      web   => '0',
      ena   => '1',
      enb   => '0');
  
  filt_coeffs_mux : entity work.sid_coeffs_mux(mayan)
    port map (
      clk   => clk,
      addr0 => filt_addr,
      val0  => filt_val,
      addr1 => 0,
      val1  => open,
      addr2 => 0,
      val2  => open,
      addr3 => 0,
      val3  => open,
      addr4 => 0,
      val4  => open,
      addr5 => 0,
      val5  => open,
      addr6 => 0,
      val6  => open,
      addr7 => 0,
      val7  => open,
      addr  => mux_addr,
      di    => mux_di);

  main: process is
    type pattern_type is record
      fc_lo, fc_hi       : unsigned(7 downto 0);
      res_filt, mode_vol : unsigned(7 downto 0);
      gen_freq, delay    : integer;
      rst                : std_logic;
    end record pattern_type;

    type pattern_array is array (natural range <>) of pattern_type;

    constant patterns : pattern_array := (
      (x"00", x"F0", x"00", x"00", 40, 10000, '1'),
      (x"00", x"20", x"00", x"00", 40, 20000, '0'),
      (x"00", x"F0", x"00", x"00", 40, 20000, '0'),
      (x"00", x"20", x"00", x"00", 200, 40000, '0'),
      (x"00", x"F0", x"00", x"00", 200, 40000, '0')
      );
    
  begin  -- process main

    for i in patterns'range loop
      fc_lo <= patterns(i).fc_lo;
      fc_hi <= patterns(i).fc_hi;
      res_filt <= patterns(i).res_filt;
      mode_vol <= patterns(i).mode_vol;
      rst <= patterns(i).rst;
      gen_wave_freq <= patterns(i).gen_freq;
      
      for delaytime in 0 to patterns(i).delay loop
        clk <= '1';
        wait for 12.5 ns;
        clk <= '0';
        wait for 12.5 ns;        
      end loop;  -- delaytime
      
    end loop;  -- i

    assert false report "Test complete" severity note;

    wait;
    
  end process main;

  gen_input_sig: process (clk) is
    variable direction : std_logic := '0';
    variable tri_wave, saw_wave : unsigned(11 downto 0) := (others => '0');
    variable wait_states : integer := 0;
    variable pulse : std_logic := '0';
  begin  -- process gen_input_sig
    if rst = '1' then
      pulse := '0';
      wait_states := 0;
      direction := '0';
      tri_wave := (others => '0');
      saw_wave := (others => '0');
    else
      if rising_edge(clk) then
        if wait_states > 0 then
          wait_states := wait_states - 1;
          saw_wave := saw_wave + 1;
        else
          if direction = '1' then
            tri_wave := tri_wave - 16;
          else
            tri_wave := tri_wave + 16;
          end if;
          --saw_wave := saw_wave + 12;
          if tri_wave = x"FF0" then
            direction := '1';
          elsif tri_wave = x"000" then
            direction := '0';
          end if;
          wait_states := gen_wave_freq;
          pulse := not pulse;
        end if;
      end if;
    end if;
    ext_in <= signed(('0'&saw_wave) + tri_wave) when pulse = '1' else (others => '0');
  end process gen_input_sig;
  
end architecture testbench;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity multisid is
  
  port (
    cpuclock, phi0_1mhz, reset_high, w : in std_logic;
    leftsid_cs, rightsid_cs, frontsid_cs, backsid_cs, filter_cs : in std_logic;
    supersid_w1_cs, supersid_w2_cs, supersid_w3_cs, supersid_w4_cs : in std_logic;
    reg_loopback_cs : in std_logic;
    leftsid_audio, rightsid_audio, frontsid_audio, backsid_audio : out signed(17 downto 0);
    data_i : in std_logic_vector(7 downto 0);
    data_o : out std_logic_vector(7 downto 0);
    sid_mode : in unsigned(4 downto 0);
    address : in unsigned(11 downto 0);
    potl_x, potr_x, potl_y, potr_y : in unsigned(7 downto 0)
    );

end entity multisid;

architecture rtl of multisid is
  signal filter_table_addr0 : integer range 0 to 2047 := 0;
  signal filter_table_addr1 : integer range 0 to 2047 := 0;
  signal filter_table_addr2 : integer range 0 to 2047 := 0;
  signal filter_table_addr3 : integer range 0 to 2047 := 0;
  signal filter_table_val0 : unsigned(15 downto 0) := (others => '0');
  signal filter_table_val1 : unsigned(15 downto 0) := (others => '0');
  signal filter_table_val2 : unsigned(15 downto 0) := (others => '0');
  signal filter_table_val3 : unsigned(15 downto 0) := (others => '0');

  signal mux_di : unsigned(7 downto 0);
  signal mux_addr : unsigned(11 downto 0);
  signal filt_data_o : std_logic_vector(7 downto 0);
  signal data_buf : std_logic_vector(7 downto 0);
begin  -- architecture rtl

  -- msid_ram_test : entity work.multisid_ram(rtl)
  --   port map (
  --     clka  => cpuclock,
  --     ena   => filter_cs,
  --     dia   => unsigned(data_i),
  --     std_logic_vector(douta) => data_o,
  --     wea   => w,
  --     addra => address(11 downto 0),
  --     web   => '0',
  --     enb   => '0',
  --     doutb => open,
  --     dib   => (others => '0'),
  --     clkb  => '0',
  --     addrb => (others => '0'));
  coefblock: block
  begin
    coeffs: entity work.sid_coeffs(beh) port map (
      clka   => cpuclock,
      clkb   => cpuclock,
      addra  => address,
      addrb  => mux_addr,
      dia    => unsigned(data_i),
      dib    => (others => '0'),
      std_logic_vector(douta)  => filt_data_o,
      doutb  => mux_di,
      wea    => w,
      web    => '0',
      ena    => filter_cs,
      enb    => '1'
      );
  end block;
  sidcblock: block
  begin
    sidc: entity work.sid_coeffs_mux(mayan) port map (
      clk => cpuclock,
      addr0 => filter_table_addr0,
      val0 => filter_table_val0,             
      addr1 => filter_table_addr1,
      val1 => filter_table_val1,             
      addr2 => filter_table_addr2,
      val2 => filter_table_val2,             
      addr3 => filter_table_addr3,
      val3 => filter_table_val3,
      addr => mux_addr,
      di => mux_di
      );
  end block;

  block6: block
  begin
    leftsid: entity work.sid6581 port map (
      clk_1MHz => phi0_1mhz,
      cpuclock => cpuclock,
      reset => reset_high,
      cs => leftsid_cs,
      loopback => reg_loopback_cs,
      mode => sid_mode(0),
      we => w,
      addr => unsigned(address(4 downto 0)),
      di => unsigned(data_i),
      std_logic_vector(do) => data_o,
      pot_x => potl_x,
      pot_y => potl_y,
      signed_audio => leftsid_audio,
      filter_table_addr => filter_table_addr0,
      filter_table_val => filter_table_val0
      );
  end block;

  block7: block
  begin
    rightsid: entity work.sid6581 port map (
      clk_1MHz => phi0_1mhz,
      cpuclock => cpuclock,
      reset => reset_high,
      cs => rightsid_cs,
      loopback => reg_loopback_cs,
      mode => sid_mode(1),
      we => w,
      addr => unsigned(address(4 downto 0)),
      di => unsigned(data_i),
      std_logic_vector(do) => data_o,
      pot_x => potr_x,
      pot_y => potr_y,
      signed_audio => rightsid_audio,
      filter_table_addr => filter_table_addr1,
      filter_table_val => filter_table_val1
      );
  end block;

  block6b: block
  begin
    frontsid: entity work.sid6581 port map (
      clk_1MHz => phi0_1mhz,
      cpuclock => cpuclock,
      reset => reset_high,
      cs => frontsid_cs,
      loopback => reg_loopback_cs,
      mode => sid_mode(2),
      we => w,
      addr => unsigned(address(4 downto 0)),
      di => unsigned(data_i),
      std_logic_vector(do) => data_o,
      pot_x => potl_x,
      pot_y => potl_y,
      signed_audio => frontsid_audio,
      filter_table_addr => filter_table_addr2,
      filter_table_val => filter_table_val2
      );
  end block;

  block7b: block
  begin
    backsid: entity work.sid6581 port map (
      clk_1MHz => phi0_1mhz,
      cpuclock => cpuclock,
      reset => reset_high,
      cs => backsid_cs,
      loopback => reg_loopback_cs,
      mode => sid_mode(3),
      we => w,
      addr => unsigned(address(4 downto 0)),
      di => unsigned(data_i),
      std_logic_vector(do) => data_o,
      pot_x => potr_x,
      pot_y => potr_y,
      signed_audio => backsid_audio,
      filter_table_addr => filter_table_addr3,
      filter_table_val => filter_table_val3
      );
  end block;

  main: process (cpuclock, filt_data_o) is
  begin  -- process main
    if rising_edge(cpuclock) then
      if filter_cs = '1' then
        data_buf <= filt_data_o;
      else
        data_buf <= (others => 'Z');
      end if;
    end if;
  end process main;
  data_o <= data_buf;
end architecture rtl;

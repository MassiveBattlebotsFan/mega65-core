
------------------------------------------------------------------------------------------------------------------------
-- Begin RC circuit modelling
------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.float_pkg.all;
use ieee.fixed_pkg.all;
use ieee.fixed_float_types.all;
use ieee.math_real.all;

entity resistor_capacitor is
  
  generic (
    capacitor_f : real := 470.0;
    charge_res_ohm : real := 1000.0;
    discharge_res_ohm : real := 1000.0;
    bypass_res_ohm : real := 100.0;
    timestep : real := 0.000000025);  -- capacitor multiplication coefficient

  port (
    signal_in  : in  unsigned(31 downto 0);  -- input signal
    signal_in_sign : in std_logic;
    signal_out : out unsigned(31 downto 0) := (others => '0');
    signal_out_sign : out std_logic := '0';
    resistor_bypass : in  unsigned(31 downto 0) := (others => '0');
    step : in std_logic
    );  -- output signal

end entity resistor_capacitor;

architecture Experimental of resistor_capacitor is
  type analog is record
    mag  : unsigned(31 downto 0);
    sign : std_logic;
  end record analog;
  
  constant charge_coefficient_bp_r : real := 1.0 - (1.0 / 2.72 ** (timestep / (bypass_res_ohm * capacitor_f)));
  constant charge_coefficient_r : real := 1.0 - (1.0 / 2.72 ** (timestep / (charge_res_ohm * capacitor_f)));
  constant discharge_coefficient_r : real := 1.0 - (1.0 / 2.72 ** (timestep / (discharge_res_ohm * capacitor_f)));
  constant charge_coefficient_bp : unsigned(31 downto 0) := to_unsigned(natural(charge_coefficient_bp_r * 4294967296.0), 32);
  constant charge_coefficient : unsigned(31 downto 0) := to_unsigned(natural(charge_coefficient_r * 4294967296.0), 32);
  constant charge_coefficient_diff : unsigned(31 downto 0) := charge_coefficient_bp - charge_coefficient;
  constant discharge_coefficient : unsigned(31 downto 0) := to_unsigned(natural(discharge_coefficient_r * 4294967296.0), 32);
  constant discharge_coefficient_diff : unsigned(31 downto 0) := charge_coefficient_bp - discharge_coefficient;

  subtype return_type is unsigned (31 downto 0);
  -- purpose: Multiply input signal by coefficient and return
  function mult_by_coeff (
    input, coeff : unsigned(31 downto 0))
    return return_type is
    variable multiplication_result : unsigned(63 downto 0) := (others => '0');
  begin  -- function mult_by_coeff
    multiplication_result := input * coeff;
    return multiplication_result(63 downto 32);
  end function mult_by_coeff;
  
  -- purpose: accumulate change in capacitor
  function cap_acc (
    current, target : analog)
    return analog is

    variable diff_ct, diff_tc : unsigned(31 downto 0);
    variable diff_scaled : unsigned(63 downto 0);  -- 32 bit * 32 bit is 64 bit max
  begin  -- function cap_acc
    if current.sign /= target.sign then
      diff_scaled := (current.mag + target.mag) * (mult_by_coeff(discharge_coefficient_diff, resistor_bypass) + discharge_coefficient);
      if diff_scaled(63 downto 32) > current.mag then
        return (diff_scaled(63 downto 32) - current.mag, not current.sign);
      else
        return (current.mag - diff_scaled(63 downto 32), current.sign);  
      end if;
    else
      diff_ct := current.mag - target.mag;
      diff_tc := target.mag - current.mag;
      if target.mag < current.mag then
        diff_scaled := diff_ct * (mult_by_coeff(discharge_coefficient_diff, resistor_bypass) + discharge_coefficient);
        return (current.mag - diff_scaled(63 downto 32), current.sign);
      else
        diff_scaled := diff_tc * (mult_by_coeff(charge_coefficient_diff, resistor_bypass) + charge_coefficient);
        return (current.mag + diff_scaled(63 downto 32), current.sign);
      end if;
    end if;    
  end function cap_acc;
  
begin  -- architecture Experimental

  main: process (signal_in, step) is
    variable cap1_in : analog  := (x"00000000", '0');
    variable cap1_out : analog := (x"00000000", '0');
  begin  -- process main

    if rising_edge(step) then
      cap1_in.mag := signal_in;
      cap1_in.sign := signal_in_sign;
      cap1_out := cap_acc(cap1_out, cap1_in);
      signal_out <= cap1_out.mag;
      signal_out_sign <= cap1_out.sign;
    end if;
    
  end process main;
  
end architecture Experimental;

------------------------------------------------------------------------------------------------------------------------
-- Begin operational amplifier
------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity op_amp is
  
  port (
    pos : in  unsigned(31 downto 0);
    pos_sign : in std_logic;
    neg : in  unsigned(31 downto 0);
    neg_sign : in std_logic;
    output   : out  unsigned(31 downto 0) := (others => '0');
    output_sign : out std_logic := '0';
    step     : in  std_logic);

end entity op_amp;

architecture Experimental of op_amp is

  subtype add_type is unsigned (31 downto 0);
  function safe_add (
    a, b : unsigned(31 downto 0))
    return add_type is
    variable temp : unsigned(32 downto 0) := (others => '0');
  begin  -- function safe_add
    temp := ('0' & a) + b;
    if temp(32) = '1' then
      return x"FFFFFFFF";
    else
      return temp(31 downto 0);
    end if;
  end function safe_add;
  
  function safe_sub (
    a, b : unsigned(31 downto 0))
    return add_type is
  begin  -- function safe_sub
    if b > a then
      return b - a;
    else
      return a - b;
    end if;
  end function safe_sub;
  
begin  -- architecture Experimental

  main: process (step) is
    variable combined_signs : std_logic_vector(1 downto 0) := "00";
    variable greater_sign : std_logic := '0';
  begin  -- process main
    if rising_edge(step) then
      combined_signs := pos_sign & neg_sign;
      if pos > neg then
        greater_sign := '0';
      else
        greater_sign := '1';
      end if;
      case combined_signs is
        when "00" => output <= safe_sub(pos, neg);
                     output_sign <= greater_sign;
        when "01" => output <= safe_add(pos, neg);
                     output_sign <= '0';
        when "10" => output <= safe_add(pos, neg);
                     output_sign <= '1';
        when "11" => output <= safe_sub(neg, pos);
                     output_sign <= not greater_sign;
        when others => null;
      end case;
    end if;
  end process main;
  
end architecture Experimental;

------------------------------------------------------------------------------------------------------------------------
-- Begin filter
------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sid_filters is
  port (
    clk         : in  std_logic; -- At least 12Mhz
    rst         : in  std_logic;
    -- SID registers.
    Fc_lo       : in  unsigned(7 downto 0);
    Fc_hi       : in  unsigned(7 downto 0);
    Res_Filt    : in  unsigned(7 downto 0);
    Mode_Vol    : in  unsigned(7 downto 0);
    -- Voices - resampled to 13 bit
    voice1      : in  signed(12 downto 0);
    voice2      : in  signed(12 downto 0);
    voice3      : in  signed(12 downto 0);
    --
    input_valid : in  std_logic;
    ext_in      : in  signed(12 downto 0);
    --
    mode        : in std_logic;
    --
    sound       : out signed(18 downto 0);
    valid       : out std_logic;

    filter_table_addr : out integer range 0 to 2047 := 0;
    filter_table_val : in unsigned(15 downto 0)
    
    );
end entity;

architecture beh of sid_filters is

  alias filt        : unsigned(3 downto 0) is Res_Filt(3 downto 0);
  alias res         : unsigned(3 downto 0) is Res_Filt(7 downto 4);
  alias volume      : unsigned(3 downto 0) is Mode_Vol(3 downto 0);
  alias hp_bp_lp    : unsigned(2 downto 0) is Mode_Vol(6 downto 4);
  alias voice3off   : std_logic is Mode_Vol(7);

  constant mixer_DC : integer := -475; -- NOTE to self: this might be wrong.

  type analog is record
    mag  : unsigned(31 downto 0);
    sign : std_logic;
  end record analog;
  
  ----------------------------------------------------------------------------------------
  type divmul_t is array(0 to 15) of integer;

  constant divmul_6581: divmul_t := (
    1448, 1323, 1218, 1128, 1051, 984, 925, 872, 825, 783, 745, 710, 679, 650, 624, 599
    );

  constant divmul_8580: divmul_t := (
    1448, 1328, 1228, 1117, 1024, 939, 861, 790, 724, 664, 609, 558, 512, 470, 431, 395
    );

  
  ----------------------------------------------------------------------------------------

  subtype return_type is unsigned(31 downto 0);
  
  -- purpose: Multiply input signal by coefficient and return
  function mult_by_coeff (
    input : unsigned(31 downto 0);
    coeff : unsigned(35 downto 0))
    return return_type is
    variable multiplication_result : unsigned(67 downto 0) := (others => '0');
  begin  -- function mult_by_coeff
    multiplication_result := input * coeff;
    return multiplication_result(63 downto 32);
  end function mult_by_coeff;

  -- purpose: Adds two analog signals and saturates on overflow.
  function add_with_saturation (
    a, b : analog)
    return analog is
    variable compute : unsigned(32 downto 0) := (others => '0');
    variable result : analog;
  begin  -- function add_with_saturation
    if a.sign = b.sign then
      compute := ('0' & a.mag) + b.mag;
      if compute(32) = '1' then
        result.mag := x"FFFFFFFF";
      else
        result.mag := compute(31 downto 0);
      end if;
      result.sign := a.sign;
    else
      if a.mag > b.mag then
        compute := ('0' & a.mag) - b.mag;
        result.mag := compute(31 downto 0);
        result.sign := a.sign;
      else
        compute := ('0' & b.mag) - a.mag;
        result.mag := compute(31 downto 0);
        result.sign := b.sign;
      end if;
    end if;
    return result;
  end function add_with_saturation;

  subtype visualization is unsigned(32 downto 0);
  function visualize_analog (
    input : analog)
    return visualization is
  begin  -- function visualize_analog

    if input.sign = '1' then
      return o"40000000000" - input.mag;
    else
      return o"40000000000" + input.mag;
    end if;
    
  end function visualize_analog;
  
  ----------------------------------------------------------------------------------------

  signal fc : unsigned (10 downto 0);

  signal hp_vin, bp_vin, lp_vin : analog := (x"00000000", '0');
  signal hp_vout, bp_vout, lp_vout : analog := (x"00000000", '0');
  signal bp_res_bypass, lp_res_bypass : unsigned(31 downto 0) := (others => '0');
  -- signal bp_inverted : analog := (x"00000000", '0');
  signal hp_opamp_pos, hp_opamp_neg, hp_opamp_out : analog := (x"00000000", '0');
  signal bp_opamp_pos, bp_opamp_neg, bp_opamp_out : analog := (x"00000000", '0');
  signal lp_opamp_pos, lp_opamp_neg, lp_opamp_out : analog := (x"00000000", '0');
  signal bp_rc_in, bp_rc_out, lp_rc_in, lp_rc_out : analog := (x"00000000", '0');
  signal mixed_selected_inputs : unsigned(31 downto 0) := x"00000000";
  signal mixed_bypass_inputs : unsigned(31 downto 0) := x"00000000";

  signal lp_vis, bp_vis, hp_vis, nr_vis : visualization := (others => '0');
  
  constant input_gain : unsigned(35 downto 0) := x"03E66E5E3"; --x"F99B978E";
  constant bp_gain : unsigned(35 downto 0) := x"115DF2884";
  constant lp_gain : unsigned(35 downto 0) := X"0FF970D60";
  
begin
  fc <= Fc_hi & Fc_lo(2 downto 0);

--	c: entity work.sid_coeffs

  filter_table_addr <= to_integer(unsigned(fc));

  bp_res_cap : entity work.resistor_capacitor(Experimental)
    generic map (
      capacitor_f       => 0.0000000022,  -- 0.00000000047
      charge_res_ohm    => 1035010.0,
      discharge_res_ohm => 1035010.0,
      bypass_res_ohm    => 1128.0,
      timestep          => 0.000000025)
    port map (
      signal_in  => bp_rc_in.mag,
      signal_in_sign => bp_rc_in.sign,
      signal_out => bp_rc_out.mag,
      signal_out_sign => bp_rc_out.sign,
      resistor_bypass => bp_res_bypass,
      step       => clk);

  lp_res_cap : entity work.resistor_capacitor(Experimental)
    generic map (
      capacitor_f       => 0.0000000022,
      charge_res_ohm    => 1011520.0,
      discharge_res_ohm => 1011520.0,
      bypass_res_ohm    => 1128.0,
      timestep          => 0.000000025)
    port map (
      signal_in  => lp_rc_in.mag,
      signal_in_sign => lp_rc_in.sign,
      signal_out => lp_rc_out.mag,
      signal_out_sign => lp_rc_out.sign,
      resistor_bypass => lp_res_bypass,
      step       => clk);

  hp_opamp : entity work.op_amp(Experimental) port map (
    pos    => hp_opamp_pos.mag,
    pos_sign => hp_opamp_pos.sign,
    neg    => hp_opamp_neg.mag,
    neg_sign => hp_opamp_neg.sign,
    output => hp_opamp_out.mag,
    output_sign => hp_opamp_out.sign,
    step   => clk);

  bp_opamp : entity work.op_amp(Experimental) port map (
    pos    => bp_opamp_pos.mag,
    pos_sign => bp_opamp_pos.sign,
    neg    => bp_opamp_neg.mag,
    neg_sign => bp_opamp_neg.sign,
    output => bp_opamp_out.mag,
    output_sign => bp_opamp_out.sign,
    step   => clk);

  lp_opamp : entity work.op_amp(Experimental) port map (
    pos    => lp_opamp_pos.mag,
    pos_sign => lp_opamp_pos.sign,
    neg    => lp_opamp_neg.mag,
    neg_sign => lp_opamp_neg.sign,
    output => lp_opamp_out.mag,
    output_sign => lp_opamp_out.sign,
    step   => clk);

  -- These opamps don't need the positive input
  hp_opamp_pos <= (x"00000000", '0');
  bp_opamp_pos <= (x"00000000", '0');
  lp_opamp_pos <= (x"00000000", '0');
  
  process(clk, rst, filter_table_val, input_valid, filt, voice1, voice2, voice3, voice3off, ext_in, hp_bp_lp, Mode_Vol,mode)
  begin
    if rising_edge(clk) then
      mixed_selected_inputs(31 downto 19) <= unsigned(ext_in);
      mixed_selected_inputs(18 downto 0) <= (others => '0');
      -- Pass in the input, resonance (NYI), LP loopback, and the output itself
      hp_vin <= add_with_saturation(add_with_saturation((mult_by_coeff(mixed_selected_inputs, input_gain), '0'),
                                                        (mult_by_coeff(bp_vout.mag, bp_gain), not bp_vout.sign)),
                                    (mult_by_coeff(lp_vout.mag, lp_gain), lp_vout.sign));
      hp_opamp_neg <= hp_vin;
      hp_vout <= hp_opamp_out;
      hp_vis <= visualize_analog(hp_opamp_out);
      
      bp_vin <= hp_vout;
      bp_res_bypass <= filter_table_val & x"0000";
      bp_rc_in <= bp_vin;
      bp_opamp_neg <= bp_rc_out;
      bp_vout <= bp_opamp_out;
      bp_vis <= visualize_analog(bp_opamp_out);
      
      lp_vin <= bp_vout;
      lp_res_bypass <= filter_table_val & x"0000";
      lp_rc_in <= lp_vin;
      lp_opamp_neg <= lp_rc_out;
      lp_vout <= lp_opamp_out;
      lp_vis <= visualize_analog(lp_opamp_out);

      nr_vis <= visualize_analog(add_with_saturation(hp_opamp_out, lp_opamp_out));
    end if;
  end process;

  -- sound <= r.vout;
  -- valid <= r.done;

end beh;

-- The block RAMs of rtl/bram.vhd and rtl/mlab.vhd as plain VHDL, for GHDL's
-- translation of the VDP and the SVP to Verilog (tools/sim.sh). The entities
-- and ports are bram.vhd's; Altera's altsyncram and altdpram are behaved as
-- the core sets them: the address registered, the output not, so a read
-- gives the word a clock later; reading where the same port writes gives the
-- new data. mlab's read is not registered at all (altdpram, rdaddress and
-- outdata UNREGISTERED). dpram_dif here is same-width only: the VDP and the
-- SVP use no other (system.sv's mixed-width SRAM is sim/genesis/bram.sv's).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram_dif is
	generic (
		addr_width_a  : integer := 8;
		data_width_a  : integer := 8;
		addr_width_b  : integer := 8;
		data_width_b  : integer := 8;
		mem_init_file : string := " "
	);
	port (
		clock     : in  std_logic;
		address_a : in  std_logic_vector(addr_width_a-1 downto 0);
		data_a    : in  std_logic_vector(data_width_a-1 downto 0) := (others => '0');
		enable_a  : in  std_logic := '1';
		wren_a    : in  std_logic := '0';
		q_a       : out std_logic_vector(data_width_a-1 downto 0);
		cs_a      : in  std_logic := '1';
		address_b : in  std_logic_vector(addr_width_b-1 downto 0) := (others => '0');
		data_b    : in  std_logic_vector(data_width_b-1 downto 0) := (others => '0');
		enable_b  : in  std_logic := '1';
		wren_b    : in  std_logic := '0';
		q_b       : out std_logic_vector(data_width_b-1 downto 0);
		cs_b      : in  std_logic := '1'
	);
end entity;

architecture sim of dpram_dif is
	type mem_t is array(0 to 2**addr_width_a-1) of std_logic_vector(data_width_a-1 downto 0);
	signal mem : mem_t := (others => (others => '0'));
	signal q0 : std_logic_vector(data_width_a-1 downto 0) := (others => '0');
	signal q1 : std_logic_vector(data_width_b-1 downto 0) := (others => '0');
begin
	assert addr_width_a = addr_width_b and data_width_a = data_width_b
		report "dpram_dif: mixed widths are not modelled here" severity failure;

	q_a <= q0 when cs_a = '1' else (others => '1');
	q_b <= q1 when cs_b = '1' else (others => '1');

	process(clock) begin
		if rising_edge(clock) then
			if enable_a = '1' then
				if wren_a = '1' and cs_a = '1' then
					mem(to_integer(unsigned(address_a))) <= data_a;
					q0 <= data_a;
				else
					q0 <= mem(to_integer(unsigned(address_a)));
				end if;
			end if;
			if enable_b = '1' then
				if wren_b = '1' and cs_b = '1' then
					mem(to_integer(unsigned(address_b))) <= data_b;
					q1 <= data_b;
				else
					q1 <= mem(to_integer(unsigned(address_b)));
				end if;
			end if;
		end if;
	end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;

entity DualPortRAM is
	generic (
		addrbits : integer := 8;
		databits : integer := 8
	);
	port (
		clock     : in  std_logic;
		address_a : in  std_logic_vector(addrbits-1 downto 0);
		data_a    : in  std_logic_vector(databits-1 downto 0) := (others => '0');
		wren_a    : in  std_logic := '0';
		q_a       : out std_logic_vector(databits-1 downto 0);
		address_b : in  std_logic_vector(addrbits-1 downto 0) := (others => '0');
		data_b    : in  std_logic_vector(databits-1 downto 0) := (others => '0');
		wren_b    : in  std_logic := '0';
		q_b       : out std_logic_vector(databits-1 downto 0)
	);
end entity;

architecture sim of DualPortRAM is
begin
	ram : entity work.dpram_dif generic map(addrbits, databits, addrbits, databits)
	port map(clock, address_a, data_a, '1', wren_a, q_a, '1', address_b, data_b, '1', wren_b, q_b, '1');
end architecture;

library ieee;
use ieee.std_logic_1164.all;

entity obj_cache is
	port (
		byteena_a : in  std_logic_vector(3 downto 0) := (others => '1');
		clock     : in  std_logic := '1';
		data      : in  std_logic_vector(31 downto 0);
		rdaddress : in  std_logic_vector(6 downto 0);
		wraddress : in  std_logic_vector(6 downto 0);
		wren      : in  std_logic := '0';
		q         : out std_logic_vector(31 downto 0)
	);
end entity;

architecture sim of obj_cache is
begin
	bytes : for i in 0 to 3 generate
		ram : entity work.dpram_dif generic map(7, 8, 7, 8)
		port map(clock, rdaddress, (others => '0'), '1', '0', q(i*8+7 downto i*8), '1',
		         wraddress, data(i*8+7 downto i*8), '1', wren and byteena_a(i));
	end generate;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spram is
	generic (
		addr_width    : integer := 8;
		data_width    : integer := 8;
		mem_init_file : string := " ";
		mem_name      : string := "MEM"
	);
	port (
		clock   : in  std_logic;
		address : in  std_logic_vector(addr_width-1 downto 0);
		data    : in  std_logic_vector(data_width-1 downto 0) := (others => '0');
		enable  : in  std_logic := '1';
		wren    : in  std_logic := '0';
		q       : out std_logic_vector(data_width-1 downto 0);
		cs      : in  std_logic := '1'
	);
end entity;

-- spram_sz's altsyncram has its clock enable bypassed, so enable does nothing
architecture sim of spram is
	type mem_t is array(0 to 2**addr_width-1) of std_logic_vector(data_width-1 downto 0);
	signal mem : mem_t := (others => (others => '0'));
	signal q0 : std_logic_vector(data_width-1 downto 0) := (others => '0');
begin
	q <= q0 when cs = '1' else (others => '1');
	process(clock) begin
		if rising_edge(clock) then
			if wren = '1' and cs = '1' then
				mem(to_integer(unsigned(address))) <= data;
				q0 <= data;
			else
				q0 <= mem(to_integer(unsigned(address)));
			end if;
		end if;
	end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mlab is
	generic (
		addr_width : integer := 8;
		data_width : integer := 8
	);
	port (
		clock     : in  std_logic;
		rdaddress : in  std_logic_vector(addr_width-1 downto 0);
		wraddress : in  std_logic_vector(addr_width-1 downto 0);
		data      : in  std_logic_vector(data_width-1 downto 0) := (others => '0');
		wren      : in  std_logic := '0';
		q         : out std_logic_vector(data_width-1 downto 0);
		cs        : in  std_logic := '1'
	);
end entity;

architecture sim of mlab is
	type mem_t is array(0 to 2**addr_width-1) of std_logic_vector(data_width-1 downto 0);
	signal mem : mem_t := (others => (others => '0'));
begin
	q <= mem(to_integer(unsigned(rdaddress))) when cs = '1' else (others => '1');
	process(clock) begin
		if rising_edge(clock) then
			if wren = '1' then
				mem(to_integer(unsigned(wraddress))) <= data;
			end if;
		end if;
	end process;
end architecture;

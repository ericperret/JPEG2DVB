--------------------------------------------------------------------------------
-- tb_dvbc_sd : banc de bout en bout du mode DVB-C : dvbs_sd (dvbt = 1, dvbc = 1, deux
--   programmes, caméra absente) → octets sigma-delta m_i, m_q enregistrés (bits.txt) ;
--   les octets entrant dans dvbc_map sont enregistrés (octets.txt) ; la référence
--   fpga_test/dvbc_verif.js recalcule le flux de bits depuis ces octets
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_dvbc_sd is
    generic (
        G_DIR : string := "/tmp/gh/sdc";
        G_NG  : natural := 40000
    );
end entity tb_dvbc_sd;

architecture sim of tb_dvbc_sd is
    signal clk, rst : std_logic := '0';
    signal m_valid : std_logic;
    signal m_i, m_q : std_logic_vector(7 downto 0);
    signal fini : boolean := false;
begin
    clk <= not clk after 6.25 ns when not fini;
    u : entity work.dvbs_sd
        generic map (G_MCPC => true, G_RS => 5_000_000)
        port map (clk => clk, rst => rst, norme => '0', dvbt => '1', dvbc => '1', m_valid => m_valid, m_ready => '1', m_i => m_i, m_q => m_q);
    process
    begin
        rst <= '1'; wait for 200 ns; wait until rising_edge(clk); rst <= '0'; wait;
    end process;

    -- octets entrant dans dvbc_map
    process
        alias b_valid is <<signal .tb_dvbc_sd.u.u_t.b_valid : std_logic>>;
        alias b_ready is <<signal .tb_dvbc_sd.u.u_t.b_ready : std_logic>>;
        alias b_data  is <<signal .tb_dvbc_sd.u.u_t.b_data : std_logic_vector(7 downto 0)>>;
        file f : text;
        variable l : line;
    begin
        file_open(f, G_DIR & "/octets.txt", write_mode);
        loop
            wait until rising_edge(clk);
            if b_valid = '1' and b_ready = '1' then
                l := null; write(l, to_integer(unsigned(b_data))); writeline(f, l);
            end if;
            exit when fini;
        end loop;
        file_close(f);
        wait;
    end process;

    -- octets de sortie
    process
        file f : text;
        variable l : line;
        variable n : natural := 0;
    begin
        file_open(f, G_DIR & "/bits.txt", write_mode);
        wait until rst = '0';
        while n < G_NG loop
            wait until rising_edge(clk);
            if m_valid = '1' then
                l := null; write(l, to_integer(unsigned(m_i))); write(l, ' '); write(l, to_integer(unsigned(m_q))); writeline(f, l);
                n := n + 1;
            end if;
        end loop;
        file_close(f);
        report "tb_dvbc_sd : " & integer'image(n) & " octets enregistres";
        fini <= true;
        wait;
    end process;
end architecture sim;

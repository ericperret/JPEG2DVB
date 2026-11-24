--------------------------------------------------------------------------------
-- tb_gmsk_sd : banc de bout en bout du mode GMSK : dvbs_sd (dvbt = 1, gmsk = 1, deux
--   programmes instanciés, caméra absente) → octets sigma-delta m_i, m_q enregistrés
--   (bits.txt) ; les mots (X, Y) entrant dans gmsk_mod (mots.txt) et les octets du
--   flux TS avant l'embrouillage (ts.txt : cycle, début de paquet, octet) sont
--   enregistrés ; la référence fpga_test/gmsk_verif.js recalcule le flux de bits
--   depuis les mots et contrôle le flux TS (programme unique, cadence)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_gmsk_sd is
    generic (
        G_DIR : string := "/tmp/gh/sdg";
        G_NG  : natural := 700000;
        G_INV : natural := 0
    );
end entity tb_gmsk_sd;

architecture sim of tb_gmsk_sd is
    signal clk, rst : std_logic := '0';
    signal m_valid : std_logic;
    signal m_i, m_q : std_logic_vector(7 downto 0);
    signal fini : boolean := false;
    signal cyc : natural := 0;
    signal inv : std_logic;
begin
    inv <= '1' when G_INV = 1 else '0';
    clk <= not clk after 6.25 ns when not fini;
    u : entity work.dvbs_sd
        generic map (G_MCPC => true, G_RS => 5_000_000)
        port map (clk => clk, rst => rst, norme => '0', dvbt => '1', gmsk => '1', inv => inv, m_valid => m_valid, m_ready => '1', m_i => m_i, m_q => m_q);
    process
    begin
        rst <= '1'; wait for 200 ns; wait until rising_edge(clk); rst <= '0'; wait;
    end process;
    process (clk)
    begin
        if rising_edge(clk) then cyc <= cyc + 1; end if;
    end process;

    -- mots entrant dans gmsk_mod
    process
        alias gm_valid is <<signal .tb_gmsk_sd.u.gm_valid : std_logic>>;
        alias gm_ready is <<signal .tb_gmsk_sd.u.gm_ready : std_logic>>;
        alias c_data   is <<signal .tb_gmsk_sd.u.c_data : std_logic_vector(1 downto 0)>>;
        file f : text;
        variable l : line;
    begin
        file_open(f, G_DIR & "/mots.txt", write_mode);
        loop
            wait until rising_edge(clk);
            if gm_valid = '1' and gm_ready = '1' then
                l := null; write(l, to_integer(unsigned(c_data))); writeline(f, l);
            end if;
            exit when fini;
        end loop;
        file_close(f);
        wait;
    end process;

    -- flux TS (avant embrouillage BISS et dispersion)
    process
        alias t_valid is <<signal .tb_gmsk_sd.u.t_valid : std_logic>>;
        alias t_ready is <<signal .tb_gmsk_sd.u.t_ready : std_logic>>;
        alias t_data  is <<signal .tb_gmsk_sd.u.t_data : std_logic_vector(7 downto 0)>>;
        alias t_sop   is <<signal .tb_gmsk_sd.u.t_sop : std_logic>>;
        file f : text;
        variable l : line;
    begin
        file_open(f, G_DIR & "/ts.txt", write_mode);
        loop
            wait until rising_edge(clk);
            if t_valid = '1' and t_ready = '1' then
                l := null; write(l, cyc); write(l, ' '); write(l, std_logic'image(t_sop)(2)); write(l, ' '); write(l, to_integer(unsigned(t_data))); writeline(f, l);
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
        report "tb_gmsk_sd : " & integer'image(n) & " octets enregistres";
        fini <= true;
        wait;
    end process;
end architecture sim;

--------------------------------------------------------------------------------
-- tb_dvbt : banc de dvbt_mod : mots (X, Y) aléatoires (mots.txt) → groupes ; compare
--   v = In3 de chaque groupe, voie I et Q, au filtre de dvbt_ref.js (ref_v.txt) et
--   contrôle les autres apports (In4 … U3 = v · constantes)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.dvbs_pkg.all;

entity tb_dvbt is
    generic (
        G_DIR : string := "/tmp/gh/vec3";
        G_N   : natural := 3 * 1512;
        G_NG  : natural := 3 * 24640
    );
end entity tb_dvbt;

architecture sim of tb_dvbt is
    signal clk, rst : std_logic := '0';
    signal s_valid, s_ready : std_logic := '0';
    signal s_w : std_logic_vector(1 downto 0) := "00";
    signal t_valid : std_logic;
    signal t_gi, t_gq : sd_grp_t;
    signal fini : boolean := false;
begin
    clk <= not clk after 6.25 ns when not fini;
    u : entity work.dvbt_mod port map (clk => clk, rst => rst, inv => '0', s_valid => s_valid, s_ready => s_ready, s_w => s_w,
                                       t_valid => t_valid, t_ready => '1', t_gi => t_gi, t_gq => t_gq);
    process
    begin
        rst <= '1'; wait for 100 ns; wait until rising_edge(clk); rst <= '0'; wait;
    end process;

    -- source
    process
        file f : text;
        variable l : line;
        variable v : integer;
        variable n : natural := 0;
    begin
        file_open(f, G_DIR & "/mots.txt", read_mode);
        wait until rst = '0';
        while n < G_N loop
            readline(f, l); read(l, v);
            s_w <= std_logic_vector(to_unsigned(v, 2)); s_valid <= '1';
            loop
                wait until rising_edge(clk);
                exit when s_ready = '1';
            end loop;
            n := n + 1;
        end loop;
        s_valid <= '0';
        wait;
    end process;

    -- contrôle
    process
        file f : text;
        variable l : line;
        variable a, b : integer;
        variable n, err, errk : natural := 0;
        variable v : integer;
    begin
        file_open(f, G_DIR & "/ref_v.txt", read_mode);
        wait until rst = '0';
        while n < G_NG loop
            wait until rising_edge(clk);
            if t_valid = '1' then
                readline(f, l); read(l, a); read(l, b);
                if to_integer(t_gi(0)) /= a or to_integer(t_gq(0)) /= b then
                    if err < 5 then
                        report "ecart groupe " & integer'image(n) & " : I " & integer'image(to_integer(t_gi(0))) & " (ref " & integer'image(a) & ") Q " &
                               integer'image(to_integer(t_gq(0))) & " (ref " & integer'image(b) & ")" severity warning;
                    end if;
                    err := err + 1;
                end if;
                v := a;
                if to_integer(t_gi(4)) /= 35 * a or to_integer(t_gi(7)) /= 56 * a or to_integer(t_gi(6)) /= 28 * a or to_integer(t_gi(5)) /= 8 * a
                   or to_integer(t_gi(2)) /= 10 * a or to_integer(t_gi(3)) /= 20 * a or to_integer(t_gi(1)) /= 4 * a then
                    errk := errk + 1;
                end if;
                n := n + 1;
            end if;
        end loop;
        report "dvbt_mod : " & integer'image(n) & " groupes, " & integer'image(err) & " ecarts, " & integer'image(errk) & " apports faux";
        assert err = 0 and errk = 0 report "dvbt_mod : ECHEC" severity failure;
        report "dvbt_mod : OK";
        fini <= true;
        wait;
    end process;
end architecture sim;

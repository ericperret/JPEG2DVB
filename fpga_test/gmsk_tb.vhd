--==============================================================================
--  Nom        : gmsk_tb.vhd
--  Projet     : JPEG2DVB, portage FPGA (mode GMSK)
--  Objet      : banc de gmsk_mod : mots (X, Y) lus dans in.txt, entrée et sortie avec
--               attentes aléatoires ; v (premier apport de chaque groupe) comparé
--               à exp.txt (gmsk_ref.js vect) ; arrêt sans sortie pendant 2 000 cycles
--  Auteur     : Eric PERRET
--  Date       : 2026-11-24
--  Version    : 1.0
--  Licence    : CC BY-NC 4.0
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.dvbs_pkg.all;

entity tb_gmsk is
    generic (
        G_REP : string := "/tmp/gh/gmsk";
        G_N   : natural := 3000;
        G_INV : natural := 0
    );
end entity tb_gmsk;

architecture sim of tb_gmsk is
    signal clk, rst : std_logic := '0';
    signal s_valid, s_ready, t_valid, t_ready : std_logic := '0';
    signal s_w : std_logic_vector(1 downto 0) := "00";
    signal gi, gq : sd_grp_t;
    signal inv : std_logic;
    signal fin : boolean := false;
    -- alea : E : registre à décalage (variable de l'appelant) → S : 3 bits pseudo-aléatoires
    procedure alea(variable r : inout unsigned(15 downto 0); variable v : out natural) is
    begin
        r := r(14 downto 0) & (r(15) xor r(13) xor r(12) xor r(10));
        v := to_integer(r(2 downto 0));
    end procedure;
begin
    inv <= '1' when G_INV = 1 else '0';
    clk <= not clk after 6.25 ns when not fin;
    u : entity work.gmsk_mod port map (clk, rst, inv, s_valid, s_ready, s_w, t_valid, t_ready, gi, gq);

    -- entrée : un mot, avec attentes aléatoires (l'inversion suit G_REP : deuxième banc par generic)
    process
        file f : text;
        variable l : line;
        variable w : integer;
        variable r : unsigned(15 downto 0) := x"ACE1";
        variable a : natural;
    begin
        rst <= '1';
        wait for 100 ns; wait until rising_edge(clk); rst <= '0';
        file_open(f, G_REP & "/in.txt", read_mode);
        while not endfile(f) loop
            readline(f, l); read(l, w);
            s_w <= std_logic_vector(to_unsigned(w, 2));
            -- attente aléatoire de 0 à 20 cycles
            alea(r, a);
            for k in 1 to (a * 3) loop wait until rising_edge(clk); end loop;
            s_valid <= '1';
            loop
                wait until rising_edge(clk);
                exit when s_ready = '1';
            end loop;
            s_valid <= '0';
        end loop;
        file_close(f);
        wait;
    end process;

    -- sortie : t_ready aléatoire, comparaison
    process
        file f : text;
        variable l : line;
        variable ei, eq : integer;
        variable n, bad, vide : natural := 0;
        variable r : unsigned(15 downto 0) := x"BEEF";
        variable a : natural;
    begin
        file_open(f, G_REP & "/exp.txt", read_mode);
        wait until rst = '0';
        while n < G_N loop
            wait until rising_edge(clk);
            t_ready <= '0';
            alea(r, a);
            if a /= 0 then t_ready <= '1'; end if;
            if t_valid = '1' and t_ready = '1' then
                vide := 0;
                readline(f, l); read(l, ei); read(l, eq);
                if to_integer(gi(0)) /= ei or to_integer(gq(0)) /= eq then
                    bad := bad + 1;
                    if bad < 6 then report "ecart a l'echantillon " & integer'image(n) & " : " & integer'image(to_integer(gi(0))) & " " & integer'image(to_integer(gq(0))) & " attendu " & integer'image(ei) & " " & integer'image(eq); end if;
                end if;
                n := n + 1;
            else
                vide := vide + 1;
                if vide > 2000 then exit; end if;
            end if;
        end loop;
        if bad = 0 and n = G_N then
            report "OK  gmsk_mod : " & integer'image(n) & " echantillons identiques a la reference";
        else
            report "ECHEC gmsk_mod : " & integer'image(bad) & " ecarts sur " & integer'image(n) & " echantillons";
        end if;
        fin <= true;
        wait;
    end process;
end architecture sim;

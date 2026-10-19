--==============================================================================
--  Nom        : tb_es.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test de l'assemblage du flux élémentaire : bits VLC
--               des macroblocs de l'étape 05 (toutes les images) en entrée,
--               découpés en mots de 1 à 24 bits ; sortie comparée octet par
--               octet au flux élémentaire de l'étape 06 (fin de séquence comprise)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_pkg.all;

entity tb_es is
    generic (
        G_IMAGES : natural := 3;
        G_N_OUT  : natural := 79147;         -- taille de es.bin
        G_CODE   : natural := 8
    );
end entity tb_es;

architecture sim of tb_es is
    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
    signal s_valid  : std_logic := '0';
    signal s_ready  : std_logic;
    signal s_code   : std_logic_vector(31 downto 0) := (others => '0');
    signal s_lg     : unsigned(5 downto 0) := (others => '0');
    signal s_fin_mb : std_logic := '0';
    signal m_valid  : std_logic;
    signal m_ready  : std_logic := '1';
    signal m_data   : std_logic_vector(7 downto 0);
    signal code     : unsigned(4 downto 0) := to_unsigned(G_CODE, 5);
begin
    clk <= not clk after 5 ns;
    dut : entity work.es_mux generic map (G_IMAGES => G_IMAGES)
        port map (clk, rst, code, s_valid, s_ready, s_code, s_lg, s_fin_mb, m_valid, m_ready, m_data);

    -- source : bits de chaque macrobloc, découpés en mots de longueur pseudo-aléatoire
    source : process
        file fb         : octets_f open read_mode is REF & "vlc.bin";
        file fl         : octets_f open read_mode is REF & "mbbits.bin";
        variable a, b   : character;
        variable octet_c : std_logic_vector(7 downto 0);
        variable nb_oct : natural := 0;              -- bits restant dans octet_c
        variable reste, lg : natural;
        variable mot    : std_logic_vector(31 downto 0);
        variable r      : std_logic_vector(15 downto 0) := x"ACE1";
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for m in 0 to G_IMAGES * 396 - 1 loop
            read(fl, a); read(fl, b);
            reste := character'pos(b) * 256 + character'pos(a);
            while reste > 0 loop
                r  := alea(r);
                lg := 1 + to_integer(unsigned(r(4 downto 0))) mod 24;
                if lg > reste then lg := reste; end if;
                mot := (others => '0');
                for k in 1 to lg loop
                    if nb_oct = 0 then
                        read(fb, a);
                        octet_c := octet(a);
                        nb_oct := 8;
                    end if;
                    mot := mot(30 downto 0) & octet_c(nb_oct - 1);
                    nb_oct := nb_oct - 1;
                end loop;
                reste := reste - lg;
                s_code   <= mot;
                s_lg     <= to_unsigned(lg, 6);
                s_fin_mb <= '1' when reste = 0 else '0';
                s_valid  <= '1';
                loop
                    wait until rising_edge(clk);
                    exit when s_ready = '1';
                end loop;
            end loop;
        end loop;
        s_valid <= '0';
        wait;
    end process;

    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
        end if;
    end process;

    controle : process (clk)
        file f          : octets_f open read_mode is REF & "es.bin";
        variable c      : character;
        variable n, err : natural := 0;
        variable cycles : natural := 0;
    begin
        if rising_edge(clk) then
            cycles := cycles + 1;
            if m_valid = '1' and m_ready = '1' and n < G_N_OUT then
                read(f, c);
                if m_data /= octet(c) then
                    if err < 10 then
                        report "ecart a l'octet " & integer'image(n) & " : " & to_hstring(m_data) & " au lieu de " & to_hstring(octet(c)) severity warning;
                    end if;
                    err := err + 1;
                end if;
                n := n + 1;
                if n = G_N_OUT then
                    if err = 0 then
                        report "OK es.bin : " & integer'image(n) & " octets identiques (" & integer'image(G_IMAGES) & " images, en-tetes et fin de sequence)";
                    else
                        report "ECHEC es.bin : " & integer'image(err) & " octets differents sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
            if cycles > 40 * G_N_OUT + 100000 then
                report "ECHEC es.bin : delai depasse, " & integer'image(n) & " octets recus" severity error;
                finish;
            end if;
        end if;
    end process;
end architecture sim;

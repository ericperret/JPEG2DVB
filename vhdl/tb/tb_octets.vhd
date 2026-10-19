--==============================================================================
--  Nom        : tb_octets.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test des modules à flux d'octets (dispersion d'énergie,
--               Reed-Solomon, entrelaceur) : entrée lue dans un fichier de
--               JPEG2DVB, sortie comparée octet par octet au fichier de l'étape
--               suivante ; trous aléatoires côté entrée et côté sortie pour
--               éprouver le contrôle de flux
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Paramètres : G_DUT 1 = prbs_disp, 2 = rs_enc, 3 = interleaver
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.dvbs_pkg.all;
use work.tb_pkg.all;

entity tb_octets is
    generic (
        G_DUT    : natural := 1;
        G_IN     : string  := "ts.bin";
        G_OUT    : string  := "rand.bin";
        G_N_IN   : natural := 12032;
        G_N_OUT  : natural := 12032;
        G_PKT    : natural := 188;          -- longueur des paquets en entrée (repère s_sop)
        G_ALEA   : boolean := true
    );
end entity tb_octets;

architecture sim of tb_octets is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal s_valid : std_logic := '0';
    signal s_ready : std_logic;
    signal s_data  : octet_t := (others => '0');
    signal s_sop   : std_logic := '0';
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_data  : octet_t;
    signal m_sop   : std_logic;
begin
    clk <= not clk after 5 ns;

    g1 : if G_DUT = 1 generate
        dut : entity work.prbs_disp port map (clk, rst, s_valid, s_ready, s_data, s_sop, m_valid, m_ready, m_data, m_sop);
    elsif G_DUT = 2 generate
        dut : entity work.rs_enc port map (clk, rst, s_valid, s_ready, s_data, s_sop, m_valid, m_ready, m_data, m_sop);
    elsif G_DUT = 3 generate
        dut : entity work.interleaver port map (clk, rst, s_valid, s_ready, s_data, s_sop, m_valid, m_ready, m_data, m_sop);
    end generate;

    -- source : octets du fichier d'entrée
    source : process
        file f      : octets_f open read_mode is REF & G_IN;
        variable c  : character;
        variable r  : std_logic_vector(15 downto 0) := x"ACE1";
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for k in 0 to G_N_IN - 1 loop
            read(f, c);
            if G_ALEA then
                r := alea(r);
                if r(0) = '1' and r(1) = '1' then
                    s_valid <= '0';
                    wait until rising_edge(clk);
                end if;
            end if;
            s_data  <= octet(c);
            s_sop   <= '1' when k mod G_PKT = 0 else '0';
            s_valid <= '1';
            loop
                wait until rising_edge(clk);
                exit when s_ready = '1';
            end loop;
        end loop;
        s_valid <= '0';
        wait;
    end process;

    -- puits : m_ready aléatoire
    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            if G_ALEA then
                m_ready <= r(0) or r(2);
            end if;
        end if;
    end process;

    -- comparaison avec le fichier de référence
    controle : process (clk)
        file f           : octets_f open read_mode is REF & G_OUT;
        variable c       : character;
        variable n, err  : natural := 0;
        variable cycles  : natural := 0;
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
                        report "OK " & G_OUT & " : " & integer'image(n) & " octets identiques (" & integer'image(cycles) & " cycles)";
                    else
                        report "ECHEC " & G_OUT & " : " & integer'image(err) & " octets differents sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
            if cycles > 20 * G_N_OUT + 10000 then
                report "ECHEC " & G_OUT & " : delai depasse, " & integer'image(n) & " octets recus" severity error;
                finish;
            end if;
        end if;
    end process;
end architecture sim;

--==============================================================================
--  Nom        : tb_mire.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test de la mire animée : macroblocs des 2 premières
--               images comparés à ceux de l'étape 01 (ref/mire.png chargée,
--               option « mobile »)
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

entity tb_mire is
    generic (
        G_N : natural := 304128              -- 2 images
    );
end entity tb_mire;

architecture sim of tb_mire is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_data  : unsigned(7 downto 0);
    signal m_debut : std_logic;
begin
    clk <= not clk after 5 ns;
    dut : entity work.mire_gen port map (clk, rst, m_valid, m_ready, m_data, m_debut);

    process
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
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
        file f          : octets_f open read_mode is REF & "mire_mb.bin";
        variable c      : character;
        variable n, err : natural := 0;
    begin
        if rising_edge(clk) then
            if m_valid = '1' and m_ready = '1' and n < G_N then
                read(f, c);
                if std_logic_vector(m_data) /= octet(c) then
                    if err < 10 then
                        report "ecart a l'octet " & integer'image(n) & " (image " & integer'image(n / 152064) & ", macrobloc " & integer'image((n mod 152064) / 384) &
                               ") : " & integer'image(to_integer(m_data)) & " au lieu de " & integer'image(character'pos(c)) severity warning;
                    end if;
                    err := err + 1;
                end if;
                if (n mod 152064 = 0) and m_debut /= '1' then
                    report "m_debut absent au debut de l'image" severity warning;
                    err := err + 1;
                end if;
                n := n + 1;
                if n = G_N then
                    if err = 0 then
                        report "OK mire_mb.bin : " & integer'image(n) & " octets identiques (" & integer'image(n / 152064) & " images)";
                    else
                        report "ECHEC mire_mb.bin : " & integer'image(err) & " octets differents sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
        end if;
    end process;
end architecture sim;

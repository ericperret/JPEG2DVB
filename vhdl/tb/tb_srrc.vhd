--==============================================================================
--  Nom        : tb_srrc.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test du filtre SRRC polyphase : entrée = symboles ±1
--               de l'étape 13, sortie comparée aux échantillons I/Q 16 bits
--               (petit-boutiste, entrelacés) du fichier .cs16 de l'étape 14
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

entity tb_srrc is
    generic (
        G_IN    : string  := "qpsk.bin";
        G_OUT   : string  := "iq.cs16";
        G_N_SYM : natural := 104448;        -- symboles lus
        G_N_ECH : natural := 160000         -- échantillons comparés (20 000 symboles)
    );
end entity tb_srrc;

architecture sim of tb_srrc is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal s_valid : std_logic := '0';
    signal s_ready : std_logic;
    signal s_i, s_q : signed(1 downto 0) := "00";
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_i, m_q : signed(15 downto 0);
begin
    clk <= not clk after 5 ns;
    dut : entity work.srrc_poly port map (clk, rst, s_valid, s_ready, s_i, s_q, m_valid, m_ready, m_i, m_q);

    source : process
        file f          : octets_f open read_mode is REF & G_IN;
        variable ci, cq : character;
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for k in 0 to G_N_SYM - 1 loop
            read(f, ci); read(f, cq);
            s_i     <= resize(signed(octet(ci)), 2);
            s_q     <= resize(signed(octet(cq)), 2);
            s_valid <= '1';
            loop
                wait until rising_edge(clk);
                exit when s_ready = '1';
            end loop;
        end loop;
        s_valid <= '0';
        wait;
    end process;

    -- sortie à plein débit la plupart du temps, avec quelques arrêts
    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(1) or r(2);
        end if;
    end process;

    controle : process (clk)
        file f          : octets_f open read_mode is REF & G_OUT;
        variable a, b   : character;
        variable ei, eq : signed(15 downto 0);
        variable n, err : natural := 0;
        variable cycles : natural := 0;
    begin
        if rising_edge(clk) then
            cycles := cycles + 1;
            if m_valid = '1' and m_ready = '1' and n < G_N_ECH then
                read(f, a); read(f, b); ei := signed(octet(b) & octet(a));
                read(f, a); read(f, b); eq := signed(octet(b) & octet(a));
                if m_i /= ei or m_q /= eq then
                    if err < 10 then
                        report "ecart a l'echantillon " & integer'image(n) & " : " & integer'image(to_integer(m_i)) & ", " & integer'image(to_integer(m_q)) &
                               " au lieu de " & integer'image(to_integer(ei)) & ", " & integer'image(to_integer(eq)) severity warning;
                    end if;
                    err := err + 1;
                end if;
                n := n + 1;
                if n = G_N_ECH then
                    if err = 0 then
                        report "OK " & G_OUT & " : " & integer'image(n) & " echantillons I/Q identiques (" & integer'image(cycles) & " cycles)";
                    else
                        report "ECHEC " & G_OUT & " : " & integer'image(err) & " echantillons differents sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
        end if;
    end process;
end architecture sim;

--==============================================================================
--  Nom        : tb_conv.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test du codeur convolutif (taux G_FEC) : entrée = sortie
--               de l'entrelaceur (JPEG2DVB étape 11), sortie comparée bit à bit
--               aux bits codés de l'étape 12 (I puis Q de chaque symbole,
--               regroupés par octets, poids fort en tête)
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
use work.dvbs_pkg.all;
use work.tb_pkg.all;

entity tb_conv is
    generic (
        G_FEC   : natural := 0;
        G_IN    : string  := "inter.bin";
        G_OUT   : string  := "conv.bin";
        G_N_IN  : natural := 13056;
        G_N_OUT : natural := 26112
    );
end entity tb_conv;

architecture sim of tb_conv is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal s_valid : std_logic := '0';
    signal s_ready : std_logic;
    signal s_data  : octet_t := (others => '0');
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_data  : std_logic_vector(1 downto 0);
begin
    clk <= not clk after 5 ns;
    dut : entity work.conv_enc generic map (G_FEC => G_FEC) port map (clk, rst, s_valid, s_ready, s_data, m_valid, m_ready, m_data);

    source : process
        file f     : octets_f open read_mode is REF & G_IN;
        variable c : character;
        variable r : std_logic_vector(15 downto 0) := x"ACE1";
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for k in 0 to G_N_IN - 1 loop
            read(f, c);
            r := alea(r);
            if r(0) = '1' and r(1) = '1' then
                s_valid <= '0';
                wait until rising_edge(clk);
            end if;
            s_data  <= octet(c);
            s_valid <= '1';
            loop
                wait until rising_edge(clk);
                exit when s_ready = '1';
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
        file f          : octets_f open read_mode is REF & G_OUT;
        variable c      : character;
        variable acc    : std_logic_vector(7 downto 0);
        variable nb     : natural := 0;
        variable n, err : natural := 0;
        variable cycles : natural := 0;
    begin
        if rising_edge(clk) then
            cycles := cycles + 1;
            if m_valid = '1' and m_ready = '1' and n < G_N_OUT then
                acc := acc(5 downto 0) & m_data;
                nb  := nb + 2;
                if nb = 8 then
                    nb := 0;
                    read(f, c);
                    if acc /= octet(c) then
                        if err < 10 then
                            report "ecart a l'octet " & integer'image(n) & " : " & to_hstring(acc) & " au lieu de " & to_hstring(octet(c)) severity warning;
                        end if;
                        err := err + 1;
                    end if;
                    n := n + 1;
                    if n = G_N_OUT then
                        if err = 0 then
                            report "OK " & G_OUT & " : " & integer'image(n) & " octets identiques (" & integer'image(n * 8) & " bits codes, " & integer'image(cycles) & " cycles)";
                        else
                            report "ECHEC " & G_OUT & " : " & integer'image(err) & " octets differents sur " & integer'image(n) severity error;
                        end if;
                        finish;
                    end if;
                end if;
            end if;
            if cycles > 40 * G_N_OUT + 10000 then
                report "ECHEC " & G_OUT & " : delai depasse, " & integer'image(n) & " octets recus" severity error;
                finish;
            end if;
        end if;
    end process;
end architecture sim;

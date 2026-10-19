--==============================================================================
--  Nom        : tb_backend.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test de la chaîne arrière complète : paquets TS de
--               l'étape 08 en entrée, échantillons I/Q comparés au fichier
--               .cs16 de l'étape 14 ; sortie à plein débit (un échantillon
--               par cycle demandé, comme vers le sigma-delta)
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

entity tb_backend is
    generic (
        G_IN    : string  := "ts.bin";
        G_OUT   : string  := "iq.cs16";
        G_N_IN  : natural := 12032;          -- 64 paquets TS
        G_N_ECH : natural := 160000          -- 20 000 symboles
    );
end entity tb_backend;

architecture sim of tb_backend is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal s_valid : std_logic := '0';
    signal s_ready : std_logic;
    signal s_data  : octet_t := (others => '0');
    signal s_sop   : std_logic := '0';
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_i, m_q : signed(15 downto 0);
begin
    clk <= not clk after 6.25 ns;          -- 80 MHz
    dut : entity work.tx_backend generic map (G_FEC => 0)
        port map (clk, rst, s_valid, s_ready, s_data, s_sop, m_valid, m_ready, m_i, m_q);

    source : process
        file f     : octets_f open read_mode is REF & G_IN;
        variable c : character;
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for k in 0 to G_N_IN - 1 loop
            read(f, c);
            s_data  <= octet(c);
            s_sop   <= '1' when k mod 188 = 0 else '0';
            s_valid <= '1';
            loop
                wait until rising_edge(clk);
                exit when s_ready = '1';
            end loop;
        end loop;
        s_valid <= '0';
        wait;
    end process;

    controle : process (clk)
        file f            : octets_f open read_mode is REF & G_OUT;
        variable a, b     : character;
        variable ei, eq   : signed(15 downto 0);
        variable n, err   : natural := 0;
        variable cycles   : natural := 0;
        variable premier  : natural := 0;
        variable trous    : natural := 0;
    begin
        if rising_edge(clk) then
            cycles := cycles + 1;
            if n > 0 and n < G_N_ECH and m_valid = '0' then
                trous := trous + 1;            -- cycle sans échantillon une fois le flux établi
            end if;
            if m_valid = '1' and m_ready = '1' and n < G_N_ECH then
                if n = 0 then premier := cycles; end if;
                read(f, a); read(f, b); ei := signed(std_logic_vector'(octet(b) & octet(a)));
                read(f, a); read(f, b); eq := signed(std_logic_vector'(octet(b) & octet(a)));
                if m_i /= ei or m_q /= eq then
                    if err < 10 then
                        report "ecart a l'echantillon " & integer'image(n) severity warning;
                    end if;
                    err := err + 1;
                end if;
                n := n + 1;
                if n = G_N_ECH then
                    if err = 0 then
                        report "OK " & G_OUT & " : " & integer'image(n) & " echantillons I/Q identiques depuis le TS ; premier au cycle " &
                               integer'image(premier) & ", " & integer'image(trous) & " cycles sans echantillon ensuite";
                    else
                        report "ECHEC " & G_OUT & " : " & integer'image(err) & " echantillons differents sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
            if cycles > 4 * G_N_ECH + 100000 then
                report "ECHEC " & G_OUT & " : delai depasse, " & integer'image(n) & " echantillons recus" severity error;
                finish;
            end if;
        end if;
    end process;
end architecture sim;

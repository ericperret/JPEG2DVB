--==============================================================================
--  Nom        : tb_dvbs.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : bancs de test de bout en bout, mire animée (ref/mire.png,
--               3 images, DCT en virgule fixe, code d'échelle 8) :
--               G_DUT = 1 : video_enc, paquets TS prélevés au rythme du canal
--               (un par 13 056 cycles), comparés au TS de l'étape 08 ;
--               G_DUT = 2 : dvbs_tx, échantillons I/Q comparés au .cs16 de
--               l'étape 14
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

entity tb_dvbs is
    generic (
        G_DUT : natural := 1;
        G_OUT : string  := "mire_ts.bin";
        G_N   : natural := 144572          -- octets TS (1) ou échantillons I/Q (2)
    );
end entity tb_dvbs;

architecture sim of tb_dvbs is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal code    : unsigned(4 downto 0) := to_unsigned(8, 5);
    signal m_valid : std_logic;
    signal m_ready : std_logic := '0';
    signal m_data  : std_logic_vector(7 downto 0);
    signal m_sop   : std_logic;
    signal m_i, m_q : signed(15 downto 0);
begin
    clk <= not clk after 6.25 ns;            -- 80 MHz

    g1 : if G_DUT = 1 generate
        dut : entity work.video_enc generic map (G_IMAGES => 3)
            port map (clk, rst, code, m_valid, m_ready, m_data, m_sop);
        -- un paquet de 188 octets par créneau de 13 056 cycles
        rythme : process (clk)
            variable cyc    : natural := 0;
            variable credit : integer := 0;
        begin
            if rising_edge(clk) then
                if rst = '0' then
                    if m_valid = '1' and m_ready = '1' then credit := credit - 1; end if;
                    if cyc = 0 then credit := credit + 188; end if;
                    cyc := (cyc + 1) mod 13056;
                    m_ready <= '1' when credit > 0 else '0';
                end if;
            end if;
        end process;
    elsif G_DUT = 2 generate
        dut : entity work.dvbs_tx generic map (G_IMAGES => 3)
            port map (clk, rst, code, m_valid, m_ready, m_i, m_q);
        m_ready <= '1';
    end generate;

    process
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        wait;
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
            if m_valid = '1' and m_ready = '1' and n < G_N then
                if G_DUT = 1 then
                    read(f, a);
                    if m_data /= octet(a) then
                        if err < 10 then
                            report "ecart a l'octet " & integer'image(n) & " (paquet " & integer'image(n / 188) & ") : " & to_hstring(m_data) & " au lieu de " & to_hstring(octet(a)) severity warning;
                        end if;
                        err := err + 1;
                    end if;
                else
                    read(f, a); read(f, b); ei := signed(std_logic_vector'(octet(b) & octet(a)));
                    read(f, a); read(f, b); eq := signed(std_logic_vector'(octet(b) & octet(a)));
                    if m_i /= ei or m_q /= eq then
                        if err < 10 then
                            report "ecart a l'echantillon " & integer'image(n) severity warning;
                        end if;
                        err := err + 1;
                    end if;
                end if;
                n := n + 1;
                if n = G_N then
                    if err = 0 then
                        if G_DUT = 1 then
                            report "OK " & G_OUT & " : " & integer'image(n) & " octets TS identiques depuis la mire (" & integer'image(cycles) & " cycles)";
                        else
                            report "OK " & G_OUT & " : " & integer'image(n) & " echantillons I/Q identiques depuis la mire (" & integer'image(cycles) & " cycles)";
                        end if;
                    else
                        report "ECHEC " & G_OUT & " : " & integer'image(err) & " differences sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
        end if;
    end process;
end architecture sim;

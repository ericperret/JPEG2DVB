--==============================================================================
--  Nom        : tb_bloc.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test des modules à blocs 8 × 8 du codage vidéo (DCT
--               entière, quantification, zigzag) : entrée et sortie comparées
--               aux fichiers de JPEG2DVB (image 0, 2 376 blocs)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Paramètres : G_DUT 1 = dct8x8_int (entrée octets), 2 = quant_intra,
--               3 = zigzag (entrée int16 LE) ; sortie int16 LE
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_pkg.all;

entity tb_bloc is
    generic (
        G_DUT  : natural := 1;
        G_IN   : string  := "mb0.bin";
        G_OUT  : string  := "dct0.bin";
        G_N    : natural := 152064;
        G_CODE : natural := 8
    );
end entity tb_bloc;

architecture sim of tb_bloc is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal s_valid : std_logic := '0';
    signal s_ready : std_logic;
    signal s_pix   : unsigned(7 downto 0) := (others => '0');
    signal s_coef  : signed(15 downto 0) := (others => '0');
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_data  : signed(15 downto 0);
    signal code    : unsigned(4 downto 0) := to_unsigned(G_CODE, 5);
begin
    clk <= not clk after 5 ns;

    g1 : if G_DUT = 1 generate
        dut : entity work.dct8x8_int port map (clk, rst, s_valid, s_ready, s_pix, m_valid, m_ready, m_data);
    elsif G_DUT = 2 generate
        dut : entity work.quant_intra port map (clk, rst, code, s_valid, s_ready, s_coef, m_valid, m_ready, m_data);
    elsif G_DUT = 3 generate
        dut : entity work.zigzag port map (clk, rst, s_valid, s_ready, s_coef, m_valid, m_ready, m_data);
    end generate;

    source : process
        file f     : octets_f open read_mode is REF & G_IN;
        variable a, b : character;
        variable r : std_logic_vector(15 downto 0) := x"ACE1";
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for k in 0 to G_N - 1 loop
            if G_DUT = 1 then
                read(f, a);
                s_pix <= unsigned(octet(a));
            else
                read(f, a); read(f, b);
                s_coef <= signed(std_logic_vector'(octet(b) & octet(a)));
            end if;
            r := alea(r);
            if r(0) = '1' and r(1) = '1' and r(2) = '1' then
                s_valid <= '0';
                wait until rising_edge(clk);
            end if;
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
        variable a, b   : character;
        variable e      : signed(15 downto 0);
        variable n, err : natural := 0;
        variable cycles : natural := 0;
    begin
        if rising_edge(clk) then
            cycles := cycles + 1;
            if m_valid = '1' and m_ready = '1' and n < G_N then
                read(f, a); read(f, b);
                e := signed(std_logic_vector'(octet(b) & octet(a)));
                if m_data /= e then
                    if err < 10 then
                        report "ecart au coefficient " & integer'image(n) & " (bloc " & integer'image(n / 64) & ", rang " & integer'image(n mod 64) & ") : " &
                               integer'image(to_integer(m_data)) & " au lieu de " & integer'image(to_integer(e)) severity warning;
                    end if;
                    err := err + 1;
                end if;
                n := n + 1;
                if n = G_N then
                    if err = 0 then
                        report "OK " & G_OUT & " : " & integer'image(n) & " coefficients identiques (" & integer'image(cycles) & " cycles)";
                    else
                        report "ECHEC " & G_OUT & " : " & integer'image(err) & " coefficients differents sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
            if cycles > 8 * G_N + 10000 then
                report "ECHEC " & G_OUT & " : delai depasse, " & integer'image(n) & " coefficients recus" severity error;
                finish;
            end if;
        end if;
    end process;
end architecture sim;

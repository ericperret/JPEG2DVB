--==============================================================================
--  Nom        : tb_vlc.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test du codeur VLC : vecteurs zigzag de l'image 0
--               (étape 04) en entrée ; mots de code mis bout à bout et
--               comparés bit à bit aux bits de l'étape 05, longueur de chaque
--               macrobloc comparée à la référence
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

entity tb_vlc is
    generic (
        G_IN   : string  := "zz0.bin";
        G_N    : natural := 152064;          -- coefficients (une image)
        G_MB   : natural := 396
    );
end entity tb_vlc;

architecture sim of tb_vlc is
    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
    signal s_valid  : std_logic := '0';
    signal s_ready  : std_logic;
    signal s_data   : signed(15 downto 0) := (others => '0');
    signal m_valid  : std_logic;
    signal m_ready  : std_logic := '1';
    signal m_code   : std_logic_vector(31 downto 0);
    signal m_lg     : unsigned(5 downto 0);
    signal m_fin_mb : std_logic;
begin
    clk <= not clk after 5 ns;
    dut : entity work.vlc_enc port map (clk, rst, s_valid, s_ready, s_data, m_valid, m_ready, m_code, m_lg, m_fin_mb);

    source : process
        file f        : octets_f open read_mode is REF & G_IN;
        variable a, b : character;
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for k in 0 to G_N - 1 loop
            read(f, a); read(f, b);
            s_data  <= signed(std_logic_vector'(octet(b) & octet(a)));
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
        file fb          : octets_f open read_mode is REF & "vlc.bin";
        file fl          : octets_f open read_mode is REF & "mbbits.bin";
        variable a, b    : character;
        variable acc     : std_logic_vector(63 downto 0) := (others => '0');
        variable nacc    : natural := 0;
        variable lg      : natural;
        variable bits_mb : natural := 0;
        variable ref_mb  : natural;
        variable nmb     : natural := 0;
        variable noct    : natural := 0;
        variable err_o, err_l : natural := 0;
        variable e       : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            if m_valid = '1' and m_ready = '1' and nmb < G_MB then
                lg := to_integer(m_lg);
                acc := std_logic_vector(shift_left(unsigned(acc), lg)) or (std_logic_vector(resize(unsigned(m_code), 64)) and std_logic_vector(shift_left(to_unsigned(1, 64), lg) - 1));
                nacc := nacc + lg;
                bits_mb := bits_mb + lg;
                while nacc >= 8 loop
                    read(fb, a);
                    e := acc(nacc - 1 downto nacc - 8);
                    if e /= octet(a) then
                        if err_o < 10 then
                            report "ecart a l'octet " & integer'image(noct) & " (macrobloc " & integer'image(nmb) & ")" severity warning;
                        end if;
                        err_o := err_o + 1;
                    end if;
                    noct := noct + 1;
                    nacc := nacc - 8;
                end loop;
                if m_fin_mb = '1' then
                    read(fl, a); read(fl, b);
                    ref_mb := character'pos(b) * 256 + character'pos(a);
                    if ref_mb /= bits_mb then
                        if err_l < 10 then
                            report "macrobloc " & integer'image(nmb) & " : " & integer'image(bits_mb) & " bits au lieu de " & integer'image(ref_mb) severity warning;
                        end if;
                        err_l := err_l + 1;
                    end if;
                    bits_mb := 0;
                    nmb := nmb + 1;
                    if nmb = G_MB then
                        if err_o = 0 and err_l = 0 then
                            report "OK vlc.bin : " & integer'image(G_MB) & " macroblocs, " & integer'image(noct) & " octets identiques, longueurs identiques";
                        else
                            report "ECHEC vlc.bin : " & integer'image(err_o) & " octets et " & integer'image(err_l) & " longueurs differents" severity error;
                        end if;
                        finish;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture sim;

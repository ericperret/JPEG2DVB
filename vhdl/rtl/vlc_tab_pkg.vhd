--==============================================================================
--  Nom        : vlc_tab_pkg.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : tables VLC MPEG-2 intra : B.12 (taille DC luminance), B.13
--               (taille DC chrominance), B.14 (coefficients AC, intra_vlc_format
--               = 0, 111 paires run / niveau, sans le bit de signe)
--               (fichier généré par scripts/gen_vlc.js depuis la page 05)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package vlc_tab_pkg is
    type dc_vlc_t is record
        code : std_logic_vector(9 downto 0);       -- cadré à droite
        lg   : natural range 0 to 10;
    end record;
    type dc_tab_t is array (0 to 11) of dc_vlc_t;
    constant DC_LUMA : dc_tab_t := (
        0 => ("0000000100", 3),
        1 => ("0000000000", 2),
        2 => ("0000000001", 2),
        3 => ("0000000101", 3),
        4 => ("0000000110", 3),
        5 => ("0000001110", 4),
        6 => ("0000011110", 5),
        7 => ("0000111110", 6),
        8 => ("0001111110", 7),
        9 => ("0011111110", 8),
        10 => ("0111111110", 9),
        11 => ("0111111111", 9));
    constant DC_CHROMA : dc_tab_t := (
        0 => ("0000000000", 2),
        1 => ("0000000001", 2),
        2 => ("0000000010", 2),
        3 => ("0000000110", 3),
        4 => ("0000001110", 4),
        5 => ("0000011110", 5),
        6 => ("0000111110", 6),
        7 => ("0001111110", 7),
        8 => ("0011111110", 8),
        9 => ("0111111110", 9),
        10 => ("1111111110", 10),
        11 => ("1111111111", 10));
    constant AC_EOB    : std_logic_vector(1 downto 0) := "10";
    constant AC_ESCAPE : std_logic_vector(5 downto 0) := "000001";

    type ac_vlc_t is record
        trouve : boolean;
        code   : std_logic_vector(15 downto 0);    -- cadré à droite, sans le signe
        lg     : natural range 0 to 16;
    end record;
    function ac_code(run : natural range 0 to 63; niveau : natural range 0 to 2047) return ac_vlc_t;
end package vlc_tab_pkg;

package body vlc_tab_pkg is
    function ac_code(run : natural range 0 to 63; niveau : natural range 0 to 2047) return ac_vlc_t is
        variable v : ac_vlc_t := (false, (others => '0'), 0);
    begin
        case run is
            when 0 =>
                case niveau is
                    when  1 => v := (true, "0000000000000011", 2);
                    when  2 => v := (true, "0000000000000100", 4);
                    when  3 => v := (true, "0000000000000101", 5);
                    when  4 => v := (true, "0000000000000110", 7);
                    when  5 => v := (true, "0000000000100110", 8);
                    when  6 => v := (true, "0000000000100001", 8);
                    when  7 => v := (true, "0000000000001010", 10);
                    when  8 => v := (true, "0000000000011101", 12);
                    when  9 => v := (true, "0000000000011000", 12);
                    when 10 => v := (true, "0000000000010011", 12);
                    when 11 => v := (true, "0000000000010000", 12);
                    when 12 => v := (true, "0000000000011010", 13);
                    when 13 => v := (true, "0000000000011001", 13);
                    when 14 => v := (true, "0000000000011000", 13);
                    when 15 => v := (true, "0000000000010111", 13);
                    when 16 => v := (true, "0000000000011111", 14);
                    when 17 => v := (true, "0000000000011110", 14);
                    when 18 => v := (true, "0000000000011101", 14);
                    when 19 => v := (true, "0000000000011100", 14);
                    when 20 => v := (true, "0000000000011011", 14);
                    when 21 => v := (true, "0000000000011010", 14);
                    when 22 => v := (true, "0000000000011001", 14);
                    when 23 => v := (true, "0000000000011000", 14);
                    when 24 => v := (true, "0000000000010111", 14);
                    when 25 => v := (true, "0000000000010110", 14);
                    when 26 => v := (true, "0000000000010101", 14);
                    when 27 => v := (true, "0000000000010100", 14);
                    when 28 => v := (true, "0000000000010011", 14);
                    when 29 => v := (true, "0000000000010010", 14);
                    when 30 => v := (true, "0000000000010001", 14);
                    when 31 => v := (true, "0000000000010000", 14);
                    when 32 => v := (true, "0000000000011000", 15);
                    when 33 => v := (true, "0000000000010111", 15);
                    when 34 => v := (true, "0000000000010110", 15);
                    when 35 => v := (true, "0000000000010101", 15);
                    when 36 => v := (true, "0000000000010100", 15);
                    when 37 => v := (true, "0000000000010011", 15);
                    when 38 => v := (true, "0000000000010010", 15);
                    when 39 => v := (true, "0000000000010001", 15);
                    when 40 => v := (true, "0000000000010000", 15);
                    when others => null;
                end case;
            when 1 =>
                case niveau is
                    when  1 => v := (true, "0000000000000011", 3);
                    when  2 => v := (true, "0000000000000110", 6);
                    when  3 => v := (true, "0000000000100101", 8);
                    when  4 => v := (true, "0000000000001100", 10);
                    when  5 => v := (true, "0000000000011011", 12);
                    when  6 => v := (true, "0000000000010110", 13);
                    when  7 => v := (true, "0000000000010101", 13);
                    when  8 => v := (true, "0000000000011111", 15);
                    when  9 => v := (true, "0000000000011110", 15);
                    when 10 => v := (true, "0000000000011101", 15);
                    when 11 => v := (true, "0000000000011100", 15);
                    when 12 => v := (true, "0000000000011011", 15);
                    when 13 => v := (true, "0000000000011010", 15);
                    when 14 => v := (true, "0000000000011001", 15);
                    when 15 => v := (true, "0000000000010011", 16);
                    when 16 => v := (true, "0000000000010010", 16);
                    when 17 => v := (true, "0000000000010001", 16);
                    when 18 => v := (true, "0000000000010000", 16);
                    when others => null;
                end case;
            when 2 =>
                case niveau is
                    when  1 => v := (true, "0000000000000101", 4);
                    when  2 => v := (true, "0000000000000100", 7);
                    when  3 => v := (true, "0000000000001011", 10);
                    when  4 => v := (true, "0000000000010100", 12);
                    when  5 => v := (true, "0000000000010100", 13);
                    when others => null;
                end case;
            when 3 =>
                case niveau is
                    when  1 => v := (true, "0000000000000111", 5);
                    when  2 => v := (true, "0000000000100100", 8);
                    when  3 => v := (true, "0000000000011100", 12);
                    when  4 => v := (true, "0000000000010011", 13);
                    when others => null;
                end case;
            when 4 =>
                case niveau is
                    when  1 => v := (true, "0000000000000110", 5);
                    when  2 => v := (true, "0000000000001111", 10);
                    when  3 => v := (true, "0000000000010010", 12);
                    when others => null;
                end case;
            when 5 =>
                case niveau is
                    when  1 => v := (true, "0000000000000111", 6);
                    when  2 => v := (true, "0000000000001001", 10);
                    when  3 => v := (true, "0000000000010010", 13);
                    when others => null;
                end case;
            when 6 =>
                case niveau is
                    when  1 => v := (true, "0000000000000101", 6);
                    when  2 => v := (true, "0000000000011110", 12);
                    when  3 => v := (true, "0000000000010100", 16);
                    when others => null;
                end case;
            when 7 =>
                case niveau is
                    when  1 => v := (true, "0000000000000100", 6);
                    when  2 => v := (true, "0000000000010101", 12);
                    when others => null;
                end case;
            when 8 =>
                case niveau is
                    when  1 => v := (true, "0000000000000111", 7);
                    when  2 => v := (true, "0000000000010001", 12);
                    when others => null;
                end case;
            when 9 =>
                case niveau is
                    when  1 => v := (true, "0000000000000101", 7);
                    when  2 => v := (true, "0000000000010001", 13);
                    when others => null;
                end case;
            when 10 =>
                case niveau is
                    when  1 => v := (true, "0000000000100111", 8);
                    when  2 => v := (true, "0000000000010000", 13);
                    when others => null;
                end case;
            when 11 =>
                case niveau is
                    when  1 => v := (true, "0000000000100011", 8);
                    when  2 => v := (true, "0000000000011010", 16);
                    when others => null;
                end case;
            when 12 =>
                case niveau is
                    when  1 => v := (true, "0000000000100010", 8);
                    when  2 => v := (true, "0000000000011001", 16);
                    when others => null;
                end case;
            when 13 =>
                case niveau is
                    when  1 => v := (true, "0000000000100000", 8);
                    when  2 => v := (true, "0000000000011000", 16);
                    when others => null;
                end case;
            when 14 =>
                case niveau is
                    when  1 => v := (true, "0000000000001110", 10);
                    when  2 => v := (true, "0000000000010111", 16);
                    when others => null;
                end case;
            when 15 =>
                case niveau is
                    when  1 => v := (true, "0000000000001101", 10);
                    when  2 => v := (true, "0000000000010110", 16);
                    when others => null;
                end case;
            when 16 =>
                case niveau is
                    when  1 => v := (true, "0000000000001000", 10);
                    when  2 => v := (true, "0000000000010101", 16);
                    when others => null;
                end case;
            when 17 =>
                case niveau is
                    when  1 => v := (true, "0000000000011111", 12);
                    when others => null;
                end case;
            when 18 =>
                case niveau is
                    when  1 => v := (true, "0000000000011010", 12);
                    when others => null;
                end case;
            when 19 =>
                case niveau is
                    when  1 => v := (true, "0000000000011001", 12);
                    when others => null;
                end case;
            when 20 =>
                case niveau is
                    when  1 => v := (true, "0000000000010111", 12);
                    when others => null;
                end case;
            when 21 =>
                case niveau is
                    when  1 => v := (true, "0000000000010110", 12);
                    when others => null;
                end case;
            when 22 =>
                case niveau is
                    when  1 => v := (true, "0000000000011111", 13);
                    when others => null;
                end case;
            when 23 =>
                case niveau is
                    when  1 => v := (true, "0000000000011110", 13);
                    when others => null;
                end case;
            when 24 =>
                case niveau is
                    when  1 => v := (true, "0000000000011101", 13);
                    when others => null;
                end case;
            when 25 =>
                case niveau is
                    when  1 => v := (true, "0000000000011100", 13);
                    when others => null;
                end case;
            when 26 =>
                case niveau is
                    when  1 => v := (true, "0000000000011011", 13);
                    when others => null;
                end case;
            when 27 =>
                case niveau is
                    when  1 => v := (true, "0000000000011111", 16);
                    when others => null;
                end case;
            when 28 =>
                case niveau is
                    when  1 => v := (true, "0000000000011110", 16);
                    when others => null;
                end case;
            when 29 =>
                case niveau is
                    when  1 => v := (true, "0000000000011101", 16);
                    when others => null;
                end case;
            when 30 =>
                case niveau is
                    when  1 => v := (true, "0000000000011100", 16);
                    when others => null;
                end case;
            when 31 =>
                case niveau is
                    when  1 => v := (true, "0000000000011011", 16);
                    when others => null;
                end case;
            when others => null;
        end case;
        return v;
    end function;
end package body vlc_tab_pkg;

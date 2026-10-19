--==============================================================================
--  Nom        : dct8x8_int.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : DCT 8 × 8 entière, MPEG-2 intra (sans centrage) ; référence
--               bit à bit : JPEG2DVB étape 02, option « virgule fixe »
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : entrée : 64 pixels d'un bloc (octets non signés), ligne par
--               ligne ; sortie : 64 coefficients signés 16 bits en ordre
--               naturel F[v][u] (indice 8v + u)
--  Principe   : Ci[k][n] = round(4096 · c(k)/2 · cos((2n+1)kπ/16)), 13 bits ;
--               passe lignes R'[y][u] = (Σx Ci[u][x]·f[y][x] + 32) >> 6 ;
--               passe colonnes F[v][u] = (Σy Ci[v][y]·R'[y][u] + 2¹⁷) >> 18
--               (décalages arithmétiques). Un résultat par cycle et par passe,
--               8 multiplieurs par passe ; 192 cycles par bloc.
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dct8x8_int is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  unsigned(7 downto 0);
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out signed(15 downto 0)
    );
end entity dct8x8_int;

architecture rtl of dct8x8_int is
    type ci_t is array (0 to 7, 0 to 7) of integer range -2048 to 2047;
    constant CI : ci_t := (
        (1448,  1448,  1448,  1448,  1448,  1448,  1448,  1448),
        (2009,  1703,  1138,   400,  -400, -1138, -1703, -2009),
        (1892,   784,  -784, -1892, -1892,  -784,   784,  1892),
        (1703,  -400, -2009, -1138,  1138,  2009,   400, -1703),
        (1448, -1448, -1448,  1448,  1448, -1448, -1448,  1448),
        (1138, -2009,   400,  1703, -1703,  -400,  2009, -1138),
        ( 784, -1892,  1892,  -784,  -784,  1892, -1892,   784),
        ( 400, -1138,  1703, -2009,  2009, -1703,  1138,  -400));

    type pix_t  is array (0 to 63) of unsigned(7 downto 0);
    type rang_t is array (0 to 63) of signed(17 downto 0);       -- R' sur 18 bits signés
    signal blk : pix_t;
    signal rr  : rang_t;
    type etat_t is (CHARGE, LIGNES, COLONNES);
    signal etat    : etat_t := CHARGE;
    signal idx     : natural range 0 to 63 := 0;
    signal o_valid : std_logic := '0';
    signal libre   : std_logic;
begin
    libre   <= (not o_valid) or m_ready;
    s_ready <= '1' when etat = CHARGE and rst = '0' else '0';
    m_valid <= o_valid;

    process (clk)
        variable y, u, v : natural range 0 to 7;
        variable acc     : signed(35 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                etat    <= CHARGE;
                idx     <= 0;
                o_valid <= '0';
            else
                if libre = '1' then
                    o_valid <= '0';
                end if;
                case etat is
                    when CHARGE =>
                        if s_valid = '1' then
                            blk(idx) <= s_data;
                            if idx = 63 then
                                idx  <= 0;
                                etat <= LIGNES;
                            else
                                idx <= idx + 1;
                            end if;
                        end if;
                    when LIGNES =>
                        y := idx / 8; u := idx mod 8;
                        acc := (others => '0');
                        for x in 0 to 7 loop
                            acc := acc + to_signed(CI(u, x), 13) * signed('0' & blk(y * 8 + x));
                        end loop;
                        rr(idx) <= resize(shift_right(acc + 32, 6), 18);
                        if idx = 63 then
                            idx  <= 0;
                            etat <= COLONNES;
                        else
                            idx <= idx + 1;
                        end if;
                    when COLONNES =>
                        if libre = '1' then
                            v := idx / 8; u := idx mod 8;
                            acc := (others => '0');
                            for yy in 0 to 7 loop
                                acc := acc + resize(to_signed(CI(v, yy), 13) * rr(yy * 8 + u), 36);
                            end loop;
                            m_data  <= resize(shift_right(acc + 131072, 18), 16);
                            o_valid <= '1';
                            if idx = 63 then
                                idx  <= 0;
                                etat <= CHARGE;
                            else
                                idx <= idx + 1;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture rtl;

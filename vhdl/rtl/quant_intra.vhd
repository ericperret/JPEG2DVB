--==============================================================================
--  Nom        : quant_intra.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : quantification MPEG-2 intra, matrice par défaut, q_scale_type 0 ;
--               référence bit à bit : JPEG2DVB étape 03
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : entrée : coefficients DCT signés 16 bits, blocs de 64 en ordre
--               naturel ; code : quantiser_scale_code (1 à 31) lu avec chaque
--               coefficient ; sortie : coefficients quantifiés signés 16 bits
--  Principe   : DC : (F + 4) >> 3 borné à 0..255 ;
--               AC : ±floor((32|F| + D) / (2D)) borné à 2 047, D = W·2·code
--               (même arrondi que Math.round de la page 03). Division exacte
--               par l'inverse m = floor(2²⁴ / 2D) + 1 tiré d'une table (63 × 31),
--               puis correction d'une unité.
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity quant_intra is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        code    : in  unsigned(4 downto 0);
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  signed(15 downto 0);
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out signed(15 downto 0)
    );
end entity quant_intra;

architecture rtl of quant_intra is
    type w_t is array (0 to 63) of natural range 0 to 255;
    -- default_intra_quantiser_matrix, ordre naturel F[v][u]
    constant W : w_t := (
         8, 16, 19, 22, 26, 27, 29, 34,
        16, 16, 22, 24, 27, 29, 34, 37,
        19, 22, 26, 27, 29, 34, 34, 38,
        22, 22, 26, 27, 29, 34, 37, 40,
        22, 26, 27, 29, 32, 35, 40, 48,
        26, 27, 29, 32, 35, 40, 48, 58,
        26, 27, 29, 34, 38, 46, 56, 69,
        27, 29, 35, 38, 46, 56, 69, 83);
    type inv_t is array (0 to 63, 1 to 31) of natural range 0 to 2 ** 24;
    function inverses return inv_t is
        variable t : inv_t;
    begin
        for i in 0 to 63 loop
            for c in 1 to 31 loop
                t(i, c) := (2 ** 24) / (4 * W(i) * c) + 1;     -- 2D = 4·W·code
            end loop;
        end loop;
        return t;
    end function;
    constant INV : inv_t := inverses;

    signal idx     : natural range 0 to 63 := 0;
    signal o_valid : std_logic := '0';
    signal libre   : std_logic;
begin
    libre   <= (not o_valid) or m_ready;
    s_ready <= libre and not rst;
    m_valid <= o_valid;

    process (clk)
        variable c        : natural range 1 to 31;
        variable a        : unsigned(15 downto 0);
        variable den      : unsigned(13 downto 0);
        variable num      : unsigned(21 downto 0);
        variable p        : unsigned(45 downto 0);
        variable q        : unsigned(21 downto 0);
        variable dc       : signed(16 downto 0);
        variable r        : integer range -2047 to 2047;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                idx     <= 0;
                o_valid <= '0';
            elsif libre = '1' then
                o_valid <= s_valid;
                if s_valid = '1' then
                    if idx = 0 then
                        dc := shift_right(resize(s_data, 17) + 4, 3);
                        if dc < 0 then
                            m_data <= (others => '0');
                        elsif dc > 255 then
                            m_data <= to_signed(255, 16);
                        else
                            m_data <= resize(dc, 16);
                        end if;
                    else
                        c   := 1 when code = 0 else to_integer(code);
                        a   := unsigned(abs(s_data));
                        den := to_unsigned(4 * W(idx) * c, 14);
                        num := shift_left(resize(a, 22), 5) + resize(den, 22) / 2;     -- 32|F| + D
                        p   := num * to_unsigned(INV(idx, c), 24);
                        q   := resize(p(45 downto 24), 22);
                        if resize(q * den, 36) > resize(num, 36) then
                            q := q - 1;
                        end if;
                        if q > 2047 then
                            r := 2047;
                        else
                            r := to_integer(q);
                        end if;
                        if s_data < 0 then
                            m_data <= to_signed(-r, 16);
                        else
                            m_data <= to_signed(r, 16);
                        end if;
                    end if;
                    idx <= 0 when idx = 63 else idx + 1;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

--==============================================================================
--  Nom        : mire_gen.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : mire animée : image 16 couleurs en mémoire, carré mobile et
--               compteur d'images incrustés, conversion Y, Cb, Cr par palette,
--               sortie en macroblocs 4:2:0 ; référence bit à bit : JPEG2DVB
--               étape 01 (ref/mire.png chargée, option « mobile »)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : sortie : octets dans l'ordre des macroblocs (rangée par rangée),
--               6 blocs par macrobloc (Y haut-gauche, haut-droite, bas-gauche,
--               bas-droite, Cb, Cr), 64 valeurs par bloc ligne par ligne ;
--               m_debut marque le premier octet de chaque image
--  Principe   : image n : carré 32 × 32 en y = 176, x = 8n mod 320 (bord noir de
--               2 pixels, intérieur blanc) ; compteur binaire de n sur 12 carrés
--               8 × 8 en y = 280, x = 8 + 10b (blanc = 1, poids fort à gauche).
--               Toutes les frontières sont paires : la chrominance d'un bloc
--               2 × 2 est celle de son pixel haut-gauche.
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mire_pkg.all;

entity mire_gen is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out unsigned(7 downto 0);
        m_debut : out std_logic
    );
end entity mire_gen;

architecture rtl of mire_gen is
    constant COLS : natural := MIRE_L / 16;
    constant ROWS : natural := MIRE_H / 16;
    signal n       : unsigned(11 downto 0) := (others => '0');   -- rang de l'image
    signal sq_x    : natural range 0 to 319 := 0;                -- abscisse du carré : 8n mod 320
    signal row     : natural range 0 to ROWS - 1 := 0;
    signal col     : natural range 0 to COLS - 1 := 0;
    signal blk     : natural range 0 to 5 := 0;
    signal yy, xx  : natural range 0 to 7 := 0;
    signal o_valid : std_logic := '0';
    signal libre   : std_logic;

    -- couleur du pixel (x, y) de l'image n, incrustations comprises
    function couleur(x, y : natural; img : unsigned(11 downto 0); x0 : natural) return natural is
        variable b  : natural range 0 to 11;
    begin
        if y >= 176 and y < 208 and x >= x0 and x < x0 + 32 then
            if y >= 178 and y < 206 and x >= x0 + 2 and x < x0 + 30 then
                return IDX_BLANC;
            else
                return IDX_NOIR;
            end if;
        end if;
        if y >= 280 and x >= 8 and x < 8 + 10 * 11 + 8 and (x - 8) mod 10 < 8 then
            b := (x - 8) / 10;
            if img(11 - b) = '1' then return IDX_BLANC; else return IDX_NOIR; end if;
        end if;
        return to_integer(MIRE_ROM(y * MIRE_L + x));
    end function;
begin
    libre   <= (not o_valid) or m_ready;
    m_valid <= o_valid;

    process (clk)
        variable px, py : natural range 0 to 511;
        variable c      : natural range 0 to 15;
        variable v      : natural range 0 to 255;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                n <= (others => '0'); sq_x <= 0; row <= 0; col <= 0; blk <= 0; yy <= 0; xx <= 0; o_valid <= '0';
            elsif libre = '1' then
                if blk < 4 then
                    px := col * 16 + (blk mod 2) * 8 + xx;
                    py := row * 16 + (blk / 2) * 8 + yy;
                else
                    px := 2 * (col * 8 + xx);
                    py := 2 * (row * 8 + yy);
                end if;
                c := couleur(px, py, n, sq_x);
                if blk < 4 then v := PALETTE(c)(0); elsif blk = 4 then v := PALETTE(c)(1); else v := PALETTE(c)(2); end if;
                m_data  <= to_unsigned(v, 8);
                m_debut <= '1' when row = 0 and col = 0 and blk = 0 and yy = 0 and xx = 0 else '0';
                o_valid <= '1';
                -- pixel suivant
                if xx < 7 then
                    xx <= xx + 1;
                else
                    xx <= 0;
                    if yy < 7 then
                        yy <= yy + 1;
                    else
                        yy <= 0;
                        if blk < 5 then
                            blk <= blk + 1;
                        else
                            blk <= 0;
                            if col < COLS - 1 then
                                col <= col + 1;
                            else
                                col <= 0;
                                if row < ROWS - 1 then
                                    row <= row + 1;
                                else
                                    row <= 0;
                                    n   <= n + 1;
                                    sq_x <= 0 when sq_x = 312 else sq_x + 8;
                                end if;
                            end if;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

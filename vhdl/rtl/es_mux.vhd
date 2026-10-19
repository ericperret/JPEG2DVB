--==============================================================================
--  Nom        : es_mux.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : assemblage du flux élémentaire MPEG-2 vidéo (images I) : en-têtes
--               de séquence, d'extension, de GOP et d'image, slices, bits VLC
--               des macroblocs ; référence bit à bit : JPEG2DVB étape 06
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.1
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : entrée : mots VLC du codeur (s_code, s_lg, s_fin_mb sur le
--               dernier mot de chaque macrobloc) ; slice_code : code d'échelle
--               de la slice à venir, slice_ok : code prêt (l'en-tête de slice
--               attend) ; sortie : octets du flux élémentaire
--  Principe   : par image : [Sequence Header, Sequence Extension, GOP Header
--               si n mod 12 = 0] + Picture Header (temporal_reference = n mod 12,
--               vbv_delay 0xFFFF) + Picture Coding Extension, puis une slice par
--               rangée : 0x000001, rang + 1, code (5 bits), extra_bit 0, pour chaque
--               macrobloc « 1 » (adresse) « 1 » (intra) et ses bits VLC, alignement.
--               Après G_IMAGES images (0 = sans fin) : sequence_end_code.
--  Historique : 1.0  2026-10-19  création
--               1.1  2026-10-19  slice_ok : attente du code de la régulation TM5
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity es_mux is
    generic (
        G_LARG     : natural := 352;
        G_HAUT     : natural := 288;
        G_BIT_RATE : natural := 23040;        -- unités de 400 bit/s (débit TS)
        G_VBV      : natural := 112;          -- unités de 16 kbit
        G_GOP      : natural := 12;
        G_FPS      : natural := 25;
        G_IMAGES   : natural := 0
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        slice_code : in  unsigned(4 downto 0);
        slice_ok   : in  std_logic;
        s_valid    : in  std_logic;
        s_ready    : out std_logic;
        s_code     : in  std_logic_vector(31 downto 0);
        s_lg       : in  unsigned(5 downto 0);
        s_fin_mb   : in  std_logic;
        m_valid    : out std_logic;
        m_ready    : in  std_logic;
        m_data     : out std_logic_vector(7 downto 0)
    );
end entity es_mux;

architecture rtl of es_mux is
    constant COLS : natural := G_LARG / 16;
    constant ROWS : natural := G_HAUT / 16;

    function slv(v, n : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(v, n));
    end function;

    type etat_t is (EN_TETE, SLICE1, SLICE2, MB_ENTETE, MB_DONNEES, SLICE_FIN, FIN_SEQ, ARRET);
    signal etat  : etat_t := EN_TETE;
    signal i     : natural range 0 to 12 := 0;
    signal image : natural range 0 to 2 ** 30 := 0;
    -- time_code du GOP : images, secondes, minutes, heures de l'image courante
    signal tc_im : natural range 0 to 63 := 0;
    signal tc_se, tc_mi : natural range 0 to 59 := 0;
    signal tc_h  : natural range 0 to 23 := 0;
    signal tr    : natural range 0 to 1023 := 0;          -- temporal_reference
    signal rang  : natural range 0 to 255 := 0;
    signal col   : natural range 0 to 255 := 0;

    signal p_valid, p_ready, p_align : std_logic;
    signal p_code : std_logic_vector(31 downto 0);
    signal p_lg   : unsigned(5 downto 0);
    signal w_code  : std_logic_vector(31 downto 0);
    signal w_lg    : natural range 0 to 32;
    signal w_align : std_logic;
begin
    packer : entity work.bit_packer
        port map (clk, rst, p_valid, p_ready, p_code, p_lg, p_align, m_valid, m_ready, m_data);

    -- mot présenté au packer selon l'état ; en-têtes de l'image : mots 0 à 7
    -- (séquence et GOP, au début de chaque GOP), 8 à 12 (image)
    process (all)
    begin
        w_code <= (others => '0'); w_lg <= 0; w_align <= '0';
        case etat is
            when EN_TETE =>
                case i is
                    when 0  => w_code <= x"000001B3"; w_lg <= 32;
                    when 1  => w_code <= slv(G_LARG, 12) & slv(G_HAUT, 12) & "0010" & "0011"; w_lg <= 32;       -- 4:3, 25 im/s
                    when 2  => w_code <= slv(G_BIT_RATE, 18) & '1' & slv(G_VBV, 10) & "000"; w_lg <= 32;        -- marqueur, VBV, matrices par défaut
                    when 3  => w_code <= x"000001B5"; w_lg <= 32;
                    when 4  => w_code <= "0001" & x"48" & '1' & "01" & "00" & "00" & x"000" & '1'; w_lg <= 32;    -- Main@Main, progressif, 4:2:0
                    when 5  => w_lg <= 16;                                                                      -- vbv ext, low_delay, frame_rate ext
                    when 6  => w_code <= x"000001B8"; w_lg <= 32;
                    when 7  => w_code(26 downto 0) <= '0' & slv(tc_h, 5) & slv(tc_mi, 6) & '1' & slv(tc_se, 6) & slv(tc_im, 6) & '1' & '0';
                               w_lg <= 27; w_align <= '1';                                                      -- GOP fermé
                    when 8  => w_code <= x"00000100"; w_lg <= 32;
                    when 9  => w_code(29 downto 0) <= slv(tr, 10) & "001" & x"FFFF" & '0'; w_lg <= 30; w_align <= '1';   -- image I
                    when 10 => w_code <= x"000001B5"; w_lg <= 32;
                    when 11 => w_code <= "1000" & x"FFFF" & "00" & "11" & "01000001"; w_lg <= 32;               -- f_code, dc 8 bits, trame, frame_pred_frame_dct, chroma_420_type
                    when others => w_code(1 downto 0) <= "10"; w_lg <= 2; w_align <= '1';                       -- progressive_frame, composite 0
                end case;
            when SLICE1    => w_code <= x"000001" & slv(rang + 1, 8); w_lg <= 32;
            when SLICE2    => w_code(5 downto 0) <= std_logic_vector(slice_code) & '0'; w_lg <= 6;
            when MB_ENTETE => w_code(1 downto 0) <= "11"; w_lg <= 2;
            when SLICE_FIN => w_align <= '1';
            when FIN_SEQ   => w_code <= x"000001B7"; w_lg <= 32;
            when others    => null;
        end case;
    end process;
    p_valid <= s_valid when etat = MB_DONNEES else '0' when etat = ARRET else slice_ok when etat = SLICE2 else '1';
    p_code  <= s_code when etat = MB_DONNEES else w_code;
    p_lg    <= s_lg when etat = MB_DONNEES else to_unsigned(w_lg, 6);
    p_align <= '0' when etat = MB_DONNEES else w_align;
    s_ready <= p_ready when etat = MB_DONNEES else '0';

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                etat <= EN_TETE; i <= 0; image <= 0; rang <= 0; col <= 0;
                tc_im <= 0; tc_se <= 0; tc_mi <= 0; tc_h <= 0; tr <= 0;
            elsif etat = ARRET then
                null;
            elsif etat = MB_DONNEES then
                if s_valid = '1' and p_ready = '1' and s_fin_mb = '1' then
                    if col = COLS - 1 then
                        col  <= 0;
                        etat <= SLICE_FIN;
                    else
                        col  <= col + 1;
                        etat <= MB_ENTETE;
                    end if;
                end if;
            elsif p_ready = '1' and (etat /= SLICE2 or slice_ok = '1') then
                case etat is
                    when EN_TETE =>
                        if i = 12 then
                            etat <= SLICE1;
                            rang <= 0;
                        else
                            i <= i + 1;
                        end if;
                    when SLICE1    => etat <= SLICE2;
                    when SLICE2    => etat <= MB_ENTETE;
                    when MB_ENTETE => etat <= MB_DONNEES;
                    when SLICE_FIN =>
                        if rang = ROWS - 1 then
                            if G_IMAGES /= 0 and image = G_IMAGES - 1 then
                                etat <= FIN_SEQ;
                            else
                                image <= image + 1;
                                -- temporal_reference : rang dans le GOP
                                if tr = G_GOP - 1 then tr <= 0; i <= 0; else tr <= tr + 1; i <= 8; end if;
                                -- time_code de l'image suivante
                                if tc_im = G_FPS - 1 then
                                    tc_im <= 0;
                                    if tc_se = 59 then
                                        tc_se <= 0;
                                        if tc_mi = 59 then
                                            tc_mi <= 0;
                                            tc_h  <= 0 when tc_h = 23 else tc_h + 1;
                                        else
                                            tc_mi <= tc_mi + 1;
                                        end if;
                                    else
                                        tc_se <= tc_se + 1;
                                    end if;
                                else
                                    tc_im <= tc_im + 1;
                                end if;
                                etat  <= EN_TETE;
                            end if;
                        else
                            rang <= rang + 1;
                            etat <= SLICE1;
                        end if;
                    when FIN_SEQ => etat <= ARRET;
                    when others  => null;
                end case;
            end if;
        end if;
    end process;
end architecture rtl;

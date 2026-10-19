--==============================================================================
--  Nom        : video_enc.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : tête de chaîne vidéo : mire animée → DCT entière → régulation
--               TM5 → quantification → zigzag → VLC → flux élémentaire → PES et
--               Transport Stream à débit constant ; référence bit à bit :
--               JPEG2DVB étapes 01 à 08 (mire ref/mire.png, DCT entière,
--               régulation TM5 de l'étape 03 3.0)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.1
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : sortie : paquets TS de
--               188 octets (m_sop sur la synchro), à prélever au rythme du
--               canal (un paquet par créneau de 13 056 cycles à 80 MHz)
--  Paramètres : G_IMAGES : nombre d'images avant sequence_end_code (0 = sans fin)
--               G_T : budget en bits par image (350 196 : 10 MS/s, FEC 1/2,
--               95 % de vidéo, 25 images/s)
--  Historique : 1.0  2026-10-19  création
--               1.1  2026-10-19  régulation TM5 (rate_ctrl) : un code par rangée
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity video_enc is
    generic (
        G_IMAGES : natural := 0;
        G_T      : natural := 350196
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out std_logic_vector(7 downto 0);
        m_sop   : out std_logic
    );
end entity video_enc;

architecture rtl of video_enc is
    signal p_valid, p_ready, p_debut : std_logic;
    signal p_data                    : unsigned(7 downto 0);
    signal d_valid, d_ready          : std_logic;
    signal d_data                    : signed(15 downto 0);
    signal g_valid, g_ready          : std_logic;
    signal g_data                    : signed(15 downto 0);
    signal code                      : unsigned(4 downto 0);
    signal code_ok                   : std_logic;
    signal q_valid, q_ready          : std_logic;
    signal q_data                    : signed(15 downto 0);
    signal z_valid, z_ready          : std_logic;
    signal z_data                    : signed(15 downto 0);
    signal v_valid, v_ready, v_fin   : std_logic;
    signal v_code                    : std_logic_vector(31 downto 0);
    signal v_lg                      : unsigned(5 downto 0);
    signal e_valid, e_ready          : std_logic;
    signal e_data                    : std_logic_vector(7 downto 0);
begin
    u_mire : entity work.mire_gen
        port map (clk, rst, p_valid, p_ready, p_data, p_debut);
    u_dct : entity work.dct8x8_int
        port map (clk, rst, p_valid, p_ready, p_data, d_valid, d_ready, d_data);
    u_rc : entity work.rate_ctrl generic map (G_T => G_T)
        port map (clk, rst, d_valid, d_ready, d_data, g_valid, g_ready, g_data, v_valid, v_ready, v_lg, v_fin, code, code_ok);
    u_quant : entity work.quant_intra
        port map (clk, rst, code, g_valid, g_ready, g_data, q_valid, q_ready, q_data);
    u_zz : entity work.zigzag
        port map (clk, rst, q_valid, q_ready, q_data, z_valid, z_ready, z_data);
    u_vlc : entity work.vlc_enc
        port map (clk, rst, z_valid, z_ready, z_data, v_valid, v_ready, v_code, v_lg, v_fin);
    u_es : entity work.es_mux generic map (G_IMAGES => G_IMAGES)
        port map (clk, rst, code, code_ok, v_valid, v_ready, v_code, v_lg, v_fin, e_valid, e_ready, e_data);
    u_ts : entity work.ts_mux
        port map (clk, rst, e_valid, e_ready, e_data, m_valid, m_ready, m_data, m_sop);
end architecture rtl;

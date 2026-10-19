--==============================================================================
--  Nom        : dvbs_tx.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : émetteur complet, de la mire animée aux échantillons I/Q mis
--               en forme : video_enc (étapes 01 à 08) → tx_backend (étapes
--               09 à 14) ; référence bit à bit : fichier .cs16 de JPEG2DVB
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.1
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : horloge 80 MHz (8 × 10 MS/s) ; sortie : I, Q signés 16 bits, un échantillon par cycle, vers
--               l'interpolateur et le sigma-delta (à venir)
--  Principe   : le filtre SRRC impose le rythme ; le contrôle de flux remonte
--               jusqu'au multiplexeur TS, qui émet ainsi un paquet par créneau
--               de 13 056 cycles, comme dans le modèle temporel de JPEG2DVB
--  Historique : 1.0  2026-10-19  création
--               1.1  2026-10-19  régulation TM5 : budget tiré du canal (10 MS/s,
--                                FEC, 95 % de vidéo), plus d'entrée code
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dvbs_pkg.all;

entity dvbs_tx is
    generic (
        G_IMAGES : natural := 0;
        G_FEC    : natural range 0 to 4 := 0
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_i     : out signed(15 downto 0);
        m_q     : out signed(15 downto 0)
    );
end entity dvbs_tx;

architecture rtl of dvbs_tx is
    signal t_valid, t_ready, t_sop : std_logic;
    signal t_data                  : std_logic_vector(7 downto 0);
begin
    u_video : entity work.video_enc generic map (G_IMAGES => G_IMAGES, G_T => budget_image(10_000_000, G_FEC, 95, 25))
        port map (clk, rst, t_valid, t_ready, t_data, t_sop);
    u_canal : entity work.tx_backend generic map (G_FEC => G_FEC)
        port map (clk, rst, t_valid, t_ready, t_data, t_sop, m_valid, m_ready, m_i, m_q);
end architecture rtl;
